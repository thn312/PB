// Writes an AltStore/SideStore source (source.json) for one release of PB.
// Usage: node tools/make-source.js <owner/repo> <build number> <path to PB.ipa> > source.json
const fs = require('fs');

function source(repo, build, size, date) {
  const version = `1.0.${build}`;
  const downloadURL = `https://github.com/${repo}/releases/download/build-${build}/PB.ipa`;
  const v = { version, buildVersion: String(build), date, downloadURL, size, minOSVersion: '17.0' };
  return {
    name: 'PB',
    identifier: 'com.usbrowser.source',
    apps: [{
      name: 'PB',
      bundleIdentifier: 'com.usbrowser.app',
      developerName: repo.split('/')[0],
      subtitle: 'Proxy browser with location spoofing',
      localizedDescription: 'Browser that runs through your proxy and matches GPS, timezone and language to the proxy IP. Built-in ad blocker.',
      iconURL: `https://raw.githubusercontent.com/${repo}/main/Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`,
      tintColor: 'F26A1B',
      versions: [v],
      // Older AltStore/SideStore builds read these top-level fields instead of `versions`.
      version, versionDate: date, downloadURL, size,
      appPermissions: { entitlements: [], privacy: {} },
    }],
    news: [],
  };
}

if (require.main === module) {
  const [repo, build, ipa] = process.argv.slice(2);
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo || '') || !/^\d+$/.test(build || '') || !ipa) {
    console.error('usage: node tools/make-source.js <owner/repo> <build number> <PB.ipa>');
    process.exit(1);
  }
  const out = source(repo, Number(build), fs.statSync(ipa).size, new Date().toISOString().slice(0, 10));
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
}

module.exports = { source };
