import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// "Поиск" (Win+S, лупа на панели задач): приложения, файлы и папки.
// Файлы ищет программа fd в домашней папке; ничего не индексируется и в фоне не работает.
Flyout {
    id: root
    name: "search"
    role: "start"
    panelWidth: 640
    panelHeight: 620

    property string query: ""
    property var files: []
    property bool busy: false
    property int sel: 0
    readonly property string q: query.trim()

    // запрос, набранный не в той раскладке ("ашкуащч" → "firefox" и наоборот)
    readonly property string en: "qwertyuiop[]asdfghjkl;'zxcvbnm,.`"
    readonly property string ru: "йцукенгшщзхъфывапролджэячсмитьбюё"   // i18n-keep
    function swap(s) {
        let out = "";
        for (let i = 0; i < s.length; i++) {
            const c = s[i];
            const a = en.indexOf(c), b = ru.indexOf(c);
            out += a >= 0 ? ru[a] : b >= 0 ? en[b] : c;
        }
        return out;
    }
    // 0 - название начинается с запроса, 1 - слово начинается, 2 - встречается в названии, 3 - в описании; -1 - нет
    function score(a, k) {
        const n = (a.name || "").toLowerCase();
        if (n.startsWith(k)) return 0;
        if (n.indexOf(" " + k) >= 0) return 1;
        if (n.indexOf(k) >= 0) return 2;
        const extra = ((a.genericName || "") + " " + (a.comment || "") + " " + (a.id || "") + " "
                     + (a.keywords ? a.keywords.join(" ") : "")).toLowerCase();
        return extra.indexOf(k) >= 0 ? 3 : -1;
    }
    // разделы "Параметров"
    readonly property var settingsIndex: [
        { page: "system", text: Tr.t("Система"), words: "система питание сон блокировка о системе system" },
        { page: "display", text: Tr.t("Экран и ночной свет"), words: "экран ночной свет яркость display night" },
        { page: "personal", text: Tr.t("Персонализация"), words: "персонализация обои фон тема тёмная темная светлая цвета wallpaper theme" },
        { page: "themes", text: Tr.t("Темы оформления и значок \"Пуск\""), words: "тема темы оформление цвета скин значок иконка пуск логотип theme start icon" },
        { page: "taskbar", text: Tr.t("Панель задач"), words: "панель задач пуск расположение taskbar" },
        { page: "keyboard", text: Tr.t("Клавиатура"), words: "клавиатура повтор keyboard num lock" },
        { page: "lang", text: Tr.t("Время и язык"), words: "время язык часовой пояс раскладка языки ввода переключение language timezone layout" },
        { page: "notify", text: Tr.t("Уведомления и \"Не беспокоить\""), words: "уведомления не беспокоить тишина исключения всплывающие notifications dnd" },
        { page: "accounts", text: Tr.t("Учётная запись"), words: "учётная запись учетная аватар аватарка пользователь account avatar" },
        { page: "apps", text: Tr.t("Приложения: установка и удаление"), words: "приложения программы установить удалить магазин пакеты apps install packages store" },
        { page: "update", text: Tr.t("Обновление оболочки"), words: "обновление обновить архив версия update" },
        { page: "about", text: Tr.t("О системе"), words: "о системе версия компьютер about" },
        { page: "mouse", text: Tr.t("Мышь и сенсорная панель"), words: "мышь тачпад сенсорная панель скорость прокрутка mouse touchpad" },
        { page: "windows", text: Tr.t("Окна и анимации"), words: "окна анимации скругление тени windows animation" }
    ]

    readonly property var apps: {
        const v = DesktopEntries.applications.values;
        const out = [];
        const k = q.toLowerCase();
        if (k === "") {
            for (let i = 0; i < Store.pinned.length && out.length < 8; i++) {
                const e = Config.entryFor(Store.pinned[i]);
                if (e && out.indexOf(e) < 0) out.push(e);
            }
            return out;
        }
        const k2 = swap(k);
        const hits = [];
        for (let i = 0; i < v.length; i++) {
            const a = v[i];
            if (a.noDisplay) continue;
            let sc = score(a, k);
            if (sc < 0 && k2 !== k) { sc = score(a, k2); if (sc >= 0) sc += 4; }
            if (sc >= 0) hits.push({ a: a, sc: sc });
        }
        hits.sort((x, y) => x.sc !== y.sc ? x.sc - y.sc : x.a.name.localeCompare(y.a.name));
        for (let i = 0; i < hits.length && i < 6; i++) out.push(hits[i].a);
        return out;
    }
    readonly property var prefs: {
        const k = q.toLowerCase();
        if (k === "") return [];
        const k2 = swap(k);
        return settingsIndex.filter(s => {
            const w = (s.text + " " + s.words).toLowerCase();
            return w.indexOf(k) >= 0 || w.indexOf(k2) >= 0;
        }).slice(0, 3);
    }
    // строки списка: заголовки разделов, приложения, параметры, файлы
    readonly property var rows: {
        const out = [];
        if (apps.length > 0) {
            out.push({ kind: "head", text: q === "" ? Tr.t("Закреплённые") : Tr.t("Приложения") });
            for (let i = 0; i < apps.length; i++) out.push({ kind: "app", entry: apps[i], text: apps[i].name, sub: apps[i].genericName || apps[i].comment || Tr.t("Приложение") });
        }
        if (prefs.length > 0) {
            out.push({ kind: "head", text: Tr.t("Параметры") });
            for (let i = 0; i < prefs.length; i++) out.push({ kind: "pref", page: prefs[i].page, text: prefs[i].text, sub: Tr.t("Параметры системы") });
        }
        if (files.length > 0) {
            out.push({ kind: "head", text: Tr.t("Файлы и папки") });
            for (let i = 0; i < files.length; i++) {
                const dir = files[i].endsWith("/");
                const p = dir ? files[i].slice(0, -1) : files[i];
                const cut = p.lastIndexOf("/");
                out.push({ kind: dir ? "dir" : "file", path: p, text: p.slice(cut + 1), sub: p.slice(0, cut).replace(Config.home, "~") });
            }
        }
        if (q !== "") {
            out.push({ kind: "head", text: Tr.t("Интернет") });
            out.push({ kind: "web", text: q, sub: Tr.t("Искать в интернете") });
        }
        return out;
    }
    readonly property var picks: {          // номера строк, которые можно выбрать
        const out = [];
        for (let i = 0; i < rows.length; i++) if (rows[i].kind !== "head") out.push(i);
        return out;
    }
    // выбор сбрасывается только при новом запросе, а не когда подгрузились файлы
    onQChanged: {
        sel = 0;
        if (q.length < 2) { files = []; busy = false; delay.stop(); return; }
        delay.restart();
    }
    function move(d) {
        if (picks.length === 0) return;
        sel = Math.max(0, Math.min(picks.length - 1, sel + d));
        list.positionViewAtIndex(picks[sel], ListView.Contain);
    }
    // folder: открыть папку, в которой лежит файл (Ctrl+Enter или правая кнопка)
    function open(row, folder) {
        if (!row || row.kind === "head") return;
        if (row.kind === "pref") { Ui.openSettings(row.page); return; }
        Ui.close();
        if (row.kind === "app") row.entry.execute();
        else if (row.kind === "web") Quickshell.execDetached(["xdg-open", "https://yandex.ru/search/?text=" + encodeURIComponent(row.text)]);
        else Quickshell.execDetached(["xdg-open", folder && row.kind === "file" ? row.path.slice(0, row.path.lastIndexOf("/")) : row.path]);
    }
    onOpened: { files = []; input.text = Ui.searchSeed; Ui.searchSeed = ""; input.forceActiveFocus(); input.cursorPosition = input.text.length; }
    // "Поиск" уже открыт, а текст пришёл из "Пуска"
    Connections {
        target: Ui
        function onSearchSeedChanged() {
            if (Ui.searchSeed === "" || Ui.flyout !== "search") return;
            input.text = Ui.searchSeed; Ui.searchSeed = ""; input.cursorPosition = input.text.length;
        }
    }

    Timer {
        id: delay
        interval: 350
        onTriggered: {
            finder.running = false;
            // первая строка вывода - сам запрос: по ней отбрасываем устаревшие ответы
            finder.command = ["sh", "-c",
                "printf '%s\\n' \"$1\"; cd \"$HOME\" || exit 0; " +
                "if command -v fd >/dev/null 2>&1; then " +
                "fd --ignore-case --fixed-strings --absolute-path --max-depth 8 --max-results 40 --exclude node_modules -- \"$1\" . 2>/dev/null; " +
                "else find . -maxdepth 6 -name '.*' -prune -o -iname \"*$1*\" \\( -type d -printf \"$HOME/%P/\\n\" -o -printf \"$HOME/%P\\n\" \\) 2>/dev/null | head -n 40; fi",
                "sh", root.q];
            root.busy = true;
            finder.running = true;
        }
    }
    Process {
        id: finder
        stdout: StdioCollector {
            id: found
            onStreamFinished: {
                const lines = found.text.split("\n");
                if (lines[0] !== root.q) return;
                root.busy = false;
                root.files = lines.slice(1).filter(l => l !== "");
            }
        }
    }

    Rectangle {
        id: box
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 24; leftMargin: 24; rightMargin: 24 }
        height: 40; radius: 20
        color: Theme.card
        border.color: input.activeFocus ? Theme.accent : Theme.border
        FIcon { id: sIcon; anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter } icon: Icons.search }
        WText {
            anchors { left: sIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            visible: input.text === ""
            color: Theme.subtext
            text: Tr.t("Поиск приложений, параметров, файлов и папок")
        }
        TextInput {
            id: input
            anchors { left: sIcon.right; leftMargin: 10; right: spin.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            focus: true
            clip: true
            color: Theme.text
            selectionColor: Theme.accent
            font.family: Config.fontFamily
            font.pixelSize: 14
            onTextChanged: root.query = text
            Keys.onDownPressed: root.move(1)
            Keys.onUpPressed: root.move(-1)
            Keys.onTabPressed: root.move(1)
            Keys.onBacktabPressed: root.move(-1)
            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return;
                root.open(root.rows[root.picks[root.sel]], (event.modifiers & Qt.ControlModifier) !== 0);
                event.accepted = true;
            }
        }
        Spinner { id: spin; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } width: 16; height: 16; visible: root.busy }
    }

    ListView {
        id: list
        anchors { top: box.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; topMargin: 12; bottomMargin: 12; leftMargin: 16; rightMargin: 16 }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool head: modelData.kind === "head"
            width: list.width
            height: head ? 34 : 46
            WText {
                visible: row.head
                x: 12; anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 13; font.weight: Font.DemiBold
                text: row.modelData.text
            }
            HoverButton {
                id: btn
                visible: !row.head
                anchors.fill: parent
                highlighted: root.picks[root.sel] === row.index
                onClicked: mouse => root.open(row.modelData, mouse.button === Qt.RightButton)
                Item {
                    id: pic
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    width: 26; height: 26
                    IconImage {
                        visible: row.modelData.kind === "app"
                        anchors.centerIn: parent
                        implicitSize: 26
                        source: row.modelData.kind === "app" ? Config.iconUrl(row.modelData.entry.icon) : ""
                    }
                    FIcon {
                        visible: row.modelData.kind !== "app"
                        anchors.centerIn: parent
                        font.pixelSize: 22
                        color: row.modelData.kind === "dir" ? "#e8a923" : Theme.subtext
                        icon: row.modelData.kind === "dir" ? Icons.folder : row.modelData.kind === "pref" ? Icons.settings
                            : row.modelData.kind === "web" ? Icons.search : Icons.document
                    }
                }
                Column {
                    anchors { left: pic.right; leftMargin: 14; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    WText { width: parent.width; text: row.modelData.text || "" }
                    WText { width: parent.width; font.pixelSize: 11; color: Theme.subtext; elide: Text.ElideMiddle; text: row.modelData.sub || "" }
                }
            }
        }
    }
    WText {
        anchors.centerIn: list
        visible: root.rows.length === 0
        color: Theme.subtext
        text: Tr.t("Начните вводить название программы, файла или параметра")
    }
}
