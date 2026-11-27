// Runs Sources/youtube.js against a fake YouTube page, wrapped exactly as Swift does.
// Run: node tests/youtube.test.js
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const src = fs.readFileSync(path.join(__dirname, '../Sources/youtube.js'), 'utf8');

function page(hostname, adblock) {
  class Document {}
  class HTMLMediaElement {}
  const listeners = {};
  const document = new Document();
  Object.assign(document, {
    addEventListener: (t, f) => { (listeners[t] ||= []).push(f); },
    createElement: () => ({}),
    documentElement: { appendChild() {} },
    querySelector: () => null,
    querySelectorAll: () => [],
  });
  const ctx = {
    location: { hostname }, document, Document, HTMLMediaElement,
    setTimeout: (f) => f(), setInterval: () => 0, Date,
    addEventListener: () => {},
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(`(P => {\n${src}\n})(${JSON.stringify({ adblock })});`, ctx);
  return { ctx, listeners, HTMLMediaElement };
}

// Ads are stripped from JSON responses and from the inline player data.
{
  const { ctx } = page('m.youtube.com', true);
  const r = vm.runInContext('JSON.parse(\'{"adPlacements":[1],"videoDetails":{"id":"x"},"playerResponse":{"playerAds":[1],"streamingData":{}}}\')', ctx);
  assert.deepStrictEqual(Object.keys(r).sort(), ['playerResponse', 'videoDetails']);
  assert.deepStrictEqual(Object.keys(r.playerResponse), ['streamingData']);
  vm.runInContext('var ytInitialPlayerResponse = { adSlots: [1], adBreakHeartbeatParams: "x", videoDetails: {} };', ctx);
  assert.deepStrictEqual(Object.keys(vm.runInContext('ytInitialPlayerResponse', ctx)), ['videoDetails']);
  assert.strictEqual(vm.runInContext('JSON.parse("[1,2]")', ctx).length, 2); // non-objects pass through
  assert.strictEqual(vm.runInContext('JSON.parse("null")', ctx), null);
}

// Page always looks visible, and iOS's background pause gets undone.
{
  const { ctx, listeners, HTMLMediaElement } = page('www.youtube.com', true);
  assert.strictEqual(ctx.document.hidden, false);
  assert.strictEqual(ctx.document.visibilityState, 'visible');

  let plays = 0;
  const v = Object.assign(new HTMLMediaElement(), { ended: false, paused: true, play: () => { plays++; return Promise.resolve(); } });
  ctx.__pbBg(true);
  listeners.pause[0]({ target: v }); // iOS pauses right after backgrounding
  assert.strictEqual(plays, 1);

  ctx.__pbBg(false);
  listeners.pause[0]({ target: v }); // user pauses in the foreground: leave it paused
  assert.strictEqual(plays, 1);
}

// Pause that happened just *before* the app told us it went to the background is also resumed.
{
  const { ctx, listeners, HTMLMediaElement } = page('m.youtube.com', false);
  let plays = 0;
  const v = Object.assign(new HTMLMediaElement(), { ended: false, paused: true, play: () => { plays++; return Promise.resolve(); } });
  listeners.pause[0]({ target: v });
  ctx.__pbBg(true);
  assert.strictEqual(plays, 1);
  // adblock off: JSON is untouched
  assert.ok('adPlacements' in vm.runInContext('JSON.parse(\'{"adPlacements":[1]}\')', ctx));
}

// Other sites are left completely alone.
{
  const { ctx } = page('notyoutube.com', true);
  assert.ok('adPlacements' in vm.runInContext('JSON.parse(\'{"adPlacements":[1]}\')', ctx));
  assert.strictEqual(ctx.__pbBg, undefined);
}

console.log('youtube.js OK');
