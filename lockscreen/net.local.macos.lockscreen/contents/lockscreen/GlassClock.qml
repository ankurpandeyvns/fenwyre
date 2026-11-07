/*
    macOS 26-style lock screen clock: date line above a very large "Liquid Glass" time.

    Default style "Stencil" draws SF Pro Rounded Heavy digits with stencil gaps cut through
    them at the stroke junctions, like the macOS lock screen; the other
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
    // macOS "Stencil": SF Pro Rounded Heavy glyphs with stencil gaps cut through them (the 1's
    // flag, the 2's hook and base, ...). Cuts are [x1, y1, x2, y2]: x in units of the glyph's
    // advance, y in units of the digit height, origin at the glyph's top-left. Positions were
    // measured on the font's outlines (stroke edges), so each gap falls on a stroke junction.
    readonly property var cuts: ({
        "0": [[0.66, 0.28, 0.94, 0.04], [0.06, 0.96, 0.34, 0.72]],
        "1": [[0.415, -0.1, 0.415, 0.42]],
        "2": [[0.60, 0.27, 0.95, 0.67], [-0.1, 0.80, 0.45, 0.80]],
        "3": [[0.56, 0.47, 1.10, 0.47]],
        "4": [[0.565, -0.1, 0.565, 0.62]],
        "5": [[0.38, -0.05, 0.38, 0.22]],
        "6": [[0.335, 0.40, 0.335, 0.54]],
        "7": [[0.55, 0.225, 1.10, 0.225]],
        "8": [[-0.05, 0.50, 0.31, 0.50], [0.69, 0.50, 1.05, 0.50]],
        "9": [[0.672, 0.44, 0.672, 0.62]]
    })
    readonly property real gapW: 0.042          // stencil gap, of the digit height
    readonly property real tracking: 0.035      // extra space between glyphs, of the digit height
    // SF Pro Rounded: digit height = 0.741 em, digit top = 0.723 em above the baseline
    readonly property int stencilPx: Math.round(digitH / 0.741)
    readonly property int stencilWeight: 600 + Math.round(weight * 2) * 100     // 600..800 (Heavy)
    function stencilFont() { return stencilWeight + " " + stencilPx + "px \"SF Pro Rounded\""; }
    // Draw the time at (x, y) = top-left of the digits; `cut` punches the stencil gaps.
    function drawTime(ctx, x, y, cut) {
        if (stencil) {
            ctx.font = stencilFont();
            ctx.textBaseline = "alphabetic";
            var base = y + 0.723 * stencilPx, xx = x;
            for (var i = 0; i < timeText.length; ++i) {
                var ch = timeText[i], a = ctx.measureText(ch).width;
                ctx.globalCompositeOperation = "source-over";
                ctx.fillText(ch, xx, base);
                var cs = cuts[ch];
                if (cut && cs) {
                    ctx.save();
                    ctx.globalCompositeOperation = "destination-out";
                    ctx.lineCap = "butt";
                    ctx.lineWidth = gapW * digitH;
                    for (var k = 0; k < cs.length; ++k) {
                        ctx.beginPath();
                        ctx.moveTo(xx + cs[k][0] * a, y + cs[k][1] * digitH);
                        ctx.lineTo(xx + cs[k][2] * a, y + cs[k][3] * digitH);
                        ctx.stroke();
                    }
                    ctx.restore();
                }
                xx += a + tracking * digitH;
            }
        } else {
            ctx.font = cssWeight + " " + timePx + "px \"" + family + "\"";
            ctx.textBaseline = "alphabetic";
            ctx.fillText(timeText, x, y + digitH);
        }
    }

    TextMetrics {
        id: stencilMetrics
        font.family: "SF Pro Rounded"
        font.weight: clock.stencilWeight
        font.pixelSize: clock.stencilPx
        text: clock.timeText
    }
    TextMetrics {
        id: metrics
        font.family: clock.family
        font.weight: clock.cssWeight
        font.pixelSize: clock.timePx
        text: clock.timeText
    }
    readonly property real textW: stencil ? stencilMetrics.advanceWidth + tracking * digitH * Math.max(0, timeText.length - 1)
                                             : metrics.advanceWidth
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
            blur: 0.26
            blurMax: 32
            brightness: 0.05
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
