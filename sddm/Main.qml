import QtQuick
import QtQuick.Effects

// Экран входа SDDM в стиле Windows 11: часы → клик/клавиша → размытие и поле пароля.
Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "black"

    property bool showLogin: false
    property bool busy: false
    property bool failed: false
    property bool done: false
    property real reveal: showLogin ? 1 : 0
    property int userIndex: Math.max(0, userModel.lastIndex)
    property int sessionIndex: Math.max(0, sessionModel.lastIndex)
    property date now: new Date()
    readonly property string fontName: config.font || "Inter"
    readonly property string userName: {
        users.count;
        const it = users.itemAt(userIndex);
        return it ? it.name : (userModel.lastUser || "");
    }
    readonly property string userLabel: {
        users.count;
        const it = users.itemAt(userIndex);
        return it ? (it.realName || it.name) : userName;
    }
    readonly property string sessionName: {
        sessions.count;
        const it = sessions.itemAt(sessionIndex);
        return it ? it.name : "";
    }

    Behavior on reveal { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    Timer { interval: 10000; running: true; repeat: true; onTriggered: root.now = new Date() }
    FontLoader { id: icons; source: Qt.resolvedUrl("icons.ttf") }

    // имена пользователей и сеансов из моделей SDDM
    Item {
        visible: false
        Repeater { id: users; model: userModel; Item { property string name: model.name; property string realName: model.realName; property string icon: model.icon || "" } }
        Repeater { id: sessions; model: sessionModel; Item { property string name: model.name } }
    }

    // аватарка: сначала выбранная в "Параметрах", затем та, что знает SDDM
    function faceOf(name) { return name ? "file:///var/lib/win11-shell/faces/" + name : ""; }
    function pickUser(i) {
        if (i === userIndex) return;
        userIndex = i; failed = false; password.text = "";
        showLogin = true; password.forceActiveFocus();
    }

    component Face: Item {
        id: face
        property string user: ""
        property string fallback: ""          // значок из SDDM
        readonly property bool ready: pic.status === Image.Ready
        Rectangle {
            anchors.fill: parent; radius: width / 2
            visible: !face.ready
            color: "#33ffffff"
            Text { anchors.centerIn: parent; font.family: icons.name; font.pixelSize: face.width * 0.5; color: "white"; text: "\uf5bd" }
        }
        Image {
            id: pic
            anchors.fill: parent
            visible: false
            cache: false
            source: root.faceOf(face.user)
            sourceSize.width: Math.max(64, face.width * 2); sourceSize.height: Math.max(64, face.width * 2)
            fillMode: Image.PreserveAspectCrop
            // своей картинки нет - пробуем значок SDDM (один раз)
            onStatusChanged: if (status === Image.Error && face.fallback !== "" && source.toString() !== face.fallback) source = face.fallback
        }
        Rectangle { id: faceMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
        MultiEffect { anchors.fill: parent; visible: face.ready; source: pic; maskEnabled: true; maskSource: faceMask }
    }

    // белый текст поверх обоев - с тёмной обводкой, чтобы читался и на светлой картинке
    // (обводка, а не эффект тени: она рисуется при любом способе отрисовки)
    component Sh: Text {
        color: "white"
        font.family: root.fontName
        style: Text.Outline
        styleColor: "#8c000000"
    }

    function login() {
        if (busy || userName === "") return;
        busy = true; failed = false;
        sddm.login(userName, password.text, sessionIndex);
    }

    Connections {
        target: sddm
        function onLoginFailed() { root.busy = false; root.failed = true; password.text = ""; password.forceActiveFocus(); }
        function onLoginSucceeded() { root.done = true; }
    }

    Image {
        id: bg
        anchors.fill: parent
        source: Qt.resolvedUrl(config.background || "wallpaper.jpg")
        sourceSize.width: Math.ceil(Math.max(root.width, root.height * 1.6))
        fillMode: Image.PreserveAspectCrop
    }
    MultiEffect { anchors.fill: parent; source: bg; blurEnabled: true; blur: 1; blurMax: 64; opacity: root.reveal }
    Rectangle { anchors.fill: parent; color: "black"; opacity: 0.25 + 0.2 * root.reveal }

    FocusScope {
        id: catcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (!root.showLogin) { root.showLogin = true; password.forceActiveFocus(); event.accepted = true; }
        }
        MouseArea { anchors.fill: parent; onClicked: { root.showLogin = true; password.forceActiveFocus(); } }

        // ---- часы ----
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.12 - root.reveal * 160
            opacity: 1 - root.reveal
            spacing: 4
            Sh {
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 120; font.weight: Font.DemiBold
                text: Qt.formatDateTime(root.now, "HH:mm")
            }
            Sh {
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 24
                text: root.now.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM")
            }
        }

        // ---- вход ----
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: (1 - root.reveal) * 60
            opacity: root.done ? 0 : root.reveal
            visible: opacity > 0
            spacing: 16
            Behavior on opacity { enabled: root.done; NumberAnimation { duration: 150 } }

            Face {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 160; height: 160
                user: root.userName
                fallback: { users.count; const it = users.itemAt(root.userIndex); return it ? it.icon : ""; }
            }
            Sh {
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 28
                text: root.userLabel
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 296; height: 36; radius: 4
                color: "#aa1f1f1f"
                border.color: "#55ffffff"
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 2; radius: 1
                    color: password.activeFocus ? "#60cdff" : "#99ffffff"
                }
                Text {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    visible: password.text === ""
                    color: "#ccffffff"; font.family: root.fontName; font.pixelSize: 14
                    text: "Пароль"
                }
                TextInput {
                    id: password
                    anchors { left: parent.left; right: eye.left; leftMargin: 12; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    clip: true
                    color: "white"
                    // Любые символы (русские, цифры, знаки) сразу показываются точками, без задержки.
                    // Увидеть пароль можно, только удерживая или нажав "глаз" справа.
                    property bool reveal: false
                    echoMode: reveal ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "\u25CF"
                    passwordMaskDelay: 0
                    inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    onTextChanged: if (text === "") reveal = false
                    font.family: root.fontName; font.pixelSize: 14
                    enabled: !root.busy
                    onAccepted: root.login()
                    Keys.onEscapePressed: { root.showLogin = false; catcher.forceActiveFocus(); }
                }
                // "глаз": показать или снова скрыть пароль
                Rectangle {
                    id: eye
                    anchors { right: submit.left; rightMargin: 2; verticalCenter: parent.verticalCenter }
                    width: 32; height: 32; radius: 4
                    visible: password.text !== ""
                    color: eyeArea.containsMouse ? "#33ffffff" : "transparent"
                    Text { anchors.centerIn: parent; font.family: icons.name; font.pixelSize: 16; color: "white"; text: password.reveal ? "\ue5f5" : "\ue5f2" }
                    MouseArea { id: eyeArea; anchors.fill: parent; hoverEnabled: true; onClicked: { password.reveal = !password.reveal; password.forceActiveFocus(); } }
                }
                Rectangle {
                    id: submit
                    anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
                    width: 32; height: 32; radius: 4
                    color: submitArea.containsMouse ? "#33ffffff" : "transparent"
                    Text { anchors.centerIn: parent; font.family: icons.name; font.pixelSize: 16; color: "white"; text: "\uf181" }
                    MouseArea { id: submitArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.login() }
                }
            }
            Sh {
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 13
                text: " "   // о результате проверки пароля ничего не сообщаем
            }
        }

        // ---- слева внизу: все учётные записи, как в Windows ----
        Column {
            anchors { left: parent.left; bottom: parent.bottom; margins: 24 }
            visible: users.count > 1
            opacity: root.done ? 0 : 1
            spacing: 4
            Repeater {
                model: userModel
                Rectangle {
                    id: ub
                    required property int index
                    required property var model
                    readonly property bool current: index === root.userIndex
                    width: 260; height: 52; radius: 4
                    color: current ? "#40ffffff" : (ubArea.containsMouse ? "#26ffffff" : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Rectangle { visible: ub.current; x: 0; anchors.verticalCenter: parent.verticalCenter; width: 3; height: 20; radius: 2; color: "#60cdff" }
                    Face { id: ubFace; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 36; height: 36; user: ub.model.name; fallback: ub.model.icon || "" }
                    Text {
                        anchors { left: ubFace.right; leftMargin: 12; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        color: "white"; font.family: root.fontName; font.pixelSize: 14
                        style: Text.Outline; styleColor: "#8c000000"
                        text: ub.model.realName || ub.model.name
                    }
                    MouseArea { id: ubArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.pickUser(ub.index) }
                }
            }
        }

        // ---- низ: сеанс и питание ----
        Rectangle {
            anchors { right: power.left; rightMargin: 12; verticalCenter: power.verticalCenter }
            visible: sessions.count > 1
            width: sessionText.implicitWidth + 24; height: 36; radius: 4
            color: sessionArea.containsMouse ? "#33ffffff" : "transparent"
            Sh {
                id: sessionText
                anchors.centerIn: parent
                font.pixelSize: 13
                text: "Сеанс: " + root.sessionName
            }
            MouseArea {
                id: sessionArea
                anchors.fill: parent; hoverEnabled: true
                onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessions.count
            }
        }
        Row {
            id: power
            anchors { right: parent.right; bottom: parent.bottom; margins: 24 }
            spacing: 4
            Repeater {
                model: [ { glyph: "\uf13f", act: "reboot" }, { glyph: "\uf60e", act: "off" } ]
                Rectangle {
                    id: pb
                    required property var modelData
                    width: 40; height: 40; radius: 4
                    color: pbArea.containsMouse ? "#33ffffff" : "transparent"
                    Text { anchors.centerIn: parent; font.family: icons.name; font.pixelSize: 20; color: "white"; text: pb.modelData.glyph }
                    MouseArea {
                        id: pbArea
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: pb.modelData.act === "reboot" ? sddm.reboot() : sddm.powerOff()
                    }
                }
            }
        }
    }
}
