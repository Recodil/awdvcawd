import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Services.Mpris

Flyout {
    id: root
    name: "quick"
    role: "end"
    panelWidth: 360
    panelHeight: body.implicitHeight + 48 + 24

    component Tile: Column {
        id: tile
        property string icon
        property string label
        property bool on: false
        signal toggled()
        spacing: 6
        width: 96
        Rectangle {
            width: 96; height: 48; radius: 4
            color: tile.on ? Theme.accent : (ma.containsMouse ? Theme.hover : Theme.card)
            border.color: tile.on ? Theme.accent : Theme.border
            scale: ma.pressed ? 0.96 : 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 100 } }
            FIcon { anchors.centerIn: parent; icon: tile.icon; font.pixelSize: 18; color: tile.on ? Theme.accentText : Theme.text }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: tile.toggled() }
        }
        WText { width: parent.width; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 12; text: tile.label }
    }

    // проигрыватель, который сейчас играет (или первый попавшийся)
    readonly property var player: {
        const p = Mpris.players.values;
        for (let i = 0; i < p.length; i++) if (p[i].isPlaying) return p[i];
        return p.length > 0 ? p[0] : null;
    }

    Column {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 20

        // ---- карточка мультимедиа ----
        Rectangle {
            visible: root.player !== null
            width: parent.width; height: 76; radius: 6
            color: Theme.card
            border.color: Theme.border
            Column {
                anchors { left: parent.left; right: mediaRow.left; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 8 }
                spacing: 2
                WText { width: parent.width; font.pixelSize: 11; color: Theme.subtext; text: root.player ? (root.player.identity || "") : "" }
                WText { width: parent.width; font.weight: Font.DemiBold; text: root.player ? (root.player.trackTitle || Tr.t("Без названия")) : "" }
                WText { width: parent.width; font.pixelSize: 12; color: Theme.subtext; text: root.player ? (root.player.trackArtist || "") : "" }
            }
            Row {
                id: mediaRow
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                HoverButton { implicitWidth: 34; implicitHeight: 34; onClicked: root.player.previous(); FIcon { anchors.centerIn: parent; icon: Icons.previous } }
                HoverButton { implicitWidth: 34; implicitHeight: 34; onClicked: root.player.togglePlaying(); FIcon { anchors.centerIn: parent; font.pixelSize: 18; icon: (root.player && root.player.isPlaying) ? Icons.pause : Icons.play } }
                HoverButton { implicitWidth: 34; implicitHeight: 34; onClicked: root.player.next(); FIcon { anchors.centerIn: parent; icon: Icons.next } }
            }
        }

        Grid {
            columns: 3
            columnSpacing: 12; rowSpacing: 16
            Tile { visible: Sys.hasWifi; icon: Sys.wifi ? Icons.wifi : Icons.wifiOff; label: "Wi-Fi"; on: Sys.wifi; onToggled: Sys.setWifi(!Sys.wifi) }
            Tile { visible: !Sys.hasWifi; icon: Sys.netIcon; label: Sys.netText; on: Sys.net === "ethernet" && Sys.online }
            Tile { visible: Sys.hasBluetooth; icon: Icons.bluetooth; label: "Bluetooth"; on: Sys.bluetooth; onToggled: Sys.setBluetooth(!Sys.bluetooth) }
            Tile { icon: Icons.moon; label: Tr.t("Ночной свет"); on: Sys.night; onToggled: Sys.toggleNight() }
            Tile { icon: Store.dnd ? Icons.alertSnooze : Icons.alert; label: Tr.t("Не беспокоить"); on: Store.dnd; onToggled: Notifs.toggleDnd() }
            Tile { icon: Icons.darkTheme; label: Theme.dark ? Tr.t("Тёмная тема") : Tr.t("Светлая тема"); on: Theme.dark; onToggled: Theme.toggle() }
        }

        Row {
            visible: Sys.brightness >= 0
            spacing: 14
            FIcon { anchors.verticalCenter: parent.verticalCenter; icon: Icons.brightness; font.pixelSize: 18 }
            WinSlider { width: body.width - 32; value: Sys.brightness; onMoved: v => Sys.setBrightness(v) }
        }
        Row {
            spacing: 14
            FIcon {
                anchors.verticalCenter: parent.verticalCenter
                icon: Sys.muted ? Icons.speakerMute : Icons.speaker; font.pixelSize: 18
                MouseArea { anchors.fill: parent; onClicked: Sys.toggleMute() }
            }
            WinSlider { width: body.width - 32; value: Sys.volume; onMoved: v => Sys.setVolume(v) }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
        height: 47
        color: Theme.footer
        Rectangle { width: parent.width; height: 1; color: Theme.border }
        Row {
            anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
            spacing: 8
            visible: UPower.displayDevice !== null && UPower.displayDevice.isLaptopBattery
            FIcon { icon: UPower.onBattery ? Icons.battery : Icons.batteryCharge }
            WText { font.pixelSize: 12; text: UPower.displayDevice ? Math.round(UPower.displayDevice.percentage * 100) + "%" : "" }
        }
        WText {
            anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
            font.pixelSize: 12; color: Theme.subtext
            text: Tr.t("Громкость ") + Math.round(Sys.volume * 100) + "%"
        }
    }
}
