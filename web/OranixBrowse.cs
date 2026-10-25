// Oranix Web: a light WebView2 browser with an ad/popup/redirect shield where any web
// video (YouTube etc.) plays in the Oranix player UI (oranix-player.js, injected into every frame).
// Separate from the Oranix mpv player and from CineShell. Build: build.bat (.NET Framework 4.8).

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

class OranixBrowse : Form
{
    const string Home = "https://oranix.home/index.html";   // start page (saved sites + history), served from the profile folder
    static readonly Color Charcoal = Color.FromArgb(31, 31, 31), Orange = Color.FromArgb(255, 122, 0);

    // Ad, pop-under and tracking networks. Matched against the request host and its parents.
    static readonly HashSet<string> AdHosts = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
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
        "adsafeprotected.com", "serving-sys.com", "imasdk.googleapis.com"
    };
    static readonly string[] AdPaths = {
        "/ads/", "/adserver", "/pagead/", "adsbygoogle", "popunder", "pop-under", "/prebid", "/vast.",
        "/vast/", "/vpaid", "/adframe", "/banners/", "/advert"
    };

    // Runs in every page/frame before its own scripts: neuters the usual popup tricks.
    const string GuardJs = @"
(() => {
  const noop = () => null;
  try { Object.defineProperty(window, 'open', { value: noop, writable: false }); } catch (e) { window.open = noop; }
  window.addEventListener('beforeunload', e => e.stopImmediatePropagation(), true);
  try { Object.defineProperty(window, 'onbeforeunload', { get: noop, set: noop }); } catch (e) {}
  document.addEventListener('click', e => {
    const a = e.target.closest && e.target.closest('a[target=_blank]');
    if (!a || !a.href) return;
    try { if (new URL(a.href).host !== location.host) { e.preventDefault(); e.stopImmediatePropagation(); } } catch (_) {}
  }, true);
  const sweep = () => {
    for (const el of document.querySelectorAll('body > div, body > a, body > iframe')) {
      const s = getComputedStyle(el);
      if ((s.position === 'fixed' || s.position === 'absolute') && +s.zIndex > 9999 &&
          el.offsetWidth >= innerWidth * 0.9 && el.offsetHeight >= innerHeight * 0.9 &&
          (+s.opacity < 0.1 || el.tagName === 'IFRAME' || !el.innerText.trim())) el.remove();
    }
  };
  addEventListener('DOMContentLoaded', () => { sweep(); setInterval(sweep, 1500); });
})();";

    readonly WebView2 web = new WebView2();
    readonly TextBox address = new TextBox();
    readonly Pill shield = new Pill();
    readonly Panel bar = new Panel();
    CoreWebView2Environment env;
    int blockedCount;
    bool pageLoaded, allowNext;
    readonly Pill star = new Pill();
    FormWindowState restoreState;
    string snapPath;
    bool playerOn;   // the page reports when the Oranix player is open

    // Saved sites and history, kept in profile\library.json.
    class Entry { public string Url; public string Title; public DateTime Time; }
    class Library { public List<Entry> Saved = new List<Entry>(); public List<Entry> History = new List<Entry>(); }
    Library lib = new Library();
    // User data (cookies, saved sites, history) lives outside the install folder, so updates/uninstall don't touch it.
    static string ProfileDir { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Oranix", "Web"); } }
    static string LibraryFile { get { return Path.Combine(ProfileDir, "library.json"); } }
    static string StartDir { get { return Path.Combine(ProfileDir, "start"); } }

    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);

    // Dark title bar in Oranix charcoal (Windows 11), so it matches the toolbar.
    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        int dark = 1, caption = 0x001F1F1F, text = 0x00FFFFFF;
        DwmSetWindowAttribute(Handle, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, ref dark, 4);
        DwmSetWindowAttribute(Handle, 35 /* DWMWA_CAPTION_COLOR */, ref caption, 4);
        DwmSetWindowAttribute(Handle, 36 /* DWMWA_TEXT_COLOR */, ref text, 4);
    }

    [STAThread]
    static void Main(string[] args)
    {
        SetProcessDPIAware();
        Application.EnableVisualStyles();
        // Test mode: OranixBrowse.exe <url> --snap <file.png>  opens player mode, saves a snapshot, exits.
        int snap = Array.IndexOf(args, "--snap");
        Application.Run(new OranixBrowse(args.Length > 0 && args[0] != "--snap" ? args[0] : Home,
            snap >= 0 && snap + 1 < args.Length ? args[snap + 1] : null));
    }

    static string AppDir { get { return Path.GetDirectoryName(Application.ExecutablePath); } }

    OranixBrowse(string startUrl, string snapFile)
    {
        snapPath = snapFile;
        Text = "Oranix Web";
        string ico = Path.Combine(AppDir, "oranix-web.ico");
        if (File.Exists(ico)) Icon = new Icon(ico);
        BackColor = Charcoal;
        StartPosition = FormStartPosition.CenterScreen;
        var screen = Screen.PrimaryScreen.WorkingArea;
        Size = new Size(screen.Width * 8 / 10, screen.Height * 85 / 100);
        AutoScaleMode = AutoScaleMode.None;   // sizes below are scaled by hand; auto-scaling on top clipped the URL box
        KeyPreview = true;

        // Toolbar. Every piece sizes itself from its text (process is DPI-aware, fonts are in points).
        // Form.DeviceDpi still says 96 before the window exists; ask the screen (the process is DPI-aware).
        float s;
        using (var screenG = Graphics.FromHwnd(IntPtr.Zero)) s = screenG.DpiX / 96f;
        Func<float, int> px = v => (int)(v * s);
        bar.Dock = DockStyle.Top;
        bar.Height = px(52);
        bar.BackColor = Charcoal;
        bar.Padding = new Padding(px(10), px(8), px(10), px(8));
        var font = new Font("Segoe UI", 10f);
        var icons = new Font("Segoe Fluent Icons", 11f);
        var tips = new ToolTip();

        Func<string, string, Action, Pill> iconBtn = (glyph, tip, act) => {
            var b = new Pill { Glyph = glyph, IconFont = icons, Font = font, Dock = DockStyle.Left, Width = px(36), AutoWidth = false, Radius = px(9) };
            tips.SetToolTip(b, tip);
            b.Click += (o, e) => act();
            return b;
        };
        Func<DockStyle, int, Panel> gap = (side, w) => new Panel { Dock = side, Width = px(w), BackColor = Charcoal };

        var player = new Pill { Glyph = "", IconFont = new Font("Segoe Fluent Icons", 9f), Text = "Oranix player",
            Font = new Font("Segoe UI Semibold", 10f), Dock = DockStyle.Right, PadX = px(16), Radius = px(18),
            Fill = Orange, HoverFill = Color.FromArgb(255, 143, 38) };
        tips.SetToolTip(player, "Open this page's video in the full Oranix player (O) · Esc to go back");
        player.Click += (o, e) => TogglePlayer();

        shield.Glyph = "";
        shield.IconFont = icons;
        shield.Font = new Font("Segoe UI", 9f);
        shield.ForeColor = Color.FromArgb(255, 169, 77);
        shield.Dock = DockStyle.Right;
        shield.PadX = px(10);
        shield.HoverFill = Color.Transparent;
        shield.Cursor = Cursors.Default;
        shield.Text = "0 blocked";
        tips.SetToolTip(shield, "Ads, pop-ups and redirects blocked on this visit");

        star.Glyph = "";
        star.IconFont = icons;
        star.Font = font;
        star.Dock = DockStyle.Right;
        star.Width = px(36);
        star.AutoWidth = false;
        star.Radius = px(9);
        tips.SetToolTip(star, "Save this site (Ctrl+D)");
        star.Click += (o, e) => ToggleSaved();

        // Address: a rounded pill with a borderless text box inside; the edge turns orange while typing.
        var pill = new Pill { Dock = DockStyle.Fill, AutoWidth = false, Radius = px(18), Fill = Color.FromArgb(43, 43, 43),
            HoverFill = Color.FromArgb(43, 43, 43), Border = Color.FromArgb(62, 62, 62), Cursor = Cursors.IBeam };
        address.Font = new Font("Segoe UI", 10.5f);
        address.BorderStyle = BorderStyle.None;
        address.BackColor = Color.FromArgb(43, 43, 43);
        address.ForeColor = Color.White;
        address.KeyDown += (o, e) => { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; Go(address.Text); } };
        address.Enter += (o, e) => { pill.Border = Orange; pill.Invalidate(); BeginInvoke((Action)address.SelectAll); };
        address.Leave += (o, e) => { pill.Border = Color.FromArgb(62, 62, 62); pill.Invalidate(); };
        address.HandleCreated += (o, e) => SendMessage(address.Handle, 0x1501 /* EM_SETCUEBANNER */, (IntPtr)1, "Search or type a site");
        pill.Controls.Add(address);
        pill.Layout += (o, e) => {
            address.SetBounds(px(16), (pill.Height - address.PreferredHeight) / 2 + 1, Math.Max(10, pill.Width - px(32)), address.PreferredHeight);
        };
        pill.Click += (o, e) => address.Focus();
        var addrHost = new Panel { Dock = DockStyle.Fill, BackColor = Charcoal, Padding = new Padding(px(10), 0, px(10), 0) };
        addrHost.Controls.Add(pill);

        // Dock order: Fill first, then edges (WinForms docks in reverse add order).
        bar.Controls.Add(addrHost);
        bar.Controls.Add(star);
        bar.Controls.Add(gap(DockStyle.Right, 4));
        bar.Controls.Add(shield);
        bar.Controls.Add(gap(DockStyle.Right, 8));
        bar.Controls.Add(player);
        bar.Controls.Add(iconBtn("", "Home", () => Go(Home)));
        bar.Controls.Add(gap(DockStyle.Left, 2));
        bar.Controls.Add(iconBtn("", "Reload (F5)", () => web.Reload()));
        bar.Controls.Add(gap(DockStyle.Left, 2));
        bar.Controls.Add(iconBtn("", "Forward (Alt+Right)", () => { if (web.CanGoForward) web.GoForward(); }));
        bar.Controls.Add(gap(DockStyle.Left, 2));
        bar.Controls.Add(iconBtn("", "Back (Alt+Left)", () => { if (web.CanGoBack) web.GoBack(); }));

        web.Dock = DockStyle.Fill;
        web.DefaultBackgroundColor = Charcoal;
        Controls.Add(web);
        Controls.Add(bar);

        KeyDown += (o, e) => {
            if (e.Control && e.KeyCode == Keys.L) { address.Focus(); address.SelectAll(); e.Handled = true; }
            if (e.Control && e.KeyCode == Keys.D) { ToggleSaved(); e.Handled = true; }
        };

        // With the player open, the window's close button just leaves the player (back to the page).
        FormClosing += (o, e) => {
            if (!playerOn || snapPath != null || web.CoreWebView2 == null || e.CloseReason != CloseReason.UserClosing) return;
            e.Cancel = true;
            playerOn = false;
            web.CoreWebView2.ExecuteScriptAsync("window.__oranixToggle && window.__oranixToggle()");
        };

        LoadLibrary();
        Init(startUrl);
    }

    async void Init(string url)
    {
        // Normal browser autoplay rules (so Next/playlists keep playing); test mode always autoplays.
        var opts = new CoreWebView2EnvironmentOptions(snapPath == null ? "" : "--autoplay-policy=no-user-gesture-required");
        env = await CoreWebView2Environment.CreateAsync(null, ProfileDir, opts);
        await web.EnsureCoreWebView2Async(env);
        var cw = web.CoreWebView2;

        cw.Settings.AreDefaultScriptDialogsEnabled = false;
        cw.Settings.IsStatusBarEnabled = false;
        cw.Settings.IsGeneralAutofillEnabled = false;
        cw.Settings.IsPasswordAutosaveEnabled = false;

        cw.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        cw.WebResourceRequested += OnRequest;
        cw.NewWindowRequested += (o, e) => { e.Handled = true; Blocked(); };
        cw.NavigationStarting += OnNavigationStarting;
        cw.NavigationCompleted += (o, e) => {
            if (!pageLoaded && snapPath != null) Snap();
            pageLoaded = true;
            if (e.IsSuccess) AddHistory(cw.Source, cw.DocumentTitle);
        };
        cw.SourceChanged += (o, e) => { address.Text = cw.Source.StartsWith(Home) ? "" : cw.Source; playerOn = false; UpdateStar(); };
        cw.DocumentTitleChanged += (o, e) => { Text = cw.Source.StartsWith(Home) ? "Oranix Web" : cw.DocumentTitle + " - Oranix Web"; AddHistory(cw.Source, cw.DocumentTitle); };
        cw.WebMessageReceived += OnWebMessage;
        Directory.CreateDirectory(StartDir);
        cw.SetVirtualHostNameToFolderMapping("oranix.home", StartDir, CoreWebView2HostResourceAccessKind.Allow);
        cw.ContainsFullScreenElementChanged += (o, e) => SetFullscreen(cw.ContainsFullScreenElement);
        await cw.AddScriptToExecuteOnDocumentCreatedAsync(GuardJs);
        playerScriptId = await cw.AddScriptToExecuteOnDocumentCreatedAsync(File.ReadAllText(Path.Combine(AppDir, "oranix-player.js")));
        WatchLiveFiles();

        Go(url);
    }

    // The page asked for fullscreen (Oranix player F / double-click): make the window borderless and hide the toolbar.
    void SetFullscreen(bool fs)
    {
        bar.Visible = !fs;
        if (fs) {
            restoreState = WindowState;
            FormBorderStyle = FormBorderStyle.None;
            WindowState = FormWindowState.Normal;
            WindowState = FormWindowState.Maximized;
        } else {
            FormBorderStyle = FormBorderStyle.Sizable;
            WindowState = restoreState;
        }
    }

    async void TogglePlayer()
    {
        string r = await web.CoreWebView2.ExecuteScriptAsync("window.__oranixToggle ? window.__oranixToggle() : null");
        if (r == "null") MessageBox.Show(this, "No video on this page yet.", "Oranix Web");
        web.Focus();
    }

    void Go(string text)
    {
        text = text.Trim();
        if (text.Length == 0) return;
        string url = text.Contains("://") ? text
            : (text.Contains(".") && !text.Contains(" ")) ? "https://" + text
            : "https://duckduckgo.com/?q=" + Uri.EscapeDataString(text);
        allowNext = true;
        if (url == Home) url += "?t=" + DateTime.Now.Ticks;   // the start page is rewritten each visit; skip the cache
        web.CoreWebView2.Navigate(url);
        web.Focus();
    }

    static bool IsAd(Uri u)
    {
        string host = u.Host;
        while (true) {
            if (AdHosts.Contains(host)) return true;
            int dot = host.IndexOf('.');
            if (dot < 0 || host.IndexOf('.', dot + 1) < 0) break;
            host = host.Substring(dot + 1);
        }
        string path = u.PathAndQuery.ToLowerInvariant();
        return AdPaths.Any(p => path.Contains(p));
    }

    static string SiteOf(Uri u)
    {
        var parts = u.Host.Split('.');
        return parts.Length <= 2 ? u.Host : parts[parts.Length - 2] + "." + parts[parts.Length - 1];
    }

    void OnRequest(object sender, CoreWebView2WebResourceRequestedEventArgs e)
    {
        Uri u;
        if (!Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out u) || !u.Scheme.StartsWith("http")) return;
        if (IsAd(u)) {
            e.Response = env.CreateWebResourceResponse(null, 403, "Blocked", "");
            Blocked();
        }
    }

    void OnNavigationStarting(object sender, CoreWebView2NavigationStartingEventArgs e)
    {
        if (e.Uri.StartsWith(Home)) { WriteStartPage(); allowNext = false; return; }   // always fresh saved/history lists
        Uri target;
        if (!Uri.TryCreate(e.Uri, UriKind.Absolute, out target)) return;
        bool ours = allowNext;
        allowNext = false;
        if (target.Scheme.StartsWith("http") && IsAd(target)) { e.Cancel = true; Blocked(); return; }
        if (ours || e.IsUserInitiated || e.IsRedirected || !pageLoaded) return;

        // A page sending you to a different site without a click = redirect hijack.
        Uri current;
        if (Uri.TryCreate(web.CoreWebView2.Source, UriKind.Absolute, out current) && SiteOf(current) != SiteOf(target)) {
            e.Cancel = true;
            Blocked();
        }
    }

    // ---------- live editing ----------
    // oranix-player.js (the in-page player) and start.html (the start page) are read from the app
    // folder. When either is saved, the open page reloads with the change - no rebuild or restart.
    string playerScriptId;
    FileSystemWatcher liveWatcher;
    Timer liveDebounce;

    void WatchLiveFiles()
    {
        liveDebounce = new Timer { Interval = 300 };
        liveDebounce.Tick += async (o, e) => {
            liveDebounce.Stop();
            var cw = web.CoreWebView2;
            try {
                string js = File.ReadAllText(Path.Combine(AppDir, "oranix-player.js"));
                cw.RemoveScriptToExecuteOnDocumentCreated(playerScriptId);
                playerScriptId = await cw.AddScriptToExecuteOnDocumentCreatedAsync(js);
            } catch (IOException) { liveDebounce.Start(); return; }   // file still being written; try again shortly
            if (cw.Source.StartsWith(Home)) Go(Home); else cw.Reload();
        };
        liveWatcher = new FileSystemWatcher(AppDir) { NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName, EnableRaisingEvents = true };
        FileSystemEventHandler changed = (o, e) => {
            if (e.Name == "oranix-player.js" || e.Name == "start.html") BeginInvoke((Action)(() => { liveDebounce.Stop(); liveDebounce.Start(); }));
        };
        liveWatcher.Changed += changed;
        liveWatcher.Created += changed;
        liveWatcher.Renamed += (o, e) => changed(o, e);
    }

    // ---------- saved sites, history, start page ----------

    void LoadLibrary()
    {
        try { if (File.Exists(LibraryFile)) lib = new JavaScriptSerializer().Deserialize<Library>(File.ReadAllText(LibraryFile)) ?? new Library(); }
        catch { lib = new Library(); }
    }

    void SaveLibrary()
    {
        Directory.CreateDirectory(ProfileDir);
        File.WriteAllText(LibraryFile, new JavaScriptSerializer().Serialize(lib));
    }

    static bool IsWeb(string url) { return url != null && url.StartsWith("http") && !url.StartsWith(Home); }

    void AddHistory(string url, string title)
    {
        if (!IsWeb(url) || snapPath != null) return;
        lib.History.RemoveAll(x => x.Url == url);
        lib.History.Insert(0, new Entry { Url = url, Title = string.IsNullOrWhiteSpace(title) ? url : title, Time = DateTime.Now });
        if (lib.History.Count > 60) lib.History.RemoveRange(60, lib.History.Count - 60);
        SaveLibrary();
    }

    void ToggleSaved()
    {
        string url = web.CoreWebView2 == null ? null : web.CoreWebView2.Source;
        if (!IsWeb(url)) return;
        if (lib.Saved.RemoveAll(x => x.Url == url) == 0)
            lib.Saved.Insert(0, new Entry { Url = url, Title = web.CoreWebView2.DocumentTitle, Time = DateTime.Now });
        SaveLibrary();
        UpdateStar();
    }

    void UpdateStar()
    {
        bool saved = web.CoreWebView2 != null && lib.Saved.Any(x => x.Url == web.CoreWebView2.Source);
        star.Glyph = saved ? "" : "";
        star.ForeColor = saved ? Orange : Color.White;
        star.Invalidate();
    }

    void OnWebMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        string msg;
        try { msg = e.TryGetWebMessageAsString(); } catch { return; }
        if (msg == "player:on") playerOn = true;
        else if (msg == "player:off") playerOn = false;
        else if (e.Source.StartsWith(Home)) {   // start page actions
            if (msg.StartsWith("unsave:")) lib.Saved.RemoveAll(x => x.Url == msg.Substring(7));
            else if (msg.StartsWith("forget:")) lib.History.RemoveAll(x => x.Url == msg.Substring(7));
            else if (msg == "clear-history") lib.History.Clear();
            else return;
            SaveLibrary();
            web.Reload();
        }
    }

    static string Esc(string s) { return System.Net.WebUtility.HtmlEncode(s ?? ""); }

    static string Ago(DateTime t)
    {
        var d = DateTime.Now - (t.Kind == DateTimeKind.Utc ? t.ToLocalTime() : t);   // the JSON round-trip stores UTC
        if (d.TotalMinutes < 1) return "just now";
        if (d.TotalHours < 1) return (int)d.TotalMinutes + " min ago";
        if (d.TotalDays < 1) return (int)d.TotalHours + " h ago";
        return (int)d.TotalDays + " d ago";
    }

    static string HostOf(string url)
    {
        Uri u;
        return Uri.TryCreate(url, UriKind.Absolute, out u) ? u.Host.Replace("www.", "") : url;
    }

    void WriteStartPage()
    {
        var saved = lib.Saved.Count > 0 ? lib.Saved : new List<Entry> {
            new Entry { Url = "https://www.youtube.com", Title = "YouTube" },
            new Entry { Url = "https://archive.org/details/feature_films", Title = "Internet Archive Films" },
        };
        var tiles = string.Concat(saved.Select(x =>
            "<a class=tile href=\"" + Esc(x.Url) + "\"><span class=ic>" + Esc(HostOf(x.Url).Substring(0, 1).ToUpper()) + "</span>" +
            "<span class=tt>" + Esc(x.Title) + "</span><span class=hs>" + Esc(HostOf(x.Url)) + "</span>" +
            (lib.Saved.Count > 0 ? "<button class=x title=Remove data-m=\"unsave:" + Esc(x.Url) + "\">✕</button>" : "") + "</a>"));
        var rows = string.Concat(lib.History.Take(30).Select(x =>
            "<a class=row href=\"" + Esc(x.Url) + "\"><span class=ic sm>" + Esc(HostOf(x.Url).Substring(0, 1).ToUpper()) + "</span>" +
            "<span class=rt>" + Esc(x.Title) + "<small>" + Esc(HostOf(x.Url)) + "</small></span><span class=ago>" + Ago(x.Time) + "</span>" +
            "<button class=x title=Forget data-m=\"forget:" + Esc(x.Url) + "\">✕</button></a>"));
        // The page itself lives in start.html next to the app (live-editable); the app fills in the lists.
        string html = File.ReadAllText(Path.Combine(AppDir, "start.html"))
            .Replace("{{TILES}}", tiles)
            .Replace("{{CLEAR}}", lib.History.Count > 0 ? "<a data-m=clear-history>Clear</a>" : "")
            .Replace("{{ROWS}}", rows.Length > 0 ? rows : "<div class=empty>Sites you open will show up here.</div>");
        Directory.CreateDirectory(StartDir);
        File.WriteAllText(Path.Combine(StartDir, "index.html"), html);
    }

    void Blocked()
    {
        blockedCount++;
        shield.Text = blockedCount + " blocked";
    }

    async void Snap()
    {
        await System.Threading.Tasks.Task.Delay(6000);
        // Test mode shows the inline skin (default); add "--full" to snapshot the full window instead.
        string on = await web.CoreWebView2.ExecuteScriptAsync(Environment.GetCommandLineArgs().Contains("--full")
            ? "window.__oranixToggle ? window.__oranixToggle() : 'no-script'"
            : "document.documentElement.classList.contains('oranix-skin') ? 'inline' : 'none'");
        await System.Threading.Tasks.Task.Delay(4000);
        // Hover over the video so the auto-hiding controls are in the snapshot.
        await web.CoreWebView2.CallDevToolsProtocolMethodAsync("Input.dispatchMouseEvent", "{\"type\":\"mouseMoved\",\"x\":300,\"y\":260}");
        if (Environment.GetCommandLineArgs().Contains("--popup"))   // also open the Quality & speed menu
            await web.CoreWebView2.CallDevToolsProtocolMethodAsync("Input.dispatchKeyEvent", "{\"type\":\"keyDown\",\"key\":\"x\",\"text\":\"x\"}");
        await System.Threading.Tasks.Task.Delay(400);
        using (var f = File.Create(snapPath))
            await web.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, f);
        File.WriteAllText(snapPath + ".txt", "player=" + on + " blocked=" + blockedCount);
        using (var tb = new Bitmap(bar.Width, bar.Height)) {   // the toolbar too (WebView capture doesn't include it)
            bar.DrawToBitmap(tb, new Rectangle(0, 0, bar.Width, bar.Height));
            tb.Save(snapPath + ".bar.png");
        }
        Close();
    }
}

// Rounded toolbar control: optional icon glyph + text, hover colour, optional border. Sizes itself to its content.
class Pill : Control
{
    public string Glyph = "";
    public Font IconFont;
    public Color Fill = Color.Transparent, HoverFill = Color.FromArgb(52, 52, 52), Border = Color.Transparent;
    public int Radius, PadX;
    public bool AutoWidth = true;
    bool hover;

    public Pill()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        ForeColor = Color.White;
        Cursor = Cursors.Hand;
        TabStop = false;
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Fit(); Invalidate(); }
    protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); Fit(); }
    protected override void OnParentChanged(EventArgs e) { base.OnParentChanged(e); Fit(); }

    const TextFormatFlags Flags = TextFormatFlags.NoPadding | TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.SingleLine;

    Size Measure(string s, Font f) { return s.Length == 0 || f == null ? Size.Empty : TextRenderer.MeasureText(s, f, Size.Empty, Flags); }

    void Fit()
    {
        if (!AutoWidth) return;
        Size g = Measure(Glyph, IconFont), t = Measure(Text, Font);
        Width = PadX * 2 + g.Width + t.Width + (g.Width > 0 && t.Width > 0 ? PadX / 2 : 0);
    }

    static GraphicsPath Round(Rectangle r, int radius)
    {
        int d = Math.Max(1, Math.Min(radius * 2, Math.Min(r.Width, r.Height)));
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.Clear(Parent != null ? Parent.BackColor : BackColor);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Color bg = hover && HoverFill.A > 0 ? HoverFill : Fill;
        var box = new Rectangle(0, 0, Width - 1, Height - 1);
        using (var path = Round(box, Radius)) {
            if (bg.A > 0) using (var b = new SolidBrush(bg)) g.FillPath(b, path);
            if (Border.A > 0) using (var pen = new Pen(Border, 1.5f)) g.DrawPath(pen, path);
        }
        Size gs = Measure(Glyph, IconFont), ts = Measure(Text, Font);
        int gapW = gs.Width > 0 && ts.Width > 0 ? PadX / 2 : 0;
        int x = (Width - gs.Width - gapW - ts.Width) / 2;
        if (gs.Width > 0) TextRenderer.DrawText(g, Glyph, IconFont, new Rectangle(x, 0, gs.Width + 2, Height), ForeColor, Flags);
        if (ts.Width > 0) TextRenderer.DrawText(g, Text, Font, new Rectangle(x + gs.Width + gapW, 0, ts.Width + 2, Height), ForeColor, Flags);
    }
}
