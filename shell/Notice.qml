import QtQuick
import Quickshell

// Системное сообщение в стиле Windows ("Ваш сеанс будет завершён").
// Показывается командой: qs -p /etc/win11-shell ipc call shell notice "Заголовок" "Текст" "1"
// (последний параметр "1" добавляет кнопку отмены запланированного завершения работы).
Flyout {
    id: root
    name: "notice"
    role: "center"
    panelWidth: 440
    panelHeight: body.implicitHeight + 112

    Column {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 12
        WText { width: parent.width; wrapMode: Text.Wrap; font.pixelSize: 20; font.weight: Font.DemiBold; text: Ui.noticeTitle }
        WText { width: parent.width; wrapMode: Text.Wrap; elide: Text.ElideNone; textFormat: Text.PlainText; lineHeight: 1.25; text: Ui.noticeText }
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
        height: 64
        color: Theme.footer
        Rectangle { width: parent.width; height: 1; color: Theme.border }
        Row {
            anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
            spacing: 8
            HoverButton {
                visible: Ui.noticeCancel
                implicitWidth: cn.implicitWidth + 32; implicitHeight: 32
                color: pressed ? Theme.pressed : hovered ? Theme.hover : Theme.card
                border.color: Theme.border
                onClicked: { Ui.close(); Quickshell.execDetached(["win11-shutdown", "/a"]); }
                WText { id: cn; anchors.centerIn: parent; text: Tr.t("Отменить завершение") }
            }
            HoverButton {
                implicitWidth: Math.max(96, ok.implicitWidth + 32); implicitHeight: 32
                color: Theme.accent
                opacity: pressed ? 0.8 : hovered ? 0.9 : 1
                onClicked: Ui.close()
                WText { id: ok; anchors.centerIn: parent; color: Theme.accentText; text: Tr.t("Закрыть") }
            }
        }
    }
}
