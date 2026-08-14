package database

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "github.com/lib/pq"
	_ "modernc.org/sqlite"
	"github.com/focusguard/focusguard/backend/pkg/logger"
)

type Config struct {
	Host     string
	Port     string
	User     string
	Password string
	DBName   string
	SSLMode  string
}

func Connect(cfg *Config) (*sql.DB, error) {
	if cfg != nil && cfg.Host != "" && cfg.User != "" {
		if cfg.SSLMode == "" {
			cfg.SSLMode = "disable"
		}
		dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
			cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.DBName, cfg.SSLMode)

		db, err := sql.Open("postgres", dsn)
		if err != nil {
			return nil, fmt.Errorf("failed to open postgres connection: %w", err)
		}
		db.SetMaxOpenConns(25)
		db.SetMaxIdleConns(5)
		db.SetConnMaxLifetime(15 * time.Minute)

		if err := db.Ping(); err != nil {
			logger.Error("PostgreSQL ping failed, falling back to embedded SQLite", "error", err)
		} else {
			logger.Info("Successfully connected to PostgreSQL database")
			if err := initPostgresSchema(db); err != nil {
				logger.Error("Failed to init postgres schema", "error", err)
			}
			return db, nil
		}
	}

	// Default: Pure Go Embedded SQLite Database
	dbPath := os.Getenv("SQLITE_PATH")
	if dbPath == "" {
		cwd, _ := os.Getwd()
		dbPath = filepath.Join(cwd, "focusguard.db")
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open sqlite database: %w", err)
	}

	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)

	_, _ = db.Exec("PRAGMA journal_mode=WAL;")
	_, _ = db.Exec("PRAGMA busy_timeout=5000;")

	if err := initSQLiteSchema(db); err != nil {
		return nil, fmt.Errorf("failed to initialize sqlite schema: %w", err)
	}

	logger.Info("FocusGuard persistent SQLite database initialized successfully", "path", dbPath)
	return db, nil
}

func initSQLiteSchema(db *sql.DB) error {
	schema := `
	CREATE TABLE IF NOT EXISTS users (
		id TEXT PRIMARY KEY,
		email TEXT UNIQUE NOT NULL,
		password_hash TEXT NOT NULL,
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS devices (
		id TEXT PRIMARY KEY,
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		device_name TEXT NOT NULL,
		platform TEXT NOT NULL,
		os_version TEXT NOT NULL,
		role TEXT NOT NULL DEFAULT 'PERSONAL',
		is_managed INTEGER NOT NULL DEFAULT 0,
		status TEXT NOT NULL DEFAULT 'ONLINE',
		policy_version INTEGER NOT NULL DEFAULT 1,
		last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS enrollment_tokens (
		id TEXT PRIMARY KEY,
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		pairing_code TEXT UNIQUE NOT NULL,
		device_name TEXT NOT NULL,
		target_role TEXT NOT NULL DEFAULT 'MANAGED_USER',
		expires_at DATETIME NOT NULL,
		is_claimed INTEGER NOT NULL DEFAULT 0,
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS policies (
		id TEXT PRIMARY KEY,
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		name TEXT NOT NULL,
		limit_seconds INTEGER NOT NULL DEFAULT 0,
		period TEXT NOT NULL DEFAULT 'DAILY',
		schedule_cron TEXT,
		timezone TEXT NOT NULL DEFAULT 'UTC',
		enforcement_mode TEXT NOT NULL DEFAULT 'BLOCK',
		is_enabled INTEGER NOT NULL DEFAULT 1,
		version INTEGER NOT NULL DEFAULT 1,
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS policy_targets (
		id TEXT PRIMARY KEY,
		policy_id TEXT NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
		target_type TEXT NOT NULL,
		target_value TEXT NOT NULL,
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS policy_assignments (
		policy_id TEXT NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
		device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
		PRIMARY KEY (policy_id, device_id)
	);

	CREATE TABLE IF NOT EXISTS usage_aggregates (
		id TEXT PRIMARY KEY,
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
		target_value TEXT NOT NULL,
		date TEXT NOT NULL,
		total_duration_seconds INTEGER NOT NULL DEFAULT 0,
		updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		UNIQUE(user_id, device_id, target_value, date)
	);

	CREATE TABLE IF NOT EXISTS blocked_events (
		id TEXT PRIMARY KEY,
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
		policy_id TEXT NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
		target_value TEXT NOT NULL,
		timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS focus_sessions (
		id TEXT PRIMARY KEY,
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		duration_minutes INTEGER NOT NULL,
		is_completed INTEGER NOT NULL DEFAULT 0,
		started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		ended_at DATETIME
	);

	CREATE TABLE IF NOT EXISTS remote_commands (
		id TEXT PRIMARY KEY,
		device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
		issued_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		command_type TEXT NOT NULL,
		payload TEXT NOT NULL,
		issued_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		expires_at DATETIME NOT NULL,
		status TEXT NOT NULL DEFAULT 'PENDING'
	);

	CREATE TABLE IF NOT EXISTS audit_logs (
		id TEXT PRIMARY KEY,
		user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		device_id TEXT,
		action TEXT NOT NULL,
		details TEXT,
		timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);
	`
	_, err := db.Exec(schema)
	if err != nil {
		return err
	}

	// Automated column migrations for existing SQLite databases
	_, _ = db.Exec("ALTER TABLE devices ADD COLUMN role TEXT NOT NULL DEFAULT 'PERSONAL';")
	_, _ = db.Exec("ALTER TABLE devices ADD COLUMN is_managed INTEGER NOT NULL DEFAULT 0;")
	_, _ = db.Exec("ALTER TABLE devices ADD COLUMN policy_version INTEGER NOT NULL DEFAULT 1;")
	return nil
}

func initPostgresSchema(db *sql.DB) error {
	schema := `
	CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

	CREATE TABLE IF NOT EXISTS users (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		email VARCHAR(255) UNIQUE NOT NULL,
		password_hash VARCHAR(255) NOT NULL,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);

	CREATE TABLE IF NOT EXISTS devices (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		device_name VARCHAR(100) NOT NULL,
		platform VARCHAR(20) NOT NULL,
		os_version VARCHAR(50) NOT NULL,
		role VARCHAR(20) NOT NULL DEFAULT 'PERSONAL',
		is_managed BOOLEAN NOT NULL DEFAULT FALSE,
		status VARCHAR(20) NOT NULL DEFAULT 'ONLINE',
		policy_version INT NOT NULL DEFAULT 1,
		last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);

	CREATE TABLE IF NOT EXISTS enrollment_tokens (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		pairing_code VARCHAR(10) UNIQUE NOT NULL,
		device_name VARCHAR(100) NOT NULL,
		target_role VARCHAR(20) NOT NULL DEFAULT 'MANAGED_USER',
		expires_at TIMESTAMPTZ NOT NULL,
		is_claimed BOOLEAN NOT NULL DEFAULT FALSE,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);

	CREATE TABLE IF NOT EXISTS policies (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		name VARCHAR(100) NOT NULL,
		limit_seconds INT NOT NULL DEFAULT 0,
		period VARCHAR(20) NOT NULL DEFAULT 'DAILY',
		schedule_cron VARCHAR(100),
		timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',
		enforcement_mode VARCHAR(30) NOT NULL DEFAULT 'BLOCK',
		is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
		version INT NOT NULL DEFAULT 1,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);

	CREATE TABLE IF NOT EXISTS policy_targets (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		policy_id UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
		target_type VARCHAR(20) NOT NULL,
		target_value VARCHAR(255) NOT NULL,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);

	CREATE TABLE IF NOT EXISTS policy_assignments (
		policy_id UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
		device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
		PRIMARY KEY (policy_id, device_id)
	);

	CREATE TABLE IF NOT EXISTS usage_aggregates (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
		target_value VARCHAR(255) NOT NULL,
		date DATE NOT NULL,
		total_duration_seconds INT NOT NULL DEFAULT 0,
		updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		UNIQUE(user_id, device_id, target_value, date)
	);

	CREATE TABLE IF NOT EXISTS blocked_events (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
		policy_id UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
		target_value VARCHAR(255) NOT NULL,
		timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);

	CREATE TABLE IF NOT EXISTS focus_sessions (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		duration_minutes INT NOT NULL,
		is_completed BOOLEAN NOT NULL DEFAULT FALSE,
		started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		ended_at TIMESTAMPTZ
	);

	CREATE TABLE IF NOT EXISTS remote_commands (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
		issued_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		command_type VARCHAR(50) NOT NULL,
		payload TEXT NOT NULL,
		issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
		expires_at TIMESTAMPTZ NOT NULL,
		status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
	);

	CREATE TABLE IF NOT EXISTS audit_logs (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
		action VARCHAR(100) NOT NULL,
		details TEXT,
		timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
	);
	`
	_, err := db.Exec(schema)
	return err
}
