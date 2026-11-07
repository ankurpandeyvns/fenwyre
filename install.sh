#!/usr/bin/env bash
# kde-macos-parity installer. Idempotent; backs up anything it changes to ~/kde-pre-mac-backup.
#
#   ./install.sh                 run every user-level step (no sudo)
#   ./install.sh STEP...         run selected steps (see `./install.sh list`)
#   ./install.sh system          root steps (battery limit, per-app network feed, SF font priority); uses sudo
#
# Target: KDE Plasma 6 on Wayland (tested: Plasma 6.8, Asahi Arch Linux ARM, MacBook Pro M1 Max).
# Read AGENTS.md before automating this.
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
plasma_js() { qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$1")"; }

step_deps() {
    say "packages (pacman)"
    local pkgs=(sushi nethogs solaar python-pyudev python-gobject spectacle milou layer-shell-qt kwindowsystem
                qt6-declarative cmake extra-cmake-modules ddcutil kscreen)
    local missing=(); for p in "${pkgs[@]}"; do pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p"); done
    if [ ${#missing[@]} -gt 0 ]; then sudo pacman -S --needed --noconfirm "${missing[@]}"; else echo "all present"; fi
    echo "Not automated (see AGENTS.md): WhiteSur KDE theme + icons + cursors, SF fonts (AUR apple-fonts), Source Code Pro for Powerline."
}

step_bin() {
    say "helpers -> ~/.local/bin"
    for f in "$HERE"/bin/*; do put "$f" "$BIN/$(basename "$f")" 755; done
}

step_plasmoids() {
    say "Plasma widgets, wallpaper, global themes"
    for d in "$HERE"/plasmoids/*/ "$HERE"/look-and-feel/*/ "$HERE"/wallpapers/*/; do
        local kind=plasmoids; [[ $d == */look-and-feel/* ]] && kind=look-and-feel; [[ $d == */wallpapers/* ]] && kind=wallpapers
        local dst=$HOME/.local/share/plasma/$kind/$(basename "$d")
        mkdir -p "$dst"; (cd "$d" && find . -type f) | while read -r f; do put "$d/$f" "$dst/$f"; done
    done
}

step_blur() {
    say "net.local.blur QML plugin (KWin blur behind for Spotlight)"
    local b; b=$(mktemp -d)
    cmake -S "$HERE/qml-blurbehind" -B "$b" -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$b" -j"$(nproc)" >/dev/null
    local q=$HOME/.local/lib/qt6/qml/net/local/blur; mkdir -p "$q"
    cp "$b"/net/local/blur/{libblurbehind.so,qmldir,blurbehind.qmltypes} "$q/"
    rm -rf "$b"
    put "$HERE/config/environment.d/50-local-qml.conf" "$HOME/.config/environment.d/50-local-qml.conf"
    systemctl --user set-environment QML_IMPORT_PATH="$HOME/.local/lib/qt6/qml"
}

step_osd() {
    say "macOS 27.2-style volume/brightness OSD (overrides org.kde.plasma.workspace.osd via QML_IMPORT_PATH)"
    local m=$HOME/.local/lib/qt6/qml/org/kde/plasma/workspace/osd s=/usr/lib/qt6/qml/org/kde/plasma/workspace/osd
    mkdir -p "$m"
    for f in libplasmashell_osd.so plasmashell_osd.qmltypes kde-qmlmodule.version; do ln -sf "$s/$f" "$m/$f"; done
    cp "$HERE"/osd/{Osd.qml,OsdItem.qml,Glyph.qml,qmldir} "$m/"
}

step_files() {
    say "launchers, D-Bus services, Dolphin service menu, Konsole profile"
    for f in "$HERE"/config/applications/*.desktop; do put "$f" "$HOME/.local/share/applications/$(basename "$f")"; done
    put "$HERE/config/dbus-services/org.gnome.NautilusPreviewer.service" "$HOME/.local/share/dbus-1/services/org.gnome.NautilusPreviewer.service"
    put "$HERE/config/kio-servicemenus/quicklook.desktop" "$HOME/.local/share/kio/servicemenus/quicklook.desktop" 755
    for f in "$HERE"/config/konsole/*; do put "$f" "$HOME/.local/share/konsole/$(basename "$f")"; done
    for f in "$HERE"/config/wireplumber/*.conf; do put "$f" "$HOME/.config/wireplumber/wireplumber.conf.d/$(basename "$f")"; done
    kbuildsycoca6 >/dev/null 2>&1 || true
}

step_services() {
    say "user services"
    for f in "$HERE"/systemd/user/*.service; do put "$f" "$HOME/.config/systemd/user/$(basename "$f")"; done
    systemctl --user daemon-reload
    systemctl --user enable --now quicklook-nav.service logi-macmode.service brightness-here-repeat.service
    systemctl --user enable desktop-quicklook-patch.service plasma-sync-glass.service
    "$BIN/desktop-quicklook-patch" || true
    "$BIN/plasma-sync-glass" || true
}

step_settings() {
    say "KDE settings"
    for f in kxkbrc krunnerrc kwinrc kdeglobals spectaclerc plasmaparc baloofilerc konsolerc; do backup "$HOME/.config/$f"; done
    # Cmd/Ctrl swap (Cmd = Ctrl, so Cmd+C/V/Space work); KWin needs Use/LayoutList set and --notify.
    kw --file kxkbrc --group Layout --key Use true
    grep -q '^LayoutList=' "$HOME/.config/kxkbrc" 2>/dev/null || kw --file kxkbrc --group Layout --key LayoutList us
    kw --file kxkbrc --group Layout --key ResetOldOptions true
    kw --file kxkbrc --group Layout --key Options "ctrl:swap_lwin_lctl,ctrl:swap_rwin_rctl"
    # Window buttons on the left (close, minimise, maximise)
    kw --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft XIA
    kw --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""
    # Dark/Light switch keeps the macOS look
    kw --file kdeglobals --group KDE --key DefaultLightLookAndFeel net.local.macos.light
    kw --file kdeglobals --group KDE --key DefaultDarkLookAndFeel net.local.macos.dark
    # KRunner is only a fallback (Alt+F2); Spotlight widget owns Cmd+Space
    kw --file krunnerrc --group General --key FreeFloating true
    # Spotlight searches only apps, settings, calculator and unit/currency conversion (Milou uses KRunner's plugin list)
    while IFS='=' read -r k v; do [ -n "$k" ] && kw --file krunnerrc --group Plugins --key "$k" "$v"; done < "$HERE/config/krunner-plugins.ini"
    # Screenshots to the Desktop, macOS file names
    kw --file spectaclerc --group ImageSave --key imageSaveLocation "file://$(xdg-user-dir DESKTOP)"
    kw --file spectaclerc --group ImageSave --key imageFilenameTemplate "Screenshot <yyyy>-<MM>-<dd> at <hh>.<mm>.<ss>"
    kw --file plasmaparc --group General --key AudioFeedback false
    kw --file konsolerc --group "Desktop Entry" --key DefaultProfile Mac.profile
    balooctl6 disable >/dev/null 2>&1 || true
}

step_shortcuts() {
    say "global shortcuts (Ctrl below = physical Cmd after the swap; Meta = physical Ctrl)"
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
# KRunner: Alt+F2 and the Search key only (Option+Space does nothing, like macOS)
subprocess.run(["gdbus", "call", "--session", "--dest", "org.kde.kglobalaccel", "--object-path", "/kglobalaccel", "--method",
                "org.kde.KGlobalAccel.setForeignShortcutKeys", "['org.kde.krunner.desktop','_launch','','']",
                "[([150994993,0,0,0],),([16777362,0,0,0],)]"], capture_output=True)
EOF
}

step_layout() {
    say "panel widgets (Plasma scripting)"
    backup "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    plasma_js "$HERE/plasma-scripts/mac-layout.js"
}

step_restart() {
    say "restart plasmashell"
    systemctl --user restart plasma-plasmashell.service
}

step_system() {
    say "root: battery limit, nethogs feed, SF font priority"
    sudo install -m755 "$HERE/system/bin/battery-limit" /usr/local/bin/battery-limit
    sudo install -m755 "$HERE/system/bin/nethogs-feed" /usr/local/bin/nethogs-feed
    sudo install -m644 "$HERE/system/systemd/battery-limit.service" /etc/systemd/system/battery-limit.service
    sudo install -m644 "$HERE/system/systemd/nethogs-feed.service" /etc/systemd/system/nethogs-feed.service
    sudo install -Dm644 "$HERE/system/systemd/battery-limit.service.d/save-on-stop.conf" /etc/systemd/system/battery-limit.service.d/save-on-stop.conf
    sudo install -m644 "$HERE/config/fontconfig/49-zz-macos-sf.conf" /etc/fonts/conf.d/49-zz-macos-sf.conf
    sudo systemctl daemon-reload
    sudo systemctl enable --now battery-limit.service nethogs-feed.service
}

ALL=(bin plasmoids blur osd files services settings shortcuts layout restart)
case "${1:-all}" in
    list) echo "user steps: ${ALL[*]}   extra: deps system" ;;
    all) for s in "${ALL[@]}"; do "step_$s"; done ;;
    *) for s in "$@"; do "step_$s"; done ;;
esac
