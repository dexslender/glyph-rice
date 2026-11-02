# AGENTS.md

## Project overview

Glyph is a Linux desktop rice built with Quickshell/QML, fish, shell scripts,
and compositor configuration. It was originally designed for Hyprland and is
being migrated to niri on the `niri` branch. The goal is a Nothing OS-inspired
desktop with a bar, launcher, quick settings, dashboard, wallpaper/theme
system, OSDs, media and hardware integrations, and a lock screen.

The repository is also used directly through symlinked configuration paths.
Changes may therefore be visible immediately to the running session.

## Non-negotiable project rules

- Keep changes surgical and minimal. Do not refactor, rename, restyle, or
  reformat unrelated code.
- Work on the `niri` branch for niri work.
- Do not install packages or add dependencies. Use only the tools listed below.
- Do not modify or delete `config/hypr/`; it is preserved as the legacy
  compositor configuration.
- Do not invent niri KDL syntax. Validate every niri configuration change.
- Preserve existing behavior unless the task explicitly changes it.
- Disable unsupported features cleanly: remove their UI, keybind, and runtime
  calls instead of leaving dead controls.
- Prefer existing helpers and project patterns over new abstractions.
- Do not commit secrets, generated private data, or session exports.

## Available runtime tools

The migration assumes these are available: niri, quickshell, qml-niri,
swayidle, gammastep, iwd/iwctl/iwgtk, TLP for battery tuning only, bluez,
upower, brightnessctl, playerctl, libnotify, lxqt-policykit-agent,
xdg-desktop-portal-lxqt/gtk/wlr, gpu-screen-recorder, swappy, jq, curl,
python3, libqalculate, wl-clipboard, cliphist, geoclue, kitty, fish,
starship, fastfetch, btop, cava, eza, and zoxide. The login manager is Ly.

Do not assume these are installed: NetworkManager, power-profiles-daemon,
grim, slurp, hypridle, hyprsunset, hyprpicker, polkit-gnome,
gnome-keyring, SDDM, Papirus, QtEngine, Clash Verge, or the unavailable fonts
and themes documented in `agents/NIRI_RULES.md`.

## Important files

- `config/niri/config.kdl`: niri environment, startup processes, window/layer
  rules, blur, and keybinds.
- `config/quickshell/glyph/shell.qml`: Glyph root; instantiates panels and
  exposes `IpcHandler` targets used by niri binds.
- `config/quickshell/glyph/services/Niri.qml`: the sole wrapper around the
  installed `Niri` QML plugin. Other QML files consume the `Niri` singleton.
- `config/quickshell/glyph/bar/Bar.qml`: edge bar, launcher mark, dynamic
  workspace indicator, title, clock, and status tray.
- `config/quickshell/glyph/launcher/Launcher.qml`: app, style, window, and
  calculator launcher.
- `config/quickshell/glyph/deck/Deck.qml`: bottom-edge dashboard and hover
  surface.
- `config/quickshell/glyph/quick/Quick.qml`: full-screen quick-settings
  overlay and right-side panel.
- `config/quickshell/glyph/home/Back.qml` and `Home.qml`: background and home
  desktop surfaces.
- `config/quickshell/glyph/glyph/Glyph.qml`: edge OSD/progress surfaces.
- `config/quickshell/glyph/settings/Rules.qml`: idle and night-light rules;
  unsupported live Hyprland controls are disabled.
- `config/quickshell/rice/rice`: shell start/restart/lock helper.
- `agents/NIRI_RULES.md`: authoritative niri constraints, replacements,
  unsupported features, and package assumptions. Read this before niri work.
- `agents/PROJECT_STRUCTURE.md`: concise map of the active niri code paths.
- `README.md`: user-facing project and installation documentation; it is not
  required for normal agent startup.

## Niri/QML integration

Use the installed `qml-niri` module (`import Niri`) through the singleton in
`services/Niri.qml`. Do not create another plugin instance, parse
`niri msg event-stream`, or write a second IPC client.

The wrapper exposes:

- `Niri.workspaces` and `Niri.windows` models
- `Niri.focusedWindow`
- typed workspace/window actions such as `focusWorkspaceById`,
  `focusWorkspace`, `focusWindow`, and `closeWindow`
- `sendRawAction` only for actions without a typed wrapper

Workspace models are dynamic. Filter them by `workspace.output` for each
screen, iterate the actual model entries, and use each workspace's real `id`
for focus actions. Do not render a fixed minimum number of workspace dots or
assume indices are contiguous. If a derived array uses `get(i)`, ensure it is
invalidated from the model's `dataChanged` signal; otherwise role changes such
as `isFocused` and `activeWindowId` may not update the UI.

## Layer-shell guidance

Glyph namespaces include `glyph-back`, `glyph-home`, `glyph-bar`,
`glyph-deck`, `glyph-hot`, `glyph-launcher`, `glyph-quick`, `glyph-edge`,
`glyph-power`, and other panel-specific namespaces. Inspect active surfaces
with:

```sh
niri msg layers
niri msg windows
niri msg outputs
```

Bottom-anchored or full-screen transparent surfaces can still affect
composition and input. `mask` limits input; it does not necessarily remove a
surface from visual composition. Be especially careful with `glyph-deck`,
which is a `Top` layer surface at the bottom edge. Its closed-state mask is
intended to capture only the two-pixel hover strip.

The niri layer blur rule is intentionally conservative. If a rectangle or
unexpected blur blocks application rendering, identify the namespace first and
temporarily narrow or exclude that namespace rather than changing all layer
rules.

## Keybind and IPC conventions

niri binds invoke Quickshell targets in this form:

```kdl
Super_L { spawn "qs" "-c" "glyph" "ipc" "call" "shell" "launcher"; }
```

The corresponding target belongs in the `IpcHandler` with
`target: "shell"` in `shell.qml`. Keep target names synchronized with
`config/niri/config.kdl`. Do not restore Hyprland `shell:*` dispatches in the
niri path.

## Unsupported or intentionally disabled features

The niri migration intentionally disables VPN/Clash Verge, NetworkManager
Wi-Fi UI, region/window screenshot selection, region recording, power-profile
controls, game mode, live Hyprland monitor/input/motion/compositor-border
controls, GTK/Qt/icon/cursor propagation, SDDM theme installation, and
special workspaces. Bluetooth, UPower battery state, full-screen screenshots,
full-screen recording, swayidle, gammastep, and niri-native actions remain.

If reintroducing a disabled feature, first verify that its required runtime
tool is available and document the replacement in the task result.

## Validation and debugging

Run the smallest relevant checks after a change:

```sh
git diff --check
niri validate -c config/niri/config.kdl
sh -n config/quickshell/rice/rice
fish -n config/fish/config.fish
```

For QML/runtime issues, inspect the running shell without restarting the
compositor:

```sh
pgrep -a -f 'quickshell.*glyph|qs.*glyph'
qs log --path ~/.config/quickshell/glyph
niri msg layers
niri msg workspaces
```

Use `grim` only if it is actually available in the current environment; it is
not part of the supported niri migration package set. For a QML warning,
search the exact symbol first, then inspect the full component context. Remove
stale references left by Hyprland migrations rather than adding compatibility
shims.

## Recent fixes and known state

- `Launcher.qml` had a stale `focusT.stop()` call after the Hyprland focus
  timer was removed; do not reintroduce `focusT`.
- `Bar.qml` now refreshes its derived workspace list on model
  `dataChanged` and renders only the workspaces reported by niri for the
  current output.
- `Bar.qml` uses workspace IDs for clicks and navigates dynamically with the
  mouse wheel; do not restore the old fixed six-dot Hyprland behavior.
- `glyph-deck` was excluded from the niri blur layer rule after it caused a
  likely bottom rectangle/composition issue. Preserve that exclusion unless
  the namespace is re-tested.
- The repository may contain untracked migration documentation and shared
  conversation exports. Do not delete or commit them unless explicitly asked.

## Editing workflow

1. Read `agents/NIRI_RULES.md` and the relevant component before editing.
2. Inspect the active niri surface/model state when debugging runtime behavior.
3. Make the smallest change that fixes the root cause.
4. Validate syntax and runtime behavior with the targeted commands above.
5. Report changed files, validation results, disabled behavior, and any
   remaining uncertainty.
