#!/usr/bin/env bash
# Fenwyre installer. Idempotent; backs up anything it changes to ~/kde-pre-mac-backup.
#
#   ./install.sh features            list the features (id|group|title|description|sudo)  <- agents read this
#   ./install.sh plan ID... | all    show which units would run and whether sudo is needed (changes nothing)
#   ./install.sh apply ID...         apply only these features (shared pieces run once, in a safe order)
#   ./install.sh apply all           apply every feature
#   ./install.sh deps                pacman packages the features need (uses sudo)
#   ./install.sh unit NAME...        run single low-level units (debugging)
#
# Agents: never pick features yourself. Ask the user first (AGENTS.md, "Step 0"), with the AskUserQuestion tool.
# Target: KDE Plasma 6 on Wayland (tested: Plasma 6.8, Asahi Arch Linux ARM, MacBook Pro M1 Max).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BK=$HOME/kde-pre-mac-backup
BIN=$HOME/.local/bin
mkdir -p "$BK" "$BIN"

say() { printf '\e[1m==> %s\e[0m\n' "$*"; }
backup() { [ -e "$1" ] && [ ! -e "$BK/$(basename "$1").pre-parity" ] && cp -a "$1" "$BK/$(basename "$1").pre-parity" || true; }
# copy a file, replacing @HOME@ with the real home directory
put() { local src=$1 dst=$2 mode=${3:-644}; mkdir -p "$(dirname "$dst")"; backup "$dst"
        sed "s|@HOME@|$HOME|g" "$src" > "$dst.tmp" && chmod "$mode" "$dst.tmp" && mv "$dst.tmp" "$dst"; }
kw() { kwriteconfig6 --notify "$@"; }   # --notify matters: KWin/Plasma only reload on KConfig change notifications
plasma_js() { qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"; }
bin() { for f in "$@"; do put "$HERE/bin/$f" "$BIN/$f" 755; done; }
svc() { for f in "$@"; do put "$HERE/systemd/user/$f" "$HOME/.config/systemd/user/$f"; done; systemctl --user daemon-reload; }

# ------------------------------------------------------------------ features (what the user chooses from)
# id | group | title | description | sudo(yes/no)
FEATURES='
themes|Look|macOS themes + Liquid Glass|Light/Dark global themes that keep the macOS look, traffic lights on the left, genie minimize into the dock; macOS 27 Liquid Glass (refraction, specular rim) on the dock, popups and Spotlight via the KWin Glass effect, clear menu bar|yes
menubar|Look|macOS menu bar|Mac Stats (CPU/MEM/GPU/net), battery, Sound (headphones-aware), Control Center, "Nov 8  3:04 AM" clock, no tray chevron|yes
lockscreen|Look|Live wallpaper + lock screen|Macintosh live wallpaper on desktop and lock screen, glass stencil clock, unlock eases into the desktop (next login); SDDM login form on the main display only, monitor layout synced, only Plasma offered|yes
hud|Look|Volume/brightness HUD|macOS 27.2 glass capsule under the menu bar, outlined glyph, 16-segment level|no
cmdkeys|Keyboard|Cmd/Ctrl swap|Cmd+C/V/W/Q/Tab work like macOS (XKB swap of Super and Ctrl)|no
spotlight|Keyboard|Spotlight (Cmd+Space)|Centred translucent search for apps, settings, calculator, conversions; Baloo indexing off|no
screenshots|Keyboard|Screenshot shortcuts|Cmd+Shift+3/4/5 to the Desktop with macOS names, add Ctrl for clipboard|no
quicklook|Keyboard|Quick Look (Space)|Space previews files in Dolphin and on the desktop, arrows step through files (GNOME Sushi)|no
konsole|Apps|Terminal profile|Konsole "Mac" profile with Source Code Pro for Powerline as the default|no
helium|Apps|Helium hardware video|VA-API decode on Apple silicon (H.264/VP9) and an extension that hides AV1 so YouTube uses hardware decode|no
mxkeys|Apps|Logitech Mac mode|Switch Logitech keyboards (MX Keys) to macOS layout at login and on every reconnect (Solaar)|no
brightness|Apps|Brightness keys, ProMotion + DDC|Change only the display under the mouse; built-in panel steps in perceived brightness (2.5%); adaptive refresh on the built-in display; Asahi: DDC/CI to external monitors and HDMI back after sleep (patched display driver, next boot)|yes
battery|System|Battery, fans + SSD TRIM|AlDente-style charge limit (default 80%); macOS fan profiles in Mac Stats > Sensors (fans off below 60 C; patched macsmc-hwmon, Asahi M1 Pro/Max); TRIM through the encrypted root (next boot)|yes
audio|System|Bluetooth audio|LDAC adaptive bitrate (no skipping; hq option in the file); Sony Clear Bass-style EQ for a WH-1000XM3 (edit the target MAC)|no
netstats|System|Per-app network/GPU + SF font|Root feeds for Mac Stats per-app network (packet capture) and GPU (scheduler tracepoints); SF Pro preferred over other sans fonts|yes
windows|System|Remember window sizes|Per-app KWin rules so apps reopen at their last size/position (agent creates them, see AGENTS.md)|no
'
feature_units() {   # feature -> units, in no particular order (apply() orders and de-duplicates)
    case $1 in
        themes)      echo packages themesettings glass restart ;;
        menubar)     echo bin_stats packages blur volume_sound glass layout restart ;;
        lockscreen)  echo packages lockscreen lockwallpaper loginscreen ;;
        hud)         echo blur osd restart ;;
        cmdkeys)     echo cmdswap ;;
        spotlight)   echo packages blur krunner layout restart ;;
        screenshots) echo shots ;;
        quicklook)   echo quicklook ;;
        konsole)     echo konsole ;;
        helium)      echo helium ;;
        mxkeys)      echo mxkeys ;;
        brightness)  echo brightness vrr appledrm ;;
        battery)     echo battery fans trim ;;
        audio)       echo audio ;;
        netstats)    echo netfeed sffont ;;
        windows)     echo windows ;;
        *) echo "unknown feature: $1 (see ./install.sh features)" >&2; return 1 ;;
    esac
}
# Execution order for units (shared pieces first, panel layout and plasmashell restart last).
ORDER=(packages bin_stats blur osd volume_sound lockscreen lockwallpaper loginscreen themesettings glass cmdswap krunner shots
       quicklook konsole helium mxkeys brightness vrr appledrm audio windows battery fans trim netfeed sffont layout restart)

# ------------------------------------------------------------------ units
unit_packages() {   # Plasma packages are inert until used: widgets, global themes, wallpaper
    say "Plasma widgets, global themes, wallpaper"
    for d in "$HERE"/plasmoids/*/ "$HERE"/look-and-feel/*/ "$HERE"/wallpapers/*/; do
        local kind=plasmoids; [[ $d == */look-and-feel/* ]] && kind=look-and-feel; [[ $d == */wallpapers/* ]] && kind=wallpapers
        local dst=$HOME/.local/share/plasma/$kind/$(basename "$d")
        mkdir -p "$dst"; (cd "$d" && find . -type f) | while read -r f; do put "$d/$f" "$dst/$f"; done
    done
}
unit_bin_stats() { say "Mac Stats collectors"; bin mac-stats mac-stats-detail; }
unit_blur() {
    say "net.local.blur QML plugin (KWin blur behind)"
    local b; b=$(mktemp -d)
    cmake -S "$HERE/qml-blurbehind" -B "$b" -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$b" -j"$(nproc)" >/dev/null
    local q=$HOME/.local/lib/qt6/qml/net/local/blur; mkdir -p "$q"
    cp "$b"/net/local/blur/{libblurbehind.so,qmldir,blurbehind.qmltypes} "$q/"
    rm -rf "$b"
    put "$HERE/config/environment.d/50-local-qml.conf" "$HOME/.config/environment.d/50-local-qml.conf"
    systemctl --user set-environment QML_IMPORT_PATH="$HOME/.local/lib/qt6/qml"
}
unit_osd() {
    say "macOS 27.2-style OSD (overrides org.kde.plasma.workspace.osd via QML_IMPORT_PATH)"
    local m=$HOME/.local/lib/qt6/qml/org/kde/plasma/workspace/osd s=/usr/lib/qt6/qml/org/kde/plasma/workspace/osd
    mkdir -p "$m"
    for f in libplasmashell_osd.so plasmashell_osd.qmltypes kde-qmlmodule.version; do ln -sf "$s/$f" "$m/$f"; done
    cp "$HERE"/osd/{Osd.qml,OsdItem.qml,Glyph.qml,qmldir} "$m/"
}
unit_volume_sound() { :; }   # net.local.volume ships with unit_packages; the layout puts it on the bar
unit_lockscreen() {
    say "macOS lock screen (glass clock) + lock/unlock watcher"
    local b; b=$(mktemp -d)
    cmake -S "$HERE/qml-lockwatch" -B "$b" -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$b" -j"$(nproc)" >/dev/null
    local q=$HOME/.local/lib/qt6/qml/net/local/lockwatch; mkdir -p "$q"
    cp "$b"/net/local/lockwatch/{liblockwatch.so,qmldir,lockwatch.qmltypes} "$q/"
    rm -rf "$b"
    local d=$HOME/.local/share/plasma/shells/net.local.macos.lockscreen
    mkdir -p "$d" && cp -r "$HERE/lockscreen/net.local.macos.lockscreen/." "$d/"
    # KWin spawns the greeter; PLASMA_DEFAULT_SHELL on KWin only picks the lock screen QML. Next login.
    put "$HERE/systemd/user/plasma-kwin_wayland.service.d/macos-lockscreen.conf" \
        "$HOME/.config/systemd/user/plasma-kwin_wayland.service.d/macos-lockscreen.conf"
    systemctl --user daemon-reload
}
unit_loginscreen() {
    say "root: SDDM login screen (Breeze copy: form on the main display, your monitor layout, Plasma only)"
    local t; t=$(mktemp -d)
    cp -a /usr/share/sddm/themes/breeze "$t/breeze-mac" && patch -s -d "$t/breeze-mac" -p1 < "$HERE/system/sddm/breeze-mac.patch"
    # main display = your priority-1 output (System Settings > Display > Primary)
    local main; main=$(python3 -I -c 'import json,sys
d={e["name"]:e["data"] for e in json.load(open(sys.argv[1]))}
s=d["setups"][0]["outputs"]; o=min(s,key=lambda x:x["priority"])
print(d["outputs"][o["outputIndex"]].get("connectorName",""))' "$HOME/.config/kwinoutputconfig.json" 2>/dev/null || true)
    [ -n "$main" ] && sed -i "s/^primaryOutput=.*/primaryOutput=$main/" "$t/breeze-mac/theme.conf"
    sudo rm -rf /usr/share/sddm/themes/breeze-mac && sudo cp -a "$t/breeze-mac" /usr/share/sddm/themes/ && \
        sudo chown -R root:root /usr/share/sddm/themes/breeze-mac; rm -rf "$t"
    sudo install -d /usr/local/share/sddm-sessions
    sudo ln -sfn /usr/share/wayland-sessions/plasma.desktop /usr/local/share/sddm-sessions/plasma.desktop
    sudo install -m644 "$HERE/system/sddm/99-zz-mac.conf" /etc/sddm.conf.d/99-zz-mac.conf
    # SDDM runs its own KWin as user sddm: give it this session's monitor layout (rotation, scale, primary)
    sudo install -o sddm -g sddm -m644 "$HOME/.config/kwinoutputconfig.json" /var/lib/sddm/.config/kwinoutputconfig.json
}
unit_lockwallpaper() {
    say "Macintosh live wallpaper on desktops and behind the lock screen (auto-lock / power settings untouched)"
    backup "$HOME/.config/kscreenlockerrc"
    kw --file kscreenlockerrc --group Greeter --key WallpaperPlugin net.local.macintosh
    for kv in Colour=Spectrum Scene=Cycle Speed=0.75 PauseWhenCovered=false; do
        kw --file kscreenlockerrc --group Greeter --group Wallpaper --group net.local.macintosh --group General --key "${kv%%=*}" "${kv#*=}"
    done
    plasma_js 'desktops().forEach(function(d){d.wallpaperPlugin="net.local.macintosh";d.currentConfigGroup=["Wallpaper","net.local.macintosh","General"];d.writeConfig("Colour","Spectrum");d.writeConfig("Scene","Cycle");})' >/dev/null
}
unit_themesettings() {
    say "macOS global themes for Light/Dark, window buttons on the left"
    for f in kwinrc kdeglobals; do backup "$HOME/.config/$f"; done
    kw --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft XIA
    kw --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""
    kw --file kdeglobals --group KDE --key DefaultLightLookAndFeel net.local.macos.light
    kw --file kdeglobals --group KDE --key DefaultDarkLookAndFeel net.local.macos.dark
    # Dock genie (~0.45 s like macOS): macgenie (system/genie, root) is KWin's Magic Lamp aimed at the dock
    # on the window's own screen; stock Magic Lamp if it can't be built (it may pick another screen's dock).
    local fx=magiclamp
    if "$HERE/system/genie/build-effect"; then fx=macgenie; else echo "macgenie not built: using Magic Lamp"; fi
    kw --file kwinrc --group Plugins --key squashEnabled false
    kw --file kwinrc --group Plugins --key magiclampEnabled "$([ $fx = magiclamp ] && echo true || echo false)"
    kw --file kwinrc --group Plugins --key macgenieEnabled "$([ $fx = macgenie ] && echo true || echo false)"
    kw --file kwinrc --group Effect-magiclamp --key AnimationDuration 450
    kw --file kwinrc --group Effect-genie --key AnimationDuration 450
    local e; for e in squash magiclamp macgenie; do
        [ $e = $fx ] || qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect $e >/dev/null 2>&1 || true
    done
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect $fx >/dev/null 2>&1 || true
}
unit_glass() {
    say "macOS 27 Liquid Glass: KWin Glass effect (root) + tints for dock, popups, Spotlight (re-applied at login)"
    bin plasma-sync-glass; svc plasma-sync-glass.service
    systemctl --user enable plasma-sync-glass.service; "$BIN/plasma-sync-glass" || true
    "$HERE/system/glass/build-effect" || { echo "Glass effect not built: keeping KWin's blur"; return 0; }
    backup "$HOME/.config/kwinrc"
    local k v
    # Values matched to macOS 27 screenshots: clear dock with lensing only at the bevel, light hairline
    # rim with a specular highlight. Blacklist mode with an empty list, so every surface that asks for
    # blur gets glass (whitelist mode with an empty list blurs nothing at all); BlurDocks=false, or the
    # menu bars get force-blurred and visibly warped by the refraction.
    while read -r k v; do kw --file kwinrc --group Effect-blurplus --key "$k" "$v"; done <<'EOF'
BlurNonMatching true
BlurMatching false
BlurDocks false
BlurMenus true
TransparentBlur true
BlurStrength 6
DockBlurStrength 2
NoiseStrength 0
Saturation 1.2
RefractionStrength 9
RefractionEdgeSize 3
RefractionNormalPow 3
RefractionRGBFringing 1
RefractionOffsetStrength 8
RefractionBevelIntensity 12
PhysicallyBasedRefraction true
EdgeLighting false
RimSpecular true
RimSpecularTopLeft true
RimSpecularTopRight true
RimSpecularBottomLeft true
RimSpecularBottomRight true
RimWidth 12
RimSpecularScale 8
UseDeclaredCornerRadius true
MenuCornerRadius 12
DockCornerRadius 22
EOF
    kw --file kwinrc --group Plugins --key blurEnabled false
    kw --file kwinrc --group Plugins --key glassEnabled true
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect blur >/dev/null 2>&1 || true
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect glass >/dev/null 2>&1 || true
    # The dock stays glass over maximized windows (Plasma's "adaptive" swaps in the solid SVG).
    plasma_js 'panels().forEach(function(p){ if (p.location == "bottom") p.opacity = "translucent"; })' >/dev/null 2>&1 || true
}
unit_cmdswap() {
    say "Cmd/Ctrl swap"
    backup "$HOME/.config/kxkbrc"
    kw --file kxkbrc --group Layout --key Use true   # KWin needs Use/LayoutList set and --notify
    grep -q '^LayoutList=' "$HOME/.config/kxkbrc" 2>/dev/null || kw --file kxkbrc --group Layout --key LayoutList us
    kw --file kxkbrc --group Layout --key ResetOldOptions true
    kw --file kxkbrc --group Layout --key Options "ctrl:swap_lwin_lctl,ctrl:swap_rwin_rctl"
}
unit_krunner() {
    say "Spotlight search sources; KRunner only on Alt+F2 / Search key; Baloo off"
    backup "$HOME/.config/krunnerrc"
    kw --file krunnerrc --group General --key FreeFloating true
    while IFS='=' read -r k v; do [ -n "$k" ] && kw --file krunnerrc --group Plugins --key "$k" "$v"; done < "$HERE/config/krunner-plugins.ini"
    gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel --method org.kde.KGlobalAccel.setForeignShortcutKeys \
        "['org.kde.krunner.desktop','_launch','','']" "[([150994993,0,0,0],),([16777362,0,0,0],)]" >/dev/null 2>&1 || true
    balooctl6 disable >/dev/null 2>&1 || true
}
unit_shots() {
    say "screenshot shortcuts (Ctrl below = physical Cmd after the swap; Meta = physical Ctrl)"
    backup "$HOME/.config/spectaclerc"
    for f in "$HERE"/config/applications/mac-shot-*.desktop; do put "$f" "$HOME/.local/share/applications/$(basename "$f")"; done
    kbuildsycoca6 >/dev/null 2>&1 || true
    kw --file spectaclerc --group ImageSave --key imageSaveLocation "file://$(xdg-user-dir DESKTOP)"
    kw --file spectaclerc --group ImageSave --key imageFilenameTemplate "Screenshot <yyyy>-<MM>-<dd> at <hh>.<mm>.<ss>"
    python3 - <<'EOF'
import subprocess
C, S, M = 0x04000000, 0x02000000, 0x10000000
def keys(d, shifted, extra=0):  # Shift+digit can arrive as the digit or the shifted symbol; bind all forms
    return "[" + ",".join(f"([{v},0,0,0],)" for v in (C|S|extra|ord(d), C|extra|ord(shifted), C|S|extra|ord(shifted))) + "]"
def bind(comp, action, name, k):
    ident = f"['{comp}','{action}','{comp}','{name}']"
    call = ["gdbus", "call", "--session", "--dest", "org.kde.kglobalaccel", "--object-path", "/kglobalaccel", "--method"]
    subprocess.run(call + ["org.kde.KGlobalAccel.doRegister", ident], capture_output=True)
    # flags 6 = SetPresent|NoAutoloading: without SetPresent the shortcut is stored but never fires
    r = subprocess.run(call + ["org.kde.KGlobalAccel.setShortcutKeys", ident, k, "6"], capture_output=True, text=True)
    print(comp, "ok" if r.returncode == 0 else r.stderr.strip())
bind("mac-shot-screen.desktop", "_launch", "Screenshot: Entire Screen", keys("3", "#"))
bind("mac-shot-region.desktop", "_launch", "Screenshot: Selected Region", keys("4", "$"))
bind("mac-shot-tool.desktop", "_launch", "Screenshot Tool", keys("5", "%"))
bind("mac-shot-screen-clip.desktop", "_launch", "Screenshot to Clipboard", keys("3", "#", M))
bind("mac-shot-region-clip.desktop", "_launch", "Region to Clipboard", keys("4", "$", M))
EOF
}
unit_quicklook() {
    say "Quick Look (Space) via GNOME Sushi"
    bin quicklook sushi-launch desktop-quicklook-patch
    put "$HERE/config/dbus-services/org.gnome.NautilusPreviewer.service" "$HOME/.local/share/dbus-1/services/org.gnome.NautilusPreviewer.service"
    put "$HERE/config/kio-servicemenus/quicklook.desktop" "$HOME/.local/share/kio/servicemenus/quicklook.desktop" 755
    svc quicklook-nav.service desktop-quicklook-patch.service
    systemctl --user enable --now quicklook-nav.service; systemctl --user enable desktop-quicklook-patch.service
    "$BIN/desktop-quicklook-patch" || true
    echo "Dolphin: merge config/dolphinui-quicklook.xml into ~/.local/share/kxmlgui5/dolphin/dolphinui.rc (AGENTS.md step 6)"
}
unit_konsole() {
    say "Konsole Mac profile"
    backup "$HOME/.config/konsolerc"
    for f in "$HERE"/config/konsole/*; do put "$f" "$HOME/.local/share/konsole/$(basename "$f")"; done
    kw --file konsolerc --group "Desktop Entry" --key DefaultProfile Mac.profile
}
unit_helium() {
    say "Helium hardware video decode + no-AV1 extension (merged into the existing flags file)"
    local f=$HOME/.config/helium-browser-flags.conf e=$HOME/.local/share/helium-extensions/no-av1
    for x in manifest.json inject.js; do put "$HERE/config/helium/no-av1/$x" "$e/$x"; done
    touch "$f"; backup "$f"
    if grep -q 'VaapiVideoDecoder' "$f"; then echo "flags already present"; else
        sed "s|@HOME@|$HOME|g" "$HERE/config/helium/hwdecode.flags" > "$f.add"
        { cat "$f.add"; cat "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"; rm -f "$f.add"   # other lines (e.g. --password-store) kept
    fi
    echo "Restart Helium; verify chrome://media-internals shows kVideoDecoderName = VaapiVideoDecoder"
}
unit_mxkeys() {
    say "Logitech Mac mode"; bin logi-macmode; svc logi-macmode.service; systemctl --user enable --now logi-macmode.service;
    # The MX Keys lock key (Mac mode) sends Ctrl+Cmd+Q, macOS's lock shortcut: add it to Lock Session next to
    # Meta+L and the Screensaver key. 0x14000051 = Meta+Ctrl+Q (the same after the Cmd/Ctrl swap), 0x10000000|L, Key_ScreenSaver.
    gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel --method org.kde.KGlobalAccel.setShortcutKeys \
        "['ksmserver','Lock Session','Session Management','Lock Session']" \
        "[([268435532,0,0,0],),([16777402,0,0,0],),([335544401,0,0,0],)]" 6 >/dev/null
}
unit_brightness() {
    say "brightness keys for the display under the mouse"
    bin brightness-here brightness-here-repeat ddc-level ddc-rescan; svc brightness-here-repeat.service; svc ddc-rescan.service
    systemctl --user enable --now brightness-here-repeat.service
    systemctl --user enable ddc-rescan.service   # at login: PowerDevil picks up monitors that came up late
    # One source of truth: KWin owns every display's level (DDC/CI for external monitors) and the keys go
    # through KDE's ScreenBrightness service, like the tray slider. Make sure KWin's DDC/CI is on.
    local o
    for o in $(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/^Output:/ { print $3 }'); do
        case "$o" in eDP*|LVDS*|DSI*) ;; *) kscreen-doctor "output.$o.ddcCi.allow" >/dev/null 2>&1 ;; esac
    done
    # PowerDevil writes every intermediate slider/key value over DDC/CI; on a slow link the monitor lags
    # seconds behind. Preload system/ddc-coalesce so only the newest value is sent, and skip read-back.
    mkdir -p "$HOME/.local/lib" "$HOME/.config/systemd/user/plasma-powerdevil.service.d" "$HOME/.config/ddcutil"
    if cc -O2 -shared -fPIC -o "$HOME/.local/lib/libddc-coalesce.so" "$HERE/system/ddc-coalesce/ddc-coalesce.c" -ldl -lpthread; then
        printf '%s\n' '# kde-macos-parity: send only the newest DDC/CI brightness value (system/ddc-coalesce).' '[Service]' \
            'Environment=LD_PRELOAD=%h/.local/lib/libddc-coalesce.so' \
            > "$HOME/.config/systemd/user/plasma-powerdevil.service.d/ddc-coalesce.conf"
        systemctl --user daemon-reload
        systemctl --user try-restart plasma-powerdevil.service
    fi
    [ -e "$HOME/.config/ddcutil/ddcutilrc" ] || printf '%s\n' '[libddcutil]' 'options: --noverify' > "$HOME/.config/ddcutil/ddcutilrc"
}
unit_audio() {
    say "Bluetooth audio: LDAC adaptive (no skips on radio dips); Sony EQ filter (targets the MAC in the file)"
    for f in "$HERE"/config/wireplumber/*.conf; do put "$f" "$HOME/.config/wireplumber/wireplumber.conf.d/$(basename "$f")"; done
    # The EQ filter targets one headset: keep the MAC already installed, else HEADSET_MAC=AA:BB:..., else warn.
    local eq="$HOME/.config/pipewire/pipewire.conf.d/60-sony-clearbass.conf" mac="${HEADSET_MAC:-}"
    [ -z "$mac" ] && [ -f "$eq" ] && mac=$(sed -n 's/.*bluez_output\.\([0-9A-Fa-f_]\{17\}\)\..*/\1/p' "$eq" | head -1)
    for f in "$HERE"/config/pipewire/*.conf; do put "$f" "$HOME/.config/pipewire/pipewire.conf.d/$(basename "$f")"; done
    if [ -n "$mac" ]; then sed -i "s/XX_XX_XX_XX_XX_XX/$(echo "$mac" | tr ':a-f' '_A-F')/" "$eq"
    else echo "Sony EQ: set HEADSET_MAC=AA:BB:CC:DD:EE:FF (or edit $eq) to target your headset"; fi
    echo "Takes effect after: systemctl --user restart pipewire pipewire-pulse wireplumber (mute the speakers first)"
}
unit_windows() { echo "Window memory is created per app by the agent (AGENTS.md step 9); nothing to copy."; }
unit_battery() {
    say "root: battery charge limit"
    sudo install -m755 "$HERE/system/bin/battery-limit" /usr/local/bin/battery-limit
    sudo install -m644 "$HERE/system/systemd/battery-limit.service" /etc/systemd/system/battery-limit.service
    sudo install -Dm644 "$HERE/system/systemd/battery-limit.service.d/save-on-stop.conf" /etc/systemd/system/battery-limit.service.d/save-on-stop.conf
    sudo systemctl daemon-reload; sudo systemctl enable --now battery-limit.service
}
unit_appledrm() {
    say "root: patched display driver for $(uname -r) (DDC/CI on external monitors, HDMI after sleep)"
    [ -f "/usr/lib/modules/$(uname -r)/kernel/drivers/gpu/drm/apple/appledrm.ko" ] ||
        { echo "not an Asahi/Aurora kernel, skipping"; return 0; }
    local cc; cc=$(sed -n 's/^CONFIG_CLANG_VERSION=\([0-9]*\)[0-9]\{4\}$/\1/p' "/usr/lib/modules/$(uname -r)/build/.config" 2>/dev/null)
    if [ -n "$cc" ] && [ ! -x "/usr/lib/llvm$cc/bin/clang" ]; then
        sudo pacman -S --needed --noconfirm "clang$cc" "lld$cc" "llvm$cc" || echo "clang$cc not available: building with the system clang"
    fi
    "$HERE/system/display/build-module"
    pacman -Q ddcutil >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm ddcutil
    sudo modprobe i2c-dev 2>/dev/null || true
    echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
}
unit_vrr() {
    say "adaptive refresh (ProMotion) on the built-in display"
    local out; out=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/^Output:/{print $3}' | grep -E '^(eDP|LVDS|DSI)' | head -1)
    [ -n "$out" ] || { echo "no built-in display, skipping"; return 0; }
    backup "$HOME/.config/kwinoutputconfig.json"
    # "Always", not "Automatic": KWin's Automatic only enables VRR for full-screen games.
    kscreen-doctor "output.$out.vrrpolicy.always" >/dev/null || echo "$out: VRR not supported, left as is"
}
unit_trim() {
    say "root: TRIM through the LUKS root (rd.luks.options=<uuid>=discard on the kernel command line)"
    local uuid; uuid=$(tr ' ' '\n' </proc/cmdline | sed -n 's/^rd\.luks\.name=\([^=]*\)=.*/\1/p' | head -1)
    [ -n "$uuid" ] || { echo "root is not unlocked with rd.luks.name=, skipping"; return 0; }
    local f tmp; tmp=$(mktemp -d)
    # Omarchy on Apple Silicon derives /etc/default/limine from /etc/default/grub before every UKI
    # rebuild (omarchy-mac-limine-cmdline), so the option has to be in GRUB's defaults too.
    for f in /etc/default/grub /etc/default/limine /boot/efi/limine.conf /boot/limine.conf; do
        sudo test -f "$f" || continue
        sudo grep -q "rd.luks.name=$uuid=" "$f" || continue
        sudo grep -q "rd.luks.options=$uuid=discard" "$f" && continue
        sudo cp -a "$f" "$f.pre-discard"
        sudo cat "$f" | sed "s/rd\.luks\.name=$uuid=\([^ \"]*\)/rd.luks.name=$uuid=\1 rd.luks.options=$uuid=discard/g" > "$tmp/new"
        sudo install -m "$(sudo stat -c %a "$f")" "$tmp/new" "$f" && echo "$f: discard added (backup $f.pre-discard)"
    done
    rm -rf "$tmp"
    sudo test -f /etc/default/limine || echo "not Limine: add rd.luks.options=$uuid=discard to your kernel command line"
    sudo systemctl enable fstrim.timer >/dev/null 2>&1 || true
    echo "takes effect at the next boot; then lsblk -D /dev/mapper/* shows non-zero DISC-GRAN"
}
unit_netfeed() {
    say "root: per-app network feed for Mac Stats"
    sudo install -m755 "$HERE/system/bin/nethogs-feed" /usr/local/bin/nethogs-feed
    sudo install -m644 "$HERE/system/systemd/nethogs-feed.service" /etc/systemd/system/nethogs-feed.service
    sudo systemctl daemon-reload; sudo systemctl enable --now nethogs-feed.service
    if [ -d /sys/kernel/tracing/events/gpu_scheduler ]; then
        say "root: per-app GPU feed for Mac Stats"
        sudo install -m755 "$HERE/system/bin/gpu-feed" /usr/local/bin/gpu-feed
        sudo install -m644 "$HERE/system/systemd/gpu-feed.service" /etc/systemd/system/gpu-feed.service
        sudo systemctl daemon-reload; sudo systemctl enable --now gpu-feed.service
    fi
}
unit_fans() {
    say "root: fan profiles (patched macsmc-hwmon for $(uname -r), mac-fand)"
    if ! grep -qE 'apple,t600[012]' /proc/device-tree/compatible 2>/dev/null; then
        echo "not an M1 Pro/Max/Ultra: the die keys are M1-specific, skipping"; return 0; fi
    "$HERE/system/fan/build-module"
    sudo install -m644 "$HERE/system/fan/macsmc-hwmon.conf" /etc/modprobe.d/macsmc-hwmon-parity.conf
    sudo install -m755 "$HERE/system/bin/mac-fand" /usr/local/bin/mac-fand
    sudo install -m644 "$HERE/system/systemd/mac-fand.service" /etc/systemd/system/mac-fand.service
    sudo systemctl stop mac-fand.service 2>/dev/null || true
    sudo modprobe -r macsmc_hwmon && sudo modprobe macsmc_hwmon
    sudo systemctl daemon-reload; sudo systemctl enable --now mac-fand.service
}
unit_sffont() { say "root: SF font priority"; sudo install -m644 "$HERE/config/fontconfig/49-zz-macos-sf.conf" /etc/fonts/conf.d/49-zz-macos-sf.conf; }
unit_layout() {
    say "menu bar widgets (Plasma scripting)"
    backup "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    local want=()
    [[ " ${SELECTED[*]} " == *" menubar "* ]] && want+=('"net.local.macstats"' '"org.kde.plasma.battery"' '"net.local.volume"' '"net.local.controlcenter"')
    [[ " ${SELECTED[*]} " == *" spotlight "* ]] && want+=('"net.local.spotlight"')
    local list; list=$(IFS=,; echo "${want[*]}")
    plasma_js "var WANT = [$list];
$(cat "$HERE/plasma-scripts/mac-layout.js")"
}
unit_restart() { say "restart plasmashell"; systemctl --user restart plasma-plasmashell.service; }

step_deps() {
    say "packages (pacman)"
    local pkgs=(sushi nethogs solaar python-pyudev python-gobject spectacle milou layer-shell-qt kwindowsystem
                qt6-declarative cmake extra-cmake-modules ddcutil kscreen)
    local missing=(); for p in "${pkgs[@]}"; do pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p"); done
    if [ ${#missing[@]} -gt 0 ]; then sudo pacman -S --needed --noconfirm "${missing[@]}"; else echo "all present"; fi
    echo "Not automated (see AGENTS.md): WhiteSur KDE theme + icons + cursors, SF fonts (AUR apple-fonts), Source Code Pro for Powerline."
}

resolve() {   # sets SELECTED and RUN (ordered units); fails on unknown ids before anything changes
    SELECTED=("$@")
    [ "${1:-}" = all ] && SELECTED=($(echo "$FEATURES" | awk -F'|' 'NF>1{print $1}'))
    local units=" " f u
    for f in "${SELECTED[@]}"; do feature_units "$f" >/dev/null || exit 2; for u in $(feature_units "$f"); do units+="$u "; done; done
    RUN=(); for u in "${ORDER[@]}"; do if [[ $units == *" $u "* ]]; then RUN+=("$u"); fi; done
}
plan() {
    resolve "$@"
    echo "features: ${SELECTED[*]}"; echo "units:    ${RUN[*]}"
    local s=no; for u in "${RUN[@]}"; do case $u in battery|fans|trim|appledrm|netfeed|sffont|loginscreen|glass|themesettings) s=yes ;; esac; done; echo "sudo:     $s"
}
apply() {
    resolve "$@"
    say "features: ${SELECTED[*]}"
    for u in "${RUN[@]}"; do "unit_$u"; done
    say "done. Backups: $BK"
}

case "${1:-help}" in
    features) echo "$FEATURES" | sed '/^$/d' ;;
    plan) shift; [ $# -gt 0 ] || { echo "usage: ./install.sh plan all | ID..." >&2; exit 2; }; plan "$@" ;;
    apply) shift; [ $# -gt 0 ] || { echo "usage: ./install.sh apply all | ID..." >&2; exit 2; }; apply "$@" ;;
    deps) step_deps ;;
    unit) shift; SELECTED=(menubar spotlight); for u in "$@"; do "unit_$u"; done ;;
    *) sed -n '2,10p' "$0" ;;
esac
