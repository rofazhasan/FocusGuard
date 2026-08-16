#!/bin/bash
# FocusGuard Master Test Suite Runner
# Runs the full verification battery across all platforms, shared packages, backend services, and E2E slices.

set -e

echo "================================================================================"
echo "           FOCUSGUARD COMPREHENSIVE MASTER TEST BATTERY EXECUTION               "
echo "================================================================================"

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE_DIR"

TOTAL_SUITES=7
PASSED_SUITES=0

echo -e "\n[1/$TOTAL_SUITES] Running Shared Domain Packages Test Suite (JavaScript)..."
node packages/test_all_packages.js
PASSED_SUITES=$((PASSED_SUITES + 1))

echo -e "\n[2/$TOTAL_SUITES] Running Browser Extension Unit Tests..."
node apps/extension/tests/test_extension.js
PASSED_SUITES=$((PASSED_SUITES + 1))

echo -e "\n[3/$TOTAL_SUITES] Running Milestone 1: Browser Extension E2E Vertical Slice..."
node tests/e2e/vertical_slice_test.js
PASSED_SUITES=$((PASSED_SUITES + 1))

echo -e "\n[4/$TOTAL_SUITES] Running Milestone 4: macOS Native Agent Test Suite (Swift) & Proof A..."
swift tests/mac_agent_test.swift
swift apps/macos/FocusGuard/ProofA/ProofAMacOSEnforcement.swift
PASSED_SUITES=$((PASSED_SUITES + 1))

echo -e "\n[5/$TOTAL_SUITES] Running Milestone 5: Cross-Device Multi-Node Budget Reconciliation E2E..."
node tests/e2e/cross_device_shared_budget_test.js
PASSED_SUITES=$((PASSED_SUITES + 1))

echo -e "\n[6/$TOTAL_SUITES] Running Milestone 6: Android Usage & VpnService DNS Sinkhole (Proof B)..."
go run apps/android/proof/proof_b_android_enforcement.go
PASSED_SUITES=$((PASSED_SUITES + 1))

echo -e "\n[7/$TOTAL_SUITES] Running Go Cloud Backend Package Tests..."
(cd backend && go test ./...)
PASSED_SUITES=$((PASSED_SUITES + 1))

echo -e "\n================================================================================"
echo "  ✅ ALL $PASSED_SUITES / $TOTAL_SUITES FOCUSGUARD TEST SUITES PASSED SUCCESSFULLY (100%)"
echo "================================================================================"
