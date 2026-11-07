/*
    Battery percentage + icon for the lock screen status items (macOS order: "89% [icon]").
    SPDX-License-Identifier: LGPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.private.battery

RowLayout {
    id: root
    property int fontPx: 13
    spacing: Math.round(fontPx * 0.3)
    visible: batteryControl.hasInternalBatteries

    BatteryControlModel { id: batteryControl }

    Text {
        text: batteryControl.percent + "%"
        color: "white"
        font.family: "SF Pro Text"
        font.weight: Font.Medium
        font.pixelSize: root.fontPx
        Layout.alignment: Qt.AlignVCenter
    }
    PW.BatteryIcon {
        pluggedIn: batteryControl.pluggedIn
        hasBattery: batteryControl.hasCumulative
        percent: batteryControl.percent
        Layout.preferredHeight: Math.round(root.fontPx * 1.5)
        Layout.preferredWidth: Layout.preferredHeight
        Layout.alignment: Qt.AlignVCenter
    }
}
