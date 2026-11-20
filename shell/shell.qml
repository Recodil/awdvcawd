import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Variants {
        model: Quickshell.screens
        Wallpaper {
            required property var modelData
            screen: modelData
        }
    }
    Variants {
        model: Quickshell.screens
        Taskbar {
            required property var modelData
            screen: modelData
        }
    }

    // Окна, которые не нужны в первую секунду, создаются в фоне после появления рабочего стола
    // (Ui.late) - вход получается быстрее. Если окно запросили раньше, оно создаётся сразу.
    LazyLoader { loading: Ui.late; StartMenu {} }
    LazyLoader { loading: Ui.late; QuickSettings {} }
    LazyLoader { loading: Ui.late; CalendarFlyout {} }
    LazyLoader { loading: Ui.late; TaskMenu {} }
    LazyLoader { loading: Ui.late; BarMenu {} }
    LazyLoader { loading: Ui.late; Search {} }
    LazyLoader { loading: Ui.late; Run {} }
    LazyLoader { loading: Ui.late; Notice {} }
    LazyLoader { loading: Ui.late; Hub {} }
    LazyLoader { loading: Ui.late; TrayMenu {} }
    LazyLoader { loading: Ui.late; Desktops {} }
    // "Параметры" - самое большое окно оболочки. Оно создаётся при открытии
    // и выгружается из памяти через минуту после закрытия.
    Scope {
        id: lazySettings
        readonly property bool want: Ui.settingsOpen
        onWantChanged: if (want) settingsKeep.stop(); else settingsKeep.restart()
        Timer { id: settingsKeep; interval: 60000 }
        LazyLoader {
            active: lazySettings.want || settingsKeep.running
            Settings {}
        }
    }
    LazyLoader { active: Ui.updatesOpen; UpdateCenter {} }
    LazyLoader { active: Ui.taskmgrOpen; TaskManager {} }
    Osd {}
    LazyLoader { active: Ui.peek !== null; Peek {} }
    Toasts {}
    SessionOverlay {}
    LockScreen {}

    // "Добро пожаловать" показываем только при первом запуске за сеанс, а не при перезагрузке конфига
    Process {
        running: true
        command: ["sh", "-c", "f=" + Config.welcomeFlag + "; if [ -e \"$f\" ]; then echo old; else touch \"$f\"; echo new; fi"]
        stdout: StdioCollector {
            id: firstRun
            onStreamFinished: Ui.bootDone(firstRun.text.trim() === "new" && Store.welcome)
        }
    }

    // Управление с клавиатуры: qs -p /etc/win11-shell ipc call shell <команда>
    IpcHandler {
        target: "shell"
        function start(): void { Ui.taskView = false; Ui.toggle("start"); }
        function search(): void { if (Ui.flyout === "search") Ui.close(); else Ui.openSearch(""); }
        function restoreAll(): void { Niri.restoreAll(); }
        function quick(): void { Ui.toggle("quick"); }
        function calendar(): void { Ui.toggle("calendar"); }
        function lock(): void { Ui.lock(); }
        function logout(): void { Ui.endSession("logout"); }
        function poweroff(): void { Ui.endSession("poweroff"); }
        function dark(): void { Theme.toggle(); }
        function settings(): void { Ui.openSettings(""); }
        function updates(): void { Ui.openUpdates(); }
        function taskmgr(): void { Ui.openTaskManager(); }
        function updatesCheck(): void { Updates.check(); }
        function updatesDone(): void { Updates.jobDone(); }
        function idleLock(): void { if (Store.autoLock) Ui.lock(); }
        function overview(): void { Niri.toggleOverview(); }
        function run(): void { Ui.toggle("run"); }
        function hub(): void { Ui.taskView = false; Ui.toggle("hub"); }
        function dnd(): void { Notifs.toggleDnd(); }
        function reboot(): void { Ui.endSession("reboot"); }
        function notice(title: string, text: string, cancel: string): void { Ui.showNotice(title, text, cancel === "1"); }
        function noticeClose(): void { if (Ui.flyout === "notice") Ui.close(); }
        function updateFound(): void { Updates.check(); Ui.openUpdates(); }
        function desktopNext(): void { Niri.stepDesktop(1); }
        function desktopPrev(): void { Niri.stepDesktop(-1); }
        function desktopNew(): void { Niri.newDesktop(); }
        function minimize(): void { Niri.minimizeFocused(); }
        function showDesktop(): void { Niri.showDesktop(); }
    }
}
