.pragma library
.import "Assets.js" as A

// Interpreter for Apple's Macintosh wallpaper ".program" scene scripts
// (WallpaperMacintoshExtension.appex). Programs are parsed at runtime.
//
// Coordinates are in 512x342 screen-image pixels, y down. Objects added with
// "add ... at x,y" are anchored at their bottom-left pixel (verified against
// Apple's images: radio buttons line up exactly), cursors at their hotspot.
//
// Timing model: statements run sequentially on a virtual clock. A command with
// "over N seconds" blocks until it finishes, unless it is "async" or inside a
// "start simultaneous ... end simultaneous" batch. Unknown commands are logged
// and skipped.

var CURVES = {
    linear: function (t) { return t; },
    easein: function (t) { return t * t * t; },
    easeout: function (t) { return 1 - Math.pow(1 - t, 3); },
    easeinout: function (t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }
};

// ---------------------------------------------------------------------------- parsing

function tokenize(line) {
    var re = /"([^"]*)"|(-?\d+(?:\.\d+)?|-?\.\d+)|([A-Za-z_][A-Za-z0-9_]*)|(,|=|:)|(\S)/g;
    var out = [], m;
    while ((m = re.exec(line)) !== null) {
        if (m[1] !== undefined) out.push({ t: "str", v: m[1] });
        else if (m[2] !== undefined) out.push({ t: "num", v: parseFloat(m[2]) });
        else if (m[3] !== undefined) out.push({ t: "word", v: m[3].toLowerCase(), raw: m[3] });
        else if (m[4] !== undefined) out.push({ t: "sym", v: m[4] });
        else out.push({ t: "junk", v: m[5] });
    }
    return out;
}

function stripComment(line) {
    var inStr = false;
    for (var i = 0; i < line.length - 1; ++i) {
        var c = line[i];
        if (c === '"') inStr = !inStr;
        else if (!inStr && c === "/" && line[i + 1] === "/") return line.substring(0, i);
    }
    return line;
}

function parse(text, name) {
    var lines = String(text).split(/\r?\n/);
    var stmts = [], labels = {};
    for (var i = 0; i < lines.length; ++i) {
        var s = stripComment(lines[i]).trim();
        if (!s) continue;
        var lm = /^([A-Za-z_][A-Za-z0-9_]*)\s*:$/.exec(s);
        if (lm) { labels[lm[1].toLowerCase()] = stmts.length; continue; }
        stmts.push({ line: i + 1, text: s, tok: tokenize(s) });
    }
    return { name: name, stmts: stmts, labels: labels };
}

function Args(tok) { this.tok = tok; this.i = 0; }
Args.prototype.peek = function () { return this.tok[this.i]; };
Args.prototype.more = function () { return this.i < this.tok.length; };
Args.prototype.word = function (w) {
    var t = this.tok[this.i];
    if (t && t.t === "word" && t.v === w) { this.i++; return true; }
    return false;
};
Args.prototype.expect = function (w) { if (!this.word(w)) throw "expected '" + w + "'"; };
Args.prototype.anyWord = function () {
    var t = this.tok[this.i];
    if (t && t.t === "word") { this.i++; return t.v; }
    throw "expected a word";
};
Args.prototype.num = function () {
    var t = this.tok[this.i];
    if (t && t.t === "num") { this.i++; return t.v; }
    throw "expected a number";
};
Args.prototype.str = function () {
    var t = this.tok[this.i];
    if (t && t.t === "str") { this.i++; return t.v; }
    throw "expected a string";
};
Args.prototype.value = function () {
    var t = this.tok[this.i];
    if (!t) throw "expected a value";
    this.i++;
    return t.t === "word" ? t.raw : t.v;
};
Args.prototype.sym = function (c) {
    var t = this.tok[this.i];
    if (t && t.t === "sym" && t.v === c) { this.i++; return true; }
    return false;
};
Args.prototype.pair = function () {
    var a = this.num();
    if (!this.sym(",")) throw "expected ','";
    return [a, this.num()];
};
Args.prototype.seconds = function () {
    var n = this.num();
    this.word("seconds") || this.word("second") || this.word("secs") || this.word("sec") || this.word("s");
    return n;
};

function parseOpts(a) {
    var o = {};
    while (a.more()) {
        if (a.word("over")) o.over = a.seconds();
        else if (a.word("async")) o.async = a.str();
        else if (a.word("curve")) o.curve = a.anyWord();
        else if (a.word("value")) { var t = a.peek(); o.value = (t && t.t === "str") ? a.str() : a.num(); }
        else if (a.word("name")) o.name = a.str();
        else if (a.word("size")) o.size = a.pair();
        else if (a.word("action")) o.action = a.str();
        else if (a.word("at")) o.at = a.pair();
        else if (a.word("frames")) o.frames = a.str();
        else {
            var bad = a.peek();
            throw "unexpected '" + (bad.raw || bad.v) + "'";
        }
    }
    return o;
}

// ---------------------------------------------------------------------------- machine

var NUM_KEYS = ["scale", "roll", "tilt", "scrollX", "scrollY", "mouseX", "mouseY"];

function Machine(host, program) {
    this.host = host;
    this.prog = program;
    this.t = 0;            // virtual clock (seconds)
    this.waitUntil = 0;    // time at which the next statement runs
    this.pc = 0;
    this.stack = [];
    this.batch = false;
    this.done = false;
    this.state = {
        image: "", cursor: "None", ramp: "None", scene: "",
        scale: 0, roll: 0, tilt: 0, scrollX: 256, scrollY: 171,
        mouseX: 256, mouseY: 171, mouseDown: false
    };
    this.tweens = {};
    this.named = {};
    this.controls = [];
    this.group = 0;
    this.active = null;
    this.caretRate = 32;   // ticks per caret blink phase
    this.hour24 = false;
    this.cursorRects = [];
    this.calc = "0";
    this.lastPaint = null;
    this._cursorKey = "";
    this._ticks = -1;
}

Machine.prototype.log = function (msg) { this.host.hostLog(this.prog.name + ": " + msg); };

Machine.prototype.valueAt = function (key, t) {
    var tw = this.tweens[key];
    if (!tw) return this.state[key];
    var p = tw.dur > 0 ? Math.max(0, Math.min(1, (t - tw.t0) / tw.dur)) : 1;
    return tw.from + (tw.to - tw.from) * tw.curve(p);
};

Machine.prototype.updateTweens = function (t) {
    for (var i = 0; i < NUM_KEYS.length; ++i) {
        var k = NUM_KEYS[i], tw = this.tweens[k];
        if (!tw) continue;
        this.state[k] = this.valueAt(k, t);
        if (t >= tw.t0 + tw.dur) delete this.tweens[k];
    }
};

Machine.prototype.animate = function (keys, targets, o, cur, defCurve) {
    var dur = o.over || 0;
    var curve = CURVES[o.curve] || CURVES[defCurve] || CURVES.linear;
    if (o.curve && !CURVES[o.curve]) this.log("unknown curve '" + o.curve + "', using " + defCurve);
    var rec = { t0: cur, dur: dur };
    for (var i = 0; i < keys.length; ++i) {
        if (dur <= 0) {
            delete this.tweens[keys[i]];
            this.state[keys[i]] = targets[i];
        } else {
            this.tweens[keys[i]] = { from: this.valueAt(keys[i], cur), to: targets[i], t0: cur, dur: dur, curve: curve };
        }
    }
    if (o.async) this.named[o.async] = rec;
    else if (dur > 0 && !this.batch) this.waitUntil = cur + dur;
};

Machine.prototype.step = function (dt) {
    this.t += Math.max(0, dt);
    var guard = 0;
    while (!this.done && this.waitUntil <= this.t && guard++ < 2000) {
        this.updateTweens(this.waitUntil);
        this.exec(this.waitUntil);
    }
    if (guard >= 2000) { this.log("runaway program (no waits?) - stopping"); this.finish(); }
    this.updateTweens(this.t);
    this.interact();
    this.animateControls();
    this.updateCursor();
};

Machine.prototype.finish = function () {
    if (this.done) return;
    this.done = true;
    this.host.hostProgramDone();
};

Machine.prototype.exec = function (cur) {
    if (this.pc >= this.prog.stmts.length) { this.finish(); return; }
    var st = this.prog.stmts[this.pc++];
    try {
        this.run(st, cur);
    } catch (e) {
        this.log("line " + st.line + ": " + e + " - skipped: " + st.text);
    }
};

Machine.prototype.run = function (st, cur) {
    var a = new Args(st.tok);
    var cmd = a.anyWord(), o, p, n;
    switch (cmd) {
    case "start":
        a.expect("simultaneous");
        this.batch = true;
        break;
    case "end":
        a.expect("simultaneous");
        this.batch = false;
        break;
    case "scale": {
        var dir = a.anyWord();
        if (dir !== "in" && dir !== "out") throw "scale must be 'in' or 'out'";
        o = parseOpts(a);
        this.animate(["scale"], [dir === "in" ? 1 : 0], o, cur, "easeinout");
        break;
    }
    case "let": {
        var key = a.anyWord();
        if (!a.sym("=")) throw "expected '='";
        this.setVar(key, a.value());
        break;
    }
    case "add":
        this.addControl(a.anyWord(), parseOpts(a));
        return;
    case "camera":
        a.expect("to");
        p = a.pair();
        o = parseOpts(a);
        this.animate(["roll", "tilt"], [p[0], p[1]], o, cur, "easeinout");
        break;
    case "scroll":
        a.expect("to");
        p = a.pair();
        o = parseOpts(a);
        this.animate(["scrollX", "scrollY"], [p[0], p[1]], o, cur, "linear");
        break;
    case "reset":
        a.expect("controls");
        this.resetControls();
        break;
    case "remove": // authored extension: drop all controls (used between sub-scenes)
        a.expect("controls");
        this.controls = [];
        this.cursorRects = [];
        this.active = null;
        this.host.hostClearControls();
        break;
    case "wait":
        if (a.word("for")) {
            n = a.seconds();
            this.waitUntil = cur + Math.max(0, n);
        } else if (a.word("until")) {
            n = a.seconds();
            a.expect("before");
            var nm = a.str();
            a.expect("completes");
            var rec = this.named[nm];
            if (!rec) this.log("wait until: no async action named '" + nm + "'");
            else this.waitUntil = Math.max(cur, rec.t0 + rec.dur - n);
        } else throw "expected 'for' or 'until'";
        break;
    case "mouse":
        if (a.word("to")) {
            p = a.pair();
            o = parseOpts(a);
            this.animate(["mouseX", "mouseY"], [p[0], p[1]], o, cur, "linear");
        } else if (a.word("down")) {
            this.mouseDown(cur);
        } else if (a.word("up")) {
            this.mouseUp(cur);
        } else if (a.word("click")) {
            this.mouseDown(cur);
            this.mouseUp(cur);
        } else throw "expected to/down/up/click";
        break;
    case "gosub": {
        var label = a.anyWord();
        if (this.prog.labels[label] === undefined) throw "unknown label '" + label + "'";
        if (this.stack.length > 64) throw "gosub nesting too deep";
        this.stack.push(this.pc);
        this.pc = this.prog.labels[label];
        break;
    }
    case "goto": {
        var l2 = a.anyWord();
        if (this.prog.labels[l2] === undefined) throw "unknown label '" + l2 + "'";
        this.pc = this.prog.labels[l2];
        break;
    }
    case "return":
        if (this.stack.length === 0) this.finish();
        else this.pc = this.stack.pop();
        break;
    case "exit":
        this.finish();
        break;
    default:
        throw "unknown command '" + cmd + "'";
    }
    if (a.more()) this.log("line " + st.line + ": ignoring trailing tokens in: " + st.text);
};

Machine.prototype.setVar = function (key, v) {
    switch (key) {
    case "image":
        this.state.image = String(v);
        this.host.hostSetImage(this.state.image);
        break;
    case "cursor": this.state.cursor = String(v); break;
    case "ramp": this.state.ramp = String(v); break;
    case "scene": this.state.scene = String(v); break;
    default:
        this.log("unknown variable '" + key + "' ignored");
    }
};

// ---------------------------------------------------------------------------- controls

function baseItem() {
    return { kind: "", src: "", cx: 0, cy: 0, cw: 0, ch: 0, fw: 0, fh: 0, frame: 0,
             shown: true, inv: false, text: "", perm: "" };
}

Machine.prototype.newControl = function (c, item) {
    var it = baseItem();
    for (var k in item) it[k] = item[k];
    c.item = it;
    c.index = this.host.hostAddControl(it);
    this.controls.push(c);
    return c;
};

Machine.prototype.setItem = function (c, props) {
    var changed = {}, any = false;
    for (var k in props) {
        if (c.item[k] !== props[k]) { c.item[k] = props[k]; changed[k] = props[k]; any = true; }
    }
    if (any && c.index >= 0) this.host.hostSetControl(c.index, changed);
};

function sprite(name) {
    var s = A.SPRITES[name];
    if (!s) throw "unknown sprite '" + name + "'";
    return s;
}

Machine.prototype.addControl = function (kind, o) {
    var at = o.at || [0, 0], s, c;
    switch (kind) {
    case "icon":
        s = sprite(o.name);
        var seq = [];
        if (o.frames) seq = o.frames.split(",").map(function (x) { return parseInt(x, 10); })
                                     .filter(function (x) { return x >= 0 && x < s.frames; });
        if (!seq.length) for (var fi = 0; fi < s.frames; ++fi) seq.push(fi);
        this.newControl({ kind: kind, period: o.value || 30, seq: seq },
                        { kind: "sprite", src: o.name, cx: at[0], cy: at[1] - s.fh + 1, cw: s.fw, ch: s.fh, fw: s.fw, fh: s.fh });
        break;
    case "caret": {
        var sz = o.size || [1, 15];
        this.newControl({ kind: kind }, { kind: "rect", cx: at[0], cy: at[1] - sz[1] + 1, cw: sz[0], ch: sz[1], inv: true });
        break;
    }
    case "cursor": {
        var cu = A.CURSORS[o.name];
        if (!cu) throw "unknown cursor '" + o.name + "'";
        this.newControl({ kind: kind, cur: cu },
                        { kind: "sprite", src: "Cursors", cx: at[0] - cu.hx, cy: at[1] - cu.hy, cw: 16, ch: 16, fw: 16, fh: 16, frame: cu.i });
        break;
    }
    case "radiobuttongroup":
        this.group++;
        break;
    case "radiobutton":
        s = sprite(o.name || "RadioButton");
        c = this.newControl({ kind: "radio", group: this.group, init: !!o.value, selected: !!o.value, pressed: false,
                              action: o.action || "", rx: at[0], ry: at[1] - s.fh + 1, rw: s.fw, rh: s.fh },
                            { kind: "sprite", src: o.name || "RadioButton", cx: at[0], cy: at[1] - s.fh + 1, cw: s.fw, ch: s.fh, fw: s.fw, fh: s.fh });
        this.refreshSelectable(c);
        if (c.selected) this.action(c.action);
        break;
    case "selectable": { // authored extension: list item / icon that inverts when selected
        var ss = o.size || [16, 16];
        c = this.newControl({ kind: "selectable", group: this.group, init: !!o.value, selected: !!o.value, pressed: false,
                              action: o.action || "", rx: at[0], ry: at[1] - ss[1] + 1, rw: ss[0], rh: ss[1] },
                            { kind: "rect", cx: at[0], cy: at[1] - ss[1] + 1, cw: ss[0], ch: ss[1], inv: false });
        this.refreshSelectable(c);
        break;
    }
    case "button": { // authored extension: momentary push button (sprite frame 1 or inverted while pressed)
        if (o.name) {
            s = sprite(o.name);
            this.newControl({ kind: "button", pressed: false, action: o.action || "", useSprite: true,
                              rx: at[0], ry: at[1] - s.fh + 1, rw: s.fw, rh: s.fh },
                            { kind: "sprite", src: o.name, cx: at[0], cy: at[1] - s.fh + 1, cw: s.fw, ch: s.fh, fw: s.fw, fh: s.fh });
        } else {
            var bs = o.size || [16, 16];
            this.newControl({ kind: "button", pressed: false, action: o.action || "", useSprite: false,
                              rx: at[0], ry: at[1] - bs[1] + 1, rw: bs[0], rh: bs[1] },
                            { kind: "rect", cx: at[0], cy: at[1] - bs[1] + 1, cw: bs[0], ch: bs[1], inv: false });
        }
        break;
    }
    case "slider": {
        s = sprite("Slider");
        var v0 = (o.value !== undefined) ? o.value : 2;
        c = this.newControl({ kind: "slider", bx: at[0], by: at[1], init: v0, value: v0, dragOffset: 0 },
                            { kind: "sprite", src: "Slider", cx: at[0], cy: 0, cw: s.fw, ch: s.fh, fw: s.fw, fh: s.fh });
        this.placeSlider(c);
        break;
    }
    case "time":
    case "date":
    case "display":
        this.newControl({ kind: kind, ax: at[0], by: at[1], font: o.name || "Geneva12" },
                        // y is the top of the text line (Geneva 12 ascent is 2 px above cap height)
                        { kind: "text", cx: at[0], cy: at[1] + 2, cw: 0, ch: 7 });
        break;
    case "cursorrect": {
        var cs = o.size || [0, 0];
        this.cursorRects.push({ x: at[0], y: at[1] - cs[1] + 1, w: cs[0], h: cs[1], name: o.name || "Arrow" });
        break;
    }
    case "puzzle": { // authored extension: 4x4 sliding puzzle (Desk Accessory)
        var perm = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0];
        c = this.newControl({ kind: "puzzle", period: o.value || 40, perm: perm, last: -1, init: null, moves: 0 },
                            { kind: "puzzle", src: "PuzzleTiles", cx: at[0], cy: at[1] - 78, cw: 79, ch: 79 });
        for (var i = 0; i < 80; ++i) this.puzzleMove(c);
        c.init = c.perm.slice();
        this.setItem(c, { perm: c.perm.join(",") });
        break;
    }
    case "canvas": { // authored extension: MacPaint pencil area (mouse down draws)
        var ps = o.size || [0, 0];
        this.newControl({ kind: "canvas", rx: at[0], ry: at[1] - ps[1] + 1, rw: ps[0], rh: ps[1] }, { kind: "none" });
        break;
    }
    case "menu": { // authored extension: pull-down menu shown while the mouse is held on its title
        s = sprite(o.name);
        var ms = o.size || [s.fw, 18];
        this.newControl({ kind: "menu", rx: at[0], ry: at[1] - ms[1] + 1, rw: ms[0], rh: ms[1] },
                        { kind: "sprite", src: o.name, cx: at[0], cy: at[1] - ms[1] + 1, cw: s.fw, ch: s.fh, fw: s.fw, fh: s.fh, shown: false });
        break;
    }
    default:
        throw "unknown control '" + kind + "'";
    }
};

Machine.prototype.placeSlider = function (c) {
    // Knob centre sits on tick v: (by - 5) - 12 v  (System 6 speaker volume, 0..7)
    this.setItem(c, { cy: Math.round(c.by - 10 - 12 * c.value) });
};

Machine.prototype.refreshSelectable = function (c) {
    if (c.kind === "radio") this.setItem(c, { frame: (c.selected ? 2 : 0) + (c.pressed ? 1 : 0) });
    else this.setItem(c, { inv: c.selected || c.pressed });
};

Machine.prototype.resetControls = function () {
    for (var i = 0; i < this.controls.length; ++i) {
        var c = this.controls[i];
        if (c.kind === "radio" || c.kind === "selectable") {
            c.selected = c.init; c.pressed = false;
            this.refreshSelectable(c);
            if (c.selected && c.action) this.action(c.action);
        } else if (c.kind === "slider") {
            c.value = c.init; this.placeSlider(c);
        } else if (c.kind === "button") {
            c.pressed = false;
            this.setItem(c, c.useSprite ? { frame: 0 } : { inv: false });
        } else if (c.kind === "menu") {
            this.setItem(c, { shown: false });
        } else if (c.kind === "puzzle" && c.init) {
            c.perm = c.init.slice(); c.last = -1;
            this.setItem(c, { perm: c.perm.join(",") });
        }
    }
    this.calc = "0";
    this.host.hostClearPaint();
    this.active = null;
};

Machine.prototype.action = function (name) {
    if (!name) return;
    switch (name) {
    case "caretSlow": this.caretRate = 48; break;
    case "caretNormal": this.caretRate = 32; break;
    case "caretFast": this.caretRate = 16; break;
    case "time12Hour": this.hour24 = false; break;
    case "time24Hour": this.hour24 = true; break;
    default:
        if (name.indexOf("calc:") === 0) {
            var k = name.substring(5);
            if (/^[0-9]$/.test(k)) this.calc = (this.calc === "0" ? "" : this.calc) + k;
            else if (k === ".") { if (this.calc.indexOf(".") < 0) this.calc += "."; }
            else this.calc = "0";
            if (this.calc.length > 12) this.calc = this.calc.substring(this.calc.length - 12);
        }
        // other actions (e.g. sound names) are cosmetic only
    }
};

function inside(c, x, y) {
    return x >= c.rx && x < c.rx + c.rw && y >= c.ry && y < c.ry + c.rh;
}

Machine.prototype.mouseDown = function (cur) {
    var mx = this.valueAt("mouseX", cur), my = this.valueAt("mouseY", cur);
    this.state.mouseDown = true;
    this.active = null;
    for (var i = this.controls.length - 1; i >= 0; --i) {
        var c = this.controls[i];
        if (c.kind === "slider") {
            var top = c.by - 10 - 12 * c.value;
            if (mx >= c.bx - 2 && mx < c.bx + 25 && my >= top - 3 && my < top + 14) {
                c.dragOffset = (top + 5) - my;
                this.active = c;
                break;
            }
        } else if (c.rw !== undefined && inside(c, mx, my)) {
            this.active = c;
            break;
        }
    }
    var a = this.active;
    if (!a) return;
    if (a.kind === "radio" || a.kind === "selectable") { a.pressed = true; this.refreshSelectable(a); }
    else if (a.kind === "button") { a.pressed = true; this.setItem(a, a.useSprite ? { frame: 1 } : { inv: true }); }
    else if (a.kind === "menu") this.setItem(a, { shown: true });
    else if (a.kind === "canvas") { this.lastPaint = [Math.round(mx), Math.round(my)]; this.plot(a, [this.lastPaint]); }
};

Machine.prototype.interact = function () {
    var a = this.active;
    if (!a || !this.state.mouseDown) return;
    var mx = this.state.mouseX, my = this.state.mouseY;
    if (a.kind === "radio" || a.kind === "selectable") {
        var p = inside(a, mx, my);
        if (p !== a.pressed) { a.pressed = p; this.refreshSelectable(a); }
    } else if (a.kind === "button") {
        var pb = inside(a, mx, my);
        if (pb !== a.pressed) { a.pressed = pb; this.setItem(a, a.useSprite ? { frame: pb ? 1 : 0 } : { inv: pb }); }
    } else if (a.kind === "slider") {
        var v = (a.by - 5 - (my + a.dragOffset)) / 12;
        a.value = Math.max(0, Math.min(7, v));
        this.placeSlider(a);
    } else if (a.kind === "canvas") {
        var x1 = Math.round(mx), y1 = Math.round(my);
        if (this.lastPaint && (x1 !== this.lastPaint[0] || y1 !== this.lastPaint[1])) {
            this.plot(a, line(this.lastPaint[0], this.lastPaint[1], x1, y1));
            this.lastPaint = [x1, y1];
        }
    }
};

Machine.prototype.mouseUp = function (cur) {
    this.state.mouseX = this.valueAt("mouseX", cur);
    this.state.mouseY = this.valueAt("mouseY", cur);
    this.interact();
    var a = this.active;
    this.state.mouseDown = false;
    this.active = null;
    this.lastPaint = null;
    if (!a) return;
    if (a.kind === "radio" || a.kind === "selectable") {
        if (a.pressed) {
            for (var i = 0; i < this.controls.length; ++i) {
                var o = this.controls[i];
                if ((o.kind === "radio" || o.kind === "selectable") && o.group === a.group && o !== a && o.selected) {
                    o.selected = false; this.refreshSelectable(o);
                }
            }
            a.selected = true;
            this.action(a.action);
        }
        a.pressed = false;
        this.refreshSelectable(a);
    } else if (a.kind === "button") {
        if (a.pressed) this.action(a.action);
        a.pressed = false;
        this.setItem(a, a.useSprite ? { frame: 0 } : { inv: false });
    } else if (a.kind === "slider") {
        a.value = Math.round(a.value);
        this.placeSlider(a);
    } else if (a.kind === "menu") {
        this.setItem(a, { shown: false });
    }
};

function line(x0, y0, x1, y1) {
    var pts = [], dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0);
    var sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx + dy, guard = 0;
    while (guard++ < 2048) {
        pts.push([x0, y0]);
        if (x0 === x1 && y0 === y1) break;
        var e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
    }
    return pts;
}

Machine.prototype.plot = function (c, pts) {
    var keep = [];
    for (var i = 0; i < pts.length; ++i) {
        var p = pts[i];
        if (p[0] >= c.rx && p[0] < c.rx + c.rw && p[1] >= c.ry && p[1] < c.ry + c.rh) keep.push(p);
    }
    if (keep.length) this.host.hostPaint(keep);
};

Machine.prototype.puzzleMove = function (c) {
    var b = c.perm.indexOf(0), r = Math.floor(b / 4), col = b % 4, opts = [];
    if (r > 0) opts.push(b - 4);
    if (r < 3) opts.push(b + 4);
    if (col > 0) opts.push(b - 1);
    if (col < 3) opts.push(b + 1);
    var choices = opts.filter(function (x) { return x !== c.last; });
    var m = choices[Math.floor(Math.random() * choices.length)];
    c.perm[b] = c.perm[m];
    c.perm[m] = 0;
    c.last = b;
};

function pad2(n) { return (n < 10 ? "0" : "") + n; }

Machine.prototype.timeString = function () {
    var d = new Date(), h = d.getHours();
    if (this.hour24) return h + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds());
    var ap = h >= 12 ? "PM" : "AM";
    h = h % 12; if (h === 0) h = 12;
    return h + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds()) + " " + ap;
};

Machine.prototype.dateString = function () {
    var d = new Date();
    return (d.getMonth() + 1) + "/" + d.getDate() + "/" + pad2(d.getFullYear() % 100);
};

Machine.prototype.animateControls = function () {
    var ticks = Math.floor(this.t * 60);
    if (ticks === this._ticks) return;
    this._ticks = ticks;
    for (var i = 0; i < this.controls.length; ++i) {
        var c = this.controls[i];
        switch (c.kind) {
        case "icon":
            this.setItem(c, { frame: c.seq[Math.floor(ticks / Math.max(1, c.period)) % c.seq.length] });
            break;
        case "cursor":
            if (c.cur.n > 1) this.setItem(c, { frame: c.cur.i + Math.floor(ticks / c.cur.period) % c.cur.n });
            break;
        case "caret":
            this.setItem(c, { inv: Math.floor(ticks / this.caretRate) % 2 === 0 });
            break;
        case "time":
        case "date":
        case "display": {
            var s = c.kind === "time" ? this.timeString() : (c.kind === "date" ? this.dateString() : this.calc);
            var w = A.textWidth(s);
            this.setItem(c, { text: s, cw: w, cx: c.kind === "display" ? c.ax - w : c.ax });
            break;
        }
        case "puzzle": {
            var mv = Math.floor(ticks / c.period);
            if (mv !== c.moves) {
                c.moves = mv;
                this.puzzleMove(c);
                this.setItem(c, { perm: c.perm.join(",") });
            }
            break;
        }
        }
    }
};

Machine.prototype.updateCursor = function () {
    var name = "";
    var mode = this.state.cursor;
    var mx = this.state.mouseX, my = this.state.mouseY;
    if (mode === "Automatic") {
        name = "Arrow";
        for (var i = this.cursorRects.length - 1; i >= 0; --i) {
            var r = this.cursorRects[i];
            if (mx >= r.x && mx < r.x + r.w && my >= r.y && my < r.y + r.h) { name = r.name; break; }
        }
    } else if (mode && mode !== "None") {
        name = A.CURSORS[mode] ? mode : "Arrow";
    }
    var frame = 0, hx = 0, hy = 0;
    if (name) {
        var cu = A.CURSORS[name];
        if (!cu) { cu = A.CURSORS.Arrow; }
        frame = cu.i + (cu.n > 1 ? Math.floor(this._ticks / cu.period) % cu.n : 0);
        hx = cu.hx; hy = cu.hy;
    }
    var x = Math.round(mx) - hx, y = Math.round(my) - hy;
    var key = name + ":" + x + ":" + y + ":" + frame;
    if (key !== this._cursorKey) {
        this._cursorKey = key;
        this.host.hostCursor(name, x, y, frame);
    }
};
