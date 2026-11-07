/*
    Network status icon for the lock screen status items.
    SPDX-License-Identifier: LGPL-2.0-or-later
*/
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.networkmanagement as PlasmaNM

Kirigami.Icon {
    property int fontPx: 13
    implicitWidth: Math.round(fontPx * 1.35)
    implicitHeight: implicitWidth
    source: connectionIcon.connectionIcon
    color: "white"
    isMask: true
    PlasmaNM.ConnectionIcon { id: connectionIcon }
}
