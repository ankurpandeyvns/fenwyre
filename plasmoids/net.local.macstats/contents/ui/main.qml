import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// Stats/iStat-style menu bar: compact CPU/MEM graphs, network, temp + power.
// Clicking a module opens a Stats-like dropdown on that module's tab.
// Data: ~/.local/bin/mac-stats-detail (one JSON snapshot, shared between panel instances).
PlasmoidItem {
    id: root

    readonly property int sparkLength: 30
    readonly property int historyLength: 90      // 3 minutes at 2 s
    readonly property int intervalMs: 2000
    readonly property string cmd: "/home/ankur/.local/bin/mac-stats-detail"

    readonly property color cUser: "#0a84ff"
    readonly property color cSys: "#ff453a"
    readonly property color cMem: "#30d158"
    readonly property color cWired: "#ff9f0a"
    readonly property color cComp: "#bf5af2"
    readonly property color cShm: "#64d2ff"
    readonly property color cUp: "#ff453a"
    readonly property color cDown: "#0a84ff"
    readonly property color cGpu: "#ffd60a"

    property var d: null
    property real cpu: d ? d.cpu.total : 0
    property real mem: d ? d.mem.percent : 0
    property string temp: d && d.sensors.cpuTemp !== null ? d.sensors.cpuTemp.toFixed(0) : "–"
    property string power: d && d.sensors.power !== null ? d.sensors.power.toFixed(1) : "–"
    readonly property var g: d ? d.gpu : null
    property real gpu: g ? g.util : 0
    property real rxRate: d ? d.net.rx : 0
    property real txRate: d ? d.net.tx : 0

    property var hUser: []
    property var hSys: []
    property var hMem: []
    property var hRx: []
    property var hTx: []
    property var hTemp: []
    property var hPower: []
    property var hGpu: []
    property var hGpuPower: []

    property int page: 0

    preferredRepresentation: compactRepresentation
    toolTipMainText: "System"
    toolTipSubText: "CPU " + cpu.toFixed(0) + "%   GPU " + gpu.toFixed(0) + "%   Memory " + mem.toFixed(0) + "%   ↓ " + fmtRate(rxRate) + "  ↑ " + fmtRate(txRate)

    function push(arr, v) {
        const a = arr.slice();
        a.push(v);
        while (a.length > historyLength) a.shift();
        return a;
    }
    function tail(arr, n) { return arr.length > n ? arr.slice(arr.length - n) : arr; }

    // Network speeds in megabits per second (input is bytes/s).
    function mbps(Bps) {
        const v = Bps * 8 / 1e6;
        return v >= 100 ? v.toFixed(0) : v >= 10 ? v.toFixed(1) : v.toFixed(2);
    }
    function fmtRate(Bps) { return mbps(Bps) + " Mbps"; }
    function shortRate(Bps) { return mbps(Bps); }
    function fmtBytes(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(b >= 10737418240 ? 1 : 2) + " GB";
        if (b >= 1048576) return (b / 1048576).toFixed(0) + " MB";
        if (b >= 1024) return (b / 1024).toFixed(0) + " KB";
        return b.toFixed(0) + " B";
    }
    function open(p) {
        if (root.expanded && root.page === p) { root.expanded = false; return; }
        root.page = p;
        root.expanded = true;
    }

    P5Support.DataSource {
        id: exe
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            try {
                const j = JSON.parse((data["stdout"] || "").trim());
                root.d = j;
                root.hUser = root.push(root.hUser, j.cpu.user);
                root.hSys = root.push(root.hSys, j.cpu.system);
                root.hMem = root.push(root.hMem, j.mem.percent);
                root.hRx = root.push(root.hRx, j.net.rx);
                root.hTx = root.push(root.hTx, j.net.tx);
                if (j.sensors.cpuTemp !== null) root.hTemp = root.push(root.hTemp, j.sensors.cpuTemp);
                if (j.gpu) { root.hGpu = root.push(root.hGpu, j.gpu.util); root.hGpuPower = root.push(root.hGpuPower, j.gpu.power); }
                if (j.sensors.power !== null) root.hPower = root.push(root.hPower, j.sensors.power);
            } catch (e) {}
            disconnectSource(source);
        }
    }

    Timer {
        interval: root.intervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exe.connectSource(root.cmd)
    }

    // ---------- shared pieces ----------

    // Stacked area graph, fixed 0..max scale (CPU user+system, memory).
    component AreaGraph: Canvas {
        id: ag
        property var series: []        // [[values...], ...] stacked bottom-up
        property var colors: []
        property real maxValue: 100
        property int length: root.historyLength
        property bool grid: true
        onSeriesChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (grid) {
                ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08);
                ctx.lineWidth = 1;
                for (let g = 1; g < 4; g++) {
                    const gy = Math.round(height * g / 4) + 0.5;
                    ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke();
                }
            }
            if (!series.length) return;
            const n = series[0].length;
            if (n < 2) return;
            const step = width / (length - 1);
            const x0 = width - (n - 1) * step;
            const base = new Array(n).fill(0);
            const Y = v => height - (Math.min(maxValue, Math.max(0, v)) / maxValue) * (height - 1);
            for (let s = 0; s < series.length; s++) {
                const vals = series[s];
                const top = base.map((b, i) => b + (vals[i] || 0));
                const c = colors[s];
                ctx.beginPath();
                ctx.moveTo(x0, Y(base[0]));
                for (let i = 0; i < n; i++) ctx.lineTo(x0 + i * step, Y(top[i]));
                for (let i = n - 1; i >= 0; i--) ctx.lineTo(x0 + i * step, Y(base[i]));
                ctx.closePath();
                ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.35);
                ctx.fill();
                ctx.beginPath();
                for (let i = 0; i < n; i++) {
                    if (i === 0) ctx.moveTo(x0, Y(top[0])); else ctx.lineTo(x0 + i * step, Y(top[i]));
                }
                ctx.strokeStyle = c;
                ctx.lineWidth = 1.2;
                ctx.stroke();
                for (let i = 0; i < n; i++) base[i] = top[i];
            }
        }
    }

    // Upload above the midline, download below (Stats network chart), auto-scaled.
    component NetGraph: Canvas {
        property var up: []
        property var down: []
        property real scaleMax: Math.max(10240, Math.max.apply(null, up.concat(down).concat([0])))
        onUpChanged: requestPaint()
        onDownChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const mid = Math.round(height / 2) + 0.5;
            ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15);
            ctx.lineWidth = 1;
            ctx.beginPath(); ctx.moveTo(0, mid); ctx.lineTo(width, mid); ctx.stroke();
            const step = width / (root.historyLength - 1);
            const draw = (vals, c, dir) => {
                const n = vals.length;
                if (n < 2) return;
                const x0 = width - (n - 1) * step;
                const Y = v => mid + dir * (Math.min(1, v / scaleMax) * (height / 2 - 1));
                ctx.beginPath();
                ctx.moveTo(x0, mid);
                for (let i = 0; i < n; i++) ctx.lineTo(x0 + i * step, Y(vals[i]));
                ctx.lineTo(width, mid);
                ctx.closePath();
                ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.35);
                ctx.fill();
                ctx.beginPath();
                for (let i = 0; i < n; i++) { if (i === 0) ctx.moveTo(x0, Y(vals[0])); else ctx.lineTo(x0 + i * step, Y(vals[i])); }
                ctx.strokeStyle = c;
                ctx.lineWidth = 1.2;
                ctx.stroke();
            };
            draw(up, root.cUp, -1);
            draw(down, root.cDown, 1);
        }
    }

    // Donut for the memory composition.
    component Donut: Canvas {
        property var parts: []      // [[value, color], ...]
        property real total: 1
        property string label: ""
        onPartsChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const r = Math.min(width, height) / 2 - 4, cx = width / 2, cy = height / 2;
            ctx.lineWidth = 7;
            ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1);
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.stroke();
            let a = -Math.PI / 2;
            for (let i = 0; i < parts.length; i++) {
                const sweep = 2 * Math.PI * Math.max(0, parts[i][0]) / total;
                ctx.strokeStyle = parts[i][1];
                ctx.beginPath(); ctx.arc(cx, cy, r, a, a + sweep); ctx.stroke();
                a += sweep;
            }
        }
        PlasmaComponents.Label {
            anchors.centerIn: parent
            text: parent.label
            font.family: "SF Pro Text"
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }

    component Section: PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing * 2
        font.family: "SF Pro Text"
        font.weight: Font.DemiBold
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        opacity: 0.55
    }

    component Row2: RowLayout {
        property string k
        property string v
        property color dot: "transparent"
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Rectangle { visible: dot.a > 0; width: 8; height: 8; radius: 4; color: dot }
        PlasmaComponents.Label { text: k; Layout.fillWidth: true; elide: Text.ElideRight; font.family: "SF Pro Text" }
        PlasmaComponents.Label { text: v; font.family: "SF Pro Text"; font.features: { "tnum": 1 }; opacity: 0.85 }
    }

    // Top-process row: app icon + app name + value (Stats style). modelData = [name, icon, value]
    component ProcRow: RowLayout {
        property string name
        property string icon
        property string v
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Kirigami.Icon {
            source: icon.startsWith("/") ? "file://" + icon : icon
            fallback: "application-x-executable"
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
        PlasmaComponents.Label { text: name; Layout.fillWidth: true; elide: Text.ElideRight; font.family: "SF Pro Text" }
        PlasmaComponents.Label { text: v; font.family: "SF Pro Text"; font.features: { "tnum": 1 }; opacity: 0.85 }
    }

    component Frame: Rectangle {
        Layout.fillWidth: true
        radius: 6
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
    }

    component Big: PlasmaComponents.Label {
        font.family: "SF Pro Display"
        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.9
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }

    // ---------- compact (menu bar) ----------

    component Spark: Canvas {
        property var values: []
        property color lineColor: Kirigami.Theme.highlightColor
        onValuesChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const n = values.length;
            if (n < 2) return;
            const step = width / (root.sparkLength - 1);
            const x0 = width - (n - 1) * step;
            const y = v => height - 1 - (Math.min(100, Math.max(0, v)) / 100) * (height - 2);
            ctx.beginPath();
            ctx.moveTo(x0, height);
            for (let i = 0; i < n; i++) ctx.lineTo(x0 + i * step, y(values[i]));
            ctx.lineTo(width, height);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.35);
            ctx.fill();
            ctx.beginPath();
            for (let i = 0; i < n; i++) { if (i === 0) ctx.moveTo(x0, y(values[0])); else ctx.lineTo(x0 + i * step, y(values[i])); }
            ctx.strokeStyle = lineColor;
            ctx.lineWidth = 1.2;
            ctx.stroke();
        }
    }

    component Tiny: PlasmaComponents.Label {
        font.family: "SF Pro Text"
        font.pixelSize: Math.max(8, Math.round(Kirigami.Theme.smallFont.pixelSize * 0.85))
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
        lineHeight: 0.9
    }

    compactRepresentation: MouseArea {
        id: compact
        // Pick the tab from the module under the cursor (nearest module when clicking a gap).
        onClicked: mouse => {
            const p = mapToItem(row, mouse.x, mouse.y);
            let best = 0, bestDist = 1e9;
            for (let i = 0; i < row.children.length; i++) {
                const c = row.children[i];
                if (c.page === undefined) continue;
                const dist = p.x < c.x ? c.x - p.x : p.x > c.x + c.width ? p.x - c.x - c.width : 0;
                if (dist < bestDist) { bestDist = dist; best = c.page; }
            }
            root.open(best);
        }
        // Hidden Bar-style chevron: collapses the stats so narrow screens keep room for the
        // app menu and the clock. "auto" = collapsed when this screen is narrower than 1200 px.
        readonly property bool collapsed: {
            const c = Plasmoid.configuration.collapse;
            if (c === "hidden") return true;
            if (c === "shown") return false;
            return Screen.width > 0 && Screen.width < 1200;
        }
        Layout.minimumWidth: chevron.width + (collapsed ? 0 : row.implicitWidth + Kirigami.Units.smallSpacing)
                             + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth

        PlasmaComponents.Label {
            id: chevron
            anchors.left: parent.left
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.verticalCenter: parent.verticalCenter
            text: compact.collapsed ? "\u2039" : "\u203A"      // ‹ show / › hide
            font.pixelSize: Math.round(compact.height * 0.62)
            font.weight: Font.DemiBold
            opacity: chevronArea.containsMouse ? 1.0 : 0.7
            MouseArea {
                id: chevronArea
                anchors.fill: parent
                anchors.margins: -Kirigami.Units.smallSpacing
                hoverEnabled: true
                onClicked: Plasmoid.configuration.collapse = compact.collapsed ? "shown" : "hidden"
            }
        }

        RowLayout {
            id: row
            visible: !compact.collapsed
            anchors.left: chevron.right
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)

            RowLayout {
                property int page: 0
                spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)
                ColumnLayout {
                    spacing: 0
                    Tiny { text: "CPU"; opacity: 0.6 }
                    Tiny { text: root.cpu.toFixed(0) + "%" }
                }
                Spark {
                    values: root.tail(root.hUser.map((u, i) => u + (root.hSys[i] || 0)), root.sparkLength)
                    lineColor: root.cUser
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.1
                    Layout.preferredHeight: compact.height * 0.6
                }
            }
            RowLayout {
                property int page: 1
                spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)
                ColumnLayout {
                    spacing: 0
                    Tiny { text: "MEM"; opacity: 0.6 }
                    Tiny { text: root.mem.toFixed(0) + "%" }
                }
                Spark {
                    values: root.tail(root.hMem, root.sparkLength)
                    lineColor: root.cMem
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.1
                    Layout.preferredHeight: compact.height * 0.6
                }
            }
            RowLayout {
                property int page: 2
                visible: !!root.g
                spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)
                ColumnLayout {
                    spacing: 0
                    Tiny { text: "GPU"; opacity: 0.6 }
                    Tiny { text: root.gpu.toFixed(0) + "%" }
                }
                Spark {
                    values: root.tail(root.hGpu, root.sparkLength)
                    lineColor: root.cGpu
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.1
                    Layout.preferredHeight: compact.height * 0.6
                }
            }
            ColumnLayout {
                property int page: 3
                spacing: 0
                Tiny { text: "↑" + root.shortRate(root.txRate); Layout.minimumWidth: Kirigami.Units.gridUnit * 1.6 }
                Tiny { text: "↓" + root.shortRate(root.rxRate); Layout.minimumWidth: Kirigami.Units.gridUnit * 1.6 }
            }
            ColumnLayout {
                property int page: 4
                spacing: 0
                Tiny { text: root.temp + "°" }
                Tiny { text: root.power + "W" }
            }
        }
    }

    // ---------- dropdown ----------

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: implicitHeight
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.TabBar {
            id: tabs
            Layout.fillWidth: true
            currentIndex: root.page
            PlasmaComponents.TabButton { text: "CPU"; onClicked: root.page = 0 }
            PlasmaComponents.TabButton { text: "Memory"; onClicked: root.page = 1 }
            PlasmaComponents.TabButton { text: "GPU"; onClicked: root.page = 2 }
            PlasmaComponents.TabButton { text: "Network"; onClicked: root.page = 3 }
            PlasmaComponents.TabButton { text: "Sensors"; onClicked: root.page = 4 }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing * 2
            spacing: 0

            // CPU
            ColumnLayout {
                visible: root.page === 0
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    Big { text: root.cpu.toFixed(0) + "%" }
                    Item { Layout.fillWidth: true }
                    ColumnLayout {
                        spacing: 0
                        Row2 { k: "System"; v: root.d ? root.d.cpu.system.toFixed(1) + "%" : "–"; dot: root.cSys }
                        Row2 { k: "User"; v: root.d ? root.d.cpu.user.toFixed(1) + "%" : "–"; dot: root.cUser }
                        Row2 { k: "Idle"; v: (100 - root.cpu).toFixed(1) + "%"; dot: Qt.rgba(0.5, 0.5, 0.5, 0.6) }
                    }
                }
                Frame {
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4.5
                    AreaGraph {
                        anchors.fill: parent; anchors.margins: 1
                        series: [root.hSys, root.hUser]
                        colors: [root.cSys, root.cUser]
                    }
                }
                Section { text: "CORES" }
                Frame {
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.2
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 4
                        spacing: 3
                        Repeater {
                            model: root.d ? root.d.cpu.cores : []
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                Rectangle {
                                    anchors.bottom: parent.bottom; width: parent.width; radius: 2
                                    height: Math.max(2, parent.height * modelData / 100)
                                    color: index < 2 ? root.cComp : root.cUser
                                    Behavior on height { NumberAnimation { duration: 300 } }
                                }
                            }
                        }
                    }
                }
                Row2 { k: "Load average"; v: root.d ? root.d.cpu.load.join("  ") : "–" }
                Section { text: "TOP PROCESSES" }
                Repeater {
                    model: root.d ? root.d.cpu.top : []
                    ProcRow { name: modelData[0]; icon: modelData[1]; v: modelData[2].toFixed(1) + "%" }
                }
            }

            // Memory
            ColumnLayout {
                visible: root.page === 1
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    Donut {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                        total: root.d ? root.d.mem.total : 1
                        label: root.mem.toFixed(0) + "%"
                        parts: root.d ? [[root.d.mem.app, root.cMem], [root.d.mem.wired, root.cWired],
                                         [root.d.mem.shmem, root.cShm], [root.d.mem.compressed, root.cComp]] : []
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Row2 { k: "App"; v: root.d ? root.fmtBytes(root.d.mem.app) : "–"; dot: root.cMem }
                        Row2 { k: "Wired"; v: root.d ? root.fmtBytes(root.d.mem.wired) : "–"; dot: root.cWired }
                        Row2 { k: "Shared / GPU"; v: root.d ? root.fmtBytes(root.d.mem.shmem) : "–"; dot: root.cShm }
                        Row2 { k: "Compressed"; v: root.d ? root.fmtBytes(root.d.mem.compressed) : "–"; dot: root.cComp }
                        Row2 { k: "Cached files"; v: root.d ? root.fmtBytes(root.d.mem.cached) : "–" }
                    }
                }
                Frame {
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                    AreaGraph { anchors.fill: parent; anchors.margins: 1; series: [root.hMem]; colors: [root.cMem] }
                }
                Row2 { k: "Used"; v: root.d ? root.fmtBytes(root.d.mem.used) + " of " + root.fmtBytes(root.d.mem.total) : "–" }
                Row2 { k: "Swap (zram)"; v: root.d ? root.fmtBytes(root.d.mem.swapUsed) + " → " + root.fmtBytes(root.d.mem.compressed) : "–" }
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label { text: "Pressure"; Layout.fillWidth: true; font.family: "SF Pro Text" }
                    Rectangle {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6; height: 6; radius: 3
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                        Rectangle {
                            readonly property real p: root.d ? root.d.mem.pressure : 0
                            width: Math.max(height, parent.width * Math.min(1, p / 40)); height: parent.height; radius: 3
                            color: p < 10 ? root.cMem : p < 25 ? root.cWired : root.cSys
                        }
                    }
                }
                Section { text: "TOP PROCESSES" }
                Repeater {
                    model: root.d ? root.d.mem.top : []
                    ProcRow { name: modelData[0]; icon: modelData[1]; v: root.fmtBytes(modelData[2]) }
                }
            }

            // GPU
            ColumnLayout {
                visible: root.page === 2
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    ColumnLayout {
                        spacing: 0
                        PlasmaComponents.Label { text: "Utilization"; opacity: 0.7; font.family: "SF Pro Text" }
                        Big { text: root.gpu.toFixed(0) + "%" }
                    }
                    Item { Layout.fillWidth: true }
                    ColumnLayout {
                        spacing: 0
                        PlasmaComponents.Label { text: "GPU power"; opacity: 0.7; font.family: "SF Pro Text"; Layout.alignment: Qt.AlignRight }
                        Big { text: (root.g ? root.g.power.toFixed(1) : "–") + " W"; Layout.alignment: Qt.AlignRight }
                    }
                }
                Frame {
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                    AreaGraph { anchors.fill: parent; anchors.margins: 1; series: [root.hGpu]; colors: [root.cGpu] }
                }
                Frame {
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    AreaGraph {
                        anchors.fill: parent; anchors.margins: 1
                        series: [root.hGpuPower]; colors: [root.cComp]
                        maxValue: Math.max(10, Math.max.apply(null, root.hGpuPower.concat([0])) * 1.15)
                    }
                }
                Row2 { k: "Frequency"; v: root.g && root.g.mhz !== null ? root.g.mhz + " MHz" + (root.g.maxMhz ? "  of " + root.g.maxMhz : "") : "–" }
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label { text: "Clock"; Layout.fillWidth: true; font.family: "SF Pro Text" }
                    Rectangle {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6; height: 6; radius: 3
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                        Rectangle {
                            readonly property real f: root.g && root.g.mhz && root.g.maxMhz ? root.g.mhz / root.g.maxMhz : 0
                            width: Math.max(height, parent.width * f); height: parent.height; radius: 3
                            color: root.cGpu
                        }
                    }
                }
                Row2 { k: "Memory in use"; v: root.g ? root.fmtBytes(root.g.mem) : "–"; dot: root.cShm }
                Row2 { k: "Apps"; v: root.g ? root.fmtBytes(root.g.memUser) : "–" }
                Row2 { k: "Driver"; v: root.g ? root.fmtBytes(root.g.memKernel) : "–" }
                Row2 { k: "Jobs per second"; v: root.g ? root.g.jobs.toLocaleString(Qt.locale(), "f", 0) : "–" }
            }

            // Network
            ColumnLayout {
                visible: root.page === 3
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    ColumnLayout {
                        spacing: 0
                        PlasmaComponents.Label { text: "↓ Download"; color: root.cDown; font.family: "SF Pro Text" }
                        Big { text: root.fmtRate(root.rxRate) }
                    }
                    Item { Layout.fillWidth: true }
                    ColumnLayout {
                        spacing: 0
                        PlasmaComponents.Label { text: "↑ Upload"; color: root.cUp; font.family: "SF Pro Text"; Layout.alignment: Qt.AlignRight }
                        Big { text: root.fmtRate(root.txRate); Layout.alignment: Qt.AlignRight }
                    }
                }
                Frame {
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                    NetGraph { id: ng; anchors.fill: parent; anchors.margins: 1; up: root.hTx; down: root.hRx }
                    PlasmaComponents.Label {
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 3
                        text: root.fmtRate(ng.scaleMax); opacity: 0.45
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 0.9
                    }
                }
                Section { text: "TOP PROCESSES" }
                Repeater {
                    model: root.d && root.d.net.top ? root.d.net.top : []
                    ProcRow { name: modelData[0]; icon: modelData[1]; v: "↑ " + root.fmtRate(modelData[2]) + "   ↓ " + root.fmtRate(modelData[3]) }
                }
                PlasmaComponents.Label {
                    visible: !!(root.d && root.d.net.top && root.d.net.top.length === 0)
                    text: root.d && root.d.net.perApp ? "No network activity" : "Per-app data unavailable (nethogs-feed.service)"
                    opacity: 0.55
                    font.family: "SF Pro Text"
                }
                Section { text: "DETAILS" }
                Row2 { k: "Interface"; v: root.d ? (root.d.net.iface || "offline") : "–" }
                Row2 { k: "Local IP"; v: root.d ? (root.d.net.ip || "–") : "–" }
                Row2 { k: "Gateway"; v: root.d ? (root.d.net.gateway || "–") : "–" }
                Row2 { visible: root.d && root.d.net.tailscale; k: "Tailscale"; v: root.d ? root.d.net.tailscale : "" }
                Section { text: "SINCE BOOT" }
                Row2 { k: "Downloaded"; v: root.d ? root.fmtBytes(root.d.net.rxTotal) : "–"; dot: root.cDown }
                Row2 { k: "Uploaded"; v: root.d ? root.fmtBytes(root.d.net.txTotal) : "–"; dot: root.cUp }
            }

            // Sensors
            ColumnLayout {
                visible: root.page === 4
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                RowLayout {
                    ColumnLayout {
                        spacing: 0
                        PlasmaComponents.Label { text: "CPU temperature"; opacity: 0.7; font.family: "SF Pro Text" }
                        Big { text: root.temp + "°C" }
                    }
                    Item { Layout.fillWidth: true }
                    ColumnLayout {
                        spacing: 0
                        PlasmaComponents.Label { text: "System power"; opacity: 0.7; font.family: "SF Pro Text"; Layout.alignment: Qt.AlignRight }
                        Big { text: root.power + " W"; Layout.alignment: Qt.AlignRight }
                    }
                }
                Frame {
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3.5
                    AreaGraph { anchors.fill: parent; anchors.margins: 1; series: [root.hTemp]; colors: [root.cWired]; maxValue: 105 }
                }
                Frame {
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    AreaGraph {
                        anchors.fill: parent; anchors.margins: 1
                        series: [root.hPower]; colors: [root.cComp]
                        maxValue: Math.max(30, Math.max.apply(null, root.hPower.concat([0])) * 1.15)
                    }
                }
                Section { text: "FANS" }
                Repeater {
                    model: root.d ? root.d.sensors.fans : []
                    Row2 { k: modelData[0]; v: modelData[1].toFixed(0) + " rpm" }
                }
                Section { text: "HOTTEST" }
                Repeater {
                    model: root.d ? root.d.sensors.hot : []
                    Row2 { k: modelData[0]; v: modelData[1] + "°" }
                }
                Section { text: "BATTERY"; visible: !!(root.d && root.d.sensors.battery) }
                Row2 {
                    readonly property var b: root.d ? root.d.sensors.battery : null
                    visible: !!b
                    k: b ? b.status : ""
                    v: b ? b.capacity.toFixed(0) + "%" + (b.limit && b.limit < 100 ? "  (limit " + b.limit.toFixed(0) + "%)" : "") : ""
                }
                Row2 {
                    readonly property var b: root.d ? root.d.sensors.battery : null
                    visible: !!b
                    k: "Health"
                    v: b ? (b.health ? b.health.toFixed(0) + "%" : "–") + (b.cycles ? "  ·  " + b.cycles.toFixed(0) + " cycles" : "") : ""
                }
            }
        }
    }
}
