import QtQuick

Text {
    property alias icon: self.text
    id: self
    font.family: Icons.family
    font.pixelSize: 16
    color: Theme.text
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
