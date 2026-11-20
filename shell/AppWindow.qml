import QtQuick
import Quickshell
import QtQuick.Window

// Окно-приложение оболочки: обычное окно со своим заголовком. В отличие от
// всплывающих панелей не закрывается при щелчке мимо, его можно свернуть и передвинуть.
Window {
    id: win

    property bool open: false
    property int implicitWidth: 780
    property int implicitHeight: 600
    property size minimumSize: Qt.size(0, 0)
    width: implicitWidth
    height: implicitHeight
    minimumWidth: minimumSize.width
    minimumHeight: minimumSize.height
    flags: Qt.Window | Qt.FramelessWindowHint
    property string heading: ""
    default property alias content: body.data
    signal opened()
    signal dismissed()

    title: heading
    color: Theme.flyout
    visible: false

    function sync() {
        if (visible !== open) visible = open;
        if (open) { body.forceActiveFocus(); opened(); }
    }
    onOpenChanged: sync()
    Component.onCompleted: sync()
    // окно закрыли средствами системы (Alt+F4, крестик обзора)
    onVisibleChanged: if (!visible && open) dismissed()
    onClosing: close => { close.accepted = false; if (open) dismissed(); }


    Rectangle {
        id: bar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 36
        color: Theme.titlebar
        Behavior on color { ColorAnimation { duration: 160 } }

        MouseArea {
            anchors.fill: parent
            onPressed: if (typeof win.startSystemMove === "function") win.startSystemMove()
        }
        WText {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            font.pixelSize: 12
            text: win.heading
        }
        Row {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            HoverButton {
                implicitWidth: 44; implicitHeight: bar.height; radius: 0
                onClicked: Niri.minimizeFocused()
                FIcon { anchors.centerIn: parent; icon: Icons.subtract; font.pixelSize: 14 }
            }
            HoverButton {
                implicitWidth: 44; implicitHeight: bar.height; radius: 0
                onClicked: win.dismissed()
                FIcon { anchors.centerIn: parent; icon: Icons.dismiss; font.pixelSize: 14 }
            }
        }
    }
    FocusScope {
        id: body
        anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: parent.bottom }
        focus: true
    }
}
