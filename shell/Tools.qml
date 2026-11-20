pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Звук и обход блокировок для "Параметров". Сама работа - в сценариях win11-sound и
// win11-zapret; здесь только их состояние (команда state) и запуск команд.
Singleton {
    id: root

    // ---- звук ----
    property bool hasJacks: false         // поддерживается ли чипом Realtek
    property bool isVm: false             // виртуальная машина (VMware, VirtualBox)
    property string port: ""              // активное гнездо аналогового выхода
    property string defaultSink: ""
    property string defaultSource: ""
    property var sinks: []                // { n, name, title }
    property var sources: []              // { n, name, title }

    // ---- обход блокировок ----
    property bool zapretLive: false       // настройки меняются на ходу, без пересборки и пароля
    // смена настройки zapret: на ходу - молча, на старой сборке - в терминале (пересборка)
    function zapret(args) {
        if (zapretLive) run(["win11-zapret"].concat(args));
        else runInTerminal("win11-zapret " + args.join(" "));
    }
    property string zapretMode: ""        // on, off, disabled, missing; пусто - ещё не опрошено
    property string strategy: ""
    property string fake: ""
    property string game: "off"
    property var strategies: []           // имена в том же порядке, что в win11-zapret list
    property var fakes: []

    function refresh() { if (!reader.running) reader.running = true; }

    // Тихая команда без прав администратора; после неё состояние перечитывается.
    function run(args) {
        Quickshell.execDetached(args);
        later.restart();
    }
    // Команда, которой нужен пароль или пересборка системы: идёт в терминале, чтобы был виден ход.
    function runInTerminal(cmd) {
        Quickshell.execDetached(["sh", "-c", "setsid -f kitty --hold sh -c \"$1\" >/dev/null 2>&1", "sh", cmd]);
    }

    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
    function parse(text) {
        const s = [], src = [], st = [], fk = [];
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const p = lines[i].split("\t");
            switch (p[0]) {
            case "has_jacks": root.hasJacks = p[1] === "1"; break;
            case "is_vm": root.isVm = p[1] === "1"; break;
            case "port": root.port = p[1] || ""; break;
            case "default": root.defaultSink = p[1] || ""; break;
            case "default_source": root.defaultSource = p[1] || ""; break;
            case "sink": s.push({ n: parseInt(p[1]), name: p[2], title: p[3] || p[2] }); break;
            case "source": src.push({ n: parseInt(p[1]), name: p[2], title: p[3] || p[2] }); break;
            case "mode": root.zapretMode = p[1] || ""; break;
            case "live": root.zapretLive = p[1] === "1"; break;
            case "current": root.strategy = p[1] || ""; break;
            case "fake": root.fake = p[1] || ""; break;
            case "game": root.game = p[1] || "off"; break;
            case "strategy": st.push(p[1]); break;
            case "fakefile": fk.push(p[1]); break;
            }
        }
        // списки заменяются, только если изменились: иначе плитки на странице
        // пересоздавались бы при каждом опросе
        if (!same(root.sinks, s)) root.sinks = s;
        if (!same(root.sources, src)) root.sources = src;
        if (!same(root.strategies, st)) root.strategies = st;
        if (!same(root.fakes, fk)) root.fakes = fk;
    }

    Process {
        id: reader
        command: ["sh", "-c", "win11-sound state 2>/dev/null; win11-zapret state 2>/dev/null"]
        stdout: StdioCollector { id: out; onStreamFinished: root.parse(out.text) }
    }
    Timer { id: later; interval: 1500; onTriggered: root.refresh() }
}
