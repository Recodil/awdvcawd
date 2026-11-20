import QtQuick
import Quickshell

// Пункты контекстного меню приложения. Одни и те же на панели задач и в "Пуске".
Column {
    id: root

    property var entry: null
    property string appId: ""
    property var windows: []
    signal launched()       // приложение запущено: меню и его владелец закрываются
    signal done()           // действие выполнено: закрывается только меню

    readonly property string pinId: (entry && entry.id) ? entry.id : appId
    readonly property bool inStart: { Store.pinned; return Store.isPinned(pinId); }
    readonly property bool inBar: { Store.barPinned; return Store.isBarPinned(pinId); }

    MenuRow {
        width: root.width
        visible: root.entry !== null
        icon: Icons.open
        label: root.entry ? root.entry.name : ""
        onClicked: { const e = root.entry; root.launched(); e.execute(); }
    }
    MenuRow {
        width: root.width
        visible: root.pinId !== ""
        icon: root.inStart ? Icons.pinOff : Icons.pin
        label: root.inStart ? Tr.t("Открепить от \"Пуска\"") : Tr.t("Закрепить в \"Пуске\"")
        onClicked: { if (root.inStart) Store.unpin(root.pinId); else Store.pin(root.pinId); root.done(); }
    }
    MenuRow {
        width: root.width
        visible: root.pinId !== ""
        icon: root.inBar ? Icons.pinOff : Icons.pin
        label: root.inBar ? Tr.t("Открепить от панели задач") : Tr.t("Закрепить на панели задач")
        onClicked: { if (root.inBar) Store.unpinBar(root.pinId); else Store.pinBar(root.pinId); root.done(); }
    }
    MenuRow {
        width: root.width
        visible: root.windows.length > 0
        icon: Icons.subtract
        label: root.windows.length > 1 ? Tr.t("Свернуть все окна") : Tr.t("Свернуть")
        onClicked: { root.windows.forEach(w => Niri.minimize(w)); root.done(); }
    }
    MenuRow {
        width: root.width
        visible: root.windows.length > 0
        icon: Icons.dismiss
        label: root.windows.length > 1 ? Tr.t("Закрыть все окна") : Tr.t("Закрыть окно")
        onClicked: { root.windows.slice().reverse().forEach(w => Niri.closeWindow(w)); root.done(); }
    }
    MenuRow {
        width: root.width
        visible: root.windows.length > 0
        icon: Icons.alert
        label: Tr.t("Закрыть принудительно")
        onClicked: { root.windows.forEach(w => Niri.killWindow(w)); root.done(); }
    }
}
