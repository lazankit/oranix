// Oranix in-page player: puts Oranix-style controls on the page's main <video> (inline), with a
// full-window mode (same keys/gestures as the Oranix mpv setup). Also removes YouTube video ads.
// Injected into every frame by Oranix Browse, before the page's own scripts run.
(() => {
  if (window.__oranix) return;
  window.__oranix = true;

  // ---------- YouTube ad removal ----------
  // YouTube's video ads come from the same servers as the videos, so blocking requests can't stop
  // them. Instead, the ad schedule is deleted from the player data before the player reads it.
  if (/(^|\.)youtube(-nocookie)?\.com$/.test(location.hostname)) {
    const AD_KEYS = ['adPlacements', 'adSlots', 'playerAds', 'adBreakHeartbeatParams'];
    const prune = o => {
      if (o && typeof o === 'object') {
        for (const k of AD_KEYS) if (k in o) delete o[k];
        if (o.playerResponse) prune(o.playerResponse);
      }
      return o;
    };
    const parse = JSON.parse;
    JSON.parse = function () { return prune(parse.apply(this, arguments)); };
    const rjson = Response.prototype.json;
    Response.prototype.json = function () { return rjson.call(this).then(prune); };
    let initial;
    try {
      Object.defineProperty(window, 'ytInitialPlayerResponse', { configurable: true, get: () => initial, set: v => { initial = prune(v); } });
    } catch (_) {}

    const adCss = document.createElement('style');
    adCss.textContent = `#masthead-ad,#player-ads,ytd-ad-slot-renderer,ytd-in-feed-ad-layout-renderer,ytd-banner-promo-renderer,
ytd-promoted-sparkles-web-renderer,ytd-display-ad-renderer,ytd-companion-slot-renderer,.ytp-ad-module,.ytp-ad-overlay-container,
ytd-enforcement-message-view-model,tp-yt-iron-overlay-backdrop{display:none!important}`;
    // This runs before the page has an <html> element, so wait for one.
    const addAdCss = () => (document.head || document.documentElement).appendChild(adCss);
    if (document.documentElement) addAdCss();
    else new MutationObserver((_, o) => { if (document.documentElement) { o.disconnect(); addAdCss(); } }).observe(document, { childList: true });

    // Backup: if an ad still plays, mute it, jump to its end and press Skip; then restore sound/speed.
    let adState = null;
    setInterval(() => {
      const p = document.querySelector('.html5-video-player.ad-showing');
      const v = p && p.querySelector('video');
      if (v) {
        if (!adState) adState = { muted: v.muted, rate: v.playbackRate };
        v.muted = true;
        v.playbackRate = 16;
        if (isFinite(v.duration) && v.duration > 0) v.currentTime = Math.max(0, v.duration - 0.1);
        const skip = p.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern');
        if (skip) skip.click();
      } else if (adState) {
        const main = document.querySelector('.html5-video-player video');
        if (main) { main.muted = adState.muted; main.playbackRate = adState.rate; }
        adState = null;
      }
      // YouTube's "ad blockers are not allowed" dialog pauses the video; keep playing.
      if (document.querySelector('ytd-enforcement-message-view-model')) {
        const main = document.querySelector('.html5-video-player video');
        if (main && main.paused) main.play().catch(() => {});
      }
    }, 250);
  }

  const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
  const ICON = {
    play: 'M8 5v14l11-7z', pause: 'M6 19h4V5H6v14zm8-14v14h4V5h-4z',
    back: 'M11 18V6l-8.5 6 8.5 6zm.5-6 8.5 6V6l-8.5 6z', fwd: 'M4 18l8.5-6L4 6v12zm9-12v12l8.5-6L13 6z',
    next: 'M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z', prev: 'M6 6h2v12H6zm3.5 6 8.5 6V6z',
    backArrow: 'M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z',
    expand: 'M19 12h-2v3h-3v2h5v-5zM7 9h3V7H5v5h2V9zm14-6H3a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h18a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm0 16.01H3V4.99h18v14.02z',
    vol: 'M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 8v8a4.47 4.47 0 0 0 2.5-4z',
    speed: 'M20.38 8.57l-1.23 1.85a8 8 0 0 1-.22 7.58H5.07A8 8 0 0 1 15.58 6.85l1.85-1.23A10 10 0 0 0 3.35 19a2 2 0 0 0 1.72 1h13.85a2 2 0 0 0 1.74-1 10 10 0 0 0-.27-10.44zm-9.79 6.84a2 2 0 0 0 2.83 0l5.66-8.49-8.49 5.66a2 2 0 0 0 0 2.83z',
    subs: 'M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zM4 12h4v2H4v-2zm10 6H4v-2h10v2zm6 0h-4v-2h4v2zm0-4H10v-2h10v2z',
    full: 'M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z',
    close: 'M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
  };
  // DOM is built node-by-node: sites like YouTube enforce Trusted Types, which blocks innerHTML.
  const NS = 'http://www.w3.org/2000/svg';
  const svg = p => {
    const s = document.createElementNS(NS, 'svg'), path = document.createElementNS(NS, 'path');
    s.setAttribute('viewBox', '0 0 24 24'); path.setAttribute('d', p); s.appendChild(path);
    return s;
  };
  const h = (tag, cls, kids, attrs) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    for (const k in attrs || {}) e.setAttribute(k, attrs[k]);
    for (const c of [].concat(kids || [])) e.append(c);
    return e;
  };
  const fmt = s => {
    if (!isFinite(s)) return '0:00';
    s = Math.max(0, Math.floor(s));
    const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = String(s % 60).padStart(2, '0');
    return h ? `${h}:${String(m).padStart(2, '0')}:${x}` : `${m}:${x}`;
  };

  const CSS = `
:host{all:initial}
.wrap{position:fixed;z-index:2147483647;font-family:Poppins,'Segoe UI Variable Text','Segoe UI',sans-serif;color:#fff;cursor:default}
.wrap.full{inset:0}
.wrap.full .catch{touch-action:none}
.catch{-webkit-touch-callout:none;user-select:none;-webkit-user-select:none;-webkit-tap-highlight-color:transparent}
.boost{position:absolute;top:18px;left:50%;transform:translate(-50%,-6px);padding:6px 16px;border-radius:999px;font-size:14px;font-weight:600;
  background:rgba(31,31,31,.7);backdrop-filter:blur(14px);border:1px solid rgba(255,122,0,.5);color:#FF7A00;opacity:0;
  transition:opacity .12s,transform .12s;pointer-events:none}
.boost.on{opacity:1;transform:translate(-50%,0)}
/* Phones in portrait: keep the bar to the essentials (double-tap seeks, hardware keys do volume) */
@media (max-width:540px){[data-a=back],[data-a=fwd],[data-a=vol],[data-a=expand]{display:none}.time{margin:0 4px}}
/* Inline: the bar sits on the video inside the page, slightly smaller */
.wrap:not(.full) .top,.wrap:not(.full) .scrim.t{display:none}
.wrap:not(.full) .scrim.b{height:120px;border-radius:0 0 12px 12px}
.wrap:not(.full) .bar{left:10px;right:10px;bottom:10px;padding:6px 10px 4px;border-radius:13px}
.wrap:not(.full) .b{width:34px;height:34px;border-radius:10px}
.wrap:not(.full) .b svg{width:20px;height:20px}
.wrap:not(.full) .play{width:38px;height:38px;border-radius:50%}
.wrap:not(.full) .time{font-size:12px;margin:0 6px}
.wrap:not(.full) .prog{margin:4px 2px 7px}
.wrap:not(.full) .pop{bottom:72px;max-height:calc(100% - 92px)}
.wrap:not(.full) .upnext{bottom:72px}
.wrap.idle{cursor:none}
.catch{position:absolute;inset:0}
.top,.bar,.scrim{transition:opacity .14s cubic-bezier(.2,.8,.2,1),transform .18s cubic-bezier(.2,.8,.2,1)}
.idle .top,.idle .bar,.idle .scrim{opacity:0;pointer-events:none}
.idle .bar{transform:translateY(10px) scale(.99)}
.idle .top{transform:translateY(-8px)}
.scrim{position:absolute;left:0;right:0;pointer-events:none}
.scrim.t{top:0;height:120px;background:linear-gradient(rgba(0,0,0,.55),transparent)}
.scrim.b{bottom:0;height:200px;background:linear-gradient(transparent,rgba(0,0,0,.6))}
.top{position:absolute;left:18px;right:18px;top:14px;display:flex;align-items:center;gap:12px}
.brand{font-weight:700;font-size:16px;letter-spacing:.2px;display:flex;align-items:center;gap:8px}
.brand b{width:22px;height:22px;border-radius:7px;background:linear-gradient(135deg,#FFA94D,#F25C00);display:grid;place-items:center}
.brand b svg{width:14px;height:14px;fill:#fff}
.brand i{color:#FF7A00;font-style:normal}
.title{flex:1;font-size:14px;opacity:.9;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;text-shadow:0 1px 6px #000}
.bar{position:absolute;left:18px;right:18px;bottom:18px;padding:10px 14px 8px;border-radius:16px;
  background:rgba(31,31,31,.62);backdrop-filter:blur(18px) saturate(1.5);border:1px solid rgba(255,255,255,.09);
  box-shadow:0 10px 34px rgba(0,0,0,.45)}
.prog{position:relative;height:5px;border-radius:3px;background:rgba(255,255,255,.18);cursor:pointer;margin:4px 2px 10px;transition:height .12s}
.prog:hover{height:8px}
.prog::before{content:'';position:absolute;inset:-8px 0}
.buf,.fill{position:absolute;left:0;top:0;bottom:0;border-radius:3px}
.buf{background:rgba(255,255,255,.22)}
.fill{background:linear-gradient(90deg,#FFA94D,#FF7A00)}
.knob{position:absolute;top:50%;width:14px;height:14px;margin:-7px 0 0 -7px;border-radius:50%;background:#FF7A00;
  box-shadow:0 0 0 5px rgba(255,122,0,.22);transform:scale(.8);transition:transform .12s}
.prog:hover .knob{transform:scale(1)}
.tip{position:absolute;bottom:16px;transform:translateX(-50%);background:#1F1F1F;padding:3px 8px;border-radius:7px;font-size:12px;display:none;white-space:nowrap}
.prog:hover .tip{display:block}
.row{display:flex;align-items:center;gap:4px}
.b{width:38px;height:38px;border-radius:11px;display:grid;place-items:center;cursor:pointer;color:#fff;transition:background .12s,color .12s,transform .08s}
.b:hover{background:rgba(255,255,255,.1);color:#FF7A00}
.b:active{transform:scale(.92)}
.b svg{width:22px;height:22px;fill:currentColor}
.play{width:44px;height:44px;border-radius:50%;background:#FF7A00;margin-right:6px;box-shadow:0 4px 16px rgba(255,122,0,.4)}
.play:hover{background:#FF8F26;color:#fff}
.time{font-size:13px;opacity:.9;margin:0 10px;font-variant-numeric:tabular-nums}
.sp{flex:1}
.toast{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%) scale(.96);background:rgba(31,31,31,.7);backdrop-filter:blur(14px);
  padding:12px 20px;border-radius:16px;font-size:15px;opacity:0;transition:opacity .18s,transform .18s;display:flex;gap:14px;align-items:center;pointer-events:none}
.toast.show{opacity:1;transform:translate(-50%,-50%) scale(1)}
.meter{width:170px;height:6px;border-radius:3px;background:rgba(255,255,255,.2);overflow:hidden}
.meter>div{height:100%;background:linear-gradient(90deg,#FFA94D,#FF7A00);transition:width .1s}
.pop{position:absolute;right:18px;bottom:112px;min-width:250px;max-height:52vh;overflow:auto;background:rgba(31,31,31,.72);
  backdrop-filter:blur(18px) saturate(1.5);border:1px solid rgba(255,255,255,.1);border-radius:16px;padding:8px;
  box-shadow:0 12px 34px rgba(0,0,0,.5);animation:in .16s ease-out;scrollbar-width:thin;scrollbar-color:#FF7A00 transparent}
@keyframes in{from{opacity:0;transform:translateY(10px)}}
.h{font-size:11px;letter-spacing:2px;color:#8c8c8c;padding:8px 12px 4px;text-transform:uppercase}
.it{padding:8px 12px 8px 32px;border-radius:9px;cursor:pointer;font-size:14px;position:relative;color:#d6d6d6}
.it:hover,.it.hv{background:rgba(255,255,255,.1)}
.it.on{color:#fff;font-weight:600}
.it.on::before{content:'✓';position:absolute;left:12px;color:#FF7A00}
.backbtn{display:flex;align-items:center;gap:6px;padding:7px 14px 7px 10px;border-radius:999px;cursor:pointer;font-size:13px;font-weight:600;
  background:rgba(31,31,31,.6);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,.12);transition:background .12s,transform .08s}
.backbtn:hover{background:rgba(255,122,0,.9)}
.backbtn:active{transform:scale(.96)}
.backbtn svg{width:16px;height:16px;fill:currentColor}
.b:hover svg{filter:drop-shadow(0 0 6px rgba(255,122,0,.6))}
.b.off{opacity:.3;pointer-events:none}
.upnext{position:absolute;right:18px;bottom:120px;width:300px;padding:14px 16px;border-radius:16px;background:rgba(31,31,31,.8);
  backdrop-filter:blur(18px) saturate(1.5);border:1px solid rgba(255,255,255,.12);box-shadow:0 12px 34px rgba(0,0,0,.5);animation:in .2s ease-out}
.upnext .k{font-size:11px;letter-spacing:2px;color:#FF7A00;text-transform:uppercase;font-weight:600}
.upnext .n{font-size:15px;font-weight:600;margin:4px 0 12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.upnext .r{display:flex;gap:8px}
.upnext .go,.upnext .no{flex:1;text-align:center;padding:8px;border-radius:10px;cursor:pointer;font-size:13px;font-weight:600}
.upnext .go{background:#FF7A00}.upnext .go:hover{background:#FF8F26}
.upnext .no{background:rgba(255,255,255,.1)}.upnext .no:hover{background:rgba(255,255,255,.18)}
.upnext .ring{height:3px;border-radius:2px;background:rgba(255,255,255,.15);margin-top:12px;overflow:hidden}
.upnext .ring>div{height:100%;background:#FF7A00;width:100%;transition:width 5s linear}`;

  // Page-level rules. The whole page is hidden (visibility is inherited) and only the chosen
  // video - or the iframe that holds it - is made visible and pinned to the window. Hiding beats
  // stacking tricks: nothing the site draws can end up on top of the picture.
  const PAGE_CSS = `
html.oranix-on,html.oranix-on body{background:#000!important;overflow:hidden!important}
html.oranix-on body{visibility:hidden!important}
video[data-oranix],iframe[data-oranix-frame]{visibility:visible!important;position:fixed!important;left:0!important;top:0!important;
  right:auto!important;bottom:auto!important;width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;
  margin:0!important;border:0!important;z-index:2147483646!important;transform:none!important;opacity:1!important}
video[data-oranix]{object-fit:contain!important;background:#000!important}
[data-oranix-anc]{transform:none!important;filter:none!important;perspective:none!important;contain:none!important;
  will-change:auto!important;clip-path:none!important;mask:none!important;content-visibility:visible!important}
html.oranix-skin :is(.ytp-chrome-bottom,.ytp-chrome-top,.ytp-gradient-bottom,.ytp-gradient-top,.ytp-large-play-button,.ytp-pause-overlay,
  .jw-controlbar,.jw-display,.vjs-control-bar,.vjs-big-play-button,.plyr__controls,.plyr__control--overlaid,.fp-ui,.mejs__controls)
  {opacity:0!important;pointer-events:none!important}
html.oranix-on .ytp-caption-window-container{visibility:visible!important;position:fixed!important;left:0!important;top:0!important;
  width:100vw!important;height:calc(100vh - 110px)!important;z-index:2147483646!important;pointer-events:none!important}`;

  const TOP = window === window.top;
  let video = null, on = false, host, root, wrap, ui = {}, idleT = 0, tick = 0, pop = null, popItems = [], hover = 0;
  let level = 0, vol = 1, gain = null, actx = null, lastWheel = 0, pageStyle = null, preferredTrack = null;
  let enlargedFrame = null;   // child iframe currently pinned full-window (its video plays inside it)
  let nativeControls = false, wasIdle = false;

  // ---------- smart next / previous ----------
  // Finds "next episode"/playlist/next-page controls: YouTube's player buttons, rel=next/prev links,
  // or visible links/buttons whose text says next/previous (episode wording preferred).
  const NAV_WORDS = {
    next: /\b(next|up next|skip to next|following)\b(\s+(episode|ep\.?|video|part|chapter|lesson))?|^\s*(›|»|→)\s*$/i,
    prev: /\b(prev|previous|last)\b(\s+(episode|ep\.?|video|part|chapter|lesson))?|^\s*(‹|«|←)\s*$/i,
  };
  function findNav(dir) {
    const yt = document.querySelector(dir === 'next' ? '.ytp-next-button' : '.ytp-prev-button');
    if (yt && getComputedStyle(yt).display !== 'none' && (dir === 'next' || yt.getAttribute('aria-disabled') !== 'true'))
      return { el: yt, label: yt.getAttribute('data-tooltip-text') || yt.getAttribute('aria-label') || (dir === 'next' ? 'Next video' : 'Previous video') };
    const rel = document.querySelector('a[rel~=' + dir + '][href], link[rel~=' + dir + '][href]');
    let best = null, score = 0;
    for (const el of document.querySelectorAll('a[href], button, [role=button]')) {
      const text = (el.getAttribute('aria-label') || el.title || el.textContent || '').trim().replace(/\s+/g, ' ');
      if (!text || text.length > 60 || !NAV_WORDS[dir].test(text)) continue;
      const r = el.getBoundingClientRect();
      if (!r.width || !r.height || (el.tagName === 'A' && /^(#|javascript:)/.test(el.getAttribute('href')))) continue;
      const s = /episode|\bep\b/i.test(text) ? 3 : /video|part|chapter|lesson/i.test(text) ? 2 : 1;
      if (s > score) { best = el; score = s; }
    }
    if (best && (score > 1 || !rel)) return { el: best, label: (best.getAttribute('aria-label') || best.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 60) };
    if (rel) return { href: rel.href, label: dir === 'next' ? 'Next page' : 'Previous page' };
    return null;
  }
  // Labels shown in the bar. Inside an embedded player, the top page sends them down ("navinfo").
  let remoteNav = { next: '', prev: '' };
  function currentNav() {
    if (!TOP) return remoteNav;
    const n = findNav('next'), p = findNav('prev');
    return { next: n ? n.label : '', prev: p ? p.label : '' };
  }
  function goNav(dir) {
    if (!TOP) return top.postMessage({ oranix: 'go', dir: dir }, '*');
    const nav = findNav(dir);
    if (!nav) return toast('No ' + (dir === 'next' ? 'next' : 'previous') + ' video found');
    // From the full window, stay in the full window on the next page/video (inline re-skins by itself).
    if (on || enlargedFrame) {
      try { sessionStorage.setItem('oranix-continue', String(Date.now())); } catch (_) {}
      continueNext = true;
    }
    toast((dir === 'next' ? 'Next: ' : 'Previous: ') + nav.label);
    if (nav.el) nav.el.click(); else location.href = nav.href;
  }
  let continueNext = false;

  // Netflix-style "Up next" card when the video ends.
  let upnext = null, upnextT = 0;
  function showUpNext() {
    const nav = currentNav();
    if (!nav.next || upnext) return;
    const bar = h('div');
    const go = h('div', 'go', 'Play now'), no = h('div', 'no', 'Cancel');
    upnext = h('div', 'upnext', [h('div', 'k', 'Up next'), h('div', 'n', nav.next), h('div', 'r', [go, no]), h('div', 'ring', bar)]);
    wrap.appendChild(upnext);
    wake();
    requestAnimationFrame(() => requestAnimationFrame(() => bar.style.width = '0%'));
    const cancel = () => { clearTimeout(upnextT); if (upnext) upnext.remove(); upnext = null; };
    go.onclick = e => { e.stopPropagation(); cancel(); goNav('next'); };
    no.onclick = e => { e.stopPropagation(); cancel(); };
    upnextT = setTimeout(() => { cancel(); goNav('next'); }, 5000);
  }

  // Tell the browser window whether the player is open (its close button then just leaves the player).
  function notifyHost() {
    if (TOP && window.chrome && chrome.webview) chrome.webview.postMessage((on || enlargedFrame) ? 'player:on' : 'player:off');
  }

  function addPageStyle() {
    if (pageStyle) return;
    pageStyle = document.createElement('style');
    pageStyle.textContent = PAGE_CSS;
    (document.head || document.documentElement).appendChild(pageStyle);
  }
  function markAncestors(el) {
    for (let a = el.parentElement; a && a !== document.documentElement; a = a.parentElement) a.setAttribute('data-oranix-anc', '');
  }
  function clearPageMode() {
    document.querySelectorAll('[data-oranix-anc]').forEach(el => el.removeAttribute('data-oranix-anc'));
    document.documentElement.classList.remove('oranix-on');
  }

  const isPlaying = () => video && !video.paused && !video.ended;
  const english = t => /^en/i.test(t.language || '') || /english/i.test(t.label || '');

  // ---------- feedback ----------
  let toastT = 0;
  function toast(label, frac, value) {
    if (!ui.toast) return;
    if (frac == null) ui.toast.replaceChildren(label);
    else {
      const fill = h('div');
      fill.style.width = Math.round(Math.max(0, Math.min(1, frac)) * 100) + '%';
      ui.toast.replaceChildren(h('span', '', label), h('div', 'meter', fill), h('span', '', value));
    }
    ui.toast.classList.add('show');
    clearTimeout(toastT);
    toastT = setTimeout(() => ui.toast.classList.remove('show'), 1100);
  }

  // ---------- actions ----------
  const togglePlay = () => { isPlaying() ? video.pause() : video.play(); };
  const seek = d => { video.currentTime = Math.max(0, Math.min(video.duration || 1e9, video.currentTime + d)); toast((d > 0 ? '+' : '−') + Math.abs(d) + 's'); };

  function setVolume(v) {
    vol = Math.max(0, Math.min(2, Math.round(v * 100) / 100));
    if (vol > 1 && !gain) {
      // Boost above 100% through Web Audio (only engaged when needed; can't be undone per element).
      try {
        actx = new AudioContext();
        gain = actx.createGain();
        actx.createMediaElementSource(video).connect(gain).connect(actx.destination);
      } catch (e) { gain = null; vol = 1; }
    }
    video.muted = false;
    if (gain) { video.volume = 1; gain.gain.value = vol; actx.resume(); }
    else video.volume = Math.min(1, vol);
    toast('Volume', vol / 2, Math.round(vol * 100) + '%');
  }

  function setBrightness(d) {
    level = Math.max(-10, Math.min(10, level + d));
    const b = 1 + level * (level < 0 ? 0.05 : 0.03), c = 1 + (level < 0 ? -level * 0.012 : 0);
    video.style.setProperty('filter', `brightness(${b}) contrast(${c})`, 'important');
    toast('Brightness', (level + 10) / 20, (50 + level * 5) + '%');
  }

  function textTracks() {
    return [...(video.textTracks || [])].filter(t => t.kind === 'subtitles' || t.kind === 'captions')
      .sort((a, b) => english(b) - english(a));
  }
  // ---------- quality (when the site's player exposes it) ----------
  const YT_QUALITY = { hd2160: '2160p (4K)', hd1440: '1440p', hd1080: '1080p', hd720: '720p', large: '480p',
    medium: '360p', small: '240p', tiny: '144p', auto: 'Auto' };
  let qualityChoice = 'auto';
  function qualityApi() {
    const yt = document.getElementById('movie_player');
    if (yt && yt.getAvailableQualityLevels) {
      const levels = yt.getAvailableQualityLevels();
      if (levels && levels.length) return {
        list: levels.map(id => ({ id: id, label: YT_QUALITY[id] || id })),
        current: levels.includes(qualityChoice) ? qualityChoice : 'auto',
        set: id => { yt.setPlaybackQualityRange(id, id); if (yt.setPlaybackQuality) yt.setPlaybackQuality(id); },
      };
    }
    const jw = typeof window.jwplayer === 'function' && window.jwplayer();
    if (jw && jw.getQualityLevels) {
      const levels = jw.getQualityLevels() || [];
      if (levels.length > 1) return {
        list: levels.map((x, i) => ({ id: i, label: x.label || 'Level ' + (i + 1) })),
        current: jw.getCurrentQuality(),
        set: i => jw.setCurrentQuality(i),
      };
    }
    return null;
  }

  const siteCC = () => document.querySelector('.ytp-subtitles-button, button[aria-label*="ubtitle" i], button[aria-label*="aption" i]');

  function toggleCaptions() {
    const tracks = textTracks();
    if (tracks.length) {
      const showing = tracks.find(t => t.mode === 'showing');
      if (showing) { tracks.forEach(t => t.mode = 'disabled'); toast('Subtitles: Off'); }
      else { const t = preferredTrack && tracks.includes(preferredTrack) ? preferredTrack : tracks[0]; t.mode = 'showing'; toast('Subtitles: ' + (t.label || t.language)); }
      return;
    }
    const b = siteCC();
    if (b) { b.click(); toast('Subtitles: ' + (b.getAttribute('aria-pressed') === 'true' ? 'On' : 'Off')); }
    else toast('No subtitles on this video');
  }

  // In an iframe without fullscreen permission, ask the parent (the click's activation reaches ancestors).
  function toggleFullscreen() {
    if (document.fullscreenElement) return document.exitFullscreen();
    document.documentElement.requestFullscreen().catch(() => { if (!TOP) parent.postMessage({ oranix: 'fs' }, '*'); });
  }

  // ---------- popups (speed / subtitles & audio) ----------
  function openPop(kind) {
    if (pop && pop.dataset.kind === kind) return closePop();
    closePop();
    pop = document.createElement('div');
    pop.className = 'pop';
    pop.dataset.kind = kind;
    popItems = [];
    const add = (label, on, fn) => {
      const el = document.createElement('div');
      el.className = 'it' + (on ? ' on' : '');
      el.textContent = label;
      el.onclick = e => { e.stopPropagation(); fn(); closePop(); openPop(kind); };   // re-render with new ticks
      el.onmouseenter = () => { hover = popItems.indexOf(el); paintHover(); };
      pop.appendChild(el); popItems.push(el);
    };
    const head = t => { const h = document.createElement('div'); h.className = 'h'; h.textContent = t; pop.appendChild(h); };
    if (kind === 'speed') {
      const q = qualityApi();
      if (q) {
        head('Quality');
        q.list.forEach(x => add(x.label, x.id === q.current, () => { q.set(x.id); qualityChoice = x.id; toast('Quality: ' + x.label); }));
      }
      head('Playback speed');
      SPEEDS.forEach(s => add(s === 1 ? '1× (Normal)' : s + '×', Math.abs(video.playbackRate - s) < .01, () => { video.playbackRate = s; toast('Speed ' + s + '×'); }));
    } else {
      const audio = [...(video.audioTracks || [])];
      if (audio.length > 1) {
        head('Audio');
        audio.forEach(a => add(a.label || a.language || 'Track', a.enabled, () => audio.forEach(x => x.enabled = x === a)));
      }
      head('Subtitles');
      const tracks = textTracks();
      if (tracks.length) {
        add('Off', !tracks.some(t => t.mode === 'showing'), () => tracks.forEach(t => t.mode = 'disabled'));
        tracks.forEach(t => add(t.label || t.language || 'Track', t.mode === 'showing', () => {
          tracks.forEach(x => x.mode = x === t ? 'showing' : 'disabled'); preferredTrack = t;
        }));
      } else if (siteCC()) {
        const onNow = siteCC().getAttribute('aria-pressed') === 'true';
        add('Off', !onNow, () => { if (siteCC().getAttribute('aria-pressed') === 'true') siteCC().click(); });
        add('On (site captions)', onNow, () => { if (siteCC().getAttribute('aria-pressed') !== 'true') siteCC().click(); });
      } else {
        add('None available', false, () => {});
      }
    }
    hover = Math.max(0, popItems.findIndex(e => e.classList.contains('on')));
    paintHover();
    wrap.appendChild(pop);
  }
  function closePop() { if (pop) { pop.remove(); pop = null; } }
  function paintHover() { popItems.forEach((e, i) => e.classList.toggle('hv', i === hover)); popItems[hover] && popItems[hover].scrollIntoView({ block: 'nearest' }); }

  // ---------- UI ----------
  function build() {
    host = document.createElement('oranix-player');
    root = host.attachShadow({ mode: 'closed' });
    const btn = (a, icon, tip, cls) => h('div', 'b' + (cls ? ' ' + cls : ''), svg(icon), { 'data-a': a, title: tip });
    const style = document.createElement('style');
    style.textContent = CSS;
    const back = h('div', 'backbtn', [svg(ICON.backArrow), 'Back to page'], { 'data-a': 'close', title: 'Back to page (Esc)' });
    wrap = h('div', 'wrap', [
      h('div', 'catch'),
      h('div', 'scrim t'), h('div', 'scrim b'),
      h('div', 'top', [
        back,
        h('div', 'brand', [h('b', '', svg(ICON.play)), h('span', '', ['Oran', h('i', '', 'ix')])]),
        h('div', 'title'),
      ]),
      h('div', 'toast'),
      h('div', 'boost', '2×  ▸▸'),
      h('div', 'bar', [
        h('div', 'prog', [h('div', 'buf'), h('div', 'fill'), h('div', 'knob'), h('div', 'tip')]),
        h('div', 'row', [
          btn('prev', ICON.prev, 'Previous (Shift+P)'),
          btn('play', ICON.play, 'Play/Pause (Space)', 'play'),
          btn('next', ICON.next, 'Next (Shift+N)'),
          btn('back', ICON.back, 'Back 10s (←)'),
          btn('fwd', ICON.fwd, 'Forward 10s (→)'),
          btn('vol', ICON.vol, 'Mute (volume: ↑/↓ or scroll right side)'),
          h('div', 'time'),
          h('div', 'sp'),
          btn('speed', ICON.speed, 'Quality & speed (X)'),
          btn('subs', ICON.subs, 'Subtitles & audio (S) · on/off (C)'),
          btn('expand', ICON.expand, 'Oranix full window (O)'),
          btn('full', ICON.full, 'Fullscreen (F)'),
        ]),
      ]),
    ]);
    root.append(style, wrap);
    ['catch', 'title', 'toast', 'boost', 'prog', 'buf', 'fill', 'knob', 'tip', 'time'].forEach(c => ui[c] = root.querySelector('.' + c));
    ui.play = root.querySelector('[data-a=play]');
    ui.next = root.querySelector('[data-a=next]');
    ui.prev = root.querySelector('[data-a=prev]');

    const actions = {
      play: togglePlay, back: () => seek(-10), fwd: () => seek(10), close: exit, full: goFullscreen,
      expand: () => on ? exit() : enter(video),
      speed: () => openPop('speed'), subs: () => openPop('subs'),
      vol: () => { video.muted = !video.muted; toast(video.muted ? 'Muted' : 'Volume ' + Math.round(vol * 100) + '%'); },
      next: () => goNav('next'), prev: () => goNav('prev'),
    };
    root.querySelectorAll('[data-a]').forEach(b => b.addEventListener('click', e => { e.stopPropagation(); actions[b.dataset.a](); }));

    // A tap while the controls are hidden only brings them back; a tap while they show plays/pauses.
    let clickT = 0;
    let lastPointer = 'mouse';
    ui.catch.addEventListener('pointerdown', e => { lastPointer = e.pointerType; wasIdle = wrap.classList.contains('idle'); wake(); });
    // Touch (phones), full window: drag sideways to seek, up/down on the left = brightness, right = volume.
    let touch = null, dragged = false;
    ui.catch.addEventListener('pointerdown', e => {
      if (e.pointerType === 'touch' && on) touch = { x: e.clientX, y: e.clientY, last: e.clientY, mode: null, target: video.currentTime };
    });
    ui.catch.addEventListener('pointermove', e => {
      if (!touch || e.pointerType !== 'touch') return;
      const dx = e.clientX - touch.x, dy = e.clientY - touch.y;
      if (!touch.mode) {
        if (Math.abs(dx) > 18) touch.mode = 'seek';
        else if (Math.abs(dy) > 18) touch.mode = touch.x < innerWidth / 2 ? 'bright' : 'vol';
        else return;
      }
      if (touch.mode === 'seek') {   // a full-width swipe = 90 s; the jump happens on release
        touch.target = Math.max(0, Math.min(video.duration || 0, video.currentTime + dx / innerWidth * 90));
        toast((dx > 0 ? '+' : '−') + fmt(Math.abs(touch.target - video.currentTime)) + '  →  ' + fmt(touch.target));
      } else {
        const steps = Math.trunc((touch.last - e.clientY) / (innerHeight / 20));
        if (steps) { touch.last = e.clientY; touch.mode === 'bright' ? setBrightness(steps) : setVolume(vol + steps * 0.05); }
      }
    });
    ['pointerup', 'pointercancel'].forEach(t => ui.catch.addEventListener(t, () => {
      if (touch && touch.mode) { dragged = true; if (touch.mode === 'seek') video.currentTime = touch.target; }
      touch = null;
    }));

    // Long-press (touch): play at 2x while the finger stays down, like YouTube.
    let pressT = 0, pressAt = null, boosted = null;
    const endPress = () => {
      clearTimeout(pressT);
      pressAt = null;
      if (boosted !== null) { video.playbackRate = boosted; boosted = null; ui.boost.classList.remove('on'); }
    };
    ui.catch.addEventListener('pointerdown', e => {
      if (e.pointerType !== 'touch') return;
      pressAt = [e.clientX, e.clientY];
      clearTimeout(pressT);
      pressT = setTimeout(() => {
        boosted = video.playbackRate;
        video.playbackRate = 2;
        if (video.paused) video.play();
        dragged = true;   // releasing isn't a tap
        ui.boost.classList.add('on');
      }, 450);
    });
    ui.catch.addEventListener('pointermove', e => {
      if (pressAt && Math.hypot(e.clientX - pressAt[0], e.clientY - pressAt[1]) > 12) clearTimeout(pressT);
    });
    ['pointerup', 'pointercancel', 'pointerleave'].forEach(t => ui.catch.addEventListener(t, endPress));
    ui.catch.addEventListener('contextmenu', e => e.preventDefault());

    // Pinch (touch, full window): spread = zoom the picture to fill a tall phone screen, pinch = fit it again.
    const fingers = new Map();
    let pinchFrom = 0;
    const spread = () => { const [a, b] = [...fingers.values()]; return Math.hypot(a[0] - b[0], a[1] - b[1]); };
    ui.catch.addEventListener('pointerdown', e => {
      if (e.pointerType !== 'touch') return;
      fingers.set(e.pointerId, [e.clientX, e.clientY]);
      if (fingers.size === 2) { pinchFrom = spread(); touch = null; endPress(); dragged = true; }
    });
    ui.catch.addEventListener('pointermove', e => {
      if (!fingers.has(e.pointerId)) return;
      fingers.set(e.pointerId, [e.clientX, e.clientY]);
      if (fingers.size !== 2 || !pinchFrom || !on) return;
      const ratio = spread() / pinchFrom;
      if (ratio > 1.2 || ratio < 0.83) {
        const fill = ratio > 1;
        video.style.setProperty('object-fit', fill ? 'cover' : 'contain', 'important');
        toast(fill ? 'Zoom to fill' : 'Fit to screen');
        pinchFrom = 0;
      }
    });
    ['pointerup', 'pointercancel'].forEach(t => ui.catch.addEventListener(t, e => { fingers.delete(e.pointerId); if (fingers.size < 2) pinchFrom = 0; }));

    ui.catch.addEventListener('click', e => {
      if (dragged) { dragged = false; return; }   // the end of a swipe isn't a tap
      if (pop) return closePop();
      // Site buttons under the video (skip ad, end-screen links...) still get the click.
      const t = siteTarget(e.clientX, e.clientY);
      if (t) return t.click();
      if (wasIdle) return;
      clearTimeout(clickT);
      clickT = setTimeout(togglePlay, 220);   // wait to see if it's a double-click
    });
    // Double-tap on a touchscreen: left third = back 10 s, right third = forward 10 s, middle = fullscreen.
    // Double-click with a mouse/touchpad stays fullscreen.
    ui.catch.addEventListener('dblclick', e => {
      clearTimeout(clickT);
      if (lastPointer === 'touch') {
        const r = ui.catch.getBoundingClientRect(), x = (e.clientX - r.left) / r.width;
        if (x < 1 / 3) return seek(-10);
        if (x > 2 / 3) return seek(10);
      }
      goFullscreen();
    });

    const frac = e => { const r = ui.prog.getBoundingClientRect(); return Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)); };
    let dragging = false;
    ui.prog.addEventListener('mousedown', e => { dragging = true; video.currentTime = frac(e) * video.duration; e.stopPropagation(); });
    addEventListener('mouseup', () => dragging = false, true);
    ui.prog.addEventListener('mousemove', e => {
      const f = frac(e);
      ui.tip.style.left = f * 100 + '%';
      ui.tip.textContent = fmt(f * video.duration);
      if (dragging) video.currentTime = f * video.duration;
    });

    wrap.addEventListener('pointermove', wake);
    wrap.addEventListener('pointerleave', () => { if (!on && isPlaying() && !pop) wrap.classList.add('idle'); });
    wrap.addEventListener('pointerdown', wake, true);
    // Two-finger scroll: vertical = brightness (left half) / volume (right half); sideways = seek 1s.
    // Directions match the user's Oranix mpv setup (natural touchpad direction).
    wrap.addEventListener('wheel', e => {
      if (pop && pop.contains(e.composedPath()[0])) return;
      // Inline on a page: up/down scrolls the page as usual; only sideways swipes seek.
      if (!on && Math.abs(e.deltaY) >= Math.abs(e.deltaX)) return;
      e.preventDefault();
      const now = performance.now();
      if (now - lastWheel < 100) return;
      lastWheel = now;
      if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) return seek(e.deltaX > 0 ? -1 : 1);
      const d = e.deltaY > 0 ? 1 : -1;
      if (e.clientX < innerWidth / 2) setBrightness(d); else setVolume(vol + d * 0.02);
    }, { passive: false });
  }

  function wake() {
    wrap.classList.remove('idle');
    clearTimeout(idleT);
    idleT = setTimeout(() => { if (isPlaying() && !pop) wrap.classList.add('idle'); }, 2500);
  }

  function update() {
    if (!skinned) return;
    const d = video.duration || 0, t = video.currentTime || 0;
    const f = d ? t / d : 0;
    ui.fill.style.width = f * 100 + '%';
    ui.knob.style.left = f * 100 + '%';
    let buf = 0;
    for (let i = 0; i < video.buffered.length; i++) if (video.buffered.start(i) <= t) buf = video.buffered.end(i);
    ui.buf.style.width = (d ? buf / d * 100 : 0) + '%';
    ui.time.textContent = `${fmt(t)}  /  −${fmt(d - t)}`;
    ui.play.querySelector('path').setAttribute('d', isPlaying() ? ICON.pause : ICON.play);
    ui.title.textContent = document.title.replace(/^\(\d+\)\s*/, '').replace(/ - YouTube$/, '');
    const nav = currentNav();
    ui.next.classList.toggle('off', !nav.next);
    ui.prev.classList.toggle('off', !nav.prev);
    ui.next.title = nav.next ? 'Next: ' + nav.next + ' (Shift+N)' : 'No next video found';
    ui.prev.title = nav.prev ? 'Previous: ' + nav.prev + ' (Shift+P)' : 'No previous video found';
  }

  // ---------- keys (same as Oranix mpv) ----------
  function onKey(e) {
    const t = e.target;
    const typing = t && (t.isContentEditable || /input|textarea|select/i.test(t.tagName));
    if (typing || e.ctrlKey || e.altKey || e.metaKey) return;
    if (e.key === 'o' || e.key === 'O') {
      e.preventDefault();
      e.stopImmediatePropagation();
      if (on || skinned) on ? exit() : enter(video);
      else if (TOP) window.__oranixToggle(); else top.postMessage({ oranix: 'toggle' }, '*');
      return;
    }
    // Player keys work in full window, or inline while the skinned video is on screen.
    if (!on && !(skinned && wrap.style.display !== 'none')) return;
    const k = e.key;
    const map = {
      ' ': togglePlay, k: togglePlay, ArrowLeft: () => seek(e.shiftKey ? -30 : -5), ArrowRight: () => seek(e.shiftKey ? 30 : 5),
      ArrowUp: () => pop ? (hover = Math.max(0, hover - 1), paintHover()) : setVolume(vol + .05),
      ArrowDown: () => pop ? (hover = Math.min(popItems.length - 1, hover + 1), paintHover()) : setVolume(vol - .05),
      Enter: () => pop ? popItems[hover] && popItems[hover].click() : goFullscreen(),
      N: () => goNav('next'), P: () => goNav('prev'),
      n: () => setBrightness(-1), m: () => setBrightness(1), c: toggleCaptions, s: () => openPop('subs'), a: () => openPop('subs'),
      x: () => openPop('speed'), f: goFullscreen,
      Escape: () => pop ? closePop() : document.fullscreenElement ? document.exitFullscreen() : on ? exit() : null,
      '[': () => { video.playbackRate = Math.max(.25, video.playbackRate - .25); toast('Speed ' + video.playbackRate + '×'); },
      ']': () => { video.playbackRate = Math.min(4, video.playbackRate + .25); toast('Speed ' + video.playbackRate + '×'); },
      Backspace: () => { video.playbackRate = 1; toast('Speed 1×'); },
    };
    const fn = map[k] || map[k.toLowerCase()];
    if (!fn) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    fn();
    wake();
  }

  // ---------- inline skin: the Oranix bar on top of a video, right where it sits on the page ----------
  let skinned = false, placeRAF = 0, lastRect = '';

  function attach(v) {
    if (skinned && video === v) return;
    if (skinned) detach();
    video = v;
    skinned = true;
    addPageStyle();
    document.documentElement.classList.add('oranix-skin');   // hides the site's own control bar
    nativeControls = v.controls;
    v.controls = false;
    if (!host) build();
    wrap.classList.remove('full');
    document.documentElement.appendChild(host);
    vol = gain ? vol : (v.muted ? 0 : v.volume);
    v.addEventListener('ended', showUpNext);
    tick = setInterval(update, 250);
    lastRect = '';
    placeRAF = requestAnimationFrame(place);
    update(); wake();
  }

  function detach() {
    if (!skinned) return;
    if (on) exit();
    skinned = false;
    closePop();
    clearInterval(tick);
    cancelAnimationFrame(placeRAF);
    video.controls = nativeControls;
    video.removeEventListener('ended', showUpNext);
    if (upnext) { clearTimeout(upnextT); upnext.remove(); upnext = null; }
    document.documentElement.classList.remove('oranix-skin');
    host.remove();
  }

  // Keep the overlay glued to the video while the page scrolls or resizes.
  function place() {
    placeRAF = requestAnimationFrame(place);
    if (on) return;
    const r = video.getBoundingClientRect();
    const show = video.isConnected && r.width >= 200 && r.height >= 110 && r.bottom > 0 && r.top < innerHeight;
    const key = show ? [r.left, r.top, r.width, r.height].map(Math.round).join() : 'hidden';
    if (key === lastRect) return;
    lastRect = key;
    if (!show) { wrap.style.display = 'none'; return; }
    Object.assign(wrap.style, { display: '', left: r.left + 'px', top: r.top + 'px', width: r.width + 'px', height: r.height + 'px' });
  }

  // The page's main video: big, not a hover preview inside a link.
  function mainVideo() {
    let best = null, area = 0;
    for (const v of document.querySelectorAll('video')) {
      if (v.closest('a') || !(v.currentSrc || v.readyState > 0)) continue;
      const r = v.getBoundingClientRect();
      if (r.width < Math.min(400, innerWidth * 0.8) || r.height < 150) continue;   // phones: ~full-width players count
      if (r.width * r.height > area) { best = v; area = r.width * r.height; }
    }
    return best;
  }
  function autoSkin() {
    if (on) return;
    const v = mainVideo();
    if (v) attach(v);
    else if (skinned && !video.isConnected) detach();
  }

  // Interactive site element under a click (ignoring the video and the player box that holds it).
  function siteTarget(x, y) {
    for (const el of document.elementsFromPoint(x, y)) {
      if (el === host || el === video) continue;
      const t = el.closest('a[href], button, [role=button]');
      if (t && !t.contains(video)) return t;
    }
    return null;
  }

  // ---------- full window (and fullscreen) ----------
  function goFullscreen() {
    if (!on) enter(video);
    toggleFullscreen();
  }

  function enter(v) {
    if (on) return;
    attach(v);
    on = true;
    markAncestors(v);
    v.setAttribute('data-oranix', '');
    document.documentElement.classList.add('oranix-on');
    wrap.classList.add('full');
    wrap.removeAttribute('style');
    lastRect = '';
    wake();
    renderDetector();
    notifyHost();
    dispatchEvent(new Event('resize'));
  }

  // Leave the full window: back to the page, with the bar still on the video.
  function exit() {
    if (!on) return;
    on = false;
    closePop();
    video.removeAttribute('data-oranix');
    video.style.removeProperty('object-fit');   // undo pinch zoom
    clearPageMode();
    wrap.classList.remove('full');
    if (document.fullscreenElement) document.exitFullscreen();
    if (!TOP) parent.postMessage({ oranix: 'exited' }, '*');
    renderDetector();
    notifyHost();
    dispatchEvent(new Event('resize'));
  }

  // ---------- video detector ----------
  // Every frame lists its own videos and reports them (plus its children's) to its parent, so the
  // top page knows every video on the page, even inside embedded players from other sites.
  let nextId = 1, lastSig = '', childVideos = new Map();
  const idOf = v => v.dataset.oranixId || (v.dataset.oranixId = String(nextId++));
  const frames = () => [...document.querySelectorAll('iframe')];

  function localVideos() {
    return [...document.querySelectorAll('video')].filter(v => {
      const r = v.getBoundingClientRect();
      return (v.currentSrc || v.readyState > 0) && r.width >= 120 && r.height >= 60 && v.duration > 3;
    }).map(v => ({
      id: idOf(v), path: [],
      label: (v.getAttribute('aria-label') || v.title || document.title || location.hostname).trim().slice(0, 70),
      host: location.hostname.replace(/^www\./, ''),
      w: v.videoWidth || 0, h: v.videoHeight || 0, dur: v.duration, playing: !v.paused && !v.ended,
    }));
  }
  const allVideos = () => localVideos().concat(...childVideos.values());

  function report() {
    if (TOP) return renderDetector();
    const list = allVideos(), sig = JSON.stringify(list);
    if (sig !== lastSig) { lastSig = sig; parent.postMessage({ oranix: 'report', videos: list }, '*'); }
  }

  // Play a video by its path of iframe indexes: pin each iframe on the way down, then enter in the last frame.
  function playPath(path, id) {
    if (!path.length) {
      const v = document.querySelector('video[data-oranix-id="' + id + '"]');
      if (v) { enter(v); if (v.paused) v.play().catch(() => {}); }
      return;
    }
    const f = frames()[path[0]];
    if (!f) return;
    addPageStyle();
    markAncestors(f);
    f.setAttribute('data-oranix-frame', '');
    document.documentElement.classList.add('oranix-on');
    enlargedFrame = f;
    renderDetector();
    notifyHost();
    f.contentWindow.postMessage({ oranix: 'play', path: path.slice(1), id: id }, '*');
    sendNavInfo();
  }
  function restoreFrame() {
    if (!enlargedFrame) return;
    enlargedFrame.removeAttribute('data-oranix-frame');
    enlargedFrame = null;
    clearPageMode();
    renderDetector();
    notifyHost();
  }
  // Pass next/previous labels down to the embedded player that is showing.
  function sendNavInfo(info) {
    if (!enlargedFrame) return;
    enlargedFrame.contentWindow.postMessage({ oranix: 'navinfo', nav: info || currentNav() }, '*');
  }

  addEventListener('message', e => {
    const d = e.data;
    if (!d || typeof d !== 'object' || !d.oranix) return;
    const idx = frames().findIndex(f => f.contentWindow === e.source);
    if (d.oranix === 'report' && idx >= 0 && Array.isArray(d.videos)) {
      childVideos.set(idx, d.videos.map(v => Object.assign({}, v, { path: [idx].concat(v.path) })));
      report();
    } else if (d.oranix === 'play' && e.source === parent && Array.isArray(d.path)) {
      playPath(d.path, d.id);
    } else if (d.oranix === 'stop' && e.source === parent) {
      if (on) exit(); else if (enlargedFrame) { enlargedFrame.contentWindow.postMessage({ oranix: 'stop' }, '*'); restoreFrame(); }
    } else if (d.oranix === 'exited' && idx >= 0) {
      restoreFrame();
      if (!TOP) parent.postMessage({ oranix: 'exited' }, '*');
    } else if (d.oranix === 'fs' && idx >= 0) {
      toggleFullscreen();
    } else if (d.oranix === 'toggle' && TOP) {
      window.__oranixToggle();
    } else if (d.oranix === 'go' && idx >= 0 && (d.dir === 'next' || d.dir === 'prev')) {
      if (TOP) goNav(d.dir); else parent.postMessage(d, '*');
    } else if (d.oranix === 'navinfo' && e.source === parent && d.nav) {
      remoteNav = { next: String(d.nav.next || ''), prev: String(d.nav.prev || '') };
      sendNavInfo(remoteNav);
    }
  });

  // Floating "Watch in Oranix" pill + chooser (top page only).
  const DETECT_CSS = `
:host{all:initial}
.pill{position:fixed;top:14px;right:18px;z-index:2147483647;display:flex;align-items:center;gap:10px;padding:8px 14px 8px 8px;
  border-radius:999px;background:rgba(31,31,31,.78);backdrop-filter:blur(16px) saturate(1.5);border:1px solid rgba(255,255,255,.1);
  color:#fff;font:600 13px Poppins,'Segoe UI',sans-serif;cursor:pointer;box-shadow:0 8px 26px rgba(0,0,0,.45);animation:in .2s ease-out}
.pill:hover{background:rgba(45,45,45,.9)}
.dot{width:30px;height:30px;border-radius:50%;background:#FF7A00;display:grid;place-items:center}
.dot svg{width:16px;height:16px;fill:#fff}
.live .dot{animation:pulse 1.6s infinite}
@keyframes pulse{0%{box-shadow:0 0 0 0 rgba(255,122,0,.6)}70%{box-shadow:0 0 0 10px rgba(255,122,0,0)}100%{box-shadow:0 0 0 0 rgba(255,122,0,0)}}
@keyframes in{from{opacity:0;transform:translateY(-6px)}}
.n{background:#FF7A00;border-radius:999px;padding:1px 8px;font-size:12px}
.list{position:fixed;top:62px;right:18px;z-index:2147483647;width:340px;max-height:60vh;overflow:auto;padding:8px;border-radius:16px;
  background:rgba(31,31,31,.85);backdrop-filter:blur(18px) saturate(1.5);border:1px solid rgba(255,255,255,.1);
  box-shadow:0 12px 34px rgba(0,0,0,.5);font:13px Poppins,'Segoe UI',sans-serif;color:#ddd;animation:in .16s ease-out}
.h{font-size:11px;letter-spacing:2px;color:#8c8c8c;padding:8px 12px 6px;text-transform:uppercase}
.v{padding:9px 12px;border-radius:10px;cursor:pointer}
.v:hover{background:rgba(255,255,255,.1);color:#fff}
.t{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.m{font-size:12px;color:#9a9a9a;margin-top:2px}
.m b{color:#FF7A00;font-weight:600}`;
  let dHost = null, dRoot = null, listOpen = false, dSig = '';

  function playEntry(v) { listOpen = false; playPath(v.path, v.id); }

  function renderDetector() {
    if (!TOP) return;
    const vids = (on || enlargedFrame) ? [] : allVideos()
      .sort((a, b) => (b.playing - a.playing) || (b.w * b.h - a.w * a.h));
    // A single video already has the Oranix bar on it; the pill is for choosing between several.
    if (vids.length < 2) { if (dHost) dHost.remove(); listOpen = false; dSig = ''; return; }
    const sig = JSON.stringify(vids) + listOpen;   // only redraw when something changed (no flicker)
    if (sig === dSig && dHost && dHost.isConnected) return;
    dSig = sig;
    if (!dHost) {
      dHost = document.createElement('oranix-detector');
      dRoot = dHost.attachShadow({ mode: 'closed' });
    }
    if (!dHost.isConnected) document.documentElement.appendChild(dHost);
    const style = document.createElement('style');
    style.textContent = DETECT_CSS;
    const pill = h('div', 'pill' + (vids.some(v => v.playing) ? ' live' : ''), [
      h('div', 'dot', svg(ICON.play)),
      vids.length === 1 ? 'Watch in Oranix' : 'Videos on this page',
      vids.length > 1 ? h('span', 'n', String(vids.length)) : '',
    ]);
    pill.onclick = () => { if (vids.length === 1) playEntry(vids[0]); else { listOpen = !listOpen; renderDetector(); } };
    const kids = [style, pill];
    if (listOpen && vids.length > 1) {
      kids.push(h('div', 'list', [h('div', 'h', 'Choose a video')].concat(vids.map(v => {
        const meta = h('div', 'm', [
          v.playing ? h('b', '', '● Playing  ') : '',
          (v.h ? v.w + '×' + v.h + '  ·  ' : '') + (isFinite(v.dur) ? fmt(v.dur) : 'Live') + '  ·  ' + v.host,
        ]);
        const row = h('div', 'v', [h('div', 't', v.label), meta]);
        row.onclick = () => playEntry(v);
        return row;
      }))));
    }
    dRoot.replaceChildren(...kids);
  }

  // Host toolbar button / O key: leave the player, or play the only video, or open the chooser.
  window.__oranixToggle = () => {
    if (on) { exit(); return false; }
    if (enlargedFrame) { enlargedFrame.contentWindow.postMessage({ oranix: 'stop' }, '*'); restoreFrame(); return false; }
    if (skinned) { enter(video); return true; }
    const vids = allVideos();
    if (!vids.length) return null;
    if (vids.length === 1) playEntry(vids[0]); else { listOpen = true; renderDetector(); }
    return true;
  };

  addEventListener('keydown', onKey, true);
  setInterval(() => { report(); if (TOP && enlargedFrame) sendNavInfo(); }, 1500);
  setInterval(autoSkin, 1000);
  ['loadedmetadata', 'play'].forEach(t => document.addEventListener(t, () => setTimeout(autoSkin, 0), true));
  ['play', 'pause', 'loadedmetadata'].forEach(t => document.addEventListener(t, () => setTimeout(report, 50), true));

  // Videos play inline with the Oranix bar (autoSkin). The full window opens on its own only when
  // the next video starts after Next/Previous was pressed from the full window.
  document.addEventListener('play', e => {
    const v = e.target;
    if (!TOP || on || enlargedFrame || !(v instanceof HTMLVideoElement)) return;
    if (continueNext && v.getBoundingClientRect().width >= 120) { continueNext = false; enter(v); }
  }, true);

  // After Next/Previous loaded a whole new page: pick up the main video and keep playing in Oranix.
  if (TOP) {
    let since = 0;
    try { since = +sessionStorage.getItem('oranix-continue') || 0; sessionStorage.removeItem('oranix-continue'); } catch (_) {}
    if (Date.now() - since < 60000) {
      continueNext = true;
      let tries = 0;
      const look = setInterval(() => {
        const vids = allVideos().sort((a, b) => b.w * b.h - a.w * a.h);
        if (on || enlargedFrame || ++tries > 40) return clearInterval(look);
        if (vids.length) { clearInterval(look); continueNext = false; playEntry(vids[0]); }
      }, 500);
    }
  }

  // YouTube swaps videos without reloading: leave the player for the old video; if we're
  // continuing (Next pressed), the new video's 'play' brings the player straight back.
  addEventListener('yt-navigate-start', exit);
})();
