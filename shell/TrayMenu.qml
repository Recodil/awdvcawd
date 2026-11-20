import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Значки программ из трея. Два вида: все значки (под стрелкой) и меню одного значка.
// Меню рисует сама оболочка (TrayEntries.qml), поэтому оно открывается у любой программы.
Flyout {
    id: root
    name: "tray"
    role: "bar"
    px: Ui.trayPos.x
    py: Ui.trayPos.y

    property var item: Ui.trayItem            // значок, меню которого открыто
    readonly property int count: Ui.trayItems.length
    readonly property int cols: Math.max(1, Math.min(4, count))
    readonly property real menuHeight: (entries.item && entries.item.implicitHeight > 0) ? entries.item.implicitHeight : 44
    panelWidth: item ? 280 : cols * 40 + 16
    panelHeight: item ? Math.min(520, menuHeight + (Ui.trayItem === null ? 44 : 8)) : Math.max(1, Math.ceil(count / cols)) * 40 + 16

    Connections { target: Ui; function onTrayItemChanged() { root.item = Ui.trayItem; } }
    onOpened: item = Ui.trayItem

    function press(it, mouse) {
        if (mouse.button === Qt.LeftButton && !it.onlyMenu) { it.activate(); Ui.close(); }
        else if (it.hasMenu) item = it;
        else { it.activate(); Ui.close(); }
    }

    // ---- все значки ----
    Grid {
        visible: root.item === null
        anchors.centerIn: parent
        columns: root.cols
        Repeater {
            model: Ui.trayItems.length
            HoverButton {
                id: tray
                required property int index
                readonly property var modelData: Ui.trayItems[index] || null
                visible: modelData !== null
                implicitWidth: 40; implicitHeight: 40
                IconImage { anchors.centerIn: parent; implicitSize: 18; source: tray.modelData ? tray.modelData.icon : "" }
                onClicked: mouse => { if (modelData) root.press(modelData, mouse); }
            }
        }
    }

    // ---- меню одного значка ----
    Column {
        visible: root.item !== null
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
        MenuRow {
            visible: Ui.trayItem === null        // пришли из общего списка - можно вернуться
            width: parent.width
            icon: Icons.chevronLeft
            label: root.item ? (root.item.tooltipTitle || root.item.title || Tr.t("Назад")) : ""
            onClicked: root.item = null
        }
        Loader {
            id: entries
            width: parent.width
            active: root.item !== null && root.item.hasMenu
            source: "TrayEntries.qml"
            onLoaded: item.handle = Qt.binding(() => root.item ? root.item.menu : null)
        }
    }
}
