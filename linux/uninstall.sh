#!/usr/bin/env bash
# Removes Oranix Player for Linux (mpv itself is left alone).
share="${XDG_DATA_HOME:-$HOME/.local/share}"
rm -rf "$share/oranix-player"
rm -f "$HOME/.local/bin/oranix-player" "$share/applications/oranix-player.desktop" "$share/icons/hicolor/256x256/apps/oranix-player.png"
command -v update-desktop-database >/dev/null && update-desktop-database "$share/applications" || true
echo "Oranix Player removed."
