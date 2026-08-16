const PolicyCoreEngine = require('./index.js');
const assert = require('assert');

console.log('Testing FocusGuard PolicyCoreEngine...');

// 1. Version monotonicity check
assert.strictEqual(PolicyCoreEngine.validateVersionTransition(40, 41), true);
assert.strictEqual(PolicyCoreEngine.validateVersionTransition(41, 41), true);
assert.strictEqual(PolicyCoreEngine.validateVersionTransition(42, 41), false);

// 2. Schedule evaluation
const schedule = { days: [1,2,3,4,5], start: '09:00', end: '17:00' };
const duringWorkday = new Date('2026-08-17T11:00:00'); // Monday 11am
const duringNight = new Date('2026-08-17T22:00:00'); // Monday 10pm
const duringWeekend = new Date('2026-08-16T11:00:00'); // Sunday 11am

assert.strictEqual(PolicyCoreEngine.isScheduleActive(schedule, duringWorkday), true);
assert.strictEqual(PolicyCoreEngine.isScheduleActive(schedule, duringNight), false);
assert.strictEqual(PolicyCoreEngine.isScheduleActive(schedule, duringWeekend), false);

// 3. Time Limit evaluation pipeline
const testPolicies = [
  {
    id: 'pol_yt_30s',
    version: 42,
    targetType: 'DOMAIN',
    target: 'youtube.com',
    action: 'TIME_LIMIT',
    limit: 30, // 30 seconds
    priority: 10
  },
  {
    id: 'pol_kids_allow',
    version: 42,
    targetType: 'DOMAIN',
    target: 'kids.youtube.com',
    action: 'ALLOW',
    priority: 100 // High priority override
  }
];

// Test Under Budget
const res1 = PolicyCoreEngine.evaluate({
  targetType: 'DOMAIN',
  target: 'www.youtube.com',
  policies: testPolicies,
  currentUsageSeconds: 15
});
assert.strictEqual(res1.decision, 'ALLOW');
assert.strictEqual(res1.reason, 'WITHIN_TIME_LIMIT');

// Test Warning at 90% (27s of 30s)
const res2 = PolicyCoreEngine.evaluate({
  targetType: 'DOMAIN',
  target: 'm.youtube.com',
  policies: testPolicies,
  currentUsageSeconds: 27
});
assert.strictEqual(res2.decision, 'WARN');
assert.strictEqual(res2.reason, 'TIME_LIMIT_90_PERCENT');

// Test Exceeded (30s reached)
const res3 = PolicyCoreEngine.evaluate({
  targetType: 'DOMAIN',
  target: 'music.youtube.com',
  policies: testPolicies,
  currentUsageSeconds: 30
});
assert.strictEqual(res3.decision, 'BLOCK');
assert.strictEqual(res3.reason, 'TIME_LIMIT_EXCEEDED');

// Test Priority Override: kids.youtube.com is ALLOW even when general youtube is exhausted
const res4 = PolicyCoreEngine.evaluate({
  targetType: 'DOMAIN',
  target: 'kids.youtube.com',
  policies: testPolicies,
  currentUsageSeconds: 50
});
assert.strictEqual(res4.decision, 'ALLOW');
assert.strictEqual(res4.reason, 'EXPLICIT_ALLOW_RULE');

console.log('✓ All PolicyCoreEngine tests passed successfully (100%)');
