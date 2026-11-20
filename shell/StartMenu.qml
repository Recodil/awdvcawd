import QtQuick
import Quickshell
import Quickshell.Widgets

// "Пуск": слева - все приложения по алфавиту (и результаты поиска),
// справа - закреплённые. Закрепить / открепить - правой кнопкой по приложению.
Flyout {
    id: root
    name: "start"
    role: "start"
    panelWidth: 736
    panelHeight: 700

    property string query: ""
    property string popup: ""          // "", "user", "power"
    property var menu: null            // меню приложения: { entry, x, y }
    readonly property bool searching: query.trim() !== ""

    readonly property var apps: {
        const v = DesktopEntries.applications.values;
        const out = [];
        for (let i = 0; i < v.length; i++) if (!v[i].noDisplay) out.push(v[i]);
        out.sort((a, b) => a.name.localeCompare(b.name));
        return out;
    }
    readonly property var pinnedApps: {
        const out = [];
        for (let i = 0; i < Store.pinned.length; i++) {
            const e = Config.entryFor(Store.pinned[i]);
            if (e && out.indexOf(e) < 0) out.push(e);
        }
        return out;
    }
    // строки левого списка: { head: "А" } - буква-заголовок, { entry: … } - приложение
    readonly property var rows: {
        const out = [];
        if (searching) {
            const q = query.trim().toLowerCase();
            for (let i = 0; i < apps.length; i++) {
                const a = apps[i];
                if (a.name.toLowerCase().includes(q) || (a.genericName || "").toLowerCase().includes(q))
                    out.push({ head: "", entry: a });
            }
            return out;
        }
        let last = "";
        for (let i = 0; i < apps.length; i++) {
            let c = apps[i].name.charAt(0).toUpperCase();
            if (c >= "0" && c <= "9") c = "#";
            if (c !== last) { out.push({ head: c, entry: null }); last = c; }
            out.push({ head: "", entry: apps[i] });
        }
        return out;
    }

    function run(entry) { Ui.close(); entry.execute(); }
    function click(item, mouse, entry) {
        if (mouse.button === Qt.RightButton) {
            const p = item.mapToItem(menuBox.parent, mouse.x, mouse.y);
            menu = { entry: entry, x: p.x, y: p.y };
        } else run(entry);
    }
    function act(name) {
        popup = "";
        if (name === "lock") Ui.lock();
        else if (name === "theme") Theme.toggle();
        else if (name === "suspend") { Ui.close(); Quickshell.execDetached(Config.suspendCommand); }
        else if (name === "hibernate") { Ui.close(); Quickshell.execDetached(Config.hibernateCommand); }
        else Ui.endSession(name);
    }
    onOpened: { input.text = ""; popup = ""; menu = null; list.positionViewAtBeginning(); input.forceActiveFocus(); }

    // ---- поиск ----
    Rectangle {
        id: searchBox
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 24; leftMargin: 24; rightMargin: 24 }
        height: 36; radius: 18
        color: Theme.card
        border.color: input.activeFocus ? Theme.accent : Theme.border
        FIcon { id: sIcon; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } icon: Icons.search }
        WText {
            anchors { left: sIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            visible: input.text === ""
            color: Theme.subtext
            text: Tr.t("Поиск приложений, файлов и параметров")
        }
        TextInput {
            id: input
            anchors { left: sIcon.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            focus: true
            clip: true
            color: Theme.text
            selectionColor: Theme.accent
            font.family: Config.fontFamily
            font.pixelSize: 13
            // как в Windows: начали печатать в "Пуске" - открывается "Поиск" с этим текстом
            onTextChanged: if (text !== "") { const t = text; text = ""; Ui.openSearch(t); }
        }
    }

    // ---- слева: все приложения ----
    Item {
        id: left
        anchors { top: searchBox.bottom; bottom: footer.top; left: parent.left; topMargin: 16; leftMargin: 16 }
        width: 296
        WText {
            id: leftTitle
            x: 12; height: 28
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 14; font.weight: Font.DemiBold
            text: root.searching ? Tr.t("Результаты") : Tr.t("Все приложения")
        }
        ListView {
            id: list
            anchors { top: leftTitle.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; topMargin: 8; bottomMargin: 8 }
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.rows
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: list.width
                height: modelData.entry ? 40 : 30
                WText {
                    visible: row.modelData.entry === null
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 13; font.weight: Font.DemiBold
                    color: Theme.accent
                    text: row.modelData.head
                }
                HoverButton {
                    id: btn
                    visible: row.modelData.entry !== null
                    anchors.fill: parent
                    highlighted: row.index === 0 && root.searching
                    onClicked: mouse => root.click(btn, mouse, row.modelData.entry)
                    IconImage {
                        id: rowIcon
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        implicitSize: 24
                        source: row.modelData.entry ? Config.iconUrl(row.modelData.entry.icon) : ""
                    }
                    WText {
                        anchors { left: rowIcon.right; leftMargin: 14; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: row.modelData.entry ? row.modelData.entry.name : ""
                    }
                }
            }
        }
        WText {
            anchors.centerIn: list
            visible: root.rows.length === 0
            color: Theme.subtext
            text: Tr.t("Ничего не найдено")
        }
    }

    Rectangle {
        anchors { top: left.top; bottom: left.bottom; left: left.right; leftMargin: 8; bottomMargin: 12 }
        width: 1
        color: Theme.border
    }

    // ---- справа: закреплённые ----
    Item {
        id: right
        anchors { top: left.top; bottom: footer.top; left: left.right; right: parent.right; leftMargin: 20; rightMargin: 12 }
        WText {
            id: rightTitle
            x: 12; height: 28
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 14; font.weight: Font.DemiBold
            text: Tr.t("Закреплённые")
        }
        GridView {
            id: grid
            anchors { top: rightTitle.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; topMargin: 8; bottomMargin: 8 }
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cellWidth: 96; cellHeight: 88
            // Модель - число плиток, а не сами объекты программ: список программ система
            // пересоздаёт на ходу, и представление со старыми объектами роняло всю оболочку.
            model: root.pinnedApps.length
            delegate: HoverButton {
                id: cell
                // без "required property": именно на их заполнении падал Qt 6.11;
                // index здесь приходит от представления сам
                readonly property int slot: index
                readonly property var modelData: root.pinnedApps[slot] || null
                visible: modelData !== null
                property real appear: 1
                width: 92; height: 84
                onClicked: mouse => { if (modelData) root.click(cell, mouse, modelData); }
                // плитки "вылетают" по очереди при каждом открытии меню
                SequentialAnimation {
                    id: pop
                    PauseAnimation { duration: 40 + cell.slot * 18 }
                    NumberAnimation { target: cell; property: "appear"; from: 0; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                }
                Connections { target: root; function onOpened() { cell.appear = 0; pop.restart(); } }
                Column {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: (1 - cell.appear) * 18
                    opacity: Math.max(0, Math.min(1, cell.appear))
                    scale: 0.6 + 0.4 * cell.appear
                    spacing: 6
                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitSize: 32
                        source: cell.modelData ? Config.iconUrl(cell.modelData.icon) : ""
                        scale: cell.pressed ? 0.85 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                    }
                    WText {
                        width: 84
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 12
                        text: cell.modelData ? cell.modelData.name : ""
                    }
                }
            }
        }
        WText {
            anchors.centerIn: grid
            visible: root.pinnedApps.length === 0
            width: grid.width - 48
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideNone
            color: Theme.subtext
            text: Tr.t("Здесь пока пусто. Нажмите правой кнопкой на приложение слева и выберите \"Закрепить\".")
        }
    }

    // ---- нижняя полоса: пользователь и питание ----
    Rectangle {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
        height: 63
        color: Theme.footer
        Rectangle { width: parent.width; height: 1; color: Theme.border }

        HoverButton {
            id: userBtn
            anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
            implicitWidth: userRow.implicitWidth + 24
            highlighted: root.popup === "user"
            onClicked: root.popup = root.popup === "user" ? "" : "user"
            Row {
                id: userRow
                anchors.centerIn: parent
                spacing: 12
                Avatar { width: 28; height: 28; backColor: Theme.dark ? "#4a4a4a" : "#d0d0d0"; iconColor: Theme.text }
                WText { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; text: Config.userName }
            }
        }
        HoverButton {
            anchors { right: powerBtn.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
            onClicked: Ui.openSettings("")
            FIcon { anchors.centerIn: parent; icon: Icons.settings; font.pixelSize: 18 }
        }
        HoverButton {
            id: powerBtn
            anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
            highlighted: root.popup === "power"
            onClicked: root.popup = root.popup === "power" ? "" : "power"
            FIcon { anchors.centerIn: parent; icon: Icons.power; font.pixelSize: 18 }
        }
    }

    // клик мимо открытого меню закрывает его
    MouseArea {
        anchors.fill: parent
        enabled: root.popup !== ""
        acceptedButtons: Qt.AllButtons
        onPressed: root.popup = ""
    }

    component Popup: Rectangle {
        id: pm
        property bool shown: false
        property var items: []
        width: 248
        height: pmCol.implicitHeight + 8
        radius: 8
        color: Theme.dark ? "#2c2c2c" : "#f9f9f9"
        border.color: Theme.border
        visible: opacity > 0
        opacity: shown ? 1 : 0
        transform: Translate { y: (1 - pm.opacity) * 12 }
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Column {
            id: pmCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
            Repeater {
                model: pm.items
                MenuRow {
                    required property var modelData
                    width: pmCol.width
                    icon: modelData.icon
                    label: modelData.label
                    onClicked: root.act(modelData.act)
                }
            }
        }
    }

    // ---- меню пользователя ----
    Popup {
        anchors { left: parent.left; leftMargin: 20; bottom: footer.top; bottomMargin: -4 }
        shown: root.popup === "user"
        items: [
            { icon: Icons.lock, label: Tr.t("Заблокировать"), act: "lock" },
            { icon: Icons.signOut, label: Tr.t("Выйти из учётной записи"), act: "logout" },
            { icon: Theme.dark ? Icons.sun : Icons.darkTheme, label: Theme.dark ? Tr.t("Светлая тема") : Tr.t("Тёмная тема"), act: "theme" }
        ]
    }

    // ---- меню питания: "Сон" и "Гибернация" видны, только если компьютер их умеет ----
    Popup {
        anchors { right: parent.right; rightMargin: 20; bottom: footer.top; bottomMargin: -4 }
        shown: root.popup === "power"
        items: {
            const out = [];
            if (Sys.canSuspend) out.push({ icon: Icons.sleep, label: Tr.t("Сон"), act: "suspend" });
            if (Sys.canHibernate) out.push({ icon: Icons.hibernate, label: Tr.t("Гибернация"), act: "hibernate" });
            out.push({ icon: Icons.power, label: Tr.t("Завершение работы"), act: "poweroff" });
            out.push({ icon: Icons.restart, label: Tr.t("Перезагрузка"), act: "reboot" });
            return out;
        }
    }

    // ---- меню приложения: открывается внутри "Пуска", сам "Пуск" остаётся на месте ----
    MouseArea {
        anchors.fill: parent
        z: 50
        visible: root.menu !== null
        acceptedButtons: Qt.AllButtons
        onPressed: root.menu = null
    }
    Rectangle {
        id: menuBox
        z: 51
        visible: root.menu !== null
        width: 264
        height: appMenu.implicitHeight + 8
        x: root.menu ? Math.max(8, Math.min(parent.width - width - 8, root.menu.x)) : 0
        y: root.menu ? Math.max(8, Math.min(parent.height - height - 8, root.menu.y)) : 0
        radius: 8
        color: Theme.flyout
        border.color: Theme.border
        AppMenu {
            id: appMenu
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
            entry: root.menu ? root.menu.entry : null
            onLaunched: { root.menu = null; Ui.close(); }
            onDone: root.menu = null
        }
    }
}
