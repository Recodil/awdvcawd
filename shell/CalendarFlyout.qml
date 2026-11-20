import QtQuick
import Quickshell

Flyout {
    id: root
    name: "calendar"
    role: "end"
    panelWidth: 344
    panelHeight: body.implicitHeight + 32

    property int year: Ui.now.getFullYear()
    property int month: Ui.now.getMonth()
    property int mode: 0                 // 0 - дни месяца, 1 - месяцы года, 2 - годы
    property var picked: null            // выбранный день (Date) или null
    property int dir: 1                  // куда листали: для анимации
    readonly property var monthNames: [Tr.t("Январь"), Tr.t("Февраль"), Tr.t("Март"), Tr.t("Апрель"), Tr.t("Май"), Tr.t("Июнь"), Tr.t("Июль"),
                                       Tr.t("Август"), Tr.t("Сентябрь"), Tr.t("Октябрь"), Tr.t("Ноябрь"), Tr.t("Декабрь")]
    readonly property var monthShort: [Tr.t("янв"), Tr.t("фев"), Tr.t("мар"), Tr.t("апр"), Tr.t("май"), Tr.t("июн"), Tr.t("июл"), Tr.t("авг"), Tr.t("сен"), Tr.t("окт"), Tr.t("ноя"), Tr.t("дек")]
    readonly property int decade: Math.floor(year / 10) * 10
    function same(a, b) { return a !== null && b !== null && a.getDate() === b.getDate() && a.getMonth() === b.getMonth() && a.getFullYear() === b.getFullYear(); }
    readonly property var cells: {
        const off = (new Date(year, month, 1).getDay() + 6) % 7;   // неделя с понедельника
        const now = Ui.now;
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(year, month, 1 - off + i);
            out.push({ date: d, day: d.getDate(), current: d.getMonth() === month, today: same(d, now),
                       weekend: i % 7 >= 5 });
        }
        return out;
    }
    // листание: в режиме дней - на месяц, месяцев - на год, лет - на десятилетие
    function shift(n) {
        dir = n > 0 ? 1 : -1;
        if (mode === 0) { const d = new Date(year, month + n, 1); year = d.getFullYear(); month = d.getMonth(); }
        else if (mode === 1) year = Math.max(1, year + n);
        else year = Math.max(1, year + n * 10);
        flip.restart();
    }
    function today() { year = Ui.now.getFullYear(); month = Ui.now.getMonth(); mode = 0; picked = null; }
    readonly property string caption: mode === 0 ? monthNames[month] + " " + year : mode === 1 ? "" + year : decade + " - " + (decade + 9)
    readonly property bool away: year !== Ui.now.getFullYear() || month !== Ui.now.getMonth() || mode !== 0
    onOpened: today()

    Column {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 12

        // ---- уведомления ----
        Item {
            width: parent.width; height: 28
            WText { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 14; font.weight: Font.DemiBold; text: Tr.t("Уведомления") }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4
                HoverButton {
                    visible: Notifs.count > 0
                    implicitWidth: clr.implicitWidth + 20; implicitHeight: 28
                    onClicked: Notifs.clearAll()
                    WText { id: clr; anchors.centerIn: parent; font.pixelSize: 12; text: Tr.t("Очистить все") }
                }
                // "Не беспокоить": щелчок - включить или выключить, правый щелчок - список исключений
                HoverButton {
                    implicitWidth: 28; implicitHeight: 28
                    highlighted: Store.dnd
                    onClicked: mouse => { if (mouse.button === Qt.RightButton) Ui.openSettings("notify"); else Notifs.toggleDnd(); }
                    FIcon { anchors.centerIn: parent; font.pixelSize: 16; icon: Store.dnd ? Icons.alertSnooze : Icons.alert; color: Store.dnd ? Theme.accent : Theme.text }
                }
                HoverButton {
                    implicitWidth: 28; implicitHeight: 28
                    onClicked: Ui.openSettings("notify")
                    FIcon { anchors.centerIn: parent; font.pixelSize: 16; icon: Icons.settings }
                }
            }
        }
        WText {
            visible: Notifs.count === 0 || Store.dnd
            width: parent.width; wrapMode: Text.Wrap
            color: Theme.subtext
            text: Store.dnd ? Tr.t("Включён режим \"Не беспокоить\": всплывают только системные уведомления и программы из списка исключений.")
                            : Tr.t("Новых уведомлений нет")
        }
        ListView {
            width: parent.width
            height: Math.min(contentHeight, 260)
            visible: Notifs.count > 0
            clip: true
            spacing: 8
            model: Notifs.list
            delegate: NotifCard {
                required property var modelData
                notif: modelData
                width: ListView.view.width
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.border }

        // ---- календарь ----
        // Листается колесом мыши и стрелками; щелчок по названию месяца открывает выбор месяца, затем года.
        Item {
            width: parent.width; height: 24
            WText {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 14
                text: (root.picked || Ui.now).toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM yyyy")
            }
        }
        Item {
            width: parent.width; height: 32
            HoverButton {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: cap.implicitWidth + 16; implicitHeight: 30
                x: -8
                onClicked: root.mode = Math.min(2, root.mode + 1)
                WText { id: cap; anchors.centerIn: parent; font.pixelSize: 14; font.weight: Font.DemiBold; text: root.caption }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                HoverButton {
                    visible: root.away
                    implicitWidth: td.implicitWidth + 16; implicitHeight: 32
                    onClicked: root.today()
                    WText { id: td; anchors.centerIn: parent; font.pixelSize: 12; color: Theme.accent; text: Tr.t("Сегодня") }
                }
                HoverButton { implicitWidth: 32; implicitHeight: 32; onClicked: root.shift(-1); FIcon { anchors.centerIn: parent; icon: Icons.chevronUp; font.pixelSize: 14 } }
                HoverButton { implicitWidth: 32; implicitHeight: 32; onClicked: root.shift(1); FIcon { anchors.centerIn: parent; icon: Icons.chevronDown; font.pixelSize: 14 } }
            }
        }
        Item {
            id: calBox
            width: parent.width
            height: 28 + 6 * 40
            clip: true
            // колесо мыши листает месяцы (годы, десятилетия) без остановки
            WheelHandler {
                property real acc: 0
                onWheel: e => {
                    acc += e.angleDelta.y;
                    while (acc >= 120) { acc -= 120; root.shift(-1); }
                    while (acc <= -120) { acc += 120; root.shift(1); }
                }
            }
            // короткий "перелист" при смене месяца
            Item {
                id: sheet
                width: parent.width; height: parent.height
                SequentialAnimation {
                    id: flip
                    PropertyAction { target: sheet; property: "y"; value: root.dir * 36 }
                    PropertyAction { target: sheet; property: "opacity"; value: 0.2 }
                    ParallelAnimation {
                        NumberAnimation { target: sheet; property: "y"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                        NumberAnimation { target: sheet; property: "opacity"; to: 1; duration: 200 }
                    }
                }

                // дни
                Grid {
                    visible: root.mode === 0
                    columns: 7
                    Repeater {
                        model: [Tr.t("Пн"), Tr.t("Вт"), Tr.t("Ср"), Tr.t("Чт"), Tr.t("Пт"), Tr.t("Сб"), Tr.t("Вс")]
                        WText {
                            required property string modelData
                            width: calBox.width / 7; height: 28
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            font.pixelSize: 12; text: modelData
                        }
                    }
                    Repeater {
                        model: root.cells
                        Item {
                            id: cell
                            required property var modelData
                            readonly property bool sel: root.same(modelData.date, root.picked)
                            width: calBox.width / 7; height: 40
                            Rectangle {
                                anchors.centerIn: parent
                                width: 36; height: 36; radius: 18
                                color: cell.modelData.today ? Theme.accent : (h.hovered ? Theme.hover : "transparent")
                                border.width: cell.sel ? 2 : 0
                                border.color: cell.modelData.today ? Theme.text : Theme.accent
                            }
                            HoverHandler { id: h }
                            TapHandler {
                                onTapped: {
                                    root.picked = cell.modelData.date;
                                    if (!cell.modelData.current) { root.dir = cell.modelData.date > new Date(root.year, root.month, 15) ? 1 : -1; root.year = cell.modelData.date.getFullYear(); root.month = cell.modelData.date.getMonth(); flip.restart(); }
                                }
                            }
                            WText {
                                anchors.centerIn: parent
                                font.pixelSize: 12
                                text: cell.modelData.day
                                color: cell.modelData.today ? Theme.accentText : cell.modelData.current ? Theme.text : Theme.subtext
                                opacity: cell.modelData.current ? 1 : 0.6
                            }
                        }
                    }
                }
                // месяцы
                Grid {
                    visible: root.mode === 1
                    columns: 4
                    Repeater {
                        model: 12
                        Item {
                            id: mcell
                            required property int index
                            readonly property bool cur: index === Ui.now.getMonth() && root.year === Ui.now.getFullYear()
                            width: calBox.width / 4; height: calBox.height / 3
                            Rectangle {
                                anchors.centerIn: parent
                                width: 60; height: 60; radius: 30
                                color: mcell.cur ? Theme.accent : (mh.hovered ? Theme.hover : "transparent")
                            }
                            HoverHandler { id: mh }
                            TapHandler { onTapped: { root.month = mcell.index; root.mode = 0; } }
                            WText { anchors.centerIn: parent; font.pixelSize: 13; text: root.monthShort[mcell.index]; color: mcell.cur ? Theme.accentText : Theme.text }
                        }
                    }
                }
                // годы
                Grid {
                    visible: root.mode === 2
                    columns: 4
                    Repeater {
                        model: 12
                        Item {
                            id: ycell
                            required property int index
                            readonly property int yr: root.decade - 1 + index
                            readonly property bool cur: y === Ui.now.getFullYear()
                            width: calBox.width / 4; height: calBox.height / 3
                            Rectangle {
                                anchors.centerIn: parent
                                width: 60; height: 60; radius: 30
                                color: ycell.cur ? Theme.accent : (yh.hovered ? Theme.hover : "transparent")
                            }
                            HoverHandler { id: yh }
                            TapHandler { onTapped: { root.year = Math.max(1, ycell.yr); root.mode = 1; } }
                            WText {
                                anchors.centerIn: parent; font.pixelSize: 13; text: ycell.yr
                                color: ycell.cur ? Theme.accentText : Theme.text
                                opacity: (ycell.index === 0 || ycell.index === 11) ? 0.6 : 1
                            }
                        }
                    }
                }
            }
        }
    }
}
