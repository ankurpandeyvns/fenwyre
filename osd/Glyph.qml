import QtQuick
import QtQuick.Shapes

// SF Symbols-like vector glyphs drawn on a 24x24 grid and scaled to the item size.
// Each glyph is up to three paths: filled shapes, stroked lines, and dimmed strokes
// (inactive Wi-Fi bars / speaker waves).
Item {
    id: g

    property string kind: "cc"
    property color color: "white"
    property real level: 1          // 0..1, for speaker / sun / wifi
    property bool muted: false
    property real dimOpacity: 0.3
    property bool outline: false     // draw filled shapes as outlines (macOS HUD style)

    implicitWidth: 16
    implicitHeight: 16

    readonly property var spec: build(kind, level, muted)

    function n(v) { return Math.round(v * 1000) / 1000; }
    function circ(cx, cy, r) {
        return "M" + n(cx - r) + "," + n(cy) + " a" + r + "," + r + " 0 1 0 " + n(2 * r) + ",0 a" + r + "," + r + " 0 1 0 " + n(-2 * r) + ",0 Z ";
    }
    function rrect(x, y, w, h, r) {
        return "M" + n(x + r) + "," + y + " H" + n(x + w - r) + " A" + r + "," + r + " 0 0 1 " + n(x + w) + "," + n(y + r)
             + " V" + n(y + h - r) + " A" + r + "," + r + " 0 0 1 " + n(x + w - r) + "," + n(y + h)
             + " H" + n(x + r) + " A" + r + "," + r + " 0 0 1 " + x + "," + n(y + h - r)
             + " V" + n(y + r) + " A" + r + "," + r + " 0 0 1 " + n(x + r) + "," + y + " Z ";
    }
    // arc from angle a0 to a1 (degrees, clockwise on screen, 0 = pointing right)
    function arc(cx, cy, r, a0, a1) {
        const p = a => [n(cx + r * Math.cos(a * Math.PI / 180)), n(cy + r * Math.sin(a * Math.PI / 180))];
        const s = p(a0), e = p(a1);
        const large = Math.abs(a1 - a0) > 180 ? 1 : 0;
        return "M" + s[0] + "," + s[1] + " A" + r + "," + r + " 0 " + large + " 1 " + e[0] + "," + e[1] + " ";
    }
    function ray(cx, cy, r0, r1, a) {
        const c = Math.cos(a * Math.PI / 180), s = Math.sin(a * Math.PI / 180);
        return "M" + n(cx + r0 * c) + "," + n(cy + r0 * s) + " L" + n(cx + r1 * c) + "," + n(cy + r1 * s) + " ";
    }

    function build(k, lv, m) {
        let f = "", s = "", d = "", w = 1.8;
        switch (k) {
        case "cc":          // Control Center: two toggle switches
            s = rrect(2.5, 3.5, 19, 7, 3.5) + rrect(2.5, 13.5, 19, 7, 3.5);
            f = circ(6, 7, 2.1) + circ(18, 17, 2.1);
            w = 1.5;
            break;
        case "speaker": {
            f = "M2.5,9.2 Q2.5,8.5 3.2,8.5 H6.6 L11,4.6 Q11.8,4 11.8,5 V19 Q11.8,20 11,19.4 L6.6,15.5 H3.2 Q2.5,15.5 2.5,14.8 Z ";
            if (m) {
                s = "M15.2,9.2 L20.8,14.8 M20.8,9.2 L15.2,14.8 ";
                w = 1.9;
                break;
            }
            const waves = [arc(12.2, 12, 3.6, -48, 48), arc(12.2, 12, 6.9, -50, 50), arc(12.2, 12, 10.2, -52, 52)];
            const on = lv <= 0.001 ? 0 : lv < 0.34 ? 1 : lv < 0.67 ? 2 : 3;
            for (let i = 0; i < 3; i++) { if (i < on) s += waves[i]; else d += waves[i]; }
            w = 1.9;
            break;
        }
        case "sun":
            if (lv < 0.34) {
                f = circ(12, 12, 3.6);
                for (let a = 0; a < 360; a += 45) s += ray(12, 12, 7.2, 7.4, a);
                w = 2.2;
            } else {
                f = circ(12, 12, 4.4);
                for (let a = 0; a < 360; a += 45) s += ray(12, 12, 7.4, 9.6, a);
                w = 1.9;
            }
            break;
        case "moon":
            f = "M10.2,2.8 A9.4,9.4 0 1 0 21.2,14.2 A7.6,7.6 0 0 1 10.2,2.8 Z ";
            break;
        case "wifi": {
            f = circ(12, 19.2, 1.9);
            const bars = [arc(12, 19.6, 5.4, -134, -46), arc(12, 19.6, 10, -136, -44), arc(12, 19.6, 14.4, -137, -43)];
            const on = lv < 0.25 ? 0 : lv < 0.5 ? 1 : lv < 0.75 ? 2 : 3;
            for (let i = 0; i < 3; i++) { if (i < on) s += bars[i]; else d += bars[i]; }
            w = 2.3;
            break;
        }
        case "bluetooth":
            s = "M6.8,7.6 L17,16.4 L12,20.8 V3.2 L17,7.6 L6.8,16.4 ";
            w = 1.8;
            break;
        case "mirror":      // rectangle.on.rectangle
            s = "M8.5,15 H4.5 A2,2 0 0 1 2.5,13 V5.5 A2,2 0 0 1 4.5,3.5 H14.5 A2,2 0 0 1 16.5,5.5 V9 "
              + rrect(8.5, 9.5, 13, 10.5, 2);
            w = 1.6;
            break;
        case "grid":        // overview
            f = rrect(3.5, 3.5, 7.5, 7.5, 2) + rrect(13, 3.5, 7.5, 7.5, 2) + rrect(3.5, 13, 7.5, 7.5, 2) + rrect(13, 13, 7.5, 7.5, 2);
            break;
        case "kbd":         // light.max
            f = "M6.6,18 A5.4,5.4 0 0 1 17.4,18 Z ";
            for (let a = 180; a <= 360; a += 45) s += ray(12, 18, 8, 10.6, a);
            s += "M3,21 H21 ";
            w = 1.8;
            break;
        case "darkmode":    // circle.righthalf.filled
            s = circ(12, 12, 8.6);
            f = "M12,3.4 A8.6,8.6 0 0 1 12,20.6 Z ";
            w = 1.6;
            break;
        case "nightshift":  // sun.max with a half-moon feel: sun.horizon-ish
            f = "M12,6.5 A5.5,5.5 0 0 1 12,17.5 Z ";
            s = circ(12, 12, 5.5);
            for (let a = 0; a < 360; a += 45) s += ray(12, 12, 8, 10, a);
            w = 1.6;
            break;
        case "play":
            f = "M7.2,4.6 Q7.2,3.6 8.1,4.1 L19.4,11.1 Q20.2,11.6 19.4,12.1 L8.1,19.1 Q7.2,19.6 7.2,18.6 Z ";
            break;
        case "pause":
            f = rrect(6, 4.5, 4.2, 15, 1.2) + rrect(13.8, 4.5, 4.2, 15, 1.2);
            break;
        case "next":
            f = "M2.5,6.4 Q2.5,5.6 3.2,6.1 L11.4,11.4 Q12,11.9 11.4,12.4 L3.2,17.7 Q2.5,18.2 2.5,17.4 Z "
              + "M12,6.4 Q12,5.6 12.7,6.1 L20.9,11.4 Q21.5,11.9 20.9,12.4 L12.7,17.7 Q12,18.2 12,17.4 Z ";
            break;
        case "prev":
            f = "M21.5,6.4 Q21.5,5.6 20.8,6.1 L12.6,11.4 Q12,11.9 12.6,12.4 L20.8,17.7 Q21.5,18.2 21.5,17.4 Z "
              + "M12,6.4 Q12,5.6 11.3,6.1 L3.1,11.4 Q2.5,11.9 3.1,12.4 L11.3,17.7 Q12,18.2 12,17.4 Z ";
            break;
        case "chevronRight":
            s = "M9,5 L16,12 L9,19 ";
            w = 2.2;
            break;
        case "chevronLeft":
            s = "M15,5 L8,12 L15,19 ";
            w = 2.2;
            break;
        case "check":
            s = "M5,12.6 L10,17.4 L19,6.8 ";
            w = 2.3;
            break;
        case "lock":
            f = rrect(5.5, 10.5, 13, 10, 2.2);
            s = "M8.3,10.5 V7.8 A3.7,3.7 0 0 1 15.7,7.8 V10.5 ";
            w = 2;
            break;
        case "display":
            s = rrect(2.5, 3.5, 19, 13, 2) + "M8.5,20.5 H15.5 M12,16.5 V20.5 ";
            w = 1.6;
            break;
        case "headphones":
            s = "M4.3,15.5 V12 A7.7,7.7 0 0 1 19.7,12 V15.5 ";
            f = rrect(2.8, 13.2, 5, 7.8, 1.8) + rrect(16.2, 13.2, 5, 7.8, 1.8);
            w = 1.8;
            break;
        case "bolt":
            f = "M13.4,2 L4.6,13.6 H11 L10.2,22 L19.4,10 H12.8 Z ";
            break;
        case "note":
            f = circ(7, 18, 2.8) + circ(17.4, 16, 2.8);
            s = "M9.6,18 V6.2 L20.2,3.8 V16 ";
            w = 1.8;
            break;
        case "gauge":       // power mode
            s = arc(12, 14, 8.5, 160, 380) + ray(12, 14, 0, 6, -55);
            f = circ(12, 14, 1.8);
            w = 1.8;
            break;
        case "leaf":
            f = "M19.5,4 C9,4 4.5,8.5 4.5,15 C4.5,17 5,18.6 5.6,19.6 C6.6,20.2 8,20.5 9.6,20.5 C16,20.5 19.5,15 19.5,4 Z ";
            s = "M4,21 C7,16 10,13 14,10 ";
            w = 1.4;
            break;
        case "battery":
            s = rrect(2, 7, 18, 10, 3);
            f = "M21.2,10 Q22.4,10.4 22.4,12 Q22.4,13.6 21.2,14 Z ";
            w = 1.4;
            break;
        case "mouse":
            s = rrect(6.5, 2.5, 11, 19, 5.5) + "M12,2.5 V9 ";
            w = 1.7;
            break;
        case "keyboard":
            s = rrect(2, 6, 20, 12, 2.5) + "M7.5,14.6 H16.5 ";
            for (let r = 0; r < 2; r++) for (let c = 0; c < 5; c++) f += rrect(4.6 + c * 3.2, 8.5 + r * 2.6, 1.6, 1.4, 0.4);
            w = 1.5;
            break;
        case "phone":
            s = rrect(6.5, 2.5, 11, 19, 2.6) + "M10.5,5 H13.5 ";
            w = 1.7;
            break;
        case "gear":
            s = circ(12, 12, 3.2);
            for (let a = 0; a < 360; a += 45) s += ray(12, 12, 6.4, 9.4, a + 22.5);
            s += circ(12, 12, 6.4);
            w = 2;
            break;
        }
        return { f: f, s: s, d: d, w: w };
    }

    Shape {
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: Math.min(g.width, g.height) / 24
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: g.outline ? g.spec.w * 0.8 : -1
            strokeColor: g.outline ? g.color : "transparent"
            fillColor: g.outline ? "transparent" : g.color
            joinStyle: ShapePath.RoundJoin
            fillRule: ShapePath.WindingFill
            PathSvg { path: g.spec.f || "M0,0" }
        }
        ShapePath {
            strokeWidth: g.spec.w
            strokeColor: g.spec.s ? g.color : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: g.spec.s || "M0,0" }
        }
        ShapePath {
            strokeWidth: g.spec.w
            strokeColor: g.spec.d ? Qt.rgba(g.color.r, g.color.g, g.color.b, g.color.a * g.dimOpacity) : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: g.spec.d || "M0,0" }
        }
    }
}
