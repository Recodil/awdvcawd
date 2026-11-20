import QtQuick

Item {
    id: root
    property real value: 0
    signal moved(real v)
    implicitHeight: 24
    implicitWidth: 200

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 4; radius: 2
        color: Theme.dark ? "#9a9a9a" : "#868686"
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: handle.x + handle.width / 2; height: 4; radius: 2
        color: Theme.accent
    }
    Rectangle {
        id: handle
        x: Math.max(0, Math.min(1, root.value)) * (root.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 20; radius: 10
        color: Theme.dark ? "#454545" : "#ffffff"
        border.color: Theme.border
        Rectangle {
            anchors.centerIn: parent
            width: area.pressed ? 8 : area.containsMouse ? 14 : 10
            height: width; radius: width / 2
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        function upd(mx) { root.moved(Math.max(0, Math.min(1, (mx - 10) / (root.width - 20)))); }
        onPressed: mouse => upd(mouse.x)
        onPositionChanged: mouse => { if (pressed) upd(mouse.x); }
    }
}
