package collector

import (
	"context"
	"database/sql"
	"fmt"
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
	db                   *sql.DB
	evaluator            *policies.Evaluator
	wsHub                *events.Hub
	userID               uuid.UUID
	deviceID             uuid.UUID
	interval             time.Duration
	stopChan             chan struct{}
	mu                   sync.Mutex
	isRunning            bool
	lastTarget           string
	lastSampleTime       time.Time
	gracePeriodStartedAt time.Time
	activeBrowserName    string
	browserGraceActive   bool
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

	logger.Info("Starting Real macOS Activity Collector daemon with Extension Watchdog", "platform", runtime.GOOS, "interval", c.interval)
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

	appName := c.detectFrontmostApp()
	target := c.detectActiveTarget(appName)

	c.mu.Lock()
	userID := c.userID
	deviceID := c.deviceID
	c.mu.Unlock()

	if userID == uuid.Nil {
		return
	}

	// 1. Anti-Tamper Watchdog: Check if extension is installed when browser is running
	if appName != "" {
		c.checkExtensionWatchdog(appName, now, userID)
	}

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

func (c *ActivityCollector) detectFrontmostApp() string {
	cmdApp := exec.Command("osascript", "-e", `tell application "System Events" to get name of first application process whose frontmost is true`)
	outApp, err := cmdApp.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(outApp))
}

func (c *ActivityCollector) checkExtensionWatchdog(appName string, now time.Time, userID uuid.UUID) {
	isBrowser := appName == "Google Chrome" || appName == "Chromium" || appName == "Brave Browser" || appName == "Microsoft Edge" || appName == "Arc"
	if !isBrowser {
		return
	}

	c.mu.Lock()
	c.activeBrowserName = appName
	c.mu.Unlock()

	// Check if extension is active (heartbeat within 25 seconds)
	isExtActive := false
	if c.wsHub != nil {
		isExtActive = c.wsHub.IsExtensionActive(userID, 25*time.Second)
	}

	if isExtActive {
		// Extension is active & healthy
		c.mu.Lock()
		wasInGrace := c.browserGraceActive
		c.browserGraceActive = false
		c.gracePeriodStartedAt = time.Time{}
		c.mu.Unlock()

		if wasInGrace && c.wsHub != nil {
			c.wsHub.BroadcastToUser(userID, events.EventMessage{
				Event: "EXTENSION_RESTORED",
				Payload: map[string]interface{}{
					"status":  "HEALTHY",
					"message": "FocusGuard extension heartbeat verified. Normal browsing resumed.",
				},
			})
			if c.db != nil {
				_, _ = c.db.Exec(`INSERT INTO audit_logs (id, user_id, action, details, timestamp)
				                  VALUES ($1, $2, 'EXTENSION_RESTORED', 'FocusGuard Extension heartbeat verified. Normal browsing resumed.', CURRENT_TIMESTAMP)`,
					uuid.New().String(), userID.String())
			}
		}
		return
	}

	// Extension is missing / deleted while browser is running
	c.mu.Lock()
	if !c.browserGraceActive {
		c.browserGraceActive = true
		c.gracePeriodStartedAt = now
		if c.db != nil {
			_, _ = c.db.Exec(`INSERT INTO audit_logs (id, user_id, action, details, timestamp)
			                  VALUES ($1, $2, 'EXTENSION_MISSING_WARNING', $3, CURRENT_TIMESTAMP)`,
				uuid.New().String(), userID.String(), fmt.Sprintf("FocusGuard Extension missing while %s is active. 60-second grace period initiated.", appName))
		}
	}
	graceStart := c.gracePeriodStartedAt
	c.mu.Unlock()

	elapsedGrace := int(now.Sub(graceStart).Seconds())
	remainingSec := 60 - elapsedGrace

	if remainingSec > 0 {
		// Broadcast countdown tick (60s -> 0s)
		if c.wsHub != nil {
			c.wsHub.BroadcastToUser(userID, events.EventMessage{
				Event: "EXTENSION_GRACE_TICK",
				Payload: map[string]interface{}{
					"browserName":      appName,
					"remainingSeconds": remainingSec,
					"warning":          fmt.Sprintf("FocusGuard Extension is missing! You have %d seconds to install or enable the extension before %s is force-closed.", remainingSec, appName),
				},
			})
		}
	} else {
		// 1 minute expired without extension! Force terminate the browser!
		logger.Warn("Extension 60s grace period expired! Force-closing browser", "appName", appName)
		c.forceTerminateBrowser(appName)

		c.mu.Lock()
		c.browserGraceActive = false
		c.gracePeriodStartedAt = time.Time{}
		c.mu.Unlock()

		if c.wsHub != nil {
			c.wsHub.BroadcastToUser(userID, events.EventMessage{
				Event: "BROWSER_TERMINATED",
				Payload: map[string]interface{}{
					"browserName": appName,
					"reason":      "FocusGuard Extension was deleted or disabled. 60-second grace period expired.",
				},
			})
		}

		if c.db != nil {
			_, _ = c.db.Exec(`INSERT INTO audit_logs (id, user_id, action, details, timestamp)
			                  VALUES ($1, $2, 'BROWSER_FORCE_TERMINATED', $3, CURRENT_TIMESTAMP)`,
				uuid.New().String(), userID.String(), fmt.Sprintf("%s was force-closed because FocusGuard Extension was not installed within 1 minute.", appName))
		}
	}
}

func (c *ActivityCollector) forceTerminateBrowser(appName string) {
	if runtime.GOOS == "darwin" {
		script := fmt.Sprintf(`tell application "%s" to quit`, appName)
		_ = exec.Command("osascript", "-e", script).Run()
	}
}

func (c *ActivityCollector) detectActiveTarget(appName string) string {
	if appName == "" {
		appName = c.detectFrontmostApp()
		if appName == "" {
			return ""
		}
	}

	// If it's a browser, extract active tab URL domain
	if appName == "Google Chrome" || appName == "Chromium" || appName == "Brave Browser" || appName == "Microsoft Edge" {
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
