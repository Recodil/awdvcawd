import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Диспетчер задач: те же вкладки, что в Windows 11. Данные даёт сценарий win11-taskmgr,
// он работает, только пока окно открыто.
AppWindow {
    id: root
    heading: Tr.t("Диспетчер задач")
    open: Ui.taskmgrOpen
    onDismissed: Ui.taskmgrOpen = false
    implicitWidth: 940
    implicitHeight: 660
    minimumSize: Qt.size(720, 480)

    readonly property var tabs: [
        { id: "procs", icon: Icons.apps, label: Tr.t("Процессы") },
        { id: "perf", icon: Icons.pulse, label: Tr.t("Производительность") },
        { id: "history", icon: Icons.history, label: Tr.t("Журнал приложений") },
        { id: "startup", icon: Icons.rocket, label: Tr.t("Автозагрузка") },
        { id: "users", icon: Icons.person, label: Tr.t("Пользователи") },
        { id: "details", icon: Icons.document, label: Tr.t("Подробности") },
        { id: "services", icon: Icons.settings, label: Tr.t("Службы") }
    ]
    property string tab: "procs"
    property string filter: ""
    property string selected: ""          // ключ выбранной строки на текущей вкладке
    onTabChanged: { selected = ""; if (tab === "services") loadServices(); if (tab === "startup") loadStartup(); }

    // ---- данные ----
    property var procs: []                // { pid, ppid, user, cpu, mem, threads, state, time, name, args }
    property var cpu: ({ pct: 0, uptime: 0, procs: 0, threads: 0, name: "", cores: 0, mhz: 0 })
    property var mem: ({ used: 0, total: 1, avail: 0, cached: 0, swapUsed: 0, swapTotal: 0 })
    property var disks: []                // { name, read, write, busy }
    property var nets: []                 // { name, rx, tx }
    property var gpus: []                 // { name, util, memUsed, memTotal, temp }
    property var hist: ({})               // ключ графика -> последние значения
    property var services: []
    property var startup: []
    property int frames: 0
    property var draft: null              // кадр, который сейчас читается

    readonly property int histLen: 60
    function push(h, key, v) {
        const a = (h[key] || []).slice(-(histLen - 1));
        a.push(v);
        h[key] = a;
    }
    function line(text) {
        const p = text.split("\t");
        if (!draft) draft = { procs: [], disks: [], nets: [], gpus: [] };
        const d = draft;
        if (p[0] === "proc" && p.length >= 11) {
            d.procs.push({ pid: +p[1], ppid: +p[2], user: p[3], cpu: +p[4], mem: +p[5], threads: +p[6], state: p[7], time: +p[8], name: p[9], args: p[10], disk: p.length > 11 ? +p[11] : -1 });
        } else if (p[0] === "perf") {
            if (p[1] === "cpu") d.cpu = { pct: +p[2], uptime: +p[3], procs: +p[4], threads: +p[5] };
            else if (p[1] === "mem") d.mem = { used: +p[2], total: Math.max(1, +p[3]), avail: +p[4], cached: +p[5], swapUsed: +p[6], swapTotal: +p[7] };
            else if (p[1] === "disk") d.disks.push({ name: p[2], read: +p[3], write: +p[4], busy: Math.min(100, +p[5]) });
            else if (p[1] === "net") d.nets.push({ name: p[2], rx: +p[3], tx: +p[4] });
            else if (p[1] === "gpu") d.gpus.push({ name: p[2], util: +p[3], memUsed: +p[4], memTotal: +p[5], temp: +p[6] });
        } else if (p[0] === "info" && p[1] === "cpu") {
            cpu = Object.assign({}, cpu, { name: p[2], cores: +p[3], mhz: +p[4] });
        } else if (p[0] === "end") {
            commit(d);
            draft = null;
        }
    }
    function commit(d) {
        const h = Object.assign({}, hist);
        if (d.cpu) { cpu = Object.assign({}, cpu, d.cpu); push(h, "cpu", d.cpu.pct); }
        if (d.mem) { mem = d.mem; push(h, "mem", 100 * d.mem.used / d.mem.total); }
        d.disks.forEach(x => push(h, "disk:" + x.name, x.busy));
        d.nets.forEach(x => push(h, "net:" + x.name, (x.rx + x.tx) / 1024));
        d.gpus.forEach((x, i) => push(h, "gpu:" + i, x.util));
        disks = d.disks; nets = d.nets; gpus = d.gpus; procs = d.procs; hist = h;
        frames++;
    }
    function feed(text) { text.split("\n").forEach(l => line(l)); }

    Process {
        running: root.open
        command: ["win11-taskmgr", "watch", "2"]
        stdout: SplitParser { onRead: l => root.line(l) }
    }
    function parseRows(text, tag, keys) {
        const out = [];
        text.split("\n").forEach(l => {
            const p = l.split("\t");
            if (p[0] !== tag) return;
            const o = {};
            keys.forEach((k, i) => o[k] = p[i + 1] || "");
            out.push(o);
        });
        return out;
    }
    function loadServices() { svcReader.running = true; }
    function loadStartup() { autoReader.running = true; }
    Process {
        id: svcReader
        command: ["win11-taskmgr", "services"]
        stdout: StdioCollector { id: svcOut; onStreamFinished: root.services = root.parseRows(svcOut.text, "svc", ["name", "pid", "desc", "state", "sub"]) }
    }
    Process {
        id: autoReader
        command: ["win11-taskmgr", "startup"]
        stdout: StdioCollector { id: autoOut; onStreamFinished: root.startup = root.parseRows(autoOut.text, "auto", ["file", "name", "on", "src", "exec"]) }
    }
    Timer { id: reload; interval: 600; onTriggered: { if (root.tab === "startup") root.loadStartup(); if (root.tab === "services") root.loadServices(); } }

    property var userPss: ({})
    Process {
        id: userPssReader
        command: ["win11-taskmgr", "users-memory"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                text.split("\n").forEach(line => {
                    const p = line.split("\t");
                    if (p[0] === "userpss" && p.length >= 5)
                        out[p[1]] = { memory: +p[2], visible: +p[3], total: +p[4] };
                });
                root.userPss = out;
            }
        }
    }
    Timer {
        interval: 10000; repeat: true; running: root.open && root.tab === "users"
        triggeredOnStart: true
        onTriggered: if (!userPssReader.running) userPssReader.running = true
    }
    function userMemory(name) {
        const p = userPss[name];
        if (!p || p.visible === 0) return "—";
        return (p.visible < p.total ? "≈ " : "") + size(p.memory);
    }

    // ---- вывод чисел ----
    function num(v, digits) { return v.toFixed(digits).replace(".", Tr.russian ? "," : "."); }
    function pct(v) { return num(v, v >= 10 ? 0 : 1) + "%"; }
    function size(kb) { return kb >= 1048576 ? num(kb / 1048576, 1) + " " + Tr.t("ГБ") : num(kb / 1024, kb >= 102400 ? 0 : 1) + " " + Tr.t("МБ"); }
    function rate(bytes) {
        const kb = bytes / 1024;
        return kb >= 1024 ? num(kb / 1024, 1) + " " + Tr.t("МБ/с") : num(kb, kb >= 100 ? 0 : 1) + " " + Tr.t("КБ/с");
    }
    function span(s) {
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = Math.floor(s % 60);
        const two = v => (v < 10 ? "0" : "") + v;
        return (h >= 24 ? Math.floor(h / 24) + ":" + two(h % 24) : h) + ":" + two(m) + ":" + two(sec);
    }
    readonly property var stateNames: ({ R: Tr.t("Выполняется"), S: Tr.t("Ожидание"), I: Tr.t("Простаивает"), T: Tr.t("Приостановлен"), Z: Tr.t("Не отвечает"), D: Tr.t("Ввод-вывод") })
    readonly property var svcStates: ({ active: Tr.t("Выполняется"), inactive: Tr.t("Остановлена"), failed: Tr.t("Сбой"), activating: Tr.t("Запускается"), deactivating: Tr.t("Останавливается") })

    // ---- списки для вкладок ----
    function match(text) { return filter === "" || text.toLowerCase().indexOf(filter.toLowerCase()) >= 0; }
    function sum(list, key) { let s = 0; for (let i = 0; i < list.length; i++) s += list[i][key]; return s; }
    function sorted(rows, key, desc) {
        const out = rows.slice();
        out.sort((a, b) => {
            const x = a[key], y = b[key];
            const c = typeof x === "number" ? x - y : ("" + x).localeCompare("" + y);
            return desc ? -c : c;
        });
        return out;
    }
    property var sort: ({ procs: ["mem", true], history: ["time", true], users: ["mem", true], details: ["name", false], services: ["name", false], startup: ["name", false] })
    function sortBy(key) {
        const s = Object.assign({}, sort);
        const cur = s[tab] || ["name", false];
        s[tab] = [key, cur[0] === key ? !cur[1] : key !== "name"];
        sort = s;
    }
    function order(rows, t) { const s = sort[t || tab] || ["name", false]; return sorted(rows, s[0], s[1]); }

    // Приложения - процессы, у которых есть окно, вместе с потомками; остальное - фоновые по именам.
    readonly property var groups: {
        const kids = {}, byPid = {};
        procs.forEach(p => { byPid[p.pid] = p; (kids[p.ppid] = kids[p.ppid] || []).push(p); });
        const taken = {}, apps = [];
        const tree = (p, acc) => { if (taken[p.pid]) return; taken[p.pid] = true; acc.push(p); (kids[p.pid] || []).forEach(k => tree(k, acc)); };
        const seen = {};
        Niri.windows.forEach(w => {
            const p = byPid[w.pid];
            if (!p || seen[p.pid]) return;
            seen[p.pid] = true;
            const all = []; tree(p, all);
            if (all.length === 0) return;
            const e = Config.entryFor(w.app_id);
            apps.push({ key: "a:" + p.pid, icon: Config.appIcon(e, w.app_id || ""), name: e ? e.name : (w.app_id || p.name), count: all.length, cpu: sum(all, "cpu"), mem: sum(all, "mem"), disk: all.some(x => x.disk < 0) ? -1 : sum(all, "disk"), pids: [p.pid], state: "" });
        });
        const bg = {};
        procs.forEach(p => {
            if (taken[p.pid]) return;
            const g = bg[p.name] = bg[p.name] || { key: "b:" + p.name, name: p.name, count: 0, cpu: 0, mem: 0, disk: 0, pids: [], state: "" };
            g.count++; g.cpu += p.cpu; g.mem += p.mem; g.disk = g.disk < 0 || p.disk < 0 ? -1 : g.disk + p.disk; g.pids.push(p.pid);
        });
        return { apps: apps, bg: Object.keys(bg).map(k => bg[k]) };
    }
    readonly property var procRows: {
        const a = order(groups.apps.filter(g => match(g.name)), "procs"), b = order(groups.bg.filter(g => match(g.name)), "procs");
        const out = [];
        if (a.length > 0) { out.push({ head: Tr.t("Приложения") + " (" + a.length + ")" }); a.forEach(x => out.push(x)); }
        if (b.length > 0) { out.push({ head: Tr.t("Фоновые процессы") + " (" + b.length + ")" }); b.forEach(x => out.push(x)); }
        return out;
    }
    function grouped(key, mine) {
        const m = {};
        procs.forEach(p => {
            if (mine && p.user !== Config.userName) return;
            const g = m[p[key]] = m[p[key]] || { key: p[key], name: p[key], count: 0, cpu: 0, mem: 0, time: 0 };
            g.count++; g.cpu += p.cpu; g.mem += p.mem; g.time += p.time;
        });
        return Object.keys(m).map(k => {
            const g = m[k];
            if (key === "user") g.mem = userPss[k] && userPss[k].visible > 0 ? userPss[k].memory : -1;
            return g;
        }).filter(g => match(g.name));
    }
    readonly property var rowsNow: tab === "procs" ? procRows
        : tab === "history" ? order(grouped("name", true))
        : tab === "users" ? order(grouped("user", false))
        : tab === "details" ? order(procs.filter(p => match(p.name + " " + p.args)).map(p => Object.assign({ key: "" + p.pid }, p)))
        : tab === "services" ? order(services.filter(s => match(s.name + " " + s.desc)).map(s => Object.assign({ key: s.name }, s)))
        : tab === "startup" ? order(startup.filter(s => match(s.name)).map(s => Object.assign({ key: s.file }, s)))
        : []
    readonly property var picked: { for (let i = 0; i < rowsNow.length; i++) if (rowsNow[i].key === selected) return rowsNow[i]; return null; }

    readonly property real memPct: 100 * mem.used / mem.total
    readonly property var columns: ({
        procs: [
            { key: "name", title: Tr.t("Имя"), fmt: r => r.name + (r.count > 1 ? " (" + r.count + ")" : "") },
            { key: "cpu", title: pct(cpu.pct) + "\n" + Tr.t("ЦП"), w: 90, right: true, fmt: r => pct(r.cpu), heat: r => r.cpu / 25 },
            { key: "mem", title: pct(memPct) + "\n" + Tr.t("Память"), w: 110, right: true, fmt: r => size(r.mem), heat: r => r.mem / (mem.total * 0.15) },
            { key: "disk", title: Tr.t("Диск"), w: 100, right: true, fmt: r => r.disk < 0 ? "—" : rate(r.disk) },
            { key: "network", title: Tr.t("Сеть"), w: 75, right: true, fmt: r => "—" }
        ],
        history: [
            { key: "name", title: Tr.t("Имя"), fmt: r => r.name },
            { key: "time", title: Tr.t("Время ЦП"), w: 120, right: true, fmt: r => span(r.time), heat: r => r.time / 3600 },
            { key: "mem", title: Tr.t("Память"), w: 110, right: true, fmt: r => size(r.mem) }
        ],
        users: [
            { key: "name", title: Tr.t("Пользователь"), fmt: r => r.name + " (" + r.count + ")" },
            { key: "cpu", title: pct(cpu.pct) + "\n" + Tr.t("ЦП"), w: 90, right: true, fmt: r => pct(r.cpu), heat: r => r.cpu / 25 },
            { key: "mem", title: "PSS\n" + Tr.t("Память"), w: 110, right: true, fmt: r => userMemory(r.name) }
        ],
        details: [
            { key: "name", title: Tr.t("Имя"), w: 150, fmt: r => r.name },
            { key: "pid", title: Tr.t("ИД"), w: 64, right: true, fmt: r => "" + r.pid },
            { key: "state", title: Tr.t("Состояние"), w: 100, fmt: r => stateNames[r.state] || r.state },
            { key: "user", title: Tr.t("Пользователь"), w: 96, fmt: r => r.user },
            { key: "cpu", title: Tr.t("ЦП"), w: 50, right: true, fmt: r => num(r.cpu, 1) },
            { key: "mem", title: Tr.t("Память"), w: 84, right: true, fmt: r => size(r.mem) },
            { key: "threads", title: Tr.t("Потоки"), w: 62, right: true, fmt: r => "" + r.threads },
            { key: "args", title: Tr.t("Командная строка"), fmt: r => r.args }
        ],
        services: [
            { key: "name", title: Tr.t("Имя"), w: 250, fmt: r => r.name.replace(/\.service$/, "") },
            { key: "pid", title: Tr.t("ИД процесса"), w: 90, right: true, fmt: r => r.pid === "0" ? "" : r.pid },
            { key: "desc", title: Tr.t("Описание"), fmt: r => r.desc },
            { key: "state", title: Tr.t("Состояние"), w: 130, fmt: r => svcStates[r.state] || r.state }
        ],
        startup: [
            { key: "name", title: Tr.t("Имя"), fmt: r => r.name },
            { key: "src", title: Tr.t("Источник"), w: 130, fmt: r => r.src === "system" ? Tr.t("Система") : Tr.t("Пользователь") },
            { key: "on", title: Tr.t("Состояние"), w: 120, fmt: r => r.on === "1" ? Tr.t("Включено") : Tr.t("Отключено") }
        ]
    })

    // при смене вкладки столбцы меняются на мгновение раньше строк
    function cellText(col, row) { try { return col.fmt(row) || ""; } catch (e) { return ""; } }
    function cellHeat(col, row) { try { return Math.max(0, Math.min(1, col.heat(row))) || 0; } catch (e) { return 0; } }

    // ---- действия ----
    function endTask(force) {
        const r = picked;
        if (!r) return;
        const pids = tab === "details" ? [r.pid] : (r.pids || []);
        pids.forEach(p => Quickshell.execDetached(["win11-taskmgr", "kill", "" + p].concat(force ? ["force"] : [])));
        selected = "";
    }
    function service(action) { if (picked) Tools.runInTerminal("sudo systemctl " + action + " " + picked.name); reload.restart(); }
    function toggleStartup() {
        if (!picked) return;
        Quickshell.execDetached(["win11-taskmgr", "startup-toggle", picked.file]);
        reload.restart();
    }

    // ---- графики вкладки "Производительность" ----
    property string dev: "cpu"
    readonly property var devices: {
        const out = [
            { id: "cpu", title: Tr.t("ЦП"), sub: pct(cpu.pct) + (cpu.mhz > 0 ? "  " + num(cpu.mhz / 1000, 2) + " " + Tr.t("ГГц") : ""), max: 100 },
            { id: "mem", title: Tr.t("Память"), sub: num(mem.used / 1048576, 1) + "/" + num(mem.total / 1048576, 1) + " " + Tr.t("ГБ") + " (" + pct(memPct) + ")", max: 100 }
        ];
        disks.forEach((d, i) => out.push({ id: "disk:" + d.name, title: Tr.t("Диск") + " " + i + " (" + d.name + ")", sub: pct(d.busy), max: 100, disk: d }));
        nets.forEach(n => out.push({ id: "net:" + n.name, title: (n.name.indexOf("w") === 0 ? "Wi-Fi" : "Ethernet") + " (" + n.name + ")",
                                     sub: Tr.t("О: ") + rate(n.tx) + "  " + Tr.t("П: ") + rate(n.rx), max: 0, net: n }));
        gpus.forEach((g, i) => out.push({ id: "gpu:" + i, title: Tr.t("Графический процессор") + " " + i, sub: g.name + "  " + pct(g.util), max: 100, gpu: g }));
        return out;
    }
    readonly property var device: { for (let i = 0; i < devices.length; i++) if (devices[i].id === dev) return devices[i]; return devices[0]; }
    readonly property var facts: {
        const d = device;
        if (d.id === "cpu") return [[Tr.t("Использование"), pct(cpu.pct)], [Tr.t("Скорость"), num(cpu.mhz / 1000, 2) + " " + Tr.t("ГГц")], [Tr.t("Процессы"), "" + cpu.procs],
                                    [Tr.t("Потоки"), "" + cpu.threads], [Tr.t("Логических процессоров"), "" + cpu.cores], [Tr.t("Время работы системы"), span(cpu.uptime)]];
        if (d.id === "mem") return [[Tr.t("Используется"), size(mem.used)], [Tr.t("Доступно"), size(mem.avail)], [Tr.t("Кэшировано"), size(mem.cached)],
                                    [Tr.t("Всего"), size(mem.total)], [Tr.t("Файл подкачки"), size(mem.swapUsed) + " / " + size(mem.swapTotal)]];
        if (d.disk) return [[Tr.t("Активное время"), pct(d.disk.busy)], [Tr.t("Скорость чтения"), rate(d.disk.read)], [Tr.t("Скорость записи"), rate(d.disk.write)]];
        if (d.net) return [[Tr.t("Отправка"), rate(d.net.tx)], [Tr.t("Получение"), rate(d.net.rx)]];
        if (d.gpu) return [[Tr.t("Использование"), pct(d.gpu.util)], [Tr.t("Память"), d.gpu.memUsed + " / " + d.gpu.memTotal + " " + Tr.t("МБ")], [Tr.t("Температура"), d.gpu.temp + " °C"]];
        return [];
    }

    component Chart: Canvas {
        id: chart
        property var values: []
        property real ceiling: 100              // 0 - подстраивать под наибольшее значение
        property color stroke: Theme.accent
        property bool grid: true
        onValuesChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            const w = width, h = height, n = root.histLen;
            if (grid) {
                c.strokeStyle = Qt.rgba(chart.stroke.r, chart.stroke.g, chart.stroke.b, 0.18);
                c.lineWidth = 1;
                c.beginPath();
                for (let i = 1; i < 10; i++) { c.moveTo(0, h * i / 10); c.lineTo(w, h * i / 10); }
                for (let i = 1; i < 6; i++) { c.moveTo(w * i / 6, 0); c.lineTo(w * i / 6, h); }
                c.stroke();
            }
            if (values.length < 2) return;
            let max = ceiling;
            if (max <= 0) { max = 1; values.forEach(v => { if (v > max) max = v; }); max *= 1.15; }
            const x = i => w - (values.length - 1 - i) * w / (n - 1);
            const y = v => h - Math.min(1, v / max) * (h - 2) - 1;
            c.beginPath();
            c.moveTo(x(0), h);
            values.forEach((v, i) => c.lineTo(x(i), y(v)));
            c.lineTo(w, h);
            c.closePath();
            c.fillStyle = Qt.rgba(chart.stroke.r, chart.stroke.g, chart.stroke.b, 0.16);
            c.fill();
            c.beginPath();
            values.forEach((v, i) => { if (i === 0) c.moveTo(x(i), y(v)); else c.lineTo(x(i), y(v)); });
            c.strokeStyle = chart.stroke;
            c.lineWidth = 1.5;
            c.stroke();
        }
    }

    // ---- левая колонка вкладок ----
    Rectangle {
        id: rail
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: 232
        color: Theme.footer
        Column {
            anchors { fill: parent; margins: 6 }
            spacing: 2
            Repeater {
                model: root.tabs
                HoverButton {
                    id: tabBtn
                    required property var modelData
                    width: parent.width; implicitHeight: 38
                    highlighted: root.tab === modelData.id
                    onClicked: root.tab = modelData.id
                    Rectangle { visible: tabBtn.highlighted; width: 3; height: 16; radius: 1.5; color: Theme.accent; anchors { left: parent.left; verticalCenter: parent.verticalCenter } }
                    FIcon { id: tabIcon; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } icon: tabBtn.modelData.icon; font.pixelSize: 16 }
                    WText { anchors { left: tabIcon.right; leftMargin: 12; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter } text: tabBtn.modelData.label }
                }
            }
        }
    }

    // ---- заголовок вкладки и действия ----
    Item {
        id: topBar
        anchors { left: rail.right; right: parent.right; top: parent.top; leftMargin: 20; rightMargin: 16 }
        height: 56
        WText {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            font.pixelSize: 18; font.weight: Font.DemiBold
            text: { for (let i = 0; i < root.tabs.length; i++) if (root.tabs[i].id === root.tab) return root.tabs[i].label; return ""; }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6
            Rectangle {
                visible: root.tab !== "perf"
                width: 190; height: 32; radius: 4
                color: Theme.card
                border.color: find.activeFocus ? Theme.accent : Theme.border
                FIcon { id: findIcon; anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } icon: Icons.search; font.pixelSize: 13; color: Theme.subtext }
                TextInput {
                    id: find
                    anchors { left: findIcon.right; leftMargin: 7; right: parent.right; rightMargin: 8; top: parent.top; bottom: parent.bottom }
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Theme.text; selectionColor: Theme.accent
                    font.family: Config.fontFamily; font.pixelSize: 12
                    onTextChanged: root.filter = text.trim()
                    WText { visible: find.text === ""; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; color: Theme.subtext; text: Tr.t("Поиск") }
                }
            }
            PushButton { label: Tr.t("Запустить новую задачу"); visible: root.tab === "procs" || root.tab === "details"; onClicked: Ui.toggle("run") }
            PushButton {
                label: Tr.t("Завершить задачу")
                visible: root.tab === "procs" || root.tab === "details"
                enabled: root.picked !== null
                onClicked: mouse => root.endTask(mouse.button === Qt.RightButton)
            }
            PushButton {
                label: Tr.t("Экономия ввода-вывода") + " · " + Tr.t("Включить")
                visible: root.tab === "procs"
                enabled: root.picked !== null && root.picked.key.indexOf("a:") === 0
                onClicked: Tools.runInTerminal("win11-taskmgr efficiency " + root.picked.pids[0] + " on")
            }
            PushButton {
                label: Tr.t("Экономия ввода-вывода") + " · " + Tr.t("Отключить")
                visible: root.tab === "procs"
                enabled: root.picked !== null && root.picked.key.indexOf("a:") === 0
                onClicked: Tools.runInTerminal("win11-taskmgr efficiency " + root.picked.pids[0] + " off")
            }
            PushButton { label: Tr.t("Запустить"); visible: root.tab === "services"; enabled: root.picked !== null && root.picked.state !== "active"; onClicked: root.service("start") }
            PushButton { label: Tr.t("Остановить"); visible: root.tab === "services"; enabled: root.picked !== null && root.picked.state === "active"; onClicked: root.service("stop") }
            PushButton { label: Tr.t("Перезапустить"); visible: root.tab === "services"; enabled: root.picked !== null && root.picked.state === "active"; onClicked: root.service("restart") }
            PushButton {
                label: root.picked && root.picked.on === "1" ? Tr.t("Отключить") : Tr.t("Включить")
                visible: root.tab === "startup"
                enabled: root.picked !== null
                onClicked: root.toggleStartup()
            }
        }
    }

    // ---- таблица (все вкладки, кроме графиков) ----
    Item {
        id: table
        visible: root.tab !== "perf"
        clip: true
        anchors { left: rail.right; right: parent.right; top: topBar.bottom; bottom: parent.bottom; leftMargin: 12; rightMargin: 8; bottomMargin: 8 }
        readonly property var cols: root.columns[root.tab] || []
        readonly property real fixed: { let s = 0; cols.forEach(c => s += c.w || 0); return s; }
        readonly property int flexible: cols.filter(c => !c.w).length
        function widthOf(c) { return c.w || Math.max(120, (width - fixed - 14) / Math.max(1, flexible)); }

        Row {
            id: header
            height: 42
            Repeater {
                model: table.cols
                HoverButton {
                    id: headCell
                    required property var modelData
                    readonly property bool current: root.sort[root.tab] && root.sort[root.tab][0] === modelData.key
                    implicitWidth: table.widthOf(modelData); implicitHeight: header.height
                    radius: 0
                    onClicked: root.sortBy(modelData.key)
                    WText {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: headCell.modelData.right ? Text.AlignRight : Text.AlignLeft
                        font.pixelSize: 12; lineHeight: 0.95
                        color: headCell.current ? Theme.text : Theme.subtext
                        text: headCell.modelData.title
                    }
                    Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.border; opacity: 0.6 }
                }
            }
        }
        Rectangle { anchors { left: parent.left; right: parent.right; top: header.bottom } height: 1; color: Theme.border }
        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; topMargin: 1 }
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // список обновляется каждые две секунды: прокрутка при этом должна оставаться на месте
            property var rows: root.rowsNow
            Component.onCompleted: model = rows
            onRowsChanged: { const y = contentY; model = rows; contentY = Math.max(0, Math.min(y, contentHeight - height)); }
            delegate: Rectangle {
                id: rowItem
                required property var modelData
                readonly property bool isHead: modelData.head !== undefined
                readonly property bool chosen: !isHead && modelData.key === root.selected
                width: list.width
                height: isHead ? 34 : 30
                radius: 4
                color: chosen ? Theme.pressed : rowArea.containsMouse && !isHead ? Theme.hover : "transparent"
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: if (!rowItem.isHead) root.selected = rowItem.modelData.key
                    onDoubleClicked: if (root.tab === "startup") root.toggleStartup()
                }
                WText {
                    visible: rowItem.isHead
                    anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 6 }
                    font.pixelSize: 13; font.weight: Font.DemiBold
                    text: rowItem.isHead ? rowItem.modelData.head : ""
                }
                Row {
                    visible: !rowItem.isHead
                    anchors.fill: parent
                    Repeater {
                        model: rowItem.isHead ? [] : table.cols
                        Rectangle {
                            id: cell
                            required property var modelData
                            // как в Windows: чем больше расход, тем гуще подложка ячейки
                            readonly property real heat: modelData.heat ? root.cellHeat(modelData, rowItem.modelData) : 0
                            width: table.widthOf(modelData); height: rowItem.height
                            color: modelData.heat ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.06 + 0.34 * heat) : "transparent"
                            IconImage {
                                id: appIcon
                                visible: root.tab === "procs" && cell.modelData.key === "name" && !!rowItem.modelData.icon
                                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                implicitSize: 20
                                source: visible ? rowItem.modelData.icon : ""
                            }
                            WText {
                                anchors { fill: parent; leftMargin: appIcon.visible ? 34 : 10; rightMargin: 10 }
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: cell.modelData.right ? Text.AlignRight : Text.AlignLeft
                                font.pixelSize: 12
                                text: root.cellText(cell.modelData, rowItem.modelData)
                            }
                        }
                    }
                }
            }
        }
        WText {
            anchors.centerIn: list
            visible: list.count === 0
            color: Theme.subtext
            text: root.frames === 0 && (root.tab === "procs" || root.tab === "details" || root.tab === "users" || root.tab === "history") ? Tr.t("Собираю сведения…")
                : root.tab === "startup" ? Tr.t("В автозагрузке ничего нет") : Tr.t("Ничего не найдено")
        }
    }

    // ---- производительность ----
    Item {
        visible: root.tab === "perf"
        anchors { left: rail.right; right: parent.right; top: topBar.bottom; bottom: parent.bottom; leftMargin: 12; rightMargin: 16; bottomMargin: 12 }
        ListView {
            id: devList
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 220
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.devices
            delegate: HoverButton {
                id: devBtn
                required property var modelData
                width: devList.width; implicitHeight: 62
                highlighted: root.dev === modelData.id
                onClicked: root.dev = modelData.id
                Rectangle {
                    id: mini
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    width: 62; height: 42
                    color: "transparent"; border.color: Theme.accent
                    Chart { anchors { fill: parent; margins: 1 } grid: false; values: root.hist[devBtn.modelData.id] || []; ceiling: devBtn.modelData.max }
                }
                Column {
                    anchors { left: mini.right; leftMargin: 10; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    WText { width: parent.width; text: devBtn.modelData.title }
                    WText { width: parent.width; font.pixelSize: 11; color: Theme.subtext; text: devBtn.modelData.sub }
                }
            }
        }
        Item {
            anchors { left: devList.right; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 18 }
            WText { id: devTitle; font.pixelSize: 22; text: root.device.title }
            WText {
                anchors { right: parent.right; left: devTitle.right; leftMargin: 12; baseline: devTitle.baseline }
                horizontalAlignment: Text.AlignRight
                color: Theme.subtext
                text: root.device.id === "cpu" ? root.cpu.name : root.device.gpu ? root.device.gpu.name : ""
            }
            WText { id: scale; anchors { top: devTitle.bottom; topMargin: 8 } font.pixelSize: 11; color: Theme.subtext; text: root.device.max > 0 ? Tr.t("% использования") : Tr.t("Скорость обмена") }
            WText { anchors { right: parent.right; baseline: scale.baseline } font.pixelSize: 11; color: Theme.subtext; text: root.device.max > 0 ? "100%" : "" }
            Rectangle {
                id: frame
                anchors { left: parent.left; right: parent.right; top: scale.bottom; topMargin: 4 }
                height: Math.max(140, parent.height - 230)
                color: "transparent"; border.color: Theme.accent
                Chart { anchors { fill: parent; margins: 1 } values: root.hist[root.device.id] || []; ceiling: root.device.max }
            }
            WText { anchors { top: frame.bottom; topMargin: 3 } font.pixelSize: 11; color: Theme.subtext; text: Tr.t("2 минуты") }
            WText { anchors { right: parent.right; top: frame.bottom; topMargin: 3 } font.pixelSize: 11; color: Theme.subtext; text: "0" }
            Flow {
                anchors { left: parent.left; right: parent.right; top: frame.bottom; topMargin: 30 }
                spacing: 22
                Repeater {
                    model: root.facts
                    Column {
                        required property var modelData
                        WText { font.pixelSize: 11; color: Theme.subtext; text: modelData[0] }
                        WText { font.pixelSize: 18; text: modelData[1] }
                    }
                }
            }
        }
    }
}
