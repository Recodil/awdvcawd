import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Окна программы при наведении на её значок: карточка на каждое окно, как в Windows.
// Щелчок по карточке показывает окно, крестик закрывает его.
PanelWindow {
    id: win
    readonly property var info: Ui.peek
    readonly property string edge: Store.barEdge
    readonly property bool vert: edge === "left" || edge === "right"
    // окна могли закрыться, пока карточки на экране
    readonly property var wins: {
        if (!info) return [];
        const ids = info.windows.map(w => w.id);
        return Niri.windows.filter(w => ids.indexOf(w.id) >= 0);
    }
    onWinsChanged: if (info && wins.length === 0) Ui.peek = null

    readonly property int cardW: 208
    readonly property int cardH: 152
    readonly property real shift: info ? (vert ? info.y - implicitHeight / 2 : info.x - implicitWidth / 2) : 0

    visible: info !== null && wins.length > 0
    color: "transparent"
    implicitWidth: (vert ? cardW : wins.length * (cardW + 6) - 6) + 16
    implicitHeight: (vert ? wins.length * (cardH + 6) - 6 : cardH) + 16
    anchors {
        bottom: win.edge === "bottom"; top: win.edge !== "bottom"
        left: win.edge !== "right"; right: win.edge === "right"
    }
    margins {
        left: win.vert ? 0 : Math.max(0, win.shift)
        top: win.vert ? Math.max(0, win.shift) : 0
    }
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "win11-peek"

    // One ancestor covers cards, gaps and padding. Nested controls do not race
    // with a separate sibling handler when the pointer enters a preview.
    Item {
        anchors.fill: parent
        HoverHandler { id: popupHover; onHoveredChanged: Ui.holdPeek(hovered) }
        Grid {
        anchors.centerIn: parent
        columns: win.vert ? 1 : 99
        spacing: 6
        Repeater {
            model: win.wins
            Rectangle {
                id: card
                required property var modelData
                width: win.cardW; height: win.cardH
                radius: 8
                color: Theme.flyout
                border.color: cardHover.hovered || modelData.is_focused ? Theme.accent : Theme.border
                Behavior on border.color { ColorAnimation { duration: 140 } }
                HoverHandler { id: cardHover }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) { Niri.closeWindow(card.modelData); return; }
                        Niri.focusWindow(card.modelData);
                        Ui.peek = null;
                    }
                }
                IconImage {
                    id: small
                    anchors { left: parent.left; top: parent.top; leftMargin: 10; topMargin: 9 }
                    implicitSize: 16
                    source: Config.appIcon(win.info ? win.info.entry : null, card.modelData.app_id)
                }
                WText {
                    anchors { left: small.right; leftMargin: 8; right: closeBtn.left; rightMargin: 4; verticalCenter: small.verticalCenter }
                    font.pixelSize: 12
                    text: card.modelData.title || ""
                }
                HoverButton {
                    id: closeBtn
                    anchors { right: parent.right; top: parent.top; rightMargin: 4; topMargin: 4 }
                    implicitWidth: 26; implicitHeight: 26
                    visible: cardHover.hovered || hovered
                    onClicked: Niri.closeWindow(card.modelData)
                    FIcon { anchors.centerIn: parent; icon: Icons.dismiss; font.pixelSize: 12 }
                }
                Rectangle {
                    anchors { fill: parent; topMargin: 34; leftMargin: 8; rightMargin: 8; bottomMargin: 8 }
                    radius: 4
                    color: Theme.card
                    clip: true
                    IconImage {
                        anchors.centerIn: parent
                        visible: !(thumb.item && thumb.item.ready)
                        implicitSize: 40
                        source: small.source
                    }
                    // отдельным файлом: если композитор или Quickshell не умеют миниатюры, остаётся значок
                    Loader {
                        id: thumb
                        anchors.fill: parent
                        active: win.visible
                        source: "WindowThumb.qml"
                        onLoaded: item.win = Qt.binding(() => card.modelData)
                    }
                }
            }
        }
        }
    }
}
