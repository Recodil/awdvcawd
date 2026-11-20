pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root
    property int live: 0     // сколько всплывающих уведомлений сейчас на экране
    readonly property var list: server.trackedNotifications
    readonly property int count: server.trackedNotifications.values.length

    // Название программы для заголовка уведомления: не имя файла, а понятное имя.
    readonly property var names: [
        ["nautilus", Tr.t("Проводник")], ["org.gnome.files", Tr.t("Проводник")], ["thunar", Tr.t("Проводник")], ["dolphin", Tr.t("Проводник")],
        ["cups", Tr.t("Диспетчер печати")], ["print", Tr.t("Диспетчер печати")], ["hplip", Tr.t("Диспетчер печати")], ["hp-", Tr.t("Диспетчер печати")],
        ["win11", Tr.t("Параметры")], ["settings", Tr.t("Параметры")], ["control-center", Tr.t("Параметры")],
        ["networkmanager", Tr.t("Сеть")], ["nm-applet", Tr.t("Сеть")], ["network", Tr.t("Сеть")],
        ["blueman", "Bluetooth"], ["bluetooth", "Bluetooth"],
        ["win11-taskmgr", Tr.t("Диспетчер задач")],
        ["polkit", Tr.t("Безопасность")], ["udisk", Tr.t("Съёмные устройства")], ["gvfs", Tr.t("Съёмные устройства")],
        ["upower", Tr.t("Питание")], ["power", Tr.t("Питание")], ["battery", Tr.t("Питание")],
        ["flatpak", Tr.t("Приложения")], ["niri", Tr.t("Снимок экрана")], ["kitty", Tr.t("Терминал")],
        ["notify-send", Tr.t("Система")]
    ]
    function entryOf(n) { return Config.entryFor(n.desktopEntry || "") || Config.entryFor(n.appName || ""); }
    function nameFor(n) {
        const raw = ((n.desktopEntry || "") + " " + (n.appName || "")).toLowerCase();
        for (let i = 0; i < names.length; i++) if (raw.indexOf(names[i][0]) >= 0) return names[i][1];
        const e = entryOf(n);
        if (e && e.name) return e.name;
        let s = (n.appName || "").replace(/\.desktop$/i, "");
        if (s.indexOf(".") >= 0) s = s.slice(s.lastIndexOf(".") + 1);   // org.telegram.desktop → desktop-имя без домена
        s = s.replace(/[-_]+/g, " ").trim();
        return s === "" ? Tr.t("Система") : s.charAt(0).toUpperCase() + s.slice(1);
    }
    function iconFor(n) {
        if (n.appIcon) return n.appIcon;
        const e = entryOf(n);
        return (e && e.icon) ? e.icon : "dialog-information";
    }

    // ---- "Не беспокоить" ----
    // Всплывать могут только системные уведомления, срочные и программы из списка Store.dndAllow.
    // Остальные не пропадают: они молча ложатся в центр уведомлений (щелчок по часам).
    readonly property var systemNames: [Tr.t("Система"), Tr.t("Сеть"), Tr.t("Питание"), Tr.t("Безопасность"), Tr.t("Параметры"), Tr.t("Диспетчер печати"),
                                        Tr.t("Съёмные устройства"), "Bluetooth", Tr.t("Снимок экрана")]
    property var seen: []        // кто присылал уведомления в этом сеансе - подсказки для списка исключений
    function isSystem(n) { return systemNames.indexOf(nameFor(n)) >= 0; }
    function isAllowedName(name) {
        const k = (name || "").toLowerCase();
        for (let i = 0; i < Store.dndAllow.length; i++) if (Store.dndAllow[i].toLowerCase() === k) return true;
        return false;
    }
    // программа разрешена, если в списке есть её название из уведомления или из "Пуска"
    function isAllowed(n) {
        if (isAllowedName(nameFor(n))) return true;
        const e = entryOf(n);
        return e !== null && e !== undefined && isAllowedName(e.name || "");
    }
    function quiet(n) {
        if (!Store.dnd) return false;
        if (n.urgency === NotificationUrgency.Critical) return false;
        return !isSystem(n) && !isAllowed(n);
    }
    function allow(name, on) {
        const list = Store.dndAllow.filter(x => x.toLowerCase() !== name.toLowerCase());
        if (on) list.push(name);
        Store.set("dndAllow", list);
    }
    function toggleDnd() { Store.set("dnd", !Store.dnd); }

    function clearAll() {
        const v = server.trackedNotifications.values;
        for (let i = v.length - 1; i >= 0; i--) v[i].dismiss();
    }

    NotificationServer {
        id: server
        bodySupported: true
        imageSupported: true
        onNotification: n => {
            n.tracked = true;
            const name = root.nameFor(n);
            if (root.seen.indexOf(name) < 0) root.seen = root.seen.concat([name]);
        }
    }
}
