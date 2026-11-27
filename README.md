# US Browser (iOS 17+)

A browser that runs through a proxy and automatically spoofs location, timezone and language to match the proxy's IP.

| Spoofed | How |
|---|---|
| IP + DNS | `WKWebsiteDataStore.proxyConfigurations` (SOCKS5 / HTTP CONNECT) |
| GPS | `navigator.geolocation` returns the proxy IP's coordinates (looked up via ipinfo.io) |
| Timezone | `Intl`, `Date` (getHours, toString, getTimezoneOffset…) |
| Language | `Accept-Language` + `navigator.language` = en-US |
| WebRTC | Blocked so the real IP can't leak |

If the proxy fails, the app **loads no pages**, so your real IP is never used.

Also: tabs, Chrome-style address bar and bottom toolbar, and a built-in **ad & tracker blocker** (WebKit content blocker, toggle with the 🛡 shield). Links never jump to other apps (X, YouTube…), since those apps would bypass the proxy.

## Build on GitHub (no Mac needed)
1. Push this folder to a public GitHub repo (Actions minutes are free and unlimited for public repos).
2. Open **Actions** → **Build IPA**, wait about 5 minutes, then download `USBrowser-ipa` from Artifacts.
3. The IPA is unsigned. Install it on your iPhone with **Sideloadly** (has a Windows version) and your Apple ID.
   - Free Apple ID: the app expires after 7 days and must be re-signed.
   - Apple Developer account ($99/year): the app lasts 1 year.
4. On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID. Turn on **Developer Mode** if iOS asks.

## After installing, verify
- Open the app, tap ⚙️, enter the proxy (a **US residential** proxy works best), then tap Save & Connect.
- **Force-quit the app and reopen it once** so the language header switches to en-US.
- Check with: `browserleaks.com/ip`, `browserleaks.com/javascript`, `dnsleaktest.com`, `whoer.net`.

## Test
`node tests/spoof.test.js` checks the timezone spoofing (device set to Vietnam, result must be Chicago). GitHub Actions runs it on every push.

## Ad blocklist
`Sources/blocklist.json` is generated from [Peter Lowe's ad server list](https://pgl.yoyo.org/adservers/) (~3.5k domains, free for personal use). Refresh it with `node tools/make-blocklist.js`.

## Limits
- Only works inside this app.
- Datacenter proxies are still detected by Google, Netflix, exchanges, etc.
- Web Workers still see the real timezone. `new Date(y, m, d)` and the `setHours…` setters still use device time.
- Sites that check `Function.toString` can see the overridden functions.
- The ad blocker blocks ad/tracker domains; ads served from the site's own domain (e.g. YouTube video ads) still show.
