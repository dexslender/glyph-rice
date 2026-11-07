pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.services
import qs.settings

// то, что трогают бар, быстрые настройки, Glyph и лок: звук, яркость, раскладка, запись, ночник, авиарежим, кофеин, vpn
Singleton {
    id: root

    // deck (панель снизу) открыта — SysStats нужен подробный опрос, как на пустом воркспейсе (Home)
    property bool deckOpen: false
    // пикер обоев открыт — дом меняет обои сразу, без волны: её уже показал пикер
    property bool wallOpen: false

    // ---- звук ----
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var mic: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.mic] }
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? true
    readonly property bool micOn: !(mic?.audio?.muted ?? true)
    function setVol(v) {
        if (!sink?.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, v));
    }
    // микрофон кто-то слушает — отдельно от записи
    PwNodeLinkTracker { id: micUse; node: root.mic }
    readonly property bool micInUse: micUse.linkGroups.length > 0

    // ---- яркость: общий с demonshot Backlight (устройство ищет brightnessctl) ----
    readonly property real bri: Backlight.value
    readonly property bool hasBri: !!Backlight.dev // нет подсветки (ПК с монитором) — регуляторов яркости нет
    function setBri(v) { Backlight.set(v); }
    Binding { target: Backlight; property: "steps"; value: Theme.state.briSteps }

    // ---- раскладка: niri owns keyboard layout; keep the UI stable until its layout model is available ----
    property string kbd: ""
    readonly property string layout: kbd.slice(0, 2).toLowerCase() // "English (US)" → en

    // ---- запись и авиарежим: запись управляется процессом, авиарежим — опросом. Ночник — общий с demonshot, в его rules.json
    property bool rec: false
    readonly property bool recording: rec || recorder.running || recDelay.running
    readonly property bool night: Rules.store.night
    property bool air: false
    property bool stopRequested: false
    Process {
        id: poll
        command: ["sh", "-c", "pgrep -f '^gpu-screen-recorder( |$)' >/dev/null && echo rec; "
                            + "rfkill -rno SOFT | grep -qv '^blocked' || echo air"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.rec = text.includes("rec");
                root.air = text.includes("air");
            }
        }
    }
    Timer { running: true; repeat: true; interval: 3000; triggeredOnStart: true; onTriggered: poll.running = true }

    // настройки записи из Theme.state (quick/Rec) → флаги gpu-screen-recorder; их же берёт скриншотилка
    readonly property var recFps: [30, 60, 120]
    function recArgs() {
        const st = Theme.state;
        const a = ["", "default_output", "default_input", "default_output|default_input"][st.recAudio];
        return `-f ${st.recFps} -q ${["medium", "high", "very_high", "ultra"][st.recQuality]} -cursor ${st.recCursor ? "yes" : "no"}` + (a ? ` -a "${a}"` : "");
    }

    Process {
        id: recorder
        stderr: StdioCollector {
            id: recorderError
            waitForEnd: true
        }
        onExited: function (exitCode) {
            root.rec = false;
            poll.running = true;
            const error = (recorderError.text || "").trim();
            if (exitCode !== 0 && !root.stopRequested)
                Quickshell.execDetached(["notify-send", "-a", "glyph", "Recording failed", error || `gpu-screen-recorder exited with ${exitCode}`]);
            root.stopRequested = false;
        }
    }

    Timer {
        id: recDelay
        property int seconds: 0
        interval: seconds * 1000
        onTriggered: root.launchRecording()
    }

    Process {
        id: stopRecorder
        command: ["pkill", "-INT", "-f", "^gpu-screen-recorder( |$)"]
        onExited: function (exitCode) {
            if (exitCode !== 0)
                Quickshell.execDetached(["notify-send", "-a", "glyph", "Recording", "No active recording process was found"]);
            poll.running = true;
        }
    }

    // segundo clic — stop. niri recording is full-screen only.
    function toggleRec() {
        if (stopRecorder.running)
            return;
        if (recDelay.running) {
            recDelay.stop();
            return;
        }
        if (recording) {
            root.stopRequested = true;
            stopRecorder.running = true;
            return;
        }
        root.launchRecording();
    }
    function startRecording(delaySeconds) {
        if (recording || stopRecorder.running)
            return;
        recDelay.seconds = Math.max(0, delaySeconds || 0);
        if (recDelay.seconds)
            recDelay.start();
        else
            root.launchRecording();
    }
    function launchRecording() {
        recorder.command = ["sh", "-c", `exec gpu-screen-recorder -w screen ${recArgs()} -o "$(xdg-user-dir VIDEOS)/rec-$(date +%F_%H-%M-%S).mp4"`];
        recorder.running = true;
    }
    function toggleNight() { Rules.store.night = !night; Rules.night(); }
    function toggleAir() { Quickshell.execDetached(["rfkill", air ? "unblock" : "block", "all"]); air = !air; }
    function toggleMic() { if (mic?.audio) mic.audio.muted = !mic.audio.muted; }

    // ---- наушники Nothing / CMF: шумодав и заряд через ./ear (их RFCOMM-протокол). Спрашиваем при открытии быстрых настроек.
    // ponytail: узнаём по имени, как Gadgetbridge; не Nothing — ear не ответит, ear останется null ----
    readonly property var buds: Bluetooth.devices.values.find(d => d.connected && /^(nothing|cmf|ear)\b/i.test(d.name)) ?? null
    property var ear: null // {mode, l, r, case?}
    onBudsChanged: ear = null
    // сразу после подключения канал ещё не готов — спрашивать раз в 2 с, пока не ответят. ponytail: не Nothing с похожим
    // именем так и будет опрашиваться, пока подключено
    Timer { interval: 2000; repeat: true; running: !!root.buds && !root.ear; onTriggered: root.earRun([]) }
    readonly property var ancModes: [[5, "off"], [7, "transp"], [3, "low"], [2, "mid"], [1, "high"], [4, "auto"]]
    property var earNext: null
    function earRun(a) {
        if (!buds) return;
        const c = [Quickshell.shellPath("ear"), buds.address, ...a];
        if (earP.running) earNext = c;
        else { earP.command = c; earP.running = true; }
    }
    function setAnc(m) { ear = Object.assign({}, ear, { mode: m }); earRun(["mode", m]); }
    Process {
        id: earP
        stdout: StdioCollector { onStreamFinished: { try { root.ear = JSON.parse(text); } catch (e) { root.ear = null; } } }
        onExited: if (root.earNext) { command = root.earNext; root.earNext = null; running = true; }
    }

    // ---- Bluetooth сам не переподключает устройства, когда адаптер включили обратно (пилюля, авиарежим, rfkill).
    // BlueZ сначала рвёт соединения и только потом гасит адаптер (Connected:false за 40–90 мс до Powered:false), так что
    // снимок в момент выключения пуст. Поэтому список подключённых пишем с задержкой: выключение её отменяет, и в
    // btResume остаётся то, что было до. Отключил сам или наушники убрали в кейс — через полсекунды список это примет ----
    readonly property var btOn: Bluetooth.devices.values.filter(d => d.connected).map(d => d.address)
    property var btResume: []
    onBtOnChanged: btKeep.restart()
    Timer { id: btKeep; interval: 500; running: true; onTriggered: if (Bluetooth.defaultAdapter?.enabled && !btResumeT.running) root.btResume = root.btOn }
    Connections {
        target: Bluetooth.defaultAdapter
        function onEnabledChanged() { if (Bluetooth.defaultAdapter.enabled) btResumeT.restart(); else btKeep.stop(); }
    }
    // адаптеру нужно время после включения
    Timer { id: btResumeT; interval: 1500; onTriggered: { for (const d of Bluetooth.devices.values) if (root.btResume.includes(d.address) && !d.connected) d.connect(); } }

    // ---- кофеин: не спать. Ингибитору нужно живое окно — невидимое 0×0, как в demonshot ----
    property bool caffeine: false
    IdleInhibitor {
        enabled: root.caffeine
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "glyph-caffeine"
            mask: Region {}
        }
    }

}
