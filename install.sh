#!/usr/bin/env bash
# Установка набора на чистый Arch Linux (см. README.md).
#
#   ./install.sh                     — только разложить настройки и скрипты по местам
#   ./install.sh --packages          — сначала поставить пакеты из packages/base.txt
#   ./install.sh --packages --nvidia — плюс драйвер NVIDIA (packages/nvidia.txt)
#
# Всё, что уже лежит на месте, перед заменой переименовывается в *.bak-ДАТА — ничего не теряется.
# Запускать от обычного пользователя (не через sudo): sudo спросится сам, только для pacman.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
stamp=$(date +%Y%m%d-%H%M%S)
want_pkgs=0
want_nvidia=0
for a in "$@"; do
    case $a in
        --packages) want_pkgs=1 ;;
        --nvidia)   want_nvidia=1 ;;
        -h|--help)  sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "непонятный параметр: $a" >&2; exit 1 ;;
    esac
done

if [ "$(id -u)" = 0 ]; then
    echo "Запусти от своего пользователя, не от root: настройки кладутся в твою домашнюю папку." >&2
    exit 1
fi

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

pkgs() { grep -v -E '^\s*(#|$)' "$1"; }

if [ $want_pkgs = 1 ]; then
    command -v pacman >/dev/null || { echo "pacman не найден — это не Arch?" >&2; exit 1; }
    list=$(pkgs "$here/packages/base.txt")
    [ $want_nvidia = 1 ] && list="$list $(pkgs "$here/packages/nvidia.txt")"
    say "Ставлю пакеты (sudo pacman)…"
    # shellcheck disable=SC2086
    sudo pacman -S --needed $list
fi

# положить src в dst, а то, что там уже было, сохранить рядом как .bak-ДАТА
place() {
    local src=$1 dst=$2
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mv "$dst" "$dst.bak-$stamp"
    fi
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
}

say "Настройки → ~/.config"
for d in hypr waybar mako fuzzel foot mpv btop; do
    [ -e "$here/config/$d" ] || continue
    place "$here/config/$d" "$HOME/.config/$d"
done
place "$here/config/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
place "$here/config/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"

# настройки конкретного компьютера: из старого ~/.config/hypr, если он был, иначе шаблон ПК
old_machine="$HOME/.config/hypr.bak-$stamp/machine.conf"
if [ -f "$old_machine" ]; then
    cp "$old_machine" "$HOME/.config/hypr/machine.conf"
    say "machine.conf взят из прежнего ~/.config/hypr"
else
    cp "$here/config/hypr/machines/desktop.conf" "$HOME/.config/hypr/machine.conf"
    say "machine.conf — шаблон домашнего ПК (мониторы и видеокарту проверь, см. README)"
fi
touch "$HOME/.config/hypr/local.conf"   # личные мелочи, его source стоит в конце hyprland.conf

# пути с ноутбука (/home/alih) → своя домашняя папка
grep -rl '/home/alih' "$HOME/.config/hypr" "$HOME/.config/mpv" 2>/dev/null \
    | xargs -r sed -i "s|/home/alih|$HOME|g"

say "Скрипты → ~/.local/bin"
mkdir -p "$HOME/.local/bin"
for f in "$here"/bin/*; do
    place "$f" "$HOME/.local/bin/$(basename "$f")"
    chmod +x "$HOME/.local/bin/$(basename "$f")"
done
chmod -x "$HOME/.local/bin/hypr_popup.py"   # модуль, его импортируют, а не запускают

say "Курсор Furina → ~/.icons"
place "$here/icons/Furina" "$HOME/.icons/Furina"
place "$here/icons/default" "$HOME/.icons/default"

say "Обои → ~/Pictures/wallpapers"
mkdir -p "$HOME/Pictures/wallpapers"
cp --update=none "$here"/wallpapers/* "$HOME/Pictures/wallpapers/"
[ -e "$HOME/.face" ] || cp "$here/face.png" "$HOME/.face"

# ~/.local/bin в PATH: часть сочетаний клавиш зовёт скрипты по имени
if ! grep -qs '.local/bin' "$HOME/.bash_profile"; then
    printf '\n# скрипты Hyprland (~/hypr-dotfiles)\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bash_profile"
    say "~/.local/bin добавлен в PATH (~/.bash_profile)"
fi

# тёмная тема, значки и курсор для GTK-программ (на Wayland они читают gsettings, а не settings.ini)
if command -v gsettings >/dev/null; then
    gsettings set org.gnome.desktop.interface cursor-theme Furina 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-size 32 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme breeze-dark 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
fi

cat <<'EOF'

Готово. Дальше (подробно — README.md):
  1. службы:   sudo systemctl enable --now NetworkManager bluetooth
               sudo systemctl enable sddm
  2. программы из Flathub:
               flatpak install flathub org.mozilla.firefox org.telegram.desktop
  3. обзор столов (Super+G):
               hyprpm update && hyprpm add https://github.com/hyprwm/hyprland-plugins && hyprpm enable hyprexpo
  4. перезагрузиться, в SDDM выбрать сеанс Hyprland. Шпаргалка по клавишам — Super+/
EOF
