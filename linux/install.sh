#!/usr/bin/env bash
# Oranix Player for Linux: installs the Oranix look, popups and gestures on top of your mpv,
# for the current user only (no root). Run:  bash install.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
share="${XDG_DATA_HOME:-$HOME/.local/share}"
app="$share/oranix-player"
bin="$HOME/.local/bin"

if ! command -v mpv >/dev/null 2>&1; then
  echo "Oranix Player needs mpv. Install it first, for example:"
  echo "  Debian/Ubuntu:  sudo apt install mpv"
  echo "  Fedora:         sudo dnf install mpv"
  echo "  Arch:           sudo pacman -S mpv"
  echo "  Any distro:     flatpak install flathub io.mpv.Mpv"
  exit 1
fi

mkdir -p "$app" "$bin" "$share/applications" "$share/icons/hicolor/256x256/apps"
rm -rf "$app/config"
cp -r "$here/config" "$app/config"
cp "$here/oranix-player.png" "$share/icons/hicolor/256x256/apps/oranix-player.png"

# Launcher: mpv with the Oranix config. The Windows-only video settings in mpv.conf are overridden here.
cat > "$bin/oranix-player" <<EOF
#!/usr/bin/env bash
exec mpv --config-dir="$app/config" --gpu-api=auto --hwdec=auto-safe --vo=gpu-next \\
  --title='\${?media-title:\${media-title} - }Oranix Player' "\$@"
EOF
chmod +x "$bin/oranix-player"

cat > "$share/applications/oranix-player.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Oranix Player
GenericName=Video Player
Comment=Play More. Worry Less.
Exec=$bin/oranix-player --player-operation-mode=pseudo-gui -- %F
Icon=oranix-player
Terminal=false
Categories=AudioVideo;Video;Player;
MimeType=video/mp4;video/x-matroska;video/webm;video/x-msvideo;video/quicktime;video/mpeg;video/x-flv;video/mp2t;
StartupWMClass=mpv
EOF
command -v update-desktop-database >/dev/null && update-desktop-database "$share/applications" || true

echo "Oranix Player installed."
echo "  Open it from your app menu, or run:  oranix-player video.mkv"
echo "  Make it the default video player in your desktop's Default Applications settings."
case ":$PATH:" in *":$bin:"*) ;; *) echo "  (Add $bin to your PATH to use the oranix-player command.)";; esac
