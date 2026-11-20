import QtQuick
import Quickshell

// Меню панели задач (правый клик по пустому месту): положение и выравнивание.
Flyout {
    id: root
    name: "barmenu"
    role: "bar"
    panelWidth: 264
    panelHeight: col.implicitHeight + 8
    px: Ui.barMenuPos.x
    py: Ui.barMenuPos.y

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
        WText { leftPadding: 12; topPadding: 8; bottomPadding: 6; font.pixelSize: 12; color: Theme.subtext; text: Tr.t("Положение панели задач") }
        Repeater {
            model: [
                { edge: "bottom", label: Tr.t("Снизу"), icon: Icons.arrowDown },
                { edge: "top", label: Tr.t("Сверху"), icon: Icons.arrowUp },
                { edge: "left", label: Tr.t("Слева"), icon: Icons.arrowLeft },
                { edge: "right", label: Tr.t("Справа"), icon: Icons.arrowRight }
            ]
            MenuRow {
                required property var modelData
                width: col.width
                icon: Store.barEdge === modelData.edge ? Icons.check : modelData.icon
                label: modelData.label
                highlighted: Store.barEdge === modelData.edge
                onClicked: { Ui.close(); Store.setBar(modelData.edge, ""); }
            }
        }
        Rectangle { width: parent.width; height: 1; color: Theme.border }
        WText { leftPadding: 12; topPadding: 8; bottomPadding: 6; font.pixelSize: 12; color: Theme.subtext; text: Tr.t("Значки и кнопка \"Пуск\"") }
        Repeater {
            model: [
                { align: "left", label: Tr.t("С края"), icon: Icons.alignLeft },
                { align: "center", label: Tr.t("По центру"), icon: Icons.alignCenter }
            ]
            MenuRow {
                required property var modelData
                width: col.width
                icon: Store.barAlign === modelData.align ? Icons.check : modelData.icon
                label: modelData.label
                highlighted: Store.barAlign === modelData.align
                onClicked: { Ui.close(); Store.setBar("", modelData.align); }
            }
        }
        Rectangle { width: parent.width; height: 1; color: Theme.border }
        MenuRow {
            width: col.width
            icon: Theme.dark ? Icons.sun : Icons.darkTheme
            label: Theme.dark ? Tr.t("Светлая тема") : Tr.t("Тёмная тема")
            onClicked: { Ui.close(); Theme.toggle(); }
        }
        MenuRow {
            width: col.width
            icon: Icons.settings
            label: Tr.t("Параметры панели задач")
            onClicked: Ui.openSettings("taskbar")
        }
        MenuRow {
            width: col.width
            icon: Icons.toolbox
            label: Tr.t("Центр управления")
            onClicked: Ui.flyout = "hub"
        }
        MenuRow {
            width: col.width
            icon: Icons.pulse
            label: Tr.t("Диспетчер задач")
            onClicked: { Ui.close(); Ui.openTaskManager(); }
        }
    }
}
