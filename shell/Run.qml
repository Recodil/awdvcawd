import QtQuick
import Quickshell
import Quickshell.Io

// "Выполнить" (Win+R): команда, название программы, папка, файл или адрес сайта.
// Enter - запустить, Ctrl+Enter - запустить в окне терминала, ↑/↓ - прежние команды.
Flyout {
    id: root
    name: "run"
    role: "start"
    panelWidth: 440
    panelHeight: 196 + Math.min(4, recent.length) * 32 + (recent.length > 0 ? 8 : 0)

    property string error: ""
    property int histPos: -1
    readonly property var recent: Store.runHistory

    // привычные команды Windows
    readonly property var aliases: ({
        "cmd": "kitty", "powershell": "kitty", "wt": "kitty", "terminal": "kitty",
        "explorer": "nautilus", "taskmgr": "qs -p /etc/win11-shell ipc call shell taskmgr", "calc": "gnome-calculator",
        "notepad": "gnome-text-editor", "mspaint": "gimp", "msedge": "firefox", "iexplore": "firefox"
    })
    readonly property var pages: ({
        "control": "system", "ms-settings:": "system", "ncpa.cpl": "system", "timedate.cpl": "lang",
        "intl.cpl": "lang", "appwiz.cpl": "apps", "desk.cpl": "display", "main.cpl": "mouse", "winver": "about"
    })

    function remember(t) {
        const list = [t].concat(Store.runHistory.filter(x => x !== t)).slice(0, 15);
        Store.set("runHistory", list);
    }
    function run(text, term) {
        let t = (text || "").trim();
        if (t === "" || runner.running) return;
        error = "";
        const key = t.toLowerCase();
        if (pages[key] !== undefined) { remember(t); Ui.openSettings(pages[key]); return; }
        if (key === "hub") { remember(t); Ui.flyout = "hub"; return; }
        if (aliases[key] !== undefined) t = aliases[key];
        // shutdown /r /t 500 - параметры как в Windows
        if (/^shutdown(\.exe)?(\s|$)/i.test(t)) t = t.replace(/^shutdown(\.exe)?/i, "win11-shutdown");
        // название программы из "Пуска" ("Firefox", "Проводник")
        if (!term) {
            const v = DesktopEntries.applications.values;
            for (let i = 0; i < v.length; i++) {
                if (v[i].noDisplay) continue;
                if ((v[i].id || "").toLowerCase() === key || (v[i].name || "").toLowerCase() === key) {
                    remember(text.trim()); Ui.close(); v[i].execute(); return;
                }
            }
        }
        // команды оболочки, которые печатают ответ, открываются в окне терминала
        const w = t.split(/\s+/);
        const windows = ["start", "search", "run", "quick", "calendar", "settings", "lock", "logout", "poweroff", "dark", "overview",
                         "desktopNext", "desktopPrev", "desktopNew", "restoreAll", "showDesktop", "hub", "dnd", "reboot"];
        if (w[0].indexOf("win11-") === 0 && w[0] !== "win11-updater" && !(w[0] === "win11-shutdown" && w.length > 1) || (w[0] === "win11" && windows.indexOf(w[1] || "") < 0 && w[1] !== "updater" && !(w[1] === "minimize" && w.length === 2)))
            term = true;
        runner.original = text.trim();
        runner.command = ["sh", "-c", script, "sh", t, term ? "1" : ""];
        runner.running = true;
    }
    // Проверяет, что запускать, запускает отдельно от оболочки и отвечает OK или ERR <текст>.
    readonly property string script:
        "c=\"$1\"; term=\"$2\"\n" +
        "case \"$c\" in '~'|'~/'*) c=\"$HOME${c#\\~}\" ;; esac\n" +
        "case \"$c\" in\n" +
        "  http://*|https://*|ftp://*|file://*|mailto:*) setsid -f xdg-open \"$c\" >/dev/null 2>&1; echo OK; exit 0 ;;\n" +
        "  www.*) setsid -f xdg-open \"https://$c\" >/dev/null 2>&1; echo OK; exit 0 ;;\n" +
        "esac\n" +
        "if [ -d \"$c\" ] || { [ -f \"$c\" ] && [ ! -x \"$c\" ]; }; then setsid -f xdg-open \"$c\" >/dev/null 2>&1; echo OK; exit 0; fi\n" +
        "first=\"${c%% *}\"\n" +
        "if ! command -v \"$first\" >/dev/null 2>&1 && [ ! -x \"$first\" ]; then echo \"ERR Не удаётся найти \"$first\". Проверьте имя.\"; exit 0; fi\n" +
        "if [ -n \"$term\" ]; then setsid -f kitty --hold sh -c \"$c\" >/dev/null 2>&1\n" +
        "else setsid -f sh -c \"$c\" >/dev/null 2>&1; fi\n" +
        "echo OK\n"
    Process {
        id: runner
        property string original: ""
        stdout: StdioCollector {
            id: runOut
            onStreamFinished: {
                const t = runOut.text.trim();
                if (t === "OK") { root.remember(runner.original); Ui.close(); }
                else root.error = t.indexOf("ERR ") === 0 ? t.slice(4) : Tr.t("Не удалось запустить");
            }
        }
    }
    onOpened: { error = ""; histPos = -1; input.text = recent.length > 0 ? recent[0] : ""; input.forceActiveFocus(); input.selectAll(); }
    function step(d) {
        if (recent.length === 0) return;
        histPos = Math.max(0, Math.min(recent.length - 1, histPos + d));
        input.text = recent[histPos];
        input.selectAll();
    }

    FIcon { id: logo; x: 24; y: 26; icon: Icons.play; font.pixelSize: 28; color: Theme.accent }
    WText { anchors { left: logo.right; leftMargin: 14; top: parent.top; topMargin: 20 } font.pixelSize: 16; font.weight: Font.DemiBold; text: Tr.t("Выполнить") }
    WText {
        anchors { left: logo.right; leftMargin: 14; right: parent.right; rightMargin: 20; top: parent.top; topMargin: 44 }
        font.pixelSize: 12; color: root.error !== "" ? "#e0443e" : Theme.subtext
        text: root.error !== "" ? root.error : Tr.t("Команда, программа, папка, файл или адрес сайта")
    }

    WText { id: lab; x: 24; anchors.verticalCenter: box.verticalCenter; text: Tr.t("Открыть:") }
    Rectangle {
        id: box
        anchors { left: lab.right; leftMargin: 12; right: parent.right; rightMargin: 20; top: parent.top; topMargin: 84 }
        height: 34; radius: 4
        color: Theme.card
        border.color: input.activeFocus ? Theme.accent : Theme.border
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: TextInput.AlignVCenter
            focus: true
            clip: true
            color: Theme.text
            selectionColor: Theme.accent
            font.family: Config.fontFamily
            font.pixelSize: 13
            onTextEdited: { root.error = ""; root.histPos = -1; }
            Keys.onUpPressed: root.step(1)
            Keys.onDownPressed: root.step(-1)
            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return;
                root.run(text, (event.modifiers & Qt.ControlModifier) !== 0);
                event.accepted = true;
            }
        }
    }

    // прежние команды
    Column {
        id: hist
        anchors { left: box.left; right: box.right; top: box.bottom; topMargin: 6 }
        Repeater {
            model: Math.min(4, root.recent.length)
            HoverButton {
                required property int index
                width: hist.width; implicitHeight: 32
                onClicked: { input.text = root.recent[index]; root.run(input.text, false); }
                FIcon { id: hi; x: 8; anchors.verticalCenter: parent.verticalCenter; icon: Icons.history; font.pixelSize: 14; color: Theme.subtext }
                WText { anchors { left: hi.right; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } font.pixelSize: 12; text: root.recent[index] || "" }
            }
        }
    }

    Row {
        anchors { right: parent.right; rightMargin: 20; bottom: parent.bottom; bottomMargin: 18 }
        spacing: 8
        Repeater {
            model: [{ label: "ОК", act: "run", main: true }, { label: Tr.t("В терминале"), act: "term", main: false }, { label: Tr.t("Отмена"), act: "close", main: false }]
            HoverButton {
                id: b
                required property var modelData
                implicitWidth: bt.implicitWidth + 32; implicitHeight: 32
                color: modelData.main ? (hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent) : (pressed ? Theme.pressed : hovered ? Theme.hover : Theme.card)
                border.color: modelData.main ? Theme.accent : Theme.border
                onClicked: modelData.act === "close" ? Ui.close() : root.run(input.text, modelData.act === "term")
                WText { id: bt; anchors.centerIn: parent; font.pixelSize: 12; color: b.modelData.main ? Theme.accentText : Theme.text; text: b.modelData.label }
            }
        }
    }
}
