// Runs spoof.js in node exactly as Swift wraps it, with the "device" in Vietnam, and checks it reports Chicago.
// Run: node tests/spoof.test.js
const { execFileSync } = require('child_process');
const path = require('path');

if (process.env.TZ !== 'Asia/Ho_Chi_Minh') {
  execFileSync(process.execPath, [__filename], { stdio: 'inherit', env: { ...process.env, TZ: 'Asia/Ho_Chi_Minh' } });
  process.exit(0);
}

const assert = require('assert');
const fs = require('fs');
const src = fs.readFileSync(path.join(__dirname, '../Sources/spoof.js'), 'utf8');
assert.strictEqual(new Date('2026-01-01').getTimezoneOffset(), -420, 'test must start with device in Vietnam');

eval('(C => {\n' + src + '\n})(' + JSON.stringify({ lat: 32.78, lon: -96.8, tz: 'America/Chicago' }) + ');');

const winter = new Date('2026-11-27T18:30:45Z'); // CST = UTC-6
const summer = new Date('2026-07-04T18:30:45Z'); // CDT = UTC-5
assert.strictEqual(winter.getTimezoneOffset(), 360);
assert.strictEqual(summer.getTimezoneOffset(), 300);
assert.strictEqual(winter.getHours(), 12);
assert.strictEqual(winter.getDate(), 27);
assert.strictEqual(new Date('2026-11-28T03:00:00Z').getDate(), 27); // still the 27th in Chicago
assert.strictEqual(new Date('2026-11-28T03:00:00Z').getDay(), 5);   // Friday
assert.strictEqual(Intl.DateTimeFormat().resolvedOptions().timeZone, 'America/Chicago');
assert.strictEqual(new Intl.DateTimeFormat('en-US', { timeZone: 'UTC' }).resolvedOptions().timeZone, 'UTC');
assert.strictEqual(winter.toString(), 'Fri Nov 27 2026 12:30:45 GMT-0600 (Central Standard Time)');
assert.strictEqual(summer.toTimeString(), '13:30:45 GMT-0500 (Central Daylight Time)');
assert.match(winter.toLocaleTimeString('en-US'), /^12:30:45/);
assert.strictEqual(String(new Date(NaN)), 'Invalid Date');
assert.strictEqual(navigator.language, 'en-US');
console.log('spoof.js OK');
