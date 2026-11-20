import QtQuick
import Quickshell
import Quickshell.Io

// "Параметры" (Win+I): слева категории, справа страница - как в Windows 11.
// Клавиатура, мышь, окна и анимации - это настройки niri; они записываются
// в ~/.config/niri/win11-settings.kdl и применяются сразу.
AppWindow {
    id: root
    heading: Tr.t("Параметры")
    open: Ui.settingsOpen
    onDismissed: Ui.settingsOpen = false
    implicitWidth: 980
    implicitHeight: 680
    minimumSize: Qt.size(820, 520)

    property string page: "home"
    Connections { target: Ui; function onSettingsPageChanged() { root.page = Ui.settingsPage; } }
    property string lastPage: "home"
    onPageChanged: {
        // обновление живёт в отдельном окне - "Центре обновления"
        if (page === "update") { page = lastPage; Ui.openUpdates(); return; }
        lastPage = page;
        const g = groupOf(page);
        lastIn[g.label] = page;
        if (Ui.settingsPage !== page) Ui.settingsPage = page;
        if (page === "apps" && pkgRows.length === 0) pkgLoad();
        if (page === "lang") loadLists();
        if (page === "themes") Theme.reload();
        if (toolsPage) Tools.refresh();
    }
    // страницы "Звук" и "Обход блокировок" показывают состояние системы: пока они открыты,
    // оно перечитывается (команды в терминале меняют его в обход оболочки)
    readonly property bool toolsPage: page === "sound" || page === "zapret"
    Timer { interval: 4000; repeat: true; running: root.toolsPage && root.visible; onTriggered: Tools.refresh() }
    property string about: ""

    // ---- поиск по параметрам ----
    // Каждая строка параметров сама записывается в список lines. Поиск идёт по названию, пояснению
    // и словам-подсказкам (words), с учётом окончаний: "обоев", "обои", "фон" находят одно и то же.
    // Найденная строка: открывается её страница, список прокручивается к ней, строка подсвечивается на 5 секунд.
    property var lines: []
    property var hit: null
    property string sq: ""
    readonly property var kw: ({
        "Автоблокировка": "блокировка экрана пароль простой бездействие сон заблокировать lock",
        "Экран приветствия при входе": "добро пожаловать заставка анимация вход welcome",
        "Диспетчер задач": "процессы память загрузка завершить программу зависла task manager",
        "Сеть": "интернет wifi вай фай подключение vpn ethernet кабель network",
        "Сбросить параметры": "по умолчанию заводские вернуть сброс reset",
        "Ночной свет": "тёплый экран глаза синий свет вечер night light",
        "Интенсивность": "ночной свет температура цвета теплее",
        "Включать по расписанию": "ночной свет время автоматически расписание",
        "Время работы": "ночной свет расписание часы",
        "Яркость": "экран ярче темнее подсветка brightness",
        "Тема": "тёмная темная светлая оформление цвет dark light theme",
        "Обои": "фон рабочего стола картинка изображение заставка wallpaper",
        "Смена обоев": "слайд шоу фото дня автоматически менять фон",
        "Папка с обоями": "картинки каталог фон слайд шоу",
        "Скругление углов окон": "углы закругление радиус окна",
        "Тени под окнами": "тень окна эффекты",
        "Положение": "панель задач снизу сверху слева справа край переместить taskbar",
        "Кнопка \"Пуск\" и значки": "выравнивание по центру слева панель задач пуск",
        "Кнопка поиска": "лупа панель задач скрыть показать поиск",
        "Кнопка представления задач": "рабочие столы панель задач скрыть показать",
        "Анимации окон": "эффекты открытие закрытие отключить анимацию",
        "Плавное сворачивание окон": "свернуть развернуть анимация скрытие окна minimize",
        "Скорость анимаций": "быстрее медленнее эффекты",
        "Активировать окно наведением": "фокус мышь указатель",
        "Сочетания клавиш и остальное": "горячие клавиши хоткеи бинды config niri",
        "Часовой пояс": "время часы город регион дата timezone utc",
        "Язык интерфейса и программ": "язык системы интерфейса перевод русский английский locale language",
        "Языки ввода (раскладки)": "клавиатура раскладка язык ввода добавить удалить английская русская layout",
        "Добавить раскладку": "клавиатура раскладка вариант фонетическая дворак язык ввода layout variant",
        "Свой список раскладок": "клавиатура раскладки вручную коды",
        "Смена языка ввода": "переключение раскладки alt shift win пробел ctrl caps сочетание",
        "Не беспокоить": "уведомления тишина отключить всплывающие фокус звук dnd",
        "Системные уведомления": "не беспокоить сеть питание печать всегда",
        "Исключения": "не беспокоить разрешить программы избранные приложения белый список",
        "Добавить программу": "не беспокоить исключения разрешить уведомления приложение",
        "Очистить уведомления": "удалить все уведомления центр",
        "Аватарка": "фото профиля картинка пользователя учётная запись avatar",
        "Задержка перед повтором": "клавиатура удержание клавиши повтор",
        "Скорость повтора": "клавиатура удержание клавиши повтор",
        "Num Lock включён при входе": "цифровая клавиатура numlock",
        "Скорость указателя": "мышь курсор чувствительность быстрее медленнее",
        "Обратная прокрутка мыши": "колесо естественная прокрутка natural scroll",
        "Мышь для левши": "левая рука кнопки поменять",
        "Сенсорная панель: касание как щелчок": "тачпад touchpad нажатие касанием tap",
        "Сенсорная панель: обратная прокрутка": "тачпад touchpad естественная прокрутка",
        "Тема оформления": "цвета оформление стиль скин своя тема акцент цвет окон theme",
        "Свои темы": "создать тему файл json папка цвета оформление скин",
        "Значок кнопки \"Пуск\"": "иконка логотип пуск меню start windows nixos картинка",
        "Свой значок": "иконка пуск своя картинка файл png svg логотип",
        "Сенсорная панель": "тачпад touchpad не найдена",
        "Пересобрать без архива": "обновление применить изменения rebuild",
        "Обновить программы системы": "обновление пакеты новые версии upgrade",
        "Восстановление": "починка системы восстановление рабочий стол неполадки сбой сброс repair recovery fix",
        "Починка системы + рабочего пространства": "восстановление починка nixos niri рабочий стол сбой repair system recovery",
        "Только починить рабочее пространство": "восстановление niri рабочий стол панели хоткеи repair workspace",
        "Сбросить параметры оболочки": "сброс настроек рабочий стол оформление вернуть стандартные reset",
        "Диагностический отчёт (Doctor)": "отчёт диагностика ошибки логи доктор сбои doctor report",
        "Громкость": "звук динамики наушники громче тише audio volume",
        "Устройство вывода": "динамики наушники hdmi звук output sound",
        "Устройство ввода": "микрофон запись гарнитура input microphone",
        "Проверка звука": "тест динамиков проверить звук test audio",
        "Устранение неполадок со звуком": "починка звука перезапуск pipewire sound fix",
        "Масштабирование": "масштаб экрана dpi интерфейс крупнее мельче scale display",
        "Разрешение и частота": "экран монитор герцы частота обновления resolution hz",
        "Ориентация дисплея": "альбомная книжная перевернуть экран поворот orientation",
        "Bluetooth": "блютуз устройства наушники мышь беспроводные bt bluetooth",
        "Принтеры и сканеры": "печать принтер сканер cups printers",
        "Хранилище": "диск память место свободное ssd hdd storage",
        "Очистка диска": "мусор временные файлы очистить память nix collect garbage disk clean",
        "Обход блокировок (Zapret 2)": "запрет ютуб дискорд блокировки zapret youtube discord",
        "Пароль учётной записи": "пароль сменить пароль пользователя passwd password"
    })
    function norm(t) { return (t || "").toLowerCase().replace(/ё/g, "е"); }
    function stem(t) { return t.length > 4 ? t.slice(0, Math.max(4, t.length - 2)) : t; }
    function hasWord(text, t) {
        const words = norm(text).split(/[^a-zа-я0-9]+/);
        for (let i = 0; i < words.length; i++) if (words[i].indexOf(t) === 0) return true;
        return t.length >= 4 && norm(text).indexOf(t) >= 0;
    }
    function pageOf(item) {
        for (let p = item; p; p = p.parent) if (p.pid !== undefined) return p.pid;
        return "";
    }
    function titleOf(id) { for (let i = 0; i < cats.length; i++) if (cats[i].id === id) return cats[i].label; return ""; }
    readonly property var found: {
        const raw = norm(sq).split(/\s+/).filter(x => x !== "");
        const toks = raw.map(stem);
        if (toks.length === 0) return [];
        const out = [];
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i];
            if (!l || !l.label || l.off === true) continue;
            const pg = pageOf(l);
            if (pg === "") continue;
            const title = titleOf(pg);
            let score = 0, all = true;
            for (let k = 0; k < toks.length; k++) {
                const t = toks[k];
                const extra = kw[Tr.orig(l.label)] || "";
                // точное слово из подсказок важнее, чем совпадение по началу слова в пояснении ("фон" ≠ "фонетическая")
                const exact = (" " + norm(extra) + " ").indexOf(" " + raw[k] + " ") >= 0;
                const sc = hasWord(l.label, t) ? 6 : exact ? 5 : hasWord(l.hint, t) ? 3 : hasWord(extra, t) ? 2 : hasWord(title, t) ? 1 : 0;
                if (sc === 0) { all = false; break; }
                score += sc;
            }
            if (all) out.push({ item: l, label: l.label, sub: title, score: score });
        }
        out.sort((a, b) => b.score - a.score);
        return out.slice(0, 9);
    }
    function goTo(item) {
        page = pageOf(item);
        hit = item;
        hitTimer.restart();
        reveal.restart();
    }
    Timer { id: hitTimer; interval: 5000; onTriggered: root.hit = null }
    // прокрутка - чуть позже: страница должна успеть показаться и посчитать высоту
    Timer {
        id: reveal
        interval: 60
        onTriggered: {
            const item = root.hit;
            if (!item) return;
            let f = null;
            for (let p = item.parent; p; p = p.parent) if (p.contentY !== undefined && p.contentItem !== undefined) { f = p; break; }
            if (!f) return;
            const y = item.mapToItem(f.contentItem, 0, 0).y;
            const max = Math.max(0, f.contentHeight - f.height);
            scrollAnim.target = f;
            scrollAnim.to = Math.max(0, Math.min(max, y - (f.height - item.height) / 2));
            scrollAnim.restart();
        }
    }
    NumberAnimation { id: scrollAnim; property: "contentY"; duration: 350; easing.type: Easing.OutCubic }
    // подсветка найденной строки
    component Glow: Rectangle {
        id: glow
        readonly property bool on: root.hit !== null && root.hit === parent
        anchors.fill: parent
        radius: 6
        visible: on
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
        border.color: Theme.accent
        border.width: 2
        SequentialAnimation on opacity {
            running: glow.on
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.35; duration: 500; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.35; to: 1; duration: 500; easing.type: Easing.InOutQuad }
        }
    }

    // ---- полные списки: часовые пояса, раскладки, языки (сценарий win11-lists) ----
    property var allZones: []
    property var allLayouts: []
    property var allLocales: []
    property bool listsLoaded: false
    function loadLists() { if (!listsLoaded && !lists.running) lists.running = true; }
    readonly property var layoutRu: [
        ["English", Tr.t("Английская")], ["Russian", Tr.t("Русская")], ["Ukrainian", Tr.t("Украинская")], ["Belarusian", Tr.t("Белорусская")], ["Kazakh", Tr.t("Казахская")],
        ["German", Tr.t("Немецкая")], ["French", Tr.t("Французская")], ["Spanish", Tr.t("Испанская")], ["Italian", Tr.t("Итальянская")], ["Polish", Tr.t("Польская")],
        ["Turkish", Tr.t("Турецкая")], ["Georgian", Tr.t("Грузинская")], ["Armenian", Tr.t("Армянская")], ["Hebrew", Tr.t("Иврит")], ["Arabic", Tr.t("Арабская")],
        ["Portuguese", Tr.t("Португальская")], ["Czech", Tr.t("Чешская")], ["Greek", Tr.t("Греческая")], ["Japanese", Tr.t("Японская")], ["Korean", Tr.t("Корейская")],
        ["Chinese", Tr.t("Китайская")], ["Uzbek", Tr.t("Узбекская")], ["Tatar", Tr.t("Татарская")], ["Kyrgyz", Tr.t("Киргизская")], ["Tajik", Tr.t("Таджикская")],
        ["Azerbaijani", Tr.t("Азербайджанская")], ["Bulgarian", Tr.t("Болгарская")], ["Serbian", Tr.t("Сербская")], ["Finnish", Tr.t("Финская")], ["Swedish", Tr.t("Шведская")],
        ["Norwegian", Tr.t("Норвежская")], ["Danish", Tr.t("Датская")], ["Dutch", Tr.t("Нидерландская")], ["Hungarian", Tr.t("Венгерская")], ["Romanian", Tr.t("Румынская")],
        ["Lithuanian", Tr.t("Литовская")], ["Latvian", Tr.t("Латышская")], ["Estonian", Tr.t("Эстонская")], ["Moldavian", Tr.t("Молдавская")], ["Mongolian", Tr.t("Монгольская")],
        ["Bashkirian", Tr.t("Башкирская")], ["Chuvash", Tr.t("Чувашская")], ["Yakut", Tr.t("Якутская")], ["Ossetian", Tr.t("Осетинская")], ["Hindi", Tr.t("Хинди")],
        ["Indian", Tr.t("Индийская")], ["Thai", Tr.t("Тайская")], ["Vietnamese", Tr.t("Вьетнамская")], ["Persian", Tr.t("Персидская")]
    ]
    function layoutName(en) {
        for (let i = 0; i < layoutRu.length; i++)
            if (en.indexOf(layoutRu[i][0]) === 0) return layoutRu[i][1] + en.slice(layoutRu[i][0].length);
        return en;
    }
    function layoutTitle(code) {
        for (let i = 0; i < allLayouts.length; i++) if (allLayouts[i].v === code) return allLayouts[i].text;
        for (let i = 0; i < knownLayouts.length; i++) if (knownLayouts[i][0] === code) return knownLayouts[i][1];
        return code;
    }
    function zoneRu(z) { for (let i = 0; i < zones.length; i++) if (zones[i][0] === z) return zones[i][1].replace(/ [+-]\d+$/, ""); return ""; }
    function localeTitle(code) {
        if (code === "") return Tr.t("Как в системе");
        const l = Qt.locale(code.replace(/\..*$/, ""));
        let n = l.nativeLanguageName || code;
        n = n.charAt(0).toUpperCase() + n.slice(1);
        return l.nativeTerritoryName ? n + " (" + l.nativeTerritoryName + ")" : n;
    }
    Process {
        id: lists
        command: ["win11-lists", "all"]
        stdout: StdioCollector {
            id: listsOut
            onStreamFinished: {
                const z = [], l = [], c = [{ v: "", text: Tr.t("Как в системе"), sub: "" }];
                let sec = "";
                const rows = listsOut.text.split("\n");
                for (let i = 0; i < rows.length; i++) {
                    const r = rows[i];
                    if (r === "") continue;
                    if (r.charAt(0) === "@") { sec = r; continue; }
                    const p = r.split("\t");
                    if (sec === "@zones") {
                        const ru = root.zoneRu(p[0]);
                        z.push({ v: p[0], text: (ru !== "" ? ru + " - " : "") + p[0].replace(/_/g, " "), sub: "UTC" + (p[1] || "") });
                    } else if (sec === "@layouts" && p.length >= 2) {
                        l.push({ v: p[0], text: root.layoutName(p[1]), sub: p[0] + (p[1] !== root.layoutName(p[1]) ? " · " + p[1] : "") });
                    } else if (sec === "@locales" && !/^(C|POSIX)\b/.test(p[0])) {
                        c.push({ v: p[0], text: root.localeTitle(p[0]), sub: p[0] });
                    }
                }
                // если списка раскладок в системе не нашлось - хотя бы известные
                if (l.length === 0) for (let i = 0; i < root.knownLayouts.length; i++) l.push({ v: root.knownLayouts[i][0], text: root.knownLayouts[i][1], sub: root.knownLayouts[i][0] });
                if (z.length === 0) for (let i = 0; i < root.zones.length; i++) z.push({ v: root.zones[i][0], text: root.zones[i][1], sub: root.zones[i][0] });
                root.allZones = z; root.allLayouts = l; root.allLocales = c;
                root.listsLoaded = true;
            }
        }
    }
    readonly property var cats: [
        { id: "home", icon: Icons.home, label: Tr.t("Главная") },
        { id: "system", icon: Icons.laptop, label: Tr.t("Система") },
        { id: "display", icon: Icons.brightness, label: Tr.t("Экран и ночной свет") },
        { id: "sound", icon: Icons.speaker, label: Tr.t("Звук") },
        { id: "notify", icon: Icons.alert, label: Tr.t("Уведомления") },
        { id: "storage", icon: Icons.storage, label: Tr.t("Память и хранилище") },
        { id: "recovery", icon: Icons.history, label: Tr.t("Восстановление") },
        { id: "about", icon: Icons.info, label: Tr.t("О системе") },
        { id: "devices", icon: Icons.bluetooth, label: Tr.t("Устройства") },
        { id: "mouse", icon: Icons.cursor, label: Sys.hasTouchpad ? Tr.t("Мышь и сенсорная панель") : Tr.t("Мышь") },
        { id: "keyboard", icon: Icons.keyboard, label: Tr.t("Клавиатура") },
        { id: "printers", icon: Icons.printer, label: Tr.t("Принтеры и сканеры") },
        { id: "network", icon: Icons.ethernet, label: Tr.t("Состояние сети") },
        { id: "zapret", icon: Icons.globe, label: Tr.t("Обход блокировок (Zapret 2)") },
        { id: "personal", icon: Icons.brush, label: Tr.t("Персонализация") },
        { id: "themes", icon: Icons.darkTheme, label: Tr.t("Темы и значок \"Пуск\"") },
        { id: "taskbar", icon: Icons.desktop, label: Tr.t("Панель задач") },
        { id: "windows", icon: Icons.open, label: Tr.t("Окна и анимации") },
        { id: "apps", icon: Icons.apps, label: Tr.t("Приложения") },
        { id: "accounts", icon: Icons.person, label: Tr.t("Учётная запись") },
        { id: "lang", icon: Icons.language, label: Tr.t("Время и язык") },
        { id: "update", icon: Icons.sync, label: Tr.t("Центр обновления Windows") }
    ]
    // Слева - разделы, как в Windows 11; страницы раздела переключаются вкладками под заголовком.
    readonly property var groups: [
        { icon: Icons.home, label: Tr.t("Главная"), pages: ["home"] },
        { icon: Icons.laptop, label: Tr.t("Система"), pages: ["system", "display", "sound", "notify", "storage", "recovery", "about"] },
        { icon: Icons.bluetooth, label: Tr.t("Bluetooth и устройства"), pages: ["devices", "mouse", "keyboard", "printers"] },
        { icon: Icons.globe, label: Tr.t("Сеть и Интернет"), pages: ["network", "zapret"] },
        { icon: Icons.brush, label: Tr.t("Персонализация"), pages: ["personal", "themes", "taskbar", "windows"] },
        { icon: Icons.apps, label: Tr.t("Приложения"), pages: ["apps"] },
        { icon: Icons.person, label: Tr.t("Учётная запись"), pages: ["accounts"] },
        { icon: Icons.language, label: Tr.t("Время и язык"), pages: ["lang"] },
        { icon: Icons.sync, label: Tr.t("Центр обновления Windows"), pages: ["update"] }
    ]
    function groupOf(pg) {
        for (let i = 0; i < groups.length; i++) {
            if (groups[i].pages.indexOf(pg) >= 0) return groups[i];
        }
        return groups[0];
    }
    readonly property var group: groupOf(page)
    // на какой странице раздела остановились в прошлый раз
    property var lastIn: ({})
    function openGroup(g) {
        const target = lastIn[g.label];
        page = (target && g.pages.indexOf(target) >= 0) ? target : g.pages[0];
    }
    readonly property string title: {
        for (let i = 0; i < cats.length; i++) if (cats[i].id === page) return cats[i].label;
        return "";
    }
    onOpened: { page = Ui.settingsPage; nfrom.text = Store.nightFrom; nto.text = Store.nightTo; path.text = Store.wallpaper; wdir.text = Store.wallDir; layouts.text = Store.niri.kbLayout; info.running = true; tzRead.running = true; if (page === "apps") root.pkgLoad(); if (page === "lang") loadLists(); sq = ""; }

    property string pcName: ""
    property string pcModel: ""
    property string pcCpu: ""
    property string pcMem: ""
    property string pcDisk: ""
    property string pcKernel: ""
    property string pcOs: ""
    Process {
        id: info
        command: ["sh", "-c",
            "echo \"Компьютер: $(hostname)\"; " +
            "echo \"Плата: $(cat /sys/class/dmi/id/product_name 2>/dev/null || cat /sys/class/dmi/id/board_name 2>/dev/null || echo \"ПК\")\"; " +
            "echo \"Система: NixOS $(nixos-version 2>/dev/null | cut -d' ' -f1)\"; " +
            "echo \"Ядро: Linux $(uname -r)\"; " +
            "echo \"Процессор: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //')\"; " +
            "free -h 2>/dev/null | awk '/^Mem:/ { printf \"Память: %s занято из %s (ZRAM сжатие)\n\", $3, $2 }'; " +
            "df -h / 2>/dev/null | awk 'NR==2 { printf \"Диск: %s свободно из %s (занято %s)\n\", $4, $2, $5 }'; " +
            "echo \"Оболочка: Niri + Quickshell Fluent UI\""]
        stdout: StdioCollector {
            id: infoOut
            onStreamFinished: {
                root.about = infoOut.text.trim();
                const lns = root.about.split("\n");
                for (let i = 0; i < lns.length; i++) {
                    if (lns[i].indexOf("Компьютер: ") === 0) root.pcName = lns[i].slice(11).trim(); // i18n-keep
                    if (lns[i].indexOf("Плата: ") === 0) root.pcModel = lns[i].slice(7).trim(); // i18n-keep
                    if (lns[i].indexOf("Процессор: ") === 0) root.pcCpu = lns[i].slice(11).trim(); // i18n-keep
                    if (lns[i].indexOf("Память: ") === 0) root.pcMem = lns[i].slice(8).trim(); // i18n-keep
                    if (lns[i].indexOf("Диск: ") === 0) root.pcDisk = lns[i].slice(6).trim(); // i18n-keep
                    if (lns[i].indexOf("Ядро: ") === 0) root.pcKernel = lns[i].slice(6).trim(); // i18n-keep
                    if (lns[i].indexOf("Система: ") === 0) root.pcOs = lns[i].slice(9).trim(); // i18n-keep
                }
            }
        }
    }

    // ---- время и язык ----
    property string tz: ""
    property string tzError: ""
    readonly property var zones: [
        ["Europe/Kaliningrad", Tr.t("Калининград +2")], ["Europe/Moscow", Tr.t("Москва +3")], ["Europe/Samara", Tr.t("Самара +4")],
        ["Asia/Yekaterinburg", Tr.t("Екатеринбург +5")], ["Asia/Omsk", Tr.t("Омск +6")], ["Asia/Novosibirsk", Tr.t("Новосибирск +7")],
        ["Asia/Krasnoyarsk", Tr.t("Красноярск +7")], ["Asia/Irkutsk", Tr.t("Иркутск +8")], ["Asia/Yakutsk", Tr.t("Якутск +9")],
        ["Asia/Vladivostok", Tr.t("Владивосток +10")], ["Asia/Magadan", Tr.t("Магадан +11")], ["Asia/Kamchatka", Tr.t("Камчатка +12")],
        ["Europe/Minsk", Tr.t("Минск +3")], ["Asia/Almaty", Tr.t("Алматы +5")], ["Asia/Tashkent", Tr.t("Ташкент +5")], ["Asia/Tbilisi", Tr.t("Тбилиси +4")],
        ["Asia/Yerevan", Tr.t("Ереван +4")], ["Asia/Baku", Tr.t("Баку +4")], ["Europe/Istanbul", Tr.t("Стамбул +3")], ["Asia/Dubai", Tr.t("Дубай +4")],
        ["Europe/Berlin", Tr.t("Берлин")], ["Europe/London", Tr.t("Лондон")], ["America/New_York", Tr.t("Нью-Йорк")], ["UTC", "UTC"]
    ]
    readonly property var knownLayouts: [
        ["us", Tr.t("Английская")], ["ru", Tr.t("Русская")], ["ua", Tr.t("Украинская")], ["by", Tr.t("Белорусская")], ["kz", Tr.t("Казахская")],
        ["de", Tr.t("Немецкая")], ["fr", Tr.t("Французская")], ["es", Tr.t("Испанская")], ["it", Tr.t("Итальянская")], ["pl", Tr.t("Польская")],
        ["tr", Tr.t("Турецкая")], ["ge", Tr.t("Грузинская")], ["am", Tr.t("Армянская")], ["il", Tr.t("Иврит")]
    ]
    readonly property var toggles: [
        ["grp:win_space_toggle", Tr.t("Win+Пробел")], ["grp:alt_shift_toggle", "Alt+Shift"], ["grp:ctrl_shift_toggle", "Ctrl+Shift"],
        ["grp:alt_space_toggle", Tr.t("Alt+Пробел")], ["grp:caps_toggle", "Caps Lock"]
    ]
    function csvHas(csv, v) { return (csv || "").split(",").indexOf(v) >= 0; }
    // добавить или убрать значение в списке через запятую; keepOne - последнее не убирать
    function csvToggle(csv, v, keepOne) {
        const list = (csv || "").split(",").filter(x => x !== "");
        const i = list.indexOf(v);
        if (i < 0) list.push(v);
        else if (!keepOne || list.length > 1) list.splice(i, 1);
        return list.join(",");
    }
    function setLayouts(v) { Store.setNiri("kbLayout", v); layouts.text = v; }
    Process {
        id: tzRead
        command: ["sh", "-c", "timedatectl show -p Timezone --value 2>/dev/null"]
        stdout: StdioCollector { id: tzOut; onStreamFinished: root.tz = tzOut.text.trim() }
    }
    // после смены пояса оболочка перезапускается: иначе часы продолжат показывать старое время
    Process {
        id: tzSet
        property string zone: ""
        command: ["sh", "-c",
            "if out=\"$(timedatectl set-timezone \"$1\" 2>&1)\"; then echo OK; " +
            "(sleep 1; kill \"$(cat \"$HOME/.local/state/win11-shell/shell.pid\")\") >/dev/null 2>&1 & " +
            "else echo \"$out\"; fi", "sh", zone]
        stdout: StdioCollector {
            id: tzSetOut
            onStreamFinished: {
                const t = tzSetOut.text.trim();
                if (t === "OK") { root.tz = tzSet.zone; root.tzError = ""; }
                else root.tzError = t.split("\n")[0] || Tr.t("не удалось");
            }
        }
    }
    function setZone(z) {
        if (!/^[A-Za-z0-9_+\/-]+$/.test(z) || tzSet.running) return;
        tzSet.zone = z; tzSet.running = true;
    }

    // свой значок "Пуска": путь к файлу (можно перетащить файл в поле - тогда придёт file://…)
    function setStartIcon(t) {
        let p = (t || "").trim().replace(/^file:\/\//, "");
        if (p.indexOf("~") === 0) p = Config.home + p.slice(1);
        if (p === "") { Store.set("startIcon", "nixos"); return; }
        if (p.indexOf("/") !== 0) return;
        Store.set("startIcon", p);
    }

    // ---- уведомления: кого можно добавить в исключения ----
    readonly property var dndRecent: Notifs.seen.filter(n => !Notifs.isAllowedName(n) && Notifs.systemNames.indexOf(n) < 0)
    readonly property var dndApps: {
        const v = DesktopEntries.applications.values, out = [], seen = {};
        for (let i = 0; i < v.length; i++) {
            if (v[i].noDisplay || !v[i].name || seen[v[i].name]) continue;
            seen[v[i].name] = true;
            out.push({ v: v[i].name, text: v[i].name, sub: v[i].genericName || "" });
        }
        out.sort((a, b) => a.text.localeCompare(b.text));
        return out;
    }

    // ---- аватарка ----
    property string faceError: ""
    Process {
        id: faceSet
        property string file: ""
        command: ["sh", "-c",
            "d=/var/lib/win11-shell/faces; f=\"$1\"; " +
            "if [ -z \"$f\" ]; then rm -f \"$d/$USER\" \"$HOME/.face\" \"$HOME/.face.icon\"; echo OK; exit 0; fi; " +
            "[ -f \"$f\" ] || { echo 'нет такого файла'; exit 0; }; " +
            "[ -d \"$d\" ] || { echo 'сначала обновите систему: win11-update'; exit 0; }; " +
            "[ \"$(wc -c < \"$f\")\" -le 10485760 ] || { echo 'картинка больше 10 МБ'; exit 0; }; " +
            "rm -f \"$d/$USER\"; cp \"$f\" \"$d/$USER\" && chmod 644 \"$d/$USER\" && cp \"$f\" \"$HOME/.face\" && cp \"$f\" \"$HOME/.face.icon\" && echo OK || echo 'не удалось скопировать'",
            "sh", file]
        stdout: StdioCollector {
            id: faceOut
            onStreamFinished: {
                const t = faceOut.text.trim();
                root.faceError = t === "OK" ? "" : t;
                if (t === "OK") Store.avatarRev = Store.avatarRev + 1;
            }
        }
    }
    function setFace(p) { if (faceSet.running) return; faceSet.file = p.trim().replace("file://", ""); faceSet.running = true; }

    // ---- приложения: установка и удаление (сценарий win11-pkg) ----
    property var pkgRows: []
    property bool pkgBusy: false         // идёт поиск
    property string pkgJob: ""           // "nix:firefox" - что сейчас ставится или удаляется
    property string pkgStatus: ""
    property int pkgPct: 0                // сколько процентов текущей установки готово
    property string pkgQuery: ""
    property string pkgFilter: "all"     // all, installed, nix, flatpak
    property bool srcPanel: false        // открыта панель источников
    property var srcRows: []             // { kind, name, url, removable }
    property string srcKind: "flatpak"
    readonly property var srcPresets: [
        { label: "NixOS unstable", kind: "nix", name: "unstable", url: "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz" },
        { label: "NUR", kind: "nix", name: "nur", url: "https://github.com/nix-community/NUR/archive/main.tar.gz" },
        { label: "Flathub Beta", kind: "flatpak", name: "flathub-beta", url: "https://flathub.org/beta-repo/flathub-beta.flatpakrepo" }
    ]
    readonly property var pkgShown: pkgRows.filter(r => pkgFilter === "all" || (pkgFilter === "installed" ? r.state === "installed" : r.src.split(":")[0] === pkgFilter))
    function srcLabel(src) {
        const p = src.split(":");
        if (p.length > 1) return p[1];
        return p[0] === "flatpak" ? "Flathub" : p[0] === "appimage" ? "AppImage" : "NixOS";
    }
    // Очередь: пока одна программа ставится, остальные ждут своей очереди. { key, status, args }
    property var pkgQueue: []
    property int pkgSerial: 0
    function pkgQueued(key) { return pkgQueue.some(j => j.key === key); }
    function pkgJobRun(key, status, args) {
        if (pkgJob === key || pkgQueued(key)) return;
        if (pkgJob !== "") { pkgQueue = pkgQueue.concat([{ key: key, status: status, args: args }]); return; }
        pkgJob = key; pkgStatus = status; pkgPct = 0; pkgSerial++;
        pkgWork.command = ["win11-pkg"].concat(args);
        pkgWork.running = true;
    }
    function pkgCancel(key) { pkgQueue = pkgQueue.filter(j => j.key !== key); }
    // текущая работа закончена: берём следующую, а список перечитываем, когда очередь пуста
    function pkgJobDone(status) {
        pkgJob = "";
        if (pkgQueue.length > 0) {
            const next = pkgQueue[0];
            pkgQueue = pkgQueue.slice(1);
            pkgJobRun(next.key, next.status, next.args);
            return;
        }
        pkgStatus = status;
        pkgLoad();
        srcList.running = true;
    }
    function srcAdd(kind, name, url) { pkgJobRun("source", Tr.t("Добавляю источник ") + name, ["source", "add", kind, name.trim(), url.trim()]); }
    function srcRemove(row) { pkgJobRun("source", Tr.t("Удаляю источник ") + row.name, ["source", "remove", row.kind, row.name]); }
    function appImageAdd(file) { if (file.trim() !== "") pkgJobRun("appimage", Tr.t("Устанавливаю файл"), ["install", "appimage", file.trim()]); }
    Process {
        id: srcList
        command: ["win11-pkg", "sources"]
        stdout: StdioCollector {
            id: srcOut
            onStreamFinished: {
                const out = [];
                srcOut.text.split("\n").forEach(line => {
                    const p = line.split("\t");
                    if (p.length >= 3) out.push({ kind: p[0], name: p[1], url: p[2], removable: p[3] === "1" });
                });
                root.srcRows = out;
            }
        }
    }
    function pkgLoad() {
        pkgList.running = false;
        pkgList.query = pkgQuery.trim();
        pkgList.command = pkgList.query === "" ? ["win11-pkg", "list"] : ["win11-pkg", "search", pkgList.query];
        pkgBusy = true;
        pkgList.running = true;
    }
    function pkgRun(action, row) {
        pkgJobRun(row.src + ":" + row.id, (action === "install" ? Tr.t("Устанавливаю ") : Tr.t("Удаляю ")) + row.name, [action, row.src, row.id]);
    }
    Process {
        id: pkgList
        property string query: ""
        stdout: StdioCollector {
            id: pkgOut
            onStreamFinished: {
                if (pkgList.query !== root.pkgQuery.trim()) return;      // ответ на устаревший запрос
                const out = [], seen = {};
                const lines = pkgOut.text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const p = lines[i].split("\t");
                    if (p.length < 4 || seen[p[1] + ":" + p[2]]) continue;
                    seen[p[1] + ":" + p[2]] = true;
                    out.push({ state: p[0], src: p[1], id: p[2], name: p[3], desc: p[4] || "" });   // state "note" - сообщение, а не программа
                }
                out.sort((a, b) => (a.state === "installed" ? 0 : 1) - (b.state === "installed" ? 0 : 1));
                root.pkgRows = out;
                root.pkgBusy = false;
            }
        }
    }
    Process {
        id: pkgWork
        // сценарий завершился, не сообщив итог (например, его прервали): очередь не должна зависнуть
        onExited: { pkgStuck.serial = root.pkgSerial; pkgStuck.restart(); }
        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (t === "") return;
                if (t.indexOf("OK ") === 0 || t.indexOf("ERR ") === 0) {
                    root.pkgJobDone(t.indexOf("OK ") === 0 ? Tr.t("Готово: ") + t.slice(3) : Tr.t("Ошибка: ") + t.slice(4));
                } else if (t.indexOf("PCT ") === 0) {
                    root.pkgPct = parseInt(t.split(" ")[1]) || 0;
                } else root.pkgStatus = t.length > 90 ? t.slice(0, 90) + "…" : t;
            }
        }
    }
    Timer {
        id: pkgStuck
        property int serial: 0
        interval: 400
        onTriggered: if (root.pkgJob !== "" && serial === root.pkgSerial && !pkgWork.running) root.pkgJobDone(Tr.t("Завершено"))
    }
    Timer { id: pkgDelay; interval: 450; onTriggered: root.pkgLoad() }

    // карточка с заголовком и содержимым под ним (для списков вариантов)
    component Card: Rectangle {
        id: card
        property string icon
        property string label
        property string hint: ""
        default property alias content: body.data
        width: pages.width
        height: body.implicitHeight + 62
        radius: 6
        color: Theme.card
        border.color: Theme.border
        Component.onCompleted: root.lines.push(card)
        Glow {}
        FIcon { id: ci; x: 16; y: 16; icon: card.icon; font.pixelSize: 18 }
        WText { anchors { left: ci.right; leftMargin: 14; verticalCenter: ci.verticalCenter } text: card.label }
        WText { anchors { right: parent.right; rightMargin: 14; verticalCenter: ci.verticalCenter } font.pixelSize: 11; color: Theme.subtext; text: card.hint }
        Flow { id: body; anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14; topMargin: 48 } spacing: 4 }
    }
    // кнопка-вариант: нажата или нет
    component Chip: Rectangle {
        id: chip
        property string label
        property bool on: false
        signal clicked()
        width: chipText.implicitWidth + 22; height: 30; radius: 4
        color: on ? Theme.accent : (chipArea.containsMouse ? Theme.hover : "transparent")
        border.color: on ? Theme.accent : Theme.border
        Behavior on color { ColorAnimation { duration: 120 } }
        WText { id: chipText; anchors.centerIn: parent; font.pixelSize: 12; color: chip.on ? Theme.accentText : Theme.text; text: chip.label }
        MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; onClicked: chip.clicked() }
    }

    // список с поиском: для длинных перечней (часовые пояса, раскладки, языки)
    component Picker: Rectangle {
        id: pk
        property string icon
        property string label
        property string hint: ""
        property string placeholder: Tr.t("Поиск")
        property var rows: []                  // [{ v, text, sub }]
        property var isOn: v => false
        property int visibleRows: 5
        signal picked(var v)
        readonly property var shown: {
            const toks = root.norm(pkIn.text).split(/\s+/).filter(x => x !== "");
            if (toks.length === 0) return rows;
            const out = [];
            for (let i = 0; i < rows.length; i++) {
                const hay = root.norm(rows[i].text + " " + rows[i].sub + " " + rows[i].v);
                let ok = true;
                for (let k = 0; k < toks.length; k++) if (hay.indexOf(toks[k]) < 0) { ok = false; break; }
                if (ok) out.push(rows[i]);
            }
            return out;
        }
        width: pages.width
        height: 56 + 40 + visibleRows * 34 + 10
        radius: 6
        color: Theme.card
        border.color: Theme.border
        Component.onCompleted: root.lines.push(pk)
        Glow {}
        FIcon { id: pki; x: 16; y: 19; icon: pk.icon; font.pixelSize: 18 }
        Column {
            anchors { left: pki.right; leftMargin: 14; right: parent.right; rightMargin: 14; verticalCenter: pki.verticalCenter }
            WText { text: pk.label }
            WText { visible: pk.hint !== ""; width: parent.width; font.pixelSize: 11; color: Theme.subtext; text: pk.hint }
        }
        Rectangle {
            id: pkBox
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 56 }
            height: 32; radius: 4
            color: Theme.flyout
            border.color: pkIn.activeFocus ? Theme.accent : Theme.border
            FIcon { id: pkLens; anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter } icon: Icons.search; font.pixelSize: 14; color: Theme.subtext }
            TextInput {
                id: pkIn
                anchors { left: pkLens.right; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 8; rightMargin: 8 }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.text; selectionColor: Theme.accent
                font.family: Config.fontFamily; font.pixelSize: 12
                onTextChanged: pkList.contentY = 0
                onAccepted: if (pk.shown.length > 0) pk.picked(pk.shown[0].v)
                WText { visible: pkIn.text === ""; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; color: Theme.subtext; text: pk.placeholder + (pk.rows.length > 0 ? Tr.t(" - всего ") + pk.rows.length : "") }
            }
        }
        ListView {
            id: pkList
            anchors { left: parent.left; right: parent.right; top: pkBox.bottom; bottom: parent.bottom; margins: 14; topMargin: 6; bottomMargin: 8 }
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: pk.shown
            delegate: HoverButton {
                id: pkRow
                required property var modelData
                readonly property bool on: pk.isOn(modelData.v)
                width: pkList.width; implicitHeight: 34
                onClicked: pk.picked(modelData.v)
                FIcon { id: pkCheck; anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter } width: 16; font.pixelSize: 14; color: Theme.accent; icon: pkRow.on ? Icons.check : "" }
                WText { anchors { left: pkCheck.right; leftMargin: 8; right: pkSub.left; rightMargin: 8; verticalCenter: parent.verticalCenter } font.pixelSize: 12; font.weight: pkRow.on ? Font.DemiBold : Font.Normal; text: pkRow.modelData.text }
                WText { id: pkSub; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } font.pixelSize: 11; color: Theme.subtext; text: pkRow.modelData.sub }
            }
            WText { visible: pk.shown.length === 0; anchors.centerIn: parent; color: Theme.subtext; font.pixelSize: 12; text: pk.rows.length === 0 ? Tr.t("Загрузка списка…") : Tr.t("Ничего не найдено") }
        }
    }

    // строка параметра: подпись слева, элемент управления справа
    component Line: Rectangle {
        id: line
        property string icon
        property string label
        property string hint: ""
        default property alias content: slot.data
        property bool off: false          // строка не нужна на этом компьютере (нет такого устройства)
        visible: !off
        width: pages.width
        height: 56
        radius: 6
        color: Theme.card
        border.color: Theme.border
        Component.onCompleted: root.lines.push(line)
        Glow {}
        FIcon { id: li; anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter } icon: line.icon; font.pixelSize: 18 }
        Column {
            anchors { left: li.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
            WText { text: line.label }
            WText { visible: line.hint !== ""; font.pixelSize: 11; color: Theme.subtext; text: line.hint }
        }
        Row { id: slot; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } spacing: 6 }
    }
    // выбор одного из вариантов
    component Seg: Row {
        id: seg
        property var options: []
        property var value
        signal picked(var v)
        spacing: 4
        Repeater {
            model: seg.options
            Rectangle {
                id: opt
                required property var modelData
                readonly property bool on: seg.value === modelData.v
                width: optText.implicitWidth + 24; height: 32; radius: 4
                color: on ? Theme.accent : (optArea.containsMouse ? Theme.hover : "transparent")
                border.color: on ? Theme.accent : Theme.border
                Behavior on color { ColorAnimation { duration: 120 } }
                WText { id: optText; anchors.centerIn: parent; font.pixelSize: 12; color: opt.on ? Theme.accentText : Theme.text; text: opt.modelData.label }
                MouseArea { id: optArea; anchors.fill: parent; hoverEnabled: true; onClicked: seg.picked(opt.modelData.v) }
            }
        }
    }
    // выключатель
    component Switch: Rectangle {
        id: sw
        property bool on: false
        signal toggled()
        width: 40; height: 20; radius: 10
        color: on ? Theme.accent : "transparent"
        border.color: on ? Theme.accent : Theme.subtext
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 12; height: 12; radius: 6
            anchors.verticalCenter: parent.verticalCenter
            x: sw.on ? 24 : 4
            color: sw.on ? Theme.accentText : Theme.subtext
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; onClicked: sw.toggled() }
    }
    // поле ввода в одну строку
    component Field: Rectangle {
        property alias text: fieldInput.text
        property string hint: ""
        signal accepted()
        height: 32; radius: 4
        color: Theme.flyout
        border.color: fieldInput.activeFocus ? Theme.accent : Theme.border
        TextInput {
            id: fieldInput
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Theme.text; selectionColor: Theme.accent
            font.family: Config.fontFamily; font.pixelSize: 12
            onAccepted: parent.accepted()
            WText { visible: fieldInput.text === ""; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; color: Theme.subtext; text: parent.parent.hint }
        }
    }
    component Btn: HoverButton {
        id: btn
        property string label
        implicitWidth: btnText.implicitWidth + 24; implicitHeight: 32
        color: pressed ? Theme.pressed : hovered ? Theme.hover : Theme.card
        border.color: Theme.border
        WText { id: btnText; anchors.centerIn: parent; font.pixelSize: 12; text: btn.label }
    }


    // ---- слева: категории ----
    Column {
        id: side
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 16 }
        width: 250
        spacing: 2
        WText { leftPadding: 10; topPadding: 6; bottomPadding: 4; font.pixelSize: 20; font.weight: Font.DemiBold; text: Tr.t("Параметры") }

        // Карточка пользователя вверху боковой панели (как в Windows 11)
        HoverButton {
            width: side.width; implicitHeight: 48
            onClicked: root.page = "accounts"
            Row {
                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 8 }
                spacing: 12
                Avatar {
                    width: 32; height: 32
                    anchors.verticalCenter: parent.verticalCenter
                    backColor: Theme.dark ? "#404040" : "#dcdcdc"
                    iconColor: Theme.text
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    WText { font.pixelSize: 13; font.weight: Font.DemiBold; text: Config.userName }
                    WText { font.pixelSize: 11; color: Theme.subtext; text: Tr.t("Локальная учётная запись") }
                }
            }
        }

        // поиск параметра
        Rectangle {
            width: side.width; height: 34; radius: 4
            color: Theme.card
            border.color: find.activeFocus ? Theme.accent : Theme.border
            FIcon { id: lens; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } icon: Icons.search; font.pixelSize: 14; color: Theme.subtext }
            TextInput {
                id: find
                anchors { left: lens.right; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 8; rightMargin: 8 }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.text; selectionColor: Theme.accent
                font.family: Config.fontFamily; font.pixelSize: 13
                onTextEdited: root.sq = text
                Connections { target: root; function onSqChanged() { if (find.text !== root.sq) find.text = root.sq; } }
                onAccepted: if (root.found.length > 0) root.goTo(root.found[0].item)
                Keys.onEscapePressed: event => { if (root.sq !== "") root.sq = ""; else event.accepted = false; }
                WText { visible: find.text === ""; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 13; color: Theme.subtext; text: Tr.t("Найти параметр") }
            }
        }
        Item { width: 1; height: 6 }
        // результаты поиска (вместо списка разделов)
        Repeater {
            model: root.sq !== "" ? root.found : []
            HoverButton {
                id: res
                required property var modelData
                width: side.width; implicitHeight: 44
                highlighted: root.hit === modelData.item
                onClicked: root.goTo(modelData.item)
                Column {
                    anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    WText { width: parent.width; text: res.modelData.label }
                    WText { width: parent.width; font.pixelSize: 11; color: Theme.subtext; text: res.modelData.sub }
                }
            }
        }
        WText {
            visible: root.sq !== "" && root.found.length === 0
            leftPadding: 12; topPadding: 8; width: side.width; wrapMode: Text.Wrap
            color: Theme.subtext; text: Tr.t("Ничего не найдено. Попробуйте другое слово: \"обои\", \"язык\", \"уведомления\".")
        }
        Repeater {
            model: root.sq === "" ? root.groups : []
            HoverButton {
                id: cat
                required property var modelData
                width: side.width; implicitHeight: 38
                highlighted: root.group.label === modelData.label
                onClicked: root.openGroup(modelData)
                Rectangle {
                    visible: cat.highlighted
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 3; height: 16; radius: 1.5
                    color: Theme.accent
                }
                FIcon { id: ci; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } icon: cat.modelData.icon; font.pixelSize: 18 }
                WText { anchors { left: ci.right; leftMargin: 12; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: cat.modelData.label }
            }
        }
    }

    // ---- справа: страница ----
    WText {
        id: heading
        anchors { left: side.right; leftMargin: 24; top: parent.top; topMargin: 22 }
        font.pixelSize: 22; font.weight: Font.DemiBold
        text: root.group.label
    }
    // Tabs remain accessible on narrow windows with arrows, wheel or touchpad.
    Item {
        id: tabs
        anchors { left: heading.left; right: parent.right; rightMargin: 24; top: heading.bottom; topMargin: 12 }
        visible: root.group.pages.length > 1
        height: visible ? 30 : 0
        readonly property bool overflow: tabRow.implicitWidth > width
        function revealCurrent() {
            const index = root.group.pages.indexOf(root.page);
            const item = index >= 0 ? tabRepeater.itemAt(index) : null;
            if (!item) return;
            if (item.x < tabView.contentX) tabView.contentX = item.x;
            else if (item.x + item.width > tabView.contentX + tabView.width)
                tabView.contentX = Math.min(tabView.contentWidth - tabView.width, item.x + item.width - tabView.width);
        }
        Connections { target: root; function onPageChanged() { Qt.callLater(tabs.revealCurrent); } }
        HoverButton {
            id: tabPrev
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            implicitWidth: tabs.overflow ? 26 : 0; implicitHeight: 30
            visible: tabs.overflow
            enabled: tabView.contentX > 0
            onClicked: tabView.contentX = Math.max(0, tabView.contentX - 180)
            FIcon { anchors.centerIn: parent; icon: Icons.chevronLeft; font.pixelSize: 14; color: Theme.text }
        }
        Flickable {
            id: tabView
            anchors { left: tabPrev.right; right: tabNext.left; top: parent.top; bottom: parent.bottom }
            clip: true
            contentWidth: tabRow.implicitWidth; contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            WheelHandler {
                target: null
                onWheel: event => {
                    const delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
                    tabView.contentX = Math.max(0, Math.min(tabView.contentWidth - tabView.width, tabView.contentX - delta));
                    event.accepted = true;
                }
            }
            Row {
                id: tabRow
                spacing: 4
                Repeater {
                    id: tabRepeater
                    model: root.group.pages
                    Chip {
                        required property string modelData
                        label: root.titleOf(modelData)
                        on: root.page === modelData
                        onClicked: root.page = modelData
                    }
                }
            }
        }
        HoverButton {
            id: tabNext
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            implicitWidth: tabs.overflow ? 26 : 0; implicitHeight: 30
            visible: tabs.overflow
            enabled: tabView.contentX < tabView.contentWidth - tabView.width - 1
            onClicked: tabView.contentX = Math.min(tabView.contentWidth - tabView.width, tabView.contentX + 180)
            FIcon { anchors.centerIn: parent; icon: Icons.chevronRight; font.pixelSize: 14; color: Theme.text }
        }
    }
    Item {
        id: pages
        anchors { left: side.right; right: parent.right; top: tabs.bottom; bottom: parent.bottom; leftMargin: 24; rightMargin: 24; topMargin: 14; bottomMargin: 20 }
        // ---- Главная ----
        Flickable {
            visible: root.page === "home"; property string pid: "home"
            anchors.fill: parent
            clip: true
            contentHeight: homeCol.implicitHeight + 20
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: homeCol
                spacing: 8

                // Карточка устройства (как в Windows 11)
                Rectangle {
                    width: pages.width
                    height: 80
                    radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    Row {
                        anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter; right: homeDevBtn.left; rightMargin: 12 }
                        spacing: 16
                        Rectangle {
                            width: 58; height: 42; radius: 4
                            color: Theme.hover
                            border.color: Theme.border
                            anchors.verticalCenter: parent.verticalCenter
                            Image { anchors.centerIn: parent; width: 26; height: 26; sourceSize: Qt.size(26, 26); source: Qt.resolvedUrl("assets/start-win11.svg") }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            WText { font.pixelSize: 16; font.weight: Font.DemiBold; text: root.pcName !== "" ? root.pcName : Config.userName + "-PC" }
                            WText { font.pixelSize: 12; color: Theme.subtext; text: root.pcModel !== "" ? root.pcModel : "MSI PRO H610M-B (MS-7D46)" }
                        }
                    }
                    Btn {
                        id: homeDevBtn
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        label: Tr.t("О системе")
                        onClicked: root.page = "about"
                    }
                }

                // Рекомендуемые параметры
                WText { topPadding: 4; font.pixelSize: 13; font.weight: Font.DemiBold; text: Tr.t("Рекомендуемые параметры") }

                Line {
                    icon: Theme.dark ? Icons.darkTheme : Icons.sun
                    label: Tr.t("Тема оформления")
                    hint: Theme.dark ? Tr.t("Тёмная") : Tr.t("Светлая")
                    Btn { label: Tr.t("Переключить"); onClicked: Theme.toggle() }
                }

                Line {
                    icon: Icons.moon
                    label: Tr.t("Ночной свет")
                    hint: Sys.night ? Tr.t("Включён") : Tr.t("Выключен")
                    Switch { on: Sys.night; onToggled: Sys.toggleNight() }
                }

                Line {
                    icon: Sys.muted ? Icons.speakerMute : Icons.speaker
                    label: Tr.t("Звук")
                    hint: Sys.muted ? Tr.t("Выключен") : Math.round(Sys.volume * 100) + "%"
                    Btn { label: Tr.t("Параметры звука"); onClicked: root.page = "sound" }
                }

                // Bluetooth-устройства
                Rectangle {
                    visible: Sys.btDevices.length > 0
                    width: pages.width
                    height: 44 + Sys.btDevices.length * 34
                    radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    WText { x: 16; y: 12; font.pixelSize: 13; font.weight: Font.DemiBold; text: Tr.t("Bluetooth-устройства") }
                    Column {
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 36; margins: 14 }
                        spacing: 4
                        Repeater {
                            model: Sys.btDevices
                            Row {
                                required property var modelData
                                width: parent.width; height: 30
                                spacing: 12
                                Item {
                                    width: 16; height: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: modelData.type === "mouse"
                                    Image { anchors.centerIn: parent; width: 15; height: 15; sourceSize: Qt.size(15, 15); source: Qt.resolvedUrl("assets/bt-mouse.svg") }
                                }
                                FIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.pixelSize: 15
                                    visible: modelData.type !== "mouse"
                                    icon: modelData.type === "keyboard" ? Icons.keyboard : modelData.type === "gamepad" ? Icons.gamepad : Icons.headphones
                                }
                                WText { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; text: modelData.name }
                                WText { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 11; color: modelData.percent > 0 ? Theme.accent : Theme.subtext; font.weight: Font.DemiBold; text: modelData.percent > 0 ? (modelData.percent + "%") : Tr.t("Подключено") }
                            }
                        }
                    }
                }

                // Сеть и интернет
                Line {
                    icon: Sys.netIcon
                    label: Sys.netText
                    hint: Sys.online ? Tr.t("Подключение установлено") : Tr.t("Без доступа к интернету")
                    Btn { label: Tr.t("Параметры сети"); onClicked: root.page = "zapret" }
                }

                // Центр обновления Windows
                Line {
                    icon: Icons.sync
                    label: Tr.t("Центр обновления Windows")
                    hint: Updates.count > 0 ? Tr.t("Доступно обновлений: ") + Updates.count : Tr.t("Система обновлена")
                    Btn { label: Tr.t("Проверить"); onClicked: Ui.openUpdates() }
                }
            }
        }


        Column {
            visible: root.page === "system"; property string pid: "system"
            spacing: 6

            // Карточка компьютера (как в Windows 11: модель, имя ПК, центр обновления)
            Rectangle {
                width: pages.width
                height: 76
                radius: 6
                color: Theme.card
                border.color: Theme.border
                Row {
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter; right: sysBtn.left; rightMargin: 12 }
                    spacing: 14
                    Rectangle {
                        width: 54; height: 38; radius: 4
                        color: Theme.hover
                        border.color: Theme.border
                        anchors.verticalCenter: parent.verticalCenter
                        Image { anchors.centerIn: parent; width: 24; height: 24; sourceSize: Qt.size(24, 24); source: Qt.resolvedUrl("assets/start-win11.svg") }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        WText { font.pixelSize: 15; font.weight: Font.DemiBold; text: root.pcName !== "" ? root.pcName : Config.userName + "-PC" }
                        WText { font.pixelSize: 11; color: Theme.subtext; text: root.pcModel !== "" ? root.pcModel : "MSI PRO H610M-B (MS-7D46)" }
                    }
                }
                Btn {
                    id: sysBtn
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    label: Tr.t("Центр обновления Windows")
                    onClicked: Ui.openUpdates()
                }
            }
            Line {
                icon: Icons.lock; label: Tr.t("Автоблокировка"); hint: Tr.t("Через 10 минут без действий")
                Switch { on: Store.autoLock; onToggled: Store.set("autoLock", !Store.autoLock) }
            }
            Line {
                icon: Icons.person; label: Tr.t("Экран приветствия при входе")
                Switch { on: Store.welcome; onToggled: Store.set("welcome", !Store.welcome) }
            }
            Line {
                icon: Icons.pulse; label: Tr.t("Диспетчер задач"); hint: "Ctrl+Shift+Esc"
                Btn { label: Tr.t("Открыть"); onClicked: Ui.openTaskManager() }
            }
            Line {
                icon: Sys.hasWifi ? Icons.wifi : Icons.ethernet; label: Tr.t("Сеть")
                hint: Sys.hasWifi ? Tr.t("Адаптер Wi-Fi найден. Подключения, Wi-Fi, VPN") : Tr.t("Адаптера Wi-Fi нет - проводная сеть. Подключения, VPN")
                Btn { label: Tr.t("Открыть"); onClicked: Quickshell.execDetached(["nm-connection-editor"]) }
            }
            Line {
                icon: Icons.history
                label: Tr.t("Восстановление")
                hint: Tr.t("Починка системы, рабочего пространства и устранение сбоев")
                Btn { label: Tr.t("Открыть"); onClicked: root.page = "recovery" }
            }
            Line {
                icon: Icons.restart; label: Tr.t("Сбросить параметры"); hint: Tr.t("Вернуть всё как после установки")
                Btn { label: Tr.t("Сбросить"); onClicked: { Store.reset(); path.text = ""; layouts.text = Store.niri.kbLayout; } }
            }
        }

        Column {
            visible: root.page === "display"; property string pid: "display"
            spacing: 6
            Line {
                icon: Icons.moon; label: Tr.t("Ночной свет"); hint: Sys.night ? Tr.t("Сейчас включён") : Tr.t("Сейчас выключен")
                Switch { on: Sys.night; onToggled: Sys.toggleNight() }
            }
            Line {
                icon: Icons.brightness; label: Tr.t("Интенсивность"); hint: Store.nightTemp + Tr.t(" К - чем меньше, тем теплее")
                WinSlider {
                    width: 240
                    value: (6000 - Store.nightTemp) / 4000
                    onMoved: v => Store.set("nightTemp", Math.round((6000 - v * 4000) / 100) * 100)
                }
            }
            Line {
                icon: Icons.history; label: Tr.t("Включать по расписанию")
                Switch { on: Store.nightAuto; onToggled: Store.set("nightAuto", !Store.nightAuto) }
            }
            Line {
                icon: Icons.history; label: Tr.t("Время работы"); hint: Tr.t("Часы:минуты, например 21:00 и 07:00")
                opacity: Store.nightAuto ? 1 : 0.5
                WText { anchors.verticalCenter: parent.verticalCenter; text: Tr.t("с") }
                Rectangle {
                    width: 64; height: 32; radius: 4
                    color: Theme.flyout
                    border.color: nfrom.activeFocus ? Theme.accent : Theme.border
                    TextInput {
                        id: nfrom
                        anchors.fill: parent
                        horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text; selectionColor: Theme.accent
                        font.family: Config.fontFamily; font.pixelSize: 12
                        maximumLength: 5
                        onTextEdited: if (Sys.minutes(text) >= 0) Store.set("nightFrom", text)
                    }
                }
                WText { anchors.verticalCenter: parent.verticalCenter; text: Tr.t("до") }
                Rectangle {
                    width: 64; height: 32; radius: 4
                    color: Theme.flyout
                    border.color: nto.activeFocus ? Theme.accent : Theme.border
                    TextInput {
                        id: nto
                        anchors.fill: parent
                        horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text; selectionColor: Theme.accent
                        font.family: Config.fontFamily; font.pixelSize: 12
                        maximumLength: 5
                        onTextEdited: if (Sys.minutes(text) >= 0) Store.set("nightTo", text)
                    }
                }
            }
            Line {
                visible: Sys.brightness >= 0
                icon: Icons.brightness; label: Tr.t("Яркость")
                WinSlider { width: 240; value: Sys.brightness; onMoved: v => Sys.setBrightness(v) }
            }
        }

        Column {
            visible: root.page === "personal"; property string pid: "personal"
            spacing: 6
            Line {
                icon: Icons.darkTheme; label: Tr.t("Тема")
                Seg {
                    options: [{ v: false, label: Tr.t("Светлая") }, { v: true, label: Tr.t("Тёмная") }]
                    value: Store.dark
                    onPicked: v => Store.set("dark", v)
                }
            }
            Line {
                icon: Icons.image; label: Tr.t("Обои"); hint: Tr.t("Путь к файлу")
                Rectangle {
                    width: 260; height: 32; radius: 4
                    color: Theme.flyout
                    border.color: path.activeFocus ? Theme.accent : Theme.border
                    TextInput {
                        id: path
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: Theme.text
                        selectionColor: Theme.accent
                        font.family: Config.fontFamily; font.pixelSize: 12
                        onAccepted: Store.set("wallpaper", text.trim().replace("file://", ""))
                    }
                }
                Btn { label: Tr.t("Применить"); onClicked: Store.set("wallpaper", path.text.trim().replace("file://", "")) }
                Btn { label: Tr.t("Сброс"); onClicked: { path.text = ""; Store.set("wallpaper", ""); } }
            }
            Line {
                icon: Icons.history; label: Tr.t("Смена обоев")
                hint: Sys.wallError !== "" && Store.wallMode !== "fixed" ? Tr.t("Не получилось: ") + Sys.wallError
                    : Store.wallMode === "web" ? Tr.t("Фотография дня из интернета") : ""
                Seg {
                    options: [{ v: "fixed", label: Tr.t("Нет") }, { v: "day", label: Tr.t("Каждый день") }, { v: "minute", label: Tr.t("Каждую минуту") }, { v: "web", label: Tr.t("Из интернета") }]
                    value: Store.wallMode
                    onPicked: v => { Store.wallKey = ""; Store.set("wallMode", v); }
                }
            }
            Line {
                visible: Store.wallMode === "day" || Store.wallMode === "minute"
                icon: Icons.folder; label: Tr.t("Папка с обоями"); hint: Tr.t("Пусто - ~/Pictures/Wallpapers")
                Rectangle {
                    width: 260; height: 32; radius: 4
                    color: Theme.flyout
                    border.color: wdir.activeFocus ? Theme.accent : Theme.border
                    TextInput {
                        id: wdir
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: Theme.text
                        selectionColor: Theme.accent
                        font.family: Config.fontFamily; font.pixelSize: 12
                        onAccepted: { Store.wallKey = ""; Store.set("wallDir", text.trim().replace("file://", "")); }
                    }
                }
                Btn { label: Tr.t("Применить"); onClicked: { Store.wallKey = ""; Store.set("wallDir", wdir.text.trim().replace("file://", "")); } }
            }
            Line {
                icon: Icons.lock; label: Tr.t("Экран блокировки")
                hint: Store.lockMode === "folder" ? Tr.t("Новая картинка из папки с обоями при каждой блокировке") : ""
                Seg {
                    options: [{ v: "same", label: Tr.t("Как рабочий стол") }, { v: "own", label: Tr.t("Своя") }, { v: "web", label: Tr.t("Фото дня") },
                              { v: "folder", label: Tr.t("Из папки") }, { v: "default", label: Tr.t("Стандартная") }]
                    value: Store.lockMode
                    onPicked: v => Store.set("lockMode", v)
                }
            }
            Line {
                off: Store.lockMode !== "own"
                icon: Icons.image; label: Tr.t("Картинка экрана блокировки"); hint: Tr.t("Путь к файлу")
                Field { id: lockPath; width: 260; text: Store.lockWallpaper; onAccepted: Store.set("lockWallpaper", text.trim().replace("file://", "")) }
                Btn { label: Tr.t("Применить"); onClicked: Store.set("lockWallpaper", lockPath.text.trim().replace("file://", "")) }
            }
            Line {
                icon: Icons.open; label: Tr.t("Скругление углов окон")
                Seg {
                    options: [{ v: 0, label: Tr.t("Нет") }, { v: 4, label: Tr.t("Малое") }, { v: 8, label: Tr.t("Обычное") }, { v: 12, label: Tr.t("Большое") }]
                    value: Store.niri.radius
                    onPicked: v => Store.setNiri("radius", v)
                }
            }
            Line {
                icon: Icons.brightness; label: Tr.t("Тени под окнами")
                Switch { on: Store.niri.shadows; onToggled: Store.setNiri("shadows", !Store.niri.shadows) }
            }
        }

        Column {
            visible: root.page === "taskbar"; property string pid: "taskbar"
            spacing: 6
            Line {
                icon: Icons.desktop; label: Tr.t("Положение"); hint: Tr.t("Край экрана")
                Seg {
                    options: [{ v: "bottom", label: Tr.t("Снизу") }, { v: "top", label: Tr.t("Сверху") }, { v: "left", label: Tr.t("Слева") }, { v: "right", label: Tr.t("Справа") }]
                    value: Store.barEdge
                    onPicked: v => Store.setBar(v, "")
                }
            }
            Line {
                icon: Icons.alignLeft; label: Tr.t("Кнопка \"Пуск\" и значки")
                Seg {
                    options: [{ v: "left", label: Tr.t("С края") }, { v: "center", label: Tr.t("По центру") }]
                    value: Store.barAlign
                    onPicked: v => Store.setBar("", v)
                }
            }
            Line {
                icon: Icons.search; label: Tr.t("Кнопка поиска"); hint: Tr.t("Win+S работает всегда")
                Switch { on: Store.showSearch; onToggled: Store.set("showSearch", !Store.showSearch) }
            }
            Line {
                icon: Icons.taskView; label: Tr.t("Кнопка представления задач"); hint: Tr.t("Win+Tab работает всегда")
                Switch { on: Store.showTaskView; onToggled: Store.set("showTaskView", !Store.showTaskView) }
            }
            Line {
                icon: Icons.sync
                label: Tr.t("Значок \"Центр обновления Windows\"")
                hint: Tr.t("Показывать значок на панели задач при наличии важных обновлений")
                Switch { on: Store.updIcon; onToggled: Store.set("updIcon", !Store.updIcon) }
            }
            Line {
                icon: Icons.apps
                label: Tr.t("Закреплённые значки")
                hint: Tr.t("Закреплять и откреплять программы можно щелчком правой кнопки мыши по значку")
            }
        }

        Column {
            visible: root.page === "windows"; property string pid: "windows"
            spacing: 6
            Line {
                icon: Icons.play; label: Tr.t("Анимации окон")
                Switch { on: Store.niri.animations; onToggled: Store.setNiri("animations", !Store.niri.animations) }
            }
            Line {
                icon: Icons.arrowDown; label: Tr.t("Плавное сворачивание окон"); hint: Tr.t("Окно уезжает к панели задач и возвращается обратно")
                Switch { on: Store.minAnim; onToggled: Store.set("minAnim", !Store.minAnim) }
            }
            Line {
                icon: Icons.next; label: Tr.t("Скорость анимаций")
                Seg {
                    options: [{ v: 0.6, label: Tr.t("Быстро") }, { v: 1, label: Tr.t("Обычно") }, { v: 1.6, label: Tr.t("Медленно") }]
                    value: Store.niri.animSlow
                    onPicked: v => Store.setNiri("animSlow", v)
                }
            }
            Line {
                icon: Icons.open; label: Tr.t("Скругление углов окон")
                Seg {
                    options: [{ v: 0, label: Tr.t("Нет") }, { v: 4, label: Tr.t("Малое") }, { v: 8, label: Tr.t("Обычное") }, { v: 12, label: Tr.t("Большое") }]
                    value: Store.niri.radius
                    onPicked: v => Store.setNiri("radius", v)
                }
            }
            Line {
                icon: Icons.brightness; label: Tr.t("Тени под окнами")
                Switch { on: Store.niri.shadows; onToggled: Store.setNiri("shadows", !Store.niri.shadows) }
            }
            Line {
                icon: Icons.cursor; label: Tr.t("Активировать окно наведением"); hint: Tr.t("Без щелчка мышью")
                Switch { on: Store.niri.focusFollows; onToggled: Store.setNiri("focusFollows", !Store.niri.focusFollows) }
            }
            Line {
                icon: Icons.wrench; label: Tr.t("Сочетания клавиш и остальное"); hint: Tr.t("Файл настроек niri")
                Btn { label: Tr.t("Открыть файл"); onClicked: Quickshell.execDetached(Config.niriConfigCommand) }
            }
        }

        // ---- Время и язык ----
        Flickable {
            visible: root.page === "lang"; property string pid: "lang"
            anchors.fill: parent
            clip: true
            contentHeight: langCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: langCol
                spacing: 6

                // Крупные цифровые часы и дата (как в Windows 11)
                Rectangle {
                    width: pages.width
                    height: 84
                    radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    Row {
                        anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                        spacing: 16
                        Column {
                            WText { font.pixelSize: 38; font.weight: Font.DemiBold; text: Qt.formatDateTime(Ui.now, "HH:mm") }
                            WText { font.pixelSize: 12; color: Theme.subtext; text: Qt.formatDateTime(Ui.now, Tr.t("d MMMM yyyy г.")) }
                        }
                    }
                    Column {
                        anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        Row {
                            spacing: 8
                            FIcon { icon: Icons.clock; font.pixelSize: 13; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                            WText { font.pixelSize: 12; text: Tr.t("Часовой пояс: ") + (root.tz !== "" ? root.tz : "Europe/Moscow") }
                        }
                        Row {
                            spacing: 8
                            FIcon { icon: Icons.globe; font.pixelSize: 13; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                            WText { font.pixelSize: 12; text: Tr.t("Регион: Россия") }
                        }
                    }
                }
                Picker {
                    icon: Icons.clock; label: Tr.t("Часовой пояс")
                    hint: root.tzError !== "" ? Tr.t("Не получилось: ") + root.tzError : (root.tz !== "" ? Tr.t("Сейчас: ") + root.tz : "")
                    placeholder: Tr.t("Город или регион: Москва, Paris, Asia")
                    rows: root.allZones
                    isOn: v => v === root.tz
                    onPicked: v => root.setZone(v)
                }
                Picker {
                    icon: Icons.language; label: Tr.t("Язык интерфейса и программ")
                    hint: Tr.t("Сейчас: ") + root.localeTitle(Store.lang) + Tr.t(". Оболочка переключается сразу, программы - после выхода и входа")
                    placeholder: Tr.t("Язык или код: Deutsch, uk, zh")
                    visibleRows: 4
                    rows: root.allLocales
                    isOn: v => v === Store.lang
                    onPicked: v => Store.setLang(v)
                }
                Card {
                    icon: Icons.keyboard; label: Tr.t("Языки ввода (раскладки)"); hint: Tr.t("Щелчок убирает раскладку. Порядок - как в списке")
                    Repeater {
                        model: (Store.niri.kbLayout || "").split(",").filter(x => x !== "")
                        Chip {
                            required property string modelData
                            label: root.layoutTitle(modelData) + "  ✕"
                            on: true
                            onClicked: root.setLayouts(root.csvToggle(Store.niri.kbLayout, modelData, true))
                        }
                    }
                }
                Picker {
                    icon: Icons.add; label: Tr.t("Добавить раскладку")
                    hint: Tr.t("Все языки и варианты: фонетическая, машинописная, Дворак и другие")
                    placeholder: Tr.t("Язык или вариант: русская, phonetic, dvorak")
                    rows: root.allLayouts
                    isOn: v => root.csvHas(Store.niri.kbLayout, v)
                    onPicked: v => root.setLayouts(root.csvToggle(Store.niri.kbLayout, v, true))
                }
                Line {
                    icon: Icons.keyboard; label: Tr.t("Свой список раскладок"); hint: Tr.t("Коды через запятую: us,ru,de")
                    Rectangle {
                        width: 160; height: 32; radius: 4
                        color: Theme.flyout
                        border.color: layouts.activeFocus ? Theme.accent : Theme.border
                        TextInput {
                            id: layouts
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: Theme.text
                            selectionColor: Theme.accent
                            font.family: Config.fontFamily; font.pixelSize: 12
                            onAccepted: Store.setNiri("kbLayout", text.trim().toLowerCase())
                        }
                    }
                    Btn { label: Tr.t("Применить"); onClicked: Store.setNiri("kbLayout", layouts.text.trim().toLowerCase()) }
                }
                Card {
                    icon: Icons.arrowRight; label: Tr.t("Смена языка ввода"); hint: Tr.t("Можно включить несколько способов")
                    Repeater {
                        model: root.toggles
                        Chip {
                            required property var modelData
                            label: modelData[1]
                            on: root.csvHas(Store.niri.kbToggle, modelData[0])
                            onClicked: Store.setNiri("kbToggle", root.csvToggle(Store.niri.kbToggle, modelData[0], true))
                        }
                    }
                }
            }
        }

        // ---- Темы оформления и значок "Пуск" ----
        Flickable {
            visible: root.page === "themes"; property string pid: "themes"
            anchors.fill: parent
            clip: true
            contentHeight: themeCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: themeCol
                spacing: 6
                Line {
                    icon: Icons.darkTheme; label: Tr.t("Режим")
                    Seg {
                        options: [{ v: false, label: Tr.t("Светлый") }, { v: true, label: Tr.t("Тёмный") }]
                        value: Store.dark
                        onPicked: v => Store.set("dark", v)
                    }
                }
                Card {
                    icon: Icons.brush; label: Tr.t("Тема оформления")
                    hint: Theme.errors.length > 0 ? Tr.t("Не прочитаны: ") + Theme.errors.join(", ") : Tr.t("Цвета панели задач, окон оболочки и акцента")
                    Chip { label: "Windows 11"; on: Theme.current === null; onClicked: Theme.use("") }
                    Repeater {
                        model: Theme.all
                        Rectangle {
                            id: tc
                            required property var modelData
                            readonly property bool on: Store.theme === modelData.name
                            readonly property var side: (Theme.dark ? modelData.dark : modelData.light) || ({})
                            width: tcText.implicitWidth + 44; height: 30; radius: 4
                            color: on ? Theme.accent : (tcArea.containsMouse ? Theme.hover : "transparent")
                            border.color: on ? Theme.accent : Theme.border
                            // образец акцентного цвета темы
                            Rectangle {
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                width: 14; height: 14; radius: 7
                                color: Theme.ok(tc.side.accent) ? tc.side.accent : (Theme.ok(tc.modelData.accent) ? tc.modelData.accent : Theme.accent)
                                border.color: Theme.border
                            }
                            WText { id: tcText; x: 30; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; color: tc.on ? Theme.accentText : Theme.text; text: tc.modelData.name }
                            MouseArea { id: tcArea; anchors.fill: parent; hoverEnabled: true; onClicked: Theme.use(tc.modelData.name) }
                        }
                    }
                }
                Line {
                    icon: Icons.folder; label: Tr.t("Свои темы"); hint: Tr.t("Файлы .json")
                    Btn { label: Tr.t("Создать свою тему"); onClicked: Theme.createSample() }
                    Btn { label: Tr.t("Папка тем"); onClicked: Theme.openDir() }
                    Btn { label: Tr.t("Обновить список"); onClicked: Theme.reload() }
                }
                Card {
                    icon: Icons.apps; label: Tr.t("Значок кнопки \"Пуск\""); hint: Store.startIconCustom ? Tr.t("Сейчас: своя картинка") : ""
                    Repeater {
                        model: Store.startIcons
                        Rectangle {
                            id: si
                            required property var modelData
                            readonly property bool on: Store.startIcon === modelData.id
                            width: 84; height: 74; radius: 6
                            color: siArea.containsMouse ? Theme.hover : "transparent"
                            border.width: on ? 2 : 1
                            border.color: on ? Theme.accent : Theme.border
                            Image {
                                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 10 }
                                width: 32; height: 32; sourceSize.width: 64; sourceSize.height: 64
                                source: Qt.resolvedUrl("assets/" + (si.modelData.id === "nixos" ? "nixos" : "start-" + si.modelData.id) + ".svg")
                            }
                            WText { anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 } font.pixelSize: 11; text: si.modelData.label }
                            MouseArea { id: siArea; anchors.fill: parent; hoverEnabled: true; onClicked: Store.set("startIcon", si.modelData.id) }
                        }
                    }
                }
                Line {
                    icon: Icons.image; label: Tr.t("Свой значок"); hint: Tr.t("Путь к png, svg, jpg")
                    Rectangle {
                        width: 250; height: 32; radius: 4
                        color: Theme.flyout
                        border.color: sicon.activeFocus ? Theme.accent : Theme.border
                        TextInput {
                            id: sicon
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: Theme.text; selectionColor: Theme.accent
                            font.family: Config.fontFamily; font.pixelSize: 12
                            text: Store.startIconCustom ? Store.startIcon : ""
                            onAccepted: root.setStartIcon(text)
                        }
                    }
                    Btn { label: Tr.t("Применить"); onClicked: root.setStartIcon(sicon.text) }
                }
            }
        }

        // ---- Уведомления ----
        Flickable {
            visible: root.page === "notify"; property string pid: "notify"
            anchors.fill: parent
            clip: true
            contentHeight: notifyCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: notifyCol
                spacing: 6
                Line {
                    icon: Icons.alertSnooze; label: Tr.t("Не беспокоить")
                    hint: Store.dnd ? Tr.t("Включено: уведомления не всплывают, а сразу ложатся в центр уведомлений") : Tr.t("Выключено: всплывают все уведомления")
                    Switch { on: Store.dnd; onToggled: Notifs.toggleDnd() }
                }
                Line {
                    icon: Icons.shield; label: Tr.t("Системные уведомления")
                    hint: Tr.t("Сеть, питание, печать, безопасность и срочные - всплывают всегда")
                    FIcon { anchors.verticalCenter: parent.verticalCenter; icon: Icons.check; color: Theme.accent }
                }
                Card {
                    icon: Icons.person; label: Tr.t("Исключения")
                    hint: Store.dndAllow.length === 0 ? Tr.t("Пока пусто") : Tr.t("Щелчок убирает программу из списка")
                    Repeater {
                        model: Store.dndAllow
                        Chip { required property string modelData; label: modelData + "  ✕"; on: true; onClicked: Notifs.allow(modelData, false) }
                    }
                    WText {
                        visible: Store.dndAllow.length === 0
                        font.pixelSize: 12; color: Theme.subtext
                        text: Tr.t("Этим программам разрешено всплывать при \"Не беспокоить\". Добавьте их из списка ниже.")
                    }
                }
                Card {
                    visible: root.dndRecent.length > 0
                    icon: Icons.history; label: Tr.t("Недавно присылали уведомления"); hint: Tr.t("Щелчок добавляет в исключения")
                    Repeater {
                        model: root.dndRecent
                        Chip { required property string modelData; label: "+  " + modelData; onClicked: Notifs.allow(modelData, true) }
                    }
                }
                Picker {
                    icon: Icons.add; label: Tr.t("Добавить программу")
                    hint: Tr.t("Установленные программы. Отмеченные - уже в исключениях")
                    placeholder: Tr.t("Название: Telegram, Discord, Firefox")
                    rows: root.dndApps
                    isOn: v => Notifs.isAllowedName(v)
                    onPicked: v => Notifs.allow(v, !Notifs.isAllowedName(v))
                }
                Line {
                    icon: Icons.dismiss; label: Tr.t("Очистить уведомления"); hint: Tr.t("Сейчас в центре уведомлений: ") + Notifs.count
                    Btn { label: Tr.t("Очистить"); onClicked: Notifs.clearAll() }
                }
            }
        }

        // ---- Учётная запись ----
        Column {
            visible: root.page === "accounts"; property string pid: "accounts"
            spacing: 6
            Rectangle {
                width: pages.width; height: 132; radius: 6
                color: Theme.card
                border.color: Theme.border
                Avatar { id: face; x: 20; anchors.verticalCenter: parent.verticalCenter; width: 92; height: 92; backColor: Theme.dark ? "#4a4a4a" : "#d0d0d0"; iconColor: Theme.text }
                Column {
                    anchors { left: face.right; leftMargin: 20; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    WText { font.pixelSize: 20; font.weight: Font.DemiBold; text: Config.userName }
                    WText { color: Theme.subtext; text: Tr.t("Локальная учётная запись") + " • " + Tr.t("Администратор") }
                }
            }
            Line {
                icon: Icons.lock
                label: Tr.t("Пароль учётной записи")
                hint: Tr.t("Изменение системного пароля пользователя")
                Btn { label: Tr.t("Сменить пароль"); onClicked: Tools.runInTerminal("passwd") }
            }
            Line {
                icon: Icons.history
                label: Tr.t("Автоблокировка экрана")
                hint: Tr.t("Блокировать экран после 10 минут простоя")
                Switch { on: Store.autoLock; onToggled: Store.set("autoLock", !Store.autoLock) }
            }
            Line {
                icon: Icons.image; label: Tr.t("Аватарка")
                hint: root.faceError !== "" ? Tr.t("Не получилось: ") + root.faceError : Tr.t("Путь к файлу")
                Rectangle {
                    width: 240; height: 32; radius: 4
                    color: Theme.flyout
                    border.color: facePath.activeFocus ? Theme.accent : Theme.border
                    TextInput {
                        id: facePath
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: Theme.text; selectionColor: Theme.accent
                        font.family: Config.fontFamily; font.pixelSize: 12
                        onAccepted: root.setFace(text)
                    }
                }
                Btn { label: Tr.t("Применить"); onClicked: root.setFace(facePath.text) }
                Btn { label: Tr.t("Убрать"); onClicked: { facePath.text = ""; root.setFace(""); } }
            }
            WText {
                width: pages.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                font.pixelSize: 12; color: Theme.subtext
                text: Tr.t("Путь проще всего получить так: в \"Проводнике\" выделите картинку, нажмите Ctrl+C и вставьте сюда (Ctrl+V). ")
                    + Tr.t("Аватарка показывается в \"Пуске\", на экране блокировки и на экране входа.")
            }
        }

        // ---- Приложения ----
        Item {
            visible: root.page === "apps"; property string pid: "apps"
            anchors.fill: parent
            Rectangle {
                id: pkgBox
                width: parent.width; height: 36; radius: 18
                color: Theme.card
                border.color: pkgInput.activeFocus ? Theme.accent : Theme.border
                FIcon { id: pkgIcon; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } icon: Icons.search }
                WText {
                    anchors { left: pkgIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    visible: pkgInput.text === ""
                    color: Theme.subtext
                    text: Tr.t("Найти программу: discord, firefox, telegram…")
                }
                TextInput {
                    id: pkgInput
                    anchors { left: pkgIcon.right; leftMargin: 10; right: pkgSpin.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    clip: true
                    color: Theme.text; selectionColor: Theme.accent
                    font.family: Config.fontFamily; font.pixelSize: 13
                    onTextChanged: { root.pkgQuery = text; pkgDelay.restart(); }
                }
                Spinner { id: pkgSpin; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } width: 16; height: 16; visible: root.pkgBusy || root.pkgJob !== "" }
            }
            // отбор по источнику и управление источниками
            Row {
                id: pkgTabs
                anchors { top: pkgBox.bottom; topMargin: 8; left: parent.left }
                spacing: 4
                Repeater {
                    model: [{ v: "all", label: Tr.t("Все") }, { v: "installed", label: Tr.t("Установленные") }, { v: "nix", label: "NixOS" }, { v: "flatpak", label: "Flathub" }]
                    Chip {
                        required property var modelData
                        label: modelData.label
                        on: root.pkgFilter === modelData.v
                        onClicked: root.pkgFilter = modelData.v
                    }
                }
            }
            Chip {
                id: srcChip
                anchors { top: pkgTabs.top; right: parent.right }
                label: Tr.t("Источники и файлы")
                on: root.srcPanel
                onClicked: { root.srcPanel = !root.srcPanel; if (root.srcPanel) srcList.running = true; }
            }
            Chip {
                anchors { top: pkgTabs.top; right: srcChip.left; rightMargin: 6 }
                label: Tr.t("Открыть магазин")
                onClicked: Tools.runInTerminal("win11-software-center run")
            }
            Rectangle {
                id: srcBox
                visible: root.srcPanel
                anchors { top: pkgTabs.bottom; topMargin: 8; left: parent.left; right: parent.right }
                height: srcCol.implicitHeight + 24
                radius: 6
                color: Theme.card
                border.color: Theme.border
                Column {
                    id: srcCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8
                    Repeater {
                        model: root.srcRows
                        Item {
                            id: sr
                            required property var modelData
                            width: srcCol.width; height: 28
                            WText { anchors { left: parent.left; verticalCenter: parent.verticalCenter } width: 150; text: sr.modelData.name }
                            WText {
                                anchors { left: parent.left; leftMargin: 160; right: srDel.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                font.pixelSize: 11; color: Theme.subtext
                                text: (sr.modelData.kind === "flatpak" ? "flatpak" : "Nix") + " · " + sr.modelData.url
                            }
                            Btn {
                                id: srDel
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                visible: sr.modelData.removable
                                implicitHeight: 26
                                label: Tr.t("Удалить")
                                onClicked: root.srcRemove(sr.modelData)
                            }
                        }
                    }
                    Flow {
                        width: parent.width; spacing: 6
                        WText { height: 30; verticalAlignment: Text.AlignVCenter; font.pixelSize: 12; color: Theme.subtext; text: Tr.t("Добавить готовый:") }
                        Repeater {
                            model: root.srcPresets.filter(p => !root.srcRows.some(r => r.name === p.name))
                            Chip {
                                required property var modelData
                                label: modelData.label
                                onClicked: root.srcAdd(modelData.kind, modelData.name, modelData.url)
                            }
                        }
                    }
                    Row {
                        spacing: 6
                        Seg {
                            options: [{ v: "flatpak", label: "flatpak" }, { v: "nix", label: "Nix" }]
                            value: root.srcKind
                            onPicked: v => root.srcKind = v
                        }
                        Field { id: srcName; width: 120; hint: Tr.t("имя") }
                        Field { id: srcUrl; width: srcCol.width - 480; hint: root.srcKind === "flatpak" ? Tr.t("адрес .flatpakrepo") : Tr.t("адрес архива с пакетами Nix") }
                        Btn { label: Tr.t("Добавить источник"); onClicked: root.srcAdd(root.srcKind, srcName.text, srcUrl.text) }
                    }
                    Row {
                        spacing: 6
                        Field { id: appImage; width: srcCol.width - 180; hint: Tr.t("путь к файлу .AppImage") }
                        Btn { label: Tr.t("Установить файл"); onClicked: root.appImageAdd(appImage.text) }
                    }
                }
            }
            ListView {
                id: pkgView
                anchors { top: srcBox.visible ? srcBox.bottom : pkgTabs.bottom; topMargin: 8; bottom: pkgNote.top; bottomMargin: 8; left: parent.left; right: parent.right }
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: root.pkgShown
                delegate: Rectangle {
                    id: pk
                    required property var modelData
                    readonly property string key: modelData.src + ":" + modelData.id
                    readonly property bool mine: root.pkgJob === key
                    readonly property bool queued: root.pkgQueue.some(j => j.key === key)
                    width: pkgView.width; height: 52; radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    Column {
                        anchors { left: parent.left; leftMargin: 14; right: pkAct.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        WText { width: parent.width; text: pk.modelData.name }
                        WText {
                            width: parent.width; font.pixelSize: 11; color: Theme.subtext
                            text: root.srcLabel(pk.modelData.src) + (pk.modelData.desc !== "" ? " · " + pk.modelData.desc : "")
                        }
                    }
                    Row {
                        id: pkAct
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        WText { anchors.verticalCenter: parent.verticalCenter; visible: pk.modelData.state === "system"; font.pixelSize: 12; color: Theme.subtext; text: Tr.t("Входит в систему") }
                        WText { anchors.verticalCenter: parent.verticalCenter; visible: pk.mine; font.pixelSize: 12; color: Theme.subtext; text: Tr.t("Подождите…") }
                        WText { anchors.verticalCenter: parent.verticalCenter; visible: pk.queued; font.pixelSize: 12; color: Theme.subtext; text: Tr.t("В очереди") }
                        Btn { visible: pk.queued; label: Tr.t("Отменить"); onClicked: root.pkgCancel(pk.key) }
                        Btn {
                            visible: pk.modelData.state === "available" && !pk.mine && !pk.queued
                            label: Tr.t("Установить")
                            onClicked: root.pkgRun("install", pk.modelData)
                        }
                        Btn {
                            visible: pk.modelData.state === "installed" && !pk.mine && !pk.queued
                            label: Tr.t("Удалить")
                            onClicked: root.pkgRun("remove", pk.modelData)
                        }
                    }
                }
            }
            WText {
                anchors.centerIn: pkgView
                visible: root.pkgShown.length === 0
                color: Theme.subtext
                text: root.pkgBusy ? Tr.t("Идёт поиск") : Tr.t("Ничего не найдено")
            }
            WText {
                id: pkgNote
                anchors { bottom: parent.bottom; left: parent.left; right: pkgBar.visible ? pkgBar.left : parent.right; rightMargin: pkgBar.visible ? 12 : 0 }
                elide: Text.ElideRight
                font.pixelSize: 12; color: Theme.subtext
                text: root.pkgStatus !== "" ? root.pkgStatus + (root.pkgQueue.length > 0 ? Tr.t("  ·  в очереди: ") + root.pkgQueue.length : "") : Tr.t("Программы ставятся в ваш профиль: пароль не нужен. Источники: ") + ["NixOS", "Flathub"].concat(root.srcRows.filter(r => r.removable).map(r => r.name)).join(", ") + "."
            }
            Rectangle {
                id: pkgBar
                visible: root.pkgJob !== ""
                anchors { right: pkgPctText.left; rightMargin: 8; verticalCenter: pkgNote.verticalCenter }
                width: 180; height: 4; radius: 2
                color: Theme.border
                Rectangle {
                    width: parent.width * Math.max(0.03, root.pkgPct / 100); height: parent.height; radius: 2
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 200 } }
                }
            }
            WText {
                id: pkgPctText
                visible: pkgBar.visible
                anchors { right: parent.right; verticalCenter: pkgNote.verticalCenter }
                width: 34; horizontalAlignment: Text.AlignRight
                font.pixelSize: 12; color: Theme.subtext
                text: root.pkgPct + "%"
            }
        }

        Flickable {
            visible: root.page === "keyboard"; property string pid: "keyboard"
            anchors.fill: parent
            clip: true
            contentHeight: kbCol.implicitHeight + 20
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: kbCol
                spacing: 6

                // Подключённые клавиатуры
                Rectangle {
                    visible: Sys.btDevices.some(d => d.type === "keyboard")
                    width: pages.width
                    height: 44 + Sys.btDevices.filter(d => d.type === "keyboard").length * 34
                    radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    WText { x: 16; y: 12; font.pixelSize: 13; font.weight: Font.DemiBold; text: Tr.t("Подключённые клавиатуры") }
                    Column {
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 36; margins: 14 }
                        spacing: 4
                        Repeater {
                            model: Sys.btDevices.filter(d => d.type === "keyboard")
                            Row {
                                required property var modelData
                                width: parent.width; height: 30
                                spacing: 12
                                FIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.pixelSize: 15
                                    icon: Icons.keyboard
                                }
                                WText { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; text: modelData.name }
                                WText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.pixelSize: 11
                                    color: modelData.percent > 0 ? Theme.accent : Theme.subtext
                                    font.weight: Font.DemiBold
                                    text: modelData.percent > 0 ? (modelData.percent + "%") : Tr.t("Подключено")
                                }
                            }
                        }
                    }
                }

                Line {
                    icon: Icons.pause; label: Tr.t("Задержка перед повтором")
                    Seg {
                        options: [{ v: 300, label: Tr.t("Короткая") }, { v: 450, label: Tr.t("Средняя") }, { v: 600, label: Tr.t("Длинная") }]
                        value: Store.niri.repeatDelay
                        onPicked: v => Store.setNiri("repeatDelay", v)
                    }
                }

                Line {
                    icon: Icons.next; label: Tr.t("Скорость повтора")
                    Seg {
                        options: [{ v: 15, label: Tr.t("Медленно") }, { v: 25, label: Tr.t("Обычно") }, { v: 40, label: Tr.t("Быстро") }]
                        value: Store.niri.repeatRate
                        onPicked: v => Store.setNiri("repeatRate", v)
                    }
                }

                Line {
                    icon: Icons.check; label: Tr.t("Num Lock включён при входе")
                    Switch { on: Store.niri.numlock; onToggled: Store.setNiri("numlock", !Store.niri.numlock) }
                }

                Line {
                    icon: Icons.keyboard
                    label: Tr.t("Экранная клавиатура")
                    hint: Tr.t("Виртуальная клавиатура для ввода с экрана или мыши")
                    Btn {
                        label: Tr.t("Запустить")
                        onClicked: Tools.run(["sh", "-c", "command -v wvkbd >/dev/null 2>&1 && wvkbd || command -v maliit-keyboard >/dev/null 2>&1 && maliit-keyboard || command -v onboard >/dev/null 2>&1 && onboard || true"])
                    }
                }

                Line {
                    icon: Icons.language
                    label: Tr.t("Языковые параметры и раскладки")
                    hint: Tr.t("Настройка горячих клавиш переключения и добавление раскладок")
                    Btn {
                        label: Tr.t("Открыть")
                        onClicked: root.page = "lang"
                    }
                }
            }
        }

        // ---- Звук ----
        Flickable {
            visible: root.page === "sound"; property string pid: "sound"
            anchors.fill: parent
            clip: true
            contentHeight: soundCol.implicitHeight + 20
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: soundCol
                spacing: 6

                // Громкость
                Line {
                    icon: Sys.muted ? Icons.speakerMute : Icons.speaker
                    label: Tr.t("Громкость")
                    hint: Sys.muted ? Tr.t("Звук выключен") : Math.round(Sys.volume * 100) + "%"
                    WinSlider {
                        width: 200
                        value: Sys.volume
                        onMoved: v => Sys.setVolume(v)
                    }
                    Btn {
                        label: Sys.muted ? Tr.t("Включить звук") : Tr.t("Выключить звук")
                        onClicked: Sys.toggleMute()
                    }
                }

                // Устройства вывода
                Card {
                    icon: Icons.speaker
                    label: Tr.t("Устройства воспроизведения (вывод)")
                    hint: Tr.t("Выберите устройство для вывода звука")
                    Repeater {
                        model: Tools.sinks
                        Chip {
                            required property var modelData
                            label: modelData.title
                            on: modelData.name === Tools.defaultSink
                            onClicked: Tools.run(["win11-sound", "out", String(modelData.n)])
                        }
                    }
                }

                // Устройства ввода (микрофон)
                Card {
                    visible: Tools.sources.length > 0
                    icon: Icons.mic
                    label: Tr.t("Устройства записи (микрофон)")
                    hint: Tr.t("Выберите микрофон по умолчанию")
                    Repeater {
                        model: Tools.sources
                        Chip {
                            required property var modelData
                            label: modelData.title
                            on: modelData.name === Tools.defaultSource
                            onClicked: Tools.run(["win11-sound", "in", String(modelData.n)])
                        }
                    }
                }

                // Проверка звука
                Line {
                    icon: Icons.play
                    label: Tr.t("Проверка звука")
                    hint: Tr.t("Тестовый сигнал на выбранном устройстве")
                    Btn { label: Tr.t("Проиграть"); onClicked: Tools.run(["win11-sound", "test"]) }
                }

                // Устранение неполадок
                Line {
                    icon: Icons.wrench
                    label: Tr.t("Устранение неполадок")
                    hint: Tr.t("Автоматическая починка служб PipeWire и ALSA")
                    Btn { label: Tr.t("Починить звук"); onClicked: Tools.runInTerminal("win11-sound fix") }
                    Btn { label: Tr.t("Диагностика"); onClicked: Tools.runInTerminal("win11-sound") }
                }



                Line {
                    visible: true
                    icon: Icons.info
                    label: Tr.t("Режим аудиоустройств")
                    hint: Tools.isVm ? Tr.t("Виртуальная звуковая карта (управляется гипервизором хоста)") : Tr.t("Стандартный аудиоконтроллер (переназначение гнёзд не требуется)")
                }

                Line {
                    icon: Icons.tools
                    label: Tr.t("Дополнительные параметры звука")
                    hint: Tr.t("Расширенный микшер громкости и профили устройств")
                    Btn {
                        label: Tr.t("Открыть микшер")
                        onClicked: Tools.run(["sh", "-c", "command -v pavucontrol >/dev/null 2>&1 && pavucontrol || alsamixer"])
                    }
                }
            }
        }

        // ---- Bluetooth и устройства: Устройства (вся периферия) ----
        Flickable {
            visible: root.page === "devices"; property string pid: "devices"
            anchors.fill: parent
            clip: true
            contentHeight: devCol.implicitHeight + 20
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: devCol
                spacing: 8

                // Карточка Bluetooth
                Rectangle {
                    width: pages.width
                    height: 64
                    radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    Row {
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        FIcon { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 22; icon: Icons.bluetooth }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            WText { font.pixelSize: 14; font.weight: Font.DemiBold; text: "Bluetooth" }
                            WText { font.pixelSize: 12; color: Theme.subtext; text: Sys.hasBluetooth ? (Sys.bluetooth ? Tr.t("Включён") : Tr.t("Выключен")) : Tr.t("Адаптер не обнаружен") }
                        }
                    }
                    Switch {
                        visible: Sys.hasBluetooth
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        on: Sys.bluetooth
                        onToggled: Sys.setBluetooth(!Sys.bluetooth)
                    }
                }

                Line {
                    icon: Icons.add
                    label: Tr.t("Добавить устройство")
                    hint: Tr.t("Поиск Bluetooth-устройств поблизости для сопряжения")
                    Btn {
                        label: Tr.t("Поиск")
                        onClicked: Tools.runInTerminal("bluetoothctl scan on")
                    }
                }

                // Заголовок периферии
                WText { topPadding: 4; font.pixelSize: 13; font.weight: Font.DemiBold; text: Tr.t("Подключенные устройства и периферия") }

                // Список всех устройств
                Rectangle {
                    visible: Sys.btDevices.length > 0
                    width: pages.width
                    height: 20 + Sys.btDevices.length * 36
                    radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    Column {
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 4
                        Repeater {
                            model: Sys.btDevices
                            Row {
                                required property var modelData
                                width: parent.width; height: 32
                                spacing: 12
                                Item {
                                    width: 18; height: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: modelData.type === "mouse"
                                    Image { anchors.centerIn: parent; width: 16; height: 16; sourceSize: Qt.size(16, 16); source: Qt.resolvedUrl("assets/bt-mouse.svg") }
                                }
                                FIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.pixelSize: 16
                                    visible: modelData.type !== "mouse"
                                    icon: modelData.type === "keyboard" ? Icons.keyboard : modelData.type === "gamepad" ? Icons.gamepad : Icons.headphones
                                }
                                WText { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 13; text: modelData.name }
                                WText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.pixelSize: 11
                                    color: modelData.percent > 0 ? Theme.accent : Theme.subtext
                                    font.weight: Font.DemiBold
                                    text: modelData.percent > 0 ? (modelData.percent + "%") : Tr.t("Подключено")
                                }
                            }
                        }
                    }
                }

                // Быстрые переходы к подразделам
                Line {
                    icon: Icons.printer
                    label: Tr.t("Принтеры и сканеры")
                    hint: Tr.t("Очереди печати, настройка и сканирование")
                    Btn { label: Tr.t("Открыть"); onClicked: root.page = "printers" }
                }

                Line {
                    icon: Icons.cursor
                    label: Sys.hasTouchpad ? Tr.t("Мышь и сенсорная панель") : Tr.t("Мышь")
                    hint: Tr.t("Скорость указателя, ускорение и колесо мыши")
                    Btn { label: Tr.t("Открыть"); onClicked: root.page = "mouse" }
                }

                Line {
                    icon: Icons.keyboard
                    label: Tr.t("Клавиатура")
                    hint: Tr.t("Параметры ввода, задержка и скорость повтора")
                    Btn { label: Tr.t("Открыть"); onClicked: root.page = "keyboard" }
                }
            }
        }

        // ---- Принтеры и сканеры ----
        Column {
            visible: root.page === "printers"; property string pid: "printers"
            spacing: 6

            Line {
                icon: Icons.add
                label: Tr.t("Добавить принтер или сканер")
                hint: Tr.t("Поиск принтеров в локальной сети и по USB")
                Btn { label: Tr.t("Добавить"); onClicked: Tools.runInTerminal("win11-printfix add") }
            }

            Line {
                icon: Icons.printer
                label: Tr.t("Служба печати CUPS")
                hint: Tr.t("Диспетчер очереди локальной и сетевой печати")
                Btn { label: Tr.t("Состояние"); onClicked: Tools.runInTerminal("win11-printfix") }
            }

            Line {
                icon: Icons.tools
                label: Tr.t("Устранение неполадок с печатью")
                hint: Tr.t("Очистить очереди, исправить права и перезапустить")
                Btn { label: Tr.t("Починить"); onClicked: Tools.runInTerminal("win11-printfix fix") }
            }

            Line {
                icon: Icons.document
                label: Tr.t("Пробная печать")
                hint: Tr.t("Отправить тестовую страницу на принтер по умолчанию")
                Btn { label: Tr.t("Печать"); onClicked: Tools.runInTerminal("win11-printfix test") }
            }

            Line {
                icon: Icons.open
                label: Tr.t("Сканирование документов")
                hint: Tr.t("Приложение для сканирования со сканеров и МФУ")
                Btn { label: Tr.t("Сканировать"); onClicked: Tools.run(["simple-scan"]) }
            }

            Line {
                icon: Icons.globe
                label: Tr.t("Веб-интерфейс администрирования CUPS")
                hint: "http://localhost:631 — " + Tr.t("управление всеми очередями и сетевыми драйверами")
                Btn {
                    label: Tr.t("Открыть в браузере")
                    onClicked: Tools.run(["xdg-open", "http://localhost:631"])
                }
            }
        }

        // ---- Обход блокировок (zapret) ----
        Flickable {
            visible: root.page === "zapret"; property string pid: "zapret"
            anchors.fill: parent
            clip: true
            contentHeight: zapretCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: zapretCol
                spacing: 6
                readonly property bool present: Tools.zapretMode === "on" || Tools.zapretMode === "off"

                // Карточка сети: значок подключения, статус (как в Windows 11)
                Rectangle {
                    width: pages.width
                    height: 72
                    radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    Row {
                        anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                        spacing: 16
                        FIcon { icon: Sys.netIcon; font.pixelSize: 30; anchors.verticalCenter: parent.verticalCenter; color: Sys.online ? Theme.accent : Theme.subtext }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            WText { font.pixelSize: 15; font.weight: Font.DemiBold; text: Sys.netText }
                            WText { font.pixelSize: 12; color: Theme.subtext; text: Sys.online ? Tr.t("Подключение установлено") : Tr.t("Без доступа к интернету") }
                        }
                    }
                    WText {
                        anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                        font.pixelSize: 12; color: Theme.subtext
                        text: Tr.t("Частная сеть")
                    }
                }
                Line {
                    icon: Icons.globe; label: Tr.t("Обход замедления YouTube и Discord")
                    hint: ({ on: Tr.t("Работает"), off: Tr.t("Остановлен до перезагрузки"), disabled: Tr.t("Выключен насовсем"),
                             missing: Tr.t("Не установлен: обновите оболочку"), "": Tr.t("Проверяю...") })[Tools.zapretMode] || ""
                    Switch {
                        visible: zapretCol.present
                        on: Tools.zapretMode === "on"
                        onToggled: Tools.runInTerminal("win11-zapret " + (Tools.zapretMode === "on" ? "off" : "on"))
                    }
                }
                Line {
                    off: Tools.zapretMode === "missing" || Tools.zapretMode === ""
                    icon: Icons.shield; label: Tr.t("Включать при запуске системы"); hint: Tr.t("Смена пересобирает систему")
                    Switch {
                        on: Tools.zapretMode !== "disabled"
                        onToggled: Tools.runInTerminal("win11-zapret " + (Tools.zapretMode === "disabled" ? "enable" : "disable"))
                    }
                }
                Card {
                    visible: zapretCol.present
                    icon: Icons.tools; label: Tr.t("Стратегия"); hint: Tr.t("Если сайты не открываются - попробуйте другую")
                    Repeater {
                        model: Tools.strategies
                        Chip {
                            required property string modelData
                            label: modelData
                            on: modelData === Tools.strategy
                            // номер из win11-zapret list: в именах есть скобки и пробелы
                            onClicked: Tools.zapret(["set", "" + (Tools.strategies.indexOf(modelData) + 1)])
                        }
                    }
                }
                Line {
                    off: !zapretCol.present
                    icon: Icons.rocket; label: Tr.t("Игровой фильтр"); hint: Tr.t("Обход для всех портов выше 1024: игры, звонки")
                    Seg {
                        options: [{ v: "off", label: Tr.t("Выкл") }, { v: "udp", label: "UDP" }, { v: "tcp", label: "TCP" }, { v: "all", label: Tr.t("Все") }]
                        value: Tools.game
                        onPicked: v => Tools.zapret(["game", v])
                    }
                }
                Card {
                    visible: zapretCol.present
                    icon: Icons.person; label: Tr.t("Пакет для звонков Discord"); hint: Tr.t("Меняйте, если звонок висит на \"RTC connecting\"")
                    Repeater {
                        model: Tools.fakes.concat(["default"])
                        Chip {
                            required property string modelData
                            label: modelData === "default" ? Tr.t("как у Flowseal") : modelData.replace("quic_initial_", "").replace(".bin", "")
                            on: modelData === Tools.fake
                            onClicked: Tools.zapret(["fake", modelData])
                        }
                    }
                }
                Line {
                    off: !zapretCol.present
                    icon: Icons.health; label: Tr.t("Проверка")
                    Btn { label: Tr.t("Проверить сайты"); onClicked: Tools.runInTerminal("win11-zapret check") }
                    Btn { label: Tr.t("Звонки"); onClicked: Tools.runInTerminal("win11-zapret voice") }
                    Btn { label: Tr.t("Перебор при звонке"); onClicked: Tools.runInTerminal("win11-zapret calls") }
                    Btn { label: Tr.t("Подобрать стратегию"); onClicked: Tools.runInTerminal("win11-zapret test") }
                }
            }
        }

        Flickable {
            visible: root.page === "mouse"; property string pid: "mouse"
            anchors.fill: parent
            clip: true
            contentHeight: mouseCol.implicitHeight + 20
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: mouseCol
                spacing: 6

                // Подключённые мыши
                Rectangle {
                    visible: Sys.btDevices.some(d => d.type === "mouse")
                    width: pages.width
                    height: 44 + Sys.btDevices.filter(d => d.type === "mouse").length * 34
                    radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    WText { x: 16; y: 12; font.pixelSize: 13; font.weight: Font.DemiBold; text: Tr.t("Подключённые мыши и манипуляторы") }
                    Column {
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 36; margins: 14 }
                        spacing: 4
                        Repeater {
                            model: Sys.btDevices.filter(d => d.type === "mouse")
                            Row {
                                required property var modelData
                                width: parent.width; height: 30
                                spacing: 12
                                Item {
                                    width: 16; height: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    Image { anchors.centerIn: parent; width: 15; height: 15; sourceSize: Qt.size(15, 15); source: Qt.resolvedUrl("assets/bt-mouse.svg") }
                                }
                                WText { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; text: modelData.name }
                                WText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.pixelSize: 11
                                    color: modelData.percent > 0 ? Theme.accent : Theme.subtext
                                    font.weight: Font.DemiBold
                                    text: modelData.percent > 0 ? (modelData.percent + "%") : Tr.t("Подключено")
                                }
                            }
                        }
                    }
                }

                Line {
                    icon: Icons.cursor
                    label: Tr.t("Основная кнопка мыши")
                    Seg {
                        options: [{ v: false, label: Tr.t("Левая") }, { v: true, label: Tr.t("Правая") }]
                        value: Store.niri.leftHanded
                        onPicked: v => Store.setNiri("leftHanded", v)
                    }
                }

                Line {
                    icon: Icons.cursor; label: Tr.t("Скорость указателя")
                    Seg {
                        options: [{ v: -0.5, label: "−2" }, { v: -0.25, label: "−1" }, { v: 0, label: Tr.t("Обычно") }, { v: 0.25, label: "+1" }, { v: 0.5, label: "+2" }]
                        value: Store.niri.mouseSpeed
                        onPicked: v => Store.setNiri("mouseSpeed", v)
                    }
                }

                Line {
                    icon: Icons.arrowDown; label: Tr.t("Обратная прокрутка мыши")
                    Switch { on: Store.niri.mouseNatural; onToggled: Store.setNiri("mouseNatural", !Store.niri.mouseNatural) }
                }

                Line {
                    off: !Sys.hasTouchpad
                    icon: Icons.laptop; label: Tr.t("Сенсорная панель: касание как щелчок")
                    Switch { on: Store.niri.tapClick; onToggled: Store.setNiri("tapClick", !Store.niri.tapClick) }
                }

                Line {
                    off: !Sys.hasTouchpad
                    icon: Icons.laptop; label: Tr.t("Сенсорная панель: обратная прокрутка")
                    Switch { on: Store.niri.touchNatural; onToggled: Store.setNiri("touchNatural", !Store.niri.touchNatural) }
                }
            }
        }

        // ---- Память и хранилище ----
        Flickable {
            visible: root.page === "storage"; property string pid: "storage"
            anchors.fill: parent
            clip: true
            contentHeight: storageCol.implicitHeight + 24
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: storageCol
                spacing: 8

                // Карточка диска
                Rectangle {
                    width: pages.width
                    height: 72
                    radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    Row {
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        FIcon { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 22; icon: Icons.hardDrive }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            WText { font.pixelSize: 14; font.weight: Font.DemiBold; text: Tr.t("Основной системный накопитель") }
                            WText { font.pixelSize: 12; color: Theme.subtext; text: root.pcDisk !== "" ? root.pcDisk : Tr.t("Файловая система Linux") }
                        }
                    }
                    Btn {
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        label: Tr.t("Проводник")
                        onClicked: Quickshell.execDetached(["nautilus"])
                    }
                }

                WText { topPadding: 4; font.pixelSize: 13; font.weight: Font.DemiBold; text: Tr.t("Управление памятью и компрессия") }

                Line {
                    icon: Icons.pulse
                    label: Tr.t("Сжатие оперативной памяти (ZRAM)")
                    hint: Tr.t("Алгоритм zstd: сжатие неактивных страниц в RAM без обращений к диску (2.5x-3x)")
                    Btn { label: Tr.t("Диспетчер задач"); onClicked: Ui.openTaskManager() }
                }

                Line {
                    icon: Icons.broom
                    label: Tr.t("Очистка старых версий (NixOS Garbage Collection)")
                    hint: Tr.t("Удаление неиспользуемых предыдущих поколений системы и освобождение места")
                    Btn { label: Tr.t("Очистить"); onClicked: Tools.runInTerminal("win11-pkg clean") }
                }

                Line {
                    icon: Icons.deleteIcon
                    label: Tr.t("Оптимизация базы пакетов (дедупликация)")
                    hint: Tr.t("Поиск одинаковых файлов и замена на жесткие ссылки (nix-store --optimise)")
                    Btn { label: Tr.t("Оптимизировать"); onClicked: Tools.runInTerminal("sudo nix-store --optimise") }
                }

                Line {
                    icon: Icons.broom
                    label: Tr.t("Временные файлы и кэш")
                    hint: Tr.t("Очистка пользовательского кэша и временных файлов")
                    Btn { label: Tr.t("Очистить кэш"); onClicked: Tools.runInTerminal("rm -rf ~/.cache/* /tmp/* 2>/dev/null; echo 'Кэш очищен!'") }
                }
            }
        }

        // ---- Состояние сети ----
        Column {
            visible: root.page === "network"; property string pid: "network"
            spacing: 6

            // Карточка сети
            Rectangle {
                width: pages.width
                height: 72
                radius: 6
                color: Theme.card
                border.color: Theme.border
                Row {
                    anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                    spacing: 16
                    FIcon { icon: Sys.netIcon; font.pixelSize: 30; anchors.verticalCenter: parent.verticalCenter; color: Sys.online ? Theme.accent : Theme.subtext }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        WText { font.pixelSize: 15; font.weight: Font.DemiBold; text: Sys.netText }
                        WText { font.pixelSize: 12; color: Theme.subtext; text: Sys.online ? Tr.t("Подключение установлено") : Tr.t("Без доступа к интернету") }
                    }
                }
                WText {
                    anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                    font.pixelSize: 12; color: Theme.subtext
                    text: Tr.t("Частная сеть")
                }
            }

            Line {
                icon: Sys.hasWifi ? Icons.wifi : Icons.ethernet
                label: Tr.t("Свойства сетевого адаптера")
                hint: Tr.t("Настройка IP-адреса, DNS, шлюза и профилей подключения")
                Btn { label: Tr.t("Настроить"); onClicked: Quickshell.execDetached(["nm-connection-editor"]) }
            }

            Line {
                icon: Icons.globe
                label: Tr.t("Обход блокировок (Zapret 2)")
                hint: Tr.t("Настройка стратегий обхода замедления YouTube и Discord")
                Btn { label: Tr.t("Параметры"); onClicked: root.page = "zapret" }
            }

            Line {
                icon: Icons.restart
                label: Tr.t("Сброс сети")
                hint: Tr.t("Перезапуск NetworkManager и сброс активных соединений")
                Btn {
                    label: Tr.t("Сбросить")
                    onClicked: Tools.runInTerminal("systemctl restart NetworkManager")
                }
            }
        }

        // ---- Восстановление ----
        Flickable {
            visible: root.page === "recovery"; property string pid: "recovery"
            anchors.fill: parent
            clip: true
            contentHeight: recCol.implicitHeight + 24
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: recCol
                spacing: 8

                // Информационная карточка
                Rectangle {
                    width: pages.width
                    height: 72
                    radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    Row {
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        FIcon { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 22; icon: Icons.history }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            WText { font.pixelSize: 14; font.weight: Font.DemiBold; text: Tr.t("Параметры восстановления") }
                            WText { font.pixelSize: 12; color: Theme.subtext; text: Tr.t("Устранение неполадок без потери личных данных и файлов") }
                        }
                    }
                }

                Line {
                    icon: Icons.tools
                    label: Tr.t("Починка системы + рабочего пространства")
                    hint: Tr.t("Полная проверка NixOS, служб, Niri и рабочего стола")
                    Btn {
                        label: Tr.t("Починить всё")
                        onClicked: Tools.runInTerminal("win11-recovery system")
                    }
                }

                Line {
                    icon: Icons.laptop
                    label: Tr.t("Только починить рабочее пространство")
                    hint: Tr.t("Восстановление конфигурации Niri, панелей и горячих клавиш")
                    Btn {
                        label: Tr.t("Починить рабочий стол")
                        onClicked: Tools.runInTerminal("win11-recovery workspace")
                    }
                }

                Line {
                    icon: Icons.restart
                    label: Tr.t("Сбросить параметры оболочки")
                    hint: Tr.t("Вернуть внешний вид и настройки рабочего стола к стандартным")
                    Btn {
                        label: Tr.t("Сбросить")
                        onClicked: { Store.reset(); path.text = ""; layouts.text = Store.niri.kbLayout; }
                    }
                }

                Line {
                    icon: Icons.info
                    label: Tr.t("Диагностический отчёт (Doctor)")
                    hint: Tr.t("Собрать сведения о сбоях и оборудовании в ~/win11-report.txt")
                    Btn {
                        label: Tr.t("Собрать отчёт")
                        onClicked: Tools.runInTerminal("win11-doctor")
                    }
                }
            }
        }

        // ---- О системе (в стиле Windows 11) ----
        Flickable {
            visible: root.page === "about"; property string pid: "about"
            anchors.fill: parent
            clip: true
            contentHeight: aboutCol.implicitHeight + 24
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: aboutCol
                spacing: 8

                // Карточка ПК
                Rectangle {
                    width: pages.width
                    height: 80
                    radius: 6
                    color: Theme.card
                    border.color: Theme.border
                    Row {
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        Rectangle {
                            width: 52; height: 38; radius: 4
                            color: Theme.hover
                            border.color: Theme.border
                            anchors.verticalCenter: parent.verticalCenter
                            Image { anchors.centerIn: parent; width: 24; height: 24; sourceSize: Qt.size(24, 24); source: Qt.resolvedUrl("assets/start-win11.svg") }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            WText { font.pixelSize: 15; font.weight: Font.DemiBold; text: root.pcName !== "" ? root.pcName : Config.userName + "-PC" }
                            WText { font.pixelSize: 11; color: Theme.subtext; text: root.pcModel !== "" ? root.pcModel : "MSI PRO H610M-B (MS-7D46)" }
                        }
                    }
                    Btn {
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        label: Tr.t("Копировать")
                        onClicked: {
                            const spec = Tr.t("Имя устройства") + ": " + root.pcName + "\n" +
                                         Tr.t("Процессор") + ": " + root.pcCpu + "\n" +
                                         Tr.t("Оперативная память") + ": " + root.pcMem + "\n" +
                                         Tr.t("Система") + ": " + root.pcOs + "\n" +
                                         Tr.t("Ядро системы") + ": " + root.pcKernel;
                            Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", spec]);
                        }
                    }
                }

                // Характеристики устройства
                WText { topPadding: 4; font.pixelSize: 13; font.weight: Font.DemiBold; text: Tr.t("Характеристики устройства") }

                Line {
                    icon: Icons.laptop
                    label: Tr.t("Имя устройства")
                    hint: root.pcName !== "" ? root.pcName : Config.userName + "-PC"
                }

                Line {
                    icon: Icons.pulse
                    label: Tr.t("Процессор")
                    hint: root.pcCpu !== "" ? root.pcCpu : Tr.t("Собираю сведения…")
                }

                Line {
                    icon: Icons.storage
                    label: Tr.t("Оперативная память")
                    hint: root.pcMem !== "" ? root.pcMem : Tr.t("Собираю сведения…")
                }

                Line {
                    icon: Icons.info
                    label: Tr.t("Тип системы")
                    hint: Tr.t("64-разрядная операционная система, процессор x64")
                }

                // Характеристики Windows
                WText { topPadding: 4; font.pixelSize: 13; font.weight: Font.DemiBold; text: Tr.t("Характеристики Windows") }

                Line {
                    icon: Icons.desktop
                    label: Tr.t("Выпуск")
                    hint: "Windows 11 Pro (NixOS Edition)"
                }

                Line {
                    icon: Icons.sync
                    label: Tr.t("Версия")
                    hint: "24H2 (" + (root.pcOs !== "" ? root.pcOs : "NixOS 2026") + ")"
                }

                Line {
                    icon: Icons.wrench
                    label: Tr.t("Ядро системы")
                    hint: root.pcKernel !== "" ? root.pcKernel : "Linux 6.18"
                }

                Line {
                    icon: Icons.tools
                    label: Tr.t("Графическая среда")
                    hint: "Niri Wayland Compositor + Quickshell Fluent UI"
                }
            }
        }
    }
}
