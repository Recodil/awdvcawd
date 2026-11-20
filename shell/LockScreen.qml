import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam

// Экран блокировки: часы уезжают вверх, фон размывается, появляется поле пароля.
Scope {
    id: root
    property string password: ""
    property bool showLogin: false
    property bool busy: false
    property bool failed: false
    property bool unlocking: false
    signal clearInput()

    function tryUnlock() {
        if (password === "" || busy) return;
        busy = true; failed = false;
        pam.start();
    }

    Connections {
        target: Ui
        function onLockedChanged() {
            if (Ui.locked) { root.showLogin = false; root.unlocking = false; root.failed = false; root.clearInput(); }
        }
    }

    PamContext {
        id: pam
        configDirectory: "pam"
        config: "password.conf"
        onPamMessage: { if (pam.responseRequired) pam.respond(root.password); }
        onCompleted: result => {
            root.busy = false;
            root.clearInput();
            if (result === PamResult.Success) {
                root.unlocking = true;       // фон плавно "проявляется", затем снимаем блокировку
                root.showLogin = false;
                unlockTimer.start();
            } else {
                root.failed = true;
            }
        }
    }
    Timer { id: unlockTimer; interval: 420; onTriggered: Ui.locked = false }

    WlSessionLock {
        id: lock
        locked: Ui.locked

        WlSessionLockSurface {
            id: surface
            color: "black"
            property real reveal: root.showLogin ? 1 : 0
            Behavior on reveal { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

            Image {
                id: bg
                anchors.fill: parent
                source: width > 0 ? Store.lockUrl : ""
                sourceSize.width: Math.ceil(Math.max(width, height * 1.6))
                fillMode: Image.PreserveAspectCrop
            }
            MultiEffect { anchors.fill: parent; source: bg; blurEnabled: true; blur: 1; blurMax: 64; opacity: surface.reveal }
            Rectangle { anchors.fill: parent; color: "black"; opacity: 0.25 + 0.2 * surface.reveal }

            FocusScope {
                id: catcher
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (!root.showLogin && !root.unlocking) { root.showLogin = true; event.accepted = true; }
                }
                MouseArea { anchors.fill: parent; onClicked: if (!root.unlocking) root.showLogin = true }

                Connections {
                    target: root
                    function onShowLoginChanged() {
                        if (root.showLogin) input.forceActiveFocus(); else catcher.forceActiveFocus();
                    }
                    function onClearInput() { input.text = ""; }
                }

                // ---- часы ----
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.12 - surface.reveal * 160
                    opacity: root.unlocking ? 0 : 1 - surface.reveal
                    spacing: 4
                    ShadowText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.pixelSize: 120; font.weight: Font.DemiBold
                        text: Qt.formatDateTime(Ui.now, "HH:mm")
                    }
                    ShadowText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.pixelSize: 24
                        text: Ui.now.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM")
                    }
                }

                // ---- вход ----
                Column {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: (1 - surface.reveal) * 60
                    opacity: surface.reveal
                    visible: opacity > 0
                    spacing: 16

                    Avatar { anchors.horizontalCenter: parent.horizontalCenter; width: 160; height: 160 }
                    ShadowText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.pixelSize: 28
                        text: Config.userName
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 296; height: 36; radius: 4
                        color: "#aa1f1f1f"
                        border.color: "#55ffffff"
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 2; radius: 1
                            color: input.activeFocus ? "#60cdff" : "#99ffffff"
                        }
                        WText {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            visible: input.text === ""
                            color: "#ccffffff"
                            text: Tr.t("Пароль")
                        }
                        TextInput {
                            id: input
                            anchors { left: parent.left; right: eye.left; leftMargin: 12; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            clip: true
                            color: "white"
                            // любые символы сразу показываются точками; увидеть пароль можно кнопкой "глаз"
                            property bool reveal: false
                            echoMode: reveal ? TextInput.Normal : TextInput.Password
                            passwordCharacter: "\u25CF"
                            passwordMaskDelay: 0
                            inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                            font.family: Config.fontFamily
                            font.pixelSize: 14
                            enabled: !root.busy
                            onTextChanged: { root.password = text; if (text === "") reveal = false; }
                            onAccepted: root.tryUnlock()
                            Keys.onEscapePressed: root.showLogin = false
                        }
                        HoverButton {
                            id: eye
                            anchors { right: submit.left; rightMargin: 2; verticalCenter: parent.verticalCenter }
                            implicitWidth: 32; implicitHeight: 32
                            visible: input.text !== ""
                            onClicked: { input.reveal = !input.reveal; input.forceActiveFocus(); }
                            FIcon { anchors.centerIn: parent; icon: input.reveal ? Icons.eyeOff : Icons.eye; color: "white" }
                        }
                        HoverButton {
                            id: submit
                            anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
                            implicitWidth: 32; implicitHeight: 32
                            onClicked: root.tryUnlock()
                            FIcon { anchors.centerIn: parent; icon: Icons.arrowRight; color: "white"; visible: !root.busy }
                            Spinner { anchors.centerIn: parent; width: 18; height: 18; visible: root.busy }
                        }
                    }
                }
            }
        }
    }
}
