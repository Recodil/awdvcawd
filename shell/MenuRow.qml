import QtQuick

HoverButton {
    id: root
    property string icon
    property string label
    implicitHeight: 36
    FIcon { id: glyph; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } icon: root.icon }
    WText {
        anchors { left: glyph.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        text: root.label
    }
}
