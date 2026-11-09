// Plasma scripting (qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat this)").
// Idempotent: on every top panel, adds Mac Stats, battery, volume, Control Center and Spotlight (appended;
// reorder with AppletOrder, see AGENTS.md), sets the Apple-logo launcher icon, removes the tray chevron and
// sets the macOS clock format. Make the bars clear: set panelOpacity=1 (opaque) for top panels in
// plasmashellrc; plasma-sync-glass makes the theme's solid panel background fully transparent.
// Cmd+Space (Ctrl+Space after the Cmd/Ctrl swap) goes to the Spotlight on the first top panel.
// install.sh may prepend `var WANT = [...]` to add only the widgets of the features the user picked, and
// `var SCREENS = [{x, y, w, ppi, notch}]` (logical position/width, logical px per inch, Apple notch shown).
// With SCREENS: the clock font is 10 pt on ordinary screens and shrinks on dense ones (the digital clock sizes
// points by physical density, so 10 pt is ~40% taller on a MacBook than on a desktop monitor), and the bar on
// a notched built-in display is 32 px, under the notch's 37.
if (typeof SCREENS === "undefined")
    var SCREENS = [];
if (typeof WANT === "undefined")
    var WANT = ["net.local.macstats", "org.kde.plasma.battery", "net.local.volume", "net.local.controlcenter", "net.local.spotlight"];
var out = [];
var first = true;
panels().forEach(function (p) {
    if (p.location !== "top") return;
    WANT.forEach(function (id) {
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
    var g = screenGeometry(p.screen), scr = null;
    SCREENS.forEach(function (q) { if (q.x === g.x && q.y === g.y && q.w === g.width) scr = q; });
    if (scr && scr.notch && p.height !== 32) { p.height = 32; out.push("panel " + p.id + ": height 32 (notch)"); }
    p.widgets("org.kde.plasma.digitalclock").forEach(function (c) {   // "Nov 8  3:04 AM"
        c.currentConfigGroup = ["Appearance"];
        c.writeConfig("showDate", true); c.writeConfig("dateFormat", "custom");
        c.writeConfig("customDateFormat", "MMM d"); c.writeConfig("dateDisplayFormat", "BesideTime");
        if (scr) {
            var pt = Math.min(10, Math.round(864 / scr.ppi));   // 10 pt at <= ~86 px/in, scaled down above
            c.writeConfig("autoFontAndSize", false); c.writeConfig("fontSize", pt);
            if (!c.readConfig("fontFamily", "")) {   // fixed size needs a family; macOS menu bar is SF Pro Medium
                c.writeConfig("fontFamily", "SF Pro Text"); c.writeConfig("fontStyleName", "Medium");
                c.writeConfig("fontWeight", 500);
            }
            out.push("panel " + p.id + ": clock " + pt + " pt (" + scr.ppi + " px/in)");
        }
    });
    var s = p.widgets("net.local.spotlight")[0];
    if (s && first) { s.globalShortcut = "Ctrl+Space"; first = false; out.push("panel " + p.id + ": Spotlight = Cmd+Space"); }
});
print(out.join("\n") || "nothing to do");
