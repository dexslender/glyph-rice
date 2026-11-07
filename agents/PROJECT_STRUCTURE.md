# Active code map

This map covers the niri-only path.

## Compositor and shell entry points

- `config/niri/config.kdl`: niri environment, startup processes, layer/window
  rules, blur, and keybinds.
- `config/quickshell/glyph/shell.qml`: root shell, panels, and `IpcHandler`
  targets called by niri binds.
- `config/quickshell/glyph/services/Niri.qml`: the only `qml-niri` plugin
  instance; all QML niri state and actions go through its singleton.
- `config/quickshell/rice/rice`: starts, restarts, and locks the selected
  Quickshell shell.

## Main surfaces

- `bar/Bar.qml`: per-output bar, dynamic workspaces, title, clock, and tray.
- `launcher/Launcher.qml`: application, style, window, and calculator launcher.
- `deck/Deck.qml`: bottom-edge dashboard and hover strip.
- `quick/Quick.qml`: quick-settings overlay and right-side panel.
- `home/Back.qml`, `home/Home.qml`: background and desktop surfaces.
- `glyph/Glyph.qml`: volume, brightness, notification, and progress OSDs.
- `settings/Rules.qml`: supported idle and night-light rules.
- `shot/Shot.qml`: niri screenshots and full-screen recording.
- `power/Power.qml`, `lock.qml`, `lock/LockSurface.qml`: session actions and
  lock screen.

## Supporting services

- `services/Backlight.qml`: brightness device and brightness actions.
- `services/Media.qml`: MPRIS/playerctl media state and controls.
- `services/SysStats.qml`: CPU, memory, process, and uptime data.
- `Theme.qml`: palette and wallpaper-derived shell theme state.
- `config/fish/config.fish`: fish startup and interactive helpers.

For detailed constraints, unavailable tools, disabled features, and validation
commands, read `agents/NIRI_RULES.md`.
