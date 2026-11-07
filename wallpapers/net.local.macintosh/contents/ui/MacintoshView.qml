import QtQuick
import QtCore
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
    property var machine: null
    property var sidecar: null              // authored companion of an Apple program (<Name>.extra)
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

    // ---- run mode (set by main.qml)
    //  "live":         always animating (the lock screen)
    //  "static":       hold one frame, no timers or render loop (desktop default); eases
    //                  to a stop on unlockEase()
    //  "desktop-live": animate on the desktop, pausing while covered
    property string mode: "live"
    property double freezeAt: 0             // static mode: wall time (ms) of the frame to hold, 0 = pick one
    property double anchorWall: 0           // testing: timeline starts here instead of the epoch
    signal frozeAt(double wallMs)           // static mode settled on the frame at this wall time

    // The whole animation is a pure function of wall-clock time: programs follow each
    // other from a fixed epoch in seeded order, so every instance (lock screen, desktop,
    // each screen) shows the same frame at the same moment without talking to each other.
    readonly property double epochMs: Date.UTC(2024, 0, 24)        // Macintosh 40th anniversary
    readonly property real speedK: Math.max(0.05, speed)
    property var durations: ({})            // program time each program runs before its fade-out
    property double slotStart: 0            // timeline position (program s) where the current program began
    property int slotSeed: 0
    property bool clockRunning: false
    property real frozenT: 0                // program time shown while the clock is stopped
    // Virtual timeline: v (ms) is the moment of the epoch timeline being shown. The lock
    // screen resumes from the frame the desktop holds (heldV), ramping up to full speed
    // over rampMs; after unlock the desktop keeps playing and decelerates to a stop over
    // easeMs, then holds that frame. Both processes share heldV / runStart through a small
    // state file, so they always compute the same frame.
    property double heldV: 0                // timeline position held (static) / resumed from
    property double runStart: 0             // wall time playback resumed from heldV (0: v = wall time)
    readonly property int rampMs: 1000
    property bool easing: false
    property double easeStartWall: 0
    property double easeFromV: 0
    readonly property int easeMs: 5000
    // ease-out playback rate ~ (1 + cos(pi u)) / 2, as a cubic bezier on position
    readonly property var easeCurve: [0.4, 0.8, 0.6, 1.0, 1, 1]
    property real fadeOutAt: 1e9
    readonly property real fadeDur: 0.6 * speedK
    property var curveIds: [3, 3, 3, 0, 0]
    property int clockMinute: -1            // minutes since midnight, drives the analog clock faces
    readonly property bool shouldRun: visible && loaded && (mode === "live" || (mode === "desktop-live" && !paused))

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
    function hostProgramDone(t) {
        if (fadeOutAt < 1e8) return;
        fadeOutAt = t;
        plane.fadeOutStart = t;
    }
    // Main program entered a new scene: start the matching label of its companion
    // program, if any. The companion adds mouse activity to Apple's own programs.
    function hostScene(name, t) {
        if (sidecar) {
            for (var i = 0; i < sidecar.controls.length; ++i)
                sidecar.setItem(sidecar.controls[i], { shown: false });
            sidecar = null;
        }
        hostCursor("", 0, 0, 0);
        if (machine) machine._cursorKey = "?";
        var extra = programs[currentProgram + ".extra"];
        if (!extra || extra.labels[name] === undefined) return;
        var m = new M.Machine(view, extra, true, slotSeed * 7 + 3);
        m.t = t;
        m.waitUntil = t;
        m.pc = extra.labels[name];
        sidecar = m;
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

    // ------------------------------------------------------------------ timeline
    function timelinePos(wallMs) {
        return (wallMs - (anchorWall > 0 ? anchorWall : epochMs)) / 1000 * speedK;
    }
    function wallOf(t) {        // wall time (ms) at program time t of the current program
        return (anchorWall > 0 ? anchorWall : epochMs) + (slotStart + t) / speedK * 1000;
    }
    function slotLen(name) { return (durations[name] || 60) + fadeDur; }
    function rawBag(k) {
        var a = programNames.slice().sort(), r = M.rng(0x5eed0000 + k);
        for (var i = a.length - 1; i > 0; --i) {
            var j = Math.floor(r() * (i + 1));
            var x = a[i]; a[i] = a[j]; a[j] = x;
        }
        return a;
    }
    function bagOrder(k) {      // no program plays twice in a row across bag boundaries
        var b = rawBag(k), prev = rawBag(k - 1);
        if (b.length > 2 && b[0] === prev[prev.length - 1]) { var x = b[0]; b[0] = b[1]; b[1] = x; }
        return b;
    }
    // Which program plays at wallMs, and how far into it.
    function locate(wallMs) {
        var P = timelinePos(wallMs), k, S;
        if (scene !== "Cycle" && programs[scene]) {
            S = slotLen(scene);
            k = Math.floor(P / S);
            return { name: scene, off: P - k * S, start: k * S, seed: k };
        }
        var L = 0, i, order = programNames;
        for (i = 0; i < order.length; ++i) L += slotLen(order[i]);
        k = Math.floor(P / L);
        var off = P - k * L;
        order = bagOrder(k);
        for (i = 0; i < order.length; ++i) {
            S = slotLen(order[i]);
            if (off < S || i === order.length - 1)
                return { name: order[i], off: Math.min(off, S), start: P - off, seed: k * 64 + i };
            off -= S;
        }
        return null;
    }

    // ------------------------------------------------------------------ clock
    // Program time of the current program. Running: derived from the wall clock (the
    // shader's copy is advanced on the render thread by clockAnim). While easing after
    // an unlock, time slows to a stop (ease-out quad) over easeMs.
    function bezierY(u) {      // the same cubic bezier Qt applies to the animator
        var c = easeCurve, lo = 0, hi = 1, t = u;
        function bx(t) { var m = 1 - t; return 3 * m * m * t * c[0] + 3 * m * t * t * c[2] + t * t * t; }
        for (var i = 0; i < 40; ++i) { t = (lo + hi) / 2; if (bx(t) < u) lo = t; else hi = t; }
        var m = 1 - t;
        return 3 * m * m * t * c[1] + 3 * m * t * t * c[3] + t * t * t;
    }
    // timeline position for wall time w
    function vOf(w) {
        if (easing) {
            var u = Math.max(0, Math.min(1, (w - easeStartWall) / easeMs));
            return easeFromV + easeMs / 2 * bezierY(u);
        }
        if (runStart > 0) {
            var e = w - runStart;
            if (e <= 0) return heldV;
            if (e < rampMs) return heldV + e * e / (2 * rampMs);       // rate ramps 0 -> 1
            return heldV + rampMs / 2 + (e - rampMs);
        }
        if (mode === "static") return heldV;
        return w;
    }
    function now() {
        if (!clockRunning) return frozenT;
        return timelinePos(vOf(Date.now())) - slotStart;
    }
    function setClock(t, run) {
        // hue follows wall time too: one turn per 10 minutes
        var rate = 1 / (600 * speedK);
        var hb = slotStart * rate + 0.37;
        plane.hueBase = hb - Math.floor(hb);
        plane.hueRate = rate;
        clockRunning = false;           // before stop(): nothing may restart the animator meanwhile
        clockAnim.stop();
        lastSync = Date.now();
        clockRunning = run;
        frozenT = t;
        plane.clock = t;
        if (!run) return;
        var w = Date.now();
        rampAnim = false;
        if (easing && w - easeStartWall < 50) {
            // fresh unlock: the whole deceleration runs on the render thread
            clockAnim.easing.type = Easing.BezierSpline;
            clockAnim.easing.bezierCurve = easeCurve;
            clockAnim.from = t;
            clockAnim.to = timelinePos(easeFromV + easeMs / 2) - slotStart;
            clockAnim.duration = easeMs - (w - easeStartWall);
        } else if (easing) {
            // re-anchored mid-way (a new program began): approximate the rest linearly
            var wEnd = easeStartWall + easeMs;
            clockAnim.easing.type = Easing.Linear;
            clockAnim.from = t;
            clockAnim.to = t + timelinePos(vOf(wEnd)) - timelinePos(vOf(w));
            clockAnim.duration = Math.max(1, wEnd - w);
        } else if (runStart > 0 && w - runStart < rampMs) {
            // lock screen ramping up from the held frame
            var e0 = Math.max(0, w - runStart);
            clockAnim.easing.type = e0 < 20 ? Easing.InQuad : Easing.Linear;
            clockAnim.from = t;
            clockAnim.to = timelinePos(vOf(runStart + rampMs)) - slotStart;
            clockAnim.duration = Math.max(1, rampMs - e0);
            rampAnim = true;
        } else {
            clockAnim.easing.type = Easing.Linear;
            clockAnim.from = t;
            clockAnim.to = t + 100000 * speedK;
            clockAnim.duration = 100000000;
        }
        clockAnim.start();
    }

    // Watchdog: the render-thread animator can stall or fall behind (window unexposed,
    // monitor asleep, scene graph re-created) while the wall clock keeps going, which
    // freezes the camera. Re-anchor it to the wall clock every couple of seconds and
    // whenever the window's exposure changes.
    property double lastSync: 0
    function resync() { if (clockRunning && !easing && !ramping()) setClock(now(), true); }
    property bool rampAnim: false
    function rampEnded() {
        // switch the animator from the ramp curve to plain linear time once
        return rampAnim && !easing && Date.now() - runStart >= rampMs;
    }
    function ramping() { return runStart > 0 && Date.now() - runStart < rampMs; }
    Connections {
        target: view.Window.window
        ignoreUnknownSignals: true
        function onVisibilityChanged() { view.resync(); }
        function onSceneGraphInitialized() { view.resync(); }
        function onScreenChanged() { view.resync(); }
    }
    Connections {
        target: view.Window.window && view.Window.window.screen ? view.Window.window.screen : null
        ignoreUnknownSignals: true
        function onGeometryChanged() { view.resync(); }
    }

    onShouldRunChanged: if (loaded && !easing) { if (shouldRun) jumpTo(Date.now(), true); else setClock(now(), false); }
    onSpeedChanged: restart()
    onSceneChanged: restart()
    onModeChanged: restart()

    function restart() {
        if (!loaded) return;
        computeDurations();
        machine = null;
        easing = false;
        runStart = 0;
        if (mode === "static") settleStatic(freezeAt);
        else {
            if (mode === "live" && anchorWall === 0) startLive();
            jumpTo(Date.now(), shouldRun);
        }
    }

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
        programNames = names.filter(function (n) { return n.indexOf(".extra") < 0; });
        if (!names.length) hostLog("no programs found in " + programDir);
        restart();
    }

    // Each program's running time is fixed by its waits and tweens: dry-run it once.
    function computeDurations() {
        var d = {};
        var done = 0;
        var stub = {
            hostLog: function () {}, hostSetImage: function () {}, hostClearControls: function () {},
            hostSetControl: function () {}, hostPaint: function () {}, hostClearPaint: function () {},
            hostCursor: function () {}, hostTween: function () {}, hostRamp: function () {},
            hostAddControl: function () { return -1; },
            hostProgramDone: function (t) { done = t; }
        };
        for (var i = 0; i < programNames.length; ++i) {
            done = 0;
            var m = new M.Machine(stub, programs[programNames[i]], false, 1);
            for (var n = 0; n < 50 && !m.done; ++n) m.step(10000);
            d[programNames[i]] = m.done && done > 0 ? done : 60;
        }
        durations = d;
    }

    // Build the state of the program in `slot` from its beginning up to slot.off.
    function enter(slot) {
        sidecar = null;
        controls.clear();
        hostClearPaint();
        cursorName = "";
        if (colour === "Random") {
            var c = ["Blue", "Red", "Purple", "Yellow", "Green", "Orange", "Gray", "Dark Gray"];
            randomColour = c[Math.floor(M.rng(slot.seed * 13 + 5)() * c.length)];
        }
        currentProgram = slot.name;
        slotStart = slot.start;
        slotSeed = slot.seed;
        fadeOutAt = 1e9;
        plane.fadeOutStart = 1e9;
        hostTween("scale", 0, 0, 0, 0, "linear");
        hostTween("roll", 0, 0, 0, 0, "linear");
        hostTween("tilt", 0, 0, 0, 0, "linear");
        hostTween("scrollX", 256, 256, 0, 0, "linear");
        hostTween("scrollY", 171, 171, 0, 0, "linear");
        plane.rampFrom = Qt.point(0, 0);
        plane.rampTo = Qt.point(0, 0);
        plane.rampT0 = -100;
        machine = new M.Machine(view, programs[slot.name], false, slot.seed);
        machine.step(0);
        fastForward(slot.off);
    }
    function fastForward(t) {
        for (var guard = 0; machine.t < t - 1e-6 && guard < 30000; ++guard) {
            machine.step(Math.min(1 / 30, t - machine.t));
            if (sidecar && !sidecar.done) sidecar.step(machine.t - sidecar.t);
        }
    }
    // Bring the current program to wall time w (entering another program if needed).
    function jumpTo(w, run) {
        var slot = locate(vOf(w));
        if (!slot) return;
        if (machine && slot.name === currentProgram && Math.abs(slot.start - slotStart) < 1e-3
                && machine.t <= slot.off + 1e-6) fastForward(slot.off);
        else enter(slot);
        setClock(slot.off, run);
        frameRendered();
    }

    // ---- shared state ($XDG_RUNTIME_DIR/macintosh-wallpaper.ini)
    //   heldV:      timeline position (ms) the desktop holds / the lock screen resumes from
    //   heldAt:     wall time heldV was written
    //   runStart:   wall time the lock screen started playing from heldV
    Settings {
        id: shared
        location: "file://" + StandardPaths.writableLocation(StandardPaths.RuntimeLocation).toString().replace(/^file:\/\//, "") + "/macintosh-wallpaper.ini"
        category: "State"
    }
    function readShared() {
        shared.sync();
        return { heldV: Number(shared.value("heldV", 0)) || 0, heldAt: Number(shared.value("heldAt", 0)) || 0,
                 runStart: Number(shared.value("runStart", 0)) || 0 };
    }
    function writeHeld(v) {
        shared.setValue("heldV", String(Math.round(v)));
        shared.setValue("heldAt", String(Date.now()));
        shared.sync();
        frozeAt(v);
    }

    // Lock screen: resume from the desktop's frame (the first screen to start records
    // when playback began; the others reuse it).
    function startLive() {
        var st = readShared();
        var w = Date.now();
        if (!(st.heldV > 0)) {
            heldV = w;
            shared.setValue("heldV", String(w));
            shared.setValue("heldAt", String(w - 1));
        } else heldV = st.heldV;
        if (st.runStart > st.heldAt && w - st.runStart < 30000) runStart = st.runStart;
        else {
            runStart = w;
            shared.setValue("runStart", String(w));
            shared.sync();
        }
    }

    // Static desktop: show the held frame. With none yet, pick the next moment the camera
    // is fully zoomed in, and remember it.
    function settleStatic(v) {
        var st = readShared();
        if (st.heldV > 0) v = st.heldV;
        var pick = !(v > 0);
        if (pick) v = Date.now();
        heldV = v;
        jumpTo(v, false);
        if (pick) {
            for (var i = 0; i < 400; ++i) {
                if (!machine.done && machine.state.scale >= 0.999 && machine.t > 4) break;
                v += 500;
                heldV = v;
                jumpTo(v, false);
            }
            writeHeld(v);
        }
        setClock(machine.t, false);
    }

    // Locked: follow the lock screen (it resumes from heldV) so that whenever it goes
    // away the desktop is already on the same frame.
    property bool locked: false
    onLockedChanged: {
        if (!loaded || mode !== "static") return;
        if (locked) followLockScreen();
    }
    function followLockScreen() {
        var st = readShared();
        if (!(st.runStart > st.heldAt)) return;            // lock screen not started yet
        easing = false;
        runStart = st.runStart;
        heldV = st.heldV > 0 ? st.heldV : heldV;
        jumpTo(Date.now(), true);
    }
    Timer {     // the lock screen may record runStart a moment after the lock signal
        interval: 250
        repeat: true
        running: view.locked && view.mode === "static" && view.loaded && view.runStart === 0
        onTriggered: view.followLockScreen()
    }

    // Unlock: keep playing from the lock screen's frame and decelerate to a stop.
    function unlockEase() {
        if (!loaded || mode !== "static") return;
        if (runStart === 0) followLockScreen();
        var w = Date.now();
        easeFromV = vOf(w);
        runStart = 0;
        easing = true;
        easeStartWall = w;
        jumpTo(w, true);
    }

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
        if (easing && Date.now() >= easeStartWall + easeMs) {
            var vEnd = easeFromV + easeMs / 2;
            easing = false;
            heldV = vEnd;
            jumpTo(0, false);           // static: vOf() == heldV
            writeHeld(vEnd);
            frameRendered();
            return;
        }
        var t = now();
        if (t >= slotLen(currentProgram) || t < -1) {        // next program (or the clock jumped)
            var slot = locate(vOf(Date.now()));
            enter(slot);
            setClock(slot.off, true);
            frameRendered();
            return;
        }
        if (rampEnded()) setClock(t, true);
        else if (!easing && !ramping() && Date.now() - lastSync > 2000) setClock(t, true);
        if (!machine.done) machine.step(t - machine.t);
        if (sidecar && !sidecar.done) sidecar.step(t - sidecar.t);
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
                Rectangle { // cover (white), hides part of the image until revealed
                    visible: del.kind === "white"
                    anchors.fill: parent
                    color: "white"
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
        duration: 100000000             // ~28 h; the periodic resync re-anchors it long before
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
