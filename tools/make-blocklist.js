// Builds Sources/blocklist.json (WebKit content-blocker format) from Peter Lowe's ad server list.
// Run: node tools/make-blocklist.js   (re-run now and then to refresh the list)
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const SRC = 'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=nohtml&showintro=0&mimetype=plaintext';

// Common ad slots: hide them so pages don't show empty boxes where blocked ads were.
const HIDE = [
  '.adsbygoogle', 'ins.adsbygoogle', '[id^="google_ads_iframe"]', '[id^="div-gpt-ad"]',
  '[data-ad-slot]', '[data-google-query-id]', '.ad-slot', '.ad-banner', '.advertisement',
].join(', ');

function rules(domains) {
  const block = domains.map((d) => ({
    trigger: {
      // WebKit regex has no "|", so one rule per domain. Matches the domain and all its subdomains.
      'url-filter': '^[^:]+://+([^:/]+\\.)?' + d.replace(/\./g, '\\.') + '[:/]',
      'load-type': ['third-party'],
    },
    action: { type: 'block' },
  }));
  return [...block, { trigger: { 'url-filter': '.*' }, action: { type: 'css-display-none', selector: HIDE } }];
}

async function main() {
  const text = await (await fetch(SRC)).text();
  const domains = [...new Set(text.split(/\r?\n/).map((l) => l.trim().toLowerCase()))]
    .filter((d) => /^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(d)); // trust boundary: only plain domains reach the regex
  assert(domains.length > 1000, `list looks broken: only ${domains.length} domains`);

  const out = rules(domains);
  // Self-check the generated regexes the same way WebKit will use them.
  const dc = out.find((r) => r.trigger['url-filter'].includes('doubleclick\\.net'));
  assert(dc, 'doubleclick.net missing');
  const re = new RegExp(dc.trigger['url-filter']);
  assert(re.test('https://ad.doubleclick.net/ddm/x'));
  assert(re.test('https://doubleclick.net:443/'));
  assert(!re.test('https://notdoubleclick.net/'));
  assert(!re.test('https://example.com/?u=doubleclick.net/'));

  const file = path.join(__dirname, '../Sources/blocklist.json');
  fs.writeFileSync(file, JSON.stringify(out));
  console.log(`wrote ${out.length} rules to ${file}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
