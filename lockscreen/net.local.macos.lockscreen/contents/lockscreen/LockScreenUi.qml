/*
    macOS 26-style lock screen for Plasma, based on Plasma's stock LockScreenUi.qml
    (SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez, 2026 Kristen McWilliam).
    Authentication, session switching, keyboard layouts and the virtual keyboard work
    as in the stock lock screen; only the presentation differs:
      - date + large Liquid Glass time near the top, always shown
      - nothing else at rest; avatar, name and a glass password pill near the bottom
        appear on mouse/keyboard activity and fade after 10 s of idle
      - status icons at the top right, no Plasma footer chrome

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.accessibility
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.workspace.keyboardlayout as Keyboards
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker
import org.kde.ki18n

import org.kde.plasma.private.sessions
import org.kde.breeze.components

Item {
    id: lockScreenUi

    property bool expectingPrompt: false
    property bool showPrompt: false
    property string pendingPassword

    property Item ownWallpaper: null
    function findWallpaper() {
        var win = lockScreenUi.Window.window;
        if (!win) return;
        function walk(item, depth) {
            if (!item || depth > 4) return null;
            for (var i = 0; i < item.children.length; ++i) {
                var c = item.children[i];
                if (c === root) continue;
                if (c.configuration !== undefined && c.Window.window === win) return c;
                var r = walk(c, depth + 1);
                if (r) return r;
            }
            return null;
        }
        ownWallpaper = walk(win.contentItem, 0);
    }
    Timer { interval: 300; running: lockScreenUi.ownWallpaper === null; repeat: true; onTriggered: lockScreenUi.findWallpaper() }

    function handleMessage(msg) {
        if (!root.notification) {
            root.notification += msg;
        } else if (root.notification.includes(msg)) {
            root.notificationRepeated();
        } else {
            root.notification += "\n" + msg
        }
        lockScreenRoot.uiVisible = true
    }

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) {
                return;
            }
            const msg = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed");
            lockScreenUi.handleMessage(msg);
            root.clearPassword();
            authenticator.startAuthenticating();
            notificationRemoveTimer.restart();
            mainBlock.playHighlightAnimation();
        }

        function onSucceeded() {
            authenticator.stopAuthenticating()
            if (!lockScreenUi.expectingPrompt || authenticator.hadPrompt) {
                unlockFade.start();
            } else {
                mainStack.replace(null, Qt.resolvedUrl("NoPasswordUnlock.qml"),
                    { userListModel: users }, StackView.Immediate);
                mainStack.forceActiveFocus();
            }
        }

        function onInfoMessageChanged() { lockScreenUi.handleMessage(authenticator.infoMessage); }
        function onErrorMessageChanged() { lockScreenUi.handleMessage(authenticator.errorMessage); }
        function onPromptChanged() { lockScreenUi.handleMessage(authenticator.prompt); }
        function onPromptForSecretChanged() {
            mainBlock.showPassword = false;
            mainBlock.mainPasswordBox.forceActiveFocus();
            if (lockScreenUi.showPrompt) {
                lockScreenUi.handleMessage(authenticator.promptForSecret);
            }
        }
    }

    // macOS: the lock UI fades out (~280 ms, ease-in-out) over the continuing wallpaper
    NumberAnimation {
        id: unlockFade
        target: lockScreenRoot
        property: "opacity"
        to: 0
        duration: 280
        easing.type: Easing.InOutQuad
        onFinished: Qt.quit()
    }

    SessionManagement { id: sessionManagement }
    AccessibilityStatus { id: accessibilityStatus }
    KeyboardIndicator.KeyState { id: capsLockState; key: Qt.Key_CapsLock }

    Connections {
        target: sessionManagement
        function onAboutToSuspend() { root.clearPassword(); }
    }

    ListModel {
        id: users
        Component.onCompleted: {
            users.append({
                name: kscreenlocker_userName,
                realName: kscreenlocker_userName,
                icon: kscreenlocker_userImage !== ""
                      ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/")
                      : "",
            })
        }
    }

    MouseArea {
        id: lockScreenRoot

        property bool uiVisible: false
        property bool seenPositionChange: false
        property bool blockUI: containsMouse && (mainStack.depth > 1 || mainBlock.mainPasswordBox.text.length > 0 || Keyboards.KWinVirtualKeyboard.visible)

        x: parent.x
        y: parent.y
        width: parent.width
        height: parent.height
        hoverEnabled: true
        cursorShape: uiVisible ? Qt.ArrowCursor : Qt.BlankCursor
        drag.filterChildren: true
        onPressed: uiVisible = true;
        onPositionChanged: {
            uiVisible = seenPositionChange;
            seenPositionChange = true;
        }
        onUiVisibleChanged: {
            if (uiVisible) {
                Window.window.requestActivate();
            }
            if (blockUI) {
                fadeoutTimer.running = false;
            } else if (uiVisible) {
                fadeoutTimer.restart();
            }
            authenticator.startAuthenticating();
        }

        Timer { // heart beat keeping the backend active for as long as we are in visible state
            interval: 1000
            running: !authenticator.unlocked && parent.uiVisible
            repeat: true
            onTriggered: authenticator.startAuthenticating()
        }

        onBlockUIChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
                uiVisible = true;
            } else {
                fadeoutTimer.restart();
            }
        }
        ScreenLocker.ActiveScreenMonitor {
            id: activeScreenMonitor
            lockscreenState: ScreenLocker.LockscreenState
            window: lockScreenRoot.Window.window
            onActiveChanged: {
                if (!active) {
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Keys.onEscapePressed: {
            if (uiVisible) {
                uiVisible = false;
                if (Keyboards.KWinVirtualKeyboard.visible) {
                    Keyboards.KWinVirtualKeyboard.active = false;
                }
                root.clearPassword();
            }
        }
        Keys.onPressed: event => {
            uiVisible = true;
            event.accepted = false;
        }
        Timer {
            id: fadeoutTimer
            interval: 10000
            onTriggered: {
                if (!lockScreenRoot.blockUI) {
                    mainBlock.showPassword = false;
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Timer {
            id: notificationRemoveTimer
            interval: 3000
            onTriggered: root.notification = ""
        }

        PropertyAnimation {
            id: launchAnimation
            target: lockScreenRoot
            property: "opacity"
            from: 0
            to: 1
            duration: Kirigami.Units.veryLongDuration * 2
        }
        Component.onCompleted: launchAnimation.start();

        // ---- date + Liquid Glass time
        GlassClock {
            id: clock
            // macOS shows the clock (like the password prompt) on the main display only
            visible: config.alwaysShowClock !== false && opacity > 0
            opacity: !activeScreenMonitor.active || (config.hideClockWhenIdle && !lockScreenRoot.uiVisible) ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }
            anchors.horizontalCenter: parent.horizontalCenter
            // date top at ~8%, digits from ~13% (macOS 26 reference)
            y: Math.round(lockScreenRoot.height * 0.08)
            screenHeight: lockScreenRoot.height
            // the wallpaper item of *this* screen's window (sampling another window's item
            // aborts the render thread)
            backdrop: lockScreenUi.ownWallpaper
            style: config.clockStyle || "Stencil"
            weight: config.clockWeight !== undefined ? Number(config.clockWeight) : 1.0
        }

        // ---- status items, top right: input source, battery, Wi-Fi (no menu bar)
        RowLayout {
            id: statusBar
            opacity: activeScreenMonitor.active ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }
            anchors { top: parent.top; right: parent.right; topMargin: Math.round(lockScreenRoot.height * 0.006); rightMargin: Math.round(lockScreenRoot.height * 0.012) }
            spacing: Math.round(lockScreenRoot.height * 0.011)
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.4); shadowBlur: 0.3 }
            readonly property int fontPx: Math.max(11, Math.round(lockScreenRoot.height * 0.0125))

            MouseArea {     // input source; click to switch layout
                id: keyboardButton
                implicitWidth: layoutRow.implicitWidth
                implicitHeight: layoutRow.implicitHeight
                acceptedButtons: Qt.LeftButton
                Accessible.description: i18ndc("plasma_shell_org.kde.plasma.desktop", "Button to change keyboard layout", "Switch layout")
                PW.KeyboardLayoutSwitcher {
                    id: keyboardLayoutSwitcher
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                }
                onClicked: keyboardLayoutSwitcher.keyboardLayout.switchToNextLayout()
                RowLayout {
                    id: layoutRow
                    spacing: Math.round(statusBar.fontPx * 0.35)
                    Text {
                        text: {
                            var n = keyboardLayoutSwitcher.layoutNames.shortName || "";
                            return (n === "" || n.toLowerCase() === "us" || n.toLowerCase() === "gb") ? "ABC" : n.toUpperCase();
                        }
                        color: "white"
                        font.family: "SF Pro Text"
                        font.weight: Font.Medium
                        font.pixelSize: statusBar.fontPx
                    }
                    Kirigami.Icon {
                        source: "input-keyboard"
                        color: "white"
                        isMask: true
                        Layout.preferredWidth: statusBar.fontPx * 1.25
                        Layout.preferredHeight: statusBar.fontPx * 1.25
                    }
                }
            }
            Loader {
                source: "StatusBattery.qml"
                onLoaded: item.fontPx = Qt.binding(() => statusBar.fontPx)
            }
            Loader {
                source: "StatusWifi.qml"
                onLoaded: item.fontPx = Qt.binding(() => statusBar.fontPx)
            }
        }

        Connections {
            target: authenticator
            function onPamTimeoutChanged(): void {
                if (!authenticator.pamTimeout && lockScreenUi.pendingPassword.length > 0) {
                    authenticator.respond(lockScreenUi.pendingPassword);
                    lockScreenUi.pendingPassword = "";
                    mainBlock.enabled = true;
                }
            }
        }

        // ---- unlock prompt, near the bottom like macOS
        StackView {
            id: mainStack
            anchors.fill: parent
            focus: true
            // like macOS, the password prompt only appears on one display (the active one);
            // the others show just the clock over the wallpaper
            opacity: activeScreenMonitor.active ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }

            initialItem: MacBlock {
                id: mainBlock
                lockScreenUiVisible: lockScreenRoot.uiVisible
                screenHeight: lockScreenRoot.height
                userName: kscreenlocker_userName
                avatar: kscreenlocker_userImage !== ""
                        ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/") : ""

                StackView.onStatusChanged: {
                    if (StackView.status === StackView.Activating) {
                        mainPasswordBox.clear();
                        mainPasswordBox.focus = true;
                        root.notification = "";
                    }
                }

                authenticationTypeItem: RowLayout {
                    visible: authenticationTypeRepeater.count > 1
                    Repeater {
                        id: authenticationTypeRepeater
                        model: ScreenLocker.AuthenticatorModel
                        delegate: PlasmaComponents3.Button {
                            required property int type
                            required property string iconName
                            required property bool passwordField
                            required property bool expectingPrompt
                            required property string tooltip
                            required property bool showPrompt
                            required property bool functional

                            onFunctionalChanged: {
                                if (functional) {
                                    return
                                }
                                root.notification = ""
                                mainBlock.passwordInputVisible = false
                                lockScreenUi.handleMessage(KI18n.i18ndc(
                                    "plasma_shell_org.kde.plasma.desktop",
                                    "@info:status",
                                    "This authentication method is not functioning correctly. Please try another method, and check your system configuration."))
                            }
                            enabled: functional
                            icon.name: iconName
                            icon.color: functional ? undefined : Kirigami.Theme.negativeTextColor
                            checked: authenticator.authenticator === type
                            onClicked: {
                                authenticator.authenticator = type
                                root.notification = ""
                                mainBlock.passwordInputVisible = passwordField
                                lockScreenUi.expectingPrompt = expectingPrompt
                                lockScreenUi.showPrompt = showPrompt
                            }
                            PlasmaComponents3.ToolTip.text: tooltip
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                            PlasmaComponents3.ToolTip.visible: hovered
                            Component.onCompleted: {
                                if (checked) {
                                    clicked()
                                }
                            }
                        }
                    }
                }

                notificationMessage: {
                    const parts = [];
                    if (capsLockState.locked) {
                        parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Caps Lock is on"));
                    }
                    if (accessibilityStatus.slowKeysEnabled) {
                        parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Slow Keys are enabled"));
                    }
                    if (root.notification) {
                        parts.push(root.notification);
                    }
                    return parts.join(" • ");
                }

                onPasswordResult: password => {
                    if (authenticator.pamTimeout) {
                        lockScreenUi.pendingPassword = password
                        mainBlock.enabled = false
                    } else {
                        authenticator.respond(password)
                    }
                }

            }
        }

        Loader {
            z: 2
            active: root.viewVisible
            source: "LockOsd.qml"
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Kirigami.Units.gridUnit
            }
        }
    }
}
