// Window memory (kde-macos-parity): KWin 6.8 applies a "Remember" window rule's stored position
// when a window opens, but on Wayland it never writes one back to kwinrulesrc, so after a restart
// every window opens on the active screen. This reports a window's geometry after the user moves
// or resizes it, maximizes it, sends it to another screen, and when it closes; the window-memory
// service writes it into the matching rule.
const SETTLE_MS = 3000;   // ignore the opening placement (rules, maximize at open)
const opened = new Map();

function report(w, closing) {
    if (!w || !w.normalWindow || w.transient || w.fullScreen || w.minimized || !w.resourceClass) {
        return;
    }
    if (Date.now() - (opened.get(w) || 0) < SETTLE_MS) {
        return;
    }
    const g = w.frameGeometry;
    const msg = [w.resourceClass, Math.round(g.x), Math.round(g.y), Math.round(g.width), Math.round(g.height),
                 w.maximizeMode, w.output ? w.output.name : "", closing ? 1 : 0].join("|");
    callDBus("net.local.WindowMemory", "/net/local/WindowMemory", "net.local.WindowMemory", "Save", msg);
}

function watch(w, isNew) {
    opened.set(w, isNew ? Date.now() : 0);
    w.interactiveMoveResizeFinished.connect(() => report(w));
    w.maximizedChanged.connect(() => report(w));
    w.outputChanged.connect(() => report(w));
}

workspace.windowList().forEach(w => watch(w, false));
workspace.windowAdded.connect(w => watch(w, true));
workspace.windowRemoved.connect(w => { report(w, true); opened.delete(w); });
