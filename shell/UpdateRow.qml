import QtQuick

// Строка центра обновления: значок, название, пояснение и действие справа.
Rectangle {
    id: root
    property string icon
    property string label
    property string hint: ""
    property bool marked: false          // есть что установить
    default property alias content: slot.data

    height: Math.max(56, texts.implicitHeight + 20)
    radius: 6
    color: Theme.card
    border.color: marked ? Theme.accent : Theme.border
    Behavior on color { ColorAnimation { duration: 220 } }
    Behavior on border.color { ColorAnimation { duration: 220 } }

    FIcon {
        id: glyph
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
        icon: root.icon; font.pixelSize: 18
        color: root.marked ? Theme.accent : Theme.text
    }
    Column {
        id: texts
        anchors { left: glyph.right; leftMargin: 14; right: slot.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        WText { width: parent.width; text: root.label }
        WText {
            width: parent.width; visible: root.hint !== ""
            wrapMode: Text.WordWrap; elide: Text.ElideNone
            font.pixelSize: 11; color: Theme.subtext; text: root.hint
        }
    }
    Row { id: slot; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } spacing: 6 }
}
