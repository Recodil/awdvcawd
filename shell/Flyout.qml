import QtQuick
import Quickshell
import Quickshell.Wayland

// Всплывающая панель: прозрачное окно на весь экран (клик мимо - закрыть)
// и сама панель, которая "выпрыгивает" со стороны панели задач.
PanelWindow {
    id: win
    property string name: ""
    // "start" - у кнопки "Пуск", "end" - у часов, "bar" - у точки на панели задач, "point" - у курсора, "center" - в центре экрана
    property string role: "end"
    property real panelWidth: 360
    property real panelHeight: 400
    property real px: -1
    property real py: -1
    default property alias content: holder.data
    signal opened()

    // ready: панель может создаваться в момент открытия (см. shell.qml) - тогда open
    // становится истинным уже после создания, и анимация появления проигрывается как обычно
    property bool ready: false
    Component.onCompleted: ready = true
    readonly property bool open: ready && Ui.flyout === name
    readonly property string edge: Store.barEdge
    readonly property bool vert: edge === "left" || edge === "right"
    readonly property bool centered: Store.barAlign === "center"
    // размеры экрана берём у содержимого окна
    readonly property real sw: backdrop.width
    readonly property real sh: backdrop.height
    readonly property real pw: Math.min(panelWidth, sw - 24)
    readonly property real ph: Math.min(panelHeight, sh - 24)
    function clampX(v) { return Math.max(8, Math.min(sw - pw - 8, v)); }
    function clampY(v) { return Math.max(8, Math.min(sh - ph - 8, v)); }
    readonly property real baseX: {
        if (role === "center") return (sw - pw) / 2;
        if (role === "point") return clampX(px - pw / 2);
        if (vert) return edge === "left" ? (role === "bar" ? 8 : 12) : sw - pw - (role === "bar" ? 8 : 12);
        if (role === "bar") return clampX(px - pw / 2);
        if (role === "start") return centered ? (sw - pw) / 2 : 12;
        return sw - pw - 12;
    }
    readonly property real baseY: {
        if (role === "center") return (sh - ph) / 2;
        if (role === "point") return clampY(py - ph);
        if (!vert) return edge === "top" ? (role === "bar" ? 8 : 12) : sh - ph - (role === "bar" ? 8 : 12);
        if (role === "bar") return clampY(py - ph / 2);
        if (role === "start") return centered ? (sh - ph) / 2 : 12;
        return sh - ph - 12;
    }

    // fade - прозрачность, jump - смещение и масштаб с лёгким "перелётом"
    property real fade: open ? 1 : 0
    property real jump: open ? 1 : 0
    Behavior on fade { NumberAnimation { duration: win.open ? 200 : 150; easing.type: Easing.OutCubic } }
    Behavior on jump {
        NumberAnimation {
            duration: win.open ? 420 : 170
            easing.type: win.open ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.15
        }
    }
    onOpenChanged: if (open) { holder.forceActiveFocus(); opened(); }

    visible: open || fade > 0
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "win11-flyout"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { id: backdrop; anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: Ui.close() }

    Rectangle {
        id: panel
        readonly property real dist: (1 - win.jump) * Math.min(Math.max(width, height) * 0.25 + 12, 110)
        width: win.pw
        height: win.ph
        readonly property bool free: win.role === "point" || win.role === "center"
        x: win.baseX + (free ? 0 : win.edge === "left" ? -dist : win.edge === "right" ? dist : 0)
        y: win.baseY + (free ? dist * 0.3 : win.edge === "top" ? -dist : win.edge === "bottom" ? dist : 0)
        scale: 0.94 + 0.06 * win.jump
        transformOrigin: win.role === "center" ? Item.Center : win.role === "point" ? Item.Bottom
                       : win.edge === "top" ? Item.Top : win.edge === "left" ? Item.Left
                       : win.edge === "right" ? Item.Right : Item.Bottom
        opacity: win.fade
        radius: 8
        color: Theme.flyout
        border.color: Theme.border
        border.width: 1
        clip: true

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        FocusScope {
            id: holder
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Ui.close()
        }
    }
}
