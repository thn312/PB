# PB (iOS 17+)

A browser that runs through a proxy and automatically spoofs location, timezone and language to match the proxy's IP.

| Spoofed | How |
|---|---|
| IP + DNS | `WKWebsiteDataStore.proxyConfigurations` (SOCKS5 / HTTP CONNECT) |
| GPS | `navigator.geolocation` returns the proxy IP's coordinates (looked up via ipinfo.io) |
| Timezone | `Intl`, `Date` (getHours, toString, getTimezoneOffset…) |
| Language | `Accept-Language` + `navigator.language` = en-US |
| WebRTC | Blocked so the real IP can't leak |

If the proxy fails, the app **loads no pages**, so your real IP is never used.

**No Proxy mode** (Proxies → No Proxy, or ⋯ → Switch Proxy): browse with your real IP when you don't need a location. Nothing is spoofed then (real location and timezone match the real IP); ad blocking and YouTube background play still work. The app only goes direct when you pick it, never as a fallback for a dead proxy.

Also: tabs, Chrome-style address bar and bottom toolbar, and a built-in **ad & tracker blocker** (WebKit content blocker, toggle with the 🛡 shield). Links never jump to other apps (X, YouTube…), since those apps would bypass the proxy. To allow it, turn on ⋯ → **Allow Opening Apps** (off by default); app links then open their app, and long-press adds **Open in App**.

## History & suggestions
- **History** (⋯ → History): pages you visited, grouped by day, searchable, swipe to delete, Clear to wipe. Stored only on the device.
- **Suggestions while typing**: matching pages from history plus Google search suggestions. Suggestion requests go through the active proxy (or direct in No Proxy mode), same as the tabs.

## Cookies & site data (iOS)
⋯ → **Cookies & Site Data** for the current site:
- list its cookies, swipe to delete one;
- **Copy / Export** them as JSON in the Cookie-Editor / EditThisCookie format (importable into Chrome and other tools);
- **Clear Cookies & Data** for this site, or **Clear All Website Data** (signs you out; history is kept).

## YouTube
`Sources/youtube.js` (YouTube only):
- **Background play**: keeps playing with the screen off or the app in the background (audio background mode + the page always looks visible).
- **No ads** (when 🛡 is on): strips ad data from YouTube's player responses before the player reads them, hides ad boxes, and fast-forwards/skips anything that slips through.

YouTube changes its ad delivery often. The app downloads the latest `youtube.js` from this repo (through the proxy) on every connect, so a fix pushed to `main` reaches the app without reinstalling. If the download fails, the copy bundled in the app is used.

## Build on GitHub (no Mac needed)
1. Push this folder to a public GitHub repo (Actions minutes are free and unlimited for public repos).
2. Open **Actions** → **Build IPA**, wait about 5 minutes, then download `PB-ipa` from Artifacts (or `PB.ipa` from Releases).
3. The IPA is unsigned. Install it on your iPhone with **Sideloadly** (has a Windows version) and your Apple ID.
   - Free Apple ID: the app expires after 7 days and must be re-signed.
   - Apple Developer account ($99/year): the app lasts 1 year.
4. On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID. Turn on **Developer Mode** if iOS asks.

## Android (`android/`)
Same features in Kotlin + Jetpack Compose, sharing `spoof.js`, `youtube.js` and `blocklist.json` with iOS. Differences:
- **HTTP proxies only** (Android WebView can't use SOCKS5 with a password).
- Background playback uses a foreground service with a "Playing in the background" notification.
- Install `PB.apk` from Releases directly: no 7-day re-signing.

Signing: every APK must use the same key or Android refuses to update over the old install. CI reads two repo secrets
(Settings → Secrets and variables → Actions): `PB_KEYSTORE_B64` (base64 of the keystore) and `PB_KEYSTORE_PASSWORD`.
Keep the keystore safe outside the repo; losing it means uninstalling PB once to switch keys.

## Install with SideStore (free, auto-refresh, no PC after setup)
Every push to `main` publishes a GitHub Release with `PB.ipa` and a SideStore source:

```
https://github.com/thn312/PB/releases/latest/download/source.json
```

1. iPhone: install **LocalDevVPN** from the App Store.
2. PC: install SideStore with **iloader** (follow docs.sidestore.io), signing in with your Apple ID.
3. iPhone: trust your Apple ID (Settings → General → VPN & Device Management), open LocalDevVPN and connect, then open SideStore.
4. SideStore → **Sources** → **+** → paste the URL above → install **PB**. New builds show up as updates.
5. Keep LocalDevVPN on and Background App Refresh enabled for SideStore so it re-signs before the 7 days run out.

## After installing, verify
- Open the app, tap **Proxies** (or ⋯ → Proxies), tap **+**, enter the proxy (a **US residential** proxy works best), then tap Save. Add more proxies the same way and switch with ⋯ → Switch Proxy.
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
