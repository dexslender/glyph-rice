#!/usr/bin/env bash
# Glyph: ставит всё на чистый Arch и линкует конфиги из этого репо.
#   ./install.sh                   пакеты + сервисы + симлинки; спросит, что из EXTRA поставить ещё
#   ./install.sh --with telegram   то же без вопроса (--with "" — только сам рис)
#   ./install.sh --links           только симлинки (на уже готовой системе)
set -euo pipefail

DOTS="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$HOME/.dots-backup-$(date +%F_%H-%M-%S)"

PACMAN=(
    # база
    base-devel git curl jq python
    # сессия
    niri ly quickshell swayidle gammastep xdg-desktop-portal-gtk xdg-desktop-portal-wlr
    lxqt-policykit geoclue upower xdg-user-dirs
    # звук, сеть, bluetooth
    pipewire pipewire-pulse pipewire-alsa wireplumber bluez bluez-utils
    # утилиты, которые зовут бинды и шелл
    brightnessctl playerctl wl-clipboard cliphist swappy imagemagick libvips libqalculate
    gpu-screen-recorder libnotify trash-cli
    # терминал и консоль
    kitty fish starship fastfetch btop cava eza zoxide
    # приложения
    thunar pavucontrol
)

AUR=(
    zen-browser-bin
)

# на выбор, как optional components у caelestia
declare -A EXTRA=(
    [telegram]="telegram-desktop"                                        # Super+D
    [spotify]="spotify-launcher spicetify-cli spicetify-marketplace-bin" # Super+M
)

G=config/quickshell/glyph
# репо-путь → путь в $HOME
LINKS=(
    "config/niri                               .config/niri/glyph"
    "$G                                         .config/quickshell/glyph"
    "config/quickshell/rice                     .config/quickshell/rice"
    "config/quickshell/rice/rice                .local/bin/rice"
    "config/kitty                               .config/kitty"
    "$G/term/starship.toml                      .config/starship.toml"
    "$G/term/fastfetch                          .config/fastfetch"
    "$G/term/btop                               .config/btop"
    "$G/term/cava                               .config/cava"
    "config/fish/config.fish                    .config/fish/config.fish"
    "config/fish/functions/fish_greeting.fish   .config/fish/functions/fish_greeting.fish"
    "config/fonts                               .local/share/fonts/glyph"
)

say() { printf '\e[38;2;215;25;33m●\e[0m %s\n' "$*"; }

extras() { # --with или вопрос → в EXT, ставит yay (и из репо) отдельно от AUR
    local w; EXT=()
    if [ -z "${WITH+x}" ]; then
        say "anything else to install? space-separated, Enter for none"
        for w in "${!EXTRA[@]}"; do printf '  %-9s %s\n' "$w" "${EXTRA[$w]}"; done
        read -rp "  > " WITH || true
    fi
    for w in ${WITH//,/ }; do
        [ -n "${EXTRA[$w]-}" ] || { echo "no such extra: $w (available: ${!EXTRA[*]})"; exit 1; }
        EXT+=(${EXTRA[$w]})
    done
}

packages() {
    say "pacman"
    # модули pulseaudio требуют его самого — pacman не дал бы заменить его на pipewire-pulse.
    # Списком, не grep '^pulseaudio-': pulseaudio-alsa и pulseaudio-qt с pipewire живут
    local pa; pa=$(pacman -Qq pulseaudio-{bluetooth,jack,lirc,rtp,zeroconf,equalizer,equalizer-ladspa} 2>/dev/null || true)
    [ -z "$pa" ] || sudo pacman -R $pa
    pacman -Q pulseaudio &>/dev/null && say "pacman will ask \"Remove pulseaudio?\": answer y, pipewire-pulse replaces it"
    # без --noconfirm: на конфликте (pulseaudio → pipewire-pulse) он ответил бы «нет» и уронил установку
    sudo pacman -Syu --needed "${PACMAN[@]}"

    if ! command -v yay >/dev/null; then
        say "yay"
        local tmp; tmp="$(mktemp -d)"
        git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi

    say "aur"
    # AUR необязателен: упал пакет — сервисы и ссылки всё равно ставим
    yay -S --needed --noconfirm "${AUR[@]}" || say "aur: some packages failed, see above"
    # отдельно: не собрался spicetify — ядро AUR от этого не страдает
    [ ${#EXT[@]} -eq 0 ] || yay -S --needed --noconfirm "${EXT[@]}" || say "extras: some packages failed, see above"
}

services() {
    say "services"
    sudo systemctl enable bluetooth
    systemctl --user enable pipewire-pulse.socket wireplumber
    sudo usermod -aG video "$USER" # brightnessctl
    xdg-user-dirs-update
}

links() {
    say "symlinks (old files → $BACKUP)"
    local src dst
    for l in "${LINKS[@]}"; do
        read -r src dst <<<"$l"
        src="$DOTS/$src" dst="$HOME/$dst"
        [ "$(readlink "$dst")" = "$src" ] && continue
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            mkdir -p "$BACKUP/$(dirname "${dst#"$HOME"/}")"
            mv "$dst" "$BACKUP/${dst#"$HOME"/}"
        fi
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
        echo "  $dst"
    done
    # rules.json и kitty.conf шелл создаст сам; rice поднимет glyph и соберёт тему папок
    mkdir -p "$HOME/.config/demonshot" "${XDG_STATE_HOME:-$HOME/.local/state}/rice"
    echo glyph > "${XDG_STATE_HOME:-$HOME/.local/state}/rice/shell"
    mkdir -p "$HOME/Pictures/Wallpapers" # пикер обоев (Super+Shift+W) смотрит сюда
    fc-cache -f >/dev/null
}

[ "$EUID" -eq 0 ] && { echo "run as your user, not root: sudo asks when it needs to"; exit 1; }

case "${1:-}" in
    --links) links ;; # на любом дистрибутиве (NixOS, Fedora…): пакеты тогда свои, список — в README
    ""|--with) command -v pacman >/dev/null || { echo "packages install on Arch only; on another distro: $0 --links"; exit 1; }
        [ "${1:-}" = --with ] && WITH="${*:2}" # и через запятую, и через пробел
        extras; packages; services; links
        # spicetify нужен уже скачанный Spotify с входом в аккаунт, поэтому применять до первого запуска нечего
        [[ " ${WITH//,/ } " == *" spotify "* ]] && say "spotify: launch it, log in, then run spicetify config custom_apps marketplace && spicetify backup apply"
        say "done. reboot and pick niri in Ly" ;;
    *) echo "usage: $0 [--with telegram,spotify | --links]"; exit 1 ;;
esac
