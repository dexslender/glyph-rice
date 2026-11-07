pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Wi-Fi 状态与控制：iwctl 封装（adapter / station / get-networks / known-networks / scan / connect）
// 所有 iwd 终端输出解析集中在本文件，UI 只读属性、只调方法
Singleton {
    id: root

    property string adapter: ""          // phy0
    property string station: ""          // wlan0
    property bool powered: false
    property bool available: false       // iwctl 可用且存在无线网卡
    property string state: ""            // connected / disconnected / ...
    property string ssid: ""             // 当前连接的网络
    property string security: ""
    property string ipv4: ""
    property int rssi: 0                 // dBm
    property var networks: []            // [{ ssid, security, signal, stars, known, connected }]
    property var known: []
    property bool stationScanning: false
    property bool busy: false            // 连接/断开/开关进行中
    property bool failed: false          // 最近一次操作失败（下次操作前保持）
    property string backend: "iwd"
    readonly property var fallbackDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var fallbackNetwork: fallbackDevice?.networks.values.find(n => n.connected) ?? null
    readonly property bool fallbackAvailable: Networking.backend !== NetworkBackendType.None && !!fallbackDevice
    readonly property bool usingFallback: backend === "networking"
    readonly property bool enabled: usingFallback ? Networking.wifiEnabled : powered
    readonly property bool connectedNow: usingFallback ? !!fallbackNetwork?.connected : connected
    readonly property string name: usingFallback ? (fallbackNetwork?.name ?? "") : ssid
    readonly property var networkList: usingFallback ? fallbackNetworks() : networks

    readonly property bool connected: state === "connected" && ssid !== ""
    readonly property bool ready: available && powered && station !== ""
    readonly property bool scanning: scanTimer.running || stationScanning

    property var _entries: []            // 原始扫描结果，连接状态变化时重新发布

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // ---------------- 读 ----------------
    Process {
        id: adapterProcess
        command: ["iwctl", "adapter", "list"]
        stdout: StdioCollector {
            id: adapterOutput
            waitForEnd: true
            onStreamFinished: root.applyAdapterList(adapterOutput.text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0)
                root.markUnavailable();
        }
    }

    Process {
        id: deviceProcess
        command: ["iwctl", "device", "list"]
        stdout: StdioCollector {
            id: deviceOutput
            waitForEnd: true
            onStreamFinished: root.applyDeviceList(deviceOutput.text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                root.markUnavailable();
                return;
            }
            root.readAll();
        }
    }

    Process {
        id: stationProcess
        command: ["iwctl", "station", root.station, "show"]
        stdout: StdioCollector {
            id: stationOutput
            waitForEnd: true
            onStreamFinished: root.applyStation(stationOutput.text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0)
                root.clearStation();
        }
    }

    Process {
        id: networksProcess
        command: ["iwctl", "station", root.station, "get-networks"]
        stdout: StdioCollector {
            id: networksOutput
            waitForEnd: true
            onStreamFinished: root.applyNetworks(networksOutput.text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                root._entries = [];
                root.publish();
            }
        }
    }

    Process {
        id: knownProcess
        command: ["iwctl", "known-networks", "list"]
        stdout: StdioCollector {
            id: knownOutput
            waitForEnd: true
            onStreamFinished: root.applyKnown(knownOutput.text)
        }
    }

    // ---------------- 写 ----------------
    Process {
        id: scanProcess
        onExited: function (exitCode) {
            // 扫描结果由 scanTimer 触发的一次读刷新带入
            if (exitCode !== 0)
                console.warn("wifi: scan failed with exit", exitCode);
        }
    }

    Process {
        id: connectProcess
        stderr: StdioCollector {
            id: connectError
            waitForEnd: true
        }
        onExited: function (exitCode) {
            root.busy = false;
            if (exitCode !== 0) {
                root.failed = true;
                console.warn("wifi: connect failed:", (connectError.text || "").trim());
            }
            root.scheduleRefresh();
        }
    }

    Process {
        id: disconnectProcess
        stderr: StdioCollector {
            id: disconnectError
            waitForEnd: true
        }
        onExited: function (exitCode) {
            root.busy = false;
            if (exitCode !== 0) {
                root.failed = true;
                console.warn("wifi: disconnect failed:", (disconnectError.text || "").trim());
            }
            root.scheduleRefresh();
        }
    }

    Process {
        id: powerProcess
        stderr: StdioCollector {
            id: powerError
            waitForEnd: true
        }
        onExited: function (exitCode) {
            root.busy = false;
            if (exitCode !== 0) {
                root.failed = true;
                console.warn("wifi: set Powered failed:", (powerError.text || "").trim());
            }
            root.scheduleRefresh();
        }
    }

    Timer {
        id: scanTimer
        interval: 5000
        onTriggered: root.refresh()
    }

    // 连接/断开的最终状态要等 iwd 完成，读一次不够，稍后再读一次
    Timer {
        id: soonTimer
        interval: 900
        onTriggered: root.refresh()
    }

    Timer {
        id: laterTimer
        interval: 3500
        onTriggered: root.refresh()
    }

    function _reading() {
        return adapterProcess.running || deviceProcess.running || stationProcess.running
            || networksProcess.running || knownProcess.running || powerProcess.running;
    }

    function refresh() {
        if (usingFallback)
            return;
        if (_reading())
            return;
        adapterProcess.running = true;
    }

    function readAll() {
        if (station === "" || !powered)
            return;
        stationProcess.running = true;
        networksProcess.running = true;
        knownProcess.running = true;
    }

    function scheduleRefresh() {
        soonTimer.restart();
        laterTimer.restart();
    }

    function scan() {
        if (usingFallback) {
            if (fallbackDevice)
                fallbackDevice.scannerEnabled = true;
            return;
        }
        if (!ready || busy || scanProcess.running)
            return;
        failed = false;
        stationScanning = true;
        scanProcess.command = ["iwctl", "station", station, "scan"];
        scanProcess.running = true;
        scanTimer.restart();
    }

    function connect(ssidName, passphrase) {
        if (usingFallback) {
            const network = fallbackDevice?.networks.values.find(n => n.name === ssidName);
            if (!network)
                return;
            if (passphrase !== undefined && passphrase !== null && passphrase !== "")
                network.connectWithPsk(passphrase);
            else
                network.connect();
            return;
        }
        if (!ready || busy || ssidName === "")
            return;
        busy = true;
        failed = false;
        const args = ["iwctl", "station", station, "connect", ssidName];
        if (passphrase !== undefined && passphrase !== null && passphrase !== "")
            args.push("--passphrase", passphrase);
        connectProcess.command = args;
        connectProcess.running = true;
    }

    function disconnect() {
        if (usingFallback) {
            fallbackNetwork?.disconnect();
            return;
        }
        if (!ready || busy)
            return;
        busy = true;
        failed = false;
        disconnectProcess.command = ["iwctl", "station", station, "disconnect"];
        disconnectProcess.running = true;
    }

    function setPowered(on) {
        if (usingFallback) {
            Networking.wifiEnabled = on;
            return;
        }
        if (adapter === "" || busy)
            return;
        busy = true;
        failed = false;
        powerProcess.command = ["iwctl", "adapter", adapter, "set-property", "Powered", on ? "on" : "off"];
        powerProcess.running = true;
    }

    // ---------------- 解析 ----------------
    function plain(text) {
        return (text || "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
    }

    function fallbackNetworks() {
        if (!fallbackDevice)
            return [];
        return fallbackDevice.networks.values.filter(n => n.name).map(n => ({
            name: n.name,
            ssid: n.name,
            security: WifiSecurityType.toString(n.security).toLowerCase(),
            signalStrength: n.signalStrength,
            stars: Math.max(0, Math.min(4, Math.floor(n.signalStrength * 4))),
            known: n.known,
            connected: n.connected,
            stateChanging: n.stateChanging,
            backendObject: n
        }));
    }

    function connectNetwork(network, passphrase) {
        if (!network)
            return;
        connect(network.name || network.ssid, passphrase);
    }

    function forgetNetwork(network) {
        if (usingFallback)
            network?.backendObject?.forget();
    }

    // 表格数据行：去掉标题/分隔线后按 2+ 空格切列
    function columns(text, minColumns) {
        const out = [];
        const lines = plain(text).split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].replace(/\s+$/, "").replace(/^\s+/, "");
            if (line === "" || line.startsWith("---"))
                continue;
            const cols = line.split(/\s{2,}/);
            if (cols.length >= minColumns)
                out.push(cols);
        }
        return out;
    }

    function parseProperties(text) {
        const map = {};
        const rows = columns(text, 2);
        for (let i = 0; i < rows.length; ++i) {
            let cols = rows[i];
            if (cols[0] === "*")
                cols = cols.slice(1);
            if (cols.length < 2 || cols[0] === "Settable" || cols[0] === "Property")
                continue;
            map[cols[0]] = cols.slice(1).join("  ");
        }
        return map;
    }

    function applyAdapterList(text) {
        // 列：Name / Powered / Vendor / Model；Powered 只会是 on/off
        const rows = columns(text, 2);
        let name = "";
        let power = false;
        for (let i = 0; i < rows.length; ++i) {
            const cols = rows[i];
            if (cols[1] !== "on" && cols[1] !== "off")
                continue;
            name = cols[0];
            power = cols[1] === "on";
            break;
        }
        if (name === "") {
            markUnavailable();
            return;
        }
        backend = "iwd";
        const changedPower = powered !== power;
        adapter = name;
        available = true;
        powered = power;
        if (!power) {
            station = "";
            clearStation();
            return;
        }
        if (station === "" || changedPower)
            deviceProcess.running = true;
        else
            readAll();
    }

    function applyDeviceList(text) {
        // 列：Name / Address / Powered / Adapter / Mode
        const rows = columns(text, 5);
        let found = "";
        for (let i = 0; i < rows.length; ++i) {
            const cols = rows[i];
            if (cols[4] !== "station")
                continue;
            found = cols[0];
            break;
        }
        station = found;
        if (found === "") {
            // 没有 station 模式的设备：无线网卡不可用于连接
            markUnavailable();
            return;
        }
        readAll();
    }

    function applyStation(text) {
        const props = parseProperties(text);
        if (props["State"] === undefined) {
            clearStation();
            return;
        }
        state = props["State"].toLowerCase();
        stationScanning = (props["Scanning"] || "").toLowerCase() === "yes";
        if (state === "connected") {
            ssid = props["Connected network"] || "";
            security = props["Security"] || "";
            ipv4 = props["IPv4 address"] || "";
            const dbm = parseInt(props["RSSI"], 10);
            rssi = isFinite(dbm) ? dbm : 0;
        } else {
            ssid = "";
            security = "";
            ipv4 = "";
            rssi = 0;
        }
        publish();
    }

    function applyNetworks(text) {
        // 列：<可选 ">" 标记> Network name / Security / Signal(stars)
        const entries = [];
        const lines = plain(text).split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].replace(/\s+$/, "");
            if (line === "")
                continue;
            const match = line.match(/^\s*(?:>\s*)?(.+?)\s{2,}(psk|open|8021x|wep)\s{2,}(\*+)\s*$/i);
            if (!match)
                continue;
            const stars = match[3].length;
            entries.push({
                ssid: match[1].trim(),
                security: match[2].toLowerCase(),
                stars: stars,
                signal: stars / 4
            });
        }
        _entries = entries;
        publish();
    }

    function applyKnown(text) {
        // 列：Name / Security / Hidden / Last connected
        const names = [];
        const lines = plain(text).split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const match = lines[i].match(/^\s*(?:>\s*)?(.+?)\s{2,}(psk|open|8021x|wep)\b/i);
            if (!match)
                continue;
            const name = match[1].trim();
            if (name !== "")
                names.push(name);
        }
        known = names;
        publish();
    }

    function starsForRssi(dbm) {
        if (!isFinite(dbm) || dbm >= 0)
            return 0;
        if (dbm >= -55)
            return 4;
        if (dbm >= -65)
            return 3;
        if (dbm >= -75)
            return 2;
        if (dbm >= -85)
            return 1;
        return 0;
    }

    function publish() {
        const list = [];
        let hasCurrent = false;
        for (let i = 0; i < _entries.length; ++i) {
            const entry = _entries[i];
            const isCurrent = connected && entry.ssid === ssid;
            if (isCurrent)
                hasCurrent = true;
            list.push({
                name: entry.ssid,
                ssid: entry.ssid,
                security: entry.security,
                signal: entry.signal,
                signalStrength: entry.signal,
                stars: entry.stars,
                known: known.indexOf(entry.ssid) >= 0,
                connected: isCurrent,
                stateChanging: busy
            });
        }
        // 隐藏网络不会出现在扫描结果里，仍要把当前连接显示出来
        if (connected && !hasCurrent) {
            const stars = starsForRssi(rssi);
            list.unshift({
                name: ssid,
                ssid: ssid,
                security: security,
                signal: stars / 4,
                signalStrength: stars / 4,
                stars: stars,
                known: true,
                connected: true,
                stateChanging: busy
            });
        }
        networks = list;
    }

    function clearStation() {
        state = "";
        ssid = "";
        security = "";
        ipv4 = "";
        rssi = 0;
        stationScanning = false;
        publish();
    }

    function markUnavailable() {
        if (fallbackAvailable) {
            backend = "networking";
            available = true;
            return;
        }
        available = false;
        powered = false;
        adapter = "";
        station = "";
        scanTimer.stop();
        clearStation();
        _entries = [];
        known = [];
        networks = [];
    }
}
