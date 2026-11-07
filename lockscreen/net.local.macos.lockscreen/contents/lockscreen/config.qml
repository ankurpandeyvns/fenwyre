import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

Kirigami.FormLayout {
    id: configForm

    // TODO Plasma 7: Make this an enum.
    property bool cfg_alwaysShowClock
    property bool cfg_hideClockWhenIdle
    property bool cfg_alwaysShowClockDefault: true
    property bool cfg_hideClockWhenIdleDefault: false

    property bool cfg_showMediaControls
    property bool cfg_showMediaControlsDefault: false
    property string cfg_clockStyle
    property string cfg_clockStyleDefault: "Stencil"
    property real cfg_clockWeight
    property real cfg_clockWeightDefault: 1.0

    twinFormLayouts: parentLayout

    QQC2.RadioButton {
        Kirigami.FormData.label: i18ndc("plasma_shell_org.kde.plasma.desktop",
                                        "@title: group",
                                        "Show clock:")
        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@option:radio Clock always shown", "Always")
        Accessible.name: i18nc("@option:radio", "Always show clock")
        checked: configForm.cfg_alwaysShowClock && !configForm.cfg_hideClockWhenIdle
        onToggled: {
            configForm.cfg_alwaysShowClock = true;
            configForm.cfg_hideClockWhenIdle = false;
        }

        KCM.SettingHighlighter {
            id: clockAlwaysHighlighter
            highlight: configForm.cfg_alwaysShowClock != configForm.cfg_alwaysShowClockDefault
                || configForm.cfg_hideClockWhenIdle != configForm.cfg_hideClockWhenIdleDefault
        }
    }

    QQC2.RadioButton {
        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@option:radio Clock shown only while unlock prompt is visible", "On unlocking prompt")
        Accessible.name: i18nc("@option:radio", "Show clock only on unlocking prompt")
        checked: configForm.cfg_alwaysShowClock && configForm.cfg_hideClockWhenIdle
        onToggled: {
            configForm.cfg_alwaysShowClock = true;
            configForm.cfg_hideClockWhenIdle = true;
        }

        KCM.SettingHighlighter {
            highlight: clockAlwaysHighlighter.highlight
        }
    }

    QQC2.RadioButton {
        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@option:radio Clock never shown", "Never")
        Accessible.name: i18nc("@option:radio", "Never show clock")
        checked: !configForm.cfg_alwaysShowClock
        onToggled: {
            configForm.cfg_alwaysShowClock = false;
        }

        KCM.SettingHighlighter {
            highlight: clockAlwaysHighlighter.highlight
        }
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: "Clock style:"
        readonly property var styles: ["Rounded", "Pro", "Stencil", "Serif", "Compact", "Thin"]
        model: ["SF Pro Rounded", "SF Pro", "Stencil", "New York", "SF Compact", "Thin"]
        currentIndex: Math.max(0, styles.indexOf(configForm.cfg_clockStyle))
        onActivated: configForm.cfg_clockStyle = styles[currentIndex]
    }
    QQC2.Slider {
        Kirigami.FormData.label: "Weight:"
        from: 0
        to: 1
        stepSize: 0.2
        value: configForm.cfg_clockWeight
        onMoved: configForm.cfg_clockWeight = value
    }
}
