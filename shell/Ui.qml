pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

// Общее состояние: какое всплывающее окно открыто, блокировка, экраны входа/выхода.
Singleton {
    id: root
    property string flyout: ""        // "", "start", "quick", "calendar", "ctx"
    property var ctx: null            // контекстное меню значка: { appId, entry, windows, mode, x, y }
    property point barMenuPos: Qt.point(0, 0)
    function openCtx(info) { peek = null; ctx = info; flyout = "ctx"; }
    // окна программы при наведении на значок: { windows, entry, x, y }
    property var peek: null
    property bool peekHeld: false
    function showPeek(info) { peekClose.stop(); peekHeld = false; peek = info; }
    function leavePeek() { peekClose.restart(); }
    function holdPeek(on) { peekHeld = on; if (on) peekClose.stop(); else peekClose.restart(); }
    Timer { id: peekClose; interval: 600; onTriggered: if (!root.peekHeld) root.peek = null }
    function openBarMenu(x, y) { barMenuPos = Qt.point(x, y); flyout = "barmenu"; }
    property point trayPos: Qt.point(0, 0)
    property var trayItem: null       // значок, чьё меню показать; null - показать все значки
    function toggleTray(x, y) { trayItem = null; trayPos = Qt.point(x, y); toggle("tray"); }
    function openTrayMenu(item, x, y) { trayItem = item; trayPos = Qt.point(x, y); flyout = "tray"; }
    // Значки программ в трее. Значок сети от nm-applet прячем: сеть уже показана
    // рядом со звуком (а сам nm-applet остаётся работать - он спрашивает пароли Wi-Fi).
    // nm-applet называет себя по-разному в разных версиях, поэтому смотрим и на имя значка
    // (nm-device-wired, nm-signal-75, network-wired и т. п.).
    function isNetworkApplet(item) {
        const s = [item.id, item.title, item.tooltipTitle, item.icon].map(x => String(x || "")).join(" ").toLowerCase();
        return /nm-applet|nm_applet|networkmanager|network manager|\bnm-|network-(wired|wireless|offline|error|idle|transmit|receive|vpn|cellular)/.test(s);
    }
    readonly property var trayItems: {
        const v = SystemTray.items.values, out = [];
        for (let i = 0; i < v.length; i++) {
            if (!isNetworkApplet(v[i])) out.push(v[i]);
        }
        return out;
    }
    // системное сообщение (Notice.qml)
    property string noticeTitle: ""
    property string noticeText: ""
    property bool noticeCancel: false
    function showNotice(title, text, cancel) { noticeTitle = title; noticeText = text; noticeCancel = cancel; flyout = "notice"; }
    property bool taskView: false     // представление задач (Win+Tab)
    // Удержанная клавиша повторяет команду, и окно открывалось и тут же закрывалось ("через раз").
    // Повтор того же переключения быстрее, чем за 300 мс, пропускается.
    property var toggledAt: ({})
    function bounced(name) {
        const now = Date.now(), last = toggledAt[name] || 0;
        toggledAt[name] = now;
        return now - last < 300;
    }
    function toggleTaskView() { if (bounced("taskView")) return; flyout = ""; taskView = !taskView; }
    property string searchSeed: ""    // текст, с которым открыть "Поиск"
    function openSearch(text) { searchSeed = text || ""; flyout = "search"; }
    // "Параметры" и "Центр обновления" - отдельные окна, а не всплывающие панели
    property string settingsPage: "system"
    property bool settingsOpen: false
    property bool updatesOpen: false
    property bool taskmgrOpen: false
    function openTaskManager() { flyout = ""; taskmgrOpen = true; raise(Tr.t("Диспетчер задач")); }
    function openSettings(page) {
        if (page === "update") { openUpdates(); return; }
        if (page) settingsPage = page;
        flyout = "";
        settingsOpen = true;
        raise(Tr.t("Параметры"));
    }
    function openUpdates() { flyout = ""; updatesOpen = true; raise(Tr.t("Центр обновления Windows")); }
    // уже открытое окно выводится вперёд
    function raise(title) {
        const w = Niri.windows.find(x => x.app_id === "org.quickshell" && x.title === title);
        if (w) Niri.focusWindow(w);
    }
    property string session: "boot"   // "", "boot", "welcome", "logout", "reboot", "poweroff"
    property bool skipFade: false
    property bool locked: false
    readonly property date now: clock.date

    function toggle(name) { if (bounced(name)) return; flyout = (flyout === name) ? "" : name; }
    function close() { flyout = ""; }
    function lock() { flyout = ""; locked = true; }
    function endSession(kind) { flyout = ""; skipFade = false; session = kind; }
    function bootDone(isNew) {
        if (session !== "boot") return;
        if (isNew) { skipFade = false; session = "welcome"; }
        else { skipFade = true; session = ""; }
    }

    // Быстрый вход: сначала рисуются только обои и панель задач. Остальные окна оболочки
    // ("Пуск", поиск, календарь…) создаются в фоне сразу после того, как показан рабочий стол.
    property bool wallReady: false      // обои уже на экране
    property bool late: false           // можно создавать остальные окна
    onSessionChanged: if (session === "") lateTimer.start()
    Timer { id: lateTimer; interval: 150; onTriggered: root.late = true }
    Timer { interval: 4000; running: true; onTriggered: root.late = true }     // страховка
    // запрос открыть окно до того, как оно создано, - создаём немедленно
    onFlyoutChanged: if (flyout !== "") { late = true; peek = null; }
    onTaskViewChanged: if (taskView) late = true

    SystemClock { id: clock; precision: SystemClock.Minutes }
    // страховка: если проверка первого входа зависла, не держим экран закрытым
    Timer { interval: 3000; running: root.session === "boot"; onTriggered: root.bootDone(false) }
}
