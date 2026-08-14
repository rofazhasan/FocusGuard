# FocusGuard — Production Makefile & Task Automation

.PHONY: all build test run clean docker-up docker-down seed doctor help

SHELL := /bin/bash

# Default target
all: build test

help:
	@echo "======================================================================="
	@echo "  FOCUSGUARD — Cross-Platform Attention Enforcement Platform"
	@echo "======================================================================="
	@echo "  make doctor         - Diagnose local development environment"
	@echo "  make build          - Build Go backend and extension package"
	@echo "  make test           - Run all test suites (Backend, Extension, Proofs)"
	@echo "  make test-backend   - Run Go backend unit and route tests"
	@echo "  make test-extension - Run WebExtension DNR and PSL test suite"
	@echo "  make test-proofs    - Run macOS & Android native proof pipelines"
	@echo "  make start          - Start full stack locally (Backend :8080, Web :3001)"
	@echo "  make stop           - Stop all local FocusGuard services"
	@echo "  make docker-up      - Launch production stack via Docker Compose"
	@echo "  make docker-down    - Tear down Docker Compose containers"
	@echo "  make package-ext    - Package Chrome/Firefox WebExtension zip bundle"
	@echo "  make clean          - Clean temporary binaries, logs, and artifacts"
	@echo "======================================================================="

# Environment Diagnosis
doctor:
	@chmod +x scripts/doctor.sh 2>/dev/null || true
	@./scripts/doctor.sh

# Build
build:
	@echo "==> Building FocusGuard Go Backend..."
	@cd backend && go build -o bin/server cmd/server/main.go
	@echo "✓ Backend built successfully: backend/bin/server"

# Full Test Matrix
test: test-backend test-extension test-proofs
	@echo "========================================================"
	@echo "🏆 ALL FOCUSGUARD TEST SUITES PASSED CLEANLY (100%)"
	@echo "========================================================"

test-backend:
	@echo "==> Running Go Backend Tests (13 packages)..."
	@cd backend && go test -v ./...

test-extension:
	@echo "==> Running WebExtensions DNR & PSL Tests..."
	@node apps/extension/tests/test_extension.js

test-proofs:
	@echo "==> Running macOS Screen Time Proof (Proof A)..."
	@swift apps/macos/FocusGuard/ProofA/ProofAMacOSEnforcement.swift
	@echo "==> Running Android VpnService DNS Sinkhole Proof (Proof B)..."
	@go run apps/android/proof/proof_b_android_enforcement.go

# Start / Stop Local Services
start:
	@chmod +x scripts/start-all.sh scripts/stop-all.sh 2>/dev/null || true
	@./scripts/start-all.sh

stop:
	@chmod +x scripts/stop-all.sh 2>/dev/null || true
	@./scripts/stop-all.sh

# Docker Commands
docker-up:
	@echo "==> Launching FocusGuard Production Stack..."
	@docker compose up --build -d
	@echo "✓ Stack is up! Web Dashboard: http://localhost:3001 | API: http://localhost:8080"

docker-down:
	@echo "==> Stopping FocusGuard Docker Stack..."
	@docker compose down

# WebExtension Packaging
package-ext:
	@chmod +x scripts/package-extension.sh 2>/dev/null || true
	@./scripts/package-extension.sh

# Cleanup
clean:
	@rm -rf backend/bin dist/ backend/*.log .pids
	@echo "✓ Cleaned build artifacts."
