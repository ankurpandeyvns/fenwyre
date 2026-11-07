/*
    macOS 27.2-style on-screen display for KDE Plasma 6 (kde-macos-parity).

    Overrides the stock org.kde.plasma.workspace.osd Osd.qml: this directory is first on
    QML_IMPORT_PATH, its qmldir drops the "prefer :/" line so these files win, and the C++
    plugin is a symlink to the system one.

    Look (matched to macOS 27.2 screenshots): a clear Liquid Glass capsule just below the
    menu bar at the top right, an outlined SF-style glyph, and a thin 16-segment level bar.
    No title. Text-only OSDs (Wi-Fi on, layout switched, ...) show icon + text in the capsule.
    The root is a plain layer-shell Window (not OsdWindow) so the capsule is drawn here
    instead of the Plasma theme frame; KWin blurs behind it via net.local.blur.
*/
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.layershell as LayerShell
import net.local.blur as Blur
import org.kde.plasma.workspace.osd
import org.kde.plasma.private.volume as Vol

Window {
    id: win

    // properties plasmashell sets
    property int timeout: 1500
    property var osdValue
    property int osdMaxValue: 100
    property string osdAdditionalText: ""
    property string icon
    property bool showingProgress: false

    // geometry, scaled from the reference (menu bar 37 px -> ours 29 px)
    readonly property int capW: showingProgress ? 294 : Math.max(220, Math.min(420, label.implicitWidth + 96))
    readonly property int capH: 61

    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput
    width: capW
    height: capH

    LayerShell.Window.scope: "osd"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
    LayerShell.Window.margins.top: 12      // gap below the 29 px menu bar (exclusive zone)
    LayerShell.Window.margins.right: 8
    LayerShell.Window.exclusionZone: 0       // respect the menu bar's zone, so margins.top is below it
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.wantsToBeOnActiveScreen: true

    readonly property real fraction: showingProgress && osdMaxValue > 0
        ? Math.max(0, Math.min(1, Number(osdValue) / osdMaxValue)) : 0
    // Headphones = headset/headphone form factor (Bluetooth), or an active headphone port that is
    // plugged in (Pulse port availability 2 = unavailable).
    function isHeadphones(s) {
        if (!s) return false;
        const ff = (s.formFactor || "").toLowerCase();
        if (["headphone", "headset", "hands-free", "handset"].indexOf(ff) >= 0) return true;
        const ports = s.ports || [];
        const p = s.activePortIndex >= 0 && s.activePortIndex < ports.length ? ports[s.activePortIndex] : null;
        if (!p) return false;
        const n = ((p.name || "") + " " + (p.description || "")).toLowerCase();
        return (n.indexOf("headphone") >= 0 || n.indexOf("headset") >= 0) && p.availability !== 2;
    }
    readonly property bool headphones: isHeadphones(Vol.PreferredDevice.sink)
    readonly property string kind: {
        const i = icon || "";
        if (i.startsWith("audio-volume")) return win.headphones ? "headphones" : "speaker";
        if (i.indexOf("keyboard-brightness") >= 0) return "kbd";
        if (i.indexOf("brightness") >= 0 || i.startsWith("video-display")) return "sun";
        return "";
    }

    Item {
        id: capsule
        anchors.fill: parent

        Blur.BlurBehind {
            anchors.fill: parent
            radius: height / 2
            active: win.visible
        }

        // Liquid Glass: barely tinted body, bright rim brighter at top-left and bottom-right
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.07) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.02) }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.38)
        }
        Rectangle {   // inner specular line
            anchors.fill: parent
            anchors.margins: 1.5
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
        }

        Glyph {
            id: glyph
            visible: win.kind !== ""
            x: Math.round(capsule.width * 0.066)
            anchors.verticalCenter: parent.verticalCenter
            width: 27
            height: 27
            kind: win.kind || "speaker"
            outline: true
            color: "white"
            level: win.fraction
            dimOpacity: 0.45
            muted: win.kind === "speaker" && (win.fraction === 0 || (win.icon || "").indexOf("muted") >= 0)
        }
        Kirigami.Icon {
            visible: win.kind === "" && source !== ""
            x: Math.round(capsule.width * 0.066)
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            source: win.icon
            isMask: true
            color: "white"
        }

        // 16 thin segments from 20% to 90% of the width
        Row {
            visible: win.showingProgress
            x: Math.round(capsule.width * 0.20)
            width: Math.round(capsule.width * 0.70)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: 16
                delegate: Item {
                    required property int index
                    readonly property real fill: Math.max(0, Math.min(1, win.fraction * 16 - index))
                    width: (parent.width - parent.spacing * 15) / 16
                    height: 4
                    Rectangle {
                        anchors.fill: parent
                        radius: 1
                        color: Qt.rgba(1, 1, 1, 0.32)
                    }
                    Rectangle {
                        width: parent.width * parent.fill
                        height: parent.height
                        radius: 1
                        color: "white"
                        Behavior on width { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
                    }
                }
            }
        }

        Text {
            id: label
            visible: !win.showingProgress
            x: Math.round(capsule.width * 0.066) + 36
            anchors.verticalCenter: parent.verticalCenter
            text: String(win.osdValue ?? "")
            color: "white"
            font.family: "SF Pro Text"
            font.pixelSize: 14
            font.weight: Font.Medium
            textFormat: Text.PlainText
        }
    }
}
