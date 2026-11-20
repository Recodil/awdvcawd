import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Представление задач (Win+Tab) - своё окно оболочки, а не обзор niri:
// рабочие столы идут слева направо, как в Windows.
// Клавиши: ← → выбор, ↑ ↓ переход между окнами и столами, Enter - перейти, Esc - закрыть.
PanelWindow {
    id: win
    readonly property bool show: Ui.taskView
    property real t: show ? 1 : 0
    Behavior on t { NumberAnimation { duration: win.show ? 320 : 160; easing.type: win.show ? Easing.OutCubic : Easing.InCubic } }

    // окна текущего стола, затем свёрнутые
    readonly property var wins: {
        const here = [], hidden = [];
        const all = Niri.windows;
        for (let i = 0; i < all.length; i++) {
            if (Niri.isMin(all[i])) hidden.push(all[i]);
            else if (all[i].workspace_id === Niri.currentId) here.push(all[i]);
        }
        return here.concat(hidden);
    }
    readonly property var desks: Niri.desktops
    property int sel: 0            // выбранное окно
    property int dsel: 0           // выбранный стол
    property int row: 0            // 0 - ряд окон, 1 - ряд столов
    function step(d) {
        if (row === 0 && wins.length > 0) sel = (sel + d + wins.length) % wins.length;
        else if (desks.length > 0) {
            row = 1;
            dsel = (dsel + d + desks.length) % desks.length;
            Niri.focusDesktop(desks[dsel]);      // стол сразу показывается позади
        }
    }
    function accept() {
        if (row === 0 && wins.length > 0) Niri.activate(wins[sel]);
        else { Niri.focusDesktop(desks[dsel]); Ui.taskView = false; }
    }
    function syncDesk() { for (let i = 0; i < desks.length; i++) if (desks[i].id === Niri.currentId) dsel = i; }
    onWinsChanged: if (sel >= wins.length) sel = Math.max(0, wins.length - 1)
    onDesksChanged: syncDesk()
    onShowChanged: {
        if (!show) return;
        sel = 0;
        for (let i = 0; i < wins.length; i++) if (wins[i].is_focused) sel = i;
        row = wins.length > 0 ? 0 : 1;
        syncDesk();
        keys.forceActiveFocus();
    }

    anchors { top: true; bottom: true; left: true; right: true }
    visible: show || t > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "win11-desktops"
    WlrLayershell.keyboardFocus: show ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.55 * Math.min(1, win.t)
    }
    MouseArea { anchors.fill: parent; onClicked: Ui.taskView = false }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onLeftPressed: win.step(-1)
        Keys.onRightPressed: win.step(1)
        Keys.onTabPressed: win.step(1)
        Keys.onBacktabPressed: win.step(-1)
        Keys.onUpPressed: if (win.wins.length > 0) win.row = 0
        Keys.onDownPressed: win.row = 1
        Keys.onReturnPressed: win.accept()
        Keys.onEnterPressed: win.accept()
        Keys.onEscapePressed: Ui.taskView = false

        // ---- окна ----
        Flow {
            id: cards
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: -90 + (1 - win.t) * 30 }
            width: Math.min(parent.width - 160, Math.max(1, Math.min(win.wins.length, 5)) * 232)
            spacing: 12
            opacity: Math.min(1, win.t)
            Repeater {
                model: win.wins.length
                Rectangle {
                    id: wc
                    required property int index
                    readonly property var w: win.wins[index] || null
                    readonly property var entry: Config.entryFor(Config.appIdOf(w))
                    readonly property bool chosen: win.row === 0 && win.sel === index
                    width: 220; height: 150; radius: 8
                    color: Theme.flyout
                    border.width: chosen ? 3 : 1
                    border.color: chosen ? Theme.accent : Theme.border
                    scale: chosen ? 1.05 : (wcArea.containsMouse ? 1.02 : 1)
                    opacity: (w && Niri.isMin(w)) ? 0.6 : 1
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                    IconImage {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 30 }
                        implicitSize: 52
                        source: Config.iconUrl(wc.entry ? wc.entry.icon : Config.appIdOf(wc.w))
                    }
                    WText {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 12
                        text: wc.w ? (wc.w.title || (wc.entry ? wc.entry.name : wc.w.app_id) || "") : ""
                    }
                    HoverButton {
                        anchors { right: parent.right; top: parent.top; margins: 6 }
                        visible: wcArea.containsMouse || hovered
                        implicitWidth: 26; implicitHeight: 26
                        z: 2
                        onClicked: Niri.closeWindow(wc.w)
                        FIcon { anchors.centerIn: parent; icon: Icons.dismiss; font.pixelSize: 12 }
                    }
                    MouseArea {
                        id: wcArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: mouse => { if (mouse.button === Qt.MiddleButton) Niri.closeWindow(wc.w); else Niri.activate(wc.w); }
                    }
                }
            }
        }
        ShadowText {
            anchors.centerIn: cards
            visible: win.wins.length === 0
            opacity: Math.min(1, win.t)
            font.pixelSize: 16
            text: Tr.t("На этом рабочем столе нет окон")
        }

        // ---- рабочие столы: слева направо ----
        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 72 - (1 - win.t) * 60 }
            width: Math.min(strip.implicitWidth + 24, keys.width - 120)
            height: 128
            radius: 10
            opacity: Math.min(1, win.t)
            color: Theme.flyout
            border.color: Theme.border
            MouseArea { anchors.fill: parent }

            // столов может быть сколько угодно: лента прокручивается колесом мыши и сама
            // подъезжает к текущему столу
            Flickable {
                id: stripView
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                contentWidth: strip.implicitWidth
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                function reveal(i) {
                    const x0 = i * 158, x1 = x0 + 148;
                    if (x0 < contentX) contentX = x0;
                    else if (x1 > contentX + width) contentX = Math.min(Math.max(0, contentWidth - width), x1 - width + 158);
                }
                Behavior on contentX { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Connections { target: win; function onDselChanged() { stripView.reveal(win.dsel); } function onShowChanged() { if (win.show) stripView.reveal(win.dsel); } }
                WheelHandler {
                    onWheel: e => {
                        const max = Math.max(0, stripView.contentWidth - stripView.width);
                        stripView.contentX = Math.max(0, Math.min(max, stripView.contentX - (e.angleDelta.y + e.angleDelta.x)));
                    }
                }
            Row {
                id: strip
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Repeater {
                    model: win.desks.length
                    Item {
                        id: card
                        required property int index
                        readonly property var ws: win.desks[index] || null
                        readonly property var wins: ws ? Niri.windowsOn(ws.id) : []
                        readonly property bool isNew: false
                        readonly property bool active: ws !== null && ws.id === Niri.currentId
                        readonly property bool chosen: win.row === 1 && win.dsel === index
                        width: 148; height: 104
                        scale: area.pressed ? 0.95 : (chosen || area.containsMouse ? 1.04 : 1)
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                        Rectangle {
                            id: thumb
                            width: 148; height: 80; radius: 6
                            color: Theme.card
                            border.width: card.chosen ? 3 : card.active ? 2 : 1
                            border.color: (card.active || card.chosen) ? Theme.accent : Theme.border
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                visible: !card.isNew
                                Repeater {
                                    model: Math.min(card.wins.length, 5)
                                    IconImage {
                                        required property int index
                                        readonly property var entry: Config.entryFor(Config.appIdOf(card.wins[index]))
                                        implicitSize: 22
                                        source: Config.iconUrl(entry ? entry.icon : Config.appIdOf(card.wins[index]))
                                    }
                                }
                            }
                            FIcon { anchors.centerIn: parent; visible: card.isNew; icon: Icons.add; font.pixelSize: 22 }
                        }
                        WText {
                            anchors { top: thumb.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 12
                            text: card.isNew ? Tr.t("Создать рабочий стол") : Tr.t("Рабочий стол ") + (card.index + 1)
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { Niri.focusDesktop(card.ws); Ui.taskView = false; }
                        }
                        // закрыть стол (его окна переедут на соседний)
                        HoverButton {
                            anchors { right: parent.right; top: parent.top; margins: 3 }
                            visible: win.desks.length > 1 && (area.containsMouse || hovered)
                            implicitWidth: 22; implicitHeight: 22
                            z: 2
                            color: hovered ? "#c42b1c" : Theme.flyout
                            onClicked: Niri.removeDesktop(card.ws)
                            FIcon { anchors.centerIn: parent; icon: Icons.dismiss; font.pixelSize: 10 }
                        }
                    }
                }
                // "Создать рабочий стол" - всегда последней
                Item {
                    width: 148; height: 104
                    scale: addArea.pressed ? 0.95 : (addArea.containsMouse ? 1.04 : 1)
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Rectangle {
                        id: addThumb
                        width: 148; height: 80; radius: 6
                        color: addArea.containsMouse ? Theme.hover : "transparent"
                        border.color: Theme.border
                        FIcon { anchors.centerIn: parent; icon: Icons.add; font.pixelSize: 22 }
                    }
                    WText {
                        anchors { top: addThumb.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 12
                        text: Tr.t("Создать рабочий стол")
                    }
                    MouseArea { id: addArea; anchors.fill: parent; hoverEnabled: true; onClicked: { Niri.newDesktop(); Ui.taskView = false; } }
                }
            }
            }
        }
    }
}
