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

	"github.com/focusguard/focusguard/backend/internal/auth"
	"github.com/focusguard/focusguard/backend/internal/devices"
	"github.com/focusguard/focusguard/backend/internal/events"
	"github.com/focusguard/focusguard/backend/internal/health"
	"github.com/focusguard/focusguard/backend/internal/middleware"
	"github.com/focusguard/focusguard/backend/internal/policies"
	"github.com/focusguard/focusguard/backend/internal/usage"
	"github.com/focusguard/focusguard/backend/pkg/database"
	"github.com/focusguard/focusguard/backend/pkg/logger"
)

func main() {
	logger.Info("Starting FocusGuard Backend Server...")

	// Environment configuration
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		jwtSecret = "focusguard_super_secret_jwt_key_2026"
	}

	// Database setup (Optional gracefully handled if DB credentials not present in test mode)
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
		logger.Error("Proceeding without active database connection", "reason", err.Error())
	} else if db != nil {
		defer db.Close()
	}

	// Domain Services & Handlers
	tokenService := auth.NewTokenService(jwtSecret)
	policyEvaluator := policies.NewEvaluator()
	wsHub := events.NewHub()

	go wsHub.Run()

	authHandler := auth.NewHandler(db, tokenService)
	devicesHandler := devices.NewHandler(db)
	policiesHandler := policies.NewHandler(db)
	usageHandler := usage.NewHandler(db, policyEvaluator, wsHub)

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

	// Real-Time WebSocket Endpoint
	r.Get("/ws", func(w http.ResponseWriter, r *http.Request) {
		wsHub.ServeWS(tokenService, w, r)
	})

	// Protected Routes (JWT Auth)
	r.Group(func(r chi.Router) {
		r.Use(middleware.AuthMiddleware(tokenService))

		r.Post("/api/v1/devices/register", devicesHandler.RegisterDevice)
		r.Get("/api/v1/devices", devicesHandler.ListDevices)

		r.Post("/api/v1/policies", policiesHandler.CreatePolicy)
		r.Get("/api/v1/policies", policiesHandler.ListPolicies)
		r.Delete("/api/v1/policies/{id}", policiesHandler.DeletePolicy)

		r.Post("/api/v1/usage/sync", usageHandler.SyncUsage)
	})

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		logger.Info("FocusGuard Server running", "port", port)
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
