import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.bluezqt as BluezQt
import org.kde.plasma.private.volume as Vol
import org.kde.plasma.private.brightnesscontrolplugin as BC
import org.kde.plasma.private.mpris as Mpris
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.private.battery as Bat
import org.kde.plasma.private.batterymonitor as BatMon

// macOS (26/27) style Control Center for the Plasma menu bar.
// Every control is bound to a live Plasma backend; see the module sections below.
PlasmoidItem {
    id: root

    // ---------------------------------------------------------------- look
    readonly property bool dark: Kirigami.Theme.textColor.hslLightness > 0.5
    readonly property string fontFamily: "SF Pro Text"
    readonly property color cText: dark ? "#ffffff" : "#1d1d1f"
    readonly property color cSub: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)
    readonly property color cTile: dark ? Qt.rgba(1, 1, 1, 0.085) : Qt.rgba(1, 1, 1, 0.62)
    readonly property color cTileHover: dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.82)
    readonly property color cTileBorder: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color cCircleOff: dark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.075)
    readonly property color cAccent: dark ? "#0a84ff" : "#007aff"
    readonly property color cFocus: dark ? "#5e5ce6" : "#5856d6"
    readonly property color cSep: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.1)
    readonly property color cRowHover: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.055)
    readonly property color cGreen: dark ? "#30d158" : "#34c759"

    readonly property int cell: 70
    readonly property int gap: 10
    readonly property int unit: cell + gap
    readonly property int popupWidth: 4 * cell + 3 * gap

    // ---------------------------------------------------------------- state
    property string page: "main"
    // Where the last module was clicked (in page coordinates): detail views zoom out of it
    // and the grid zooms back into it, like macOS.
    property point zoomOrigin: Qt.point(popupWidth / 2, 0)
    property bool animatePages: false
    function openPage(name, origin) {
        if (origin) zoomOrigin = origin;
        animatePages = true;
        page = name;
    }
    property string screenName: ""
    property string screenModel: ""
    property date nowTick: new Date()

    // In a panel: menu bar icon + popup. On the desktop / in a window: the panel itself.
    preferredRepresentation: (Plasmoid.formFactor === PlasmaCore.Types.Planar || Plasmoid.formFactor === PlasmaCore.Types.Application) ? fullRepresentation : compactRepresentation
    toolTipMainText: "Control Center"
    toolTipSubText: ""
    Plasmoid.icon: "preferences-system"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    onExpandedChanged: {
        if (root.expanded) {
            nowTick = new Date();
            refreshNightLight();
        } else {
            animatePages = false;
            page = "main";
            wifiPasswordFor = "";
        }
    }
    onPageChanged: {
        if (page === "wifi") nmHandler.requestScan();
        if (page === "display") refreshNightLight();
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.expanded
        onTriggered: root.nowTick = new Date()
    }

    // ---------------------------------------------------------------- shell commands
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        property var callbacks: ({})
        onNewData: (source, data) => {
            const cb = callbacks[source];
            delete callbacks[source];
            disconnectSource(source);
            if (cb) cb((data["stdout"] || "").trim(), data["exit code"]);
        }
    }
    function run(cmd, cb) {
        if (cb) exec.callbacks[cmd] = cb;
        exec.connectSource(cmd);
    }
    function openSettings(kcm) {
        root.expanded = false;
        run("systemsettings " + kcm);
    }

    // ================================================================ Wi-Fi + VPN (NetworkManager)
    PlasmaNM.Handler { id: nmHandler }
    PlasmaNM.EnabledConnections { id: nmEnabled }
    PlasmaNM.NetworkModel { id: nmModel }
    PlasmaNM.AppletProxyModel { id: nmProxy; sourceModel: nmModel }

    readonly property bool wifiOn: nmEnabled.wirelessEnabled
    property string wifiName: ""
    property int vpnCount: 0
    property int vpnActive: 0
    property string wifiPasswordFor: ""

    function isVpnType(t) { return t === PlasmaNM.Enums.Vpn || t === 19; }   // 19 = NM WireGuard
    function refreshNet() {
        let w = "", vc = 0, va = 0;
        for (let i = 0; i < netInst.count; i++) {
            const o = netInst.objectAt(i);
            if (!o) continue;
            if (o.wifiActive && !w) w = o.name;
            if (o.vpn && o.saved) { vc++; if (o.active) va++; }
        }
        wifiName = w; vpnCount = vc; vpnActive = va;
    }
    Instantiator {
        id: netInst
        model: nmModel
        delegate: QtObject {
            readonly property string name: model.Name || ""
            readonly property bool active: model.ConnectionState === PlasmaNM.Enums.Activated
            readonly property bool wifiActive: model.Type === PlasmaNM.Enums.Wireless && active
            readonly property bool vpn: root.isVpnType(model.Type)
            readonly property bool saved: (model.Uuid || "") !== ""
            onActiveChanged: Qt.callLater(root.refreshNet)
            onNameChanged: Qt.callLater(root.refreshNet)
            Component.onCompleted: Qt.callLater(root.refreshNet)
            Component.onDestruction: Qt.callLater(root.refreshNet)
        }
    }
    function toggleWifi() { nmHandler.enableWireless(!nmEnabled.wirelessEnabled); }
    function vpnAllOff() {
        for (let i = 0; i < netInst.count; i++) {
            const o = netInst.objectAt(i);
            if (o && o.vpn && o.active) {
                const idx = nmModel.index(i, 0);
                nmHandler.deactivateConnection(nmModel.data(idx, roleOf(nmModel, "ConnectionPath")), nmModel.data(idx, roleOf(nmModel, "DevicePath")));
            }
        }
    }
    function roleOf(model, name) {
        const names = model.roleNames();
        for (const k in names) if (names[k] === name) return Number(k);
        return -1;
    }

    // ================================================================ Bluetooth (BlueZ)
    readonly property bool btOn: BluezQt.Manager.bluetoothOperational
    readonly property bool btAvailable: BluezQt.Manager.adapters.length > 0
    function toggleBt() {
        const enable = !BluezQt.Manager.bluetoothOperational;
        BluezQt.Manager.bluetoothBlocked = !enable;
        const ads = BluezQt.Manager.adapters;
        for (let i = 0; i < ads.length; i++) ads[i].powered = enable;
    }
    BluezQt.DevicesModel { id: btDevices }
    function btGlyph(icon) {
        if (icon.includes("mouse") || icon.includes("tablet")) return "mouse";
        if (icon.includes("keyboard")) return "keyboard";
        if (icon.includes("headphone") || icon.includes("headset") || icon.includes("audio")) return "headphones";
        if (icon.includes("phone")) return "phone";
        if (icon.includes("computer") || icon.includes("laptop")) return "display";
        return "bluetooth";
    }

    // ================================================================ Focus (Do Not Disturb)
    NotificationManager.Settings { id: notifSettings; live: true }
    readonly property date dndUntil: notifSettings.notificationsInhibitedUntil
    readonly property bool dndTimed: !isNaN(dndUntil.getTime()) && dndUntil > nowTick
    readonly property bool dndOn: dndTimed || notifSettings.notificationsInhibitedByApplication
    readonly property bool dndIndefinite: dndTimed && dndUntil.getFullYear() > nowTick.getFullYear()
    function setDnd(until) {
        notifSettings.notificationsInhibitedUntil = until;
        notifSettings.save();
        nowTick = new Date();
    }
    function dndForever() { const d = new Date(); d.setFullYear(d.getFullYear() + 1); setDnd(d); }
    function dndOff() {
        notifSettings.notificationsInhibitedUntil = undefined;
        notifSettings.revokeApplicationInhibitions();
        notifSettings.save();
        nowTick = new Date();
    }
    function toggleDnd() { if (dndOn) dndOff(); else dndForever(); }
    function dndSubtitle() {
        if (!dndOn) return "";
        if (!dndTimed) return "On (app request)";
        if (dndIndefinite) return "On";
        return "Until " + Qt.formatTime(dndUntil, "h:mm AP");
    }

    // ================================================================ Display (KDE per-screen brightness, DDC/CI on externals)
    BC.ScreenBrightnessControl { id: sbc; isSilent: true }
    property int dispRev: 0
    Instantiator {
        id: dispInst
        model: sbc.displays
        delegate: QtObject {
            readonly property string dname: model.displayName
            readonly property string label: model.label
            readonly property bool internal: model.isInternal
            readonly property int bri: model.brightness
            readonly property int maxBri: model.maxBrightness
        }
        onObjectAdded: root.dispRev++
        onObjectRemoved: root.dispRev++
    }
    readonly property var displayList: {
        dispRev;
        const l = [];
        for (let i = 0; i < dispInst.count; i++) if (dispInst.objectAt(i)) l.push(dispInst.objectAt(i));
        return l;
    }
    // The display this panel lives on (macOS adjusts the display showing the menu bar you clicked).
    readonly property var myDisplay: {
        const l = displayList;
        if (!l.length) return null;
        if (screenName.startsWith("eDP") || screenName.startsWith("LVDS")) return l.find(d => d.internal) || l[0];
        const m = screenModel.toLowerCase();
        return (m && l.find(d => !d.internal && d.label.toLowerCase().includes(m))) || l.find(d => !d.internal) || l[0];
    }
    property var pendingBri: ({})
    function setBrightness(d, frac) {
        if (!d) return;
        // Built-in panel: slider is perceived lightness (CIE L*), like macOS; externals are already perceptual.
        const lin = d.internal ? lstarToY(frac) : frac;
        const minV = d.internal ? Math.max(1, Math.round(d.maxBri * 0.0011)) : 0;
        const p = pendingBri;
        p[d.dname] = Math.max(minV, Math.round(lin * d.maxBri));
        pendingBri = p;
        briTimer.start();
    }
    Timer {
        id: briTimer
        interval: 35
        onTriggered: {
            const p = root.pendingBri;
            root.pendingBri = {};
            for (const k in p) sbc.setBrightness(k, p[k]);
        }
    }
    function lstarToY(l) { const L = l * 100; return L > 8 ? Math.pow((L + 16) / 116, 3) : L / 903.3; }
    function yToLstar(y) { return (y > 0.008856 ? 116 * Math.cbrt(y) - 16 : y * 903.3) / 100; }
    function briFrac(d) {
        if (!d || d.maxBri <= 0) return 0;
        const y = d.bri / d.maxBri;
        return d.internal ? yToLstar(y) : y;
    }

    // Dark Mode (Plasma global theme light/dark pair) and Night Light (KWin)
    readonly property bool darkModeOn: BC.DarkModeControl.darkMode
    property bool nightOn: false
    function refreshNightLight() {
        run("qdbus6 org.kde.KWin /org/kde/KWin/NightLight org.freedesktop.DBus.Properties.Get org.kde.KWin.NightLight enabled", out => root.nightOn = (out === "true"));
    }
    function toggleNightLight() {
        const want = !nightOn;
        nightOn = want;
        // KWin follows kwinrc through KConfigWatcher, so the write must be --notify.
        // "Off" deletes the key again (KWin's default is off) instead of leaving Active=false behind.
        run("kwriteconfig6 --notify --file kwinrc --group NightColor --key Active " + (want ? "true" : "--delete")
            + " && sleep 0.5 && echo done-" + Date.now(),
            () => root.refreshNightLight());
    }

    // Keyboard backlight (PowerDevil)
    BC.KeyboardBrightnessControl { id: kbc; isSilent: true }
    readonly property bool kbdAvailable: kbc.isBrightnessAvailable && kbc.brightnessMax > 0

    // ================================================================ Sound (PipeWire via PulseAudio API)
    readonly property var sink: Vol.PreferredDevice.sink
    readonly property real normalVolume: 65536
    readonly property real volFrac: sink ? Math.min(1, sink.volume / normalVolume) : 0
    readonly property bool sinkMuted: sink ? sink.muted : true
    readonly property bool headphones: isHeadphones(sink)
    // Headphones = headset/headphone form factor (Bluetooth), or an active headphone port that is
    // plugged in (Pulse port availability 2 = unavailable).
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
    function setVolume(v) {
        if (!sink) return;
        sink.volume = Math.round(v * normalVolume);
        if (v > 0 && sink.muted) sink.muted = false;
        if (v === 0 && !sink.muted) sink.muted = true;
    }
    Vol.SinkModel { id: sinkModel }

    // ================================================================ Now Playing (MPRIS)
    Mpris.Mpris2Model { id: mpris }
    readonly property var player: mpris.currentPlayer
    readonly property bool playing: player && player.playbackStatus === Mpris.PlaybackStatus.Playing

    // ================================================================ Battery / Energy Mode
    Bat.BatteryControlModel { id: batt }
    BatMon.PowerProfilesControl { id: ppc }
    readonly property bool hasBattery: batt.hasInternalBatteries
    function profileName(p) {
        return p === "power-saver" ? "Low Power" : p === "balanced" ? "Automatic" : p === "performance" ? "High Power" : p;
    }
    function fmtRemaining(ms) {
        if (!ms) return "";
        const m = Math.round(ms / 60000);
        return Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0");
    }

    // ================================================================ building blocks
    component T13: Text {
        font.family: root.fontFamily
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: root.cText
        elide: Text.ElideRight
        renderType: Text.NativeRendering
    }
    component T11: Text {
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.cSub
        elide: Text.ElideRight
        renderType: Text.NativeRendering
    }

    component Tile: Rectangle {
        property int col: 0
        property int row: 0
        property int cols: 1
        property int rows: 1
        property bool hoverable: false
        property bool down: false
        readonly property alias hovered: tileHover.hovered
        scale: down ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        x: col * root.unit
        y: row * root.unit
        width: cols * root.unit - root.gap
        height: rows * root.unit - root.gap
        radius: 18
        color: hoverable && tileHover.hovered ? root.cTileHover : root.cTile
        border.width: 1
        border.color: root.cTileBorder
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: tileHover }
    }

    // Round toggle as used in the connectivity / Focus modules.
    component Circle: Rectangle {
        id: circ
        property string glyph: ""
        property bool on: false
        property color onColor: root.cAccent
        property real glyphScale: 0.54
        property real glyphLevel: 1
        signal clicked()
        width: 30
        height: width
        radius: width / 2
        color: on ? onColor : root.cCircleOff
        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutQuad } }
        scale: circMa.pressed ? 0.88 : 1
        Behavior on scale { SpringAnimation { spring: 6; damping: 0.32; epsilon: 0.002 } }
        Glyph {
            anchors.centerIn: parent
            width: parent.width * circ.glyphScale
            height: width
            kind: circ.glyph
            level: circ.glyphLevel
            color: circ.on ? "#ffffff" : root.cText
            Behavior on color { ColorAnimation { duration: 200 } }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "#000000"
            opacity: circMa.pressed ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        MouseArea {
            id: circMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: circ.clicked()
        }
    }

    // Circle + title + subtitle: click circle toggles, click text opens the detail page.
    component ModuleRow: Item {
        id: mr
        property string glyph
        property bool on
        property color onColor: root.cAccent
        property string title
        property string subtitle
        property real glyphLevel: 1
        signal toggle()
        signal open()
        height: 36
        Circle {
            id: mrc
            width: 32
            anchors.verticalCenter: parent.verticalCenter
            glyph: mr.glyph
            on: mr.on
            onColor: mr.onColor
            glyphLevel: mr.glyphLevel
            onClicked: mr.toggle()
        }
        Column {
            anchors.left: mrc.right
            anchors.leftMargin: 9
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            opacity: mrMa.pressed ? 0.55 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
            T13 { width: parent.width; text: mr.title }
            T11 { width: parent.width; text: mr.subtitle; visible: text !== "" }
        }
        MouseArea {
            id: mrMa
            x: mrc.width + 4
            width: parent.width - x
            height: parent.height
            cursorShape: Qt.PointingHandCursor
            onClicked: mr.open()
        }
    }

    component AppleSwitch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled()
        implicitWidth: 32
        implicitHeight: 19
        radius: height / 2
        color: checked ? root.cAccent : (root.dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.12))
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: parent.height - 3
            height: width
            radius: width / 2
            y: 1.5
            x: sw.checked ? parent.width - width - 1.5 : 1.5
            color: "#ffffff"
            border.width: 0.5
            border.color: Qt.rgba(0, 0, 0, 0.12)
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }

    component Sep: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        implicitHeight: 1
        color: root.cSep
    }

    component SectionLabel: T11 {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.topMargin: 4
        Layout.bottomMargin: 2
        font.weight: Font.DemiBold
    }

    component ListRow: Rectangle {
        id: lr
        property string glyph: ""
        property string iconName: ""
        property bool active: false
        property bool showCircle: true
        property string text: ""
        property string detail: ""
        property string rightText: ""
        property bool locked: false
        property bool checked: false
        property real strength: 1
        property bool busy: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: showCircle ? 36 : 28
        radius: 7
        color: rowMa.pressed ? Qt.darker(root.cRowHover, root.dark ? 0.6 : 1.15) : rowMa.containsMouse ? root.cRowHover : "transparent"
        Behavior on color { ColorAnimation { duration: 110 } }
        Rectangle {
            id: lrCircle
            visible: lr.showCircle
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26
            radius: 13
            color: lr.active ? root.cAccent : root.cCircleOff
            Behavior on color { ColorAnimation { duration: 200 } }
            scale: rowMa.pressed ? 0.9 : 1
            Behavior on scale { SpringAnimation { spring: 6; damping: 0.32; epsilon: 0.002 } }
            Glyph {
                visible: lr.glyph !== ""
                anchors.centerIn: parent
                width: 15
                height: 15
                kind: lr.glyph
                level: lr.strength
                color: lr.active ? "#ffffff" : root.cText
            }
            Kirigami.Icon {
                visible: lr.glyph === "" && lr.iconName !== ""
                anchors.centerIn: parent
                width: 15
                height: 15
                source: lr.iconName
                isMask: true
                color: lr.active ? "#ffffff" : root.cText
            }
        }
        Glyph {
            id: lrCheck
            visible: !lr.showCircle && lr.checked
            x: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            kind: "check"
            color: root.cText
        }
        Column {
            anchors.left: lr.showCircle ? lrCircle.right : parent.left
            anchors.leftMargin: lr.showCircle ? 9 : 26
            anchors.right: lrRight.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                text: lr.text
                font.family: root.fontFamily
                font.pixelSize: 13
                color: root.cText
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }
            T11 { width: parent.width; text: lr.detail; visible: text !== "" }
        }
        Row {
            id: lrRight
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            PlasmaComponents.BusyIndicator {
                visible: lr.busy
                running: lr.busy
                width: 16
                height: 16
            }
            T11 { text: lr.rightText; visible: text !== ""; anchors.verticalCenter: parent.verticalCenter }
            Glyph {
                visible: lr.locked
                width: 11
                height: 11
                kind: "lock"
                color: root.cSub
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lr.clicked()
        }
    }

    // Detail sheet that replaces the grid when a module is opened.
    component DetailPage: ColumnLayout {
        id: dp
        property string title
        property bool hasSwitch: false
        property bool switchOn: false
        property string settingsText: ""
        signal switchToggled()
        signal settingsClicked()
        default property alias body: dpBody.data
        spacing: 0
        Layout.fillWidth: true

        property real zoom: 1
        transform: Scale {
            origin.x: root.zoomOrigin.x
            origin.y: root.zoomOrigin.y
            xScale: dp.zoom
            yScale: dp.zoom
        }
        onVisibleChanged: if (visible && root.animatePages) dpEnter.restart()
        ParallelAnimation {
            id: dpEnter
            NumberAnimation { target: dp; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
            NumberAnimation { target: dp; property: "zoom"; from: 0.82; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 2
            Layout.rightMargin: 8
            Layout.topMargin: 4
            Layout.bottomMargin: 6
            spacing: 4
            Rectangle {
                implicitWidth: 22
                implicitHeight: 22
                radius: 6
                color: backMa.containsMouse ? root.cRowHover : "transparent"
                Glyph {
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    kind: "chevronLeft"
                    color: root.cSub
                }
                MouseArea {
                    id: backMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openPage("main", null)
                }
            }
            T13 {
                Layout.fillWidth: true
                text: dp.title
                font.pixelSize: 14
                font.weight: Font.Bold
            }
            AppleSwitch {
                visible: dp.hasSwitch
                checked: dp.switchOn
                onToggled: dp.switchToggled()
            }
        }
        Sep { Layout.topMargin: 0 }
        ColumnLayout {
            id: dpBody
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 1
        }
        Sep { visible: dp.settingsText !== "" }
        ListRow {
            visible: dp.settingsText !== ""
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.bottomMargin: 2
            showCircle: false
            text: dp.settingsText
            onClicked: dp.settingsClicked()
        }
    }

    // Wide module with title + slider (Display, Sound, Keyboard Brightness).
    component SliderModule: Tile {
        id: sm
        property string title
        property string glyph
        property real value
        property bool muted: false
        property bool openable: true
        signal moved(real v)
        signal open()
        T13 {
            id: smTitle
            x: 14
            y: 11
            width: parent.width - 28
            text: sm.title
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                enabled: sm.openable
                cursorShape: Qt.PointingHandCursor
                onPressedChanged: sm.down = pressed
                onClicked: sm.open()
            }
        }
        Glyph {
            visible: sm.openable
            opacity: sm.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 13
            width: 10
            height: 10
            kind: "chevronRight"
            color: root.cSub
        }
        CCSlider {
            x: 12
            y: parent.height - height - 12
            width: parent.width - 24
            height: 24
            dark: root.dark
            glyph: sm.glyph
            value: sm.value
            muted: sm.muted
            onMoved: v => sm.moved(v)
        }
    }

    // ================================================================ menu bar icon
    compactRepresentation: MouseArea {
        id: compact
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        Layout.minimumWidth: vertical ? -1 : Math.round(Kirigami.Units.iconSizes.small * 2)
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: vertical ? Math.round(Kirigami.Units.iconSizes.small * 1.6) : -1
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        property bool wasExpanded: false
        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded

        readonly property string scrName: Screen.name
        readonly property string scrModel: Screen.model
        onScrNameChanged: root.screenName = scrName
        onScrModelChanged: root.screenModel = scrModel
        Component.onCompleted: { root.screenName = scrName; root.screenModel = scrModel; }

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
            kind: "cc"
            color: Kirigami.Theme.textColor
        }
    }

    // ================================================================ popup
    fullRepresentation: Item {
        id: full
        Layout.minimumWidth: root.popupWidth
        Layout.maximumWidth: root.popupWidth
        Layout.preferredWidth: root.popupWidth
        Layout.minimumHeight: pages.implicitHeight
        Layout.maximumHeight: pages.implicitHeight
        Layout.preferredHeight: pages.implicitHeight
        focus: true
        Keys.onEscapePressed: event => {
            if (root.page !== "main") { root.openPage("main", null); event.accepted = true; }
            else event.accepted = false;
        }

        ColumnLayout {
            id: pages
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 0

            // ------------------------------------------------ main grid
            Item {
                id: grid
                visible: root.page === "main"
                Layout.fillWidth: true
                implicitHeight: (root.hasBattery || root.kbdAvailable ? 6 : 5) * root.unit - root.gap

                // Returning from a detail view: the grid settles back in around the module.
                property real zoom: 1
                transform: Scale {
                    origin.x: root.zoomOrigin.x
                    origin.y: root.zoomOrigin.y
                    xScale: grid.zoom
                    yScale: grid.zoom
                }
                onVisibleChanged: if (visible && root.animatePages) gridEnter.restart()
                ParallelAnimation {
                    id: gridEnter
                    NumberAnimation { target: grid; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
                    NumberAnimation { target: grid; property: "zoom"; from: 1.08; to: 1; duration: 320; easing.type: Easing.OutCubic }
                }

                // Connectivity 2x2: Wi-Fi, Bluetooth, VPN
                Tile {
                    col: 0; row: 0; cols: 2; rows: 2
                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 8
                        anchors.topMargin: 10
                        spacing: 9
                        ModuleRow {
                            width: parent.width
                            glyph: "wifi"
                            on: root.wifiOn
                            title: "Wi‑Fi"
                            subtitle: !root.wifiOn ? "Off" : (root.wifiName || "Not Connected")
                            onToggle: root.toggleWifi()
                            onOpen: root.openPage("wifi", mapToItem(pages, width / 2, height / 2))
                        }
                        ModuleRow {
                            width: parent.width
                            glyph: "bluetooth"
                            on: root.btOn
                            title: "Bluetooth"
                            subtitle: !root.btAvailable ? "Unavailable" : root.btOn ? "On" : "Off"
                            onToggle: root.toggleBt()
                            onOpen: root.openPage("bluetooth", mapToItem(pages, width / 2, height / 2))
                        }
                        ModuleRow {
                            width: parent.width
                            visible: root.vpnCount > 0
                            glyph: "lock"
                            on: root.vpnActive > 0
                            title: "VPN"
                            subtitle: root.vpnActive > 0 ? "Connected" : "Not Connected"
                            onToggle: { if (root.vpnActive > 0) root.vpnAllOff(); else root.openPage("vpn", mapToItem(pages, width / 2, height / 2)); }
                            onOpen: root.openPage("vpn", mapToItem(pages, width / 2, height / 2))
                        }
                    }
                }

                // Focus 2x1
                Tile {
                    col: 2; row: 0; cols: 2; rows: 1
                    ModuleRow {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 11
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "moon"
                        on: root.dndOn
                        onColor: root.cFocus
                        title: root.dndOn ? "Do Not Disturb" : "Focus"
                        subtitle: root.dndOn && !root.dndIndefinite ? root.dndSubtitle() : ""
                        onToggle: root.toggleDnd()
                        onOpen: root.openPage("focus", mapToItem(pages, width / 2, height / 2))
                    }
                }

                // Overview (Stage Manager slot) 1x1
                Tile {
                    id: ovTile
                    col: 2; row: 1
                    hoverable: true
                    Glyph {
                        anchors.centerIn: parent
                        width: 22; height: 22
                        kind: "grid"
                        color: root.cText
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressedChanged: parent.down = pressed
                        onClicked: {
                            root.expanded = false;
                            root.run("sleep 0.15; qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut Overview");
                        }
                    }
                    PlasmaComponents.ToolTip { text: "Overview (Stage Manager)"; visible: ovTile.hovered && root.page === "main" && root.expanded }
                }

                // Screen Mirroring 1x1 -> KScreen display mode selector
                Tile {
                    id: mirTile
                    col: 3; row: 1
                    hoverable: true
                    Glyph {
                        anchors.centerIn: parent
                        width: 22; height: 22
                        kind: "mirror"
                        color: root.cText
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressedChanged: parent.down = pressed
                        onClicked: {
                            root.expanded = false;
                            root.run("qdbus6 org.kde.kscreen.osdService /org/kde/kscreen/osdService org.kde.kscreen.osdService.showActionSelector");
                        }
                    }
                    PlasmaComponents.ToolTip { text: "Screen Mirroring (display arrangement)"; visible: mirTile.hovered && root.page === "main" && root.expanded }
                }

                // Display 4x1
                SliderModule {
                    col: 0; row: 2; cols: 4
                    title: "Display"
                    glyph: "sun"
                    value: root.briFrac(root.myDisplay)
                    onMoved: v => root.setBrightness(root.myDisplay, v)
                    onOpen: root.openPage("display", mapToItem(pages, width / 2, height / 2))
                }

                // Sound 4x1
                SliderModule {
                    col: 0; row: 3; cols: 4
                    title: "Sound"
                    glyph: root.headphones ? "headphones" : "speaker"
                    value: root.sinkMuted ? 0 : root.volFrac
                    muted: root.sinkMuted
                    onMoved: v => root.setVolume(v)
                    onOpen: root.openPage("sound", mapToItem(pages, width / 2, height / 2))
                }

                // Now Playing 4x1
                Tile {
                    id: npTile
                    col: 0; row: 4; cols: 4
                    Rectangle {
                        id: art
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 46
                        height: 46
                        radius: 9
                        color: root.cCircleOff
                        clip: true
                        Glyph {
                            anchors.centerIn: parent
                            width: 22; height: 22
                            kind: "note"
                            color: root.cSub
                            visible: artImg.status !== Image.Ready
                        }
                        Image {
                            id: artImg
                            anchors.fill: parent
                            source: root.player ? root.player.artUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 128
                            sourceSize.height: 128
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                    }
                    Column {
                        id: npText
                        anchors.left: art.right
                        anchors.leftMargin: 10
                        anchors.right: npControls.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        T13 {
                            width: parent.width
                            text: root.player && root.player.track ? root.player.track : (root.player ? root.player.identity : "Not Playing")
                        }
                        T11 {
                            width: parent.width
                            text: root.player ? (root.player.artist || root.player.identity || "") : ""
                            visible: text !== ""
                        }
                    }
                    MouseArea {
                        anchors.left: art.left
                        anchors.right: npText.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        enabled: !!root.player && root.player.canRaise
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: { root.player.Raise(); root.expanded = false; }
                    }
                    Row {
                        id: npControls
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Repeater {
                            model: [
                                { k: "prev", s: 16, en: root.player && root.player.canGoPrevious, act: () => root.player.Previous() },
                                { k: root.playing ? "pause" : "play", s: 20, en: root.player && (root.player.canPlay || root.player.canPause), act: () => root.player.PlayPause() },
                                { k: "next", s: 16, en: root.player && root.player.canGoNext, act: () => root.player.Next() }
                            ]
                            Rectangle {
                                width: 30; height: 30; radius: 15
                                color: btnMa.containsMouse && modelData.en ? root.cRowHover : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                scale: btnMa.pressed ? 0.85 : 1
                                Behavior on scale { SpringAnimation { spring: 6; damping: 0.32; epsilon: 0.002 } }
                                Glyph {
                                    anchors.centerIn: parent
                                    width: modelData.s; height: modelData.s
                                    kind: modelData.k
                                    color: modelData.en ? root.cText : root.cSub
                                    opacity: modelData.en ? 1 : 0.5
                                }
                                MouseArea {
                                    id: btnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !!modelData.en
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.act()
                                }
                            }
                        }
                    }
                }

                // Keyboard Brightness 1x1
                Tile {
                    id: kbdTile
                    visible: root.kbdAvailable
                    col: 0; row: 5
                    hoverable: true
                    Glyph {
                        anchors.centerIn: parent
                        width: 24; height: 24
                        kind: "kbd"
                        color: root.cText
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressedChanged: parent.down = pressed
                        onClicked: root.openPage("keyboard", parent.mapToItem(pages, parent.width / 2, parent.height / 2))
                    }
                    PlasmaComponents.ToolTip { text: "Keyboard Brightness"; visible: kbdTile.hovered && root.page === "main" && root.expanded }
                }

                // Dark Mode 1x1
                Tile {
                    id: dmTile
                    col: root.kbdAvailable ? 1 : 0; row: 5
                    visible: root.hasBattery || root.kbdAvailable
                    hoverable: true
                    Circle {
                        anchors.centerIn: parent
                        width: 36
                        glyph: "darkmode"
                        on: root.darkModeOn
                        onClicked: BC.DarkModeControl.darkMode = !BC.DarkModeControl.darkMode
                    }
                    PlasmaComponents.ToolTip { text: "Dark Mode"; visible: dmTile.hovered && root.page === "main" && root.expanded }
                }

                // Battery 2x1
                Tile {
                    visible: root.hasBattery
                    col: 2; row: 5; cols: 2
                    hoverable: true
                    Item {
                        id: batIcon
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 15
                        Rectangle {
                            width: 27; height: 14
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 4
                            color: "transparent"
                            border.width: 1.2
                            border.color: Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.45)
                            Rectangle {
                                x: 2; y: 2
                                height: parent.height - 4
                                width: Math.max(2, (parent.width - 4) * batt.percent / 100)
                                radius: 2.2
                                color: batt.state === Bat.BatteryControlModel.Charging ? root.cGreen
                                     : batt.percent <= 20 ? "#ff453a" : root.cText
                            }
                        }
                        Rectangle {
                            x: 28; width: 2; height: 5; radius: 1
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.45)
                        }
                    }
                    Column {
                        anchors.left: batIcon.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        T13 { width: parent.width; text: batt.percent + "%" }
                        T11 {
                            width: parent.width
                            text: batt.state === Bat.BatteryControlModel.Charging ? "Charging"
                                : batt.pluggedIn ? (batt.chargeStopThreshold > 0 && batt.chargeStopThreshold < 100 ? "Limit " + batt.chargeStopThreshold + "%" : "Power Adapter")
                                : root.profileName(ppc.activeProfile)
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressedChanged: parent.down = pressed
                        onClicked: root.openPage("battery", parent.mapToItem(pages, parent.width / 2, parent.height / 2))
                    }
                }
            }

            // ------------------------------------------------ Wi-Fi
            DetailPage {
                visible: root.page === "wifi"
                title: "Wi‑Fi"
                hasSwitch: true
                switchOn: root.wifiOn
                onSwitchToggled: root.toggleWifi()
                settingsText: "Wi‑Fi Settings…"
                onSettingsClicked: root.openSettings("kcm_networkmanagement")

                SectionLabel { text: "Known Network"; visible: root.wifiOn }
                Repeater {
                    model: root.wifiOn && root.page === "wifi" ? nmProxy : null
                    delegate: ListRow {
                        visible: model.Type === PlasmaNM.Enums.Wireless && (model.Uuid || "") !== ""
                        glyph: "wifi"
                        strength: (model.Signal || 0) / 100
                        active: model.ConnectionState === PlasmaNM.Enums.Activated
                        busy: model.ConnectionState === PlasmaNM.Enums.Activating
                        text: model.Name
                        locked: model.SecurityType > PlasmaNM.Enums.NoneSecurity
                        onClicked: {
                            if (model.ConnectionState === PlasmaNM.Enums.Activated) nmHandler.deactivateConnection(model.ConnectionPath, model.DevicePath);
                            else nmHandler.activateConnection(model.ConnectionPath, model.DevicePath, model.SpecificPath);
                        }
                    }
                }
                SectionLabel { text: "Other Networks"; visible: root.wifiOn }
                Flickable {
                    visible: root.wifiOn
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(otherCol.implicitHeight, 216)
                    contentHeight: otherCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: otherCol
                        width: parent.width
                        spacing: 1
                        Repeater {
                            model: root.wifiOn && root.page === "wifi" ? nmProxy : null
                            delegate: ColumnLayout {
                                id: otherDel
                                visible: model.Type === PlasmaNM.Enums.Wireless && (model.Uuid || "") === ""
                                Layout.fillWidth: true
                                spacing: 2
                                readonly property bool asking: root.wifiPasswordFor === model.ItemUniqueName
                                ListRow {
                                    glyph: "wifi"
                                    strength: (model.Signal || 0) / 100
                                    active: false
                                    busy: model.ConnectionState === PlasmaNM.Enums.Activating
                                    text: model.Name
                                    locked: model.SecurityType > PlasmaNM.Enums.NoneSecurity
                                    onClicked: {
                                        if (model.SecurityType <= PlasmaNM.Enums.NoneSecurity) nmHandler.addAndActivateConnection(model.DevicePath, model.SpecificPath, "");
                                        else root.wifiPasswordFor = otherDel.asking ? "" : model.ItemUniqueName;
                                    }
                                }
                                PlasmaComponents.TextField {
                                    visible: otherDel.asking
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 40
                                    Layout.rightMargin: 8
                                    Layout.bottomMargin: 4
                                    echoMode: TextInput.Password
                                    placeholderText: "Password"
                                    onVisibleChanged: if (visible) forceActiveFocus()
                                    onAccepted: {
                                        nmHandler.addAndActivateConnection(model.DevicePath, model.SpecificPath, text);
                                        root.wifiPasswordFor = "";
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------ Bluetooth
            DetailPage {
                visible: root.page === "bluetooth"
                title: "Bluetooth"
                hasSwitch: root.btAvailable
                switchOn: root.btOn
                onSwitchToggled: root.toggleBt()
                settingsText: "Bluetooth Settings…"
                onSettingsClicked: root.openSettings("kcm_bluetooth")

                SectionLabel { text: "Devices"; visible: root.btOn }
                Repeater {
                    model: root.btOn ? btDevices : null
                    delegate: ListRow {
                        readonly property var dev: model.Device
                        visible: model.Paired === true
                        glyph: root.btGlyph(model.Icon || "")
                        active: model.Connected === true
                        text: model.Name || ""
                        rightText: dev && dev.battery ? dev.battery.percentage + "%" : ""
                        onClicked: {
                            if (!dev) return;
                            if (dev.connected) dev.disconnectFromDevice(); else dev.connectToDevice();
                        }
                    }
                }
                T11 {
                    visible: !root.btOn
                    Layout.fillWidth: true
                    Layout.margins: 10
                    text: root.btAvailable ? "Bluetooth is off." : "No Bluetooth adapter."
                }
            }

            // ------------------------------------------------ VPN
            DetailPage {
                visible: root.page === "vpn"
                title: "VPN"
                settingsText: "VPN Settings…"
                onSettingsClicked: root.openSettings("kcm_networkmanagement")
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(vpnCol.implicitHeight, 300)
                    contentHeight: vpnCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: vpnCol
                        width: parent.width
                        spacing: 1
                        Repeater {
                            model: root.page === "vpn" ? nmProxy : null
                            delegate: ListRow {
                                visible: root.isVpnType(model.Type) && (model.Uuid || "") !== ""
                                glyph: "lock"
                                active: model.ConnectionState === PlasmaNM.Enums.Activated
                                busy: model.ConnectionState === PlasmaNM.Enums.Activating
                                text: model.Name
                                detail: active ? "Connected" : ""
                                onClicked: {
                                    if (model.ConnectionState === PlasmaNM.Enums.Activated) nmHandler.deactivateConnection(model.ConnectionPath, model.DevicePath);
                                    else nmHandler.activateConnection(model.ConnectionPath, model.DevicePath, model.SpecificPath);
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------ Focus
            DetailPage {
                visible: root.page === "focus"
                title: "Focus"
                settingsText: "Focus Settings…"
                onSettingsClicked: root.openSettings("kcm_notifications")
                ListRow {
                    glyph: "moon"
                    active: root.dndOn
                    text: "Do Not Disturb"
                    detail: root.dndSubtitle()
                    onClicked: root.toggleDnd()
                }
                ListRow {
                    showCircle: false
                    text: "For 1 hour"
                    onClicked: root.setDnd(new Date(Date.now() + 3600 * 1000))
                }
                ListRow {
                    showCircle: false
                    text: "Until this evening"
                    visible: new Date().getHours() < 19
                    onClicked: { const d = new Date(); d.setHours(19, 0, 0, 0); root.setDnd(d); }
                }
                ListRow {
                    showCircle: false
                    text: "Until tomorrow morning"
                    onClicked: { const d = new Date(); d.setDate(d.getDate() + 1); d.setHours(8, 0, 0, 0); root.setDnd(d); }
                }
            }

            // ------------------------------------------------ Display
            DetailPage {
                visible: root.page === "display"
                title: "Display"
                settingsText: "Displays Settings…"
                onSettingsClicked: root.openSettings("kcm_kscreen")

                Repeater {
                    model: root.displayList
                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        Layout.bottomMargin: 6
                        spacing: 5
                        T11 {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            text: modelData.internal ? "Built-in Display" : modelData.label
                            font.weight: Font.DemiBold
                        }
                        CCSlider {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            dark: root.dark
                            glyph: "sun"
                            value: root.briFrac(modelData)
                            onMoved: v => root.setBrightness(modelData, v)
                        }
                    }
                }
                Sep {}
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    spacing: 30
                    Repeater {
                        model: [
                            { g: "darkmode", t: "Dark Mode", on: root.darkModeOn, act: () => { BC.DarkModeControl.darkMode = !BC.DarkModeControl.darkMode; } },
                            { g: "nightshift", t: "Night Shift", on: root.nightOn, act: () => root.toggleNightLight() }
                        ]
                        Column {
                            spacing: 5
                            Circle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 36
                                glyph: modelData.g
                                on: modelData.on
                                onClicked: modelData.act()
                            }
                            T11 {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.t
                                color: root.cText
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------ Sound
            DetailPage {
                visible: root.page === "sound"
                title: "Sound"
                settingsText: "Sound Settings…"
                onSettingsClicked: root.openSettings("kcm_pulseaudio")
                CCSlider {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    Layout.topMargin: 4
                    Layout.bottomMargin: 6
                    Layout.preferredHeight: 24
                    dark: root.dark
                    glyph: root.headphones ? "headphones" : "speaker"
                    value: root.sinkMuted ? 0 : root.volFrac
                    muted: root.sinkMuted
                    onMoved: v => root.setVolume(v)
                }
                SectionLabel { text: "Output" }
                Repeater {
                    model: sinkModel
                    delegate: ListRow {
                        readonly property var po: model.PulseObject
                        visible: model.Name !== "auto_null" && !root.unplugged(po)
                        glyph: {
                            const t = ((model.Name || "") + " " + (model.Description || "")).toLowerCase();
                            const f = (po && po.formFactor || "").toLowerCase();
                            if (["headphone", "headset", "hands-free", "handset"].indexOf(f) >= 0 || t.includes("headphone") || t.includes("headset")) return "headphones";
                            return t.includes("hdmi") ? "display" : "speaker";
                        }
                        active: model.Default === true
                        text: model.Description || model.Name
                        onClicked: if (po) po.default = true
                    }
                }
            }

            // ------------------------------------------------ Keyboard Brightness
            DetailPage {
                visible: root.page === "keyboard"
                title: "Keyboard Brightness"
                settingsText: "Keyboard Settings…"
                onSettingsClicked: root.openSettings("kcm_keyboard")
                CCSlider {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    Layout.topMargin: 6
                    Layout.bottomMargin: 8
                    Layout.preferredHeight: 24
                    dark: root.dark
                    glyph: "kbd"
                    value: root.kbdAvailable ? kbc.brightness / kbc.brightnessMax : 0
                    onMoved: v => kbc.brightness = Math.round(v * kbc.brightnessMax)
                }
            }

            // ------------------------------------------------ Battery
            DetailPage {
                visible: root.page === "battery"
                title: "Battery"
                settingsText: "Battery Settings…"
                onSettingsClicked: root.openSettings("kcm_powerdevilprofilesconfig")
                ListRow {
                    showCircle: false
                    text: "Power Source: " + (batt.pluggedIn ? "Power Adapter" : "Battery")
                    rightText: batt.percent + "%"
                }
                ListRow {
                    showCircle: false
                    visible: batt.pluggedIn && batt.chargeStopThreshold > 0 && batt.chargeStopThreshold < 100
                    text: "Charging limited to " + batt.chargeStopThreshold + "%"
                }
                ListRow {
                    showCircle: false
                    visible: !batt.pluggedIn && batt.remainingMsec > 0
                    text: root.fmtRemaining(batt.remainingMsec) + " remaining"
                }
                Sep { visible: ppc.profiles.length > 0 }
                SectionLabel { text: "Energy Mode"; visible: ppc.profiles.length > 0 }
                Repeater {
                    model: ppc.profiles
                    delegate: ListRow {
                        glyph: modelData === "power-saver" ? "leaf" : modelData === "performance" ? "bolt" : "gauge"
                        active: ppc.activeProfile === modelData
                        text: root.profileName(modelData)
                        onClicked: ppc.setProfile(modelData)
                    }
                }
            }
        }
    }
}
