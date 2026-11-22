#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APPID="2225070"
NON_INTERACTIVE=0

for arg in "$@"; do
    case "$arg" in
        -y|--yes) NON_INTERACTIVE=1 ;;
        -h|--help)
            cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Install the Trackmania .Gbx file handler for Steam/Proton on Linux.
Automatically detects Steam, Trackmania, and Proton paths across Steam
libraries, and prompts interactively if any path cannot be found.

Options:
  -y, --yes    Accept auto-detected paths without prompting (skips optional symlink)
  -h, --help   Show this help message
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $arg (use --help)" >&2
            exit 1
            ;;
    esac
done

# Colors (disabled when stdout is not a TTY or NO_COLOR is set)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_CYAN=$'\033[36m'
    C_RESET=$'\033[0m'
else
    C_BOLD="" C_GREEN="" C_YELLOW="" C_RED="" C_CYAN="" C_RESET=""
fi

info() { echo "${C_CYAN}[INFO]${C_RESET} $*"; }
ok()   { echo "${C_GREEN}[OK]${C_RESET}   $*"; }
warn() { echo "${C_YELLOW}[WARN]${C_RESET} $*"; }
err()  { echo "${C_RED}[ERR]${C_RESET}  $*" >&2; }

expand_path() {
    local p="$1"
    p="${p/#\~/$HOME}"
    if [[ -e "$p" ]]; then
        realpath "$p"
    else
        echo "$p"
    fi
}

check_dependencies() {
    local missing_req=()
    local missing_opt=()

    for cmd in python3 nsenter pgrep realpath; do
        command -v "$cmd" >/dev/null 2>&1 || missing_req+=("$cmd")
    done

    for cmd in update-mime-database update-desktop-database xdg-mime; do
        command -v "$cmd" >/dev/null 2>&1 || missing_opt+=("$cmd")
    done

    if [[ ${#missing_req[@]} -gt 0 ]]; then
        err "Missing required tools: ${missing_req[*]}"
        echo "Please install them using your distribution's package manager (usually python3, util-linux, procps, coreutils)." >&2
        exit 1
    fi

    if [[ ${#missing_opt[@]} -gt 0 ]]; then
        warn "Missing desktop integration tools: ${missing_opt[*]}"
        warn "File manager double-click registration may be incomplete. Install shared-mime-info, desktop-file-utils, and xdg-utils."
    fi

    if ! command -v notify-send >/dev/null 2>&1; then
        info "Optional: 'notify-send' (libnotify) not found; desktop notifications will be skipped."
    fi
}

detect_steam_cmd() {
    if command -v steam >/dev/null 2>&1; then
        echo "steam"
        return 0
    fi
    if command -v flatpak >/dev/null 2>&1 && flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
        echo "flatpak run com.valvesoftware.Steam"
        return 0
    fi
    return 1
}

detect_steam_dir() {
    local candidates=(
        "$HOME/.local/share/Steam"
        "$HOME/.steam/steam"
        "$HOME/.steam/debian-installation"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
        "$HOME/snap/steam/common/.local/share/Steam"
    )
    local dir resolved
    for dir in "${candidates[@]}"; do
        if [[ -d "$dir/steamapps" ]]; then
            resolved="$(realpath "$dir")"
            echo "$resolved"
            return 0
        fi
    done
    return 1
}

get_steam_libraries() {
    local steam_dir="$1"
    local vdf="$steam_dir/steamapps/libraryfolders.vdf"
    echo "$steam_dir"
    if [[ -f "$vdf" ]]; then
        python3 - "$vdf" <<'PY'
import re, sys, os
text = open(sys.argv[1], "r", encoding="utf-8", errors="ignore").read()
seen = set()
for match in re.finditer(r'"path"\s+"([^"]+)"', text):
    p = match.group(1).replace("\\\\", "\\")
    if os.path.isdir(p) and p not in seen:
        seen.add(p)
        print(os.path.realpath(p))
PY
    fi
}

detect_game_dir() {
    local steam_dir="$1"
    local lib
    while IFS= read -r lib; do
        if [[ -f "$lib/steamapps/common/Trackmania/Trackmania.exe" ]]; then
            echo "$lib/steamapps/common/Trackmania"
            return 0
        fi
    done < <(get_steam_libraries "$steam_dir")
    return 1
}

detect_compat_data() {
    local steam_dir="$1"
    local lib
    while IFS= read -r lib; do
        if [[ -d "$lib/steamapps/compatdata/$APPID/pfx" ]]; then
            echo "$lib/steamapps/compatdata/$APPID"
            return 0
        fi
    done < <(get_steam_libraries "$steam_dir")
    return 1
}

find_wine_in_proton_dir() {
    local pdir="$1"
    if [[ -x "$pdir/files/bin/wine" ]]; then
        echo "$pdir/files/bin/wine"
        return 0
    elif [[ -x "$pdir/files/bin/wine64" ]]; then
        echo "$pdir/files/bin/wine64"
        return 0
    elif [[ -x "$pdir/dist/bin/wine" ]]; then
        echo "$pdir/dist/bin/wine"
        return 0
    elif [[ -x "$pdir" && -f "$pdir" ]]; then
        echo "$pdir"
        return 0
    fi
    return 1
}

detect_proton_wine() {
    local steam_dir="$1"
    local compat_data="$2"
    local line proton_root wine_bin

    # 1. Read exact Proton version configured in compatdata/2225070/config_info
    if [[ -f "$compat_data/config_info" ]]; then
        while IFS= read -r line; do
            if [[ "$line" == */files/* ]]; then
                proton_root="${line%%/files/*}"
                if wine_bin="$(find_wine_in_proton_dir "$proton_root")"; then
                    echo "$wine_bin"
                    return 0
                fi
            elif [[ "$line" == */dist/* ]]; then
                proton_root="${line%%/dist/*}"
                if wine_bin="$(find_wine_in_proton_dir "$proton_root")"; then
                    echo "$wine_bin"
                    return 0
                fi
            fi
        done < "$compat_data/config_info"
    fi

    # 2. Scan Steam libraries and compatibilitytools.d
    local lib cand
    while IFS= read -r lib; do
        for cand in "$lib/steamapps/common/Proton - Experimental" "$lib/steamapps/common"/Proton*; do
            if [[ -d "$cand" ]] && wine_bin="$(find_wine_in_proton_dir "$cand")"; then
                echo "$wine_bin"
                return 0
            fi
        done
    done < <(get_steam_libraries "$steam_dir")

    for cand in "$steam_dir/compatibilitytools.d"/* "$HOME/.steam/root/compatibilitytools.d"/*; do
        if [[ -d "$cand" ]] && wine_bin="$(find_wine_in_proton_dir "$cand")"; then
            echo "$wine_bin"
            return 0
        fi
    done

    return 1
}

prompt_path() {
    local prompt_msg="$1"
    local validator="$2"
    local input expanded

    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
        err "Required path could not be auto-detected in non-interactive mode: $prompt_msg"
        exit 1
    fi

    while true; do
        read -rp "$prompt_msg: " input
        expanded="$(expand_path "$input")"
        if "$validator" "$expanded"; then
            echo "$expanded"
            return 0
        fi
        warn "Invalid path: $expanded (please try again)"
    done
}

is_steam_dir()   { [[ -d "$1/steamapps" ]]; }
is_game_dir()    { [[ -f "$1/Trackmania.exe" ]]; }
is_compat_dir()  { [[ -d "$1/pfx" ]]; }
is_proton_path() { find_wine_in_proton_dir "$1" >/dev/null 2>&1; }

echo "${C_BOLD}=== Trackmania .Gbx Launcher Installer (Linux / Steam / Proton) ===${C_RESET}"
echo

check_dependencies

# 1. Steam command
STEAM_CMD="$(detect_steam_cmd || true)"
if [[ -n "$STEAM_CMD" ]]; then
    ok "Steam command: $STEAM_CMD"
else
    warn "Could not find 'steam' in PATH or Flatpak."
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
        STEAM_CMD="steam"
    else
        read -rp "Enter command to launch Steam [steam]: " STEAM_CMD
        STEAM_CMD="${STEAM_CMD:-steam}"
    fi
fi

# 2. Steam directory
STEAM_DIR="$(detect_steam_dir || true)"
if [[ -n "$STEAM_DIR" ]]; then
    ok "Steam directory: $STEAM_DIR"
else
    warn "Could not auto-detect Steam directory."
    STEAM_DIR="$(prompt_path "Enter your Steam root directory (containing steamapps/)" is_steam_dir)"
fi

# 3. Trackmania game directory
GAME_DIR="$(detect_game_dir "$STEAM_DIR" || true)"
if [[ -n "$GAME_DIR" ]]; then
    ok "Trackmania install: $GAME_DIR"
else
    warn "Could not auto-detect Trackmania installation (Trackmania.exe)."
    GAME_DIR="$(prompt_path "Enter path to Trackmania folder (containing Trackmania.exe)" is_game_dir)"
fi

# 4. Trackmania Proton compatdata directory
COMPAT_DATA="$(detect_compat_data "$STEAM_DIR" || true)"
if [[ -n "$COMPAT_DATA" ]]; then
    ok "Proton prefix (compatdata): $COMPAT_DATA"
else
    warn "Could not auto-detect Trackmania Proton prefix (compatdata/$APPID)."
    warn "Tip: Launch Trackmania at least once via Steam so Proton creates its prefix."
    COMPAT_DATA="$(prompt_path "Enter path to compatdata/$APPID folder (containing pfx/)" is_compat_dir)"
fi

# 5. Proton wine binary
PROTON_WINE="$(detect_proton_wine "$STEAM_DIR" "$COMPAT_DATA" || true)"
if [[ -n "$PROTON_WINE" ]]; then
    ok "Proton wine binary: $PROTON_WINE"
else
    warn "Could not auto-detect Proton installation."
    raw_proton="$(prompt_path "Enter path to your Proton folder (or directly to its wine binary)" is_proton_path)"
    PROTON_WINE="$(find_wine_in_proton_dir "$raw_proton")"
fi

# 6. Optional: symlink a custom maps folder into Trackmania's Maps directory
MAPS_SYMLINK_PATH=""
if [[ "$NON_INTERACTIVE" -eq 0 ]]; then
    echo
    info "Optional: Symlink a local maps folder into Trackmania's in-game Maps directory."
    info "This lets you also browse downloaded maps in-game under: Local -> Play a map."
    read -rp "Path to your local maps folder (leave empty to skip): " USER_MAPS_INPUT
    if [[ -n "$USER_MAPS_INPUT" ]]; then
        USER_MAPS_DIR="$(expand_path "$USER_MAPS_INPUT")"
        if [[ ! -d "$USER_MAPS_DIR" ]]; then
            read -rp "Directory '$USER_MAPS_DIR' does not exist. Create it? [Y/n]: " create_ans
            if [[ "${create_ans:-Y}" =~ ^[Yy]$ ]]; then
                mkdir -p "$USER_MAPS_DIR"
            else
                warn "Skipping maps symlink."
                USER_MAPS_DIR=""
            fi
        fi

        if [[ -n "${USER_MAPS_DIR:-}" && -d "$USER_MAPS_DIR" ]]; then
            read -rp "Folder name to show inside Trackmania Maps [CustomMaps]: " SYMLINK_NAME
            SYMLINK_NAME="${SYMLINK_NAME:-CustomMaps}"
            TM_MAPS_DIR="$COMPAT_DATA/pfx/drive_c/users/steamuser/Documents/Trackmania/Maps"
            mkdir -p "$TM_MAPS_DIR"
            MAPS_SYMLINK_PATH="$TM_MAPS_DIR/$SYMLINK_NAME"
            ln -sfn "$USER_MAPS_DIR" "$MAPS_SYMLINK_PATH"
            ok "Created symlink: $MAPS_SYMLINK_PATH -> $USER_MAPS_DIR"
        fi
    fi
fi

# 7. Install config, launcher script, MIME type, and .desktop entry
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/trackmania-gbx-linux"

mkdir -p "$BIN_DIR" "$DATA_DIR/mime/packages" "$DATA_DIR/applications" "$CONFIG_DIR"

# Write config
cat > "$CONFIG_DIR/config" <<EOF
# Generated by trackmania-gbx-linux install.sh
APPID="$APPID"
STEAM_CMD="$STEAM_CMD"
STEAM_DIR="$STEAM_DIR"
GAME_DIR="$GAME_DIR"
COMPAT_DATA="$COMPAT_DATA"
PROTON_WINE="$PROTON_WINE"
MAPS_SYMLINK_PATH="$MAPS_SYMLINK_PATH"
EOF
ok "Saved config: $CONFIG_DIR/config"

# Install launcher script
LAUNCHER_PATH="$BIN_DIR/trackmania-open-gbx"
install -m 755 "$SCRIPT_DIR/src/trackmania-open-gbx" "$LAUNCHER_PATH"
ok "Installed launcher: $LAUNCHER_PATH"

# Install MIME type definition
MIME_XML_PATH="$DATA_DIR/mime/packages/trackmania-gbx.xml"
install -m 644 "$SCRIPT_DIR/src/trackmania-gbx.xml" "$MIME_XML_PATH"
ok "Installed MIME definition: $MIME_XML_PATH"

# Generate and install .desktop entry
DESKTOP_PATH="$DATA_DIR/applications/trackmania-gbx.desktop"
sed -e "s|@EXEC_PATH@|$LAUNCHER_PATH|g" \
    -e "s|@APPID@|$APPID|g" \
    "$SCRIPT_DIR/src/trackmania-gbx.desktop.in" > "$DESKTOP_PATH"
chmod 644 "$DESKTOP_PATH"
ok "Installed desktop entry: $DESKTOP_PATH"

# Refresh XDG databases and register default handler
if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database "$DATA_DIR/mime"
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DATA_DIR/applications"
fi
if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default trackmania-gbx.desktop application/x-trackmania-gbx
    ok "Registered default handler for .Gbx files (application/x-trackmania-gbx)"
fi

echo
echo "${C_GREEN}${C_BOLD}Installation complete!${C_RESET}"
echo "You can now double-click any .Map.Gbx / .Gbx file in your file manager,"
echo "or run from terminal: ${C_BOLD}$LAUNCHER_PATH /path/to/map.Map.Gbx${C_RESET}"
