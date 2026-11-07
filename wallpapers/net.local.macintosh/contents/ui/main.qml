import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

WallpaperItem {
    id: main

    readonly property bool darkTheme: {
        var c = Kirigami.Theme.backgroundColor;
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) < 0.5;
    }
    readonly property string appearance: main.configuration.Appearance || "Light"
    // Like macOS: the wallpaper plays on the lock screen; the desktop holds the frame the
    // lock screen reached when it was unlocked (optionally it can animate as well).
    readonly property bool onLockScreen: Qt.application.name.indexOf("kscreenlocker") >= 0
    readonly property bool animateDesktop: main.configuration.AnimateDesktop === true

    MacintoshView {
        id: view
        anchors.fill: parent
        mode: main.onLockScreen ? "live" : (main.animateDesktop ? "desktop-live" : "static")
        freezeAt: Number(main.configuration.FrozenAt) || 0
        scene: main.configuration.Scene || "Cycle"
        colour: main.configuration.Colour || "Spectrum"
        speed: main.configuration.Speed > 0 ? main.configuration.Speed : 0.75
        dark: main.appearance === "Dark" || (main.appearance === "Automatic" && main.darkTheme)
        accent: Kirigami.Theme.highlightColor
        // Spectrum differs per screen: offset the hue by the screen's position.
        hueOffset: (main.Screen.virtualX + main.Screen.virtualY) / 9000.0
        paused: main.configuration.PauseWhenCovered !== false && watcher.item !== null && watcher.item.covered
        locked: lockBridge.item !== null && lockBridge.item.locked
        onFrozeAt: function (wallMs) {
            // remember the held frame so a plasmashell restart shows the same picture
            if (main.onLockScreen) return;
            main.configuration.FrozenAt = String(Math.round(wallMs));
            if (main.configuration.writeConfig) main.configuration.writeConfig();
        }
    }

    // Only the animated desktop needs to know about covering windows.
    Loader {
        id: watcher
        active: view.mode === "desktop-live"
        source: "WindowWatcher.qml"
        onLoaded: item.screenGeometry = Qt.binding(function () { return main.parent ? main.parent.screenGeometry : null; })
    }

    // Lock state comes from a small C++ module (net.local.lockwatch). Without it the
    // desktop simply keeps its frame.
    Loader {
        id: lockBridge
        active: !main.onLockScreen
        source: "LockBridge.qml"
        onStatusChanged: if (status === Loader.Error) console.warn("[net.local.macintosh] net.local.lockwatch not available; desktop frame will not follow the lock screen")
    }
    Connections {
        target: lockBridge.item
        function onUnlocked() { view.unlockEase(); }
    }
}
