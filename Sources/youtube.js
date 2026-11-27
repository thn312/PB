// PB youtube.js: background playback + ad removal on YouTube.
// Swift wraps it as `(P => { ... })({adblock})`. The app downloads the latest copy of this file
// from GitHub on every connect, so a fix pushed here reaches the app without reinstalling.
(() => {
  if (!/(^|\.)youtube\.com$/.test(location.hostname)) return;

  // --- Background playback ---
  // YouTube pauses when the page looks hidden, so it always looks visible.
  for (const [k, v] of [['hidden', false], ['webkitHidden', false], ['visibilityState', 'visible'], ['webkitVisibilityState', 'visible']]) {
    try { Object.defineProperty(Document.prototype, k, { configurable: true, get: () => v }); } catch (_) {}
  }
  for (const t of ['visibilitychange', 'webkitvisibilitychange']) {
    window.addEventListener(t, (e) => e.stopImmediatePropagation(), true);
  }

  // iOS itself pauses <video> when the app goes to the background. The app calls __pbBg(true) at that
  // moment; a pause that lands within a few seconds of it is iOS, not the user, so we resume.
  let bg = false, bgAt = 0, lastPause = 0, lastVideo = null;
  const resume = (v) => setTimeout(() => { v.play().catch(() => {}); }, 300);
  document.addEventListener('pause', (e) => {
    const v = e.target;
    if (!(v instanceof HTMLMediaElement) || v.ended) return;
    lastPause = Date.now();
    lastVideo = v;
    if (bg && Date.now() - bgAt < 3000) resume(v);
  }, true);
  window.__pbBg = (on) => {
    bg = on;
    bgAt = Date.now();
    if (on && lastVideo && lastVideo.paused && Date.now() - lastPause < 1500) resume(lastVideo);
  };

  if (!P.adblock) return;

  // --- Ads: strip them from player data before the player reads it (same idea as uBlock's json-prune) ---
  const AD_KEYS = ['adPlacements', 'playerAds', 'adSlots', 'adBreakHeartbeatParams'];
  const prune = (o) => {
    if (o && typeof o === 'object') {
      for (const k of AD_KEYS) if (k in o) delete o[k];
      if (o.playerResponse) prune(o.playerResponse);
    }
    return o;
  };
  const parse = JSON.parse;
  JSON.parse = function () { return prune(parse.apply(this, arguments)); };
  if (typeof Response !== 'undefined') {
    const json = Response.prototype.json;
    Response.prototype.json = function () { return json.apply(this, arguments).then(prune); };
  }
  // The first video's data arrives as `var ytInitialPlayerResponse = {...}` in the HTML.
  let ipr;
  Object.defineProperty(window, 'ytInitialPlayerResponse', {
    configurable: true, get: () => ipr, set: (v) => { ipr = prune(v); },
  });

  // Ad boxes in feeds/search, banners, and the "ad blockers are not allowed" popup.
  const style = document.createElement('style');
  style.textContent = [
    'ytd-ad-slot-renderer', 'ytm-ad-slot-renderer', 'ad-slot-renderer', 'ytd-in-feed-ad-layout-renderer',
    'ytd-promoted-sparkles-web-renderer', 'ytm-promoted-sparkles-web-renderer', 'ytm-promoted-video-renderer',
    'ytm-companion-ad-renderer', 'ytd-banner-promo-renderer', '#masthead-ad', '.ytp-ad-overlay-container',
    'ytd-player-legacy-desktop-watch-ads-renderer', 'ytd-enforcement-message-view-model', 'tp-yt-iron-overlay-backdrop',
  ].join(',') + '{display:none!important}';
  document.documentElement.appendChild(style);

  // Anything that still gets through: mute, jump to the end, press Skip.
  let mutedByUs = null;
  setInterval(() => {
    const ad = document.querySelector('.ad-showing, .ad-interrupting');
    if (!ad) {
      if (mutedByUs) { mutedByUs.muted = false; mutedByUs = null; }
      return;
    }
    const v = ad.querySelector('video') || document.querySelector('video');
    if (v) {
      if (!v.muted) { v.muted = true; mutedByUs = v; }
      if (isFinite(v.duration) && v.duration > 0) v.currentTime = v.duration;
    }
    document.querySelectorAll('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytm-skip-ad-button, [class*="skip-ad"] button')
      .forEach((b) => b.click());
  }, 300);
})();
