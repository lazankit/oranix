// Oranix Player: starts mpv with the Oranix setup from <install folder>\config and gives its window
// the Oranix Player icon. Live editing: when anything in config\ changes (keys, look, scripts), the
// player restarts on the same video at the same second with the change applied.
// Stays alive, hidden, until mpv closes (keeps the taskbar icon valid and watches config\).

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

static class OranixPlayer
{
    const int WM_SETICON = 0x80, ICON_SMALL = 0, ICON_BIG = 1;

    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    static readonly string AppDir = AppDomain.CurrentDomain.BaseDirectory;
    static readonly string ConfigDir = Path.Combine(AppDir, "config");

    static string Quote(string s) { return "\"" + s.Replace("\"", "\\\"") + "\""; }

    static string FindMpv()
    {
        string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var candidates = new[] {
            Path.Combine(pf, "MPV Player", "mpv.exe"), Path.Combine(pf, "mpv", "mpv.exe"),
            Path.Combine(local, "Programs", "mpv", "mpv.exe"), Path.Combine(local, "Microsoft", "WinGet", "Links", "mpv.exe"),
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    [STAThread]
    static void Main(string[] args)
    {
        SetProcessDPIAware();
        string mpv = FindMpv();
        if (mpv == null) {
            var answer = MessageBox.Show("Oranix Player plays videos with mpv, which isn't installed yet.\n\nInstall it now with winget?",
                "Oranix Player", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (answer == DialogResult.Yes)
                Process.Start(new ProcessStartInfo("winget", "install --id shinchiro.mpv -e --accept-source-agreements --accept-package-agreements") { UseShellExecute = true }).WaitForExit();
            mpv = FindMpv();
            if (mpv == null) return;
        }

        string ico = Path.Combine(AppDir, "oranix-player.ico");
        var big = File.Exists(ico) ? new Icon(ico, 256, 256) : null;
        var small = File.Exists(ico) ? new Icon(ico, 32, 32) : null;

        // Config changes flip this flag; the loop below then restarts mpv where it was.
        var configChanged = new ManualResetEvent(false);
        var watcher = new FileSystemWatcher(ConfigDir) { IncludeSubdirectories = true, EnableRaisingEvents = true,
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName };
        FileSystemEventHandler onChange = (o, e) => configChanged.Set();
        watcher.Changed += onChange; watcher.Created += onChange; watcher.Deleted += onChange;
        watcher.Renamed += (o, e) => configChanged.Set();

        string pipe = "oranix-player-" + Process.GetCurrentProcess().Id;
        List<string> files = args.ToList();
        string resume = null;   // extra args for a live restart (position, pause)
        while (true) {
            var mpvArgs = new List<string> { Quote("--config-dir=" + ConfigDir), Quote("--input-ipc-server=\\\\.\\pipe\\" + pipe) };
            if (files.Count == 0) mpvArgs.Add("--player-operation-mode=pseudo-gui");   // no file: the Oranix start screen
            if (!string.IsNullOrEmpty(resume)) mpvArgs.Add(resume);
            mpvArgs.AddRange(files.Select(Quote));
            var proc = Process.Start(new ProcessStartInfo(mpv, string.Join(" ", mpvArgs)) { UseShellExecute = false });
            if (resume != null) ThreadPool.QueueUserWorkItem(_ => { Thread.Sleep(1500); Ipc(pipe, "show-text", "✓ Oranix Player updated", "2000"); });
            resume = null;
            configChanged.Reset();

            IntPtr branded = IntPtr.Zero;
            bool restart = false;
            while (!proc.WaitForExit(250)) {
                proc.Refresh();
                IntPtr h = proc.MainWindowHandle;
                if (big != null && h != IntPtr.Zero && h != branded) {
                    SendMessage(h, WM_SETICON, (IntPtr)ICON_BIG, big.Handle);
                    SendMessage(h, WM_SETICON, (IntPtr)ICON_SMALL, small.Handle);
                    branded = h;
                }
                if (configChanged.WaitOne(0)) {
                    Thread.Sleep(500);   // let the editor finish writing all files
                    string path = Get(pipe, "path"), pos = Get(pipe, "time-pos"), paused = Get(pipe, "pause");
                    if (path != null) files = new List<string> { path };
                    double t;
                    if (pos != null && double.TryParse(pos, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out t))
                        resume = "--start=" + t.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture) + (paused == "True" ? " --pause" : "");
                    else resume = "";
                    Ipc(pipe, "quit");
                    proc.WaitForExit(5000);
                    restart = true;
                    break;
                }
            }
            if (!restart) break;
        }
    }

    // ---------- mpv JSON IPC ----------

    static object Send(string pipe, object[] command)
    {
        try {
            using (var c = new NamedPipeClientStream(".", pipe, PipeDirection.InOut)) {
                c.Connect(1000);
                var ser = new JavaScriptSerializer();
                var w = new StreamWriter(c) { AutoFlush = true };
                var r = new StreamReader(c);
                w.WriteLine(ser.Serialize(new Dictionary<string, object> { { "command", command }, { "request_id", 7 } }));
                for (int i = 0; i < 50; i++) {
                    string line = r.ReadLine();
                    if (line == null) return null;
                    var reply = ser.Deserialize<Dictionary<string, object>>(line);
                    if (reply.ContainsKey("request_id") && Convert.ToInt32(reply["request_id"]) == 7)
                        return reply.ContainsKey("data") ? reply["data"] : null;
                }
            }
        } catch (Exception) { }
        return null;
    }

    static string Get(string pipe, string prop)
    {
        object v = Send(pipe, new object[] { "get_property", prop });
        return v == null ? null : Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture);
    }

    static void Ipc(string pipe, params string[] command) { Send(pipe, command.Cast<object>().ToArray()); }
}
