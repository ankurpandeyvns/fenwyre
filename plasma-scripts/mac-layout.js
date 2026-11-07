// Plasma scripting (qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat this)").
// Idempotent: on every top panel, adds Mac Stats, battery, volume, Control Center and Spotlight (appended;
// reorder with AppletOrder, see AGENTS.md), sets the Apple-logo launcher icon, removes the tray chevron and
// sets the macOS clock format. Make the bars clear: set panelOpacity=1 (opaque) for top panels in
// plasmashellrc; plasma-sync-glass makes the theme's solid panel background fully transparent.
// Cmd+Space (Ctrl+Space after the Cmd/Ctrl swap) goes to the Spotlight on the first top panel.
var out = [];
var first = true;
panels().forEach(function (p) {
    if (p.location !== "top") return;
    ["net.local.macstats", "org.kde.plasma.battery", "net.local.volume", "net.local.controlcenter", "net.local.spotlight"].forEach(function (id) {
        if (!p.widgets(id).length) { p.addWidget(id); out.push("panel " + p.id + ": added " + id); }
    });
    p.widgets("org.kde.plasma.kickoff").forEach(function (w) {
        w.currentConfigGroup = ["General"]; w.writeConfig("icon", "start-here-kde-symbolic");
    });
    // macOS menu bar: no chevron. The tray keeps only notifications (needed for popups) and app icons;
    // battery and volume sit on the bar as their own widgets.
    p.widgets("org.kde.plasma.systemtray").forEach(function (t) {
        t.currentConfigGroup = ["General"];
        t.writeConfig("extraItems", "org.kde.plasma.notifications");
        t.writeConfig("hiddenItems", ""); t.writeConfig("shownItems", ""); t.writeConfig("showAllItems", true);
    });
    p.widgets("org.kde.plasma.digitalclock").forEach(function (c) {   // "Nov 8  3:04 AM"
        c.currentConfigGroup = ["Appearance"];
        c.writeConfig("showDate", true); c.writeConfig("dateFormat", "custom");
        c.writeConfig("customDateFormat", "MMM d"); c.writeConfig("dateDisplayFormat", "BesideTime");
    });
    var s = p.widgets("net.local.spotlight")[0];
    if (s && first) { s.globalShortcut = "Ctrl+Space"; first = false; out.push("panel " + p.id + ": Spotlight = Cmd+Space"); }
});
print(out.join("\n") || "nothing to do");
