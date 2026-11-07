import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "Assets.js" as A

Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout
    property alias formLayout: root

    property string cfg_Scene
    property string cfg_Colour
    property string cfg_Appearance
    property real cfg_Speed
    property bool cfg_PauseWhenCovered
    property bool cfg_AnimateDesktop
    property string cfg_FrozenAt

    readonly property var sceneModel: {
        var m = [{ value: "Cycle", text: "Cycle all scenes" }];
        for (var i = 0; i < A.PROGRAMS.length; ++i)
            m.push({ value: A.PROGRAMS[i][0], text: A.PROGRAMS[i][1] + (A.PROGRAMS[i][2] === "apple" ? "  (Apple program)" : "") });
        return m;
    }
    readonly property var colourModel: A.COLOURS.map(function (c) { return { value: c, text: c }; })
    readonly property var appearanceModel: [
        { value: "Light", text: "Light" },
        { value: "Dark", text: "Dark (deeper background)" },
        { value: "Automatic", text: "Automatic (follow colour scheme)" }
    ]

    function indexOf(model, v) {
        for (var i = 0; i < model.length; ++i) if (model[i].value === v) return i;
        return 0;
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: "Scene:"
        model: root.sceneModel
        textRole: "text"
        valueRole: "value"
        currentIndex: root.indexOf(root.sceneModel, root.cfg_Scene)
        onActivated: root.cfg_Scene = currentValue
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: "Colour:"
        model: root.colourModel
        textRole: "text"
        valueRole: "value"
        currentIndex: root.indexOf(root.colourModel, root.cfg_Colour)
        onActivated: root.cfg_Colour = currentValue
    }
    QQC2.ComboBox {
        Kirigami.FormData.label: "Appearance:"
        model: root.appearanceModel
        textRole: "text"
        valueRole: "value"
        currentIndex: root.indexOf(root.appearanceModel, root.cfg_Appearance)
        onActivated: root.cfg_Appearance = currentValue
    }
    Row {
        Kirigami.FormData.label: "Speed:"
        spacing: Kirigami.Units.smallSpacing
        QQC2.Slider {
            id: speedSlider
            from: 0.25
            to: 2.0
            stepSize: 0.05
            value: root.cfg_Speed > 0 ? root.cfg_Speed : 0.75
            onMoved: root.cfg_Speed = value
        }
        QQC2.Label {
            anchors.verticalCenter: parent.verticalCenter
            text: speedSlider.value.toFixed(2) + "×"
        }
    }
    QQC2.CheckBox {
        Kirigami.FormData.label: "Desktop:"
        text: "Animate on the desktop too (macOS animates only on the lock screen)"
        checked: root.cfg_AnimateDesktop
        onToggled: root.cfg_AnimateDesktop = checked
    }
    QQC2.CheckBox {
        id: pauseBox
        enabled: root.cfg_AnimateDesktop
        text: "Pause while a maximized or full-screen window covers the screen"
        checked: root.cfg_PauseWhenCovered
        onToggled: root.cfg_PauseWhenCovered = checked
    }
}
