package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chiMiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/google/uuid"

	"github.com/focusguard/focusguard/backend/internal/analytics"
	"github.com/focusguard/focusguard/backend/internal/audit"
	"github.com/focusguard/focusguard/backend/internal/auth"
	"github.com/focusguard/focusguard/backend/internal/collector"
	"github.com/focusguard/focusguard/backend/internal/commands"
	"github.com/focusguard/focusguard/backend/internal/devices"
	"github.com/focusguard/focusguard/backend/internal/enrollment"
	"github.com/focusguard/focusguard/backend/internal/events"
	"github.com/focusguard/focusguard/backend/internal/focus"
	"github.com/focusguard/focusguard/backend/internal/health"
	"github.com/focusguard/focusguard/backend/internal/middleware"
	"github.com/focusguard/focusguard/backend/internal/pairing"
	"github.com/focusguard/focusguard/backend/internal/policies"
	"github.com/focusguard/focusguard/backend/internal/usage"
	"github.com/focusguard/focusguard/backend/pkg/database"
	"github.com/focusguard/focusguard/backend/pkg/logger"
)

func main() {
	logger.Info("Starting FocusGuard Multi-Device Production Server...")

	// Environment configuration
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		jwtSecret = "focusguard_super_secret_jwt_key_2026"
	}

	// Database setup (Auto SQLite fallback if Postgres is absent)
	dbHost := os.Getenv("DB_HOST")
	dbPort := os.Getenv("DB_PORT")
	dbUser := os.Getenv("DB_USER")
	dbPassword := os.Getenv("DB_PASSWORD")
	dbName := os.Getenv("DB_NAME")

	var dbConn *database.Config
	if dbHost != "" && dbUser != "" {
		dbConn = &database.Config{
			Host:     dbHost,
			Port:     dbPort,
			User:     dbUser,
			Password: dbPassword,
			DBName:   dbName,
		}
	}

	db, err := database.Connect(dbConn)
	if err != nil {
		logger.Error("Database connection warning", "error", err.Error())
	} else if db != nil {
		defer db.Close()
	}

	// Domain Services & Handlers
	tokenService := auth.NewTokenService(jwtSecret)
	policyEvaluator := policies.NewEvaluator()
	wsHub := events.NewHub()
	if db != nil {
		wsHub.SetDB(db)
	}

	go wsHub.Run()

	analyticsHandler := analytics.NewHandler(db)
	authHandler := auth.NewHandler(db, tokenService)
	devicesHandler := devices.NewHandler(db, wsHub)
	pairingHandler := pairing.NewHandler(db, tokenService, wsHub)
	policiesHandler := policies.NewHandler(db, wsHub)
	usageHandler := usage.NewHandler(db, policyEvaluator, wsHub)
	focusHandler := focus.NewHandler(db, wsHub)
	enrollmentHandler := enrollment.NewHandler(db, tokenService, wsHub)
	commandsHandler := commands.NewHandler(db, wsHub)
	auditHandler := audit.NewHandler(db)
	protectionHandler := health.NewProtectionHandler(db, wsHub)
	batchEventsHandler := events.NewBatchHandler(db, wsHub)

	// Ensure default primary owner exists for instant zero-friction usability
	defaultUserID := uuid.MustParse("00000000-0000-0000-0000-000000000001")
	defaultDeviceID := uuid.MustParse("00000000-0000-0000-0000-000000000002")
	if db != nil {
		pwHash, _ := auth.HashPassword("focusguard123")
		_, _ = db.Exec(`INSERT INTO users (id, email, password_hash, created_at, updated_at)
		                VALUES ($1, 'demo@focusguard.local', $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		                ON CONFLICT (id) DO NOTHING`, defaultUserID.String(), pwHash)

		// Real Local Host Device
		hostName, err := os.Hostname()
		if err != nil || hostName == "" {
			hostName = "MacBook Pro"
		}
		platform := "MACOS"
		if runtime.GOOS == "windows" {
			platform = "WINDOWS"
		} else if runtime.GOOS == "linux" {
			platform = "LINUX"
		}

		osVer := fmt.Sprintf("%s (%s)", runtime.GOOS, runtime.GOARCH)

		_, _ = db.Exec(`INSERT INTO devices (id, user_id, device_name, platform, client_type, os_version, app_version, role, is_managed, status, protection_state, policy_version, last_seen_at, created_at)
		                VALUES ($1, $2, $3, $4, 'MACOS_AGENT', $5, '1.0.0', 'OWNER', 0, 'ACTIVE', 'PROTECTED', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		                ON CONFLICT (id) DO NOTHING`, defaultDeviceID.String(), defaultUserID.String(), hostName, platform, osVer)

		extDeviceID := "5028eea4-8da8-431a-91c7-d637a6837f9f"
		_, _ = db.Exec(`INSERT INTO devices (id, user_id, device_name, platform, client_type, os_version, app_version, role, is_managed, status, protection_state, policy_version, last_seen_at, created_at)
		                VALUES ($1, $2, 'Google Chrome Extension', 'WEB_EXTENSION', 'EXTENSION', $3, '1.0.0', 'MANAGED', 1, 'ACTIVE', 'PROTECTED', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		                ON CONFLICT (id) DO NOTHING`, extDeviceID, defaultUserID.String(), osVer)

		// Seed Initial Production Attention Policies
		var polCount int
		_ = db.QueryRow(`SELECT COUNT(*) FROM policies WHERE user_id = $1`, defaultUserID.String()).Scan(&polCount)
		if polCount == 0 {
			pol1ID := "00000000-0000-0000-0000-000000000010"
			_, _ = db.Exec(`INSERT INTO policies (id, user_id, name, limit_seconds, period, timezone, enforcement_mode, is_enabled, version, created_at, updated_at)
			                VALUES ($1, $2, 'Social & Video Attention Budget', 1800, 'DAILY', 'UTC', 'BLOCK', 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
				pol1ID, defaultUserID.String())

			targets1 := []string{"youtube.com", "instagram.com", "reddit.com", "tiktok.com", "facebook.com", "x.com"}
			for _, t := range targets1 {
				_, _ = db.Exec(`INSERT INTO policy_targets (id, policy_id, target_type, target_value)
				                VALUES ($1, $2, 'WEBSITE', $3)`, uuid.New().String(), pol1ID, t)
			}

			pol2ID := "00000000-0000-0000-0000-000000000020"
			_, _ = db.Exec(`INSERT INTO policies (id, user_id, name, limit_seconds, period, timezone, enforcement_mode, is_enabled, version, created_at, updated_at)
			                VALUES ($1, $2, 'Gaming & Distraction Cap', 1200, 'DAILY', 'UTC', 'BLOCK', 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
				pol2ID, defaultUserID.String())

			targets2 := []string{"twitch.tv", "discord.com", "steampowered.com", "roblox.com"}
			for _, t := range targets2 {
				_, _ = db.Exec(`INSERT INTO policy_targets (id, policy_id, target_type, target_value)
				                VALUES ($1, $2, 'WEBSITE', $3)`, uuid.New().String(), pol2ID, t)
			}
		}
	}

	// Real macOS Background Activity Collector
	activityCollector := collector.NewActivityCollector(db, policyEvaluator, wsHub, defaultUserID, defaultDeviceID)
	activityCollector.Start()
	defer activityCollector.Stop()

	// Rate Limiters
	authLimiter := middleware.NewRateLimiter(20, time.Minute)
	pairingLimiter := middleware.NewRateLimiter(30, time.Minute)

	// HTTP Router (Chi)
	r := chi.NewRouter()

	r.Use(middleware.RequestIDMiddleware)
	r.Use(chiMiddleware.Logger)
	r.Use(chiMiddleware.Recoverer)
	r.Use(chiMiddleware.Timeout(30 * time.Second))

	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token", "X-Request-ID", "If-None-Match"},
		ExposedHeaders:   []string{"Link", "X-Server-Timestamp", "X-Request-ID", "X-Policy-Version", "ETag"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	// Public Health & Readiness
	r.Get("/health", health.Handler)
	r.Get("/ready", func(w http.ResponseWriter, r *http.Request) {
		if db != nil {
			if pingErr := db.Ping(); pingErr != nil {
				w.WriteHeader(http.StatusServiceUnavailable)
				_, _ = w.Write([]byte(`{"status":"DOWN","reason":"Database unreachable"}`))
				return
			}
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"READY","database":"UP"}`))
	})

	// Public Auth Routes (with Rate Limiting)
	r.Group(func(publicAuth chi.Router) {
		publicAuth.Use(authLimiter)
		publicAuth.Post("/api/v1/auth/register", authHandler.Register)
		publicAuth.Post("/api/v1/auth/login", authHandler.Login)
	})
	r.Post("/api/v1/auth/refresh", authHandler.Refresh)
	r.Post("/api/v1/auth/logout", authHandler.Logout)

	// Public Pairing Client Routes (Device initiated enrollment request & status polling)
	r.Group(func(pairRouter chi.Router) {
		pairRouter.Use(pairingLimiter)
		pairRouter.Post("/api/v1/pairing/sessions/{id}/request", pairingHandler.SubmitRequest)
		pairRouter.Post("/api/v1/pairing/request", pairingHandler.SubmitRequest)
	})
	r.Get("/api/v1/pairing/sessions/{id}", pairingHandler.GetSession)
	r.Get("/api/v1/pairing/sessions/{id}/status", pairingHandler.PollStatus)

	// Legacy Enrollment Bridge (Phase 1 client compatibility)
	r.Post("/api/v1/enrollment/claim", enrollmentHandler.ClaimEnrollment)

	// Real-Time WebSocket Endpoint (with token verification & device revocation checking)
	r.Get("/ws", func(w http.ResponseWriter, r *http.Request) {
		wsHub.ServeWS(tokenService, db, w, r)
	})

	// Protected Routes (JWT User Auth - Owner operations)
	r.Group(func(r chi.Router) {
		r.Use(middleware.AuthMiddleware(tokenService))

		// User profile
		r.Get("/api/v1/auth/me", authHandler.Me)

		// Device Management (Owner)
		r.Post("/api/v1/devices/register", devicesHandler.RegisterDevice)
		r.Get("/api/v1/devices", devicesHandler.ListDevices)
		r.Post("/api/v1/devices/{id}/revoke", devicesHandler.RevokeDevice)

		// Pairing Management (Owner)
		r.Post("/api/v1/pairing/sessions", pairingHandler.CreateSession)
		r.Post("/api/v1/pairing/sessions/{id}/approve", pairingHandler.ApproveRequest)
		r.Post("/api/v1/pairing/sessions/{id}/reject", pairingHandler.RejectRequest)
		r.Post("/api/v1/pairing/sessions/{id}/cancel", pairingHandler.CancelSession)

		// Legacy Enrollment (Owner)
		r.Post("/api/v1/enrollment/create", enrollmentHandler.CreateEnrollment)
		r.Get("/api/v1/enrollment/pending", enrollmentHandler.ListPendingEnrollments)

		// Policies (Owner)
		r.Post("/api/v1/policies", policiesHandler.CreatePolicy)
		r.Get("/api/v1/policies", policiesHandler.ListPolicies)
		r.Delete("/api/v1/policies/{id}", policiesHandler.DeletePolicy)
		r.Post("/api/v1/policies/{id}/toggle", policiesHandler.TogglePolicy)
		r.Post("/api/v1/policies/simulate", policiesHandler.SimulatePolicy)
		r.Post("/api/v1/policies/explain", policiesHandler.ExplainPolicy)

		// Commands & Audit
		r.Post("/api/v1/commands/dispatch", commandsHandler.DispatchCommand)
		r.Get("/api/v1/audit/logs", auditHandler.GetAuditLogs)

		// Fleet Health & Diagnostics
		r.Get("/api/v1/health/fleet", protectionHandler.GetFleetHealth)
		r.Post("/api/v1/health/tamper", protectionHandler.ReportTamperEvent)
		r.Post("/api/v1/health/diagnostics", protectionHandler.RunDiagnostics)

		// Analytics
		r.Get("/api/v1/analytics/daily", analyticsHandler.GetDailyAnalytics)
		r.Get("/api/v1/analytics/weekly", analyticsHandler.GetWeeklyAnalytics)
		r.Get("/api/v1/analytics/timeline", analyticsHandler.GetTimeline)
		r.Get("/api/v1/analytics/enforcement-timeline", analyticsHandler.GetEnforcementTimeline)
		r.Get("/api/v1/analytics/recommendations", analyticsHandler.GetRecommendations)
		r.Post("/api/v1/analytics/interval-union", analyticsHandler.CalculateIntervalUnionEndpoint)

		// Focus Sessions
		r.Post("/api/v1/focus/start", focusHandler.StartFocus)
		r.Post("/api/v1/focus/end", focusHandler.EndFocus)
		r.Get("/api/v1/focus/active", focusHandler.GetActiveFocus)
		r.Get("/api/v1/focus/presets", focusHandler.GetFocusPresets)
	})

	// Device or User Authenticated Endpoints (Sync, Heartbeat, Events, Commands)
	r.Group(func(r chi.Router) {
		r.Use(middleware.DeviceOrUserAuthMiddleware(db, tokenService))

		r.Post("/api/v1/devices/{id}/heartbeat", devicesHandler.Heartbeat)
		r.Get("/api/v1/device/policies/sync", policiesHandler.SyncDevicePolicies)
		r.Post("/api/v1/usage/sync", usageHandler.SyncUsage)
		r.Post("/api/v1/events/batch", batchEventsHandler.HandleBatchEvents)
		r.Post("/api/v1/commands/{id}/ack", commandsHandler.AcknowledgeCommand)
		r.Get("/api/v1/commands/pending", commandsHandler.GetPendingCommands)
	})

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		logger.Info("FocusGuard Multi-Device Server running", "port", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("Server error", "error", err)
		}
	}()

	// Graceful Shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("Shutting down FocusGuard Server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		logger.Error("Server forced shutdown", "error", err)
	}

	logger.Info("FocusGuard Server exited cleanly.")
}
