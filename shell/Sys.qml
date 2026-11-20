pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Wi-Fi, Bluetooth, яркость, громкость, ночной свет.
Singleton {
    id: root
    property bool wifi: true              // радиомодуль Wi-Fi включён
    property bool hasWifi: false          // в компьютере есть адаптер Wi-Fi
    // Оборудование определяется при запуске и перепроверяется вместе с сетью (USB-адаптер можно воткнуть позже).
    property bool hasTouchpad: false      // есть сенсорная панель
    property bool hasBluetooth: false     // есть адаптер Bluetooth
    property bool hwKnown: false          // проверка уже прошла
    property string net: "none"           // чем подключены: "ethernet", "wifi", "none"
    property bool online: true            // есть ли выход в интернет (проверяется раз в минуту)
    // нет подключения - кабель с крестиком; подключение есть, а интернета нет - глобус с запретом
    readonly property string netIcon: net === "none" ? Icons.netOff
                                    : !online ? Icons.globeOff
                                    : net === "wifi" ? Icons.wifi : Icons.ethernet
    readonly property string netText: net === "none" ? Tr.t("Нет подключения")
                                    : !online ? Tr.t("Без доступа к интернету")
                                    : net === "wifi" ? "Wi-Fi" : "Ethernet"
    onNetChanged: probe.running = true
    // Уровень заряда Bluetooth-устройств (наушники, мышь, клавиатура)
    property var btDevices: []
    Process {
        id: btProc
        command: ["sh", "-c", "command -v win11-bt-battery >/dev/null 2>&1 && exec win11-bt-battery || exec bash /etc/win11-shell/scripts/bt-battery.sh 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            id: btOut
            onStreamFinished: {
                try {
                    const raw = btOut.text.trim();
                    if (raw !== '' && raw.charAt(0) === '[') root.btDevices = JSON.parse(raw);
                    else root.btDevices = [];
                } catch (e) { root.btDevices = []; }
            }
        }
    }
    Timer {
        interval: 10000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: { if (!btProc.running) btProc.running = true; }
    }

    property bool canSuspend: true
    property bool canHibernate: false     // выясняется при запуске у systemd-logind
    property bool bluetooth: false
    property real brightness: -1      // -1: подсветки нет (обычный ПК)
    // Ночной свет: вручную или по расписанию (Store.nightAuto, nightFrom, nightTo)
    function minutes(s) {
        const m = /^(\d{1,2}):(\d{2})$/.exec(s || "");
        return m ? (parseInt(m[1]) % 24) * 60 + parseInt(m[2]) % 60 : -1;
    }
    readonly property bool nightScheduled: {
        if (!Store.nightAuto) return false;
        const a = minutes(Store.nightFrom), b = minutes(Store.nightTo);
        if (a < 0 || b < 0 || a === b) return false;
        const t = Ui.now.getHours() * 60 + Ui.now.getMinutes();
        return a < b ? (t >= a && t < b) : (t >= a || t < b);
    }
    property string nightOverride: ""     // "", "on", "off" - ручное переключение до следующей смены по расписанию
    onNightScheduledChanged: nightOverride = ""
    readonly property bool night: nightOverride === "on" || (nightOverride === "" && nightScheduled)
    function toggleNight() { nightOverride = night ? "off" : "on"; }
    property bool nightGate: true

    readonly property var sink: Pipewire.defaultAudioSink
    // звуковой сервер может подняться позже оболочки: до этого устройства нет вовсе
    readonly property bool hasAudio: !!sink && !!sink.audio
    readonly property real volume: hasAudio ? sink.audio.volume : 0
    readonly property bool muted: hasAudio ? sink.audio.muted : true
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    function setVolume(v) { if (hasAudio) { sink.audio.muted = false; sink.audio.volume = v; } }
    function toggleMute() { if (hasAudio) sink.audio.muted = !sink.audio.muted; }
    function setWifi(on) { wifi = on; Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]); }
    function setBluetooth(on) { bluetooth = on; Quickshell.execDetached(["bluetoothctl", "power", on ? "on" : "off"]); }
    function setBrightness(v) {
        brightness = v;
        Quickshell.execDetached(["brightnessctl", "-q", "set", Math.max(1, Math.round(v * 100)) + "%"]);
    }

    Process {
        id: poll
        command: ["sh", "-c",
            "nmcli -t radio wifi 2>/dev/null | head -n1; echo '|'; " +
            "timeout 1 bluetoothctl show 2>/dev/null | grep -c 'Powered: yes'; echo '|'; " +
            "brightnessctl -m 2>/dev/null | head -n1 | cut -d, -f4; echo '|'; " +
            "nmcli -t -f TYPE,STATE device 2>/dev/null; echo '|'; " +
            // оборудование: Wi-Fi, сенсорная панель (метка udev или название устройства), Bluetooth
            "w=0; for d in /sys/class/net/*/wireless /sys/class/net/*/phy80211; do [ -e \"$d\" ] && w=1; done; " +
            "t=0; grep -qs 'ID_INPUT_TOUCHPAD=1' /run/udev/data/* 2>/dev/null && t=1; " +
            "[ $t = 0 ] && grep -qiE 'Name=.*(touchpad|trackpad|synaptics|glidepoint)' /proc/bus/input/devices 2>/dev/null && t=1; " +
            "b=0; for d in /sys/class/bluetooth/hci*; do [ -e \"$d\" ] && b=1; done; echo \"$w $t $b\""]
        stdout: StdioCollector {
            id: pollOut
            onStreamFinished: {
                const p = pollOut.text.split("|");
                if (p.length < 3) return;
                root.wifi = p[0].trim() !== "disabled";
                root.bluetooth = parseInt(p[1].trim()) > 0;
                const b = parseInt(p[2].trim());
                root.brightness = isNaN(b) ? -1 : b / 100;
                const dev = (p[3] || "").split("\n").map(l => l.trim());
                const hw = (p[4] || "").trim().split(/\s+/);
                // Wi-Fi: адаптер виден ядру (/sys/class/net/*/wireless) или NetworkManager
                root.hasWifi = dev.some(l => l.startsWith("wifi:")) || hw[0] === "1";
                root.hasTouchpad = hw[1] === "1";
                root.hasBluetooth = hw[2] === "1";
                root.hwKnown = hw.length >= 3;
                // провод без Wi-Fi - значок компьютера; есть связь по Wi-Fi - значок Wi-Fi
                root.net = dev.indexOf("wifi:connected") >= 0 ? "wifi"
                         : dev.indexOf("ethernet:connected") >= 0 ? "ethernet" : "none";
            }
        }
    }
    Timer {
        interval: Ui.flyout === "quick" ? 3000 : 20000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: poll.running = true
    }

    Process { command: ["gammastep", "-O", "" + Store.nightTemp]; running: root.night && root.nightGate }
    // сменили интенсивность - перезапускаем с новой температурой
    Connections { target: Store; function onNightTempChanged() { if (root.night) { root.nightGate = false; regate.restart(); } } }
    Timer { id: regate; interval: 400; onTriggered: root.nightGate = true }

    // ---- Смена обоев (Store.wallMode). Вся работа - один короткий сценарий раз в минуту или раз в день.
    readonly property string wallWant: {
        const n = Ui.now;
        const day = n.getFullYear() + "-" + (n.getMonth() + 1) + "-" + n.getDate();
        return Store.wallMode === "fixed" ? ""
             : Store.wallMode + ":" + Store.wallDir + ":" + day + (Store.wallMode === "minute" ? " " + n.getHours() + ":" + n.getMinutes() : "");
    }
    property string wallError: ""
    function wallTick() {
        if (wallWant === "" || wallWant === Store.wallKey || wallPick.running) return;
        wallPick.want = wallWant;
        wallPick.command = ["sh", "-c", wallScript, "sh", Store.wallMode, Store.wallDir];
        wallPick.running = true;
    }
    onWallWantChanged: wallTick()
    // если картинка не получена (нет сети, пустая папка) - повтор раз в минуту
    Timer { interval: 60000; repeat: true; running: Store.wallMode !== "fixed"; triggeredOnStart: true; onTriggered: root.wallTick() }
    readonly property string wallScript:
        "mode=\"$1\"; dir=\"${2:-$HOME/Pictures/Wallpapers}\"; cache=\"$HOME/.cache/win11-shell\"; mkdir -p \"$cache\"\n" +
        "if [ \"$mode\" = web ]; then\n" +
        "  f=\"$cache/web-$(date +%F).jpg\"\n" +
        "  if [ ! -s \"$f\" ]; then\n" +
        "    u=\"$(curl -s -m 15 'https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US' | sed -n 's/.*\"url\":\"\\([^\"]*\\)\".*/\\1/p' | sed 's/\\\\u0026/\\&/g')\"\n" +
        "    [ -n \"$u\" ] && curl -s -L -m 60 -o \"$f.part\" \"https://www.bing.com$u\"\n" +
        "    [ -s \"$f.part\" ] || curl -s -L -m 60 -o \"$f.part\" 'https://picsum.photos/1920/1080'\n" +
        "    if [ \"$(wc -c < \"$f.part\" 2>/dev/null || echo 0)\" -gt 30000 ]; then mv \"$f.part\" \"$f\"; else rm -f \"$f.part\"; echo 'ERR нет связи с интернетом'; exit 0; fi\n" +
        "    find \"$cache\" -name 'web-*.jpg' ! -name \"${f##*/}\" -delete\n" +
        "  fi\n" +
        "  echo \"$f\"; exit 0\n" +
        "fi\n" +
        "[ -d \"$dir\" ] || { echo \"ERR нет папки $dir\"; exit 0; }\n" +
        "list=\"$(find \"$dir\" -maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort)\"\n" +
        "n=\"$(printf '%s\\n' \"$list\" | grep -c .)\"\n" +
        "[ \"$n\" -gt 0 ] || { echo \"ERR в папке $dir нет картинок\"; exit 0; }\n" +
        "if [ \"$mode\" = minute ]; then t=$(( $(date +%s) / 60 )); else t=$(( ($(date +%s) + $(date +%z | sed 's/^+//; s/^\\(-\\{0,1\\}\\)0*\\([0-9]\\)/\\1\\2/') * 36) / 86400 )); fi\n" +
        "printf '%s\\n' \"$list\" | sed -n \"$(( t % n + 1 ))p\"\n"
    // Картинка экрана блокировки для режимов "web" и "folder" - тем же сценарием.
    // Из папки берётся новая при каждой блокировке, из интернета - одна на день.
    function lockTick() {
        if ((Store.lockMode !== "web" && Store.lockMode !== "folder") || lockPick.running) return;
        lockPick.command = ["sh", "-c", wallScript, "sh", Store.lockMode === "web" ? "web" : "minute", Store.wallDir];
        lockPick.running = true;
    }
    Connections {
        target: Store
        function onLockModeChanged() { root.lockTick(); }
    }
    Connections {
        target: Ui
        function onLockedChanged() { if (!Ui.locked) root.lockTick(); }
    }
    Timer { interval: 3600000; repeat: true; running: Store.lockMode === "web"; onTriggered: root.lockTick() }
    Timer { interval: 20000; running: true; onTriggered: root.lockTick() }
    Process {
        id: lockPick
        stdout: StdioCollector {
            id: lockOut
            onStreamFinished: {
                const line = lockOut.text.trim();
                if (line !== "" && line.indexOf("ERR ") !== 0) Store.set("lockAuto", line);
            }
        }
    }
    Process {
        id: wallPick
        property string want: ""
        stdout: StdioCollector {
            id: wallOut
            onStreamFinished: {
                const line = wallOut.text.trim();
                if (line.indexOf("ERR ") === 0) { root.wallError = line.slice(4); return; }
                if (line === "") return;
                root.wallError = "";
                Store.wallAuto = line;
                Store.set("wallKey", wallPick.want);
            }
        }
    }

    // Проверка выхода в интернет: любой ответ от одного из двух сайтов считается успехом.
    Process {
        id: probe
        command: ["sh", "-c",
            "curl -s -m 4 -o /dev/null http://ya.ru || curl -s -m 4 -o /dev/null http://connectivitycheck.gstatic.com/generate_204; echo $?"]
        stdout: StdioCollector { id: probeOut; onStreamFinished: root.online = probeOut.text.trim() === "0" }
    }
    Timer { interval: 60000; running: root.net !== "none"; repeat: true; triggeredOnStart: true; onTriggered: probe.running = true }

    // Автопроверка: умеет ли этот компьютер спать и уходить в гибернацию.
    // logind сам проверяет, хватает ли подкачки на диске и поддержку в ядре.
    Process {
        running: true
        command: ["sh", "-c",
            "c() { busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager \"$1\" 2>/dev/null; }; " +
            "c CanSuspend; echo '|'; c CanHibernate"]
        stdout: StdioCollector {
            id: canOut
            onStreamFinished: {
                const p = canOut.text.split("|");
                if (p.length < 2) return;
                root.canSuspend = p[0].indexOf('"yes"') >= 0;
                root.canHibernate = p[1].indexOf('"yes"') >= 0;
            }
        }
    }
}
