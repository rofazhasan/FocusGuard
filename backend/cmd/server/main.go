package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
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

	go wsHub.Run()

	analyticsHandler := analytics.NewHandler(db)
	authHandler := auth.NewHandler(db, tokenService)
	devicesHandler := devices.NewHandler(db)
	policiesHandler := policies.NewHandler(db, wsHub)
	usageHandler := usage.NewHandler(db, policyEvaluator, wsHub)
	focusHandler := focus.NewHandler(db, wsHub)
	enrollmentHandler := enrollment.NewHandler(db, tokenService, wsHub)
	commandsHandler := commands.NewHandler(db, wsHub)
	auditHandler := audit.NewHandler(db)
	protectionHandler := health.NewProtectionHandler(db, wsHub)

	// Ensure default primary owner exists for instant zero-friction usability
	defaultUserID := uuid.MustParse("00000000-0000-0000-0000-000000000001")
	defaultDeviceID := uuid.MustParse("00000000-0000-0000-0000-000000000002")
	managedDeviceID := uuid.MustParse("00000000-0000-0000-0000-000000000004")
	if db != nil {
		pwHash, _ := auth.HashPassword("focusguard123")
		_, _ = db.Exec(`INSERT INTO users (id, email, password_hash, created_at, updated_at)
		                VALUES ($1, 'demo@focusguard.local', $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		                ON CONFLICT (id) DO NOTHING`, defaultUserID.String(), pwHash)

		// Owner Mac
		_, _ = db.Exec(`INSERT INTO devices (id, user_id, device_name, platform, os_version, role, is_managed, status, last_seen_at, created_at)
		                VALUES ($1, $2, 'MacBook Pro 16"', 'MACOS', 'macOS 15.0', 'OWNER', 0, 'ONLINE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		                ON CONFLICT (id) DO NOTHING`, defaultDeviceID.String(), defaultUserID.String())

		// Managed Student Tablet
		_, _ = db.Exec(`INSERT INTO devices (id, user_id, device_name, platform, os_version, role, is_managed, status, last_seen_at, created_at)
		                VALUES ($1, $2, 'Student Pixel Tablet', 'ANDROID', 'Android 15 (API 35)', 'MANAGED_USER', 1, 'ONLINE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		                ON CONFLICT (id) DO NOTHING`, managedDeviceID.String(), defaultUserID.String())

		// Default initial policy: YouTube 30m limit
		defaultPolicyID := uuid.MustParse("00000000-0000-0000-0000-000000000003")
		_, _ = db.Exec(`INSERT INTO policies (id, user_id, name, limit_seconds, period, timezone, enforcement_mode, is_enabled, version, created_at, updated_at)
		                VALUES ($1, $2, 'YouTube Daily Budget', 1800, 'DAILY', 'UTC', 'BLOCK', 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		                ON CONFLICT (id) DO NOTHING`, defaultPolicyID.String(), defaultUserID.String())

		_, _ = db.Exec(`INSERT INTO policy_targets (id, policy_id, target_type, target_value, created_at)
		                VALUES ($1, $2, 'WEBSITE', 'youtube.com', CURRENT_TIMESTAMP)
		                ON CONFLICT (id) DO NOTHING`, uuid.New().String(), defaultPolicyID.String())
	}

	// Real macOS Background Activity Collector
	activityCollector := collector.NewActivityCollector(db, policyEvaluator, wsHub, defaultUserID, defaultDeviceID)
	activityCollector.Start()
	defer activityCollector.Stop()

	// HTTP Router (Chi)
	r := chi.NewRouter()

	r.Use(chiMiddleware.Logger)
	r.Use(chiMiddleware.Recoverer)
	r.Use(chiMiddleware.Timeout(30 * time.Second))

	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link", "X-Server-Timestamp"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	// Public Routes
	r.Get("/health", health.Handler)
	r.Post("/api/v1/auth/register", authHandler.Register)
	r.Post("/api/v1/auth/login", authHandler.Login)
	r.Post("/api/v1/enrollment/claim", enrollmentHandler.ClaimEnrollment)

	// Real-Time WebSocket Endpoint
	r.Get("/ws", func(w http.ResponseWriter, r *http.Request) {
		wsHub.ServeWS(tokenService, w, r)
	})

	// Protected Routes (JWT Auth)
	r.Group(func(r chi.Router) {
		r.Use(middleware.AuthMiddleware(tokenService))

		r.Post("/api/v1/devices/register", devicesHandler.RegisterDevice)
		r.Get("/api/v1/devices", devicesHandler.ListDevices)

		r.Post("/api/v1/enrollment/create", enrollmentHandler.CreateEnrollment)
		r.Get("/api/v1/enrollment/pending", enrollmentHandler.ListPendingEnrollments)

		r.Post("/api/v1/policies", policiesHandler.CreatePolicy)
		r.Get("/api/v1/policies", policiesHandler.ListPolicies)
		r.Delete("/api/v1/policies/{id}", policiesHandler.DeletePolicy)
		r.Post("/api/v1/policies/simulate", policiesHandler.SimulatePolicy)
		r.Post("/api/v1/policies/explain", policiesHandler.ExplainPolicy)

		r.Post("/api/v1/commands/dispatch", commandsHandler.DispatchCommand)
		r.Get("/api/v1/audit/logs", auditHandler.GetAuditLogs)

		r.Post("/api/v1/usage/sync", usageHandler.SyncUsage)

		r.Get("/api/v1/analytics/daily", analyticsHandler.GetDailyAnalytics)
		r.Get("/api/v1/analytics/weekly", analyticsHandler.GetWeeklyAnalytics)
		r.Get("/api/v1/analytics/timeline", analyticsHandler.GetTimeline)

		r.Get("/api/v1/health/fleet", protectionHandler.GetFleetHealth)
		r.Post("/api/v1/health/tamper", protectionHandler.ReportTamperEvent)

		r.Post("/api/v1/focus/start", focusHandler.StartFocus)
		r.Post("/api/v1/focus/end", focusHandler.EndFocus)
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
