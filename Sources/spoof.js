// Injected at document start in every frame. Swift wraps it as `(C => { ... })({lat, lon, tz})`.
(() => {
  const TZ = C.tz;
  const ODTF = Intl.DateTimeFormat;

  // --- Timezone ---
  const parts = new ODTF('en-US', {
    timeZone: TZ, hourCycle: 'h23',
    year: 'numeric', month: 'numeric', day: 'numeric',
    hour: 'numeric', minute: 'numeric', second: 'numeric',
  });
  // Minutes to add to TZ-local time to get UTC (same sign convention as getTimezoneOffset).
  const off = (d) => {
    const t = Math.floor(d.getTime() / 1000) * 1000;
    const g = {};
    for (const p of parts.formatToParts(t)) g[p.type] = +p.value;
    return Math.round((t - Date.UTC(g.year, g.month - 1, g.day, g.hour, g.minute, g.second)) / 60000);
  };
  const shifted = (d) => new Date(d.getTime() - off(d) * 60000);

  function DTF(locales, opts) {
    return new ODTF(locales, Object.assign({ timeZone: TZ }, opts));
  }
  DTF.prototype = ODTF.prototype;
  DTF.supportedLocalesOf = ODTF.supportedLocalesOf;
  Intl.DateTimeFormat = DTF;

  const P = Date.prototype;
  P.getTimezoneOffset = function () { return isNaN(this) ? NaN : off(this); };
  for (const n of ['FullYear', 'Month', 'Date', 'Day', 'Hours', 'Minutes', 'Seconds']) {
    P['get' + n] = function () { return isNaN(this) ? NaN : shifted(this)['getUTC' + n](); };
  }
  for (const n of ['toLocaleString', 'toLocaleDateString', 'toLocaleTimeString']) {
    const orig = P[n];
    P[n] = function (l, o) { return orig.call(this, l, Object.assign({ timeZone: TZ }, o)); };
  }
  const D = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const M = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const pad = (n) => String(n).padStart(2, '0');
  const tzName = (d) => new ODTF('en-US', { timeZone: TZ, timeZoneName: 'long' })
    .formatToParts(d).find((p) => p.type === 'timeZoneName').value;
  const gmt = (d) => { const o = -off(d), a = Math.abs(o); return 'GMT' + (o < 0 ? '-' : '+') + pad(Math.floor(a / 60)) + pad(a % 60); };
  P.toDateString = function () {
    if (isNaN(this)) return 'Invalid Date';
    const s = shifted(this);
    return `${D[s.getUTCDay()]} ${M[s.getUTCMonth()]} ${pad(s.getUTCDate())} ${s.getUTCFullYear()}`;
  };
  P.toTimeString = function () {
    if (isNaN(this)) return 'Invalid Date';
    const s = shifted(this);
    return `${pad(s.getUTCHours())}:${pad(s.getUTCMinutes())}:${pad(s.getUTCSeconds())} ${gmt(this)} (${tzName(this)})`;
  };
  P.toString = function () { return isNaN(this) ? 'Invalid Date' : this.toDateString() + ' ' + this.toTimeString(); };
  // shortcut: setters (setHours…) and new Date(y,m,d) still use device-local time; shift them too if a site breaks.

  if (typeof navigator === 'undefined') return; // lets tests run this file in node

  // --- Language ---
  const NP = Object.getPrototypeOf(navigator);
  Object.defineProperty(NP, 'language', { get: () => 'en-US' });
  Object.defineProperty(NP, 'languages', { get: () => ['en-US', 'en'] });

  // --- Geolocation ---
  if (navigator.geolocation) {
    const pos = () => ({
      coords: { latitude: C.lat, longitude: C.lon, accuracy: 25, altitude: null, altitudeAccuracy: null, heading: null, speed: null },
      timestamp: Date.now(),
    });
    const G = Object.getPrototypeOf(navigator.geolocation);
    G.getCurrentPosition = (ok) => setTimeout(() => ok(pos()), 50);
    G.watchPosition = (ok) => { setTimeout(() => ok(pos()), 50); return 1; };
    G.clearWatch = () => {};
  }

  // --- WebRTC: block so the real IP can't leak over UDP ---
  for (const k of ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel']) {
    try { delete window[k]; window[k] = undefined; } catch (_) {}
  }
})();
