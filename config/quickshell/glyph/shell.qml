import QtQuick
import Quickshell
import Quickshell.Io
import "bar"
import "buds"
import "cal"
import "charms"
import "clip"
import "deck"
import "glyph"
import "home"
import "launcher"
import "power"
import "prefs"
import "quick"
import "services"
import "settings"
import "shot"
import "wall"

// glyph: rice в духе nothing os. Дом на обоях, бар, лаунчер, быстрые настройки,
// Glyph-полосы по краям вместо OSD, остров уведомлений, меню питания, настройки, deck (дашборд снизу), буфер обмена, чары (эмодзи и символы), скриншоты, vpn, обои. Блокировка — отдельный процесс (lock.qml).
// Переключается с demonshot через `rice switch` / приложение Rice.
ShellRoot {
    id: shell

    Component.onCompleted: {
        Theme.apply();
        if (Theme.state.paint)
            Theme.apps();
 // rice start ставит ссылки на term/ — цвет надо вернуть
        Rules.night();
        Rules.idle();
    }

    Launcher {
        id: launcherPanel
    }

    Quick {
        id: quickPanel

        onPowerRequested: powerPanel.open()
        onSettingsRequested: prefsPanel.open()
    }

    Power {
        id: powerPanel
    }

    Prefs {
        id: prefsPanel

        onWallRequested: wallsPanel.open()
    }

    Glyph {
    }

    Buds {
    }

    Cal {
        id: cal
    }

    Clip {
        id: clipPanel
    }

    Charms {
        id: charmsPanel
    }

    Deck {
        id: deck
    }

    Shot {
        id: shotPanel
    }

    Walls {
        id: wallsPanel
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: s

            required property var modelData

            Back {
                screen: s.modelData
            }

            Home {
                screen: s.modelData
            }

            Hot {
                screen: s.modelData
                onTriggered: quickPanel.peek()
            }

            Bar {
                screen: s.modelData
                onMarkClicked: launcherPanel.toggle()
                onTrayClicked: quickPanel.toggle()
                onPowerClicked: powerPanel.visible ? powerPanel.close() : powerPanel.open()
                onClockClicked: cal.toggle()
            }

        }

    }

    Connections {
        function onGreysChanged() {
            paint.restart();
        }

        target: Theme
    }
    // сменились тема или цвет (style, новые обои) — окна, kitty, gtk и qt. Через 300 мс: тона новых обоев приходят не сразу,

    // а gtk не стоит дёргать дважды
    Timer {
        id: paint

        interval: 300
        onTriggered: {
            Theme.apply();
            Theme.apps();
        }
    }

    // тона обоев (Theme.pick) — здесь, не в Theme: его грузит и лок, ему хватает готовых из glyph.json. Пусто — копия обоев не
    // загрузилась (серые дают 16 цветов): старые тона остаются. Новые обои — с первого тона
    ColorQuantizer {
        source: Theme.url(Theme.wallSrc(Theme.state.wall))
        depth: 4
        rescaleSize: 64
        onColorsChanged: {
            if (!colors.length)
                return ;

            const t = Theme.pick(colors);
            if (t.join() === Theme.state.tones.join())
                return ;

            Theme.state.tones = t;
            Theme.state.paintAt = 0;
        }
    }

    Connections {
        function onRoundingChanged() {
            Theme.apply();
        }

        target: Theme.state
    }
    // режим ultra включает/снимает blur и тени поверх настроек — окна перекрасить

    Connections {
        function onUltraChanged() {
            Theme.apply();
        }

        target: Rules.store
    }

    IpcHandler {
        function launcher() {
            launcherPanel.toggle();
        }

        function quick() {
            quickPanel.toggle();
        }

        function altar() {
            deck.toggle();
        }

        function settings() {
            prefsPanel.toggle();
        }

        function shot() {
            shotPanel.open();
        }

        function clip() {
            clipPanel.toggle();
        }

        function charms() {
            charmsPanel.toggle();
        }

        function wall() {
            wallsPanel.toggle();
        }

        function power() {
            powerPanel.visible ? powerPanel.close() : powerPanel.open();
        }

        function briUp() {
            Backlight.step(1);
        }

        function briDown() {
            Backlight.step(-1);
        }

        target: "shell"
    }

}
