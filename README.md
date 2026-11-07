# kde-macos-parity

Make KDE Plasma 6 (Wayland) look and behave as close to macOS as practical. Built and used daily on a
MacBook Pro 16" M1 Max running Asahi Arch Linux ARM with Plasma 6.8, an LG 4K, a side monitor,
a Logitech MX Keys and an MX Master 3.

Everything is user-level except three small root services. All of it is idempotent and backs up what it
touches to `~/kde-pre-mac-backup/`.

> Agents: read [AGENTS.md](AGENTS.md) before running anything. It has the order of operations, the
> verification method for each piece, and the traps that cost hours the first time
> ([docs/LESSONS.md](docs/LESSONS.md)).

## What you get

| macOS | Here | How |
|---|---|---|
| Menu bar + Dock | Top panel (Apple logo launcher, global menu, tray, clock) and auto-hiding dock on every screen | Plasma panels |
| Look | WhiteSur Plasma style, icons, cursors, window decoration, SF Pro / SF Mono fonts | WhiteSur (upstream), AUR `apple-fonts`, `config/fontconfig` |
| Light / Dark switch | "macOS Light" / "macOS Dark" global themes that keep the macOS look | `look-and-feel/` |
| Same glass everywhere | Menu bar, dock, popups and Spotlight share one tint over KWin blur, re-synced at every login | `bin/plasma-sync-glass` |
| Cmd shortcuts | Cmd/Ctrl swapped in XKB, so Cmd+C/V/W/Q/Space work | `kxkbrc` |
| Spotlight (Cmd+Space) | Centred translucent search: apps, settings, calculator, unit and currency conversion | `plasmoids/net.local.spotlight` + `qml-blurbehind` |
| Control Center | Wi-Fi, Bluetooth, VPN, Focus/DND, per-screen brightness, volume + output, Now Playing, keyboard backlight, battery mode | `plasmoids/net.local.controlcenter` |
| Stats / iStat Menus | Menu-bar CPU/MEM sparklines, network Mbps, temp, watts; click for graphs, per-app CPU/memory/network | `plasmoids/net.local.macstats`, `bin/mac-stats*`, `system/bin/nethogs-feed` |
| Quick Look (Space) | Space previews in Dolphin and on the desktop, arrow keys move between files, big window | GNOME Sushi + `bin/quicklook`, `bin/sushi-launch`, `bin/desktop-quicklook-patch` |
| Screenshots | Cmd+Shift+3 / 4 / 5 to the Desktop, add Ctrl for clipboard | `config/applications/mac-shot-*` + kglobalaccel |
| BetterDisplay brightness | Brightness keys change only the display under the mouse (DDC/CI on externals) | `bin/brightness-here*` |
| AlDente | Battery charge limit (default 80%) that survives reboots | `system/bin/battery-limit` |
| MX Keys in Mac mode | Logitech keyboards switched to macOS layout on every connect | `bin/logi-macmode` (Solaar) |
| Windows reopen where you left them | KWin "remember" rules per app | AGENTS.md step 9 |
| Terminal | Konsole "Mac" profile, translucent dark scheme, Source Code Pro for Powerline | `config/konsole` |
| Macintosh live wallpaper (Sequoia) | Susan Kare 1-bit scenes as tilted coloured pixel tiles that zoom, scroll and animate; Spectrum and 10 other colours; 10 scenes | `wallpapers/net.local.macintosh` |
| Aerial wallpaper | Apple aerial videos via Smart Video Wallpaper Reborn | AGENTS.md step 11 |

## Not possible (and why)

- **XDR / HDR brightness boost**: the Asahi display driver tops out at 500 nits SDR and has no HDR.
- **Real AirDrop**: no Apple protocol support; KDE Connect is the nearest thing.
- **Focus modes other than Do Not Disturb**: no Linux equivalent.
- **Reading Apple's own wallpaper bundles from the macOS partition**: Apple silicon volumes are
  hardware-encrypted; apfs-fuse fails at KeyManager.
- **Restyling KRunner**: its UI is compiled into the binary, so Spotlight is a separate widget on
  KRunner's engine (Milou).

## Install

```bash
./install.sh deps        # pacman packages (sudo)
./install.sh             # all user-level steps, then restarts plasmashell
./install.sh system      # battery limit, per-app network feed, SF font priority (sudo)
./install.sh list        # individual steps
```

Then follow the manual steps in AGENTS.md (WhiteSur theme, fonts, panel order, window rules, wallpaper).

## Layout

```
bin/                user helpers (installed to ~/.local/bin)
systemd/user/       user services for those helpers
system/             root helpers + units (battery-limit, nethogs-feed)
plasmoids/          Spotlight, Control Center, Mac Stats widgets
wallpapers/         Macintosh live wallpaper (interprets Apple's .program scene scripts)
look-and-feel/      macOS Light / macOS Dark global themes
qml-blurbehind/     tiny C++ QML plugin: ask KWin to blur behind a QML item
plasma-scripts/     Plasma scripting snippets (panel widgets, tray, launcher icon)
config/             launchers, D-Bus services, Dolphin service menu, Konsole, fontconfig, KRunner plugins
docs/LESSONS.md     traps and how they were solved
```

`wallpapers/net.local.macintosh` contains Apple's Macintosh artwork and two of Apple's scene scripts, for
personal use only. **Keep this repository private.**

Files containing `@HOME@` are templates; the installer substitutes your home directory.
