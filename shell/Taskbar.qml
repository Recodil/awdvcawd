import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower

// Панель задач. Может стоять у любого края экрана (Store.barEdge),
// значки - с края или по центру (Store.barAlign). Правый клик по пустому месту - меню.
PanelWindow {
    id: bar
    readonly property string edge: Store.barEdge
    readonly property bool vert: edge === "left" || edge === "right"
    readonly property bool centered: Store.barAlign === "center"

    anchors { left: edge !== "right"; right: edge !== "left"; top: edge !== "bottom"; bottom: edge !== "top" }
    implicitWidth: 48
    implicitHeight: 48
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "win11-taskbar"

    // Группы окон по приложениям: закреплённые + окна текущего рабочего стола + свёрнутые.
    readonly property var groups: {
        DesktopEntries.applications.values;
        const keys = [], wins = {}, ids = {};
        for (let i = 0; i < Store.barPinned.length; i++) {
            const k = Store.barPinned[i].toLowerCase();
            if (k in wins) continue;
            keys.push(k); wins[k] = []; ids[k] = Store.barPinned[i];
        }
        const all = Niri.windows;
        for (let i = 0; i < all.length; i++) {
            const w = all[i];
            if (w.workspace_id !== Niri.currentId && !Niri.isMin(w)) continue;
            const appId = Config.appIdOf(w);
            const e = Config.entryFor(appId);
            const k = ((e && e.id) ? e.id : appId).toLowerCase();
            if (!(k in wins)) { keys.push(k); wins[k] = []; ids[k] = appId; }
            wins[k].push(w);
        }
        return { keys: keys, wins: wins, ids: ids };
    }
    // список ключей меняем только когда изменился состав - значки не пересоздаются при каждом событии
    property var appKeys: []
    onGroupsChanged: {
        if (bar.dragIndex >= 0) return;
        let k = groups.keys.slice();
        if (Store.barOrder && Store.barOrder.length > 0) {
            k.sort(function(a, b) {
                const ia = Store.barOrder.indexOf(a);
                const ib = Store.barOrder.indexOf(b);
                if (ia >= 0 && ib >= 0) return ia - ib;
                if (ia >= 0) return -1;
                if (ib >= 0) return 1;
                return 0;
            });
        }
        if (JSON.stringify(k) !== JSON.stringify(appKeys)) appKeys = k;
    }

    // Перетаскивание значков на панели задач
    property int dragIndex: -1
    property int dropIndex: -1
    property real dragOffset: 0
    property string dragKey: ""

    function startDrag(idx, key) {
        dragIndex = idx;
        dropIndex = idx;
        dragOffset = 0;
        dragKey = key;
    }
    function updateDrag(delta) {
        dragOffset = delta;
        const steps = Math.round(delta / 44);
        dropIndex = Math.max(0, Math.min(appKeys.length - 1, dragIndex + steps));
    }
    function finishDrag() {
        const from = dragIndex;
        const to = dropIndex;
        dragIndex = -1;
        dropIndex = -1;
        dragOffset = 0;
        dragKey = "";
        if (from >= 0 && to >= 0 && from !== to && from < appKeys.length && to < appKeys.length) {
            const next = appKeys.slice();
            const item = next.splice(from, 1)[0];
            next.splice(to, 0, item);
            appKeys = next;
            Store.setBarOrder(next);
        }
    }

    readonly property int trayCount: Ui.trayItems.length
    function menuPos(item) { return item.mapToItem(null, item.width / 2, item.height / 2); }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Theme.taskbar
        Rectangle {
            color: Theme.border; opacity: 0.6
            width: bar.vert ? 1 : parent.width
            height: bar.vert ? parent.height : 1
            x: bar.edge === "left" ? parent.width - 1 : 0
            y: bar.edge === "top" ? parent.height - 1 : 0
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: mouse => Ui.openBarMenu(mouse.x, mouse.y)
        }
    }

    // ---- "Пуск", поиск, представление задач, приложения ----
    Grid {
        id: main
        columns: bar.vert ? 1 : 999
        spacing: 4
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        x: bar.vert ? (bg.width - width) / 2 : (bar.centered ? (bg.width - width) / 2 : 8)
        y: bar.vert ? (bar.centered ? (bg.height - height) / 2 : 8) : (bg.height - height) / 2
        Behavior on x { NumberAnimation { duration: 450; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on y { NumberAnimation { duration: 450; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }

        HoverButton {
            highlighted: Ui.flyout === "start"
            onClicked: Ui.toggle("start")
            // логотип NixOS; при открытии "Пуска" снежинка проворачивается на один луч
            Image {
                anchors.centerIn: parent
                width: 26; height: 26
                sourceSize.width: 52; sourceSize.height: 52
                smooth: true
                source: Store.startIconUrl
                fillMode: Image.PreserveAspectFit
                // если своя картинка не открылась - стандартный значок
                onStatusChanged: if (status === Image.Error) source = Qt.resolvedUrl("assets/nixos.svg")
                scale: parent.pressed ? 0.8 : (Ui.flyout === "start" && Store.startIcon !== "nixos" ? 1.12 : 1)
                // снежинка NixOS проворачивается на один луч, остальные значки слегка увеличиваются
                rotation: Ui.flyout === "start" && Store.startIcon === "nixos" ? 60 : 0
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                Behavior on rotation { NumberAnimation { duration: 420; easing.type: Easing.OutBack } }
            }
        }
        HoverButton {
            visible: Store.showSearch
            highlighted: Ui.flyout === "search"
            onClicked: { if (Ui.flyout === "search") Ui.close(); else Ui.openSearch(""); }
            FIcon { anchors.centerIn: parent; icon: Icons.search; font.pixelSize: 20 }
        }
        HoverButton {
            visible: Store.showTaskView
            highlighted: Ui.taskView
            onClicked: Niri.toggleOverview()
            FIcon { anchors.centerIn: parent; icon: Icons.taskView; font.pixelSize: 20 }
        }

                Repeater {
            model: bar.appKeys
            Item {
                id: appWrap
                required property int index
                required property string modelData
                readonly property var wins: bar.groups.wins[modelData] || []
                readonly property string appId: bar.groups.ids[modelData] || modelData
                readonly property bool running: wins.length > 0
                readonly property bool active: {
                    for (let i = 0; i < wins.length; i++) if (wins[i].is_focused) return true;
                    return false;
                }
                readonly property bool allMin: {
                    for (let i = 0; i < wins.length; i++) if (!Niri.isMin(wins[i])) return false;
                    return running;
                }
                readonly property var entry: {
                    DesktopEntries.applications.values;
                    return Config.entryFor(appId);
                }
                property real hop: 0
                visible: running || entry !== null
                implicitWidth: 40
                implicitHeight: 40

                readonly property bool isDragging: bar.dragIndex === index
                readonly property real shift: {
                    if (bar.dragIndex < 0 || bar.dragIndex === index) return 0;
                    if (bar.dragIndex < bar.dropIndex && index > bar.dragIndex && index <= bar.dropIndex) return -44;
                    if (bar.dragIndex > bar.dropIndex && index < bar.dragIndex && index >= bar.dropIndex) return 44;
                    return 0;
                }

                function ctx() {
                    const p = bar.menuPos(appCard);
                    Ui.openCtx({ appId: appId, entry: entry, windows: wins, mode: "bar", x: p.x, y: p.y });
                }
                function launch() { if (entry) { hopAnim.restart(); entry.execute(); } }

                function handleClicked(mouse) {
                    Ui.peek = null;
                    if (mouse.button === Qt.RightButton) { ctx(); return; }
                    if (!running || mouse.button === Qt.MiddleButton) { launch(); return; }
                    let focused = -1;
                    for (let i = 0; i < wins.length; i++) if (wins[i].is_focused) focused = i;
                    if (wins.length === 1) {
                        if (focused === 0) Niri.minimize(wins[0]); else Niri.focusWindow(wins[0]);
                    } else if (focused < 0) {
                        Niri.focusWindow(Niri.recent(wins));
                    } else {
                        Niri.focusWindow(wins[(focused + 1) % wins.length]);
                    }
                }

                Timer {
                    id: peekOpen
                    interval: Ui.peek ? 80 : 450
                    onTriggered: {
                        if (bar.dragIndex >= 0) return;
                        const p = bar.menuPos(appCard);
                        Ui.showPeek({ windows: appWrap.wins, entry: appWrap.entry, x: p.x, y: p.y });
                    }
                }

                SequentialAnimation {
                    id: hopAnim
                    NumberAnimation { target: appWrap; property: "hop"; to: 1; duration: 150; easing.type: Easing.OutCubic }
                    NumberAnimation { target: appWrap; property: "hop"; to: 0; duration: 520; easing.type: Easing.OutBounce }
                }

                Rectangle {
                    id: appCard
                    width: 40; height: 40
                    radius: 4
                    z: appWrap.isDragging ? 100 : 1
                    opacity: appWrap.isDragging ? 0.9 : 1
                    x: appWrap.isDragging ? (bar.vert ? 0 : bar.dragOffset) : (bar.vert ? 0 : appWrap.shift)
                    y: appWrap.isDragging ? (bar.vert ? bar.dragOffset : 0) : (bar.vert ? appWrap.shift : 0)

                    Behavior on x {
                        enabled: !appWrap.isDragging
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        enabled: !appWrap.isDragging
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    color: appMouse.pressed && !appMouse.dragging ? Theme.pressed
                         : (appMouse.containsMouse || appWrap.active) ? Theme.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: 90 } }

                    IconImage {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -1 - appWrap.hop * 9
                        implicitSize: 24
                        source: Config.appIcon(appWrap.entry, appWrap.appId)
                        opacity: appWrap.allMin ? 0.75 : 1
                        scale: appMouse.pressed && !appMouse.dragging ? 0.78 : (appWrap.isDragging ? 1.08 : 1)
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                    }

                    Rectangle {
                        anchors { bottom: parent.bottom; bottomMargin: 2; horizontalCenter: parent.horizontalCenter }
                        visible: appWrap.running
                        width: appWrap.active ? 16 : 6
                        height: 3; radius: 1.5
                        color: appWrap.active ? Theme.accent : Theme.subtext
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }

                MouseArea {
                    id: appMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                    property real startPos: 0
                    property bool dragging: false

                    onHoveredChanged: {
                        if (containsMouse && appWrap.wins.length > 1 && Ui.flyout === "" && bar.dragIndex < 0) peekOpen.restart();
                        else { peekOpen.stop(); Ui.leavePeek(); }
                    }

                    onPressed: mouse => {
                        startPos = bar.vert ? mouse.y : mouse.x;
                        dragging = false;
                    }

                    onPositionChanged: mouse => {
                        if (!pressed || (mouse.buttons & Qt.LeftButton) === 0) return;
                        const delta = (bar.vert ? mouse.y : mouse.x) - startPos;
                        if (!dragging && Math.abs(delta) > 6) {
                            dragging = true;
                            peekOpen.stop();
                            Ui.leavePeek();
                            Ui.peek = null;
                            bar.startDrag(appWrap.index, appWrap.modelData);
                        }
                        if (dragging) {
                            bar.updateDrag(delta);
                        }
                    }

                    onReleased: mouse => {
                        if (dragging) {
                            dragging = false;
                            bar.finishDrag();
                        } else {
                            appWrap.handleClicked(mouse);
                        }
                    }
                }
            }
        }
    }

    // ---- трей, быстрые настройки, часы ----
    Grid {
        id: side
        columns: bar.vert ? 1 : 999
        spacing: 2
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        x: bar.vert ? (bg.width - width) / 2 : bg.width - width
        y: bar.vert ? bg.height - height : (bg.height - height) / 2

        // Заряд подключённых Bluetooth-устройств (наушники, мышь, клавиатура - как на концепте)
        // Заряд подключённых Bluetooth-устройств (наушники, мышь, клавиатура - как на концепте)
        Repeater {
            model: Sys.btDevices
            HoverButton {
                id: btItem
                required property var modelData
                implicitWidth: bar.vert ? 40 : btRow.implicitWidth + 12
                implicitHeight: bar.vert ? btRow.implicitHeight + 8 : 40
                onClicked: Ui.openSettings("keyboard")
                Row {
                    id: btRow
                    anchors.centerIn: parent
                    spacing: 4
                    Item {
                        width: 14; height: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: btItem.modelData.type === "mouse"
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 14
                            source: Qt.resolvedUrl("assets/bt-mouse.svg")
                        }
                    }
                    FIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: 13
                        visible: btItem.modelData.type !== "mouse"
                        icon: btItem.modelData.type === "keyboard" ? Icons.keyboard
                            : btItem.modelData.type === "gamepad" ? Icons.gamepad
                            : Icons.headphones
                    }
                    WText {
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        text: btItem.modelData.percent + "%"
                    }
                }
            }
        }
        HoverButton {
            id: trayBtn
            visible: bar.trayCount > 3
            implicitWidth: bar.vert ? 40 : 28
            implicitHeight: bar.vert ? 28 : 40
            highlighted: Ui.flyout === "tray" && Ui.trayItem === null
            onClicked: { const p = bar.menuPos(trayBtn); Ui.toggleTray(p.x, p.y); }
            FIcon {
                anchors.centerIn: parent
                font.pixelSize: 14
                icon: bar.edge === "bottom" ? Icons.chevronUp : bar.edge === "top" ? Icons.chevronDown
                    : bar.edge === "left" ? Icons.chevronRight : Icons.chevronLeft
                rotation: Ui.flyout === "tray" ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
        }
        Repeater {
            // число значков, а не сами объекты: программа может убрать свой значок в любой момент
            model: bar.trayCount <= 3 ? bar.trayCount : 0
            HoverButton {
                id: tray
                required property int index
                readonly property var modelData: Ui.trayItems[index] || null
                visible: modelData !== null
                implicitWidth: bar.vert ? 40 : 30
                implicitHeight: bar.vert ? 30 : 40
                IconImage { anchors.centerIn: parent; implicitSize: 16; source: tray.modelData ? tray.modelData.icon : "" }
                onClicked: mouse => {
                    if (!modelData) return;
                    const p = bar.menuPos(tray);
                    if (mouse.button === Qt.LeftButton && !modelData.onlyMenu) modelData.activate();
                    else if (modelData.hasMenu) Ui.openTrayMenu(modelData, p.x, p.y);
                }
            }
        }

        // центр обновления: значок виден, только когда есть что установить или установка идёт
        HoverButton {
            visible: Store.updIcon && (Updates.notable > 0 || Updates.working || Ui.updatesOpen)
            implicitWidth: bar.vert ? 40 : 30
            implicitHeight: bar.vert ? 30 : 40
            highlighted: Ui.updatesOpen
            onClicked: Ui.openUpdates()
            FIcon {
                id: updGlyph
                anchors.centerIn: parent
                icon: Icons.sync; font.pixelSize: 16
                RotationAnimation on rotation { running: Updates.busy; from: 0; to: 360; duration: 1200; loops: Animation.Infinite }
                Connections { target: Updates; function onBusyChanged() { if (!Updates.busy) updGlyph.rotation = 0; } }
            }
            Rectangle {
                visible: Updates.notable > 0
                anchors { right: parent.right; top: parent.top; rightMargin: 4; topMargin: 9 }
                width: 8; height: 8; radius: 4
                color: Theme.accent
                border.color: Theme.taskbar
            }
        }

        // текущая раскладка клавиатуры; щелчок переключает
        HoverButton {
            visible: Niri.layoutLabel !== ""
            implicitWidth: bar.vert ? 40 : 38
            implicitHeight: bar.vert ? 28 : 40
            onClicked: Niri.nextLayout()
            WText { anchors.centerIn: parent; elide: Text.ElideNone; font.pixelSize: 12; text: Niri.layoutLabel }
        }

        HoverButton {
            implicitWidth: bar.vert ? 40 : quick.implicitWidth + 20
            implicitHeight: bar.vert ? quick.implicitHeight + 18 : 40
            highlighted: Ui.flyout === "quick"
            onClicked: Ui.toggle("quick")
            Grid {
                id: quick
                anchors.centerIn: parent
                columns: bar.vert ? 1 : 3
                spacing: 8
                FIcon { icon: Sys.netIcon }
                FIcon { icon: Sys.muted ? Icons.speakerMute : Icons.speaker }
                FIcon {
                    visible: UPower.displayDevice !== null && UPower.displayDevice.isLaptopBattery
                    icon: UPower.onBattery ? Icons.battery : Icons.batteryCharge
                }
            }
        }

        HoverButton {
            implicitWidth: bar.vert ? 44 : clock.implicitWidth + 20
            implicitHeight: bar.vert ? clock.implicitHeight + 14 : 40
            highlighted: Ui.flyout === "calendar"
            onClicked: Ui.toggle("calendar")
            Grid {
                id: clock
                anchors.centerIn: parent
                columns: bar.vert ? 1 : 2
                spacing: bar.vert ? 4 : 8
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter
                Column {
                    id: stamp
                    width: Math.max(timeText.implicitWidth, dateText.implicitWidth)
                    WText { id: timeText; elide: Text.ElideNone; x: bar.vert ? (stamp.width - width) / 2 : stamp.width - width
                            font.pixelSize: 12; text: Qt.formatDateTime(Ui.now, "HH:mm") }
                    WText { id: dateText; elide: Text.ElideNone; x: bar.vert ? (stamp.width - width) / 2 : stamp.width - width
                            font.pixelSize: bar.vert ? 11 : 12; text: Qt.formatDateTime(Ui.now, bar.vert ? "dd.MM" : "dd.MM.yyyy") }
                }
                FIcon { icon: Store.dnd ? Icons.alertSnooze : Icons.alert; color: Notifs.count > 0 ? Theme.accent : Theme.text }
            }
        }

        // узкая полоска у края, как в Windows: свернуть все окна / вернуть их
        Rectangle {
            width: bar.vert ? 40 : 6
            height: bar.vert ? 6 : 40
            color: deskArea.containsMouse ? Theme.hover : "transparent"
            Rectangle {
                color: Theme.border
                width: bar.vert ? parent.width : 1
                height: bar.vert ? 1 : parent.height
            }
            MouseArea { id: deskArea; anchors.fill: parent; hoverEnabled: true; onClicked: Niri.showDesktop() }
        }
    }
}
