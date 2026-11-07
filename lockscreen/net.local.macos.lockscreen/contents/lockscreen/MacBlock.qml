/*
    macOS-style unlock block: round avatar, user name, a glass "Enter Password" pill,
    and a small hint line underneath. Keeps the interface LockScreenUi.qml expects from
    Breeze's MainBlock (mainPasswordBox, passwordResult, notificationMessage, ...).

    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Effects

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker

FocusScope {
    id: block

    property string userName: ""
    property url avatar: ""
    property alias passwordInputVisible: pill.visible
    readonly property alias mainPasswordBox: passwordBox
    property bool lockScreenUiVisible: false
    property bool showPassword: false
    property string notificationMessage: ""
    property Item authenticationTypeItem: null
    property real screenHeight: 1080

    signal passwordResult(string password)

    function startLogin() {
        const password = passwordBox.text;
        unlockButton.forceActiveFocus();
        passwordResult(password);
    }
    function playHighlightAnimation() { shake.start(); }


    // Positions measured from a macOS 26 recording (fractions of the screen height):
    // avatar centre 85%, password pill centre 90.5%, hint centre 93.5%.
    readonly property real sh: screenHeight

    Item {
        id: avatarItem
        readonly property int size: Math.round(block.sh * 0.048)
        x: Math.round((block.width - size) / 2)
        y: Math.round(block.sh * 0.85 - size / 2)
        width: size
        height: size
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(1, 1, 1, 0.25)
            border.color: Qt.rgba(1, 1, 1, 0.35)
            border.width: 1
            Kirigami.Icon {
                anchors.centerIn: parent
                width: parent.width * 0.6
                height: width
                source: "user-identity"
                color: "white"
                visible: avatarImage.status !== Image.Ready
            }
        }
        Image {
            id: avatarImage
            anchors.fill: parent
            source: block.avatar
            sourceSize: Qt.size(width * 2, height * 2)
            fillMode: Image.PreserveAspectCrop
            visible: false
            layer.enabled: true
        }
        Rectangle {
            id: avatarMask
            anchors.fill: parent
            radius: width / 2
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            visible: avatarImage.status === Image.Ready
            source: avatarImage
            maskEnabled: true
            maskSource: avatarMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    Item {
        id: pill
        width: Math.round(block.sh * 0.162)
        height: Math.round(block.sh * 0.0278)
        x: Math.round((block.width - width) / 2)
        y: Math.round(block.sh * 0.905 - height / 2)

        transform: Translate { id: shakeX }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: shakeX; property: "x"; to: -12; duration: 50 }
            NumberAnimation { target: shakeX; property: "x"; to: 12; duration: 80 }
            NumberAnimation { target: shakeX; property: "x"; to: -8; duration: 70 }
            NumberAnimation { target: shakeX; property: "x"; to: 6; duration: 60 }
            NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 50 }
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(1, 1, 1, passwordBox.activeFocus ? 0.24 : 0.18)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.32)
            Rectangle {     // top highlight of the glass
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                height: parent.height / 2
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.16) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }
        }

        QQC2.TextField {
            id: passwordBox
            anchors.fill: parent
            anchors.leftMargin: parent.height * 0.45
            anchors.rightMargin: parent.height * 0.95
            background: null
            color: "white"
            placeholderText: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:placeholder in text field", "Enter Password")
            placeholderTextColor: Qt.rgba(1, 1, 1, 0.72)
            echoMode: block.showPassword ? TextInput.Normal : TextInput.Password
            passwordCharacter: "●"
            horizontalAlignment: TextInput.AlignLeft
            verticalAlignment: TextInput.AlignVCenter
            font.family: "SF Pro Text"
            font.pixelSize: Math.max(11, Math.round(parent.height * 0.47))
            selectByMouse: true
            focus: true
            text: PasswordSync.password
            cursorVisible: visible && activeFocus
            inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            onAccepted: {
                if (block.lockScreenUiVisible) {
                    block.startLogin();
                }
            }
            Connections {
                target: root
                function onClearPassword() {
                    passwordBox.forceActiveFocus();
                    passwordBox.text = "";
                    passwordBox.text = Qt.binding(() => PasswordSync.password);
                }
                function onNotificationRepeated() {
                    block.playHighlightAnimation();
                }
            }
        }
        Binding {
            target: PasswordSync
            property: "password"
            value: passwordBox.text
        }

        // round "go" button inside the pill, shown once something is typed
        QQC2.AbstractButton {
            id: unlockButton
            anchors.right: parent.right
            anchors.rightMargin: parent.height * 0.12
            anchors.verticalCenter: parent.verticalCenter
            width: parent.height * 0.76
            height: width
            opacity: passwordBox.text.length > 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Accessible.name: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button accessible only", "Unlock")
            background: Rectangle { radius: width / 2; color: Qt.rgba(1, 1, 1, unlockButton.down ? 0.5 : 0.3) }
            contentItem: Kirigami.Icon {
                source: LayoutMirroring.enabled ? "go-previous" : "go-next"
                color: "white"
                isMask: true
            }
            onClicked: block.startLogin()
            Keys.onEnterPressed: clicked()
            Keys.onReturnPressed: clicked()
        }
    }

    // small hint / status line
    Text {
        width: block.sh * 0.6
        x: Math.round((block.width - width) / 2)
        y: Math.round(block.sh * 0.935 - height / 2)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: block.notificationMessage.length > 0 ? block.notificationMessage
              : i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:placeholder in text field", "Enter Password")
        color: Qt.rgba(1, 1, 1, 0.72)
        font.family: "SF Pro Text"
        font.weight: Font.Medium
        font.pixelSize: Math.max(10, Math.round(block.sh * 0.0112))
    }

    // alternative authenticators (fingerprint, smartcard), only when there are several
    Item {
        x: Math.round((block.width - width) / 2)
        y: Math.round(block.sh * 0.955)
        width: block.authenticationTypeItem ? block.authenticationTypeItem.implicitWidth : 0
        height: block.authenticationTypeItem ? block.authenticationTypeItem.implicitHeight : 0
        data: block.authenticationTypeItem ? [block.authenticationTypeItem] : []
    }
}
