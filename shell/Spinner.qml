import QtQuick

Item {
    id: root
    property color color: "white"
    implicitWidth: 40
    implicitHeight: 40
    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.lineWidth = 3;
            ctx.lineCap = "round";
            ctx.strokeStyle = root.color;
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, width / 2 - 3, 0, Math.PI * 1.35);
            ctx.stroke();
        }
        RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: root.visible }
    }
}
