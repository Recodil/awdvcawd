import QtQuick
import Quickshell.Wayland

// Живая миниатюра окна. Работает, только если композитор отдаёт содержимое отдельного окна;
// иначе ready остаётся ложным и вместо миниатюры показывается значок программы.
Item {
    id: root
    property var win: null            // окно из Niri.windows
    readonly property var toplevel: {
        if (!win) return null;
        const all = ToplevelManager.toplevels.values;
        let same = null;
        for (let i = 0; i < all.length; i++) {
            if (all[i].appId !== win.app_id) continue;
            if (all[i].title === win.title) return all[i];
            same = same || all[i];
        }
        return same;
    }
    readonly property bool ready: toplevel !== null && view.hasContent

    ScreencopyView {
        id: view
        anchors.fill: parent
        captureSource: root.toplevel
        live: root.visible
    }
}
