import QtQuick
import Quickshell

// Контекстное меню значка на панели задач.
Flyout {
    id: root
    name: "ctx"
    role: info.mode === "point" ? "point" : "bar"
    panelWidth: 264
    panelHeight: menu.implicitHeight + 8
    px: info.x
    py: info.y

    readonly property var info: Ui.ctx || ({ appId: "", entry: null, windows: [], mode: "bar", x: -1, y: -1 })

    AppMenu {
        id: menu
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
        entry: root.info.entry
        appId: root.info.appId
        windows: root.info.windows
        onLaunched: Ui.close()
        onDone: Ui.close()
    }
}
