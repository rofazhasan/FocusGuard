const CryptoEngine = require('./index.js');
const assert = require('assert');

console.log('Testing FocusGuard CryptoEngine...');

// 1. Identity generation
const devId = CryptoEngine.generateId();
assert.strictEqual(devId.length, 32);

const devKey = CryptoEngine.generateDeviceKey();
assert.strictEqual(devKey.length, 64);

const pairingCode = CryptoEngine.generatePairingCode();
assert.strictEqual(pairingCode.length, 6);
assert.match(pairingCode, /^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$/);

// 2. Sign and Verify
const payload = JSON.stringify({ deviceId: devId, timestamp: Date.now(), command: 'SYNC_POLICY' });
const signature = CryptoEngine.sign(payload, devKey);
assert.strictEqual(CryptoEngine.verifySignature(payload, signature, devKey), true);
assert.strictEqual(CryptoEngine.verifySignature(payload, 'deadbeef1234', devKey), false);
assert.strictEqual(CryptoEngine.verifySignature(payload + 'tampered', signature, devKey), false);

// 3. Freshness & Replay protection
assert.strictEqual(CryptoEngine.isTimestampValid(Date.now(), 60), true);
assert.strictEqual(CryptoEngine.isTimestampValid(Date.now() - 500000, 60), false);

console.log('✓ All CryptoEngine tests passed successfully (100%)');
