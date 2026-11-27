// Checks the SideStore source points at the right release asset. Run: node tests/source.test.js
const assert = require('assert');
const { source } = require('../tools/make-source.js');

const s = source('thn312/PB', 42, 1234, '2026-11-27');
const app = s.apps[0];
assert.strictEqual(app.bundleIdentifier, 'com.usbrowser.app'); // must match project.yml or SideStore won't see updates
assert.strictEqual(app.versions[0].version, '1.0.42');
assert.strictEqual(app.versions[0].buildVersion, '42');
assert.strictEqual(app.versions[0].downloadURL, 'https://github.com/thn312/PB/releases/download/build-42/PB.ipa');
assert.strictEqual(app.downloadURL, app.versions[0].downloadURL);
assert.strictEqual(app.size, 1234);

const yml = require('fs').readFileSync(require('path').join(__dirname, '../project.yml'), 'utf8');
assert(yml.includes(`PRODUCT_BUNDLE_IDENTIFIER: ${app.bundleIdentifier}`), 'bundle id drifted from project.yml');
console.log('source OK');
