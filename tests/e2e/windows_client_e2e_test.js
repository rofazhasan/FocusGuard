/**
 * FocusGuard Phase 3: Windows Native Client End-to-End Integration Test
 * 
 * Verifies the full Windows Agent integration lifecycle with the Go Cloud Backend:
 * 1. Owner registers and authenticates.
 * 2. Owner creates pairing session with pairing code and session UUID.
 * 3. Windows Client generates Ed25519 identity keypair and submits enrollment request (platform: WINDOWS, clientType: WINDOWS_AGENT).
 * 4. Owner approves pending pairing session in atomic transaction.
 * 5. Windows Client polls status, receives persistent deviceToken, and verifies device registration.
 * 6. Owner dashboard lists Windows device: "Windows — Gaming PC".
 * 7. Windows Client sends heartbeat telemetry.
 * 8. Owner creates app policy for discord.exe (30m limit).
 * 9. Windows Client syncs policies and receives assigned policy.
 * 10. Windows Client ingests usage deltas and batch events (USAGE_SESSION_STARTED, LIMIT_REACHED, ENFORCEMENT_TRIGGERED).
 * 11. Cold reboot simulation: client reloads credentials, connects without re-pairing.
 * 12. Remote device revocation: Owner revokes device -> client receives HTTP 403 DEVICE_REVOKED -> authenticated access permanently halted.
 */

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const assert = require('assert');
const crypto = require('crypto');

const TEST_PORT = 8383;
const API_BASE = `http://localhost:${TEST_PORT}/api/v1`;
const TEST_DB = path.join(__dirname, 'test_windows_e2e.db');

console.log('================================================================================');
console.log('🚀 FOCUSGUARD PHASE 3: WINDOWS NATIVE CLIENT END-TO-END VERIFICATION');
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
  // Clean previous artifacts
  [TEST_DB, `${TEST_DB}-shm`, `${TEST_DB}-wal`].forEach(f => {
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
      JWT_SECRET: 'test_jwt_secret_focusguard_win32_2026'
    },
    stdio: 'inherit'
  });

  try {
    await waitForServer(`http://localhost:${TEST_PORT}`);
    console.log('✓ Server is healthy and accepting requests.\n');

    // STEP 1: Owner Registration & Login
    console.log('--- STEP 1: Register and authenticate account owner ---');
    const ownerEmail = `win_admin_${Date.now()}@focusguard.local`;
    const ownerPassword = 'WindowsSecurePassword#2026!';

    const regRes = await fetch(`${API_BASE}/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: ownerEmail, password: ownerPassword })
    });
    assert.strictEqual(regRes.status, 201, 'Registration must return 201 Created');
    const regData = await regRes.json();
    const ownerToken = regData.accessToken;
    console.log(`✓ Owner registered: ${ownerEmail}`);

    // STEP 2: Owner creates Pairing Session
    console.log('\n--- STEP 2: Owner generates pairing session ---');
    const sessRes = await fetch(`${API_BASE}/pairing/sessions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${ownerToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ deviceName: 'Windows — Gaming PC' })
    });
    assert.strictEqual(sessRes.status, 201);
    const session = await sessRes.json();
    assert.ok(session.sessionId);
    assert.ok(session.pairingCode);
    console.log(`✓ Pairing session created: ${session.sessionId} (Code: ${session.pairingCode})`);

    // STEP 3: Windows Client generates Ed25519 keypair and submits enrollment
    console.log('\n--- STEP 3: Windows Client submits enrollment request ---');
    const { publicKey } = crypto.generateKeyPairSync('ed25519', {
      publicKeyEncoding: { type: 'spki', format: 'pem' }
    });

    const pairReqRes = await fetch(`${API_BASE}/pairing/sessions/${session.sessionId}/request`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        deviceName: 'Windows — Gaming PC',
        platform: 'WINDOWS',
        clientType: 'WINDOWS_AGENT',
        appVersion: '0.3.0',
        publicKey,
        keyAlgorithm: 'Ed25519'
      })
    });
    assert.strictEqual(pairReqRes.status, 200);
    const pairReqData = await pairReqRes.json();
    assert.strictEqual(pairReqData.status, 'PENDING_APPROVAL');
    console.log('✓ Windows Client enrollment request submitted (PENDING_APPROVAL).');

    // STEP 4: Owner Approves Pairing Session
    console.log('\n--- STEP 4: Owner reviews and approves Windows PC enrollment ---');
    const approveRes = await fetch(`${API_BASE}/pairing/sessions/${session.sessionId}/approve`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${ownerToken}`,
        'Content-Type': 'application/json'
      }
    });
    assert.strictEqual(approveRes.status, 200);
    const approveData = await approveRes.json();
    assert.strictEqual(approveData.status, 'APPROVED');
    assert.ok(approveData.deviceId);
    const deviceId = approveData.deviceId;
    console.log(`✓ Owner approved Windows device. Assigned Device ID: ${deviceId}`);

    // STEP 5: Windows Client polls status and extracts device credential
    console.log('\n--- STEP 5: Windows Client polls status to retrieve deviceToken ---');
    const pollRes = await fetch(`${API_BASE}/pairing/sessions/${session.sessionId}/status`);
    assert.strictEqual(pollRes.status, 200);
    const pollData = await pollRes.json();
    assert.strictEqual(pollData.status, 'APPROVED');
    assert.ok(pollData.deviceToken);
    const deviceToken = pollData.deviceToken;
    console.log('✓ Windows Client received persistent device token.');

    // STEP 6: Verify Device appears in Owner Fleet
    console.log('\n--- STEP 6: Verify Windows PC appears in dashboard device list ---');
    const devicesRes = await fetch(`${API_BASE}/devices`, {
      headers: { 'Authorization': `Bearer ${ownerToken}` }
    });
    assert.strictEqual(devicesRes.status, 200);
    const devicesList = await devicesRes.json();
    const winDevice = devicesList.find(d => d.id === deviceId);
    assert.ok(winDevice, 'Windows device must appear in fleet list');
    assert.strictEqual(winDevice.platform, 'WINDOWS');
    assert.strictEqual(winDevice.status, 'ACTIVE');
    console.log(`✓ Fleet verified: ${winDevice.deviceName} (${winDevice.platform}) is ACTIVE.`);

    // STEP 7: Windows Client Heartbeat Telemetry
    console.log('\n--- STEP 7: Windows Client sends heartbeat telemetry ---');
    const hbRes = await fetch(`${API_BASE}/devices/${deviceId}/heartbeat`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${deviceToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        appVersion: '0.3.0',
        protectionState: 'PROTECTED',
        policyVersion: 1
      })
    });
    assert.strictEqual(hbRes.status, 200);
    const hbData = await hbRes.json();
    assert.strictEqual(hbData.acknowledged, true);
    console.log(`✓ Heartbeat acknowledged by cloud. Status: ${hbData.deviceStatus}`);

    // STEP 8: Owner creates application policy for discord.exe
    console.log('\n--- STEP 8: Owner defines application focus policy for discord.exe ---');
    const polRes = await fetch(`${API_BASE}/policies`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${ownerToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        name: 'Discord Focus Budget',
        limitSeconds: 1800,
        period: 'DAILY',
        timezone: 'UTC',
        enforcementMode: 'BLOCK',
        targets: [{
          targetType: 'APP',
          targetValue: 'discord.exe'
        }],
        assignedDeviceIds: [deviceId]
      })
    });
    assert.strictEqual(polRes.status, 201);
    const policy = await polRes.json();
    console.log(`✓ Policy created: ${policy.name} (Limit: 30m) for discord.exe.`);

    // STEP 9: Windows Client syncs policies
    console.log('\n--- STEP 9: Windows Client syncs assigned policies ---');
    const syncRes = await fetch(`${API_BASE}/device/policies/sync`, {
      headers: { 'Authorization': `Bearer ${deviceToken}` }
    });
    assert.strictEqual(syncRes.status, 200);
    const syncData = await syncRes.json();
    assert.ok(syncData.policies.length >= 1);
    const targetMatch = syncData.policies.some(p => p.targets.some(t => t.targetValue === 'discord.exe'));
    assert.ok(targetMatch, 'Windows client must receive policy for discord.exe');
    console.log(`✓ Policies synchronized. Total active policies: ${syncData.policies.length}.`);

    // STEP 10: Windows Client flushes active usage deltas & batch events
    console.log('\n--- STEP 10: Ingesting usage deltas & batch events from Windows Agent ---');
    const usageRes = await fetch(`${API_BASE}/usage/sync`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${deviceToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        deviceId,
        syncSequence: 1,
        usageDeltas: [{
          targetValue: 'discord.exe',
          durationSeconds: 1800,
          date: new Date().toISOString().split('T')[0]
        }]
      })
    });
    assert.strictEqual(usageRes.status, 200);
    const usageData = await usageRes.json();
    assert.strictEqual(usageData.aggregatedTotal['discord.exe'], 1800);
    console.log('✓ Usage delta synchronized (1800s accumulated).');

    // Batch event ingestion
    const eventBatchRes = await fetch(`${API_BASE}/events/batch`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${deviceToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        events: [
          {
            id: `evt_win_${Date.now()}_1`,
            eventType: 'USAGE_SESSION_STARTED',
            domain: 'discord.exe',
            reason: 'Foreground focus active',
            timestamp: new Date().toISOString()
          },
          {
            id: `evt_win_${Date.now()}_2`,
            eventType: 'LIMIT_REACHED',
            domain: 'discord.exe',
            reason: 'Daily 30m limit reached',
            timestamp: new Date().toISOString()
          },
          {
            id: `evt_win_${Date.now()}_3`,
            eventType: 'ENFORCEMENT_TRIGGERED',
            domain: 'discord.exe',
            reason: 'Action CLOSE_APPLICATION executed',
            timestamp: new Date().toISOString()
          }
        ]
      })
    });
    assert.strictEqual(eventBatchRes.status, 200);
    const eventData = await eventBatchRes.json();
    assert.strictEqual(eventData.success, true);
    assert.strictEqual(eventData.processed, 3);
    console.log('✓ Batch events processed by cloud (3/3 events ingested).');

    // STEP 11: Cold reboot verification
    console.log('\n--- STEP 11: Cold reboot credential recovery (No re-pairing) ---');
    const rebootHb = await fetch(`${API_BASE}/devices/${deviceId}/heartbeat`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${deviceToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        appVersion: '0.3.0',
        protectionState: 'PROTECTED',
        policyVersion: syncData.policyVersion
      })
    });
    assert.strictEqual(rebootHb.status, 200);
    console.log('✓ Cold reboot successful. Device authenticated without re-pairing.');

    // STEP 12: Remote Device Revocation
    console.log('\n--- STEP 12: Owner revokes Windows device from Dashboard ---');
    const revokeRes = await fetch(`${API_BASE}/devices/${deviceId}/revoke`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${ownerToken}` }
    });
    assert.strictEqual(revokeRes.status, 200);
    const revokeData = await revokeRes.json();
    assert.strictEqual(revokeData.status, 'REVOKED');
    console.log('✓ Owner successfully revoked device.');

    // Verify revoked device cannot make API requests
    console.log('\n--- STEP 13: Verifying revoked Windows client is rejected ---');
    const rejectHb = await fetch(`${API_BASE}/devices/${deviceId}/heartbeat`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${deviceToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        appVersion: '0.3.0',
        protectionState: 'PROTECTED',
        policyVersion: 1
      })
    });
    assert.strictEqual(rejectHb.status, 403, 'Revoked device must receive HTTP 403 Forbidden');
    const rejectErr = await rejectHb.json();
    assert.strictEqual(rejectErr.error.code, 'DEVICE_REVOKED');
    console.log('✓ Zero-Trust verified: Revoked device immediately rejected with HTTP 403 (DEVICE_REVOKED).');

    console.log('\n================================================================================');
    console.log('🎉 ALL FOCUSGUARD PHASE 3 WINDOWS CLIENT INTEGRATION CHECKS PASSED (100%)');
    console.log('================================================================================\n');

  } finally {
    server.kill();
    // Clean up test db
    [TEST_DB, `${TEST_DB}-shm`, `${TEST_DB}-wal`].forEach(f => {
      if (fs.existsSync(f)) fs.unlinkSync(f);
    });
  }
}

runTest().catch(err => {
  console.error('\n❌ TEST FAILED:', err);
  process.exit(1);
});
