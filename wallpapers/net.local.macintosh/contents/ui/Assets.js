.pragma library
// Asset metadata for the Macintosh wallpaper.
// Images live in contents/images/<Name>.png at native 1-bit resolution (the Apple
// 5120 px originals are kept untouched in contents/images/original/).

// Animation strips: frames laid out left to right.
var SPRITES = {
    Trash: { fw: 32, fh: 32, frames: 2 },
    Clarus: { fw: 32, fh: 32, frames: 2 },
    Disks: { fw: 32, fh: 32, frames: 2 },
    CloseBox: { fw: 32, fh: 32, frames: 4 },
    Bomb: { fw: 32, fh: 32, frames: 4 },
    HappyMac: { fw: 32, fh: 32, frames: 14 },
    ResEdit: { fw: 32, fh: 32, frames: 19 },
    StartupIcons: { fw: 32, fh: 32, frames: 3 },
    FolderIcon: { fw: 64, fh: 48, frames: 4 },
    TrashIcon: { fw: 64, fh: 48, frames: 4 },
    RadioButton: { fw: 16, fh: 16, frames: 4 },
    RadioButtonSystem1Number0: { fw: 16, fh: 16, frames: 4 },
    RadioButtonSystem1Number1: { fw: 16, fh: 16, frames: 4 },
    Slider: { fw: 23, fh: 11, frames: 1 },
    CancelButton: { fw: 74, fh: 18, frames: 2 },
    PuzzleTiles: { fw: 19, fh: 19, frames: 16 },
    MacWriteStyleMenu: { fw: 119, fh: 213, frames: 1 }
};

// Cursors.png: 16x16 frames. i = first frame, n = frame count, (hx,hy) = hotspot,
// period = ticks (1/60 s) per frame.
var CURSORS = {
    Arrow: { i: 0, n: 1, hx: 1, hy: 1, period: 0 },
    Crosshair: { i: 1, n: 1, hx: 5, hy: 5, period: 0 },
    Hand: { i: 2, n: 1, hx: 8, hy: 8, period: 0 },
    Pencil: { i: 3, n: 1, hx: 1, hy: 14, period: 0 },
    IBeam: { i: 4, n: 1, hx: 4, hy: 7, period: 0 },
    Watch: { i: 5, n: 8, hx: 8, hy: 8, period: 10 },
    Ball: { i: 13, n: 4, hx: 8, hy: 8, period: 8 }
};

// Geneva12.png: 8 px cells, 7 px tall (cap height), glyph bottom row on the baseline.
var FONT_CHARS = "0123456789:/APM -.";
var FONT_ADV = { ":": 3, " ": 4, "-": 5, ".": 3 };

function advance(ch) {
    return FONT_ADV[ch] !== undefined ? FONT_ADV[ch] : 6;
}

function textWidth(s) {
    var w = 0;
    for (var i = 0; i < s.length; ++i) w += advance(s[i]);
    return w;
}

// Returns [{g: glyphIndex, x: offset}] for a string.
function layout(s) {
    var out = [], x = 0;
    for (var i = 0; i < s.length; ++i) {
        var g = FONT_CHARS.indexOf(s[i]);
        if (g >= 0 && s[i] !== " ") out.push({ g: g, x: x });
        x += advance(s[i]);
    }
    return out;
}

// Program catalogue: [file stem, display name, origin]
var PROGRAMS = [
    ["IconGarden", "Icon Garden", "apple"],
    ["System6ControlPanel", "System 6 Control Panel", "apple"],
    ["AlertSounds", "Alert Sounds", "authored"],
    ["DeskAccessories", "Desk Accessories", "authored"],
    ["Finder", "Finder", "authored"],
    ["MacPaint", "MacPaint", "authored"],
    ["MacPaintHello", "MacPaint Hello / Quit Dialog", "authored"],
    ["MacWrite", "MacWrite", "authored"],
    ["Startup", "Startup", "authored"],
    ["System1ControlPanel", "System 1 Control Panel", "authored"]
];

var COLOURS = ["Spectrum", "Accent", "Blue", "Red", "Purple", "Yellow", "Dark Gray",
               "Gray", "Green", "Orange", "Random"];

// Light-appearance palettes sampled from Apple's rendered Macintosh wallpaper stills:
// background gradient top/bottom and ink (the 1-bit "black" pixels).
var PALETTE = {
    "Blue":      { top: [73, 162, 246],  bottom: [15, 134, 244], ink: [5, 111, 205] },
    "Orange":    { top: [250, 142, 87],  bottom: [236, 108, 40], ink: [216, 95, 32] },
    "Yellow":    { top: [232, 220, 96],  bottom: [222, 206, 40], ink: [185, 171, 27] },
    "Green":     { top: [196, 224, 112], bottom: [168, 204, 58], ink: [128, 164, 38] },
    "Red":       { top: [255, 122, 112], bottom: [238, 72, 62],  ink: [196, 42, 38] },
    "Purple":    { top: [194, 146, 236], bottom: [160, 98, 216], ink: [124, 64, 180] },
    "Gray":      { top: [208, 208, 212], bottom: [172, 172, 178], ink: [132, 132, 138] },
    "Dark Gray": { top: [112, 112, 118], bottom: [78, 78, 84],   ink: [46, 46, 52] }
};

function _mix(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; }

function accentPalette(rgb) { // rgb 0..255
    return { top: _mix(rgb, [255, 255, 255], 0.28), bottom: rgb, ink: _mix(rgb, [0, 0, 0], 0.2) };
}

// Returns {top, bottom, ink: [r,g,b] 0..1, spectrum: bool, shadow: amount}
function palette(colour, dark, accentRgb) {
    var p;
    if (colour === "Spectrum") {
        if (dark) return { top: [0.105, 0.105, 0.11], bottom: [0.04, 0.04, 0.045], ink: [1, 1, 1], spectrum: true, shadow: 0.0, sat: 0.78, val: 1.0 };
        return { top: [0.965, 0.965, 0.965], bottom: [0.86, 0.86, 0.87], ink: [0, 0, 0], spectrum: true, shadow: 0.16, sat: 0.86, val: 0.93 };
    }
    p = colour === "Accent" ? accentPalette(accentRgb) : (PALETTE[colour] || PALETTE["Blue"]);
    function n(c) { return [c[0] / 255, c[1] / 255, c[2] / 255]; }
    if (dark) {
        var inkD = colour === "Dark Gray" ? [150, 150, 158] : p.bottom;
        return { top: [0.105, 0.105, 0.11], bottom: [0.04, 0.04, 0.045], ink: n(inkD), spectrum: false, shadow: 0.0, sat: 0, val: 0 };
    }
    return { top: n(p.top), bottom: n(p.bottom), ink: n(p.ink), spectrum: false, shadow: 0.2, sat: 0, val: 0 };
}

// Analog clock faces drawn in the scene images. Their hands are redrawn with the
// current time: (x,y) centre pixel, r = radius of the face interior that is cleared,
// m / h = minute / hour hand lengths (image pixels).
var CLOCK_FACES = {
    System6ControlPanel: [ { x: 311, y: 154, r: 6.6, m: 6, h: 4 } ],
    IconGarden: [ { x: 299, y: 245, r: 4.6, m: 4, h: 3 } ]
};

// Pixels for one clock face: [[x, y, ink], ...] relative to the face bounding box origin.
function clockPixels(face, hours, minutes) {
    var R = Math.ceil(face.r), out = [], x, y;
    for (y = -R; y <= R; ++y)
        for (x = -R; x <= R; ++x)
            if (x * x + y * y <= face.r * face.r) out.push([x + R, y + R, 0]);
    function hand(len, ang) {
        var x1 = Math.round(len * Math.sin(ang)), y1 = Math.round(-len * Math.cos(ang));
        var x0 = 0, y0 = 0, dx = Math.abs(x1), dy = -Math.abs(y1);
        var sx = x1 > 0 ? 1 : -1, sy = y1 > 0 ? 1 : -1, err = dx + dy;
        for (var n = 0; n < 64; ++n) {
            out.push([x0 + R, y0 + R, 1]);
            if (x0 === x1 && y0 === y1) break;
            var e2 = 2 * err;
            if (e2 >= dy) { err += dy; x0 += sx; }
            if (e2 <= dx) { err += dx; y0 += sy; }
        }
    }
    hand(face.h, ((hours % 12) + minutes / 60) / 12 * 2 * Math.PI);
    hand(face.m, minutes / 60 * 2 * Math.PI);
    return out;
}
