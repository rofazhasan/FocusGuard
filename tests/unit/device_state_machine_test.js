/**
 * Unit Test: FocusGuard Device State Machine & Transitions
 * Verifies all valid transitions, invalid transitions, and terminal states.
 */

const assert = require('assert');
const { DeviceStateMachine, isValidStateTransition } = require('../../packages/device-model/index.js');
const { PairingState } = require('../../packages/shared-types/index.js');

console.log('====================================================');
console.log('🧪 RUNNING DEVICE STATE MACHINE UNIT TEST MATRIX');
console.log('====================================================');

const S = DeviceStateMachine.States;

// 1. Valid Lifecycle Transitions
console.log('\n--- 1. Testing Valid State Transitions ---');
assert.strictEqual(DeviceStateMachine.canTransition(S.UNREGISTERED, S.PAIRING), true);
assert.strictEqual(DeviceStateMachine.canTransition(S.PAIRING, S.PENDING_APPROVAL), true);
assert.strictEqual(DeviceStateMachine.canTransition(S.PENDING_APPROVAL, S.ACTIVE), true);
assert.strictEqual(DeviceStateMachine.canTransition(S.ACTIVE, S.OFFLINE), true);
assert.strictEqual(DeviceStateMachine.canTransition(S.OFFLINE, S.ACTIVE), true);
assert.strictEqual(DeviceStateMachine.canTransition(S.ACTIVE, S.REVOKED), true);
assert.strictEqual(DeviceStateMachine.canTransition(S.OFFLINE, S.REVOKED), true);
assert.strictEqual(DeviceStateMachine.canTransition(S.REVOKED, S.TERMINAL), true);
console.log('✓ All primary lifecycle transitions passed');

// 2. Alternative Valid Branches (Rejections & Timeouts)
console.log('\n--- 2. Testing Alternative Valid Branches ---');
assert.strictEqual(DeviceStateMachine.canTransition(S.PENDING_APPROVAL, S.REJECTED), true);
assert.strictEqual(DeviceStateMachine.canTransition(S.PAIRING, S.EXPIRED), true);
assert.strictEqual(DeviceStateMachine.canTransition(S.REJECTED, S.TERMINAL), true);
assert.strictEqual(DeviceStateMachine.canTransition(S.EXPIRED, S.TERMINAL), true);
console.log('✓ Rejection and expiration transitions passed');

// 3. Invalid Transition Matrix
console.log('\n--- 3. Testing Invalid & Illegal Transitions ---');
const invalidCases = [
  [S.UNREGISTERED, S.ACTIVE],          // Cannot skip pairing & approval
  [S.UNREGISTERED, S.PENDING_APPROVAL],// Cannot skip pairing initialization
  [S.PAIRING, S.ACTIVE],               // Cannot activate without owner approval
  [S.PENDING_APPROVAL, S.OFFLINE],     // Unapproved device cannot be active/offline
  [S.REVOKED, S.ACTIVE],               // Revoked device cannot magically reactivate
  [S.REVOKED, S.PAIRING],              // Revoked device cannot directly resume pairing
  [S.TERMINAL, S.ACTIVE],              // Terminal state is final
  [S.ACTIVE, S.UNREGISTERED]           // Must follow revocation lifecycle
];

for (const [from, to] of invalidCases) {
  assert.strictEqual(DeviceStateMachine.canTransition(from, to), false, `Transition ${from} -> ${to} must be prohibited`);
  assert.throws(() => {
    DeviceStateMachine.transition(from, to);
  }, /Illegal state transition/, `Transition ${from} -> ${to} must throw illegal transition error`);
}
console.log('✓ All illegal transitions rejected with errors');

// 4. Backward Compatibility Check for Legacy isValidStateTransition
console.log('\n--- 4. Checking Backward Compatibility with PairingState ---');
assert.strictEqual(isValidStateTransition(PairingState.UNPAIRED, PairingState.PAIRING), true);
assert.strictEqual(isValidStateTransition(PairingState.PAIRING, PairingState.PENDING_APPROVAL), true);
assert.strictEqual(isValidStateTransition(PairingState.PENDING_APPROVAL, PairingState.PAIRED), true);
assert.strictEqual(isValidStateTransition(PairingState.PAIRED, PairingState.ACTIVE), true);
assert.strictEqual(isValidStateTransition(PairingState.REVOKED, PairingState.ACTIVE), false);
console.log('✓ Legacy compatibility verified');

console.log('\n====================================================');
console.log('✅ ALL DEVICE STATE MACHINE TESTS PASSED (100%)');
console.log('====================================================\n');
