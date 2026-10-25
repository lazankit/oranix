package com.oranix.web;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

/**
 * Oranix Web for Android: a light WebView browser with an ad/popup/redirect shield where web video
 * plays with the Oranix player bar (assets/oranix-player.js, shared with the Windows app).
 */
public class MainActivity extends Activity {
    static final String HOME = "https://oranix.home/index.html";
    static final int CHARCOAL = 0xFF1F1F1F, ORANGE = 0xFFFF7A00, PEACH = 0xFFFFA94D;

    // Ad, pop-under and tracking networks; matched against the request host and its parents.
    static final Set<String> AD_HOSTS = new HashSet<>(Arrays.asList(
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "googletagservices.com", "googletagmanager.com", "google-analytics.com", "amazon-adsystem.com",
        "adnxs.com", "taboola.com", "outbrain.com", "criteo.com", "criteo.net", "pubmatic.com",
        "rubiconproject.com", "openx.net", "adform.net", "smartadserver.com", "media.net", "zedo.com",
        "popads.net", "popcash.net", "propellerads.com", "propellerclick.com", "onclickads.net", "onclkds.com",
        "adsterra.com", "adsterratools.com", "highperformanceformat.com", "profitablegatecpm.com",
        "effectivegatecpm.com", "highcpmgate.com", "exoclick.com", "exosrv.com", "juicyads.com",
        "trafficjunky.net", "hilltopads.net", "a-ads.com", "adcash.com", "clickadu.com", "mgid.com",
        "revcontent.com", "bidvertiser.com", "infolinks.com", "adsrvr.org", "moatads.com",
        "scorecardresearch.com", "quantserve.com", "hotjar.com", "histats.com", "admaven.com",
        "ad-maven.com", "galaksion.com", "richads.com", "pushground.com", "monetag.com", "realsrv.com",
        "tsyndicate.com", "adskeeper.com", "yllix.com", "popmyads.com", "ad.plus", "adspyglass.com",
        "displayvertising.com", "betteradsystem.com", "ads.yahoo.com", "advertising.com", "yieldmo.com",
        "sharethrough.com", "teads.tv", "33across.com", "casalemedia.com", "contextweb.com", "lijit.com",
        "adsafeprotected.com", "serving-sys.com", "imasdk.googleapis.com"));
    static final String[] AD_PATHS = {
        "/ads/", "/adserver", "/pagead/", "adsbygoogle", "popunder", "pop-under", "/prebid", "/vast.",
        "/vast/", "/vpaid", "/adframe", "/banners/", "/advert" };

    // Runs in every page: neuters popup tricks and gives pages the same message bridge as the Windows app.
    static final String GUARD_JS = "(() => {"
        + "if (window.__oranixGuard) return; window.__oranixGuard = true;"
        + "if (!window.chrome || !window.chrome.webview) { window.chrome = window.chrome || {};"
        + "  window.chrome.webview = { postMessage: m => window.OranixHost && OranixHost.postMessage(String(m)) }; }"
        + "const noop = () => null;"
        + "try { Object.defineProperty(window, 'open', { value: noop, writable: false }); } catch (e) { window.open = noop; }"
        + "window.addEventListener('beforeunload', e => e.stopImmediatePropagation(), true);"
        + "document.addEventListener('click', e => { const a = e.target.closest && e.target.closest('a[target=_blank]');"
        + "  if (!a || !a.href) return; try { if (new URL(a.href).host !== location.host) { e.preventDefault(); e.stopImmediatePropagation(); } } catch (_) {} }, true);"
        + "const sweep = () => { for (const el of document.querySelectorAll('body > div, body > a, body > iframe')) {"
        + "  const s = getComputedStyle(el); if ((s.position === 'fixed' || s.position === 'absolute') && +s.zIndex > 9999 &&"
        + "  el.offsetWidth >= innerWidth * 0.9 && el.offsetHeight >= innerHeight * 0.9 &&"
        + "  (+s.opacity < 0.1 || el.tagName === 'IFRAME' || !el.innerText.trim())) el.remove(); } };"
        + "addEventListener('DOMContentLoaded', () => { sweep(); setInterval(sweep, 1500); });"
        + "})();";

    FrameLayout root;
    WebView web;
    EditText address;
    TextView star, shield;
    int blocked;
    boolean pageLoaded, playerOn, injectedEarly;
    String playerJs, startTemplate;
    View customView;
    WebChromeClient.CustomViewCallback customCallback;
    SharedPreferences prefs;
    JSONArray saved, history;

    int dp(float v) { return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics()); }

    String asset(String name) {
        try (InputStream in = getAssets().open(name)) {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        } catch (Exception e) { return ""; }
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(CHARCOAL);
        getWindow().setNavigationBarColor(CHARCOAL);
        tuneDisplay();
        playerJs = asset("oranix-player.js");
        startTemplate = asset("start.html");
        prefs = getSharedPreferences("library", MODE_PRIVATE);
        try { saved = new JSONArray(prefs.getString("saved", "[]")); } catch (Exception e) { saved = new JSONArray(); }
        try { history = new JSONArray(prefs.getString("history", "[]")); } catch (Exception e) { history = new JSONArray(); }

        root = new FrameLayout(this);
        root.setBackgroundColor(CHARCOAL);
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        root.addView(column, new FrameLayout.LayoutParams(-1, -1));

        // Toolbar: home, address pill, save star, blocked counter.
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(6), dp(6), dp(10), dp(6));
        bar.setBackgroundColor(CHARCOAL);

        TextView home = iconButton("⌂", 24);
        home.setOnClickListener(v -> go(HOME));
        bar.addView(home, new LinearLayout.LayoutParams(dp(44), dp(44)));

        address = new EditText(this);
        address.setSingleLine(true);
        address.setTextColor(Color.WHITE);
        address.setHintTextColor(0xFF8C8C8C);
        address.setHint("Search or type a site");
        address.setTextSize(15);
        address.setSelectAllOnFocus(true);
        address.setImeOptions(EditorInfo.IME_ACTION_GO);
        address.setInputType(android.text.InputType.TYPE_TEXT_VARIATION_URI);
        address.setPadding(dp(16), 0, dp(16), 0);
        GradientDrawable pill = new GradientDrawable();
        pill.setColor(0xFF2B2B2B);
        pill.setCornerRadius(dp(22));
        pill.setStroke(dp(1), 0xFF3E3E3E);
        address.setBackground(pill);
        address.setOnFocusChangeListener((v, focused) -> pill.setStroke(dp(focused ? 2 : 1), focused ? ORANGE : 0xFF3E3E3E));
        address.setOnEditorActionListener((v, action, event) -> {
            go(address.getText().toString());
            hideKeyboard();
            return true;
        });
        LinearLayout.LayoutParams ap = new LinearLayout.LayoutParams(0, dp(44), 1);
        ap.setMargins(dp(4), 0, dp(6), 0);
        bar.addView(address, ap);

        star = iconButton("☆", 22);
        star.setOnClickListener(v -> toggleSaved());
        bar.addView(star, new LinearLayout.LayoutParams(dp(40), dp(44)));

        shield = new TextView(this);
        shield.setTextColor(PEACH);
        shield.setTextSize(12);
        shield.setGravity(Gravity.CENTER);
        shield.setPadding(dp(6), 0, 0, 0);
        shield.setText("🛡 0");
        bar.addView(shield, new LinearLayout.LayoutParams(-2, dp(44)));
        column.addView(bar, new LinearLayout.LayoutParams(-1, -2));

        web = new WebView(this);
        web.setBackgroundColor(CHARCOAL);
        column.addView(web, new LinearLayout.LayoutParams(-1, 0, 1));
        setupWebView();
        setContentView(root);

        String start = urlFromIntent(getIntent());
        go(start != null ? start : HOME);
    }

    // Tall 20:9 phones with a punch-hole camera (e.g. Nothing Phone 3): fullscreen video may use the
    // area beside the camera, and the app asks for the panel's highest refresh rate (120 Hz) for smooth scrolling.
    void tuneDisplay() {
        android.view.WindowManager.LayoutParams lp = getWindow().getAttributes();
        lp.layoutInDisplayCutoutMode = android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            android.view.Display d = getDisplay();
            if (d != null) {
                android.view.Display.Mode cur = d.getMode(), best = cur;
                for (android.view.Display.Mode m : d.getSupportedModes())
                    if (m.getPhysicalWidth() == cur.getPhysicalWidth() && m.getPhysicalHeight() == cur.getPhysicalHeight()
                            && m.getRefreshRate() > best.getRefreshRate()) best = m;
                lp.preferredDisplayModeId = best.getModeId();
            }
        }
        getWindow().setAttributes(lp);
    }

    TextView iconButton(String glyph, int sp) {
        TextView b = new TextView(this);
        b.setText(glyph);
        b.setTextSize(sp);
        b.setTextColor(Color.WHITE);
        b.setGravity(Gravity.CENTER);
        TypedValue ripple = new TypedValue();
        getTheme().resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, ripple, true);
        b.setBackgroundResource(ripple.resourceId);
        return b;
    }

    void setupWebView() {
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);   // so Next/playlists keep playing
        s.setSupportMultipleWindows(true);              // ...and onCreateWindow refuses every popup
        s.setJavaScriptCanOpenWindowsAutomatically(false);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setBuiltInZoomControls(true);
        s.setDisplayZoomControls(false);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false);
        // Speed: keep the page renderer at top priority and pre-render just off screen for smooth scrolling.
        web.setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_IMPORTANT, false);
        s.setOffscreenPreRaster(true);
        web.addJavascriptInterface(new Host(), "OranixHost");

        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest req) {
                Uri u = req.getUrl();
                String url = u.toString();
                if (url.startsWith("https://oranix.home/")) {
                    byte[] html = startPage().getBytes(StandardCharsets.UTF_8);
                    return new WebResourceResponse("text/html", "utf-8", new ByteArrayInputStream(html));
                }
                if (isAd(u)) {
                    runOnUiThread(MainActivity.this::countBlocked);
                    return new WebResourceResponse("text/plain", "utf-8", 403, "Blocked", null, new ByteArrayInputStream(new byte[0]));
                }
                return null;
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri u = req.getUrl();
                String scheme = u.getScheme() == null ? "" : u.getScheme();
                // intent:// and market:// are the usual "open the Play Store / another app" hijacks.
                if (!scheme.equals("http") && !scheme.equals("https")) { countBlocked(); return true; }
                if (isAd(u)) { countBlocked(); return true; }
                if (!req.isForMainFrame() || req.hasGesture() || req.isRedirect() || !pageLoaded) return false;
                // A page sending you to a different site without a tap = redirect hijack.
                Uri current = Uri.parse(view.getUrl() == null ? "" : view.getUrl());
                if (current.getHost() != null && !site(current).equals(site(u))) { countBlocked(); return true; }
                return false;
            }

            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap icon) {
                injectedEarly = false;
                inject();
                if (!url.startsWith("https://oranix.home/")) address.setText(url); else address.setText("");
                playerOn = false;
                updateStar();
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                inject();
                pageLoaded = true;
                addHistory(url, view.getTitle());
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onCreateWindow(WebView view, boolean dialog, boolean userGesture, android.os.Message msg) {
                countBlocked();   // no popups, ever
                return false;
            }

            @Override
            public void onProgressChanged(WebView view, int progress) {
                // Get the scripts in early, but only once mid-load (each pass re-sends ~50 KB of script).
                if (progress >= 20 && !injectedEarly) { injectedEarly = true; inject(); }
            }

            @Override
            public void onReceivedTitle(WebView view, String title) { addHistory(view.getUrl(), title); }

            // Page asked for fullscreen (Oranix player F / double tap): fill the screen, landscape, no system bars.
            @Override
            public void onShowCustomView(View view, CustomViewCallback callback) {
                if (customView != null) { callback.onCustomViewHidden(); return; }
                customView = view;
                customCallback = callback;
                root.addView(view, new FrameLayout.LayoutParams(-1, -1));
                hideSystemBars(true);
                setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
            }

            @Override
            public void onHideCustomView() { leaveFullscreen(); }
        });
    }

    void leaveFullscreen() {
        if (customView == null) return;
        root.removeView(customView);
        customView = null;
        if (customCallback != null) customCallback.onCustomViewHidden();
        customCallback = null;
        hideSystemBars(false);
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);
    }

    @SuppressWarnings("deprecation")
    void hideSystemBars(boolean on) {
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = getWindow().getInsetsController();
            if (c == null) return;
            if (on) {
                c.hide(WindowInsets.Type.systemBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            } else c.show(WindowInsets.Type.systemBars());
        } else {
            getWindow().getDecorView().setSystemUiVisibility(on
                ? View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                : 0);
        }
    }

    void inject() {
        web.evaluateJavascript(GUARD_JS, null);
        web.evaluateJavascript(playerJs, null);   // guarded inside: runs once per page
    }

    // ---------- shield ----------

    static boolean isAd(Uri u) {
        String scheme = u.getScheme();
        if (scheme == null || !scheme.startsWith("http")) return false;
        String host = u.getHost() == null ? "" : u.getHost().toLowerCase(Locale.ROOT);
        while (true) {
            if (AD_HOSTS.contains(host)) return true;
            int dot = host.indexOf('.');
            if (dot < 0 || host.indexOf('.', dot + 1) < 0) break;
            host = host.substring(dot + 1);
        }
        String path = (u.getEncodedPath() == null ? "" : u.getEncodedPath()) + "?" + (u.getEncodedQuery() == null ? "" : u.getEncodedQuery());
        path = path.toLowerCase(Locale.ROOT);
        for (String p : AD_PATHS) if (path.contains(p)) return true;
        return false;
    }

    static String site(Uri u) {
        String[] parts = (u.getHost() == null ? "" : u.getHost()).split("\\.");
        return parts.length <= 2 ? u.getHost() : parts[parts.length - 2] + "." + parts[parts.length - 1];
    }

    void countBlocked() {
        blocked++;
        shield.setText("🛡 " + blocked);
    }

    // ---------- navigation ----------

    void go(String text) {
        text = text.trim();
        if (text.isEmpty()) return;
        String url = text.contains("://") ? text
            : (text.contains(".") && !text.contains(" ")) ? "https://" + text
            : "https://duckduckgo.com/?q=" + Uri.encode(text);
        web.loadUrl(url);
        web.requestFocus();
    }

    String urlFromIntent(Intent i) {
        if (i == null) return null;
        if (Intent.ACTION_VIEW.equals(i.getAction()) && i.getData() != null) return i.getData().toString();
        if (Intent.ACTION_SEND.equals(i.getAction())) {
            String t = i.getStringExtra(Intent.EXTRA_TEXT);
            if (t != null) {
                java.util.regex.Matcher m = java.util.regex.Pattern.compile("https?://\\S+").matcher(t);
                return m.find() ? m.group() : t;
            }
        }
        return null;
    }

    @Override
    protected void onNewIntent(Intent i) {
        super.onNewIntent(i);
        String url = urlFromIntent(i);
        if (url != null) go(url);
    }

    void hideKeyboard() {
        InputMethodManager imm = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
        imm.hideSoftInputFromWindow(address.getWindowToken(), 0);
        address.clearFocus();
    }

    // Back: leave fullscreen, then the Oranix player, then go back a page.
    @Override
    public void onBackPressed() {
        if (customView != null) { web.evaluateJavascript("document.exitFullscreen && document.exitFullscreen()", null); leaveFullscreen(); return; }
        if (playerOn) { playerOn = false; web.evaluateJavascript("window.__oranixToggle && window.__oranixToggle()", null); return; }
        if (web.canGoBack()) { web.goBack(); return; }
        super.onBackPressed();
    }

    @Override
    protected void onPause() { super.onPause(); web.onPause(); CookieManager.getInstance().flush(); }

    @Override
    protected void onResume() { super.onResume(); web.onResume(); }

    // ---------- page messages (same as the Windows app) ----------

    class Host {
        @JavascriptInterface
        public void postMessage(String msg) {
            runOnUiThread(() -> {
                if ("player:on".equals(msg)) playerOn = true;
                else if ("player:off".equals(msg)) playerOn = false;
                else if (web.getUrl() != null && web.getUrl().startsWith("https://oranix.home/")) {   // start page only
                    if (msg.startsWith("unsave:")) remove(saved, msg.substring(7));
                    else if (msg.startsWith("forget:")) remove(history, msg.substring(7));
                    else if (msg.equals("clear-history")) history = new JSONArray();
                    else return;
                    saveLibrary();
                    web.reload();
                }
            });
        }
    }

    // ---------- saved sites, history, start page ----------

    static boolean isWeb(String url) { return url != null && url.startsWith("http") && !url.startsWith("https://oranix.home/"); }

    void saveLibrary() {
        prefs.edit().putString("saved", saved.toString()).putString("history", history.toString()).apply();
    }

    static void remove(JSONArray list, String url) {
        for (int i = list.length() - 1; i >= 0; i--) if (url.equals(list.optJSONObject(i).optString("url"))) list.remove(i);
    }

    void addHistory(String url, String title) {
        if (!isWeb(url)) return;
        try {
            remove(history, url);
            JSONArray next = new JSONArray();
            next.put(new JSONObject().put("url", url).put("title", TextUtils.isEmpty(title) ? url : title).put("time", System.currentTimeMillis()));
            for (int i = 0; i < history.length() && next.length() < 60; i++) next.put(history.get(i));
            history = next;
            saveLibrary();
        } catch (Exception ignored) { }
    }

    void toggleSaved() {
        String url = web.getUrl();
        if (!isWeb(url)) return;
        int before = saved.length();
        remove(saved, url);
        if (saved.length() == before) {
            try {
                JSONArray next = new JSONArray();
                next.put(new JSONObject().put("url", url).put("title", web.getTitle()).put("time", System.currentTimeMillis()));
                for (int i = 0; i < saved.length(); i++) next.put(saved.get(i));
                saved = next;
            } catch (Exception ignored) { }
            Toast.makeText(this, "Saved to the start page", Toast.LENGTH_SHORT).show();
        }
        saveLibrary();
        updateStar();
    }

    void updateStar() {
        String url = web.getUrl();
        boolean on = false;
        for (int i = 0; url != null && i < saved.length(); i++) if (url.equals(saved.optJSONObject(i).optString("url"))) on = true;
        star.setText(on ? "★" : "☆");
        star.setTextColor(on ? ORANGE : Color.WHITE);
    }

    static String esc(String s) { return TextUtils.htmlEncode(s == null ? "" : s); }

    static String hostOf(String url) {
        String h = Uri.parse(url).getHost();
        return h == null ? url : h.replaceFirst("^www\\.", "");
    }

    static String ago(long t) {
        long m = (System.currentTimeMillis() - t) / 60000;
        if (m < 1) return "just now";
        if (m < 60) return m + " min ago";
        if (m < 1440) return (m / 60) + " h ago";
        return (m / 1440) + " d ago";
    }

    static String initial(String url) {
        String h = hostOf(url);
        return h.isEmpty() ? "?" : h.substring(0, 1).toUpperCase(Locale.ROOT);
    }

    // start.html (shared with the Windows app) with the saved sites and history filled in.
    String startPage() {
        StringBuilder tiles = new StringBuilder(), rows = new StringBuilder();
        JSONArray shown = saved;
        if (saved.length() == 0) {
            shown = new JSONArray();
            try {
                shown.put(new JSONObject().put("url", "https://m.youtube.com").put("title", "YouTube"));
                shown.put(new JSONObject().put("url", "https://archive.org/details/feature_films").put("title", "Internet Archive Films"));
            } catch (Exception ignored) { }
        }
        for (int i = 0; i < shown.length(); i++) {
            JSONObject x = shown.optJSONObject(i);
            String url = x.optString("url");
            tiles.append("<a class=tile href=\"").append(esc(url)).append("\"><span class=ic>").append(esc(initial(url)))
                .append("</span><span class=tt>").append(esc(x.optString("title"))).append("</span><span class=hs>")
                .append(esc(hostOf(url))).append("</span>");
            if (saved.length() > 0) tiles.append("<button class=x title=Remove data-m=\"unsave:").append(esc(url)).append("\">✕</button>");
            tiles.append("</a>");
        }
        for (int i = 0; i < history.length() && i < 30; i++) {
            JSONObject x = history.optJSONObject(i);
            String url = x.optString("url");
            rows.append("<a class=row href=\"").append(esc(url)).append("\"><span class=\"ic sm\">").append(esc(initial(url)))
                .append("</span><span class=rt>").append(esc(x.optString("title"))).append("<small>").append(esc(hostOf(url)))
                .append("</small></span><span class=ago>").append(ago(x.optLong("time"))).append("</span>")
                .append("<button class=x title=Forget data-m=\"forget:").append(esc(url)).append("\">✕</button></a>");
        }
        return startTemplate
            .replace("<meta charset=utf-8>", "<meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\">")
            .replace("{{TILES}}", tiles.toString())
            .replace("{{CLEAR}}", history.length() > 0 ? "<a data-m=clear-history>Clear</a>" : "")
            .replace("{{ROWS}}", rows.length() > 0 ? rows.toString() : "<div class=empty>Sites you open will show up here.</div>");
    }
}
