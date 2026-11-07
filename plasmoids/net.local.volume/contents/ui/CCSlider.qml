import QtQuick
import QtQuick.Effects

// macOS Control Center slider: thick pill track, white fill up to a round white knob,
// symbol inside the track at the left that changes with the level.
// Click anywhere jumps to that point; drag; scroll wheel steps 5 %.
Item {
    id: s

    property real value: 0                 // 0..1 (external state)
    property string glyph: "speaker"
    property bool muted: false
    property bool dark: true
    property real step: 0.05
    property color trackColor: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.09)
    property color fillColor: "#ffffff"
    property color iconColor: dark ? "#7c7c80" : "#8a8a8e"

    signal moved(real v)

    readonly property bool dragging: ma.pressed
    readonly property real knob: height
    property real dragValue: 0
    property real animValue: value
    Behavior on animValue {
        enabled: !ma.pressed
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    readonly property real shown: Math.max(0, Math.min(1, ma.pressed ? dragValue : animValue))
    readonly property real fillWidth: knob + (width - knob) * shown

    implicitWidth: 240
    implicitHeight: 24

    function clamp(v) { return Math.max(0, Math.min(1, v)); }
    function valueAt(x) { return clamp((x - knob / 2) / Math.max(1, width - knob)); }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: s.trackColor
        border.width: s.dark ? 0 : 0.5
        border.color: Qt.rgba(0, 0, 0, 0.06)
    }

    Rectangle {
        id: fill
        height: parent.height
        width: s.fillWidth
        radius: height / 2
        color: s.fillColor
    }

    Item {
        id: knobSource
        x: s.fillWidth - s.knob
        width: s.knob
        height: s.knob
        visible: false
        Rectangle {
            anchors.fill: parent
            anchors.margins: 0.5
            radius: width / 2
            color: "#ffffff"
            border.width: 0.5
            border.color: Qt.rgba(0, 0, 0, 0.14)
        }
    }
    MultiEffect {
        source: knobSource
        x: knobSource.x
        y: knobSource.y
        width: knobSource.width
        height: knobSource.height
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: s.dark ? 0.45 : 0.25
        shadowBlur: 0.35
        shadowVerticalOffset: 0.5
        shadowHorizontalOffset: 0
        autoPaddingEnabled: true
    }

    Glyph {
        kind: s.glyph
        level: s.shown
        muted: s.muted
        color: s.iconColor
        dimOpacity: 0
        width: s.glyph === "speaker" ? 16 : 15
        height: width
        x: 6
        anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        preventStealing: true
        hoverEnabled: false
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            s.dragValue = s.valueAt(mouse.x);
            s.moved(s.dragValue);
        }
        onPositionChanged: mouse => {
            if (!pressed) return;
            const v = s.valueAt(mouse.x);
            if (Math.abs(v - s.dragValue) < 0.002) return;
            s.dragValue = v;
            s.moved(v);
        }
        onWheel: wheel => {
            const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x;
            if (d === 0) return;
            s.moved(s.clamp(s.value + (d > 0 ? s.step : -s.step)));
        }
    }
}
