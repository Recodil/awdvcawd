pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Состояние центра обновления. Сведения собирает сценарий win11-updates:
// оболочка, NixOS, программы, драйверы под найденное оборудование, прошивки.
Singleton {
    id: root

    // { kind, state, id, title, detail };  kind: shell, nixos, release, apps, driver, optional, firmware
    property var rows: []
    property bool busy: false
    property string checkedAt: ""

    readonly property var pending: rows.filter(r => r.state === "update" || r.state === "install" || (r.kind === "driver" && r.state === "offer"))
    readonly property int count: pending.length
    // то, ради чего стоит показывать значок на панели задач: переход на новый выпуск NixOS
    // к таким не относится - это большое дело, его начинают сами, из центра обновления
    readonly property int notable: pending.filter(r => r.kind !== "release").length
    readonly property bool driversPending: rows.some(r => r.kind === "driver" && (r.state === "install" || r.state === "update" || r.state === "offer"))

    function check() {
        if (busy) return;
        busy = true;
        checker.running = true;
    }
    // what: shell, nixos, release, apps, drivers, firmware, all
    function apply(what, arg) {
        Quickshell.execDetached(["win11-updates", "apply", what].concat(arg ? [arg] : []));
    }

    // Установка идёт по одной: пока работает одна, остальные нажатые строки сами встают
    // в очередь и запускаются следом. Ключ строки - "раздел" или "раздел=id".
    property var queue: []
    property var running: []              // ключи того, что ставится сейчас
    readonly property bool working: running.length > 0
    function isRunning(r) { return running.indexOf(keyOf(r)) >= 0; }
    function launch(keys) {
        running = keys;
        Quickshell.execDetached(["win11-updates", "apply", "queue"].concat(keys));
    }
    // кнопка у строки: поставить; повторное нажатие на стоящую в очереди - убрать из неё
    function install(r) {
        const k = keyOf(r);
        if (isRunning(r)) return;
        if (queued(r)) { queue = queue.filter(x => x !== k); return; }
        if (working) queue = queue.concat([k]);
        else launch([k]);
    }
    function installAll() {
        const keys = [];
        pending.forEach(r => { const k = keyOf(r); if (keys.indexOf(k) < 0 && running.indexOf(k) < 0) keys.push(k); });
        if (keys.length === 0) return;
        if (working) queue = keys; else launch(keys);
    }
    // сценарий сообщает, что окно установки закрылось
    function jobDone() {
        running = [];
        if (queue.length > 0) { const next = queue; queue = []; launch(next); }
        else check();
    }
    function keyOf(r) {
        if (r.kind === "driver") return (r.id && r.id !== "-") ? "driver=" + r.id : "drivers";
        // необязательное: предложенное включается, уже включённое - убирается
        if (r.kind === "optional") return (r.state === "applied" ? "optional-off=" : "optional=") + r.id;
        return (r.kind === "shell" || r.kind === "release") && r.id && r.id !== "-" ? r.kind + "=" + r.id : r.kind;
    }
    function queued(r) { return queue.indexOf(keyOf(r)) >= 0; }
    function parse(text) {
        const out = [];
        text.split("\n").forEach(line => {
            const p = line.split("\t");
            if (p.length >= 4) out.push({ kind: p[0], state: p[1], id: p[2], title: p[3], detail: p[4] || "" });
        });
        return out;
    }

    Process {
        id: checker
        command: ["win11-updates", "check"]
        stdout: StdioCollector {
            id: output
            onStreamFinished: {
                root.rows = root.parse(output.text);
                root.checkedAt = Qt.formatDateTime(new Date(), "dd.MM.yyyy HH:mm");
                root.busy = false;
            }
        }
    }
    // первая проверка - вскоре после входа, дальше раз в шесть часов
    Timer { interval: 90 * 1000; running: true; onTriggered: root.check() }
    Timer { interval: 6 * 3600 * 1000; running: true; repeat: true; onTriggered: root.check() }
}
