/**
 * FocusGuard Browser Extension Test Suite
 * 
 * Verifies domain normalization, subdomain matching, URL pattern policies,
 * session state transitions, active-time calculation, and policy evaluation.
 */

const assert = require('assert');
const { DomainMatcher } = require('../core/domain-matcher');
const { SessionTracker, SessionState } = require('../core/session-tracker');
const { ExtensionPolicyEngine } = require('../policy/policy-engine');

console.log('--- Running FocusGuard Extension Core Tests ---');

// 1. Domain Matcher Tests
console.log('1. Testing DomainMatcher...');
assert.strictEqual(DomainMatcher.normalizeDomain('https://www.YouTube.com/watch?v=123'), 'www.youtube.com');
assert.strictEqual(DomainMatcher.normalizeDomain('http://m.reddit.com:8080/r/all#top'), 'm.reddit.com');
assert.strictEqual(DomainMatcher.normalizeDomain('instagram.com.'), 'instagram.com');

// Subdomain matching & false positive prevention
assert.strictEqual(DomainMatcher.isDomainMatch('youtube.com', 'youtube.com'), true, 'Exact match should pass');
assert.strictEqual(DomainMatcher.isDomainMatch('www.youtube.com', 'youtube.com'), true, 'www prefix should match target');
assert.strictEqual(DomainMatcher.isDomainMatch('m.youtube.com', 'youtube.com'), true, 'Subdomain m. should match target');
assert.strictEqual(DomainMatcher.isDomainMatch('music.youtube.com', 'youtube.com'), true, 'music.youtube.com should match');
assert.strictEqual(DomainMatcher.isDomainMatch('notyoutube.com', 'youtube.com'), false, 'notyoutube.com must NOT match youtube.com');
assert.strictEqual(DomainMatcher.isDomainMatch('myoutube.com', 'youtube.com'), false, 'myoutube.com must NOT match youtube.com');
assert.strictEqual(DomainMatcher.isDomainMatch('youtube.company.com', 'youtube.com'), false, 'Infix domain must NOT match');

// URL Pattern Matching
assert.strictEqual(DomainMatcher.isUrlPatternMatch('https://reddit.com/r/gaming', 'reddit.com/r/gaming'), true);
assert.strictEqual(DomainMatcher.isUrlPatternMatch('https://reddit.com/r/science', 'reddit.com/r/gaming'), false);
assert.strictEqual(DomainMatcher.isUrlPatternMatch('https://youtube.com/shorts/abc', 'youtube.com/shorts*'), true);
assert.strictEqual(DomainMatcher.isUrlPatternMatch('https://youtube.com/feed/trending', 'youtube.com/shorts*'), false);
console.log('✓ DomainMatcher tests passed successfully.');

// 2. Session Tracker & State Machine Tests
console.log('2. Testing SessionTracker...');
let tickCount = 0;
let lastState = null;
const tracker = new SessionTracker({
  idleThresholdSeconds: 60,
  onUsageTick: () => { tickCount++; },
  onStateChange: (newState) => { lastState = newState; }
});

tracker.startSession('https://youtube.com', 1, 100);
assert.strictEqual(tracker.state, SessionState.ACTIVE, 'Session should be ACTIVE upon start');
assert.strictEqual(tracker.currentDomain, 'youtube.com');

// Window blur pauses session
tracker.onWindowFocusChanged(false);
assert.strictEqual(tracker.state, SessionState.PAUSED, 'Window blur should PAUSE session');

// Window focus resumes session
tracker.onWindowFocusChanged(true);
assert.strictEqual(tracker.state, SessionState.ACTIVE, 'Window focus should RESUME session');

// System idle transitions to IDLE
tracker.onIdleStateChanged('idle');
assert.strictEqual(tracker.state, SessionState.IDLE, 'Idle state change should transition to IDLE');

// System active returns to ACTIVE
tracker.onIdleStateChanged('active');
assert.strictEqual(tracker.state, SessionState.ACTIVE, 'System active should return to ACTIVE');

const summary = tracker.endSession();
assert.strictEqual(tracker.state, SessionState.ENDED, 'End session should transition to ENDED');
assert.strictEqual(summary.domain, 'youtube.com');
console.log('✓ SessionTracker tests passed successfully.');

// 3. Policy Engine Evaluation Tests
console.log('3. Testing ExtensionPolicyEngine...');
const engine = new ExtensionPolicyEngine(DomainMatcher);

engine.setPolicies([
  {
    id: 'pol-1',
    name: 'YouTube Daily Budget',
    limitSeconds: 1800, // 30 mins
    enforcementMode: 'BLOCK',
    isEnabled: true,
    targets: [{ targetType: 'WEBSITE', targetValue: 'youtube.com' }]
  },
  {
    id: 'pol-2',
    name: 'Social Category Block',
    enforcementMode: 'BLOCK',
    isEnabled: true,
    targets: [{ targetType: 'CATEGORY', targetValue: 'SOCIAL' }]
  },
  {
    id: 'pol-3',
    name: 'Documentation Whitelist',
    enforcementMode: 'ALLOW',
    isEnabled: true,
    targets: [{ targetType: 'WEBSITE', targetValue: 'github.com' }]
  }
]);

// A. Check Whitelist Precedence
const allowRes = engine.evaluate('https://github.com/focusguard');
assert.strictEqual(allowRes.action, 'ALLOW');

// B. Check Category Blocking (Instagram -> Social)
const socialRes = engine.evaluate('https://instagram.com/p/123');
assert.strictEqual(socialRes.action, 'BLOCK');
assert.strictEqual(socialRes.category, 'SOCIAL');

// C. Check Time Limit Evaluation (YouTube budget)
engine.setTodayUsage({ 'youtube.com': 600 }); // 10 mins consumed
let ytRes = engine.evaluate('https://m.youtube.com');
assert.strictEqual(ytRes.action, 'ALLOW', 'Under budget should be ALLOW');

// Warning at 80% (24 mins / 1440s)
engine.setTodayUsage({ 'youtube.com': 1500 }); // 25 mins consumed (83%)
ytRes = engine.evaluate('https://youtube.com');
assert.strictEqual(ytRes.action, 'WARN', '80%+ should trigger WARN');

// Block at 100% (30 mins / 1800s)
engine.setTodayUsage({ 'youtube.com': 1800 }); // 30 mins consumed
ytRes = engine.evaluate('https://youtube.com');
assert.strictEqual(ytRes.action, 'BLOCK', '100% should trigger BLOCK');
assert.strictEqual(ytRes.reason, 'Daily attention budget reached.');

// D. Check Focus Session Lockdown
engine.setFocusSession({
  isActive: true,
  name: 'Remote Study Session',
  durationMinutes: 60,
  allowedDomains: ['github.com', 'canvas.instructure.com'],
  allowedCategories: ['EDUCATION']
});

const focusBlockRes = engine.evaluate('https://twitch.tv');
assert.strictEqual(focusBlockRes.action, 'BLOCK');
assert.strictEqual(focusBlockRes.reason, 'Remote Focus Lockdown Active');

console.log('✓ ExtensionPolicyEngine tests passed successfully.');
console.log('================================================');
console.log('ALL BROWSER EXTENSION CORE TESTS PASSED (100%)');
console.log('================================================');
