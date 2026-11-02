import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import "lock"

// блокировка — отдельный процесс, как в demonshot: qs -p …/glyph/lock.qml (его зовёт `rice lock`). Разблокировались — выходим.
// Упал шелл — лок живёт; упал лок — Hyprland держит экран закрытым, SUPER+ALT+L поднимает его заново
ShellRoot {
    id: shell
    // hot-reload пересоздаёт WlSessionLock: старый умирает, процесс висит без экрана
    settings.watchFiles: false

    QtObject {
        id: gate
        property string buffer: ""
        property bool fail: false
        property bool leaving: false // пароль принят: поверхность доигрывает уход, потом unlockT снимает лок
        readonly property bool busy: pam.active
        function submit() {
            if (!buffer || pam.active || leaving) return;
            pam.start();
        }
    }

    PamContext {
        id: pam
        config: "lock"
        configDirectory: Quickshell.shellPath("pam")
        onResponseRequiredChanged: if (responseRequired) respond(gate.buffer)
        onCompleted: res => {
            gate.buffer = "";
            if (res === PamResult.Success) {
                gate.leaving = true;
                unlockT.start();
            } else gate.fail = true;
        }
    }
    Timer { id: unlockT; interval: 470; onTriggered: lock.locked = false }

    property string layout: "en"
    function short(name) { return name.slice(0, 2).toLowerCase(); }
    WlSessionLock {
        id: lock
        locked: true
        // ponytail: lockedChanged после locked = false не приходит (quickshell 0.3.2), а secure падает — выходим по нему
        onSecureChanged: if (!secure) Qt.quit()

        LockSurface { auth: gate; layout: shell.layout }
    }
}
