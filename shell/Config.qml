pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Все настройки оболочки - в этом файле.
Singleton {
    id: root

    // Segoe UI несвободный. Если скопируете его из Windows в ~/.local/share/fonts,
    // поставьте здесь "Segoe UI Variable" или "Segoe UI".
    property string fontFamily: "Inter"
    property bool darkByDefault: false
    property bool welcomeAnimation: true
    property url wallpaper: Qt.resolvedUrl("assets/wallpaper.jpg")

    // Закреплённые на панели задач и в "Пуске" (имена .desktop-файлов без расширения).
    // Показываются только установленные.
    property var pinned: [
        "org.gnome.Nautilus", "org.kde.dolphin", "thunar",
        "firefox", "chromium-browser",
        "kitty", "Alacritty", "foot", "org.wezfurlong.wezterm",
        "vlc", "discord", "win11-store", "win11-taskmgr", "code", "org.telegram.desktop", "steam"
    ]

    readonly property string userName: Quickshell.env("USER") || "user"
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string welcomeFlag: "\"$XDG_RUNTIME_DIR/win11-shell-welcomed\""

    property var logoutCommand: ["niri", "msg", "action", "quit", "--skip-confirmation"]
    property var rebootCommand: ["systemctl", "reboot"]
    property var poweroffCommand: ["systemctl", "poweroff"]
    property var suspendCommand: ["systemctl", "suspend"]
    property var hibernateCommand: ["systemctl", "hibernate"]
    // Ctrl+Shift+Esc и пункт в меню панели задач
    property var taskManagerCommand: ["qs", "-p", "/etc/win11-shell", "ipc", "call", "shell", "taskmgr"]
    property var niriConfigCommand: ["kitty", "-e", "nano", Quickshell.env("HOME") + "/.config/niri/config.kdl"]

    // Окна самой оболочки ("Параметры", "Центр обновления") для панели задач - обычные приложения
    // со своими значками. Все они принадлежат одному процессу, поэтому различаются по заголовку.
    // окна самой оболочки узнаются по заголовку, а он зависит от языка
    readonly property var shellApps: {
        const m = {};
        m[Tr.t("Параметры")] = "win11-settings";
        m[Tr.t("Центр обновления Windows")] = "win11-updates";
        m[Tr.t("Диспетчер задач")] = "win11-taskmgr";
        return m;
    }
    readonly property var shellIcons: ({ "win11-settings": "assets/app-settings.svg", "win11-updates": "assets/app-updates.svg", "win11-taskmgr": "assets/app-taskmgr.svg" })
    // Flatpak exports its own application icons under the hicolor theme.
    // Prefer those over a desktop theme's branded-icon substitutions.
    property var flatpakIcons: ({})
    Process {
        id: flatpakIconReader
        command: ["sh", "-c", "for root in \"${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share/icons/hicolor\" /var/lib/flatpak/exports/share/icons/hicolor; do for size in 128x128 256x256 scalable 64x64 48x48; do d=\"$root/$size/apps\"; [ -d \"$d\" ] || continue; find \"$d\" -maxdepth 1 \\( -type f -o -type l \\) \\( -name '*.png' -o -name '*.svg' \\) -print; done; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const icons = {};
                text.split("\n").forEach(path => {
                    if (!path) return;
                    const file = path.slice(path.lastIndexOf("/") + 1);
                    const id = file.replace(/\.(png|svg)$/i, "").toLowerCase();
                    if (!icons[id]) icons[id] = "file://" + encodeURI(path);
                });
                root.flatpakIcons = icons;
            }
        }
    }
    Component.onCompleted: flatpakIconReader.running = true
    Timer { interval: 60000; repeat: true; running: true; onTriggered: if (!flatpakIconReader.running) flatpakIconReader.running = true }
    function appIcon(entry, appId) {
        const icon = entry && entry.icon ? entry.icon : "";
        const id = (appId || "").replace(/\.desktop$/i, "").toLowerCase();
        const name = icon.toLowerCase();
        return flatpakIcons[id] || flatpakIcons[name] || iconUrl(icon || appId);
    }
    function appIdOf(win) {
        if (!win) return "";
        if (win.app_id === "org.quickshell" && shellApps[win.title]) return shellApps[win.title];
        return win.app_id || "";
    }
    function iconUrl(name) {
        if (shellIcons[name]) return Qt.resolvedUrl(shellIcons[name]);
        if (name && name.startsWith("file://")) return name;
        if (name && name.startsWith("/")) return "file://" + name;
        return Quickshell.iconPath(name || "", "application-x-executable");
    }

    function entryFor(appId) {
        if (!appId) return null;
        let e = DesktopEntries.byId(appId);
        if (!e && typeof DesktopEntries.heuristicLookup === "function")
            e = DesktopEntries.heuristicLookup(appId);
        return e || null;
    }
}
