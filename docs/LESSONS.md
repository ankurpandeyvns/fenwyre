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

## Brightness curve (Apple panel)
- `apple-panel-bl` is linear in nits (0..500). Equal percentage steps look drastic at the bottom
  (1% → 5% → 10% = 5 → 25 → 50 nits). Step in CIE L* instead: Y = ((L+16)/116)^3 (L > 8), else L/903.3.
- `kscreen-doctor` brightness is integer percent; PowerDevil's `org.kde.ScreenBrightness` displays take
  0..10000, fine enough for the low end. `KWin.activeOutputName` follows the mouse — test with an override,
  not with whatever screen the pointer happens to be on.

## Sound
- Stock `org.kde.plasma.volume` picks its panel icon with `AudioIcon.forVolume(...)` only (QML compiled into
  the .so, zstd-compressed); it never shows headphones. Volume keys and the OSD come from plasma-pa's kded
  `audioshortcutsservice`, so the applet can be replaced safely (`plasmoids/net.local.volume`).
- Headphones: `sink.formFactor` is `headset`/`headphone` for Bluetooth; for the jack, the active port name has
  "headphone" and `availability !== 2` (2 = unplugged). The OSD override can import
  `org.kde.plasma.private.volume` and read `PreferredDevice.sink` itself.
- LDAC defaults to adaptive bitrate; on this M1 Max it ran at ~660 kbps and sounded thinner than AAC.
  `bluez5.a2dp.ldac.quality` is a **device** property: set it in `monitor.bluez.rules` (`update-props`),
  not `monitor.bluez.properties` (silently ignored there). Verify on the air, not by ear:
  `sudo timeout 4 btmon`, sum `< ACL ... dlen` over the time span (hq ≈ 1 Mbps incl. overhead).
- WirePlumber remembers the chosen card profile/codec in `~/.local/state/wireplumber/default-profile`.
- Before restarting WirePlumber, mute the built-in speakers: the Bluetooth sink vanishes for a few seconds and
  playback falls back to the speakers.
- Per-headphone EQ without an app: PipeWire `filter-chain` with `filter.smart = true` and
  `filter.smart.target = { node.name = "bluez_output.<MAC>.1" }` in `capture.props`. WirePlumber inserts it in
  front of that sink only, the sink stays the default (hardware volume intact), and it disappears when the
  headset does. Give it headroom (preamp `linear` Mult < 1) before boosting, or the encoder clips.
  Its `effect_input.*` sink still shows in `SinkModel`: filter it out of output pickers.

## Lock screen
- The greeter (`kscreenlocker_greet`, spawned by KWin) loads `contents/lockscreen/` from the Plasma/Shell package
  named by `PLASMA_DEFAULT_SHELL`. Setting it only on `plasma-kwin_wayland.service` (systemd drop-in) changes the
  lock screen without switching plasmashell's desktop shell. Takes effect at the next login.
- `kscreenlocker_greet --testing` takes real keyboard input from the session: anything typed while it runs goes
  into its password field. Don't run it while the user is typing.
- The wallpaper hands off between greeter and desktop through `$XDG_RUNTIME_DIR` state plus a lock watcher
  (`org.freedesktop.ScreenSaver` ActiveChanged) in `qml-lockwatch/`.

## Helium (Chromium) hardware video on Asahi
- Asahi's AVD decoder is exposed through VA-API (`libva-v4l2-request`): H.264, HEVC, VP9, no AV1 on M1/M2.
  Helium needs `--enable-features=VaapiVideoDecoder,VaapiIgnoreDriverChecks,AcceleratedVideoDecodeLinuxGL,...`
  and `--ignore-gpu-blocklist`; YouTube prefers AV1, so an extension hides AV1 from `isTypeSupported`,
  `canPlayType` and `mediaCapabilities`.
- `--load-extension` needs `--disable-features=DisableLoadExtensionCommandLineSwitch` on newer Chromium.
- `helium-wrapper` escapes `~` in the flags file with a bash pattern that also matches `$HOME`; don't rely on
  home paths there behaving literally.
- Verify: `chrome://media-internals` → `kVideoDecoderName = VaapiVideoDecoder`, or the GPU process holds
  `/dev/video*` fds.

## Installer design
- Features are user-facing and chosen by the user (AGENTS.md Step 0, AskUserQuestion). Each maps to small units;
  `apply` de-duplicates units and runs them in one fixed order (layout and plasmashell restart last).
- 4 groups x 4 features matches AskUserQuestion's limits (4 questions, 4 options each). Keep it that way when
  adding features, or split into a second call.

## Login screen (SDDM)
- SDDM's greeter runs its own KWin as user `sddm`, with its own `/var/lib/sddm/.config/kwinoutputconfig.json`, so
  rotation/scale/primary from your session don't apply there. Copy yours over (what System Settings' "Apply Plasma
  Settings" does).
- SDDM shows the theme on every screen; the stock Breeze form appears on all of them. The `breeze-mac` copy shows it on
  `theme.conf primaryOutput` only (falls back to SDDM's `primaryScreen`).
- To hide sessions without uninstalling them (Hyprland/Omarchy), point `[Wayland] SessionDir` at a directory holding
  only a symlink to `plasma.desktop`. The greeter logs which session files it read.
- Autologin hides the greeter at boot; you only see it after logging out.
- Lock clock "Stencil" = SF Pro Rounded Heavy glyphs with gaps cut (`destination-out` lines) at stroke junctions,
  positions measured on the outlines (`cuts` table in `GlassClock.qml`). Apple's own lock-screen clock face is a
  private system font (not in the public SF downloads); copy it from your own macOS install if you want it exact.
- Testing Qt Quick shaders: `QT_QPA_PLATFORM=offscreen` falls back to the software renderer (ShaderEffect/MultiEffect
  draw nothing) and offscreen OpenGL fails to build pipelines on Asahi; render in a real window with
  `Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput` and `grabToImage`. Qt logs go to the journal unless
  `QT_FORCE_STDERR_LOGGING=1`. Compile `.qsb` with `qsb --glsl "300 es,330,440"` (other targets fail to link).

## Narrow screens
- A portrait 1080p monitor at 1.25 gives an 864 px menu bar: app menu + stats push the clock off. Mac Stats has a
  Hidden Bar-style « » toggle that appears only when the bar overflows: the panel GridLayout's width vs the other
  widgets' `Layout.minimumWidth` (spacer ~1, app menu = its menus) plus the stats at full width. `Screen.*` inside a
  panel widget reported eDP-1 on every screen, so don't size by screen.

## Fans (M1 Max, Asahi)
- Stock `macsmc-hwmon` (linux-aurora): `fan_control=1` makes `fanN_target` writable, but only `min..max` or 0
  (= back to the SMC); the SMC idles the fans at their minimum (~1500 rpm), never 0 like macOS. SoC die sensors and
  the debugfs key list (`/sys/kernel/debug/macsmc-hwmon/keys`) are gated to M3 machines.
- The patch (`system/fan/`) adds t6000/1/2 to that gate and `fan_stop=1`: a target between 1 and the minimum writes
  manual mode with target 0, and the SMC stops the fan (verified: 0 rpm, back to ~1550 rpm within ~3 s on 0).
- M1 Pro/Max die keys (Stats `values.swift`): Tp01..Tp0b P-cores, Tp09/Tp0T E-cores, Tg05/0D/0L/0T GPU. Each comes in
  a triplet (x0/x1/x2); x1 is what Stats shows, x2 runs ~5 C hotter.
- The kernel is clang-built but has no CFI/LTO/randstruct/modversions, so a gcc-built module loads fine.
- Apple doesn't publish fan curves; macOS keeps these fans at 0 rpm at idle and lets the chip run hot before
  ramping. A fixed curve with a 6 C hysteresis kept the fans on forever (this chip idles at 55-59 C with animated
  wallpapers) and a 4 s burst to 66 C started them. mac-fand's "macos" profile is a silence-first controller instead:
  10 s smoothing, 30 s least-squares trend, 60 s prediction; start at 60 C only if the prediction reaches 70 C;
  creep up by 0.15% of the fan range per cycle per degree the prediction exceeds 80 C; full speed only at 90 C+,
  still rising, fans already past 60%; stop below 58 C after 30 s.
- LDAC `hq` (990 kbps) skips now and then even with clean PipeWire (0 errors in `pw-top`), Wi-Fi on 5 GHz and a
  20 s btmon capture with no stalls: brief radio dips with nothing to back off to. Adaptive (`auto`) avoids that at
  the cost of a lower bitrate most of the time; the user chose adaptive.


## Per-app GPU usage (asahi)

- The asahi DRM driver exposes no `drm-engine-*` keys in fdinfo, so nvtop/Activity Monitor-style per-process GPU %
  is not available from the usual source. `agx_stats` `busy_ns` gives only the total.
- The `gpu_scheduler` tracepoints work: `drm_sched_job_queue` fires in the submitting thread (its pid, mapped to the
  tgid, owns the fence context), `drm_sched_job_run`/`drm_sched_job_done` bracket each job. `client_id` is always 0 on
  asahi, so don't key on it. Split overlapping jobs' elapsed time between them, then scale the shares by `busy_ns`
  utilization. Checked against SIGSTOP-ing the suspect: pausing Helium's GPU process dropped busy 57% → 9%, and the
  feed attributed ~69% of GPU time to it.
- ~3000 events/s on a busy desktop: tracing continuously from Python costs ~8% of a core; sampling 1 s of every 2
  costs ~2%. Use a private tracefs instance (`instances/mac_stats_gpu`) so the global trace buffer is untouched.
- Utilization is busy time at the *current* clock: 56% at 388 MHz (pstate 1 of 1296 MHz) is a small amount of work
  at ~2 W. Hardware video decode (`/dev/video0` = `avd`) only takes the decoding off the GPU; Chromium still uses the
  GPU to convert/scale each frame and composite the page, and KWin composites it again.
- MX Keys in Mac mode: the lock key sends LEFTMETA+LEFTCTRL+Q (macOS Ctrl+Cmd+Q), not a lock keycode. After the
  Cmd/Ctrl XKB swap KDE still sees Meta+Ctrl+Q; bind it to ksmserver "Lock Session" (unit_mxkeys).
- Helium video GPU cost (2026-11-08): 1080p60 H.264 in a ~1400x850 window costs ~5% GPU with avd decode, and
  `WaylandOverlayDelegation` made no measurable difference (4.8% vs 5.0%), so it is not enabled. A maximized YouTube
  tab on eDP (3456x2176 px at 120 Hz) cost ~35%; pausing the YouTube renderer halved it, i.e. page work (Ambient mode
  glow, UI) rather than decoding. KWin's `KWIN_USE_OVERLAYS` (opt-in, needs a new login) is untested on Apple DCP.
- GPU "%": `busy_ns` is busy time at whatever clock the GPU runs, and asahi idles it at the lowest pstate (388 of
  1296 MHz), so a light desktop reads ~30% busy. The firmware's `util1..4` are the same kind of number (DVFS load
  at the current clock). Mac Stats shows **Load** = busy time weighted by clock / max clock, sampled every 50 ms by
  gpu-feed (the clock changes many times a second; one sample per 2 s is wrong). Raw busy stays as "Busy time".
