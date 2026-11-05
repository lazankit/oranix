// Oranix Player: a Windows video player built on libmpv (bundled, x64 + ARM64).
// The app owns the window (native dark title bar, icon, fullscreen, maximize, drag & drop) and embeds
// mpv's renderer in it; the controls are uosc plus Oranix's own Lua scripts from <app>\config.
// Live editing: when anything in config\ changes, the player reloads at the same second.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using System.Globalization;
using System.Web.Script.Serialization;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

static class Mpv
{
    const string Dll = "libmpv-2.dll";
    [DllImport(Dll)] public static extern IntPtr mpv_create();
    [DllImport(Dll)] public static extern int mpv_initialize(IntPtr ctx);
    [DllImport(Dll)] public static extern void mpv_terminate_destroy(IntPtr ctx);
    [DllImport(Dll)] public static extern int mpv_set_option_string(IntPtr ctx, byte[] name, byte[] value);
    [DllImport(Dll)] public static extern int mpv_command(IntPtr ctx, IntPtr[] args);
    [DllImport(Dll)] public static extern IntPtr mpv_get_property_string(IntPtr ctx, byte[] name);
    [DllImport(Dll)] public static extern void mpv_free(IntPtr data);
    [DllImport(Dll)] public static extern int mpv_observe_property(IntPtr ctx, ulong id, byte[] name, int format);
    [DllImport(Dll)] public static extern IntPtr mpv_wait_event(IntPtr ctx, double timeout);

    public const int FORMAT_STRING = 1, FORMAT_FLAG = 3;
    public const int EVENT_SHUTDOWN = 1, EVENT_PROPERTY_CHANGE = 22;

    [StructLayout(LayoutKind.Sequential)] public struct Event { public int id; public int error; public ulong userdata; public IntPtr data; }
    [StructLayout(LayoutKind.Sequential)] public struct Property { public IntPtr name; public int format; public IntPtr data; }

    public static byte[] U8(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }

    public static string FromU8(IntPtr p)
    {
        if (p == IntPtr.Zero) return null;
        int n = 0;
        while (Marshal.ReadByte(p, n) != 0) n++;
        var b = new byte[n];
        Marshal.Copy(p, b, 0, n);
        return Encoding.UTF8.GetString(b);
    }

    public static void Command(IntPtr ctx, params string[] args)
    {
        var ptrs = new IntPtr[args.Length + 1];
        try {
            for (int i = 0; i < args.Length; i++) {
                byte[] b = U8(args[i]);
                ptrs[i] = Marshal.AllocHGlobal(b.Length);
                Marshal.Copy(b, 0, ptrs[i], b.Length);
            }
            mpv_command(ctx, ptrs);
        } finally {
            foreach (var p in ptrs) if (p != IntPtr.Zero) Marshal.FreeHGlobal(p);
        }
    }

    public static string Get(IntPtr ctx, string name)
    {
        IntPtr p = mpv_get_property_string(ctx, U8(name));
        string s = FromU8(p);
        if (p != IntPtr.Zero) mpv_free(p);
        return s;
    }
}

class OranixPlayer : Form
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool SetDllDirectory(string path);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);

    static readonly string AppDir = AppDomain.CurrentDomain.BaseDirectory;
    static readonly string ConfigDir = Path.Combine(AppDir, "config");

    readonly Panel screen = new Panel { Dock = DockStyle.Fill, BackColor = Color.Black };
    IntPtr mpv;
    bool restarting, closing;
    string resumeFile, resumeAt;
    bool resumePaused;
    FormWindowState beforeFullscreen;
    readonly System.Windows.Forms.Timer liveDebounce = new System.Windows.Forms.Timer { Interval = 700 };

    // Library home screen (library\index.html in a WebView2 over the video), shown when nothing plays.
    readonly WebView2 lib = new WebView2 { Dock = DockStyle.Fill, Visible = false, DefaultBackgroundColor = Color.FromArgb(20, 20, 20) };
    readonly System.Windows.Forms.Timer historyTimer = new System.Windows.Forms.Timer { Interval = 2000 };
    readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
    bool libReady, scanning;

    [STAThread]
    static void Main(string[] args)
    {
        SetProcessDPIAware();
        // One build for x64 and Windows on ARM: load the libmpv that matches this process.
        SetDllDirectory(Path.Combine(AppDir, "libmpv", RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "arm64" : "x64"));
        Application.EnableVisualStyles();
        Application.Run(new OranixPlayer(args));
    }

    OranixPlayer(string[] files)
    {
        Text = "Oranix Player";
        string ico = Path.Combine(AppDir, "oranix-player.ico");
        if (File.Exists(ico)) Icon = new Icon(ico);
        BackColor = Color.Black;
        StartPosition = FormStartPosition.CenterScreen;
        var area = Screen.PrimaryScreen.WorkingArea;
        Size = new Size(area.Width * 8 / 10, area.Height * 8 / 10);
        AllowDrop = true;
        Controls.Add(screen);

        DragEnter += (o, e) => e.Effect = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        DragDrop += (o, e) => {
            var dropped = (string[])e.Data.GetData(DataFormats.FileDrop);
            for (int i = 0; i < dropped.Length; i++) Mpv.Command(mpv, "loadfile", dropped[i], i == 0 ? "replace" : "append");
        };
        Controls.Add(lib);
        lib.BringToFront();
        Library.Load();
        Library.Ffmpeg = Path.Combine(AppDir, "alass", "bin", "ffmpeg.exe");
        Library.ThumbReady += key => { if (IsHandleCreated) BeginInvoke((Action)(() => SendThumb(key))); };
        historyTimer.Tick += (o, e) => RecordProgress();
        historyTimer.Start();
        Shown += (o, e) => { InitLibrary(); Start(files.ToList(), null, false); };
        FormClosing += (o, e) => {
            try { RecordProgress(); Library.SaveHistory(); } catch { }
            if (mpv == IntPtr.Zero || closing) return;
            e.Cancel = true;   // let mpv save the position and shut down first; the event loop closes us
            closing = true;
            Mpv.Command(mpv, "quit");
        };
        WatchConfig();
    }

    // Dark title bar in Oranix charcoal (Windows 11).
    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        int dark = 1, caption = 0x001F1F1F, text = 0x00FFFFFF;
        DwmSetWindowAttribute(Handle, 20, ref dark, 4);
        DwmSetWindowAttribute(Handle, 35, ref caption, 4);
        DwmSetWindowAttribute(Handle, 36, ref text, 4);
    }

    void Start(List<string> files, string startAt, bool paused)
    {
        mpv = Mpv.mpv_create();
        Action<string, string> opt = (k, v) => Mpv.mpv_set_option_string(mpv, Mpv.U8(k), Mpv.U8(v));
        opt("config-dir", ConfigDir);
        opt("config", "yes");
        opt("wid", screen.Handle.ToInt64().ToString());
        opt("input-default-bindings", "yes");
        opt("input-vo-keyboard", "yes");
        opt("force-window", "yes");
        opt("idle", "yes");              // stay open with the Oranix start screen when nothing plays
        opt("border", "yes");            // the app's own title bar replaces uosc's window buttons
        opt("terminal", "no");
        if (startAt != null) opt("start", startAt);
        if (paused) opt("pause", "yes");
        Mpv.mpv_initialize(mpv);
        Mpv.mpv_observe_property(mpv, 1, Mpv.U8("media-title"), Mpv.FORMAT_STRING);
        Mpv.mpv_observe_property(mpv, 2, Mpv.U8("fullscreen"), Mpv.FORMAT_FLAG);
        Mpv.mpv_observe_property(mpv, 3, Mpv.U8("window-maximized"), Mpv.FORMAT_FLAG);
        Mpv.mpv_observe_property(mpv, 4, Mpv.U8("window-minimized"), Mpv.FORMAT_FLAG);
        Mpv.mpv_observe_property(mpv, 5, Mpv.U8("idle-active"), Mpv.FORMAT_FLAG);
        for (int i = 0; i < files.Count; i++) Mpv.Command(mpv, "loadfile", files[i], i == 0 ? "replace" : "append");
        if (startAt != null) ThreadPool.QueueUserWorkItem(_ => { Thread.Sleep(1200); var h = mpv; if (h != IntPtr.Zero) Mpv.Command(h, "show-text", "✓ Oranix Player updated", "2000"); });

        IntPtr ctx = mpv;
        new Thread(() => EventLoop(ctx)) { IsBackground = true, Name = "mpv events" }.Start();
        screen.Focus();
    }

    void EventLoop(IntPtr ctx)
    {
        while (true) {
            var ev = (Mpv.Event)Marshal.PtrToStructure(Mpv.mpv_wait_event(ctx, -1), typeof(Mpv.Event));
            if (ev.id == Mpv.EVENT_SHUTDOWN) {
                Mpv.mpv_terminate_destroy(ctx);
                BeginInvoke((Action)(() => {
                    mpv = IntPtr.Zero;
                    if (restarting) { restarting = false; Start(resumeFile == null ? new List<string>() : new List<string> { resumeFile }, resumeAt, resumePaused); }
                    else { closing = true; Close(); }
                }));
                return;
            }
            if (ev.id != Mpv.EVENT_PROPERTY_CHANGE || ev.data == IntPtr.Zero) continue;
            var prop = (Mpv.Property)Marshal.PtrToStructure(ev.data, typeof(Mpv.Property));
            if (prop.data == IntPtr.Zero) continue;
            string name = Mpv.FromU8(prop.name);
            string str = prop.format == Mpv.FORMAT_STRING ? Mpv.FromU8(Marshal.ReadIntPtr(prop.data)) : null;
            bool flag = prop.format == Mpv.FORMAT_FLAG && Marshal.ReadInt32(prop.data) != 0;
            BeginInvoke((Action)(() => OnProperty(name, str, flag)));
        }
    }

    // uosc's buttons and keys change mpv properties; the app turns them into real window actions.
    void OnProperty(string name, string str, bool flag)
    {
        switch (name) {
            case "media-title": Text = string.IsNullOrEmpty(str) ? "Oranix Player" : str + " - Oranix Player"; break;
            case "idle-active": ShowLibrary(flag); break;
            case "window-minimized": if (flag) WindowState = FormWindowState.Minimized; break;
            case "window-maximized":
                if (FormBorderStyle != FormBorderStyle.None) WindowState = flag ? FormWindowState.Maximized : FormWindowState.Normal;
                break;
            case "fullscreen":
                if (flag && FormBorderStyle != FormBorderStyle.None) {
                    beforeFullscreen = WindowState;
                    FormBorderStyle = FormBorderStyle.None;
                    WindowState = FormWindowState.Normal;
                    WindowState = FormWindowState.Maximized;
                } else if (!flag && FormBorderStyle == FormBorderStyle.None) {
                    FormBorderStyle = FormBorderStyle.Sizable;
                    WindowState = beforeFullscreen;
                }
                break;
        }
    }

    // ---------- library ----------

    async void InitLibrary()
    {
        string page = Path.Combine(AppDir, "library");
        if (!Directory.Exists(page)) return;
        try {
            string arch = RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "win-arm64" : "win-x64";
            string loader = Path.Combine(AppDir, "runtimes", arch, "native");
            if (File.Exists(Path.Combine(loader, "WebView2Loader.dll"))) CoreWebView2Environment.SetLoaderDllFolderPath(loader);
            var env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(Library.DataDir, "webview"));
            await lib.EnsureCoreWebView2Async(env);
        } catch (Exception) { return; }   // no WebView2 runtime: the player still works, just without the library
        var cw = lib.CoreWebView2;
        cw.Settings.AreDefaultContextMenusEnabled = false;
        cw.Settings.AreDevToolsEnabled = false;
        cw.Settings.IsZoomControlEnabled = false;
        cw.Settings.IsStatusBarEnabled = false;
        cw.SetVirtualHostNameToFolderMapping("oranix.library", page, CoreWebView2HostResourceAccessKind.Allow);
        cw.SetVirtualHostNameToFolderMapping("oranix.thumbs", Library.ThumbDir, CoreWebView2HostResourceAccessKind.Allow);
        cw.SetVirtualHostNameToFolderMapping("oranix.fonts", Path.Combine(ConfigDir, "fonts"), CoreWebView2HostResourceAccessKind.Allow);
        cw.WebMessageReceived += OnLibraryMessage;
        cw.Navigate("https://oranix.library/index.html");
        // Live editing of the page: reload when library\ changes.
        var w = new FileSystemWatcher(page) { EnableRaisingEvents = true, SynchronizingObject = this, NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName };
        w.Changed += (o, e) => cw.Reload();
        Rescan();
    }

    void ShowLibrary(bool show)
    {
        if (show) Text = "Oranix Player";
        if (!libReady && show) { lib.Visible = lib.CoreWebView2 != null; return; }
        lib.Visible = show;
        if (show) { lib.BringToFront(); SendState(); lib.Focus(); Rescan(); }
        else screen.Focus();
    }

    void Rescan()
    {
        if (scanning) return;
        scanning = true;
        ThreadPool.QueueUserWorkItem(_ => {
            try { Library.Scan(); } catch { }
            BeginInvoke((Action)(() => { scanning = false; SendState(); Library.StartThumbnails(); }));
        });
    }

    void Post(object msg)
    {
        if (lib.CoreWebView2 == null || !libReady) return;
        lib.CoreWebView2.PostWebMessageAsJson(msg as string ?? json.Serialize(msg));
    }

    void SendState() { if (libReady) Post(Library.StateJson()); }

    void SendThumb(string key)
    {
        double d;
        Library.Durations.TryGetValue(key, out d);
        Post(new Dictionary<string, object> { { "type", "thumb" }, { "key", key }, { "dur", d } });
    }

    void Toast(string text) { Post(new Dictionary<string, object> { { "type", "toast" }, { "text", text } }); }

    void OnLibraryMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        Dictionary<string, object> m;
        try { m = json.Deserialize<Dictionary<string, object>>(e.WebMessageAsJson); } catch { return; }
        string cmd = m.ContainsKey("cmd") ? m["cmd"] as string : null;
        string path = m.ContainsKey("path") ? m["path"] as string : null;
        switch (cmd) {
            case "ready":
                libReady = true;
                if (mpv != IntPtr.Zero && Mpv.Get(mpv, "idle-active") == "yes") ShowLibrary(true); else SendState();
                break;
            case "play": if (path != null) PlayFromLibrary(path); break;
            case "rescan": Toast("Looking for new videos…"); Rescan(); break;
            case "watched": Library.SetWatched(path, m.ContainsKey("value") && (bool)m["value"]); SendState(); break;
            case "forget": Library.Forget(path); SendState(); break;
            case "clearHistory": Library.ClearHistory(); SendState(); break;
            case "removeFolder": Library.Folders.Remove(path); Library.SaveSettings(); Rescan(); break;
            case "addFolder":
                using (var dlg = new FolderBrowserDialog { Description = "Choose a folder with your series or movies", ShowNewFolderButton = false }) {
                    if (dlg.ShowDialog(this) == DialogResult.OK && !Library.Folders.Contains(dlg.SelectedPath)) {
                        Library.Folders.Add(dlg.SelectedPath); Library.SaveSettings(); Toast("Added " + dlg.SelectedPath); Rescan();
                    }
                }
                break;
            case "openFile":
                using (var dlg = new OpenFileDialog { Title = "Open a video", Filter = "Videos|*.mkv;*.mp4;*.avi;*.webm;*.mov;*.m4v;*.wmv;*.ts;*.flv;*.mpg|All files|*.*" }) {
                    if (dlg.ShowDialog(this) == DialogResult.OK) PlayFromLibrary(dlg.FileName);
                }
                break;
        }
    }

    // Plays a file, resuming where it was left. For an episode the whole series becomes the playlist,
    // so it continues into the next episode and Next/Previous work across seasons.
    void PlayFromLibrary(string path)
    {
        if (mpv == IntPtr.Zero) return;
        string start = Library.ResumeAt(path).ToString("0.###", CultureInfo.InvariantCulture);
        Mpv.Command(mpv, "loadfile", path, "replace", "-1", "start=" + start);
        var item = Library.Find(path);
        if (item != null && item.kind == "episode") {
            var eps = Library.ShowEpisodes(item.showId);
            int at = eps.FindIndex(x => string.Equals(x.path, path, StringComparison.OrdinalIgnoreCase));
            for (int i = 0; i < at; i++) Mpv.Command(mpv, "loadfile", eps[i].path, "insert-at", i.ToString(), "start=0");
            for (int i = at + 1; i < eps.Count; i++) Mpv.Command(mpv, "loadfile", eps[i].path, "append", "-1", "start=" + Library.ResumeAt(eps[i].path).ToString("0.###", CultureInfo.InvariantCulture));
        }
        ShowLibrary(false);
    }

    // History: sample the playing file's position every 2 s.
    void RecordProgress()
    {
        if (mpv == IntPtr.Zero || lib.Visible) return;
        string path = Mpv.Get(mpv, "path");
        double pos, dur;
        if (path == null || !double.TryParse(Mpv.Get(mpv, "time-pos") ?? "", NumberStyles.Float, CultureInfo.InvariantCulture, out pos)
            || !double.TryParse(Mpv.Get(mpv, "duration") ?? "", NumberStyles.Float, CultureInfo.InvariantCulture, out dur)) return;
        if (!path.Contains("://")) path = Path.GetFullPath(path);
        Library.Record(path, pos, dur);
    }

    // Live editing: a change anywhere in config\ reloads the player on the same video at the same second.
    void WatchConfig()
    {
        if (!Directory.Exists(ConfigDir)) return;
        var watcher = new FileSystemWatcher(ConfigDir) { IncludeSubdirectories = true, EnableRaisingEvents = true,
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName, SynchronizingObject = this };
        FileSystemEventHandler changed = (o, e) => { liveDebounce.Stop(); liveDebounce.Start(); };
        watcher.Changed += changed; watcher.Created += changed; watcher.Deleted += changed;
        watcher.Renamed += (o, e) => changed(o, e);
        liveDebounce.Tick += (o, e) => {
            liveDebounce.Stop();
            if (mpv == IntPtr.Zero || restarting || closing) return;
            resumeFile = Mpv.Get(mpv, "path");
            resumeAt = Mpv.Get(mpv, "time-pos");
            resumePaused = Mpv.Get(mpv, "pause") == "yes";
            restarting = true;
            Mpv.Command(mpv, "quit");
        };
    }
}
