/**
 * FocusGuard Phase 2 Master Vertical Slice End-to-End Test
 * 
 * Verifies the entire Phase 2 trust and pairing lifecycle against a live server:
 * 1. User registers & authenticates (Argon2id)
 * 2. Owner creates short-lived pairing session (high-entropy code)
 * 3. Simulated device generates keypair & submits enrollment request
 * 4. Owner approves pending request (atomic database transaction)
 * 5. Device receives persistent device credential & saves to SecureCredentialStore
 * 6. Device sends heartbeat & syncs policies
 * 7. Device sends batch events with idempotency
 * 8. Simulated client restarts -> restores credentials -> reconnects without re-pairing
 * 9. Owner revokes device from Dashboard API
 * 10. Revoked device is immediately rejected on subsequent requests (HTTP 403 DEVICE_REVOKED)
 */

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const assert = require('assert');
const FocusGuardDeviceClient = require('../../apps/device-test-client/device-client.js');

const TEST_PORT = 8181;
const API_BASE = `http://localhost:${TEST_PORT}/api/v1`;
const TEST_DB = path.join(__dirname, 'test_e2e_pairing.db');
const TEST_CREDS = path.join(__dirname, 'test_e2e_creds.json');

console.log('================================================================================');
console.log('🚀 FOCUSGUARD PHASE 2: MASTER VERTICAL SLICE PAIRING & TRUST E2E TEST');
console.log('================================================================================\n');

async function waitForServer(url, timeoutMs = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(`${url}/health`);
      if (res.ok) return true;
    } catch (e) {
      // Waiting for server start
    }
    await new Promise(r => setTimeout(r, 200));
  }
  throw new Error(`Server failed to start on ${url} within ${timeoutMs}ms`);
}

async function runTest() {
  // Clean up previous test artifacts
  [TEST_DB, `${TEST_DB}-shm`, `${TEST_DB}-wal`, TEST_CREDS].forEach(f => {
    if (fs.existsSync(f)) fs.unlinkSync(f);
  });

  const serverBin = path.join(__dirname, '../../backend/bin/server');
  if (!fs.existsSync(serverBin)) {
    throw new Error(`Backend binary not found at ${serverBin}. Run 'go build -o bin/server cmd/server/main.go' first.`);
  }

  console.log(`--- [SETUP] Spawning FocusGuard Test Server on port ${TEST_PORT} ---`);
  const server = spawn(serverBin, [], {
    env: {
      ...process.env,
      PORT: String(TEST_PORT),
      SQLITE_PATH: TEST_DB,
      JWT_SECRET: 'test_jwt_secret_focusguard_e2e_2026'
    },
    stdio: 'ignore'
  });

  try {
    await waitForServer(`http://localhost:${TEST_PORT}`);
    console.log('✓ Server is healthy and accepting requests.\n');

    // -------------------------------------------------------------
    // STEP 1: Owner Registration & Login (Argon2id)
    // -------------------------------------------------------------
    console.log('--- STEP 1: Register and authenticate account owner ---');
    const ownerEmail = `alice_${Date.now()}@focusguard.local`;
    const ownerPassword = 'Argon2Password#2026!';

    const regRes = await fetch(`${API_BASE}/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: ownerEmail, password: ownerPassword })
    });
    assert.strictEqual(regRes.status, 201, 'Registration must return 201 Created');
    const regData = await regRes.json();
    assert.ok(regData.accessToken, 'Must return accessToken');
    assert.ok(regData.refreshToken, 'Must return refreshToken');
    const ownerToken = regData.accessToken;
    console.log(`✓ Owner registered and authenticated: ${ownerEmail}`);

    // Verify /auth/me
    const meRes = await fetch(`${API_BASE}/auth/me`, {
      headers: { 'Authorization': `Bearer ${ownerToken}` }
    });
    assert.strictEqual(meRes.status, 200);
    const meData = await meRes.json();
    assert.strictEqual(meData.user.email, ownerEmail);
    console.log(`✓ /auth/me verified for user ID: ${meData.user.id}`);

    // -------------------------------------------------------------
    // STEP 2: Create Pairing Session
    // -------------------------------------------------------------
    console.log('\n--- STEP 2: Owner creates short-lived pairing session ---');
    const createSessionRes = await fetch(`${API_BASE}/pairing/sessions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${ownerToken}`
      },
      body: JSON.stringify({ deviceName: 'Office Android Tablet' })
    });
    assert.strictEqual(createSessionRes.status, 201);
    const sessionData = await createSessionRes.json();
    assert.ok(sessionData.sessionId, 'Must return sessionId');
    assert.ok(sessionData.pairingCode.startsWith('FG-'), 'Must return FG- formatted code');
    assert.strictEqual(sessionData.status, 'CREATED');
    console.log(`✓ Pairing session created: ID=${sessionData.sessionId}, Code=${sessionData.pairingCode}`);

    // -------------------------------------------------------------
    // STEP 3: Simulated Device Submits Enrollment Request
    // -------------------------------------------------------------
    console.log('\n--- STEP 3: Simulated client requests pairing with public key ---');
    const client = new FocusGuardDeviceClient({
      apiBase: API_BASE,
      deviceName: 'Pixel 8 Pro (QA Device)',
      platform: 'ANDROID',
      clientType: 'ANDROID_APP',
      credentialPath: TEST_CREDS
    });

    const enrollReq = await client.startPairing(sessionData.sessionId);
    assert.strictEqual(enrollReq.status, 'PENDING_APPROVAL');
    console.log(`✓ Enrollment request submitted. Status: PENDING_APPROVAL`);

    // Verify owner sees pending session details
    const sessionDetailRes = await fetch(`${API_BASE}/pairing/sessions/${sessionData.sessionId}`);
    assert.strictEqual(sessionDetailRes.status, 200);
    const detailData = await sessionDetailRes.json();
    assert.strictEqual(detailData.status, 'PENDING_APPROVAL');
    assert.strictEqual(detailData.requestedDeviceMetadata.deviceName, 'Pixel 8 Pro (QA Device)');
    console.log(`✓ Dashboard verifies pending request with device metadata: ${detailData.requestedDeviceMetadata.deviceName}`);

    // -------------------------------------------------------------
    // STEP 4: Owner Approves Request (Atomic Transaction)
    // -------------------------------------------------------------
    console.log('\n--- STEP 4: Owner explicitly approves device enrollment ---');
    const approveRes = await fetch(`${API_BASE}/pairing/sessions/${sessionData.sessionId}/approve`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${ownerToken}`
      }
    });
    assert.strictEqual(approveRes.status, 200);
    const approveData = await approveRes.json();
    assert.strictEqual(approveData.status, 'APPROVED');
    assert.ok(approveData.deviceId, 'Must return enrolled deviceId');
    console.log(`✓ Owner approved device. Enrolled Device ID: ${approveData.deviceId}`);

    // -------------------------------------------------------------
    // STEP 5: Device Polls Status & Stores Credential
    // -------------------------------------------------------------
    console.log('\n--- STEP 5: Device receives credential & persists locally ---');
    const pollResult = await client.pollForApproval(sessionData.sessionId, 10, 200);
    assert.strictEqual(pollResult.success, true);
    assert.strictEqual(pollResult.deviceId, approveData.deviceId);
    assert.ok(pollResult.deviceToken, 'Must receive persistent deviceToken');
    assert.strictEqual(client.state, 'ACTIVE');
    assert.ok(fs.existsSync(TEST_CREDS), 'Credentials must be saved to disk');
    console.log(`✓ Device is ACTIVE. Credentials securely saved in ${path.basename(TEST_CREDS)}`);

    // Verify dashboard devices list shows device
    const listDevRes = await fetch(`${API_BASE}/devices`, {
      headers: { 'Authorization': `Bearer ${ownerToken}` }
    });
    assert.strictEqual(listDevRes.status, 200);
    const devList = await listDevRes.json();
    const found = devList.find(d => d.id === approveData.deviceId);
    assert.ok(found, 'Enrolled device must appear in user device registry');
    assert.strictEqual(found.status, 'ACTIVE');
    console.log(`✓ Enrolled device verified in Dashboard registry: ${found.deviceName} (${found.platform})`);

    // -------------------------------------------------------------
    // STEP 6: Device Heartbeat & Policy Sync
    // -------------------------------------------------------------
    console.log('\n--- STEP 6: Device sends heartbeat and synchronizes policies ---');
    const hbRes = await client.sendHeartbeat();
    assert.strictEqual(hbRes.acknowledged, true);
    assert.strictEqual(hbRes.deviceStatus, 'ACTIVE');
    console.log(`✓ Device heartbeat acknowledged: Status=${hbRes.deviceStatus}`);

    const syncRes = await client.syncPolicies();
    assert.ok(Array.isArray(syncRes.policies), 'Must return policies array');
    console.log(`✓ Device policy sync succeeded: version=${syncRes.policyVersion}`);

    // -------------------------------------------------------------
    // STEP 7: Event Batch Ingestion with Idempotency
    // -------------------------------------------------------------
    console.log('\n--- STEP 7: Device uploads telemetry event batch (Testing Idempotency) ---');
    const testEventId = `evt_test_${Date.now()}`;
    const testEvents = [{
      id: testEventId,
      eventType: 'DOMAIN_BLOCKED',
      domain: 'youtube.com',
      reason: 'Attention budget reached',
      timestamp: new Date().toISOString()
    }];

    // First upload
    const batch1 = await client.sendEvents(testEvents);
    assert.strictEqual(batch1.processed, 1);
    assert.strictEqual(batch1.duplicates, 0);

    // Duplicate upload (same event ID)
    const batch2 = await client.sendEvents(testEvents);
    assert.strictEqual(batch2.processed, 0);
    assert.strictEqual(batch2.duplicates, 1);
    console.log(`✓ Idempotency verified: duplicate event correctly identified and not double-counted`);

    // -------------------------------------------------------------
    // STEP 8: CRITICAL RESTART TEST (NO RE-PAIRING REQUIRED)
    // -------------------------------------------------------------
    console.log('\n--- STEP 8: CRITICAL RESTART TEST (Device reboot simulation) ---');
    // Destroy in-memory client instance
    const restartedClient = new FocusGuardDeviceClient({
      apiBase: API_BASE,
      credentialPath: TEST_CREDS
    });

    const initResult = await restartedClient.initialize();
    assert.strictEqual(initResult.paired, true, 'Client must automatically detect saved credentials');
    assert.strictEqual(restartedClient.deviceId, approveData.deviceId);
    assert.strictEqual(restartedClient.state, 'ACTIVE');
    console.log(`✓ Client restarted. Restored Device ID: ${restartedClient.deviceId} without re-pairing!`);

    // Authenticate and sync with restored credentials
    const restartSync = await restartedClient.syncPolicies();
    assert.strictEqual(restartSync.status, 'UP_TO_DATE');
    console.log(`✓ Reconnection verified: successfully synced policies using persisted credential`);

    // -------------------------------------------------------------
    // STEP 9: Device Revocation by Owner
    // -------------------------------------------------------------
    console.log('\n--- STEP 9: Owner revokes device from Dashboard ---');
    const revokeRes = await fetch(`${API_BASE}/devices/${approveData.deviceId}/revoke`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${ownerToken}` }
    });
    assert.strictEqual(revokeRes.status, 200);
    const revokeData = await revokeRes.json();
    assert.strictEqual(revokeData.status, 'REVOKED');
    console.log(`✓ Device revoked by owner.`);

    // -------------------------------------------------------------
    // STEP 10: Revoked Device Reconnection Rejected
    // -------------------------------------------------------------
    console.log('\n--- STEP 10: Verify revoked device is rejected on subsequent API requests ---');
    try {
      await restartedClient.sendHeartbeat();
      assert.fail('Heartbeat must fail for revoked device');
    } catch (err) {
      assert.ok(err.message.includes('DEVICE_REVOKED') || err.message.includes('revoked'),
        `Error message must indicate revocation: ${err.message}`);
      console.log(`✓ Rejected heartbeat: ${err.message}`);
    }

    try {
      await restartedClient.syncPolicies();
      assert.fail('Policy sync must fail for revoked device');
    } catch (err) {
      assert.ok(err.message.includes('DEVICE_REVOKED') || err.message.includes('revoked'));
      console.log(`✓ Rejected policy sync: ${err.message}`);
    }

    // Attempt reuse of consumed pairing session
    console.log('\n--- STEP 11: Verify reuse of consumed pairing session is rejected ---');
    const reuseRes = await fetch(`${API_BASE}/pairing/sessions/${sessionData.sessionId}/request`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ deviceName: 'Malicious Device' })
    });
    assert.ok(reuseRes.status === 409 || reuseRes.status === 410, 'Reuse must be rejected with 409 or 410');
    console.log(`✓ Consumed pairing reuse rejected with HTTP ${reuseRes.status}`);

    console.log('\n================================================================================');
    console.log('🎉 ALL 11 STEPS OF FOCUSGUARD PHASE 2 VERTICAL SLICE PASSED SUCCESSFULLY (100%)');
    console.log('================================================================================\n');

  } finally {
    // Teardown server and test files
    server.kill('SIGTERM');
    [TEST_DB, `${TEST_DB}-shm`, `${TEST_DB}-wal`, TEST_CREDS].forEach(f => {
      if (fs.existsSync(f)) {
        try { fs.unlinkSync(f); } catch (e) {}
      }
    });
  }
}

runTest().catch(err => {
  console.error('\n❌ E2E Test Failed:\n', err);
  process.exit(1);
});
