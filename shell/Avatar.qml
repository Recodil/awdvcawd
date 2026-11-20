import QtQuick
import QtQuick.Effects
import Quickshell.Io

// Круглая аватарка пользователя. Файл: /var/lib/win11-shell/faces/<имя> (его же показывает экран входа).
// Картинки нет - значок человека.
Item {
    id: root
    property string user: Config.userName
    property color backColor: "#33ffffff"
    property color iconColor: "white"
    readonly property string path: "/var/lib/win11-shell/faces/" + user
    property bool exists: false
    readonly property bool ready: img.status === Image.Ready
    readonly property int rev: Store.avatarRev
    onRevChanged: reload()
    onUserChanged: reload()
    Component.onCompleted: reload()

    // Файл сначала проверяется: Image на отсутствующий файл пишет предупреждение в журнал.
    // Работающую проверку не трогаем: повторный запрос выполняется после неё.
    property bool again: false
    function reload() {
        if (user === "") return;
        if (probe.running) { again = true; return; }
        probe.command = ["test", "-s", path];
        probe.running = true;
    }
    Process {
        id: probe
        onExited: (code) => {
            root.exists = code === 0;
            img.source = "";
            if (root.exists) img.source = "file://" + root.path;
            if (root.again) { root.again = false; root.reload(); }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        visible: !root.ready
        color: root.backColor
        FIcon { anchors.centerIn: parent; icon: Icons.person; font.pixelSize: root.width * 0.5; color: root.iconColor }
    }
    Image {
        id: img
        anchors.fill: parent
        visible: false
        cache: false
        asynchronous: true
        sourceSize.width: Math.max(64, root.width * 2)
        sourceSize.height: Math.max(64, root.width * 2)
        fillMode: Image.PreserveAspectCrop
    }
    Rectangle { id: mask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
    MultiEffect { anchors.fill: parent; visible: root.ready; source: img; maskEnabled: true; maskSource: mask }
}
