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
    property real fade: 0
    property int fadeDir: 1
    property real wall: 0
    property string randomColour: "Blue"
    property real rampX: 0
    property real rampY: 0
    property string cursorName: ""
    property int cursorX: 0
    property int cursorY: 0
    property int cursorFrame: 0
    property var pendingPaint: []
    property bool clearPaintPending: false
    readonly property bool loaded: programNames.length > 0
    readonly property var pal: A.palette(colour === "Random" ? randomColour : colour, dark,
                                         [accent.r * 255, accent.g * 255, accent.b * 255])

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
        fadeDir = -1;
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
        machine = new M.Machine(view, programs[name]);
        machine.step(0);
        fadeDir = 1;
    }

    onSceneChanged: if (loaded) fadeDir = -1

    // ------------------------------------------------------------------ per-frame update
    FrameAnimation {
        // keep running until the first fade-in completes so a covered screen still has a frame
        running: view.visible && view.loaded && (!view.paused || view.fade < 1)
        onTriggered: view.advance(Math.min(frameTime, 0.1))
    }

    function advance(dt) {
        wall += dt;
        if (!machine) return;
        if (fadeDir < 0) {
            fade = Math.max(0, fade - dt / 0.6);
            if (fade <= 0) startNext();
        } else if (fade < 1) {
            fade = Math.min(1, fade + dt / 0.6);
        }
        if (fadeDir >= 0) machine.step(dt * speed);
        updateView(dt);
    }

    function updateView(dt) {
        var s = machine.state;
        var e = Math.max(0, Math.min(1, s.scale));
        var aspect = width / Math.max(1, height);
        var outH = Math.min(342, 512 / aspect);      // whole screen image, cover-fit
        var inH = 116 / Math.max(aspect, 1.0);         // ~116 image px across the long edge
        var vh = Math.exp(Math.log(outH) * (1 - e) + Math.log(inH) * e);
        var roll = -s.roll * e * Math.PI / 180;   // Apple: camera -22.5 => rows rise to the right
        plane.center = Qt.point(256 + (s.scrollX - 256) * e, 171 + (s.scrollY - 171) * e);
        plane.viewHeight = vh;
        plane.roll = roll;
        plane.tilt = Math.abs(s.tilt) * e * Math.PI / 180;
        plane.shadowOffset = Qt.point(0.3 * Math.sin(roll), 0.3 * Math.cos(roll));
        var tx = 0, ty = 0;
        switch (s.ramp) {
        case "Right": tx = 1; break;
        case "Left": tx = -1; break;
        case "Up": ty = -1; break;
        case "Down": ty = 1; break;
        }
        var k = Math.min(1, dt * 0.8);
        rampX += (tx - rampX) * k;
        rampY += (ty - rampY) * k;
        plane.rampDir = Qt.point(rampX, rampY);
        plane.hueBase = wall / 150 + hueOffset;
        plane.inkFade = fade;
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
        property point center: Qt.point(256, 171)
        property real roll: 0
        property real tilt: 0
        property real viewHeight: 342
        property real persp: 0.3
        property vector4d bgTop: Qt.vector4d(view.pal.top[0], view.pal.top[1], view.pal.top[2], 1)
        property vector4d bgBottom: Qt.vector4d(view.pal.bottom[0], view.pal.bottom[1], view.pal.bottom[2], 1)
        property vector4d inkColor: Qt.vector4d(view.pal.ink[0], view.pal.ink[1], view.pal.ink[2], 1)
        property point rampDir: Qt.point(0, 0)
        property point shadowOffset: Qt.point(0, 0.3)
        property real hueBase: 0
        property real hueSpan: 0.6
        property real spectrum: view.pal.spectrum ? 1 : 0
        property real spectrumSat: view.pal.sat
        property real spectrumVal: view.pal.val
        property real inkFade: 0
        property real gap: 0.14
        property real shadowAmt: view.pal.shadow
        property real shadowBlur: 0.45
        vertexShader: Qt.resolvedUrl("../shaders/plane.vert.qsb")
        fragmentShader: Qt.resolvedUrl("../shaders/plane.frag.qsb")
    }
}
