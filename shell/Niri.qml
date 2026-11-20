pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Связь с композитором niri: окна, рабочие столы, обзор, сворачивание.
// niri не умеет сворачивать окна, поэтому "свернуть" = перенести окно
// на скрытый именованный рабочий стол (hiddenName), "развернуть" = вернуть на текущий.
Singleton {
    id: root
    readonly property string hiddenName: "min"
    property var workspaces: []
    property var windows: []
    property bool overview: false
    property var layoutNames: []       // раскладки клавиатуры
    property int layoutIdx: 0
    // подпись раскладки, как в Windows: ENG, РУС…
    readonly property string layoutLabel: {
        const n = (layoutNames[layoutIdx] || "").toLowerCase();
        if (n === "") return "";
        const known = [["russian", "РУС"], ["english", "ENG"], ["ukrainian", "УКР"], ["belarus", "БЕЛ"], ["kazakh", "КАЗ"],
                       ["german", "DEU"], ["french", "FRA"], ["spanish", "ESP"], ["italian", "ITA"], ["polish", "POL"]];
        for (let i = 0; i < known.length; i++) if (n.indexOf(known[i][0]) === 0) return known[i][1];
        return n.slice(0, 3).toUpperCase();
    }
    function nextLayout() { act(["switch-layout", "next"]); }
    property var shownDesktop: []      // окна, свёрнутые командой "Показать рабочий стол"

    readonly property int hiddenId: {
        for (let i = 0; i < workspaces.length; i++) if (workspaces[i].name === hiddenName) return workspaces[i].id;
        return -1;
    }
    readonly property var current: {
        for (let i = 0; i < workspaces.length; i++) if (workspaces[i].is_focused) return workspaces[i];
        return null;
    }
    readonly property int currentId: current ? current.id : -1
    // Рабочие столы текущего монитора без скрытого, по порядку.
    // niri всегда держит в конце один пустой безымянный стол и сам удаляет пустые в середине.
    // Чтобы созданный стол не пропадал, ему даётся имя (deskPrefix…): именованные столы niri хранит.
    // Пустой хвостовой стол в список не входит (кроме случая, когда мы на нём стоим) -
    // вместо него в представлении задач кнопка "Создать рабочий стол".
    readonly property string deskPrefix: "desk-"
    readonly property var allDesktops: {
        const out = [];
        const mon = current ? current.output : null;
        for (let i = 0; i < workspaces.length; i++) {
            const w = workspaces[i];
            if (w.name === hiddenName) continue;
            if (mon !== null && w.output !== mon) continue;
            out.push(w);
        }
        out.sort((a, b) => a.idx - b.idx);
        return out;
    }
    readonly property var desktops: {
        const all = allDesktops;
        if (all.length < 2) return all;
        const last = all[all.length - 1];
        const spare = !last.name && !last.is_focused && windowsOn(last.id).length === 0;
        return spare ? all.slice(0, all.length - 1) : all;
    }
    readonly property var focusedWindow: {
        for (let i = 0; i < windows.length; i++) if (windows[i].is_focused) return windows[i];
        return null;
    }

    function act(args) { Quickshell.execDetached(["niri", "msg", "action"].concat(args)); }
    function isMin(w) { return hiddenId >= 0 && w.workspace_id === hiddenId; }
    function windowsOn(wsId) {
        const out = [];
        for (let i = 0; i < windows.length; i++) if (windows[i].workspace_id === wsId) out.push(windows[i]);
        return out;
    }
    function minimize(w) {
        if (!w) return;
        // тот же сценарий вызывает кнопка "Свернуть" в заголовке окна; он ведёт журнал ошибок
        Quickshell.execDetached(["win11-minimize", "" + w.id]);
    }
    function restore(w) {
        if (!w) return;
        const idx = current && current.name !== hiddenName ? current.idx : (desktops.length > 0 ? desktops[0].idx : 1);
        // сценарий возвращает окно на стол и плавно поднимает его на прежнее место
        Quickshell.execDetached(["win11-minimize", "--restore", "" + w.id, "" + idx]);
    }
    function focusWindow(w) { if (isMin(w)) restore(w); else act(["focus-window", "--id", "" + w.id]); }
    // когда окно последний раз было активным (niri сообщает это не во всех версиях)
    function focusStamp(w) {
        const t = w ? w.focus_timestamp : null;
        return t ? t.secs + t.nanos / 1e9 : 0;
    }
    // окно, с которым работали последним
    function recent(list) {
        let best = list.length > 0 ? list[0] : null;
        for (let i = 1; i < list.length; i++) if (focusStamp(list[i]) > focusStamp(best)) best = list[i];
        return best;
    }
    function closeWindow(w) { act(["close-window", "--id", "" + w.id]); }
    // принудительно: для зависшей программы, которая не отвечает на обычное закрытие
    function killWindow(w) { if (w && w.pid > 1) Quickshell.execDetached(["kill", "-KILL", "" + w.pid]); }
    function toggleOverview() { Ui.toggleTaskView(); }
    // выбрать окно из представления задач: показать его и закрыть обзор
    function activate(w) {
        Ui.taskView = false;
        if (w) focusWindow(w);
    }
    function restoreAll() {
        for (let i = 0; i < windows.length; i++) if (isMin(windows[i])) restore(windows[i]);
        shownDesktop = [];
    }
    function focusDesktop(d) { if (d) act(["focus-workspace", "" + d.idx]); }
    function stepDesktop(delta) {
        let i = 0;
        for (let k = 0; k < desktops.length; k++) if (desktops[k].id === currentId) i = k;
        focusDesktop(desktops[Math.max(0, Math.min(desktops.length - 1, i + delta))]);
    }
    // Новый стол: переходим на пустой хвостовой стол и даём ему имя - теперь он не исчезнет,
    // даже если на нём нет окон, и на него можно вернуться.
    function newDesktop() {
        const all = allDesktops;
        if (all.length === 0) return;
        const last = all[all.length - 1];
        const name = deskPrefix + Date.now();
        if (last.name || windowsOn(last.id).length > 0) return;     // хвостового пустого стола нет - не бывает, но на всякий случай
        Quickshell.execDetached(["sh", "-c",
            "niri msg action focus-workspace \"$1\" && niri msg action set-workspace-name \"$2\"", "sh", "" + last.idx, name]);
    }
    // Закрыть стол: окна переезжают на соседний, имя снимается - пустой стол niri уберёт сам.
    function removeDesktop(d) {
        const list = desktops;
        if (!d || list.length < 2) return;
        let k = -1;
        for (let i = 0; i < list.length; i++) if (list[i].id === d.id) k = i;
        if (k < 0) return;
        const to = list[k > 0 ? k - 1 : 1];
        const ids = windowsOn(d.id).map(w => "" + w.id);
        // сначала переходим на соседний стол (пока номера столов не сдвинулись), потом переносим окна
        const cmd = "to=\"$1\"; from=\"$2\"; named=\"$3\"; shift 3; " +
                  "niri msg action focus-workspace \"$to\"; " +
                  "for id in \"$@\"; do niri msg action move-window-to-workspace --window-id \"$id\" --focus false \"$to\"; done; " +
                  "[ -n \"$named\" ] && niri msg action unset-workspace-name \"$named\"; true";
        // на соседний стол ссылаемся по имени, если оно есть: номера сдвигаются, когда стол исчезает
        Quickshell.execDetached(["sh", "-c", cmd, "sh", to.name ? to.name : "" + to.idx, "" + d.idx, d.name || ""].concat(ids));
    }
    function minimizeFocused() { if (focusedWindow) minimize(focusedWindow); }
    function showDesktop() {
        const here = windowsOn(currentId);
        if (here.length > 0) {
            shownDesktop = here.map(w => w.id);
            for (let i = 0; i < here.length; i++) minimize(here[i]);
        } else {
            for (let i = 0; i < windows.length; i++)
                if (shownDesktop.indexOf(windows[i].id) >= 0 && isMin(windows[i])) restore(windows[i]);
            shownDesktop = [];
        }
    }

    function apply(wsText, winText, kbText) {
        try {
            const kb = JSON.parse(kbText || "null");
            if (kb && Array.isArray(kb.names)) { layoutNames = kb.names; layoutIdx = kb.current_idx || 0; }
        } catch (e) {}
        try {
            const ws = JSON.parse(wsText);
            const wn = JSON.parse(winText);
            if (Array.isArray(ws)) workspaces = ws;
            if (Array.isArray(wn)) { wn.sort((a, b) => a.id - b.id); windows = wn; }
        } catch (e) {}
    }

    // скрытый стол не должен оставаться текущим: уходим с него, как только закрыт обзор
    Timer {
        interval: 150
        running: root.current !== null && root.current.name === root.hiddenName && !root.overview && root.desktops.length > 0
        onTriggered: root.focusDesktop(root.desktops[0])
    }

    // поток событий niri: по любому событию перечитываем состояние
    Process {
        id: events
        running: true
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("OverviewOpenedOrClosed") >= 0) {
                    try { root.overview = JSON.parse(line).OverviewOpenedOrClosed.is_open === true; } catch (e) {}
                }
                debounce.restart();
            }
        }
        onExited: restart.start()
    }
    Timer { id: restart; interval: 2000; onTriggered: events.running = true }
    Timer { id: debounce; interval: 25; onTriggered: refresh.running = true }
    Process {
        id: refresh
        command: ["sh", "-c", "niri msg --json workspaces; printf '\\n@@\\n'; niri msg --json windows; printf '\\n@@\\n'; niri msg --json keyboard-layouts"]
        stdout: StdioCollector {
            id: state
            onStreamFinished: {
                const p = state.text.split("@@");
                if (p.length >= 2) root.apply(p[0], p[1], p[2]);
            }
        }
    }
}
