import QtQuick

// Кнопка с подсветкой при наведении, как в Windows 11.
Rectangle {
    id: root
    signal clicked(var mouse)
    property bool highlighted: false
    readonly property bool hovered: area.containsMouse
    readonly property bool pressed: area.pressed
    default property alias content: inner.data

    implicitWidth: 40
    implicitHeight: 40
    radius: 4
    color: area.pressed ? Theme.pressed : (area.containsMouse || highlighted) ? Theme.hover : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }

    Item { id: inner; anchors.fill: parent }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: mouse => root.clicked(mouse)
    }
}
