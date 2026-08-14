package collector

import (
	"context"
	"database/sql"
	"net/url"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/events"
	"github.com/focusguard/focusguard/backend/internal/policies"
	"github.com/focusguard/focusguard/backend/pkg/logger"
)

type ActivityCollector struct {
	db              *sql.DB
	evaluator       *policies.Evaluator
	wsHub           *events.Hub
	userID          uuid.UUID
	deviceID        uuid.UUID
	interval        time.Duration
	stopChan        chan struct{}
	mu              sync.Mutex
	isRunning       bool
	lastTarget      string
	lastSampleTime  time.Time
}

func NewActivityCollector(db *sql.DB, evaluator *policies.Evaluator, wsHub *events.Hub, userID, deviceID uuid.UUID) *ActivityCollector {
	return &ActivityCollector{
		db:        db,
		evaluator: evaluator,
		wsHub:     wsHub,
		userID:    userID,
		deviceID:  deviceID,
		interval:  3 * time.Second,
		stopChan:  make(chan struct{}),
	}
}

func (c *ActivityCollector) SetUserAndDevice(userID, deviceID uuid.UUID) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.userID = userID
	c.deviceID = deviceID
}

func (c *ActivityCollector) Start() {
	c.mu.Lock()
	if c.isRunning {
		c.mu.Unlock()
		return
	}
	c.isRunning = true
	c.lastSampleTime = time.Now()
	c.mu.Unlock()

	logger.Info("Starting Real macOS Activity Collector daemon", "platform", runtime.GOOS, "interval", c.interval)
	go c.runLoop()
}

func (c *ActivityCollector) Stop() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.isRunning {
		return
	}
	c.isRunning = false
	close(c.stopChan)
	logger.Info("Stopped macOS Activity Collector daemon")
}

func (c *ActivityCollector) runLoop() {
	ticker := time.NewTicker(c.interval)
	defer ticker.Stop()

	for {
		select {
		case <-c.stopChan:
			return
		case now := <-ticker.C:
			c.sampleAndRecord(now)
		}
	}
}

func (c *ActivityCollector) sampleAndRecord(now time.Time) {
	if runtime.GOOS != "darwin" {
		return // macOS specific activity sampling
	}

	target := c.detectActiveTarget()
	if target == "" {
		c.mu.Lock()
		c.lastSampleTime = now
		c.mu.Unlock()
		return
	}

	c.mu.Lock()
	elapsed := int(now.Sub(c.lastSampleTime).Seconds())
	if elapsed <= 0 {
		elapsed = int(c.interval.Seconds())
	}
	if elapsed > 15 {
		elapsed = int(c.interval.Seconds()) // Cap in case of sleep/wake
	}
	c.lastSampleTime = now
	c.lastTarget = target
	userID := c.userID
	deviceID := c.deviceID
	c.mu.Unlock()

	if userID == uuid.Nil {
		return
	}

	todayStr := now.UTC().Format("2006-01-02")

	// Record in database
	if c.db != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		upsertQ := `INSERT INTO usage_aggregates (id, user_id, device_id, target_value, date, total_duration_seconds, updated_at)
		            VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP)
		            ON CONFLICT (user_id, device_id, target_value, date)
		            DO UPDATE SET total_duration_seconds = usage_aggregates.total_duration_seconds + EXCLUDED.total_duration_seconds,
		                           updated_at = CURRENT_TIMESTAMP`
		recordID := uuid.New().String()
		_, err := c.db.ExecContext(ctx, upsertQ, recordID, userID.String(), deviceID.String(), target, todayStr, elapsed)
		if err != nil {
			logger.Error("Collector error updating aggregate", "error", err)
		}

		// Evaluate policies for this target
		var currentTotal int
		queryTotal := `SELECT SUM(total_duration_seconds) FROM usage_aggregates WHERE user_id = $1 AND date = $2 AND target_value = $3`
		_ = c.db.QueryRowContext(ctx, queryTotal, userID.String(), todayStr, target).Scan(&currentTotal)

		policyQ := `SELECT p.id, p.name, p.limit_seconds, p.enforcement_mode, p.is_enabled, pt.target_type, pt.target_value
		            FROM policies p
		            JOIN policy_targets pt ON p.id = pt.policy_id
		            WHERE p.user_id = $1 AND p.is_enabled = 1`
		prows, err := c.db.QueryContext(ctx, policyQ, userID.String())
		if err == nil {
			defer prows.Close()
			for prows.Next() {
				var p policies.Policy
				var pt policies.PolicyTarget
				var isEnabledInt int
				if err := prows.Scan(&p.ID, &p.Name, &p.LimitSeconds, &p.EnforcementMode, &isEnabledInt, &pt.TargetType, &pt.TargetValue); err == nil {
					p.IsEnabled = (isEnabledInt == 1)
					if c.evaluator.IsTargetMatched(pt, target) && c.evaluator.IsLimitExceeded(p, currentTotal) {
						// Limit reached! Broadcast event
						if c.wsHub != nil {
							c.wsHub.BroadcastToUser(userID, events.EventMessage{
								Event: "LIMIT_REACHED",
								Payload: map[string]interface{}{
									"policyId":     p.ID,
									"targetValue":  target,
									"currentUsage": currentTotal,
									"limitSeconds": p.LimitSeconds,
									"policyName":   p.Name,
								},
							})
						}
					}
				}
			}
		}

		// Broadcast real-time usage tick to active web/clients
		if c.wsHub != nil {
			c.wsHub.BroadcastToUser(userID, events.EventMessage{
				Event: "USAGE_TICK",
				Payload: map[string]interface{}{
					"targetValue":     target,
					"durationSeconds": elapsed,
					"currentTotal":    currentTotal,
					"timestamp":       now.Unix(),
				},
			})
		}
	}
}

func (c *ActivityCollector) detectActiveTarget() string {
	// 1. Get frontmost app name
	cmdApp := exec.Command("osascript", "-e", `tell application "System Events" to get name of first application process whose frontmost is true`)
	outApp, err := cmdApp.Output()
	if err != nil {
		return ""
	}
	appName := strings.TrimSpace(string(outApp))

	// 2. If it's a browser, extract active tab URL domain
	if appName == "Google Chrome" || appName == "Chromium" || appName == "Brave Browser" {
		script := `tell application "` + appName + `" to get URL of active tab of front window`
		cmdURL := exec.Command("osascript", "-e", script)
		outURL, err := cmdURL.Output()
		if err == nil {
			rawURL := strings.TrimSpace(string(outURL))
			if parsed, err := url.Parse(rawURL); err == nil && parsed.Host != "" {
				host := strings.ToLower(parsed.Host)
				host = strings.TrimPrefix(host, "www.")
				return host
			}
		}
	} else if appName == "Safari" {
		script := `tell application "Safari" to get URL of front document`
		cmdURL := exec.Command("osascript", "-e", script)
		outURL, err := cmdURL.Output()
		if err == nil {
			rawURL := strings.TrimSpace(string(outURL))
			if parsed, err := url.Parse(rawURL); err == nil && parsed.Host != "" {
				host := strings.ToLower(parsed.Host)
				host = strings.TrimPrefix(host, "www.")
				return host
			}
		}
	}

	return appName
}
