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
        Shown += (o, e) => Start(files.ToList(), null, false);
        FormClosing += (o, e) => {
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
            case "idle-active": if (flag) Text = "Oranix Player"; break;
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
