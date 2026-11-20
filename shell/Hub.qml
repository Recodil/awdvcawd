import QtQuick
import Quickshell
import Quickshell.Io

// "Центр управления" (Win+H, команда win11 hub): то, что раньше делалось командами в терминале, - кнопками.
// Короткие проверки выполняются прямо здесь, ответ виден справа. Действия, которым нужен пароль
// администратора или которые идут долго, открываются в окне терминала.
// Сами команды никуда не делись: под каждой кнопкой написано, что она запускает.
Flyout {
    id: root
    name: "hub"
    role: "center"
    panelWidth: 940
    panelHeight: 620

    property string output: ""
    property string running: ""       // подпись выполняемого действия
    property string lastCmd: ""
    readonly property var groups: [
        { title: Tr.t("Интернет: обход замедления YouTube и Discord"), items: [
            { icon: Icons.globe, label: Tr.t("Состояние"), cmd: "win11-zapret" },
            { icon: Icons.shield, label: Tr.t("Проверить доступ"), cmd: "win11-zapret check" },
            { icon: Icons.play, label: Tr.t("Включить"), cmd: "win11-zapret on", term: true },
            { icon: Icons.pause, label: Tr.t("Выключить"), cmd: "win11-zapret off", term: true },
            { icon: Icons.document, label: Tr.t("Список стратегий"), cmd: "win11-zapret list" },
            { icon: Icons.tools, label: Tr.t("Подбор стратегии"), cmd: "win11-zapret test", term: true, hint: Tr.t("долго") }
        ] },
        { title: Tr.t("Печать"), items: [
            { icon: Icons.printer, label: Tr.t("Состояние принтеров"), cmd: "win11-printfix" },
            { icon: Icons.wrench, label: Tr.t("Починить печать"), cmd: "win11-printfix fix", term: true },
            { icon: Icons.dismiss, label: Tr.t("Очистить очередь"), cmd: "win11-printfix clear", term: true },
            { icon: Icons.document, label: Tr.t("Пробная страница"), cmd: "win11-printfix test" },
            { icon: Icons.add, label: Tr.t("Добавить принтер"), cmd: "win11-printfix add" }
        ] },
        { title: Tr.t("Система"), items: [
            { icon: Icons.health, label: Tr.t("Отчёт о системе"), cmd: "win11-doctor", term: true, hint: Tr.t("файл для помощи") },
            { icon: Icons.pulse, label: Tr.t("Расход памяти"), cmd: "sudo win11-mem", term: true },
            { icon: Icons.open, label: Tr.t("Кнопка \"Свернуть\""), cmd: "win11-minimize --check" },
            { icon: Icons.sync, label: Tr.t("Перезапуск оболочки"), cmd: "kill \"$(cat \"$HOME/.local/state/win11-shell/shell.pid\")\"", hint: Tr.t("панель мигнёт") },
            { icon: Icons.archive, label: Tr.t("Освободить место"), cmd: "sudo nix-collect-garbage --delete-older-than 14d", term: true, hint: Tr.t("старые версии системы") }
        ] },
        { title: Tr.t("Обновление и установка"), items: [
            { icon: Icons.history, label: Tr.t("Обновить оболочку"), page: "update" },
            { icon: Icons.settings, label: Tr.t("Пересобрать систему"), cmd: "win11-updater run", detach: true },
            { icon: Icons.apps, label: Tr.t("Обновить программы"), cmd: "win11-updater system", detach: true },
            { icon: Icons.apps, label: Tr.t("Установка программ"), page: "apps" },
            { icon: Icons.rocket, label: Tr.t("Установщик для друга"), cmd: "win11-pack", term: true, hint: Tr.t("вся сборка одним файлом") }
        ] }
    ]

    function clean(t) { return (t || "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").replace(/\r/g, ""); }
    function act(item) {
        if (item.page) { Ui.openSettings(item.page); return; }
        lastCmd = item.cmd;
        if (item.term) {
            Ui.close();
            Quickshell.execDetached(["sh", "-c", "setsid -f kitty --hold sh -c \"$1\" >/dev/null 2>&1", "sh", item.cmd]);
            return;
        }
        if (item.detach) {
            Ui.close();
            Quickshell.execDetached(["sh", "-c", "setsid -f sh -c \"$1\" >/dev/null 2>&1", "sh", item.cmd]);
            return;
        }
        if (job.running) return;
        running = item.label;
        output = "";
        job.command = ["sh", "-c", "export PATH=\"$PATH:/run/current-system/sw/bin\"; " + item.cmd + " 2>&1; echo; echo \"[код завершения: $?]\""];
        job.running = true;
    }
    Process {
        id: job
        stdout: SplitParser { onRead: line => { root.output += root.clean(line) + "\n"; } }
        onExited: { root.running = ""; }
    }
    // зависшую проверку не ждём вечно
    Timer { interval: 90000; running: job.running; onTriggered: { job.running = false; root.output += Tr.t("\n[остановлено: нет ответа 90 секунд]\n"); root.running = ""; } }

    WText {
        id: heading
        anchors { left: parent.left; top: parent.top; leftMargin: 24; topMargin: 20 }
        font.pixelSize: 20; font.weight: Font.DemiBold
        text: Tr.t("Центр управления")
    }
    HoverButton {
        anchors { right: parent.right; top: parent.top; margins: 14 }
        implicitWidth: 32; implicitHeight: 32
        onClicked: Ui.close()
        FIcon { anchors.centerIn: parent; icon: Icons.dismiss }
    }

    // ---- слева: кнопки ----
    Flickable {
        id: left
        anchors { left: parent.left; top: heading.bottom; bottom: parent.bottom; leftMargin: 24; topMargin: 14; bottomMargin: 20 }
        width: 500
        clip: true
        contentHeight: tiles.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: tiles
            width: left.width
            spacing: 8
            Repeater {
                model: root.groups
                Column {
                    id: grp
                    required property var modelData
                    width: tiles.width
                    spacing: 6
                    WText { topPadding: 6; font.pixelSize: 12; color: Theme.subtext; text: grp.modelData.title }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: grp.modelData.items
                            HoverButton {
                                id: tile
                                required property var modelData
                                implicitWidth: (tiles.width - 12) / 3; implicitHeight: 76
                                radius: 6
                                color: pressed ? Theme.pressed : hovered ? Theme.hover : Theme.card
                                border.color: root.running === modelData.label ? Theme.accent : Theme.border
                                onClicked: root.act(modelData)
                                FIcon { id: ti; x: 12; y: 10; icon: tile.modelData.icon; font.pixelSize: 20; color: Theme.accent }
                                FIcon {
                                    visible: tile.modelData.term === true || tile.modelData.page !== undefined || tile.modelData.detach === true
                                    anchors { right: parent.right; top: parent.top; margins: 10 }
                                    font.pixelSize: 12; color: Theme.subtext; icon: Icons.open
                                }
                                WText { anchors { left: parent.left; right: parent.right; top: ti.bottom; margins: 12; topMargin: 4 } font.pixelSize: 12; text: tile.modelData.label }
                                WText {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12; bottomMargin: 6 }
                                    font.pixelSize: 10; color: Theme.subtext
                                    text: tile.modelData.hint || tile.modelData.cmd || Tr.t("Параметры")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- справа: ответ ----
    Rectangle {
        anchors { left: left.right; right: parent.right; top: heading.bottom; bottom: parent.bottom; leftMargin: 16; rightMargin: 24; topMargin: 20; bottomMargin: 20 }
        radius: 6
        color: Theme.dark ? "#161616" : "#f3f3f3"
        border.color: Theme.border
        Row {
            id: outHead
            anchors { left: parent.left; top: parent.top; margins: 12 }
            spacing: 8
            Spinner { visible: root.running !== ""; width: 14; height: 14; color: Theme.text }
            WText { font.pixelSize: 12; color: Theme.subtext; text: root.running !== "" ? Tr.t("Выполняется: ") + root.running : (root.lastCmd !== "" && root.output !== "" ? "$ " + root.lastCmd : Tr.t("Ответ")) }
        }
        Flickable {
            id: outView
            anchors { fill: parent; margins: 12; topMargin: 38 }
            clip: true
            contentHeight: outText.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: if (contentHeight > height) contentY = contentHeight - height
            Text {
                id: outText
                width: outView.width
                wrapMode: Text.WrapAnywhere
                textFormat: Text.PlainText
                color: Theme.text
                font.family: "monospace"; font.pixelSize: 12
                text: root.output !== "" ? root.output
                    : Tr.t("Нажмите кнопку слева.\n\nКнопки со стрелкой в углу открывают отдельное окно: им нужен пароль администратора или много времени.\n\nВсе команды по-прежнему работают в терминале и в окне \"Выполнить\" (Win+R); полный список - команда win11.")
            }
        }
    }
}
