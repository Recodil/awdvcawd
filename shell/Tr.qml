pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Перевод надписей оболочки. Исходные надписи русские; для другого языка строка ищется
// в словаре i18n/<код>.json ("русская строка": "перевод"). Нет перевода - остаётся русская.
// Свой словарь можно положить в ~/.config/win11-shell/i18n/<код>.json, он важнее встроенного.
Singleton {
    id: root

    // "ru", "en", "de" … из выбранного в "Параметрах" языка, иначе из языка системы
    readonly property string code: {
        const name = Store.lang !== "" ? Store.lang : Qt.locale().name;
        const two = name.split(/[_.@-]/)[0].toLowerCase();
        return two === "c" || two === "posix" || two === "" ? "en" : two;
    }
    readonly property bool russian: code === "ru"
    property var dict: ({})
    // перевод → исходная строка: нужен там, где по надписи ищут в русских таблицах
    property var back: ({})

    function t(s) {
        const v = dict[s];
        return v === undefined || v === "" ? s : v;
    }
    function orig(s) {
        const v = back[s];
        return v === undefined ? s : v;
    }
    function use(d) {
        const b = {};
        for (const k in d) b[d[k]] = k;
        back = b;
        dict = d;
    }

    onCodeChanged: load()
    Component.onCompleted: load()
    function load() {
        if (russian) { use({}); return; }
        // язык без своего словаря получает английский
        reader.command = ["sh", "-c",
            "cat \"$HOME/.config/win11-shell/i18n/$1.json\" 2>/dev/null || cat \"$2/$1.json\" 2>/dev/null || cat \"$2/en.json\"",
            "sh", code, Qt.resolvedUrl("i18n").toString().replace("file://", "")];
        reader.running = true;
    }
    Process {
        id: reader
        stdout: StdioCollector {
            id: text
            onStreamFinished: {
                try { root.use(JSON.parse(text.text)); }
                catch (e) { console.warn("перевод не прочитан:", e); root.use({}); }
            }
        }
    }
}
