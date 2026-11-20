pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Сохраняемые настройки: ~/.config/win11-shell/settings.json
Singleton {
    id: root
    property bool loaded: false
    property var pinned: Config.pinned         // закреплено в "Пуске"
    property var barPinned: Config.pinned
    property var barOrder: []      // закреплено на панели задач
    property bool updIcon: true                // значок центра обновления на панели задач
    property bool dark: Config.darkByDefault
    property string barEdge: "bottom"    // "bottom", "top", "left", "right"
    property string barAlign: "left"     // "left" (как в Windows 10) или "center"
    property string wallpaper: ""        // путь к своей картинке; пусто - стандартные обои
    property bool welcome: Config.welcomeAnimation
    property bool autoLock: true         // блокировать экран после 10 минут простоя
    // Смена обоев: "fixed" - одна картинка, "day" / "minute" - по очереди из папки wallDir,
    // "web" - фотография дня из интернета (раз в день)
    property string wallMode: "fixed"
    property string wallDir: ""          // пусто - ~/Pictures/Wallpapers
    property string wallAuto: ""         // картинка, выбранная сменой обоев
    property string wallKey: ""          // за какой день / минуту она выбрана
    // Экран блокировки: "same" - как рабочий стол, "own" - своя картинка, "web" - фотография дня,
    // "folder" - по очереди из папки с обоями, "default" - стандартная
    property string lockMode: "same"
    property string lockWallpaper: ""
    property string lockAuto: ""         // картинка, выбранная для режимов web и folder
    readonly property url lockUrl: lockMode === "own" && lockWallpaper !== "" ? "file://" + lockWallpaper
                                 : (lockMode === "web" || lockMode === "folder") && lockAuto !== "" ? "file://" + lockAuto
                                 : lockMode === "default" ? Config.wallpaper : wallpaperUrl
    readonly property url wallpaperUrl: (wallMode !== "fixed" && wallAuto !== "") ? "file://" + wallAuto
                                      : wallpaper !== "" ? "file://" + wallpaper : Config.wallpaper

    property string lang: ""             // язык программ: "" - системный, иначе ru_RU.UTF-8 / en_US.UTF-8
    function setLang(v) {
        lang = v; save();
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$HOME/.config/win11-shell\" && printf '%s\\n' \"$1\" > \"$HOME/.config/win11-shell/lang\"", "sh", v]);
    }
    // Значок кнопки "Пуск": имя встроенного (nixos, win11, win10, orb, grid, tux) или путь к своей картинке (png, svg, jpg)
    property string startIcon: "nixos"
    readonly property var startIcons: [
        { id: "nixos", label: "NixOS" }, { id: "win11", label: "Windows 11" }, { id: "win10", label: "Windows 10" },
        { id: "orb", label: Tr.t("Шар") }, { id: "grid", label: Tr.t("Сетка") }, { id: "tux", label: Tr.t("Пингвин") }
    ]
    readonly property bool startIconCustom: startIcon.indexOf("/") >= 0
    readonly property url startIconUrl: startIconCustom ? "file://" + startIcon
                                      : Qt.resolvedUrl("assets/" + (startIcon === "nixos" || startIcon === "" ? "nixos" : "start-" + startIcon) + ".svg")
    property string theme: ""            // тема оформления: "" - стандартная, иначе имя встроенной или своей темы (см. Theme.qml)
    property bool dnd: false             // "Не беспокоить": уведомления не всплывают, а сразу уходят в центр уведомлений
    property var dndAllow: []            // программы, которым можно всплывать и при "Не беспокоить" (названия, как в заголовке уведомления)
    property bool minAnim: true          // плавное сворачивание и разворачивание окон
    property var runHistory: []          // прежние команды окна "Выполнить"
    property int avatarRev: 0            // растёт при смене аватарки - картинки перечитываются
    property int nightTemp: 4000         // ночной свет: цветовая температура, К (меньше - теплее)
    property bool nightAuto: false       // включать по расписанию
    property string nightFrom: "21:00"
    property string nightTo: "07:00"
    property bool showSearch: true       // кнопка поиска на панели задач
    property bool showTaskView: true     // кнопка представления задач

    // Параметры niri, которыми управляет окно "Параметры".
    // Записываются в ~/.config/niri/win11-settings.kdl (подключён из config.kdl).
    readonly property var niriDefaults: ({
        kbLayout: "us,ru", kbToggle: "grp:win_space_toggle,grp:alt_shift_toggle", kbVer: 2, repeatDelay: 600, repeatRate: 25, numlock: false,
        mouseSpeed: 0, mouseNatural: false, leftHanded: false, focusFollows: false,
        tapClick: true, touchNatural: true,
        animations: true, animSlow: 1, radius: 8, shadows: true
    })
    property var niri: niriDefaults
    function setNiri(key, value) {
        const c = Object.assign({}, niri);
        c[key] = value;
        niri = c;
        save();
        writeNiri();
    }
    function niriKdl() {
        const spd = isNaN(Number(n.mouseSpeed)) ? 0.0 : Math.max(-1.0, Math.min(1.0, Number(n.mouseSpeed)));
        const repD = isNaN(Number(n.repeatDelay)) ? 600 : Math.max(100, Math.min(2000, Math.round(Number(n.repeatDelay))));
        const repR = isNaN(Number(n.repeatRate)) ? 25 : Math.max(1, Math.min(100, Math.round(Number(n.repeatRate))));
        const slow = isNaN(Number(n.animSlow)) ? 1.0 : Math.max(0.1, Math.min(5.0, Number(n.animSlow)));
        const rad = isNaN(Number(n.radius)) ? 8 : Math.max(0, Math.min(32, Math.round(Number(n.radius))));

        const layout = /^[a-z0-9_,()-]+$/.test(n.kbLayout) ? n.kbLayout : "us,ru";
        const toggle = /^[a-z0-9_:,]*$/.test(n.kbToggle || "") ? n.kbToggle : "grp:win_space_toggle";
        const L = [];
        L.push("// Этот файл создаёт окно \"Параметры\" (Win+I). Вручную не править - будет перезаписан.");
        L.push("input {");
        L.push("    keyboard {");
        L.push("        xkb {");
        // "ru(phonetic)" → раскладка ru, вариант phonetic; варианты идут отдельной строкой в том же порядке
        const codes = [], vars = [];
        layout.split(",").filter(x => x !== "").forEach(item => {
            const m = /^([a-z0-9_-]+)(?:\(([a-z0-9_-]+)\))?$/.exec(item);
            if (m) { codes.push(m[1]); vars.push(m[2] || ""); }
        });
        if (codes.length === 0) { codes.push("us", "ru"); vars.push("", ""); }
        L.push("            layout \"" + codes.join(",") + "\"");
        if (vars.some(v => v !== "")) L.push("            variant \"" + vars.join(",") + "\"");
        if (toggle) L.push("            options \"" + toggle + "\"");
        L.push("        }");
        L.push("        repeat-delay " + repD);
        L.push("        repeat-rate " + repR);
        if (n.numlock) L.push("        numlock");
        L.push("    }");
        L.push("    mouse {");
        L.push("        accel-speed " + spd.toFixed(2));
        if (n.mouseNatural) L.push("        natural-scroll");
        if (n.leftHanded) L.push("        left-handed");
        L.push("    }");
        L.push("    touchpad {");
        if (n.tapClick) L.push("        tap");
        if (n.touchNatural) L.push("        natural-scroll");
        L.push("    }");
        if (n.focusFollows) L.push("    focus-follows-mouse");
        L.push("}");
        L.push("animations {");
        L.push(n.animations ? "    slowdown " + slow.toFixed(2) : "    off");
        L.push("}");
        L.push("layout {");
        L.push("    shadow {");
        L.push(n.shadows ? "        on" : "        off");
        L.push("    }");
        L.push("}");
        L.push("window-rule {");
        L.push("    geometry-corner-radius " + rad);
        L.push("    clip-to-geometry true");
        L.push("}");
        return L.join("\n") + "\n";
    }
    function writeNiri() {
        if (!loaded) return;
        Quickshell.execDetached(["sh", "-c",
            "f=\"$HOME/.config/niri/win11-settings.kdl\"; mkdir -p \"${f%/*}\"; cp -f \"$f\" \"$f.prev\" 2>/dev/null; " +
            "printf '%s' \"$1\" > \"$f.tmp\" && mv -f \"$f.tmp\" \"$f\"; " +
            "if niri validate >/dev/null 2>&1; then niri msg action load-config-file 2>/dev/null || true; " +
            "elif [ -s \"$f.prev\" ]; then cp -f \"$f.prev\" \"$f\" && niri msg action load-config-file 2>/dev/null || true; fi",
            "sh", niriKdl()]);
    }

    function set(key, value) { root[key] = value; save(); }
    function reset() {
        pinned = Config.pinned; barPinned = Config.pinned; updIcon = true; dark = Config.darkByDefault; barEdge = "bottom"; barAlign = "left";
        wallpaper = ""; welcome = Config.welcomeAnimation; autoLock = true;
        wallMode = "fixed"; wallDir = ""; wallAuto = ""; wallKey = "";
        lockMode = "same"; lockWallpaper = ""; lockAuto = "";
        showSearch = true; showTaskView = true; niri = niriDefaults;
        nightTemp = 4000; nightAuto = false; nightFrom = "21:00"; nightTo = "07:00"; dnd = false; dndAllow = []; minAnim = true; startIcon = "nixos"; theme = "";
        save();
        writeNiri();
    }

    function setBar(edge, align) {
        if (edge) barEdge = edge;
        if (align) barAlign = align;
        save();
    }

    // закрепление: "Пуск" и панель задач ведут отдельные списки
    function indexIn(list, id) {
        const k = (id || "").toLowerCase();
        for (let i = 0; i < list.length; i++) if (list[i].toLowerCase() === k) return i;
        return -1;
    }
    function without(list, id) {
        const copy = list.slice();
        copy.splice(indexIn(list, id), 1);
        return copy;
    }
    function isPinned(id) { return indexIn(pinned, id) >= 0; }
    function pin(id) { if (id && !isPinned(id)) { pinned = pinned.concat([id]); save(); } }
    function unpin(id) { if (isPinned(id)) { pinned = without(pinned, id); save(); } }
    function isBarPinned(id) { return indexIn(barPinned, id) >= 0; }
    function pinBar(id) { if (id && !isBarPinned(id)) { barPinned = barPinned.concat([id]); save(); } }
    function unpinBar(id) { if (isBarPinned(id)) { barPinned = without(barPinned, id); save(); }

    function setBarOrder(keys) {
        barOrder = keys.slice();
        const newPinned = [];
        for (let i = 0; i < keys.length; i++) {
            for (let j = 0; j < barPinned.length; j++) {
                if (barPinned[j].toLowerCase() === keys[i].toLowerCase()) {
                    newPinned.push(barPinned[j]);
                    break;
                }
            }
        }
        for (let j = 0; j < barPinned.length; j++) {
            let found = false;
            for (let i = 0; i < newPinned.length; i++) {
                if (newPinned[i].toLowerCase() === barPinned[j].toLowerCase()) { found = true; break; }
            }
            if (!found) newPinned.push(barPinned[j]);
        }
        barPinned = newPinned;
        save();
    } }
    function save() {
        if (!loaded) return;
        Quickshell.execDetached(["sh", "-c",
            "d=\"$HOME/.config/win11-shell\"; mkdir -p \"$d\"; cp -f \"$d/settings.json\" \"$d/settings.json.bak\" 2>/dev/null; " +
            "printf '%s' \"$1\" > \"$d/settings.json.tmp\" && mv -f \"$d/settings.json.tmp\" \"$d/settings.json\"",
            "sh", JSON.stringify({ pinned: pinned, barPinned: barPinned, barOrder: barOrder, updIcon: updIcon, dark: dark, barEdge: barEdge, barAlign: barAlign,
                                   wallpaper: wallpaper, welcome: welcome, autoLock: autoLock,
                                   lockMode: lockMode, lockWallpaper: lockWallpaper, lockAuto: lockAuto,
                                   showSearch: showSearch, showTaskView: showTaskView, niri: niri,
                                   nightTemp: nightTemp, nightAuto: nightAuto, nightFrom: nightFrom, nightTo: nightTo,
                                   lang: lang, runHistory: runHistory, dnd: dnd, dndAllow: dndAllow, minAnim: minAnim, startIcon: startIcon, theme: theme, wallMode: wallMode, wallDir: wallDir, wallAuto: wallAuto, wallKey: wallKey })]);
    }

    Process {
        running: true
        command: ["sh", "-c", "cat \"$HOME/.config/win11-shell/settings.json\" 2>/dev/null"]
        stdout: StdioCollector {
            id: saved
            onStreamFinished: {
                try {
                    const d = JSON.parse(saved.text);
                    if (Array.isArray(d.pinned)) root.pinned = d.pinned;
                    // раньше список был общим: панель задач наследует его
                    if (Array.isArray(d.barPinned)) root.barPinned = d.barPinned;
                    if (Array.isArray(d.barOrder)) root.barOrder = d.barOrder;
                    else if (Array.isArray(d.pinned)) root.barPinned = d.pinned;
                    if (typeof d.updIcon === "boolean") root.updIcon = d.updIcon;
                    if (typeof d.dark === "boolean") root.dark = d.dark;
                    if (["bottom", "top", "left", "right"].indexOf(d.barEdge) >= 0) root.barEdge = d.barEdge;
                    if (["left", "center"].indexOf(d.barAlign) >= 0) root.barAlign = d.barAlign;
                    if (typeof d.wallpaper === "string") root.wallpaper = d.wallpaper;
                    if (typeof d.welcome === "boolean") root.welcome = d.welcome;
                    if (typeof d.autoLock === "boolean") root.autoLock = d.autoLock;
                    if (typeof d.showSearch === "boolean") root.showSearch = d.showSearch;
                    if (typeof d.nightTemp === "number") root.nightTemp = Math.max(1500, Math.min(6500, d.nightTemp));
                    if (typeof d.nightAuto === "boolean") root.nightAuto = d.nightAuto;
                    if (typeof d.nightFrom === "string") root.nightFrom = d.nightFrom;
                    if (typeof d.nightTo === "string") root.nightTo = d.nightTo;
                    if (["fixed", "day", "minute", "web"].indexOf(d.wallMode) >= 0) root.wallMode = d.wallMode;
                    if (typeof d.wallDir === "string") root.wallDir = d.wallDir;
                    if (["same", "own", "web", "folder", "default"].indexOf(d.lockMode) >= 0) root.lockMode = d.lockMode;
                    if (typeof d.lockWallpaper === "string") root.lockWallpaper = d.lockWallpaper;
                    if (typeof d.lockAuto === "string") root.lockAuto = d.lockAuto;
                    if (typeof d.wallAuto === "string") root.wallAuto = d.wallAuto;
                    if (typeof d.wallKey === "string") root.wallKey = d.wallKey;
                    if (typeof d.showTaskView === "boolean") root.showTaskView = d.showTaskView;
                    if (typeof d.lang === "string") root.lang = d.lang;
                    if (typeof d.dnd === "boolean") root.dnd = d.dnd;
                    if (typeof d.startIcon === "string" && /^[A-Za-z0-9_\/. ~()А-Яа-яЁё-]+$/.test(d.startIcon)) root.startIcon = d.startIcon;
                    if (typeof d.theme === "string") root.theme = d.theme;
                    if (typeof d.minAnim === "boolean") root.minAnim = d.minAnim;
                    if (Array.isArray(d.dndAllow)) root.dndAllow = d.dndAllow.filter(x => typeof x === "string").slice(0, 60);
                    if (Array.isArray(d.runHistory)) root.runHistory = d.runHistory.filter(x => typeof x === "string").slice(0, 15);
                    if (d.niri && typeof d.niri === "object") {
                        const old = !d.niri.kbVer;
                        root.niri = Object.assign({}, root.niriDefaults, d.niri, { kbVer: 2 });
                        // раньше способ был один; к Win+Пробел добавляем Alt+Shift
                        if (old && d.niri.kbToggle === "grp:win_space_toggle") {
                            root.niri = Object.assign({}, root.niri, { kbToggle: "grp:win_space_toggle,grp:alt_shift_toggle" });
                            root.loaded = true; root.save(); root.writeNiri();
                        }
                    }
                } catch (e) {}
                root.loaded = true;
            }
        }
    }
}
