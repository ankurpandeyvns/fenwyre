import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.milou as Milou
import org.kde.layershell as LayerShell
import net.local.blur as Blur

// macOS-style Spotlight on KRunner's search engine (Milou ResultsModel, plugins from krunnerrc).
// The menu-bar magnifier or the widget's global shortcut (Cmd+Space) opens a centred overlay.
PlasmoidItem {
    id: root

    // Inline in the menu bar (zero width), so Plasma never opens its panel popup for this applet: with a
    // compact representation, every other Cmd+Space opened that empty popup (a dark 541x390 box under the
    // menu bar). The real UI is the overlay window below.
    preferredRepresentation: fullRepresentation
    activationTogglesExpanded: false

    readonly property int panelWidth: 680
    readonly property int barHeight: 54
    readonly property int rowHeight: 38
    readonly property int maxRows: 9
    // Same glass tint as the menu bar and popups (kept in sync by ~/.local/bin/plasma-sync-glass), over a KWin blur.
    readonly property bool dark: Kirigami.Theme.textColor.hslLightness > 0.5
    readonly property color glass: dark ? Qt.rgba(0, 0, 0, 0.38) : Qt.rgba(0.8, 0.8, 0.8, 0.35)
    readonly property color fg: dark ? "white" : "#1d1d1f"
    readonly property color stroke: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color dim: dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.45)
    readonly property color accent: Kirigami.Theme.highlightColor

    function toggle() {
        if (overlay.visible) {
            close();
        } else {
            overlay.visible = true;
            overlay.requestActivate();
            field.forceActiveFocus();
            Qt.callLater(() => field.forceActiveFocus());
        }
    }
    function close() {
        overlay.visible = false;
        field.text = "";
        results.currentIndex = 0;
    }
    function runCurrent() {
        if (results.count === 0)
            return;
        const i = Math.max(0, results.currentIndex);
        if (searchModel.run(searchModel.index(i, 0)))
            close();
    }

    Connections {
        target: Plasmoid
        function onActivated() { root.toggle(); }
    }

    compactRepresentation: MouseArea {
        // macOS 26+ shows no Spotlight icon in the menu bar; the widget stays for Cmd+Space only.
        Layout.minimumWidth: 0
        Layout.preferredWidth: 0
        Layout.maximumWidth: 0
        visible: false
        onClicked: root.toggle()
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small
            height: width
            visible: false
            source: "system-search-symbolic"
            fallback: "edit-find"
            isMask: true
            color: Kirigami.Theme.textColor
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: 0
        Layout.preferredWidth: 0
        Layout.maximumWidth: 0
    }

    Milou.ResultsModel {
        id: searchModel
        queryString: field.text
        limit: 30
    }

    function isAnswer(cat) { return cat === "Calculator" || cat === "Unit Converter"; }

    Window {
        id: overlay
        visible: false
        color: "transparent"
        flags: Qt.FramelessWindowHint
        // The layer-shell surface gets keyboard focus a moment after it maps; hand it to the field then.
        onActiveChanged: if (active) field.forceActiveFocus()

        LayerShell.Window.scope: "spotlight"
        LayerShell.Window.layer: LayerShell.Window.LayerOverlay
        LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                                   | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
        LayerShell.Window.exclusionZone: -1
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
        LayerShell.Window.wantsToBeOnActiveScreen: true

        // Click anywhere outside the panel closes it, like macOS.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            id: card
            width: root.panelWidth
            height: bar.height + (resultsArea.visible ? resultsArea.height : 0)
            x: Math.round((overlay.width - width) / 2)
            y: Math.round(overlay.height * 0.22)

            MouseArea { anchors.fill: parent }   // swallow clicks inside

            Blur.BlurBehind {   // frosted background (KWin blur behind the rounded card)
                anchors.fill: parent
                radius: bg.radius
                active: overlay.visible
            }

            Rectangle {
                id: bg
                anchors.fill: parent
                radius: resultsArea.visible ? 22 : height / 2
                color: root.glass
                border.color: root.stroke
                border.width: 1
                Behavior on radius { NumberAnimation { duration: 120 } }
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.55)
                    shadowBlur: 1.0
                    shadowVerticalOffset: 10
                    blurMax: 48
                }
            }

            // Search bar
            Item {
                id: bar
                width: parent.width
                height: root.barHeight

                Kirigami.Icon {
                    id: glass
                    source: "search"
                    width: 22; height: 22
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: 0.6
                }

                // Inline completion of the top hit, drawn under the typed text (macOS shows the rest greyed).
                Text {
                    anchors.fill: field
                    verticalAlignment: Text.AlignVCenter
                    font: field.font
                    color: root.dim
                    textFormat: Text.PlainText
                    visible: text.length > 0
                    text: {
                        const q = field.text;
                        if (!q || results.count === 0)
                            return "";
                        const top = String(searchModel.data(searchModel.index(0, 0), Qt.DisplayRole) || "");
                        if (top.toLowerCase().startsWith(q.toLowerCase()) && top.length > q.length)
                            return q + top.substring(q.length);
                        return "";
                    }
                }

                TextInput {
                    id: field
                    anchors.left: glass.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: "SF Pro Display"
                    font.pixelSize: 23
                    color: root.fg
                    selectionColor: root.accent
                    clip: true
                    onTextChanged: results.currentIndex = 0

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        font: field.font
                        color: root.dim
                        text: "Spotlight Search"
                        visible: field.text.length === 0
                    }

                    Keys.onEscapePressed: root.close()
                    Keys.onReturnPressed: root.runCurrent()
                    Keys.onEnterPressed: root.runCurrent()
                    Keys.onDownPressed: results.incrementCurrentIndex()
                    Keys.onUpPressed: results.decrementCurrentIndex()
                    Keys.onTabPressed: {   // accept the inline completion
                        if (results.count > 0)
                            field.text = String(searchModel.data(searchModel.index(0, 0), Qt.DisplayRole));
                    }
                }
            }

            // Results
            Item {
                id: resultsArea
                anchors.top: bar.bottom
                width: parent.width
                visible: field.text.length > 0 && results.count > 0
                height: Math.min(results.contentHeight, root.rowHeight * root.maxRows + 60) + 14

                Rectangle {   // hairline between bar and results
                    width: parent.width - 28; height: 1
                    x: 14
                    color: root.stroke
                }

                ListView {
                    id: results
                    anchors.fill: parent
                    anchors.margins: 7
                    anchors.topMargin: 6
                    clip: true
                    model: searchModel
                    currentIndex: 0
                    keyNavigationWraps: false
                    highlightMoveDuration: 0
                    boundsBehavior: Flickable.StopAtBounds

                    section.property: "category"
                    section.delegate: Text {
                        required property string section
                        width: ListView.view.width
                        height: 24
                        leftPadding: 12
                        verticalAlignment: Text.AlignBottom
                        bottomPadding: 3
                        font.family: "SF Pro Text"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: root.dim
                        text: section
                    }

                    highlight: Rectangle { radius: 8; color: root.accent }

                    delegate: MouseArea {
                        id: row
                        required property int index
                        required property string display
                        required property var decoration
                        required property string category
                        required property string subtext
                        readonly property bool answer: root.isAnswer(category)
                        readonly property bool current: ListView.isCurrentItem

                        width: ListView.view.width
                        height: answer ? 48 : root.rowHeight
                        hoverEnabled: true
                        onEntered: results.currentIndex = index
                        onClicked: { results.currentIndex = index; root.runCurrent(); }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 12
                            spacing: 10

                            Kirigami.Icon {
                                source: row.decoration
                                Layout.preferredWidth: row.answer ? 30 : 26
                                Layout.preferredHeight: Layout.preferredWidth
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                font.family: row.answer ? "SF Pro Display" : "SF Pro Text"
                                font.pixelSize: row.answer ? 22 : 14
                                font.weight: row.answer ? Font.Medium : Font.Normal
                                color: row.current ? "white" : root.fg
                                text: (row.answer ? "= " : "") + row.display
                            }
                            Text {
                                visible: !row.answer && text.length > 0
                                font.family: "SF Pro Text"
                                font.pixelSize: 12
                                color: row.current ? Qt.rgba(1, 1, 1, 0.8) : root.dim
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                Layout.maximumWidth: 220
                                text: row.subtext || (row.category === "Applications" ? "Application" : row.category)
                            }
                        }
                    }
                }
            }
        }
    }
}
