/*
    macOS 27.2-style on-screen display for KDE Plasma 6 (kde-macos-parity).

    Overrides the stock org.kde.plasma.workspace.osd Osd.qml: this directory is first on
    QML_IMPORT_PATH, its qmldir drops the "prefer :/" line so these files win, and the C++
    plugin (OsdWindow) is a symlink to the system one.

    Look: a glass card under the menu bar at the top right (macOS 26+ placement), with an
    SF-style glyph, a title ("Display", "Sound", "Keyboard", "Microphone") and a 16-segment
    level bar (27.2 brought back the precise segmented steps). Text-only OSDs (Wi-Fi on,
    layout switched, ...) show glyph/icon + text in the same card.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.layershell as LayerShell
import org.kde.plasma.workspace.osd

OsdWindow {
    id: win

    property alias timeout: osd.timeout
    property alias osdValue: osd.osdValue
    property alias osdMaxValue: osd.osdMaxValue
    property alias osdAdditionalText: osd.osdAdditionalText
    property alias icon: osd.icon
    property alias showingProgress: osd.showingProgress

    // top-right, just below the menu bar, like macOS 26/27
    LayerShell.Window.scope: "osd"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
    LayerShell.Window.margins.top: 36
    LayerShell.Window.margins.right: 10
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.wantsToBeOnActiveScreen: true

    width: 300 + leftPadding + rightPadding
    height: osd.implicitHeight + topPadding + bottomPadding

    mainItem: Item {
        id: osd
        implicitWidth: 300
        implicitHeight: 58

        property int timeout: 1500
        property var osdValue
        property int osdMaxValue: 100
        property string osdAdditionalText: ""
        property string icon
        property bool showingProgress: false

        readonly property color fg: Kirigami.Theme.textColor
        readonly property real fraction: showingProgress && osdMaxValue > 0
            ? Math.max(0, Math.min(1, Number(osdValue) / osdMaxValue)) : 0
        readonly property bool overdrive: showingProgress && Number(osdValue) > 100

        // what the OSD is about, from Plasma's icon names
        readonly property string kind: {
            const i = icon || "";
            if (i.startsWith("audio-volume")) return "speaker";
            if (i.startsWith("microphone")) return "mic";
            if (i.indexOf("keyboard-brightness") >= 0) return "kbd";
            if (i.indexOf("brightness") >= 0 || i.startsWith("video-display")) return "sun";
            return "";
        }
        readonly property string title: {
            if (!showingProgress) return String(osdValue ?? "");
            switch (kind) {
            case "speaker": return osdAdditionalText && osdAdditionalText.indexOf("%") < 0 ? osdAdditionalText : "Sound";
            case "mic": return "Microphone";
            case "kbd": return "Keyboard";
            case "sun": return osdAdditionalText && osdAdditionalText.indexOf("%") < 0 ? osdAdditionalText : "Display";
            }
            return osdAdditionalText || "";
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 16
            spacing: 12

            Item {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter
                Glyph {
                    anchors.fill: parent
                    visible: osd.kind === "speaker" || osd.kind === "sun" || osd.kind === "kbd"
                    kind: osd.kind || "speaker"
                    color: osd.fg
                    level: osd.fraction
                    muted: osd.kind === "speaker" && (osd.fraction === 0 || (osd.icon || "").indexOf("muted") >= 0)
                }
                Kirigami.Icon {
                    anchors.fill: parent
                    visible: !(osd.kind === "speaker" || osd.kind === "sun" || osd.kind === "kbd")
                    source: osd.icon
                    isMask: true
                    color: osd.fg
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 7

                Text {
                    Layout.fillWidth: true
                    text: osd.title
                    color: osd.fg
                    font.family: "SF Pro Text"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                // 16 segments, filled left to right; a partial segment fills proportionally
                Row {
                    visible: osd.showingProgress
                    Layout.fillWidth: true
                    spacing: 3
                    readonly property int count: 16
                    Repeater {
                        model: 16
                        delegate: Rectangle {
                            required property int index
                            readonly property real fill: Math.max(0, Math.min(1, osd.fraction * 16 - index))
                            width: (parent.width - parent.spacing * 15) / 16
                            height: 6
                            radius: 3
                            color: Qt.rgba(osd.fg.r, osd.fg.g, osd.fg.b, 0.22)
                            Rectangle {
                                width: parent.width * parent.fill
                                height: parent.height
                                radius: 3
                                color: osd.overdrive ? Kirigami.Theme.neutralTextColor : osd.fg
                                Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                            }
                        }
                    }
                }
            }
        }
    }
}
