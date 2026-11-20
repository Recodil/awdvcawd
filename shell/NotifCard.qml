import QtQuick
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root
    required property var notif
    implicitHeight: col.implicitHeight + 24
    radius: 8
    color: Theme.dark ? "#2b2b2b" : "#f9f9f9"
    border.color: Theme.border

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 6
        Row {
            spacing: 8
            width: parent.width
            IconImage {
                implicitSize: 16
                source: Quickshell.iconPath(Notifs.iconFor(root.notif), "dialog-information")
            }
            WText { text: Notifs.nameFor(root.notif); font.pixelSize: 12; color: Theme.subtext; width: parent.width - 60 }
        }
        WText { text: root.notif.summary; font.weight: Font.DemiBold; font.pixelSize: 14; width: parent.width }
        WText {
            text: root.notif.body
            visible: text !== ""
            textFormat: Text.PlainText
            color: Theme.subtext
            width: parent.width
            wrapMode: Text.Wrap
            maximumLineCount: 4
        }
    }
    HoverButton {
        anchors { right: parent.right; top: parent.top; margins: 6 }
        implicitWidth: 24; implicitHeight: 24
        FIcon { anchors.centerIn: parent; icon: Icons.dismiss; font.pixelSize: 12 }
        onClicked: root.notif.dismiss()
    }
}
