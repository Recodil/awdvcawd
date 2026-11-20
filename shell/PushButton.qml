import QtQuick

// Кнопка с подписью. accent - главная кнопка окна.
HoverButton {
    id: root
    property string label
    property bool accent: false
    implicitWidth: text.implicitWidth + 26
    implicitHeight: 32
    color: accent ? (pressed ? Qt.darker(Theme.accent, 1.15) : hovered ? Qt.lighter(Theme.accent, 1.08) : Theme.accent)
                  : (pressed ? Theme.pressed : hovered ? Theme.hover : Theme.card)
    border.color: accent ? "transparent" : Theme.border
    opacity: enabled ? 1 : 0.5
    WText { id: text; anchors.centerIn: parent; font.pixelSize: 12; color: root.accent ? Theme.accentText : Theme.text; text: root.label }
}
