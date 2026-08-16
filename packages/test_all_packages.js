/**
 * FocusGuard Monorepo Packages Test Suite
 */

const DomainEngine = require('./domain-engine/index.js');
const CryptoEngine = require('./crypto/index.js');
const PolicyCoreEngine = require('./policy-core/index.js');
const { EventFactory, EventType } = require('./event-model/index.js');
const DeviceModel = require('./device-model/index.js');
const { ProtocolEnvelope, MessageType } = require('./protocol/index.js');
const ValidationEngine = require('./validation/index.js');
const assert = require('assert');

console.log('=== RUNNING FOCUSGUARD PACKAGES TEST SUITE ===');

// 1. Domain Engine
assert.strictEqual(DomainEngine.matches('m.youtube.com', 'youtube.com'), true);
assert.strictEqual(DomainEngine.matches('fakeyoutube.com', 'youtube.com'), false);
console.log('✓ 1. DomainEngine passed');

// 2. Crypto Engine
const id = CryptoEngine.generateId();
const key = CryptoEngine.generateDeviceKey();
const sig = CryptoEngine.sign('test_payload', key);
assert.strictEqual(CryptoEngine.verifySignature('test_payload', sig, key), true);
console.log('✓ 2. CryptoEngine passed');

// 3. Policy Core Engine
const decision = PolicyCoreEngine.evaluate({
  targetType: 'DOMAIN',
  target: 'youtube.com',
  policies: [{ id: 'pol_1', version: 1, targetType: 'DOMAIN', target: 'youtube.com', action: 'TIME_LIMIT', limit: 30 }],
  currentUsageSeconds: 30
});
assert.strictEqual(decision.decision, 'BLOCK');
assert.strictEqual(decision.reason, 'TIME_LIMIT_EXCEEDED');
console.log('✓ 3. PolicyCoreEngine passed');

// 4. Event Model
const evt = EventFactory.createDomainBlockedEvent({
  deviceId: 'dev_123',
  policyVersion: 1,
  domain: 'youtube.com',
  policyId: 'pol_1',
  reason: 'TIME_LIMIT_EXCEEDED',
  usedSeconds: 30,
  limitSeconds: 30
});
assert.strictEqual(evt.type, EventType.DOMAIN_BLOCKED);
assert.strictEqual(evt.payload.domain, 'youtube.com');
console.log('✓ 4. EventModel passed');

// 5. Device Model
const dev = DeviceModel.createDeviceRecord({ platform: 'BROWSER', deviceName: 'Chrome on MacBook' });
assert.strictEqual(dev.platform, 'BROWSER');
const score = DeviceModel.calculateProtectionScore({ policyCurrent: true, usageDetection: true, browserProtection: true, networkProtection: true, syncActive: true });
assert.strictEqual(score.score, 100);
console.log('✓ 5. DeviceModel passed');

// 6. Protocol
const packed = ProtocolEnvelope.pack(MessageType.POLICY_PUSH, { version: 42 });
const unpacked = ProtocolEnvelope.unpack(packed);
assert.strictEqual(unpacked.type, MessageType.POLICY_PUSH);
assert.strictEqual(unpacked.payload.version, 42);
console.log('✓ 6. Protocol passed');

// 7. Validation
const validPol = ValidationEngine.validatePolicy({ id: 'p1', targetType: 'DOMAIN', target: 'youtube.com', action: 'TIME_LIMIT', limit: 30 });
assert.strictEqual(validPol.valid, true);
const invalidPol = ValidationEngine.validatePolicy({ id: 'p2', targetType: 'INVALID', target: '', action: 'BLOCK' });
assert.strictEqual(invalidPol.valid, false);
console.log('✓ 7. ValidationEngine passed');

console.log('==============================================');
console.log('ALL MONOREPO PACKAGES TESTS PASSED (100%)');
console.log('==============================================');
