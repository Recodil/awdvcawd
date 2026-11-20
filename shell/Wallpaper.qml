import QtQuick
import Quickshell
import Quickshell.Wayland

// Обои. При смене картинки новая плавно проявляется поверх старой;
// вторая картинка держится в памяти только на время перехода.
PanelWindow {
    id: win
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "#0a1c3a"      // тот же цвет, что у фона niri и заставки: до появления картинки экран не мигает
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "win11-wallpaper"

    readonly property url target: Store.wallpaperUrl
    function show() {
        if (width <= 0 || !Store.loaded) return;
        if (base.source.toString() === "") { base.source = target; return; }
        if (base.source.toString() === target.toString()) return;
        fade.stop(); settle.stop();
        next.opacity = 0;
        next.source = target;
    }
    onTargetChanged: show()
    onWidthChanged: show()
    Connections { target: Store; function onLoadedChanged() { win.show(); } }

    Image {
        id: base
        anchors.fill: parent
        // декодируем картинку под размер экрана, а не в полном 4K - экономия памяти
        sourceSize.width: Math.ceil(Math.max(width, height * 1.6))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        onStatusChanged: if (status === Image.Ready || status === Image.Error) Ui.wallReady = true
    }
    Image {
        id: next
        anchors.fill: parent
        opacity: 0
        sourceSize.width: base.sourceSize.width
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        onStatusChanged: {
            if (source.toString() === "") return;
            if (status === Image.Ready) fade.restart();
            else if (status === Image.Error) source = "";
        }
    }
    SequentialAnimation {
        id: fade
        NumberAnimation { target: next; property: "opacity"; to: 1; duration: 700; easing.type: Easing.InOutCubic }
        ScriptAction { script: { base.source = next.source; settle.restart(); } }
    }
    // старая картинка заменена - убираем верхний слой и освобождаем память
    Timer { id: settle; interval: 400; onTriggered: { next.opacity = 0; next.source = ""; } }
}
