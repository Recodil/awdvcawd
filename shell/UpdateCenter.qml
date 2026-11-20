import QtQuick
import Quickshell

// Центр обновления: одно окно для оболочки, NixOS, программ, драйверов и прошивок.
AppWindow {
    id: root
    heading: Tr.t("Центр обновления Windows")
    open: Ui.updatesOpen
    onDismissed: Ui.updatesOpen = false
    onOpened: Updates.check()
    implicitWidth: 780
    implicitHeight: 660
    minimumSize: Qt.size(620, 480)

    readonly property var sections: [
        { title: Tr.t("Система"), kinds: ["shell", "nixos", "release"] },
        { title: Tr.t("Программы"), kinds: ["apps"] },
        { title: Tr.t("Драйверы и устройства"), kinds: ["driver", "firmware"] },
        { title: Tr.t("Необязательные обновления"), kinds: ["optional"] }
    ]
    readonly property var kindIcon: ({
        shell: Icons.desktop, nixos: Icons.sync, release: Icons.rocket,
        apps: Icons.apps, driver: Icons.wrench, firmware: Icons.shield, optional: Icons.add
    })
    readonly property var stateText: ({
        ok: Tr.t("Обновлять нечего"), applied: Tr.t("Установлен"), none: Tr.t("Нет драйвера"), info: "", offer: Tr.t("Рекомендуется")
    })
    // список для показа: заголовки разделов вперемешку со строками
    readonly property var items: {
        const out = [];
        sections.forEach(s => {
            const rows = Updates.rows.filter(r => s.kinds.indexOf(r.kind) >= 0);
            if (rows.length === 0) return;
            out.push({ head: s.title });
            rows.forEach(r => out.push(r));
        });
        return out;
    }
    readonly property string summary: Updates.busy && Updates.rows.length === 0 ? Tr.t("Идёт проверка")
        : Updates.count > 0 ? Tr.t("Доступно обновлений: ") + Updates.count
        : Updates.rows.length > 0 ? Tr.t("Система обновлена") : Tr.t("Проверка ещё не выполнялась")

    function actionLabel(r) {
        if (r.kind === "release") return Tr.t("Перейти");
        if (r.kind === "optional") return r.state === "applied" ? Tr.t("Убрать") : Tr.t("Установить");
        if (r.kind === "driver") return r.state === "update" ? Tr.t("Обновить") : r.state === "applied" ? Tr.t("Переустановить") : Tr.t("Установить");
        return r.kind === "shell" ? Tr.t("Установить") : Tr.t("Обновить");
    }

    DropArea {
        id: drop
        anchors.fill: parent
        onDropped: d => { if (d.hasUrls && d.urls.length > 0) Updates.install({ kind: "shell", id: d.urls[0].toString().replace("file://", "") }); }
    }

    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        height: 72
        Rectangle {
            id: badge
            width: 56; height: 56; radius: 28
            anchors.verticalCenter: parent.verticalCenter
            color: Updates.count > 0 ? Theme.accent : Theme.card
            border.color: Theme.border
            Behavior on color { ColorAnimation { duration: 250 } }
            FIcon {
                anchors.centerIn: parent
                icon: Updates.count > 0 ? Icons.arrowDown : Icons.check
                font.pixelSize: 24
                color: Updates.count > 0 ? Theme.accentText : Theme.text
                visible: !Updates.busy
            }
            Spinner { anchors.centerIn: parent; width: 22; height: 22; visible: Updates.busy }
        }
        Column {
            anchors { left: badge.right; leftMargin: 18; right: actions.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 2
            WText { width: parent.width; font.pixelSize: 20; font.weight: Font.DemiBold; text: root.summary }
            WText {
                width: parent.width; font.pixelSize: 12; color: Theme.subtext
                text: Updates.checkedAt !== "" ? Tr.t("Последняя проверка: ") + Updates.checkedAt : Tr.t("Проверяется оболочка, NixOS, программы, драйверы и прошивки")
            }
        }
        Row {
            id: actions
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
            PushButton { label: Tr.t("Проверить"); enabled: !Updates.busy; onClicked: Updates.check() }
            PushButton {
                label: Tr.t("Установить все драйверы")
                accent: true
                visible: Updates.driversPending && !Updates.working && Updates.count > 1
                onClicked: Updates.apply("drivers")
            }
            PushButton { label: Tr.t("Установить всё"); accent: true; visible: Updates.count > 0 && !Updates.working; onClicked: Updates.installAll() }
        }
    }

    ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footer.top; leftMargin: 24; rightMargin: 24; topMargin: 12; bottomMargin: 12 }
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        model: root.items
        delegate: Item {
            id: cell
            required property var modelData
            readonly property bool isHead: modelData.head !== undefined
            readonly property bool isDriverHead: isHead && modelData.head === Tr.t("Драйверы и устройства")
            readonly property bool wanted: !isHead && (modelData.state === "update" || modelData.state === "install" || (modelData.kind === "driver" && modelData.state === "offer"))
            readonly property bool actionable: wanted || (!isHead && (modelData.kind === "optional" || (modelData.kind === "driver" && modelData.state === "applied")))
            width: list.width
            height: isHead ? 30 : line.height
            Item {
                visible: cell.isHead
                anchors.fill: parent
                WText {
                    anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 4 }
                    font.pixelSize: 13; font.weight: Font.DemiBold
                    text: cell.isHead ? cell.modelData.head : ""
                }
                PushButton {
                    visible: cell.isDriverHead
                    anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 2 }
                    label: Tr.t("Поиск драйверов")
                    enabled: !Updates.busy
                    onClicked: Updates.check()
                }
            }
            UpdateRow {
                id: line
                visible: !cell.isHead
                width: parent.width
                icon: cell.isHead ? "" : (root.kindIcon[cell.modelData.kind] || Icons.info)
                label: cell.isHead ? "" : cell.modelData.title
                hint: cell.isHead ? "" : cell.modelData.detail
                marked: cell.wanted
                WText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !cell.actionable
                    font.pixelSize: 12; color: Theme.subtext
                    text: cell.isHead ? "" : (root.stateText[cell.modelData.state] || "")
                }
                WText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: cell.actionable && (Updates.isRunning(cell.modelData) || Updates.queued(cell.modelData))
                    font.pixelSize: 12; color: Theme.subtext
                    text: !cell.actionable ? "" : Updates.isRunning(cell.modelData) ? Tr.t("Устанавливается") : Tr.t("В очереди")
                }
                PushButton {
                    visible: cell.actionable && !Updates.isRunning(cell.modelData)
                    label: cell.isHead ? "" : Updates.queued(cell.modelData) ? Tr.t("Отменить") : root.actionLabel(cell.modelData)
                    onClicked: Updates.install(cell.modelData)
                }
            }
        }
    }
    WText {
        anchors.centerIn: list
        visible: root.items.length === 0
        color: Theme.subtext
        text: Updates.busy ? Tr.t("Собираю сведения о системе и оборудовании") : Tr.t("Нажмите \"Проверить\"")
    }

    Column {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 24 }
        spacing: 6
        UpdateRow {
            width: parent.width
            icon: Icons.archive
            label: Tr.t("Установить оболочку из файла")
            hint: drop.containsDrag ? Tr.t("Отпустите архив здесь") : Tr.t("Перетащите архив win11-shell.zip в это окно или положите его в \"Загрузки\"")
            marked: drop.containsDrag
            PushButton { label: Tr.t("Пересобрать систему"); onClicked: Updates.install({ kind: "shell", id: "-" }) }
        }
        WText {
            width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
            font.pixelSize: 12; color: Theme.subtext
            text: Tr.t("Установка идёт в отдельном окне и один раз спрашивает пароль. Если новая система не запустится, прежняя вернётся сама.")
        }
    }
}
