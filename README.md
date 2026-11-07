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
| Clear menu bar, glass popups | Nearly clear menu bar (35% black veil keeps white text readable on bright wallpapers; Plasma can't switch the bar to dark text the way macOS does); dock, popups and Spotlight share one glass tint; re-applied at every login | `bin/plasma-sync-glass` |
| Menu bar right side | Battery, Sound (speaker or headphones glyph; menu with slider + output list, unplugged outputs hidden), Control Center, "Nov 8  3:04 AM" clock; no tray chevron, no Spotlight icon | `plasma-scripts/mac-layout.js`, `plasmoids/net.local.volume` |
| Cmd shortcuts | Cmd/Ctrl swapped in XKB, so Cmd+C/V/W/Q/Space work | `kxkbrc` |
| Spotlight (Cmd+Space) | Centred translucent search: apps, settings, calculator, unit and currency conversion | `plasmoids/net.local.spotlight` + `qml-blurbehind` |
| Control Center | Wi-Fi, Bluetooth, VPN, Focus/DND, per-screen brightness, volume + output, Now Playing, keyboard backlight, battery mode | `plasmoids/net.local.controlcenter` |
| Stats / iStat Menus | Menu-bar CPU/MEM/GPU sparklines, network Mbps, temp, watts; click for graphs, per-app CPU/memory/network, GPU load/clock/power/memory (Asahi `agx_stats`) | `plasmoids/net.local.macstats`, `bin/mac-stats*`, `system/bin/nethogs-feed` |
| Quick Look (Space) | Space previews in Dolphin and on the desktop, arrow keys move between files, big window | GNOME Sushi + `bin/quicklook`, `bin/sushi-launch`, `bin/desktop-quicklook-patch` |
| Lock screen (26/27) | Macintosh live wallpaper animates behind a Liquid Glass stencil clock (date above, no AM/PM), password pill appears on input; on unlock the desktop wallpaper continues from the same frame and eases to a stop over ~5 s | `lockscreen/`, `qml-lockwatch/`, `systemd/user/plasma-kwin_wayland.service.d/`, `wallpapers/net.local.macintosh` |
| Volume / brightness HUD (27.2) | Clear Liquid Glass capsule under the menu bar, top right, outlined glyph (headphones when they're the output), thin 16-segment bar | `osd/` (+ `qml-blurbehind`) |
| Screenshots | Cmd+Shift+3 / 4 / 5 to the Desktop, add Ctrl for clipboard | `config/applications/mac-shot-*` + kglobalaccel |
| BetterDisplay brightness | Brightness keys change only the display under the mouse (DDC/CI on externals); the built-in panel steps 2.5% in perceived lightness (CIE L*), like macOS, instead of linear nits | `bin/brightness-here*` |
| AlDente | Battery charge limit (default 80%) that survives reboots; above the limit it discharges while plugged in (Asahi `auto-discharge`) | `system/bin/battery-limit` |
| Bluetooth audio | LDAC locked at its top bitrate (909/990 kbps, measured ~1 Mbps on air) instead of adaptive (~660 kbps here) | `config/wireplumber/52-bluez-ldac-hq.conf` |
| Sony Clear Bass on LDAC | WH-1000XM3 ignores its own EQ on LDAC, so PipeWire applies a Clear Bass-style tune (−6 dB preamp, +6 dB low shelf at 120 Hz) as a smart filter in front of the headset only; hidden from output lists | `config/pipewire/60-sony-clearbass.conf` (edit `filter.smart.target` for your headset's `bluez_output.<MAC>.1`) |
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
osd/                replacement Plasma OSD (Osd.qml), shadowing the system module
qml-blurbehind/     tiny C++ QML plugin: ask KWin to blur behind a QML item
plasma-scripts/     Plasma scripting snippets (panel widgets, tray, launcher icon)
config/             launchers, D-Bus services, Dolphin service menu, Konsole, fontconfig, KRunner plugins
docs/LESSONS.md     traps and how they were solved
```

`wallpapers/net.local.macintosh` contains Apple's Macintosh artwork and two of Apple's scene scripts, for
personal use only. **Keep this repository private.**

Files containing `@HOME@` are templates; the installer substitutes your home directory.
