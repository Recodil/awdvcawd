import QtQuick
import Quickshell
import Quickshell.Wayland

// Экран "Добро пожаловать" при входе и экраны выхода / перезагрузки / выключения.
PanelWindow {
    id: win
    readonly property bool shown: Ui.session !== ""
    property string mode: "boot"
    readonly property var labels: ({
        "boot": "", "welcome": Tr.t("Добро пожаловать"), "logout": Tr.t("Выход из системы"),
        "reboot": Tr.t("Перезагрузка"), "poweroff": Tr.t("Завершение работы")
    })

    Connections {
        target: Ui
        function onSessionChanged() { if (Ui.session !== "") win.mode = Ui.session; }
    }

    visible: shown || root.opacity > 0
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "win11-session"
    WlrLayershell.keyboardFocus: (shown && mode !== "boot" && mode !== "welcome")
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Item {
        id: root
        anchors.fill: parent
        opacity: win.shown ? 1 : 0
        Behavior on opacity {
            enabled: !Ui.skipFade
            // уход заставки входа - быстрый; экраны выхода и выключения появляются спокойнее
            NumberAnimation { duration: win.shown ? 300 : 180; easing.type: Easing.OutCubic }
        }

        Rectangle { anchors.fill: parent; color: "#0a1c3a" }
        // Размытый фон без шейдеров: картинка декодируется крошечной (это в десятки раз быстрее
        // и почти не занимает памяти) и растягивается со сглаживанием - получается то же размытие.
        Image {
            id: bg
            anchors.fill: parent
            source: (win.visible && width > 0 && Store.loaded) ? Store.wallpaperUrl : ""   // не держим картинку в памяти, пока экран скрыт
            sourceSize.width: 64
            smooth: true
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
        }
        Rectangle { anchors.fill: parent; color: "#66000000" }
        MouseArea { anchors.fill: parent; onClicked: if (win.mode === "welcome") Ui.session = "" }

        Column {
            anchors.centerIn: parent
            spacing: 24
            visible: win.mode !== "boot"
            scale: win.shown ? 1 : 1.06
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Avatar { anchors.horizontalCenter: parent.horizontalCenter; visible: win.mode === "welcome"; width: 140; height: 140 }
            ShadowText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: win.mode === "welcome"
                font.pixelSize: 28
                text: Config.userName
            }
            Spinner { anchors.horizontalCenter: parent.horizontalCenter }
            ShadowText {
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 20
                text: win.labels[win.mode] || ""
            }
        }
    }

    // "Добро пожаловать" не держит экран ради себя: заставка уходит, как только рабочий стол
    // готов (обои загружены), но не раньше 0,4 с - чтобы не мелькнуть, - и не позже 1,5 с.
    property bool minShown: false
    Timer { interval: 400; running: Ui.session === "welcome"; onTriggered: win.minShown = true }
    Timer { interval: 1500; running: Ui.session === "welcome"; onTriggered: Ui.session = "" }
    readonly property bool canLeave: Ui.session === "welcome" && minShown && Ui.wallReady
    // через callLater: менять Ui.session прямо отсюда нельзя - от него зависит само canLeave
    function leave() { if (Ui.session === "welcome") Ui.session = ""; }
    onCanLeaveChanged: if (canLeave) Qt.callLater(win.leave)
    Timer {
        interval: 450
        running: Ui.session === "logout" || Ui.session === "reboot" || Ui.session === "poweroff"
        onTriggered: {
            if (Ui.session === "logout")
                Quickshell.execDetached(["sh", "-c", "rm -f " + Config.welcomeFlag + "; exec " + Config.logoutCommand.join(" ")]);
            else
                Quickshell.execDetached(Ui.session === "reboot" ? Config.rebootCommand : Config.poweroffCommand);
        }
    }
}
