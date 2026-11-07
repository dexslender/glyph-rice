# Niri migration rules

Goal: keep this Quickshell rice ("Glyph") working only with the niri compositor. These rules apply to every phase.

## Hard rules

- MINIMAL DIFF. Do not refactor, rename, restyle, or "improve" anything unrelated to the migration.
- NEVER install packages and NEVER add a dependency. Use only what is listed under "Available". If a feature cannot work with those tools, disable it cleanly (guard it, hide its UI and keybind) and state the limitation in the task result. Do not substitute a package that is not listed.
- Work on the git branch `niri`. Do not add compatibility paths for another compositor.
- Do not invent niri KDL syntax. Consult the official niri wiki (github.com/niri-wm/niri/wiki) for every config block, and validate with `niri validate -c config/niri/config.kdl`. Never run commands that alter the live session.
- Do only the phase I ask for, then STOP and report.

## Available (assume present)

niri 26.04, quickshell, swayidle, gammastep, iwd + iwgtk (`iwctl`), TLP (battery tuning only, NOT used for power profiles), bluez, upower, brightnessctl, playerctl, libnotify, lxqt-policykit, xdg-desktop-portal-lxqt/-gtk/-wlr (screencast uses xdg-desktop-portal-wlr; do not touch portal config), gpu-screen-recorder, swappy, jq, curl, python3, libqalculate, wl-clipboard, cliphist, geoclue, kitty, fish, starship, fastfetch, btop, cava, eza, zoxide. Login manager is Ly (not SDDM). qml-niri (QML module "Niri", already installed).

## NOT available

direnv, NetworkManager, power-profiles-daemon, grim, slurp, polkit-gnome, gnome-keyring, sddm, papirus-icon-theme, adw-gtk-theme, Bibata, qtengine, darkly, JetBrains Nerd Font, noto fonts, Clash Verge.

## Replacement table

- idle timeouts -> swayidle (currently set by the settings/idle code)
- night light -> gammastep
- color picker -> `niri msg pick-color`
- Screenshots (grim/slurp) -> `niri msg action screenshot` / `screenshot-screen` / `screenshot-window`. Shot module: remove its own region selection and editor; optionally add an "edit" action using `swappy -f`. Recording stays on gpu-screen-recorder, full screen/monitor only (no region selection).
- Wi-Fi uses `qs.services.Wifi`, which runs `iwctl` through `Process` as the default backend. If iwd/iwctl is unavailable or has no usable station, the service falls back to `Quickshell.Networking`/NetworkManager when that backend is available; do not use `Quickshell.Networking` as the primary backend.
- polkit-gnome -> `lxqt-policykit-agent`. Remove gnome-keyring autostart.
- Compositor workspaces / active window / events / keyboard layout in QML -> the installed `qml-niri` plugin (`import Niri`): `Niri {}` with `connect()`, models `workspaces` and `windows`, `focusedWindow`, `keyboardLayouts`, `overview`, and actions like `focusWorkspaceById`. Wrap ONE instance in a singleton services/Niri.qml; all other QML consumes it. Filter workspaces by `output` per screen, and use `workspaces.maxCount` where the bar showed a fixed number. Use `sendRawAction` only for actions without a typed wrapper. Do NOT parse `niri msg event-stream` yourself and do NOT write a new IPC client.
- Global shortcuts -> Quickshell `IpcHandler` targets, triggered from niri binds as `spawn "qs" "-c" "glyph" "ipc" "call" <target> <function>`.
- direnv in fish config -> guard with `type -q direnv`.

## Disable cleanly (no dead UI, no dead keybinds)

- VPN module and its keybind.
- Login / SDDM theme (skip `--sddm`, leave config/sddm untouched).
- GTK / Qt / icon-folder / cursor theme propagation (Theme.qml and the `rice` script: skip Papirus folders, qtengine, GTK css, cursor).
- Special workspaces (todo / music / editor binds).
- Power profile controls (any selector in Quick/Deck using power-profiles-daemon or the PowerProfiles D-Bus API). Do not use tlpctl or tlp-pd. Battery level and charging state (UPower) stay.
- Game mode and settings that require unsupported live compositor mutation are disabled unless a niri IPC action exists for them.

## Blur

niri 26.04 supports native blur via `background-effect { blur true }` inside `window-rule` and `layer-rule` (wiki: "Window Effects", "Configuration: Layer Rules"). Reproduce the required Glyph surface blur with layer-rules matching the Glyph namespaces. Keep it conservative
and easy to turn off.
