// Plasma scripting (qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat this)").
// Idempotent: on every top panel, adds Mac Stats, Control Center and Spotlight (appended; reorder with
// AppletOrder, see AGENTS.md), sets the Apple-logo launcher icon, and hides tray items behind the chevron.
// Cmd+Space (Ctrl+Space after the Cmd/Ctrl swap) goes to the Spotlight on the first top panel.
var out = [];
var first = true;
panels().forEach(function (p) {
    if (p.location !== "top") return;
    ["net.local.macstats", "net.local.controlcenter", "net.local.spotlight"].forEach(function (id) {
        if (!p.widgets(id).length) { p.addWidget(id); out.push("panel " + p.id + ": added " + id); }
    });
    p.widgets("org.kde.plasma.kickoff").forEach(function (w) {
        w.currentConfigGroup = ["General"]; w.writeConfig("icon", "start-here-kde-symbolic");
    });
    p.widgets("org.kde.plasma.systemtray").forEach(function (t) {
        t.currentConfigGroup = ["General"];
        var known = t.readConfig("knownItems", "");
        if (known) { t.writeConfig("hiddenItems", known); t.writeConfig("shownItems", ""); out.push("panel " + p.id + ": tray items hidden"); }
    });
    var s = p.widgets("net.local.spotlight")[0];
    if (s && first) { s.globalShortcut = "Ctrl+Space"; first = false; out.push("panel " + p.id + ": Spotlight = Cmd+Space"); }
});
print(out.join("\n") || "nothing to do");
