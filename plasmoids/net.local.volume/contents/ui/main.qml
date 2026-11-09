import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.volume as Vol

// macOS menu bar Sound item (kde-macos-parity). The glyph follows the output like macOS:
// speaker waves for speakers / HDMI, headphones when the output is headphones or a headset
// (Bluetooth or the 3.5 mm jack). Click: Sound menu with a slider and the output list.
// Volume keys and the HUD are handled elsewhere (plasma-pa's kded + the OSD override).
// Microphone (stock Plasma's tray mic indicator, in every menu bar): a mic symbol left of the sound
// item while an app records (orange) or while the mic is muted (slashed); click mutes/unmutes, wheel
// sets the input level. The menu's Input section has a mute button and the input level.
PlasmoidItem {
    id: root

    readonly property bool dark: Kirigami.Theme.textColor.hslLightness > 0.5
    readonly property string fontFamily: "SF Pro Text"
    readonly property color cText: dark ? "#ffffff" : "#1d1d1f"
    readonly property color cSub: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
    readonly property color cAccent: dark ? "#0a84ff" : "#007aff"
    readonly property color cCircleOff: dark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.075)
    readonly property color cSep: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.1)
    readonly property color cRowHover: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.055)
    readonly property int popupWidth: 310

    readonly property var sink: Vol.PreferredDevice.sink
    readonly property real normalVolume: 65536
    readonly property real volFrac: sink ? Math.min(1, sink.volume / normalVolume) : 0
    readonly property bool sinkMuted: sink ? sink.muted : true
    readonly property bool headphones: isHeadphones(sink)

    readonly property var source: Vol.PreferredDevice.source
    readonly property bool micMuted: source ? source.muted : false
    readonly property real micFrac: source ? Math.min(1, source.volume / normalVolume) : 0
    property var micApps: []           // apps recording now (names)
    readonly property bool micInUse: micApps.length > 0
    readonly property bool micShown: source !== null && (micInUse || micMuted)
    readonly property color cMicLive: "#ff9f0a"   // macOS orange: microphone in use
    readonly property color cMicMuted: "#ff453a"

    // Recording streams of real apps: skips virtual streams and PipeWire's own filter-chain captures
    // (the mic processing chain records the raw mic all the time and has no app process).
    function recomputeMic() {
        const apps = [];
        for (let i = 0; i < recModel.rowCount(); i++) {
            const po = recModel.data(recModel.index(i, 0), recModel.role("PulseObject"));
            if (!po || po.virtualStream) continue;
            const p = po.properties || {};
            const bin = p["application.process.binary"] || "";
            if (!bin || bin === "wireplumber" || bin === "pipewire") continue;
            const name = (p["application.name"] || (po.client ? po.client.name : "") || bin).replace(/ input$/, "");
            if (apps.indexOf(name) < 0) apps.push(name);
        }
        if (JSON.stringify(apps) !== JSON.stringify(micApps)) micApps = apps;
    }
    function toggleMic() {   // unmuting at 0 % would stay silent: come back at 50 %
        if (!source) return;
        if (!source.muted) { source.muted = true; return; }
        source.muted = false;
        if (source.volume <= 0) source.volume = Math.round(0.5 * normalVolume);
    }
    function setMicVolume(v) {
        if (!source) return;
        source.volume = Math.round(Math.max(0, Math.min(1, v)) * normalVolume);
        if (v > 0 && source.muted) source.muted = false;
        if (v <= 0 && !source.muted) source.muted = true;
    }
    Vol.SourceOutputModel { id: recModel }
    Connections {
        target: recModel
        function onRowsInserted() { root.recomputeMic(); }
        function onRowsRemoved() { root.recomputeMic(); }
        function onModelReset() { root.recomputeMic(); }
        function onDataChanged() { root.recomputeMic(); }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.recomputeMic() }

    // Headphones = headset/headphone form factor (Bluetooth), or an active headphone port that is
    // actually plugged in (Pulse availability 2 = unavailable).
    // A device whose only/active port is unavailable (e.g. nothing in the headphone jack): macOS hides it.
    function unplugged(s) {
        if (!s) return false;
        const ports = s.ports || [];
        if (!ports.length) return false;
        const p = s.activePortIndex >= 0 && s.activePortIndex < ports.length ? ports[s.activePortIndex] : null;
        return ports.every(q => q.availability === 2) || (p !== null && p.availability === 2 && ports.length === 1);
    }
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
    function glyphFor(name, desc, ff) {
        const t = ((name || "") + " " + (desc || "")).toLowerCase();
        const f = (ff || "").toLowerCase();
        if (["headphone", "headset", "hands-free", "handset"].indexOf(f) >= 0 || t.indexOf("headphone") >= 0 || t.indexOf("headset") >= 0) return "headphones";
        if (t.indexOf("hdmi") >= 0 || t.indexOf("displayport") >= 0) return "display";
        return "speaker";
    }
    function setVolume(v) {
        if (!sink) return;
        sink.volume = Math.round(Math.max(0, Math.min(1, v)) * normalVolume);
        if (v > 0 && sink.muted) sink.muted = false;
        if (v <= 0 && !sink.muted) sink.muted = true;
    }

    function toggleMute() {   // unmuting at 0 % would stay silent: come back at 25 %
        if (!sink) return;
        if (!sink.muted) { sink.muted = true; return; }
        sink.muted = false;
        if (sink.volume <= 0) sink.volume = Math.round(0.25 * normalVolume);
    }

    P5Support.DataSource { id: exec; engine: "executable"; connectedSources: []; onNewData: (s) => disconnectSource(s) }
    function openSettings() { root.expanded = false; exec.connectSource("systemsettings kcm_pulseaudio"); }

    Vol.SinkModel { id: sinkModel }

    preferredRepresentation: compactRepresentation
    toolTipMainText: "Sound"
    toolTipSubText: (sink ? (sink.description + " — " + (sinkMuted ? "Muted" : Math.round(volFrac * 100) + "%")) : "")
        + (source ? "\nMicrophone — " + (micMuted ? "Muted" : Math.round(micFrac * 100) + "%")
                    + (micInUse ? " (in use by " + micApps.join(", ") + ")" : "") : "")
    Plasmoid.icon: headphones ? "audio-headphones" : "audio-volume-high"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    compactRepresentation: Item {
        id: compactBox
        readonly property real unit: Math.round(Kirigami.Units.iconSizes.small * 1.6)
        Layout.minimumWidth: unit + (root.micShown ? unit : 0)
        Layout.preferredWidth: Layout.minimumWidth

        MouseArea {   // microphone: click mutes/unmutes, wheel sets the input level
            id: micArea
            visible: root.micShown
            width: compactBox.unit
            height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleMic()
            property real wheelAcc: 0
            onWheel: wheel => {
                wheelAcc += wheel.angleDelta.y;
                while (Math.abs(wheelAcc) >= 120) {
                    const d = wheelAcc > 0 ? 1 : -1;
                    wheelAcc -= d * 120;
                    root.setMicVolume((root.micMuted ? 0 : root.micFrac) + d * 0.05);
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: Math.min(parent.height, Kirigami.Units.iconSizes.small + 8)
                radius: 6
                color: Kirigami.Theme.textColor
                opacity: micArea.pressed ? 0.18 : (micArea.containsMouse ? 0.09 : 0)
                Behavior on opacity { NumberAnimation { duration: 100 } }
            }
            Glyph {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.small
                height: width
                kind: "mic"
                muted: root.micMuted
                color: root.micMuted ? Kirigami.Theme.textColor : root.cMicLive
            }
        }

    MouseArea {
        id: compact
        x: root.micShown ? compactBox.unit : 0
        width: compactBox.unit
        height: parent.height
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        property bool wasExpanded: false
        onPressed: wasExpanded = root.expanded
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) { if (root.sink) root.sink.muted = !root.sink.muted; return; }
            root.expanded = !wasExpanded;
        }
        property real wheelAcc: 0
        onWheel: wheel => {
            wheelAcc += wheel.angleDelta.y;
            while (Math.abs(wheelAcc) >= 120) {
                const d = wheelAcc > 0 ? 1 : -1;
                wheelAcc -= d * 120;
                root.setVolume((root.sinkMuted ? 0 : root.volFrac) + d * 0.05);
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: Math.min(parent.height, Kirigami.Units.iconSizes.small + 8)
            radius: 6
            color: Kirigami.Theme.textColor
            opacity: root.expanded ? 0.18 : (compact.containsMouse ? 0.09 : 0)
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
        Glyph {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small
            height: width
            kind: root.headphones ? "headphones" : "speaker"
            level: root.sinkMuted ? 0 : root.volFrac
            muted: !root.headphones && root.sinkMuted
            color: Kirigami.Theme.textColor
            dimOpacity: 0.35
        }
    }
    }

    component T11: Text {
        font.family: root.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: root.cSub
        renderType: Text.NativeRendering
    }

    fullRepresentation: Item {
        Layout.minimumWidth: root.popupWidth
        Layout.maximumWidth: root.popupWidth
        Layout.preferredWidth: root.popupWidth
        Layout.minimumHeight: col.implicitHeight + 8
        Layout.maximumHeight: col.implicitHeight + 8
        Layout.preferredHeight: col.implicitHeight + 8

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            spacing: 2

            Text {
                Layout.leftMargin: 10
                Layout.topMargin: 4
                text: "Sound"
                font.family: root.fontFamily
                font.pixelSize: 14
                font.weight: Font.Bold
                color: root.cText
                renderType: Text.NativeRendering
            }
            CCSlider {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.topMargin: 6
                Layout.bottomMargin: 8
                Layout.preferredHeight: 24
                dark: root.dark
                glyph: root.headphones ? "headphones" : "speaker"
                value: root.sinkMuted ? 0 : root.volFrac
                muted: root.sinkMuted
                glyphToggles: true
                onGlyphClicked: root.toggleMute()
                onMoved: v => root.setVolume(v)
            }
            T11 { Layout.leftMargin: 10; Layout.topMargin: 2; Layout.bottomMargin: 2; text: "Output" }
            Repeater {
                model: sinkModel
                delegate: Rectangle {
                    id: row
                    readonly property var po: model.PulseObject
                    readonly property bool active: model.Default === true
                    visible: model.Name !== "auto_null" && !(model.Name || "").startsWith("effect_input.") && !root.unplugged(po)
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: 7
                    color: ma.containsMouse ? root.cRowHover : "transparent"
                    Rectangle {
                        id: circle
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 26; radius: 13
                        color: row.active ? root.cAccent : root.cCircleOff
                        Glyph {
                            anchors.centerIn: parent
                            width: 15; height: 15
                            kind: root.glyphFor(model.Name, model.Description, row.po ? row.po.formFactor : "")
                            color: row.active ? "#ffffff" : root.cText
                        }
                    }
                    Text {
                        anchors.left: circle.right
                        anchors.leftMargin: 9
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.Description || model.Name
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        color: root.cText
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (row.po) row.po.default = true
                    }
                }
            }
            T11 { Layout.leftMargin: 10; Layout.topMargin: 8; Layout.bottomMargin: 2; text: "Input"; visible: root.source !== null }
            RowLayout {
                visible: root.source !== null
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 10
                Layout.bottomMargin: 4
                spacing: 9
                Rectangle {   // microphone mute button
                    implicitWidth: 26; implicitHeight: 26; radius: 13
                    color: root.micMuted ? root.cMicMuted : root.cCircleOff
                    border.width: micBtn.containsMouse && !root.micMuted ? 1 : 0
                    border.color: root.cSep
                    Glyph {
                        anchors.centerIn: parent
                        width: 15; height: 15
                        kind: "mic"
                        muted: root.micMuted
                        color: root.micMuted ? "#ffffff" : root.cText
                    }
                    MouseArea { id: micBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMic() }
                }
                CCSlider {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    dark: root.dark
                    glyph: "mic"
                    value: root.micMuted ? 0 : root.micFrac
                    muted: root.micMuted
                    onMoved: v => root.setMicVolume(v)
                }
            }
            Text {
                visible: root.source !== null
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                text: (root.micMuted ? "Muted" : (root.source ? root.source.description : ""))
                      + (root.micInUse ? " · in use by " + root.micApps.join(", ") : "")
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.micMuted ? root.cMicMuted : root.cSub
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }
            Rectangle { Layout.fillWidth: true; Layout.leftMargin: 10; Layout.rightMargin: 10; Layout.topMargin: 4; implicitHeight: 1; color: root.cSep }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 28
                radius: 7
                color: setMa.containsMouse ? root.cRowHover : "transparent"
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Sound Settings…"
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    color: root.cText
                    renderType: Text.NativeRendering
                }
                MouseArea { id: setMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.openSettings() }
            }
        }
    }
}
