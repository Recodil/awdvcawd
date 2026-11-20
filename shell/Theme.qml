pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property bool dark: Store.dark
    function toggle() { Store.dark = !Store.dark; Store.save(); }

    // ---- темы оформления ----
    // Встроенные темы - ниже. Свои - файлы *.json в ~/.config/win11-shell/themes (образец создаёт
    // кнопка "Создать свою тему" в "Параметрах"). В теме можно задать любой из цветов для светлого
    // и тёмного режима; чего нет - берётся из стандартной темы. Формат:
    //   { "name": "Моя тема",
    //     "light": { "accent": "#c2410c", "taskbar": "#f5fff7ed", ... },
    //     "dark":  { "accent": "#fb923c", ... },
    //     "wallpaper": "/путь/к/обоям.jpg", "startIcon": "orb", "radius": 8 }
    // Цвета: #RRGGBB или #AARRGGBB (первые две цифры - прозрачность).
    readonly property var keys: ["taskbar", "flyout", "footer", "titlebar", "card", "border", "text", "subtext", "accent", "accentText", "logo"]
    readonly property var builtin: [
        { name: "Графит",
          light: { accent: "#4b5563", taskbar: "#f5e5e7eb", flyout: "#faf3f4f6", footer: "#e5e7eb", card: "#ffffff", border: "#cbd0d8" },
          dark: { accent: "#cbd5e1", accentText: "#111111", taskbar: "#f5111214", flyout: "#fa1a1c1f", footer: "#111214", card: "#26292e", border: "#383c43" } },
        { name: "Лес",
          light: { accent: "#15803d", taskbar: "#f5ecf7ee", flyout: "#faf2f8f3", footer: "#e2efe5", border: "#c5d9ca" },
          dark: { accent: "#4ade80", accentText: "#052e16", taskbar: "#f50f1a13", flyout: "#fa16231a", footer: "#0f1a13", card: "#1f3125", border: "#2e4636" } },
        { name: "Закат",
          light: { accent: "#c2410c", taskbar: "#f5fff3e8", flyout: "#fafff7f0", footer: "#fde8d7", border: "#ecd0b8" },
          dark: { accent: "#fb923c", accentText: "#2a1203", taskbar: "#f51f1410", flyout: "#fa291a14", footer: "#1f1410", card: "#38241b", border: "#4d3327" } },
        { name: "Сирень",
          light: { accent: "#7c3aed", taskbar: "#f5f3effc", flyout: "#faf7f4fd", footer: "#e9e2f8", border: "#d5c9ee" },
          dark: { accent: "#c4b5fd", accentText: "#1e1b4b", taskbar: "#f5151225", flyout: "#fa1c1830", footer: "#151225", card: "#2a2444", border: "#3d3560" } },
        { name: "Nord",
          light: { accent: "#5e81ac", taskbar: "#f5e5e9f0", flyout: "#faeceff4", footer: "#d8dee9", card: "#f8f9fb", border: "#c8d0de", text: "#2e3440", subtext: "#4c566a" },
          dark: { accent: "#88c0d0", accentText: "#2e3440", taskbar: "#f52e3440", flyout: "#fa3b4252", footer: "#2e3440", card: "#434c5e", border: "#4c566a", text: "#eceff4", subtext: "#d8dee9" } },
        { name: "Dracula",
          light: { accent: "#9b5de5", taskbar: "#f5f1effa", flyout: "#faf8f7fd", footer: "#e6e3f3", border: "#d2cde6" },
          dark: { accent: "#bd93f9", accentText: "#1e1f29", taskbar: "#f51e1f29", flyout: "#fa282a36", footer: "#1e1f29", card: "#343746", border: "#44475a", text: "#f8f8f2", subtext: "#c9cbe0" } }
    ]
    property var custom: []              // свои темы из папки
    property var errors: []              // файлы, которые не удалось прочитать
    readonly property var all: builtin.concat(custom)
    readonly property var current: {
        for (let i = 0; i < all.length; i++) if (all[i].name === Store.theme) return all[i];
        return null;
    }
    function ok(v) { return typeof v === "string" && /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v); }
    // цвет из текущей темы или стандартный
    function pick(key, std) {
        const t = current;
        if (!t) return std;
        const side = dark ? t.dark : t.light;
        if (side && ok(side[key])) return side[key];
        if (ok(t[key])) return t[key];          // общий для обоих режимов (например "accent")
        return std;
    }
    function use(name) {
        Store.set("theme", name);
        const t = current;
        if (!t) return;
        if (typeof t.wallpaper === "string" && t.wallpaper !== "") { Store.wallMode = "fixed"; Store.set("wallpaper", t.wallpaper.replace(/^~/, Config.home)); }
        if (typeof t.startIcon === "string" && t.startIcon !== "") Store.set("startIcon", t.startIcon.replace(/^~/, Config.home));
        if (typeof t.radius === "number") Store.setNiri("radius", Math.max(0, Math.min(20, Math.round(t.radius))));
    }
    readonly property string dir: Config.home + "/.config/win11-shell/themes"
    function reload() { reader.running = true; }
    // образец своей темы: копия текущих цветов, которую можно править
    function createSample() {
        const side = d => { const o = {}; for (let i = 0; i < keys.length; i++) o[keys[i]] = d[keys[i]]; return o; };
        const sample = {
            name: "Моя тема",
            light: side({ taskbar: "#f5eef3f9", flyout: "#faf3f3f3", footer: "#e9e9e9", card: "#fbfbfb", border: "#d4d4d4", text: "#1b1b1b", subtext: "#5d5d5d", accent: "#005fb8", accentText: "#ffffff", logo: "#0a7fe0" }),
            dark: side({ taskbar: "#f51c1c1c", flyout: "#fa242424", footer: "#1c1c1c", card: "#323232", border: "#3d3d3d", text: "#ffffff", subtext: "#c5c5c5", accent: "#60cdff", accentText: "#000000", logo: "#4cc2ff" }),
            wallpaper: "", startIcon: "", radius: 8
        };
        Quickshell.execDetached(["sh", "-c",
            "d=\"$1\"; mkdir -p \"$d\"; f=\"$d/my-theme.json\"; n=1; while [ -e \"$f\" ]; do n=$((n+1)); f=\"$d/my-theme-$n.json\"; done; " +
            "printf '%s\\n' \"$2\" > \"$f\"; " +
            "for e in gnome-text-editor gedit kate mousepad; do command -v $e >/dev/null 2>&1 && { setsid -f $e \"$f\" >/dev/null 2>&1; exit 0; }; done; " +
            "setsid -f kitty -e nano \"$f\" >/dev/null 2>&1",
            "sh", dir, JSON.stringify(sample, null, 2)]);
        later.restart();
    }
    function openDir() { Quickshell.execDetached(["sh", "-c", "mkdir -p \"$1\" && setsid -f xdg-open \"$1\" >/dev/null 2>&1", "sh", dir]); }
    Timer { id: later; interval: 1500; onTriggered: root.reload() }
    Process {
        id: reader
        running: true
        command: ["sh", "-c", "for f in \"$1\"/*.json; do [ -f \"$f\" ] || continue; printf '\\n@@%s\\n' \"$f\"; head -c 65536 \"$f\"; done", "sh", root.dir]
        stdout: StdioCollector {
            id: readerOut
            onStreamFinished: {
                const out = [], bad = [];
                const parts = readerOut.text.split("\n@@");
                for (let i = 1; i < parts.length; i++) {
                    const nl = parts[i].indexOf("\n");
                    const file = parts[i].slice(0, nl), body = parts[i].slice(nl + 1);
                    try {
                        const t = JSON.parse(body);
                        if (!t || typeof t !== "object") throw 0;
                        if (typeof t.name !== "string" || t.name === "") t.name = file.replace(/^.*\//, "").replace(/\.json$/, "");
                        if (root.builtin.some(b => b.name === t.name) || out.some(b => b.name === t.name)) t.name += " (своя)";
                        t.file = file;
                        out.push(t);
                    } catch (e) { bad.push(file.replace(/^.*\//, "")); }
                }
                root.custom = out; root.errors = bad;
            }
        }
    }

    readonly property color taskbar: pick("taskbar", dark ? "#f51c1c1c" : "#f5eef3f9")
    readonly property color flyout: pick("flyout", dark ? "#fa242424" : "#faf3f3f3")
    readonly property color footer: pick("footer", dark ? "#1c1c1c" : "#e9e9e9")
    readonly property color titlebar: pick("titlebar", footer)
    readonly property color card: pick("card", dark ? "#323232" : "#fbfbfb")
    readonly property color border: pick("border", dark ? "#3d3d3d" : "#d4d4d4")
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color pressed: dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color text: pick("text", dark ? "#ffffff" : "#1b1b1b")
    readonly property color subtext: pick("subtext", dark ? "#c5c5c5" : "#5d5d5d")
    readonly property color accent: pick("accent", dark ? "#60cdff" : "#005fb8")
    readonly property color accentText: pick("accentText", dark ? "#000000" : "#ffffff")
    readonly property color logo: pick("logo", dark ? "#4cc2ff" : "#0a7fe0")

    function apply() {
        const scheme = dark ? "prefer-dark" : "prefer-light";
        const gtk = dark ? "Fluent-Dark" : "Fluent-Light";
        Quickshell.execDetached(["sh", "-c",
            "dconf write /org/gnome/desktop/interface/color-scheme \"'" + scheme + "'\"; " +
            "dconf write /org/gnome/desktop/interface/gtk-theme \"'" + gtk + "'\"; " +
            "dconf write /org/gnome/desktop/wm/preferences/button-layout \"':minimize,maximize,close'\"; " +
            "for v in 3.0 4.0; do f=\"$HOME/.config/gtk-$v/settings.ini\"; mkdir -p \"${f%/*}\"; " +
            "grep -q '^\\[Settings\\]' \"$f\" 2>/dev/null || printf '[Settings]\\n' >> \"$f\"; " +
            "sed -i '/^gtk-decoration-layout/d' \"$f\"; " +
            "sed -i '/^\\[Settings\\]/a gtk-decoration-layout=:minimize,maximize,close' \"$f\"; done; " +
            "dconf write /org/gnome/desktop/interface/icon-theme \"'Fluent'\"; " +
            "dconf write /org/gnome/desktop/interface/cursor-theme \"'Bibata-Modern-Ice'\"; " +
            "dconf write /org/gnome/desktop/interface/font-name \"'" + Config.fontFamily + " 10'\""]);
    }
    onDarkChanged: apply()
    Component.onCompleted: apply()
}
