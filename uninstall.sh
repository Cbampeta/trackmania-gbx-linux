#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/trackmania-gbx-linux"
CONFIG_FILE="$CONFIG_DIR/config"

MAPS_SYMLINK_PATH=""
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

echo "Uninstalling trackmania-gbx-linux..."

rm -f "$BIN_DIR/trackmania-open-gbx"
rm -f "$DATA_DIR/applications/trackmania-gbx.desktop"
rm -f "$DATA_DIR/mime/packages/trackmania-gbx.xml"
rm -rf "$CONFIG_DIR"

if [[ -n "$MAPS_SYMLINK_PATH" && -L "$MAPS_SYMLINK_PATH" ]]; then
    read -rp "Remove custom maps symlink ($MAPS_SYMLINK_PATH)? [y/N]: " ans
    if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
        rm -f "$MAPS_SYMLINK_PATH"
        echo "Removed symlink: $MAPS_SYMLINK_PATH"
    fi
fi

if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database "$DATA_DIR/mime"
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DATA_DIR/applications"
fi

echo "Done! trackmania-gbx-linux has been uninstalled."
