const DomainEngine = require('./index.js');
const assert = require('assert');

console.log('Testing FocusGuard DomainEngine...');

// 1. Normalization tests
assert.strictEqual(DomainEngine.normalizeHostname('https://WWW.YouTube.COM/watch?v=123'), 'www.youtube.com');
assert.strictEqual(DomainEngine.normalizeHostname('http://reddit.com:8080/r/programming'), 'reddit.com');
assert.strictEqual(DomainEngine.normalizeHostname('m.facebook.com.'), 'm.facebook.com');

// 2. Base domain tests with multi-level TLDs
assert.strictEqual(DomainEngine.getBaseDomain('music.youtube.com'), 'youtube.com');
assert.strictEqual(DomainEngine.getBaseDomain('news.bbc.co.uk'), 'bbc.co.uk');
assert.strictEqual(DomainEngine.getBaseDomain('app.project.github.io'), 'project.github.io');

// 3. Subdomain matching tests
assert.strictEqual(DomainEngine.matches('youtube.com', 'youtube.com'), true);
assert.strictEqual(DomainEngine.matches('www.youtube.com', 'youtube.com'), true);
assert.strictEqual(DomainEngine.matches('music.youtube.com', 'youtube.com'), true);
assert.strictEqual(DomainEngine.matches('m.youtube.com', 'youtube.com'), true);
assert.strictEqual(DomainEngine.matches('gaming.youtube.com', '*.youtube.com'), true);

// 4. Critical security boundary tests: NEVER match non-subdomains or spoof domains
assert.strictEqual(DomainEngine.matches('notyoutube.com', 'youtube.com'), false);
assert.strictEqual(DomainEngine.matches('youtube.com.attacker.com', 'youtube.com'), false);
assert.strictEqual(DomainEngine.matches('fakeyoutube.com', 'youtube.com'), false);
assert.strictEqual(DomainEngine.matches('myoutube.com', 'youtube.com'), false);

// 5. Best match specificity tests
const rules = [
  { target: 'google.com', action: 'ALLOW', priority: 1 },
  { target: 'youtube.com', action: 'TIME_LIMIT', priority: 2 },
  { target: 'kids.youtube.com', action: 'ALLOW', priority: 10 }
];

const match1 = DomainEngine.findBestMatch('www.youtube.com', rules);
assert.strictEqual(match1.target, 'youtube.com');

const match2 = DomainEngine.findBestMatch('kids.youtube.com', rules);
assert.strictEqual(match2.target, 'kids.youtube.com');

console.log('✓ All DomainEngine tests passed successfully (100%)');
