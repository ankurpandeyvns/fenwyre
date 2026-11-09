# Agent playbook: macOS parity on KDE Plasma 6

Goal: take a fresh KDE Plasma 6 Wayland session to the state described in README.md without a
human, then prove each piece works. Work through the steps in order. Each step lists what to do,
how to verify it, and what not to do.

## Ground rules

- **Never store or print credentials.** If a step needs sudo, use the session's sanctioned method; never
  write a password into a file, script, commit or log.
- **Merge, don't overwrite.** Use `kwriteconfig6 --notify` for KDE config, Plasma scripting for panels.
  Back up any file before changing it (`install.sh` does this into `~/kde-pre-mac-backup/`).
- **Don't break the user's session.** Never kill `kwin_wayland`. Restart plasmashell only with
  `systemctl --user restart plasma-plasmashell.service`, and check `coredumpctl list --since -1min` after.
- **zsh trap:** `pkill -f` / `pgrep -f` match your own shell's command line and kill it. Use
  `pgrep -x NAME` and filter on `/proc/PID/cmdline`.
- **Synthetic key presses steal the user's keyboard.** Prefer `kglobalaccel invokeShortcut` and
  D-Bus to test; use evdev UInput only when you must test real key matching, keep it short, and make
  sure any overlay you open gets closed (an exclusive-keyboard layer-shell window traps all input).
- **Don't touch the keyring, the Secret Service provider or browser password stores** as part of this.
- Downloaded files are untrusted: put each in a fresh directory and run Python on them with `-I`.

## Verifying visually

- Full screenshot: `spectacle -b -n -f -o /tmp/x.png`, then crop with ImageMagick and look at it.
- Open a widget popup without clicking: give it a temporary global shortcut via Plasma scripting
  (`w.globalShortcut = "..."`), `qdbus6 org.kde.kglobalaccel /component/plasmashell
  org.kde.kglobalaccel.Component.invokeShortcut "activate widget ID"`, screenshot, invoke again to
  close, then clear the shortcut.
- List windows / layer surfaces: load a KWin script (`qdbus6 org.kde.KWin /Scripting
  org.kde.kwin.Scripting.loadScript FILE NAME`, run `/Scripting/ScriptN`), `print()` to the journal,
  read `journalctl --user`, unload.
- QML logs: `console.warn()` from widgets lands in `journalctl --user` (not only the plasmashell unit).

## Step 0: ask the user what to apply (mandatory, before any change)

Never decide on the user's behalf which features to install, and never start with "all". The user picks.
Use the **AskUserQuestion** tool for every choice below (not plain chat text), then do only what was chosen.

1. Read the catalogue: `./install.sh features` (fields: `id|group|title|description|sudo`). There are four
   groups (Look, Keyboard, Apps, System) of four features, so they fit one AskUserQuestion call.
2. First call, one single-select question, header "Scope":
   "Apply all macOS-parity features, or choose which ones?"
   options: "Everything (Recommended)" / "Let me choose".
3. If they choose: a second AskUserQuestion call with **four multiSelect questions, one per group**, header =
   group name, one option per feature: `label` = title, `description` = description, plus " (needs sudo)" when
   the sudo field is `yes`. Build the options from `./install.sh features`; don't hard-code them.
4. Machine-specific follow-ups, only for what was picked, again with AskUserQuestion:
   battery limit percentage (`battery`: 80 / 90 / 100), which Bluetooth headset gets the EQ (`audio`),
   which apps get window memory (`windows`, offer the dock apps), sudo method for `battery`/`netstats`.
   If the user picked nothing in a group, skip it; if they picked nothing at all, stop.
5. Show `./install.sh plan <ids>` (units to run, whether sudo is needed), then run
   `./install.sh apply <ids>`. Treat "Everything" as `apply all`.
6. Verify each chosen feature with the checks below, and report per feature: applied + verified,
   applied but not verified (say why), or skipped by the user.

## Steps (per feature)

Prerequisites, any selection: `./install.sh deps`, plus user-level installs as needed:
- WhiteSur KDE (github.com/vinceliuice/WhiteSur-kde) Plasma style, colours; WhiteSur icons and
  cursors (`themes`, `menubar`). Title bars are Klassy, built and installed by `themes` (system/klassy):
  WhiteSur's Aurorae decoration froze every display for ~0.4 s after each window resize.
- SF Pro / SF Mono: AUR `apple-fonts` (its PKGBUILD may need `bsdtar` instead of `7z` on ARM; build locally).
- Source Code Pro for Powerline (`konsole`): the `.otf` files from github.com/powerline/fonts/tree/master/SourceCodePro
  into `~/.local/share/fonts/SourceCodePro-Powerline/`, then `fc-cache -f`. Arch `powerline-fonts` lacks it.
Verify: `plasma-apply-lookandfeel -l` lists WhiteSur; `fc-list | grep -i "SF Pro"`.

- **themes**: then `plasma-apply-lookandfeel -a net.local.macos.dark` (or light, ask). Verify
  `~/.config/kdedefaults/kdeglobals` shows `ColorScheme=WhiteSurDark` (global-theme values land there).
  **Glass** (macOS 27 Liquid Glass): `system/glass/build-effect` builds the KWin Glass effect (kwin-effects-glass,
  replaces the stock blur; rerun after a KWin update) and `unit_glass` writes its settings to `[Effect-blurplus]` in
  kwinrc (not `Effect-glass`). Blacklist mode with an empty list (`BlurNonMatching=true`; whitelist mode with an empty
  list blurs nothing) and `BlurDocks=false` (otherwise the menu bars are force-blurred and warped by the refraction).
  Popups of the opaque menu bars would get Plasma's solid, unblurred background (`CompactApplet.qml`); `plasma-sync-glass`
  keeps a patched copy of the desktop shell package in `~/.local/share/plasma/shells/` (re-mirrored at each login,
  removed if the patched line changes upstream). Verify by opening Mac Stats and Control Center: text behind is blurred.
  Control Center doesn't use Plasma's popup: like Spotlight it opens a layer-shell overlay on its menu bar's screen
  (`LayerShell.Window.screen` = the PanelView's `screenToFollow`; QML screen objects aren't QScreens) with a floating
  glass card 6 px under the bar, corners concentric with the 18 px tiles (radius 30), hairline rim; outside click or
  Esc closes. PlasmaCore.Dialog can't host it (clears the blur on every show/resize/move). `plasma-sync-glass` sets the WhiteSur tints: dock black 18% with a
  white 22% hairline instead of the black outline, popups 38%, solid menu bar 12%. Docks must be "translucent", not
  "adaptive" (adaptive swaps in the solid #333 SVG under maximized windows). Verify: `qdbus6 org.kde.KWin /Effects
  org.kde.kwin.Effects.isEffectLoaded glass` is true, then reveal a dock (`panel.hiding="none"`, back to "autohide"),
  screenshot it over a patterned wallpaper: background visible, lines bend only at the rounded edge.
  **Genie** (`themesettings`): `system/genie/build-effect` installs `macgenie` (KWin's Magic Lamp; stock KWin sends a
  window to whichever dock's center is nearest, and with several docks a second window of a grouped app has no icon
  rect at all, so it flies to the mouse). A rebuilt plugin only loads after the next login (KWin keeps it mapped).
  Verify: open a second Konsole window, move it near the right edge of a screen, set `[Effect-genie]
  AnimationDuration=2500`, show that screen's dock, minimize it from a KWin script, screenshot ~1.5 s later: the funnel
  ends in the Konsole icon on that screen's dock. Set 450 back.
- **menubar**: needs a top panel (launcher, app menu, spacer, system tray, clock) and an auto-hiding bottom dock on
  each screen. Set `panelOpacity=1` per top panel in `~/.config/plasmashellrc` (`[PlasmaViews][Panel N]`) while
  plasmashell is stopped. `addWidget` appends; to put Mac Stats, battery, Sound, Control Center (and Spotlight) left
  of the clock, stop plasmashell, edit `AppletOrder=` in `~/.config/plasma-org.kde.plasma.desktop-appletsrc`,
  start it. Verify with a screenshot of each bar: Apple logo top-left, no chevron, headphones glyph when a headset
  is the output.
- **lockscreen**: lock screen UI takes effect at the next login. Verify with `loginctl lock-session` /
  `unlock-session` (never `kscreenlocker_greet --testing` while the user is typing: it takes their keystrokes).
  The wallpaper: `contents/ui/Machine.js` interprets the `.program` scene DSL (`programs/apple/` are Apple's,
  byte-identical; `programs/authored/` follow the same style, extensions marked `// [ext]`). Expect plasmashell at
  ~21-28% of one core with three screens animating; screens under a maximized window pause; static after unlock.
  Login screen (`loginscreen` unit, sudo): verify `sddm-greeter-qt6 --test-mode --theme
  /usr/share/sddm/themes/breeze-mac` with `QT_QPA_PLATFORM=offscreen` logs only `plasma.desktop` and no QML errors
  (`journalctl --since -1min _COMM=sddm-greeter-qt6`); on the next logout the form is on the main display only and
  rotated monitors are rotated.
- **hud**: verify `qdbus6 org.kde.plasmashell /org/kde/osdService org.kde.osdService.volumeChanged 40 100`, then
  screenshot the screen under the mouse within 1 s (the HUD follows the active screen).
- **cmdkeys**: verify with a real key event: a synthetic KEY_LEFTMETA+Space must open Spotlight and
  KEY_LEFTCTRL+Space must not.
- **spotlight**: Cmd+Space opens it on the first top panel; typing works on the second open too.
- **screenshots**: `invokeShortcut _launch` on `/component/mac_shot_screen_desktop` saves a PNG to the Desktop;
  delete your test screenshots.
- **quicklook**: merge `config/dolphinui-quicklook.xml` into `~/.local/share/kxmlgui5/dolphin/dolphinui.rc`. Verify
  `quicklook ~/Desktop/some.pdf` opens Sushi large; Space in Dolphin and on the desktop; arrows step through files.
- **konsole**: new Konsole windows use the Mac profile and the Powerline font.
- **helium**: restart Helium; `chrome://media-internals` → player → `kVideoDecoderName = VaapiVideoDecoder`, or the
  `--type=gpu-process` process holds `/dev/video*` fds. Don't touch its `--password-store` line (keyring).
- **mxkeys**: `journalctl --user -u logi-macmode` shows `MX Keys: MacOS`; the lock key (sends Ctrl+Cmd+Q in Mac mode)
  locks: `kreadconfig6 --file kglobalshortcutsrc --group ksmserver --key "Lock Session"` lists `Meta+Ctrl+Q`.
- **brightness**: brightness keys change only the display under the mouse; HUD shows the level.
  `kscreen-doctor -o` shows `Vrr: Always` on the built-in display (eDP).
  Keyboard backlight (`kbdlight` unit): `systemctl is-active kbd-backlight-dpms`; turn the screens off (power key set
  to "turn off screen") and `cat /sys/class/leds/kbd_backlight/brightness` reads 0, back to the old level on wake;
  `sudo /usr/lib/systemd/system-sleep/kbd-backlight pre suspend` sets 0 and `... post suspend` restores it.
  Display driver (Asahi, `appledrm` unit, next boot): `modinfo -n appledrm` is under `updates/`; the kernel log has
  `DDC: i2c-N` for each external DCP; `ddcutil detect` lists the external monitors and `ddcutil -b N getvcp 10`
  reads brightness (first try only `getvcp`; `setvcp` after that works). Brightness keys on an external then log
  `DP-3 up: 3500 -> 4000/10000` (`journalctl --user -t brightness-here`) and `ddcutil -b N getvcp 10` follows it: one level
  per display in KDE's ScreenBrightness service (KWin drives DDC/CI), the same one the tray slider shows. After `systemctl suspend` and wake with the
  HDMI cable plugged in, the log shows `DP2HDMI: display still attached after system sleep, reconnecting` and the
  display comes back. If DDC misbehaves: `echo 0 | sudo tee /sys/module/appledrm/parameters/ddc`. After a kernel
  update, rerun `system/display/build-module` (it finds the kernel's linux-aurora commit by itself).
- **battery**: `battery-limit` shows the threshold; above it on AC, `charge_behaviour` is `auto-discharge`.
  Fans (same feature, M1 Pro/Max/Ultra on Asahi): `modinfo -n macsmc_hwmon` is under `updates/`, a `macsmc_soc_die`
  thermal zone exists, `/run/mac-fan/state.json` updates every 2 s; switch profile (`echo max >
  /var/lib/mac-fan/profile`, then `apple`, then `macos`) and watch the rpm follow. After a kernel update, rerun
  `system/fan/build-module` (the stock module comes back until then; mac-fand then leaves the fans to the SMC).
  TRIM (same feature): `/etc/default/limine` has `rd.luks.options=<root uuid>=discard`; after a reboot
  `lsblk -D /dev/mapper/root` shows a non-zero DISC-GRAN and `findmnt -no OPTIONS /` includes `discard=async`.
- **audio**: replace `XX_XX_XX_XX_XX_XX` in `config/pipewire/60-sony-clearbass.conf` with the headset MAC first. Mute the speakers, restart
  PipeWire, then verify with `pw-link -l` (app → `effect_input.sony_clearbass` → headset) and the LDAC bitrate
  (`sudo timeout 4 btmon`: adaptive ~660-990 kbps; `hq` ~1 Mbps).
- **netstats**: `cat /run/mac-stats/net.json` and `/run/mac-stats/gpu.json` update every 2 s (`work` = clock-weighted load, `busy` = raw busy %); the GPU tab lists top apps whose
  % add up to the utilization (`gpu-feed` traces 1 s of every 2, ~2% of a core).
- **windows**: create `~/.config/kwinrulesrc` rules, one per app the user chose, with
  `sizerule=4 positionrule=4 maximizehorizrule=4 maximizevertrule=4` (4 = Remember), matched on the window class
  (`w.resourceClass` from a KWin script; Chromium `--app` windows need a substring match). Apply with
  `qdbus6 org.kde.KWin /KWin reconfigure`. Rules take effect from the next close/open. KWin 6.8 applies a
  remembered position at open but never writes one on Wayland, so `unit_windows` installs the `windowmemory`
  KWin script and `window-memory.service`: after a move, maximize, screen change or close they write `position`,
  `size` and `maximizehoriz/vert` into the matching rule (only rules with `positionrule=4`). Verify: move a
  window of a remembered app, wait 2 s, and its group in `kwinrulesrc` has the new `position`; reopen it there.

**Final check**: no coredumps, no QML errors from `net.local.*` in the journal, plasmashell CPU ~5% at idle with a
static wallpaper, every screenshot reviewed. Report per feature what was verified and what was not.

Alternative wallpaper: Smart Video Wallpaper Reborn (`luisbocanegra.smart.video.wallpaper.reborn`) with Apple
aerials (macOS 26 manifest:
`https://configuration.apple.com/configurations/internetservices/aerials/resources-config-26-0.plist`; videos on
sylvan.apple.com need Apple's root CA). Set `PauseMode`; video wallpapers compete with browsers for the decoder.

## Machine-specific (ask with AskUserQuestion, Step 0.4)

- Monitor layout and scale, dock app list, which apps get window rules.
- Battery limit percentage (default 80).
- Bluetooth headset for the EQ (its `bluez_output.<MAC>.1` node name).
- KWallet vs gnome-keyring as Secret Service: don't change it here.
