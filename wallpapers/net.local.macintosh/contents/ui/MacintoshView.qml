import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "Machine.js" as M
import "Assets.js" as A

// Renders the Macintosh wallpaper: runs .program scripts, composites the 1-bit
// 512x342 scene (image + animated controls), and draws it as a tilted plane of
// chunky pixels through a fragment shader.
Item {
    id: view

    // ---- configuration (set by main.qml) ----
    property string scene: "Cycle"          // "Cycle" or a program stem
    property string colour: "Spectrum"
    property bool dark: false
    property real speed: 1.0
    property bool paused: false
    property color accent: "#3daee9"
    property real hueOffset: 0              // per-screen spectrum offset

    // ---- state ----
    readonly property url imgBase: Qt.resolvedUrl("../images/")
    readonly property string programDir: decodeURIComponent(Qt.resolvedUrl("../programs").toString().replace(/^file:\/\//, ""))
    property var programs: ({})
    property var programNames: []
    property var bag: []
    property var machine: null
    property string currentProgram: ""
    property string imageName: ""
    property string randomColour: "Blue"
    property string cursorName: ""
    property int cursorX: 0
    property int cursorY: 0
    property int cursorFrame: 0
    property var pendingPaint: []
    property bool clearPaintPending: false
    readonly property bool loaded: programNames.length > 0
    readonly property var pal: A.palette(colour === "Random" ? randomColour : colour, false,
                                         [accent.r * 255, accent.g * 255, accent.b * 255])
    readonly property bool shouldRun: visible && loaded && !paused

    // Program clock: the shader's copy is advanced on the render thread by clockAnim;
    // the interpreter derives the same time from the wall clock.
    property real clockBase: 0
    property double wallBase: 0
    property bool clockRunning: false
    property real fadeOutAt: 1e9
    readonly property real fadeDur: 0.6 * Math.max(0.05, speed)
    property var curveIds: [3, 3, 3, 0, 0]
    property int clockMinute: -1        // minutes since midnight, drives the analog clock faces

    signal frameRendered()

    // ------------------------------------------------------------------ host API for Machine.js
    function hostLog(msg) { console.warn("[net.local.macintosh] " + msg); }
    function hostSetImage(name) { imageName = name; }
    function hostAddControl(item) { controls.append(item); return controls.count - 1; }
    function hostClearControls() { controls.clear(); }
    function hostSetControl(i, props) {
        for (var k in props) controls.setProperty(i, k, props[k]);
    }
    function hostPaint(pts) {
        pendingPaint = pendingPaint.concat(pts);
        paintCanvas.requestPaint();
    }
    function hostClearPaint() {
        pendingPaint = [];
        clearPaintPending = true;
        paintCanvas.requestPaint();
    }
    function hostCursor(name, x, y, frame) {
        cursorName = name; cursorX = x; cursorY = y; cursorFrame = frame;
    }
    function hostProgramDone() {
        if (fadeOutAt < 1e8) return;
        fadeOutAt = now();
        plane.fadeOutStart = fadeOutAt;
    }
    readonly property var curveMap: ({ linear: 0, easein: 1, easeout: 2, easeinout: 3 })
    function hostTween(key, from, to, t0, dur, curve) {
        var v = Qt.vector4d(from, to, t0, dur);
        var c = curveMap[curve] !== undefined ? curveMap[curve] : 0;
        var ids = curveIds.slice();
        switch (key) {
        case "scale": plane.twScale = v; ids[0] = c; break;
        case "roll": plane.twRoll = v; ids[1] = c; break;
        case "tilt": plane.twTilt = v; ids[2] = c; break;
        case "scrollX": plane.twScrollX = v; ids[3] = c; break;
        case "scrollY": plane.twScrollY = v; ids[4] = c; break;
        default: return;
        }
        curveIds = ids;
        plane.curvesA = Qt.vector4d(ids[0], ids[1], ids[2], ids[3]);
        plane.curveScrollY = ids[4];
    }
    function rampVec(name) {
        switch (name) {
        case "Right": return Qt.point(1, 0);
        case "Left": return Qt.point(-1, 0);
        case "Up": return Qt.point(0, -1);
        case "Down": return Qt.point(0, 1);
        }
        return Qt.point(0, 0);
    }
    function hostRamp(name, t) {
        // start a cross-fade from whatever gradient is showing to the new one
        var k = Math.max(0, Math.min(1, (t - plane.rampT0) / 2.5));
        k = k * k * (3 - 2 * k);
        var showingTo = k > 0.5;
        plane.rampFrom = showingTo ? plane.rampTo : plane.rampFrom;
        plane.rampTo = rampVec(name);
        plane.rampT0 = t;
    }

    // ------------------------------------------------------------------ clock
    function now() {
        return clockRunning ? clockBase + speed * (Date.now() - wallBase) / 1000 : clockBase;
    }
    function setClock(t, run) {
        var cur = now();
        var newRate = 1 / (600 * Math.max(0.05, speed));       // one hue turn per 10 minutes
        var hb = plane.hueBase + cur * plane.hueRate - t * newRate;
        plane.hueBase = hb - Math.floor(hb);
        plane.hueRate = newRate;
        clockAnim.stop();
        clockBase = t;
        wallBase = Date.now();
        clockRunning = run;
        plane.clock = t;
        if (run) {
            clockAnim.from = t;
            clockAnim.to = t + 100000 * speed;
            clockAnim.duration = 100000000;
            clockAnim.start();
        }
    }
    onShouldRunChanged: setClock(now(), shouldRun)
    onSpeedChanged: if (loaded) setClock(now(), shouldRun)


    // ------------------------------------------------------------------ program management
    P5Support.DataSource {
        id: reader
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            disconnectSource(source);
            view.ingest(data["stdout"] || "");
        }
    }

    Component.onCompleted: {
        var dir = programDir.replace(/'/g, "'\\''");
        reader.connectSource("cd '" + dir + "' && for f in apple/*.program authored/*.program; do printf '\\n@@MACPROGRAM@@ %s\\n' \"$f\"; cat \"$f\"; done");
    }

    function ingest(out) {
        var parts = out.split("\n@@MACPROGRAM@@ ");
        var progs = {}, names = [];
        for (var i = 1; i < parts.length; ++i) {
            var nl = parts[i].indexOf("\n");
            var path = parts[i].substring(0, nl);
            var stem = path.replace(/^.*\//, "").replace(/\.program$/, "");
            try {
                progs[stem] = M.parse(parts[i].substring(nl + 1), stem);
                names.push(stem);
            } catch (e) {
                hostLog("failed to parse " + path + ": " + e);
            }
        }
        programs = progs;
        programNames = names;
        if (!names.length) hostLog("no programs found in " + programDir);
        startNext();
    }

    function shuffled(list) {
        var a = list.slice();
        for (var i = a.length - 1; i > 0; --i) {
            var j = Math.floor(Math.random() * (i + 1));
            var t = a[i]; a[i] = a[j]; a[j] = t;
        }
        return a;
    }

    function startNext() {
        if (!loaded) return;
        var name;
        if (scene !== "Cycle" && programs[scene]) {
            name = scene;
        } else {
            if (!bag.length) {
                var b = shuffled(programNames);
                if (b.length > 1 && b[0] === currentProgram) b.push(b.shift());
                bag = b;
            }
            name = bag[0];
            bag = bag.slice(1);
        }
        controls.clear();
        hostClearPaint();
        cursorName = "";
        if (colour === "Random") {
            var c = ["Blue", "Red", "Purple", "Yellow", "Green", "Orange", "Gray", "Dark Gray"];
            randomColour = c[Math.floor(Math.random() * c.length)];
        }
        currentProgram = name;
        // reset the camera tweens and gradient to a neutral state, restart the clock at 0
        setClock(0, shouldRun);
        fadeOutAt = 1e9;
        plane.fadeOutStart = 1e9;
        hostTween("scale", 0, 0, 0, 0, "linear");
        hostTween("roll", 0, 0, 0, 0, "linear");
        hostTween("tilt", 0, 0, 0, 0, "linear");
        hostTween("scrollX", 256, 256, 0, 0, "linear");
        hostTween("scrollY", 171, 171, 0, 0, "linear");
        plane.rampFrom = plane.rampTo;
        plane.rampTo = plane.rampFrom;
        plane.rampT0 = -100;
        machine = new M.Machine(view, programs[name]);
        machine.step(0);
    }

    onSceneChanged: if (loaded) hostProgramDone()

    // ------------------------------------------------------------------ interpreter tick
    // Runs on the GUI thread only to advance the script, animate sprites and move the
    // simulated mouse; camera motion is computed on the render thread (see plane).
    Timer {
        interval: 33
        repeat: true
        running: view.clockRunning && view.machine !== null
        onTriggered: view.tick()
    }

    function tick() {
        if (!machine) return;
        var d = new Date(), cm = d.getHours() * 60 + d.getMinutes();
        if (cm !== clockMinute) clockMinute = cm;
        var t = now();
        if (fadeOutAt < 1e8 && t >= fadeOutAt + fadeDur) {
            startNext();
            return;
        }
        if (!machine.done) machine.step(t - machine.t);
        frameRendered();
    }

    // ------------------------------------------------------------------ 1-bit composite (512x342)
    ListModel { id: controls }

    Item {
        id: composite
        width: 512
        height: 342

        Rectangle { anchors.fill: parent; color: "white" }
        Image {
            source: view.imageName ? view.imgBase + view.imageName + ".png" : ""
            smooth: false
            cache: true
        }
        Canvas {
            id: paintCanvas
            width: 512
            height: 342
            smooth: false
            antialiasing: false
            onPaint: {
                var ctx = getContext("2d");
                if (view.clearPaintPending) {
                    ctx.clearRect(0, 0, width, height);
                    view.clearPaintPending = false;
                }
                ctx.fillStyle = "black";
                var p = view.pendingPaint;
                for (var i = 0; i < p.length; ++i) ctx.fillRect(p[i][0], p[i][1], 1, 1);
                view.pendingPaint = [];
            }
        }
        Repeater {
            model: controls
            delegate: Item {
                id: del
                required property string kind
                required property string src
                required property real cx
                required property real cy
                required property real cw
                required property real ch
                required property real fw
                required property real fh
                required property int frame
                required property bool shown
                required property string text
                required property string perm
                x: Math.round(cx)
                y: Math.round(cy)
                width: cw
                height: ch
                visible: shown

                Item { // sprite frame
                    visible: del.kind === "sprite"
                    width: del.fw
                    height: del.fh
                    clip: true
                    Image {
                        x: -del.frame * del.fw
                        source: del.kind === "sprite" ? view.imgBase + del.src + ".png" : ""
                        smooth: false
                    }
                }
                Repeater { // Geneva 12 text
                    model: del.kind === "text" ? A.layout(del.text) : []
                    delegate: Item {
                        required property var modelData
                        x: modelData.x
                        width: 8
                        height: 7
                        clip: true
                        Image { x: -parent.modelData.g * 8; source: view.imgBase + "Geneva12.png"; smooth: false }
                    }
                }
                Repeater { // sliding puzzle tiles
                    model: del.kind === "puzzle" ? del.perm.split(",") : []
                    delegate: Item {
                        required property var modelData
                        required property int index
                        x: (index % 4) * 20
                        y: Math.floor(index / 4) * 20
                        width: 19
                        height: 19
                        clip: true
                        Image { x: -parseInt(parent.modelData) * 19; source: view.imgBase + "PuzzleTiles.png"; smooth: false }
                    }
                }
            }
        }
        Repeater { // analog clock faces in the scene image show the current time
            model: A.CLOCK_FACES[view.imageName] || []
            delegate: Canvas {
                required property var modelData
                readonly property int rad: Math.ceil(modelData.r)
                x: modelData.x - rad
                y: modelData.y - rad
                width: 2 * rad + 1
                height: 2 * rad + 1
                smooth: false
                antialiasing: false
                readonly property int minuteOfDay: view.clockMinute
                onMinuteOfDayChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    var m = minuteOfDay < 0 ? 0 : minuteOfDay;
                    var px = A.clockPixels(modelData, Math.floor(m / 60), m % 60);
                    for (var i = 0; i < px.length; ++i) {
                        ctx.fillStyle = px[i][2] ? "black" : "white";
                        ctx.fillRect(px[i][0], px[i][1], 1, 1);
                    }
                }
            }
        }
        Item { // the simulated mouse cursor
            visible: view.cursorName !== ""
            x: view.cursorX
            y: view.cursorY
            width: 16
            height: 16
            clip: true
            Image { x: -view.cursorFrame * 16; source: view.imgBase + "Cursors.png"; smooth: false }
        }
    }

    // XOR layer: opaque where the composite should be inverted (caret, selections).
    Item {
        id: invertLayer
        width: 512
        height: 342
        Repeater {
            model: controls
            delegate: Rectangle {
                required property real cx
                required property real cy
                required property real cw
                required property real ch
                required property bool inv
                required property bool shown
                x: Math.round(cx)
                y: Math.round(cy)
                width: cw
                height: ch
                color: "white"
                visible: inv && shown
            }
        }
    }

    UniformAnimator {
        id: clockAnim
        target: plane
        uniform: "clock"
        from: 0
        to: 100000
        duration: 100000000
        onFinished: if (view.clockRunning) view.setClock(view.now(), true)
    }

    ShaderEffectSource {
        id: compositeSrc
        sourceItem: composite
        textureSize: Qt.size(512, 342)
        hideSource: true
        smooth: false
        live: true
    }
    ShaderEffectSource {
        id: invertSrc
        sourceItem: invertLayer
        textureSize: Qt.size(512, 342)
        hideSource: true
        smooth: false
        live: true
    }

    ShaderEffect {
        id: plane
        anchors.fill: parent
        property variant source: compositeSrc
        property variant invertMask: invertSrc
        property size resolution: Qt.size(width, height)
        property point sceneSize: Qt.point(512, 342)
        property real clock: 0
        property vector4d twScale: Qt.vector4d(0, 0, 0, 0)
        property vector4d twRoll: Qt.vector4d(0, 0, 0, 0)
        property vector4d twTilt: Qt.vector4d(0, 0, 0, 0)
        property vector4d twScrollX: Qt.vector4d(256, 256, 0, 0)
        property vector4d twScrollY: Qt.vector4d(171, 171, 0, 0)
        property vector4d curvesA: Qt.vector4d(3, 3, 3, 0)
        property real curveScrollY: 0
        property real persp: 0.3
        property vector4d bgTop: Qt.vector4d(view.pal.top[0], view.pal.top[1], view.pal.top[2], 1)
        property vector4d bgBottom: Qt.vector4d(view.pal.bottom[0], view.pal.bottom[1], view.pal.bottom[2], 1)
        // Classic Mac look: the 1-bit "black" pixels are drawn black on the coloured plane.
        property vector4d inkColor: Qt.vector4d(0.02, 0.02, 0.025, 0.96)
        property real spectrum: view.colour === "Spectrum" ? 1 : 0
        property real hueBase: Math.random()
        property real hueRate: 1 / 150
        property real hueOffset: view.hueOffset
        property real bgDim: view.dark ? 0.55 : 1.0
        property point rampFrom: Qt.point(0, 0)
        property point rampTo: Qt.point(0, 0)
        property real rampT0: -100
        property real fadeOutStart: 1e9
        property real fadeDur: view.fadeDur
        property real gap: 0.14
        property real shadowAmt: 0.22
        property real shadowBlur: 0.45
        vertexShader: Qt.resolvedUrl("../shaders/plane.vert.qsb")
        fragmentShader: Qt.resolvedUrl("../shaders/plane.frag.qsb")
    }
}
