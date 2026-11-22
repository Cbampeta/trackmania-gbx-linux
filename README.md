# trackmania-gbx-linux

Open Trackmania (2020) `.Map.Gbx` / `.Gbx` files directly on Linux (Steam + Proton) by double-clicking them in your file manager — **both when the game is closed and when it is already running**, just like *"Open with Trackmania.exe"* on Windows.

## Features

- **Double-click `.Gbx` files anywhere** (`.Map.Gbx`, `.Replay.Gbx`, `.Challenge.Gbx`, `.gbx`) from your file manager or CLI.
- **Works when Trackmania is closed**: launches Trackmania via Steam (`-applaunch 2225070 "/file=Z:\..."`) straight into the map.
- **Works when Trackmania is already running**: injects the second `Trackmania.exe /file=...` call directly into the active Steam Linux Runtime (`pressure-vessel`) container via `nsenter` and the live `wineserver` environment, so Trackmania loads the new map immediately without restarting or hitting Ubisoft Connect single-instance errors.
- **Distro-agnostic & modular installer**: auto-detects native/Flatpak/Snap Steam, multiple Steam library drives (`libraryfolders.vdf`), Trackmania (`2225070`), and the exact Proton version (Experimental, official Proton, GE-Proton, etc.). If any path cannot be detected automatically, `./install.sh` prompts you for it.
- **Optional in-game Maps symlink**: optionally symlinks your local downloaded-maps directory into Trackmania's Proton `Maps/` folder so all maps also show up under **Local → Play a map**.

## Requirements

- **Trackmania (2020)** installed via Steam (AppID `2225070`) and launched at least once so Proton creates its prefix.
- Standard Linux utilities (pre-installed on almost all distros):
  - `bash`, `python3`, `nsenter` (`util-linux`), `pgrep` (`procps`), `realpath` (`coreutils`)
- Freedesktop desktop integration (for file manager double-click):
  - `shared-mime-info` (`update-mime-database`), `desktop-file-utils` (`update-desktop-database`), `xdg-utils` (`xdg-mime`)
- Optional: `libnotify` (`notify-send`) for desktop notifications.

## Installation

```bash
git clone https://github.com/<your-username>/trackmania-gbx-linux.git
cd trackmania-gbx-linux
chmod +x install.sh uninstall.sh
./install.sh
```

The installer will:
1. Auto-detect your Steam command, Steam root directory, Trackmania install directory, Proton prefix (`compatdata/2225070`), and Proton `wine` binary (prompting you interactively if anything isn't found).
2. Optionally ask if you want to symlink a local maps folder into Trackmania's `Maps/` directory.
3. Install:
   - `~/.local/bin/trackmania-open-gbx`
   - `~/.config/trackmania-gbx-linux/config`
   - `~/.local/share/mime/packages/trackmania-gbx.xml`
   - `~/.local/share/applications/trackmania-gbx.desktop`
4. Register **Trackmania (Open .Gbx)** as the default handler for `.Gbx` files.

For non-interactive installation (accepting all auto-detected paths):

```bash
./install.sh --yes
```

## Usage

- **File Manager**: Double-click any `.Map.Gbx` / `.Gbx` file (or right-click → *Open With → Trackmania (Open .Gbx)*).
- **Terminal**:
  ```bash
  ~/.local/bin/trackmania-open-gbx "/path/to/My Map.Map.Gbx"
  # or
  xdg-open "/path/to/My Map.Map.Gbx"
  ```

## How It Works

On Windows, opening a `.Map.Gbx` with `Trackmania.exe` while the game is already running spawns a short-lived second `Trackmania.exe` process that hands the `/file=...` path over to the active instance and exits.

On Linux with Steam + Proton, Trackmania runs inside a `SteamLinuxRuntime` (`pressure-vessel` / `srt-bwrap`) container. Running `wine Trackmania.exe` or `proton runinprefix` from outside that container fails with Ubisoft Connect / Proton errors (e.g. exit code `222`).

`trackmania-open-gbx` solves this by:
1. Converting the Linux path (or `file://` URI) to a Proton Windows path (`Z:\...`).
2. Checking whether `Trackmania\Trackmania.exe` is already running.
   - **Not running**: calls `steam -applaunch 2225070 "/file=Z:\..."`.
   - **Running**: locates the active `Trackmania.exe` PID and its sibling `wineserver`, enters the active container's user & mount namespaces without root (`nsenter -t <PID> -U -m --preserve-credentials`), dynamically picks the active Proton `wine` binary, and executes `Trackmania.exe "/file=Z:\..."` with the exact `wineserver` environment.

## Uninstallation

```bash
./uninstall.sh
```

## Troubleshooting

- **Check the log**: every launch logs to `/tmp/trackmania-open-gbx.log`.
- **Moved your Steam library or changed paths?** Just re-run `./install.sh` — it updates `~/.config/trackmania-gbx-linux/config` cleanly.
- **Switched Proton version in Steam?** When Trackmania is already running, `trackmania-open-gbx` automatically detects the active Proton `wine` binary from the running `wineserver`, so no reconfiguration is needed.

## License

MIT
