import QtQuick
import Quickshell
import Quickshell.Wayland

// Индикатор громкости над панелью задач.
PanelWindow {
    id: win
    property bool show: false
    property bool ready: false
    function pop() {
        if (!ready || Ui.flyout === "quick") return;
        show = true;
        hide.restart();
    }

    anchors { bottom: true }
    implicitWidth: 240
    implicitHeight: 64
    visible: show || box.opacity > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "win11-osd"

    Connections {
        target: Sys
        function onVolumeChanged() { win.pop(); }
        function onMutedChanged() { win.pop(); }
    }
    Timer { id: hide; interval: 1600; onTriggered: win.show = false }
    Timer { interval: 2500; running: true; onTriggered: win.ready = true }

    Rectangle {
        id: box
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.show ? 4 : 24
        width: 220; height: 44; radius: 8
        opacity: win.show ? 1 : 0
        color: Theme.flyout
        border.color: Theme.border
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 220 } }

        FIcon { id: ic; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } icon: Sys.muted ? Icons.speakerMute : Icons.speaker; font.pixelSize: 18 }
        Rectangle {
            id: track
            anchors { left: ic.right; leftMargin: 12; right: pct.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            height: 4; radius: 2
            color: Theme.dark ? "#9a9a9a" : "#868686"
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, Sys.volume)); height: 4; radius: 2
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: 100 } }
            }
        }
        WText { id: pct; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } width: 26; horizontalAlignment: Text.AlignRight; text: Math.round(Sys.volume * 100) }
    }
}
