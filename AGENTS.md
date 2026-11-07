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

## Steps

1. **Packages**: `./install.sh deps`. Also install, user-level:
   - WhiteSur KDE (github.com/vinceliuice/WhiteSur-kde) Plasma style, colours, Aurorae decoration;
     WhiteSur icon theme and cursors.
   - SF Pro / SF Mono: AUR `apple-fonts` (its PKGBUILD may need `bsdtar` instead of `7z` on ARM; build locally).
   - Source Code Pro for Powerline: the `.otf` files from github.com/powerline/fonts/tree/master/SourceCodePro into
     `~/.local/share/fonts/SourceCodePro-Powerline/`, then `fc-cache -f`. The Arch `powerline-fonts` package does
     not include it.
   Verify: `plasma-apply-lookandfeel -l` lists WhiteSur; `fc-list | grep -i "SF Pro"`.

2. **User files and widgets**: `./install.sh bin plasmoids blur files services`.
   Verify: `ls ~/.local/share/plasma/plasmoids`; `systemctl --user is-active quicklook-nav logi-macmode`.

3. **Settings**: `./install.sh settings`. Then `plasma-apply-lookandfeel -a net.local.macos.dark`.
   Verify the Cmd/Ctrl swap with a real key event: a synthetic KEY_LEFTMETA+Space must open Spotlight and
   KEY_LEFTCTRL+Space must not. Verify the theme took: `~/.config/kdedefaults/kdeglobals` shows
   `ColorScheme=WhiteSurDark` (Plasma writes global-theme values there, not to `~/.config/kdeglobals`).

4. **Panels**: build a top panel (launcher, app menu, spacer, system tray, clock) and an auto-hiding bottom
   dock (icon task manager, trash) on each screen, translucent. Then `./install.sh layout`.
   `addWidget` appends; to put Mac Stats, Control Center and Spotlight just left of the clock, stop plasmashell,
   edit `AppletOrder=` for the panel in `~/.config/plasma-org.kde.plasma.desktop-appletsrc`, start it again.
   Verify with a screenshot of each bar: Apple logo top-left, tray icons only inside the chevron, Spotlight
   magnifier visible.

5. **Shortcuts**: `./install.sh shortcuts`, restart plasmashell.
   Verify: `invokeShortcut _launch` on `/component/mac_shot_screen_desktop` saves a PNG to the Desktop; a
   synthetic Meta(=Cmd)+Shift+3 does too. Delete your test screenshots.

6. **Quick Look**: merge `config/dolphinui-quicklook.xml` into `~/.local/share/kxmlgui5/dolphin/dolphinui.rc`.
   Verify: `quicklook ~/Desktop/some.pdf` opens Sushi at a large size; Space in Dolphin and on the desktop;
   arrow keys step through files.

7. **Logitech**: `logi-macmode` sets Solaar `multiplatform=MacOS` for every Logitech keyboard at login and
   on every connect. Verify: `journalctl --user -u logi-macmode` shows `MX Keys: MacOS`.

8. **System**: `./install.sh system`. Verify: `battery-limit` shows the threshold;
   `cat /run/mac-stats/net.json` updates every 2 s.

9. **Window memory**: create `~/.config/kwinrulesrc` rules, one per app the user keeps in the dock, with
   `sizerule=4 positionrule=4 maximizehorizrule=4 maximizevertrule=4` (4 = Remember), matched on the
   window class (get it from a KWin script: `w.resourceClass`; Chromium `--app` windows need a substring match).
   Apply with `qdbus6 org.kde.KWin /KWin reconfigure`. Rules take effect from the next close/open.

10. **Glass**: `plasma-sync-glass` sets the WhiteSur panel and dialog tint to one value per theme. Both
    WhiteSur variants use white text, so both use black at 45%. Spotlight uses the same tint. Verify by
    screenshotting the bar and an open Control Center popup over the same wallpaper.

11. **Wallpaper**: the Macintosh live wallpaper is installed by `./install.sh plasmoids`. Apply it with
    Plasma scripting: `desktops().forEach(function(d){d.wallpaperPlugin="net.local.macintosh"})`, and set
    `Colour=Spectrum`, `Scene=Cycle` in the `["Wallpaper","net.local.macintosh","General"]` group.
    `contents/ui/Machine.js` interprets the `.program` scene DSL (`programs/apple/` are Apple's, byte-identical;
    `programs/authored/` follow the same style, with extensions marked `// [ext]`). Expect about 11% of
    one CPU core with three screens animating; it pauses under maximized windows.
    Alternative: Smart Video Wallpaper Reborn (`luisbocanegra.smart.video.wallpaper.reborn`) with Apple
    aerials. The macOS 26 manifest is
    `https://configuration.apple.com/configurations/internetservices/aerials/resources-config-26-0.plist`
    (points to a resources tar with `entries.json`; videos on sylvan.apple.com need Apple's root CA). Set
    `PauseMode` so playback pauses under windows; a video wallpaper competes with browsers for the hardware
    decoder.

12. **Final check**: no coredumps, no QML errors from `net.local.*` in the journal, plasmashell CPU at idle
    under 2%, and every screenshot reviewed. Report what was verified and what was not.

## Machine-specific (decide with the user)

- Monitor layout and scale, dock app list, which apps get window rules.
- Battery limit percentage (default 80).
- KWallet vs gnome-keyring as Secret Service: don't change it here.
