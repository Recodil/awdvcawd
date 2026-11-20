import QtQuick
import Quickshell
import Quickshell.Wayland

// Всплывающие уведомления: выезжают справа над панелью задач.
PanelWindow {
    id: win
    anchors { bottom: true; right: true }
    implicitWidth: 388
    implicitHeight: Math.max(1, col.implicitHeight + 12)
    visible: Notifs.live > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "win11-toasts"

    Column {
        id: col
        anchors { bottom: parent.bottom; right: parent.right; bottomMargin: 12; rightMargin: 12 }
        width: 364
        Repeater {
            model: Notifs.list
            Item {
                id: toast
                required property var modelData
                property bool live: true
                property real slide: 1
                width: col.width
                height: live ? card.implicitHeight + 8 : 0
                visible: height > 0
                clip: true
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                // при "Не беспокоить" уведомление не всплывает (остаётся в центре уведомлений)
                Component.onCompleted: { if (Notifs.quiet(modelData)) { live = false; return; } Notifs.live++; slide = 0; }
                Component.onDestruction: if (live) Notifs.live--
                Behavior on slide { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                function hide() { if (live) { live = false; Notifs.live--; } }
                Timer { interval: 6000; running: toast.live && !hover.hovered; onTriggered: toast.hide() }
                HoverHandler { id: hover }
                NotifCard {
                    id: card
                    notif: toast.modelData
                    width: parent.width
                    x: toast.slide * 400
                    opacity: 1 - toast.slide
                }
            }
        }
    }
}
