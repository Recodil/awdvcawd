import QtQuick
import Quickshell
import Quickshell.Widgets

// Пункты меню значка из трея (одно вложение подменю).
Column {
    id: root
    property var handle: null
    property var sub: null            // открытое подменю

    QsMenuOpener { id: top; menu: root.handle }
    QsMenuOpener { id: nested; menu: root.sub }

    MenuRow {
        visible: root.sub !== null
        width: root.width
        icon: Icons.chevronLeft
        label: root.sub ? root.sub.text : ""
        onClicked: root.sub = null
    }
    Repeater {
        model: root.sub !== null ? nested.children : top.children
        Item {
            id: row
            required property var modelData
            width: root.width
            height: modelData.isSeparator ? 9 : 34
            Rectangle {
                visible: row.modelData.isSeparator
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                height: 1
                color: Theme.border
            }
            HoverButton {
                visible: !row.modelData.isSeparator
                anchors.fill: parent
                opacity: row.modelData.enabled ? 1 : 0.45
                onClicked: {
                    if (!row.modelData.enabled) return;
                    if (row.modelData.hasChildren) { root.sub = row.modelData; return; }
                    row.modelData.triggered();
                    Ui.close();
                }
                WText {
                    anchors { left: parent.left; leftMargin: 12; right: more.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: (row.modelData.text || "").replace(/_/g, "")
                }
                FIcon {
                    id: more
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    font.pixelSize: 12
                    icon: row.modelData.hasChildren ? Icons.chevronRight : (row.modelData.checkState === Qt.Checked ? Icons.check : "")
                }
            }
        }
    }
}
