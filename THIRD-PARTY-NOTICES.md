# Third-party notices

Oranix's own code is MIT-licensed (see [LICENSE](LICENSE)). It builds on these projects, which keep their own licenses:

| Component | Used for | License | Where |
|---|---|---|---|
| [mpv](https://mpv.io) | Video playback in Oranix Player | GPL-2.0-or-later | **Not bundled.** Installed separately (Oranix Player offers to install it with `winget install shinchiro.mpv`) and run as its own program. |
| [uosc](https://github.com/tomasklaen/uosc) | Oranix Player's control bar and menus | LGPL-2.1 | Bundled unmodified in [`player/config/scripts/uosc`](player/config/scripts/uosc) with its license ([`LICENSE.LGPL`](player/config/scripts/uosc/LICENSE.LGPL)), plus its fonts `uosc_icons.otf` / `uosc_textures.ttf`. Configured through `player/config/script-opts/uosc.conf`. |
| [Poppins](https://github.com/itfoundry/Poppins) | The Oranix typeface | SIL Open Font License 1.1 | [`player/config/fonts`](player/config/fonts) ([`Poppins-OFL.txt`](player/config/fonts/Poppins-OFL.txt)) |
| [Microsoft Edge WebView2](https://developer.microsoft.com/microsoft-edge/webview2/) | Oranix Web's browser engine (Windows) | Microsoft WebView2 SDK license | **Not bundled in the source.** `build.ps1` downloads the SDK package from NuGet; the WebView2 Runtime ships with Windows 11. |
| Android System WebView | Oranix Web's browser engine (Android) | Part of Android | Provided by the phone. |
| [Inno Setup](https://jrsoftware.org/isinfo.php) | Builds the Windows installer | Inno Setup License | Build tool only. |
| [Material Symbols](https://fonts.google.com/icons) (path data) | Icons in the web player bar | Apache-2.0 | Inline SVG paths in `web/oranix-player.js`. |
