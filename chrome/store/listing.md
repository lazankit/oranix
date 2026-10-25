# Chrome Web Store listing — Oranix for Chrome

Upload `chrome/out/oranix-chrome.zip` at https://chrome.google.com/webstore/devconsole (one-time $5 developer registration), then paste the fields below. The same zip works for the Microsoft Edge Add-ons store (free): https://partner.microsoft.com/dashboard/microsoftedge/

## Store listing

**Name:** Oranix for Chrome

**Summary (≤132 chars):**
One clean player bar for every web video — same keys, subtitle & speed menus, gestures — plus an ad and tracker blocklist.

**Category:** Productivity → Tools (or "Entertainment")

**Language:** English

**Description:**
Every video site has different controls. Oranix replaces them with one consistent, keyboard- and gesture-friendly player bar — right where the video sits on the page.

• The same bar on YouTube and most sites: play/pause, ±10 s, previous/next, time remaining, volume up to 200 %
• Quality & speed menu (YouTube and JW Player sites), subtitles & audio menu, C toggles subtitles
• Full-window mode (O) and fullscreen (F), with a Netflix-style "Up next" card and smart next-episode detection
• Touchpad and touch gestures: sideways to seek; in full window, left half = brightness, right half = volume
• Picks the right video when a page has several, including videos inside embedded players
• Blocks 77 ad and tracking networks with Chrome's built-in request blocking (declarativeNetRequest)

Open source (MIT): https://github.com/lazankit/oranix

**Screenshots (1280×800):** `screenshot-1.png`, `screenshot-2.png`
**Small promo tile (440×280):** `promo-440x280.png`

## Privacy practices tab

**Single purpose:** Replace web video players' controls with one consistent player bar, and block ad and tracker requests.

**Permission justification:**
- `declarativeNetRequest` — blocks requests to a fixed list of ad and tracking domains (rules.json), without reading page contents or browsing history.
- Content script on all sites (`<all_urls>`) — the player bar has to attach to video elements on whatever site the user watches. It only touches `<video>` elements and their page's controls.

**Remote code:** No — all code is in the package.

**Data usage:** Oranix for Chrome does not collect, store or transmit any user data. Tick none of the data categories. Certify the three disclosures (no selling, no unrelated use, no creditworthiness use).

**Privacy policy URL:** https://github.com/lazankit/oranix#privacy
