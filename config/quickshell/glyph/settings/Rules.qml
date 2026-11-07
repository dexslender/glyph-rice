pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// house rules: ~/.config/demonshot/rules.json — единственный источник правды для настроек.
// Правка из Settings пишет файл (writeAdapter) и сама зовёт нужный apply. applyAll зовёт только shell.qml на старте:
// лок (lock.qml) тоже читает Theme → Rules, но ничего не применяет
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/demonshot"
    readonly property alias store: adapter

    // восемь цветов в порядке Theme: void crypt wine plum rose crimson ash bone
    readonly property var palettes: [
        { name: "Demon's Shot", what: "blood & bone", c: ["#0D0B0E", "#151116", "#2B1820", "#4A2236", "#B8487A", "#C7303D", "#7A6870", "#E9DFDD"] },
        { name: "Absinthe", what: "green fairy", c: ["#0B0D0B", "#121612", "#1E2A1F", "#2F4630", "#A9B85A", "#7CC24A", "#6E7A6C", "#E3E6D8"] },
        { name: "Nightshade", what: "poison bloom", c: ["#0C0B10", "#131119", "#221A30", "#3A2852", "#8E6BD8", "#B04BD6", "#706A80", "#E4DFEA"] },
        { name: "Holy Water", what: "cold blessing", c: ["#0A0C10", "#11151B", "#1A2433", "#263C57", "#5E9BD1", "#3F7FE0", "#687687", "#DDE4EA"] },
        { name: "Rust", what: "old iron", c: ["#0E0B09", "#17120F", "#2E1D14", "#4D2E1C", "#D08A3E", "#D1532A", "#7E6E62", "#EADFD3"] },
        { name: "Gilded", what: "altar gold", c: ["#0D0C0A", "#16140F", "#2E2716", "#4A3D1E", "#B88A4A", "#D9A43A", "#7A7262", "#EDE5D3"] },
        { name: "Ghost", what: "no color left", c: ["#0C0C0D", "#141416", "#26262A", "#3A3A40", "#9A9AA6", "#E9E9EE", "#6E6E76", "#E2E2E6"] }
    ]
    readonly property var pal: palettes[adapter.palette] ?? palettes[0]

    // ждём файл при создании синглтона: иначе первый, кто прочтёт store (glyph на старте), получит умолчания, а не rules.json
    Component.onCompleted: file.waitForJob()

    FileView {
        id: file
        path: root.dir + "/rules.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: this.reload()
        // запись — раз в конце хода: writeAdapter() на каждое поле подряд путает соседние (пресет меняет четыре разом)
        onAdapterUpdated: Qt.callLater(file.writeAdapter)
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) this.writeAdapter(); } // первый запуск: файл с умолчаниями

        // умолчания — как в текущей конфигурации niri, чтобы первый запуск ничего не сдвинул
        JsonAdapter {
            id: adapter
            // Display
            property real monScale: 0      // 0 — auto, решает niri
            property int refresh: 120
            property int brightness: 62
            property bool night: false
            property int warmth: 4300
            property int gaps: 15
            property int border: 2
            property int rounding: 0
            property bool blur: true
            property bool shadow: true
            property bool motion: true
            property bool ultra: false   // режим ultra (setMode 0): 60 Гц и без украшений поверх настроек
            property bool game: false    // игровой, как в caelestia: без анимаций, blur, теней, зазоров и скруглений, tearing (Theme.apply)
            // Colors
            property int palette: 0
            property bool paintKitty: true
            // Input — значения по умолчанию для niri
            property int kbSwitch: 0      // индекс в switches
            property int repeatDelay: 250
            property int repeatRate: 35
            property bool natural: true
            property bool tap: true
            property bool typingOff: false
            property int scroll: 30       // % — scroll_factor 0.3
            property int sens: 0          // -100…100 → sensitivity -1…1
            property bool flat: false
            // Idle: минуты, 0 — никогда
            property int lockAfter: 3
            property int dpmsAfter: 5
            property int sleepAfter: 10
            property bool hibernate: true // suspend-then-hibernate
            // System
            property bool roman: true
            // Notices. Тишина (её же ставят обереги): обычные уведомления не показываются, критические — всегда
            property bool dnd: false
            property int noteTime: 6      // с, если приложение не задало своё; 0 — ждут, пока не смахнут
            property int noteDeck: 5      // сколько видно в колоде
        }
    }

    // kitty: include-файл с цветами палитры (kitty.conf подключает его), SIGUSR1 — перечитать конфиг
    FileView { id: kitty; path: root.dir + "/kitty.conf"; printErrors: false }

    function monitor() {}

    property var mon: ({ name: "", w: 0, h: 0, scale: 1, rates: [] })
    readonly property var rates: mon.rates.length ? mon.rates : [60, 120]
    readonly property int refreshHz: rates.reduce((a, b) => Math.abs(b - store.refresh) < Math.abs(a - store.refresh) ? b : a)
    readonly property real scale: store.monScale || mon.scale || 1 // что стоит на деле, и при auto
    readonly property var scales: ["auto", "1", "1.25", "1.5", "2"]
    readonly property int scaleIdx: store.monScale ? scales.indexOf(String(store.monScale)) : 0
    function setScale(i) { store.monScale = i ? +scales[i] : 0; monitor(); }
    function windows() {}
    // ponytail: только вкл/выкл; slam/snap — переопределять кривые из animations.lua
    function motion() {}
    readonly property var switches: [["alt+shift", "grp:alt_shift_toggle"], ["caps", "grp:caps_toggle"], ["ctrl+shift", "grp:ctrl_shift_toggle"]]
    function input() {}
    // гибернация есть не везде (нужен swap под resume, zram не годится) — спрашиваем logind. Нет — обычный сон, пункты
    // гибернации прячутся. Ответ пришёл после idle() — переписать конфиг (лок idle() не зовёт, его это не касается)
    property bool canHibernate: false
    property bool idleDone: false
    readonly property bool hibernateOn: store.hibernate && canHibernate
    onCanHibernateChanged: if (idleDone) idle()
    Process {
        running: true
        command: ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "CanSuspendThenHibernate"]
        stdout: StdioCollector { onStreamFinished: root.canHibernate = text.includes('"yes"') }
    }
    function idle() {
        idleDone = true;
        const s = store;
        const lock = s.lockAfter ? `timeout ${s.lockAfter * 60} '$HOME/.config/quickshell/rice/rice lock'` : "";
        const dpms = s.dpmsAfter ? `timeout ${s.dpmsAfter * 60} 'niri msg action power-off-monitors' resume 'niri msg action power-on-monitors'` : "";
        const sleep = s.sleepAfter ? `timeout ${s.sleepAfter * 60} '${hibernateOn ? "systemctl suspend-then-hibernate" : "systemctl suspend"}'` : "";
        Quickshell.execDetached(["sh", "-c", `pkill -x swayidle 2>/dev/null; exec swayidle -w ${lock} ${dpms} ${sleep}`]);
    }
    function brightness() { Quickshell.execDetached(["brightnessctl", "-q", "set", store.brightness + "%"]); }
    function night() {
        Quickshell.execDetached(["sh", "-c", store.night ? `pkill -x gammastep 2>/dev/null; exec gammastep -O ${store.warmth}` : "pkill -x gammastep"]);
    }

    // палитра: Theme перекрашивается сам (биндинги на pal), здесь — то, что живёт вне шелла
    function paint() {
        const c = pal.c;
        if (store.paintKitty) {
            kitty.setText([
                ["foreground", c[7]], ["background", c[1]], ["cursor", c[7]], ["cursor_text_color", c[1]],
                ["selection_foreground", c[7]], ["selection_background", c[3]], ["url_color", c[4]],
                ["active_border_color", c[5]], ["inactive_border_color", c[2]],
                ["active_tab_foreground", c[7]], ["active_tab_background", c[5]],
                ["inactive_tab_foreground", c[6]], ["inactive_tab_background", c[1]], ["tab_bar_background", c[0]]
            ].map(([k, v]) => `${k} ${v}`).join("\n") + "\n");
            Quickshell.execDetached(["pkill", "-USR1", "-x", "kitty"]);
        }
    }

    // режимы отображения: ultra сверху — 60 Гц и без анимаций, blur и теней,
    // поверх своих настроек, не трогая их: вышел — вернулись. 0 ultra · 1 saver · 2 balanced · 3 performance.
    // Окна (blur, тени) применяет вызвавший: demonshot — windows(), glyph — Theme.apply() (windows() снял бы его скругление)
    readonly property var modes: [{ name: "ultra", short: "ULT", what: `ultra · ${rates[0]} hz · still` }]
    readonly property int mode: 0
    readonly property int modeCount: 1
    function setMode(i) {
        store.ultra = true;
    }
    // что стоит на деле: ultra перекрывает настройки — самые низкие герцы экрана, иначе ближайшие к выбранным
    readonly property int hz: store.ultra ? rates[0] : refreshHz
    readonly property bool moving: store.motion && !store.ultra && !store.game
    readonly property bool blurOn: store.blur && !store.ultra && !store.game
    readonly property bool shadowOn: store.shadow && !store.ultra && !store.game

    // старт шелла: всё, кроме яркости (её крутят клавиши и OSD, перетирать на каждом запуске нельзя)
    function applyAll() {
        monitor(); windows(); motion(); night(); paint(); input(); idle();
    }
}
