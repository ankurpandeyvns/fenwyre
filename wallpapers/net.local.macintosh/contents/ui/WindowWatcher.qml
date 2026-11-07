import QtQuick
import org.kde.taskmanager as TaskManager
import org.kde.kwindowsystem as KWindowSystem

// Reports whether a maximized or full-screen window covers this screen on the
// current virtual desktop/activity, so the wallpaper can stop rendering.
Item {
    id: root
    property var screenGeometry
    // true when a maximized/full-screen window is showing (not while "Show Desktop" is active)
    readonly property bool covered: windowCovers && !KWindowSystem.KWindowSystem.showingDesktop
    property bool windowCovers: false

    function update() {
        var hit = false;
        for (var i = 0; i < tasks.count; ++i) {
            var idx = tasks.index(i, 0);
            if (!tasks.data(idx, TaskManager.AbstractTasksModel.IsWindow)) continue;
            if (tasks.data(idx, TaskManager.AbstractTasksModel.IsMinimized)) continue;
            if (tasks.data(idx, TaskManager.AbstractTasksModel.IsMaximized)
                    || tasks.data(idx, TaskManager.AbstractTasksModel.IsFullScreen)) {
                hit = true;
                break;
            }
        }
        windowCovers = hit;
    }

    Timer { id: debounce; interval: 50; onTriggered: root.update() }
    // safety net in case a model update is missed (window moved between screens, etc.)
    Timer { interval: 3000; repeat: true; running: true; onTriggered: root.update() }

    TaskManager.VirtualDesktopInfo { id: vdInfo }
    TaskManager.ActivityInfo { id: actInfo }

    TaskManager.TasksModel {
        id: tasks
        sortMode: TaskManager.TasksModel.SortDisabled
        groupMode: TaskManager.TasksModel.GroupDisabled
        activity: actInfo.currentActivity
        screenGeometry: root.screenGeometry
        filterByScreen: true
        filterByActivity: true
        filterMinimized: true
        onDataChanged: debounce.restart()
        onCountChanged: debounce.restart()
        Component.onCompleted: {
            if (tasks.hasOwnProperty("filterByCurrentVirtualDesktop")) {
                tasks.filterByCurrentVirtualDesktop = true;
            } else {
                tasks.virtualDesktop = Qt.binding(function () { return vdInfo.currentDesktop; });
                tasks.filterByVirtualDesktop = true;
            }
            debounce.restart();
        }
    }
}
