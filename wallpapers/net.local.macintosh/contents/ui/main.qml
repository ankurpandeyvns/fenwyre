import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

WallpaperItem {
    id: main

    readonly property bool darkTheme: {
        var c = Kirigami.Theme.backgroundColor;
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) < 0.5;
    }
    readonly property string appearance: main.configuration.Appearance || "Automatic"

    MacintoshView {
        id: view
        anchors.fill: parent
        scene: main.configuration.Scene || "Cycle"
        colour: main.configuration.Colour || "Spectrum"
        speed: main.configuration.Speed > 0 ? main.configuration.Speed : 1.0
        dark: main.appearance === "Dark" || (main.appearance === "Automatic" && main.darkTheme)
        accent: Kirigami.Theme.highlightColor
        // Spectrum differs per screen: offset the hue by the screen's position.
        hueOffset: (main.Screen.virtualX + main.Screen.virtualY) / 9000.0
        paused: main.configuration.PauseWhenCovered !== false && watcher.covered
    }

    WindowWatcher {
        id: watcher
        screenGeometry: main.parent ? main.parent.screenGeometry : null
    }
}
