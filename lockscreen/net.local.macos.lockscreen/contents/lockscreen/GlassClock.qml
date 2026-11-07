/*
    macOS 26-style lock screen clock: date line above a very large "Liquid Glass" time.

    Default style "Stencil" draws the macOS lock screen digits as vector strokes (each
    digit is built from separate rounded pieces with gaps between them); the other
    styles use the installed SF / New York faces. The glyph mask is softened (blur +
    threshold) to round the corners; the glass is a frosted, brightened sample of the
    wallpaper behind, a milky gradient, a bright inner rim band and a soft shadow.

    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Effects

Item {
    id: clock

    // Item to sample for the frosted glass (this screen's wallpaper); may be null.
    property Item backdrop: null
    // Stencil, Rounded, Pro, Serif, Compact, Thin (the six macOS styles)
    property string style: "Stencil"
    property real weight: 1.0               // 0 .. 1, like the macOS "Weight" slider
    property real screenHeight: 1080

    readonly property var families: ({
        Rounded: "SF Pro Rounded", Pro: "SF Pro Display",
        Serif: "New York", Compact: "SF Compact Rounded", Thin: "SF Pro Display"
    })
    readonly property bool stencil: style === "Stencil" || families[style] === undefined
    readonly property string family: families[style] || "SF Pro Rounded"
    readonly property int cssWeight: style === "Thin" ? 100 + Math.round(weight * 200)
                                                     : 400 + Math.round(weight * 5) * 100   // 400..900
    // digit height ~9.7% of the screen height (measured on the macOS reference)
    readonly property real digitH: Math.round(screenHeight * 0.097)
    readonly property int timePx: Math.round(digitH / 0.72)     // font size whose cap height is digitH
    readonly property int datePx: Math.max(14, Math.round(screenHeight * 0.0225))

    property date now: new Date()
    property bool freezeNow: false
    readonly property string timeText: Qt.formatTime(now, "h:mm")
    readonly property string dateText: Qt.formatDate(now, "ddd MMM d")
    Timer {
        interval: 1000
        repeat: true
        running: !clock.freezeNow
        triggeredOnStart: true
        onTriggered: {
            var d = new Date();
            if (d.getMinutes() !== clock.now.getMinutes() || d.getDate() !== clock.now.getDate()
                    || d.getHours() !== clock.now.getHours())
                clock.now = d;
        }
    }

    implicitWidth: Math.max(glyphs.width, dateLabel.implicitWidth)
    implicitHeight: dateLabel.implicitHeight + glyphs.height

    Text {
        id: dateLabel
        anchors.horizontalCenter: parent.horizontalCenter
        text: clock.dateText
        color: "white"
        font.family: "SF Pro Display"
        font.weight: Font.DemiBold
        font.pixelSize: clock.datePx
        renderType: Text.QtRendering
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.30)
            shadowBlur: 0.4
            shadowVerticalOffset: 1
        }
    }

    // ------------------------------------------------------------ stencil digits
    // Units of the digit height h, origin at the glyph's top-left, y down. Every piece is
    // a thick stroke (butt caps); the gaps between pieces are the stencil bridges.
    readonly property real sw: 0.25 * (0.7 + 0.3 * weight)      // stroke width (of h)
    readonly property var advances: ({ "1": 0.56, ":": 0.30 })
    function adv(ch) { return (advances[ch] !== undefined ? advances[ch] : 0.80); }
    readonly property real spacing: 0.11
    readonly property real gapW: 0.028          // stencil gap (of h)
    function stencilWidth(s) {
        var w = 0;
        for (var i = 0; i < s.length; ++i) w += adv(s[i]) + (i ? spacing : 0);
        return w * digitH;
    }
    function strokePieces(ctx, ch, x0, y0, h, cut) {
        var r = sw / 2;
        function P(x, y) { return [x0 + x * h, y0 + y * h]; }
        // Each piece first erases a slightly larger halo of itself, so wherever it
        // meets an earlier piece a clean stencil gap remains.
        var g = gapW * h, base = ctx.lineWidth;
        function line(ax, ay, bx, by, wScale) {
            var a = P(ax, ay), b = P(bx, by);
            var lw = base * (wScale || 1);
            if (cut) {
                var dx = b[0] - a[0], dy = b[1] - a[1], L = Math.sqrt(dx * dx + dy * dy) || 1;
                var ex = dx / L * g, ey = dy / L * g;
                ctx.save();
                ctx.globalCompositeOperation = "destination-out";
                ctx.lineWidth = lw + 2 * g;
                ctx.beginPath();
                ctx.moveTo(a[0] - ex, a[1] - ey); ctx.lineTo(b[0] + ex, b[1] + ey);
                ctx.stroke();
                ctx.restore();
            }
            ctx.lineWidth = lw;
            ctx.beginPath();
            ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
            ctx.stroke();
            ctx.lineWidth = base;
        }
        function arc(cx, cy, R, a0, a1, ccw) {
            var c = P(cx, cy);
            if (cut) {
                var da = g / (R * h) * (ccw ? -1 : 1);
                ctx.save();
                ctx.globalCompositeOperation = "destination-out";
                ctx.lineWidth = base + 2 * g;
                ctx.beginPath();
                ctx.arc(c[0], c[1], R * h, a0 - da, a1 + da, !!ccw);
                ctx.stroke();
                ctx.restore();
            }
            ctx.beginPath();
            ctx.arc(c[0], c[1], R * h, a0, a1, !!ccw);
            ctx.stroke();
        }
        function dot(cx, cy, R) {
            ctx.beginPath();
            var c = P(cx, cy);
            ctx.arc(c[0], c[1], R * h, 0, 2 * Math.PI, false);
            ctx.fill();
        }
        // one side of a "0": arc, straight side, arc as a single stroke
        function halfO(left) {
            var Wd = 0.80, Rr = (Wd / 2 - r), cxx = Wd / 2, t = r + Rr, b2 = 1 - r - Rr, gapA = 0.20;
            function trace(ext) {
                ctx.beginPath();
                var c1 = P(cxx, t), c2 = P(cxx, b2), RR = Rr * h;
                if (left) {
                    ctx.arc(c1[0], c1[1], RR, Math.PI * 1.5 - gapA + ext, Math.PI, true);
                    ctx.arc(c2[0], c2[1], RR, Math.PI, Math.PI * 0.5 + gapA - ext, true);
                } else {
                    ctx.arc(c1[0], c1[1], RR, Math.PI * 1.5 + gapA - ext, Math.PI * 2, false);
                    ctx.arc(c2[0], c2[1], RR, 0, Math.PI * 0.5 - gapA + ext, false);
                }
                ctx.stroke();
            }
            trace(0);
        }
        var PI = Math.PI, W = 0.80, cx = W / 2, R = cx - r;
        switch (ch) {
        case "0":
            halfO(true);
            halfO(false);
            break;
        case "1":
            line(0.03, 0.25, 0.25, 0.10, 0.62);             // flag (thinner, separate)
            line(0.43, 0.0, 0.43, 1.0);                     // stem
            break;
        case "2":
            arc(cx, r + R * 0.98, R, PI * 1.0, PI * 2.05, false);            // top hook
            line(0.71, 0.36, 0.06, 0.88, 0.92);                                  // diagonal
            line(0.02, 1 - r * 0.72, W, 1 - r * 0.72, 0.72);                 // base (thinner)
            break;
        case "3":
            arc(cx - 0.02, 0.265, 0.20, PI * 1.02, PI * 2.30, false);
            arc(cx - 0.02, 0.70, 0.235, PI * 1.72, PI * 2.98, false);
            break;
        case "4":
            line(0.52, 0.02, 0.10, 0.58);                   // diagonal
            line(0.02, 0.73, 0.62, 0.73);                   // bar (ends at the stem)
            line(0.60, 0.33, 0.60, 1.0);                    // stem (crosses the bar)
            break;
        case "5":
            line(0.10, r, 0.74, r);                         // top bar
            line(0.12 + r, 0.10, 0.12 + r, 0.42);           // left upright
            arc(cx - 0.01, 0.655, 0.225, PI * 1.25, PI * 2.80, false);       // bowl
            break;
        case "6":
            arc(cx, 0.67, 0.205, PI * 1.18, PI * 3.12, false);               // loop (gap at top-left)
            line(0.17, 0.53, 0.50, 0.03);                   // rising stroke
            break;
        case "7":
            line(0.02, r, W, r);                            // top bar
            line(0.66, 0.32, 0.26, 1.0);                    // diagonal
            break;
        case "8":
            arc(cx, 0.255, 0.18, PI * 0.72, PI * 2.28, false);
            arc(cx, 0.705, 0.215, PI * 1.76, PI * 3.24, false);
            break;
        case "9":
            arc(cx, 0.33, 0.205, PI * 0.18, PI * 2.12, false);               // loop (gap at bottom-right)
            line(0.63, 0.47, 0.30, 0.97);                   // tail
            break;
        case ":":
            dot(0.15, 0.32, 0.125);
            dot(0.15, 0.80, 0.125);
            break;
        }
    }
    // Draw the time at (x, y) with the current style; `stroke` for the outline pass.
    function drawTime(ctx, x, y, cut) {
        if (stencil) {
            ctx.lineWidth = sw * digitH;
            ctx.lineCap = "butt";
            ctx.lineJoin = "round";
            var xx = x;
            for (var i = 0; i < timeText.length; ++i) {
                strokePieces(ctx, timeText[i], xx, y, digitH, !!cut);
                xx += (adv(timeText[i]) + spacing) * digitH;
            }
        } else {
            ctx.font = cssWeight + " " + timePx + "px \"" + family + "\"";
            ctx.textBaseline = "alphabetic";
            ctx.fillText(timeText, x, y + digitH);
        }
    }

    TextMetrics {
        id: metrics
        font.family: clock.family
        font.weight: clock.cssWeight
        font.pixelSize: clock.timePx
        text: clock.timeText
    }
    readonly property real textW: stencil ? stencilWidth(timeText) : metrics.advanceWidth
    readonly property real pad: Math.round(digitH * 0.25)
    onTextWChanged: redraw()
    onTimeTextChanged: redraw()
    onStyleChanged: redraw()
    onWeightChanged: redraw()

    function redraw() {
        fill.requestPaint();
        shadow.requestPaint();
    }

    Item {
        id: glyphs
        anchors.top: dateLabel.bottom
        anchors.topMargin: Math.round(clock.screenHeight * 0.022) - clock.pad
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.ceil(clock.textW + 2 * clock.pad)
        height: Math.ceil(clock.digitH + 2 * clock.pad)

        // soft drop shadow (glyphs drawn off-canvas, only their shadow lands inside)
        Canvas {
            id: shadow
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.shadowColor = Qt.rgba(0, 0, 0, 0.22);
                ctx.shadowBlur = clock.digitH * 0.10;
                ctx.shadowOffsetX = 10000;
                ctx.shadowOffsetY = clock.digitH * 0.025;
                ctx.fillStyle = "black";
                ctx.strokeStyle = "black";
                clock.drawTime(ctx, clock.pad - 10000, clock.pad);
            }
        }

        // sharp glyph shapes
        Canvas {
            id: fill
            anchors.fill: parent
            visible: false
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = "white";
                ctx.strokeStyle = "white";
                clock.drawTime(ctx, clock.pad, clock.pad, true);
            }
        }
        // wallpaper behind the digits, slightly magnified and frosted
        ShaderEffectSource {
            id: behind
            anchors.fill: parent
            visible: false
            live: true
            sourceItem: clock.backdrop
            sourceRect: {
                if (!clock.backdrop) return Qt.rect(0, 0, 0, 0);
                var p = glyphs.mapToItem(clock.backdrop, 0, 0);
                var m = glyphs.height * 0.06;
                return Qt.rect(p.x - m, p.y - m, glyphs.width + 2 * m, glyphs.height + 2 * m);
            }
        }
        MultiEffect {
            id: frosted
            anchors.fill: parent
            visible: false
            source: behind
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 0.35
            blurMax: 32
            brightness: 0.12
            layer.enabled: true
        }
        ShaderEffectSource {
            id: maskTex
            anchors.fill: parent
            visible: false
            sourceItem: fill
            hideSource: true
        }
        ShaderEffect {
            anchors.fill: parent
            property var mask: maskTex
            property var backdrop: frosted
            property size texel: Qt.size(1 / Math.max(1, width), 1 / Math.max(1, height))
            property real radius: clock.digitH * 0.022
            property real rimWidth: clock.digitH * 0.03
            property real hasBackdrop: clock.backdrop ? 1 : 0
            vertexShader: Qt.resolvedUrl("shaders/glass.vert.qsb")
            fragmentShader: Qt.resolvedUrl("shaders/glass.frag.qsb")
        }
    }
    Component.onCompleted: redraw()
}
