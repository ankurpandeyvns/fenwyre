# Lessons (each of these cost real time)

## KDE configuration
- **`kwriteconfig6 --notify` or nothing happens.** KWin ignores the old `org.kde.keyboard reloadConfig`
  signal; it reloads `kxkbrc` (and Night Light, and more) only on KConfig change notifications. Writing the file
  plainly leaves the setting dormant until the next login.
- `kxkbrc` options need `[Layout] Use=true` and a `LayoutList` to be applied.
- A global theme (look-and-feel) writes its values to `~/.config/kdedefaults/*`, not `~/.config/kdeglobals`.
- The Dark Mode toggle (Plasma's `DarkModeControl`) applies `DefaultLightLookAndFeel` /
  `DefaultDarkLookAndFeel` from `kdeglobals [KDE]`. Unset, it flips to stock Breeze and drops your icons.
- A launcher icon given as a file path doesn't recolour. Use a theme icon name (`start-here-kde-symbolic`)
  so it follows light and dark.

## Global shortcuts
- `KGlobalAccel.doRegister` + `setForeignShortcutKeys` store a shortcut that **never fires**. Use
  `setShortcutKeys(id, keys, 6)` (SetPresent | NoAutoloading) for `.desktop` launcher components.
- Shift+digit can arrive as the digit or as the shifted symbol (`#`, `$`, `%`). Bind both.
- Qt key codes: Ctrl `0x04000000`, Shift `0x02000000`, Alt `0x08000000`, Meta `0x10000000`.
- After swapping Cmd/Ctrl in XKB, physical Cmd is Ctrl and physical Ctrl is Meta. Bind accordingly.
- KRunner's UI is compiled in; you can't restyle it. Milou's `ResultsModel` gives you its engine in QML.

## Plasma widgets
- A `PlasmoidItem` with no `fullRepresentation` gets **no panel button at all**, even with
  `preferredRepresentation: compactRepresentation`. Add `fullRepresentation: Item {}`.
- `StackLayout` whose height binds to the current child's implicit height segfaults plasmashell (layout
  recursion). Use a `ColumnLayout` with `visible:` pages.
- `TabBar.onCurrentIndexChanged` fires during construction and clobbers state; use `TabButton.onClicked`.
- Reordering panel widgets: stop plasmashell, edit `AppletOrder=`, start it. Editing live gets overwritten.
- Debug timers in a widget run on every screen's instance; gate them on `Plasmoid.containment.screen === 0`.
- Another process editing `plasma-org.kde.plasma.desktop-appletsrc` while plasmashell runs can drop
  widgets. Re-list panel widgets after any concurrent change.
- Layer-shell overlay (`org.kde.layershell`): with exclusive keyboard focus, call `requestActivate()` and
  re-focus the text field on `onActiveChanged`, or typing goes nowhere after the first open.
- QML has no blur API. `qml-blurbehind/` wraps `KWindowEffects::enableBlurBehind` with a rounded region.
  Plasma needs `QML_IMPORT_PATH` (set via `~/.config/environment.d` and `systemctl --user set-environment`).
- WhiteSur panel and dialog backgrounds ship different tints (black 45% vs grey 65%). Blur strength is global
  in KWin; the tint is what makes them differ.

## OSD (volume/brightness pop-up)
- plasmashell loads `Osd` from the QML module `org.kde.plasma.workspace.osd`. A copy earlier on
  `QML_IMPORT_PATH` wins only if its `qmldir` drops the `prefer :/...` line (otherwise the files compiled
  into the plugin are used). Symlink the system `libplasmashell_osd.so` for `OsdWindow`.
- `OsdWindow` accepts `LayerShell.Window.*` attached properties, so the OSD can be anchored top-right.
- After a Plasma update, if the OSD stops appearing, check `journalctl --user | grep -i osd`: the override
  may need refreshing from the new stock `Osd.qml`/`OsdItem.qml`.

## Quick Look
- GNOME Sushi (`org.gnome.NautilusPreviewer2.ShowFile`) is the best previewer. It caps its window at 50%
  of the screen and, on KWin, sizes before it has a monitor (null → tiny window). Fix both with a
  `G_RESOURCE_OVERLAYS` copy of `mainWindow.js` (`bin/sushi-launch`).
- Sushi emits `SelectionEvent(direction)` on arrow keys; answer it by showing the next file.
- Dolphin service-menu actions are bindable as `servicemenu_<file>.desktop::<action>`; Space belongs to
  selection mode until you clear it.
- The Plasma desktop is a separate FolderView. Patch a local copy of `org.kde.desktopcontainment`, and re-check
  the patch after every Plasma update (`bin/desktop-quicklook-patch`). Its URLs are `desktop:/Name`.

## Hardware / Asahi
- Apple silicon macOS volumes can't be read from Linux (hardware-encrypted; apfs-fuse KeyManager fails).
- The MX Keys "Windows" mode sends Alt from the key labelled cmd. Solaar `multiplatform` = MacOS fixes it, but
  the keyboard forgets on reconnect unless something re-applies it.
- Per-app network data needs root (nethogs); feed it to the widget through `/run/mac-stats/net.json`.
- A video wallpaper and browser video share the hardware decoder; pause the wallpaper under windows.

## Process
- Screenshot every visual change; "looks right in code" was wrong several times.
- Keep a progress log with backups listed, so any change can be reverted.

## GPU stats (Asahi AGX)
- The asahi DRM driver exposes `/sys/class/drm/cardN/device/agx_stats` (`busy_ns`, `jobs`, `pstate`, `power_mw`,
  `util1..4`) and `gpu_memory` (`user_resident`, `kernel_resident`). Utilization = Δbusy_ns / Δwall time.
  `pstate` indexes `/sys/firmware/devicetree/base/opp-table-gpu/opp*/opp-hz` (big-endian u64; M1 Max tops out at
  1296 MHz). There is no per-process GPU fdinfo, and `temperature_raw` has no documented scale, so neither is shown.
