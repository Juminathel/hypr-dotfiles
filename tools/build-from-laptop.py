#!/usr/bin/env python3
"""Собирает ~/hypr-dotfiles: переносимая копия настроек Hyprland с этого ноутбука."""
import os
import re
import shutil
import sys

H = os.path.expanduser("~")
OUT = os.path.join(H, "hypr-dotfiles")
SKIP = re.compile(r"(\.bak|\.pretest|__pycache__|/pulse(/|$)|\.pyc$)")


def keep(path):
    return not SKIP.search(path)


def copy(src, dst):
    src, dst = os.path.join(H, src), os.path.join(OUT, dst)
    if os.path.isdir(src):
        for root, dirs, files in os.walk(src):
            dirs[:] = [d for d in dirs if keep(os.path.join(root, d))]
            for f in files:
                s = os.path.join(root, f)
                if not keep(s):
                    continue
                d = os.path.join(dst, os.path.relpath(s, src))
                os.makedirs(os.path.dirname(d), exist_ok=True)
                if os.path.islink(s):          # курсоры-синонимы — ссылки, копируем ссылкой
                    os.symlink(os.readlink(s), d)
                else:
                    shutil.copy2(s, d)
    else:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)


def cut(text, start, end_incl):
    """вырезать из text кусок от строки start до строки end_incl включительно; вернуть (текст, кусок)"""
    a = text.index(start)
    b = text.index(end_incl, a) + len(end_incl)
    if text[b:b + 1] == "\n":
        b += 1
    return text[:a], text[a:b], text[b:]


# README.md, install.sh, packages/ и сам этот скрипт пишутся руками — их не трогаем
for name in ("bin", "config", "icons", "wallpapers", "laptop-only", "face.png"):
    p = os.path.join(OUT, name)
    if os.path.isdir(p):
        shutil.rmtree(p)
    elif os.path.exists(p):
        os.remove(p)
os.makedirs(OUT, exist_ok=True)

# ---------- конфиги как есть ----------
for d in ["waybar", "mako", "fuzzel", "foot", "mpv", "btop"]:
    copy(f".config/{d}", f"config/{d}")
copy(".config/gtk-3.0/settings.ini", "config/gtk-3.0/settings.ini")
if os.path.exists(os.path.join(H, ".config/gtk-4.0/settings.ini")):
    copy(".config/gtk-4.0/settings.ini", "config/gtk-4.0/settings.ini")
for f in ["hyprlock.conf", "hypridle.conf", "hyprpaper.conf"]:
    copy(f".config/hypr/{f}", f"config/hypr/{f}")
copy(".config/hypr/gtk", "config/hypr/gtk")

# ---------- hyprland.conf: машинное — в machine.conf ----------
conf = open(os.path.join(H, ".config/hypr/hyprland.conf")).read()
laptop = []

conf = conf.replace("""# Hyprland 0.53.x — ноутбук с гибридной графикой
# AMD Radeon 680M (iGPU, ведёт встроенный экран) + NVIDIA RTX 4050 Max-Q""",
"""# Hyprland 0.53.x — общий конфиг (перенесён с ноутбука MSI, см. README.md)
# Всё, что зависит от компьютера (мониторы, видеокарта, правила столов), — в machine.conf.""", 1)

pre, part, post = cut(conf, "# eDP-1: 1920x1080@144.", "monitor = , preferred, auto, auto          # любой внешний — автоматически")
laptop.append(part)
conf = pre + "# Мониторы — в machine.conf (у каждого компьютера свои).\nsource = ~/.config/hypr/machine.conf\n" + post

pre, part, post = cut(conf, "#############################\n### ГИБРИДНАЯ ГРАФИКА", "см. ~/.local/bin/hypr-gpu-select. Запуск на дискретке при рендере на AMD — обёртка ~/.local/bin/nv.")
laptop.append(part)
conf = pre + "# Видеокарта (переменные драйвера) — в machine.conf.\n" + post

pre, part, post = cut(conf, "env = XDG_MENU_PREFIX,plasma-", "env = XDG_MENU_PREFIX,plasma-")
laptop.append(part)
conf = pre + "# XDG_MENU_PREFIX (меню программ для Dolphin) — в machine.conf: в Ubuntu plasma-, в Arch arch-.\n" + post

pre, part, post = cut(conf, "# Обзор рабочих столов (пакет hyprland-plugin-hyprexpo)", "plugin = /usr/lib/x86_64-linux-gnu/hyprland/plugins/libhyprexpo.so")
laptop.append(part)
conf = pre + "# Обзор рабочих столов hyprexpo: плагин подключается в machine.conf (в Arch — через hyprpm).\n" + post

pre, part, post = cut(conf, "# Acer — главный: на нём столы 1–10", "workspace = 11, monitor:eDP-1, default:true   # не persistent: без Acer он пустеет и пропадает (laptop_main)")
laptop.append(part)
conf = pre + "# Правила столов (на каком мониторе какие) — в machine.conf.\n" + post

# обои: на новом компьютере сначала статичные (hyprpaper); waywallen — по желанию, см. README
old = """exec-once = flatpak run --branch=stable --arch=x86_64 --command=waywallen org.waywallen.waywallen --no-ui
exec-once = $HOME/.local/bin/hypr-respawn $HOME/.local/bin/waywallen-layer-shell
# exec-once = hyprpaper
"""
assert old in conf
conf = conf.replace(old, """# На новом компьютере по умолчанию статичные обои (hyprpaper.conf). Живые — waywallen:
# поставить его (README, раздел «Живые обои»), раскомментировать две строки и убрать hyprpaper.
# exec-once = flatpak run --branch=stable --arch=x86_64 --command=waywallen org.waywallen.waywallen --no-ui
# exec-once = $HOME/.local/bin/hypr-respawn $HOME/.local/bin/waywallen-layer-shell
exec-once = hyprpaper
""", 1)
# плагин hyprexpo в Arch грузит hyprpm уже ПОСЛЕ чтения конфига: прямой диспетчер и его
# ключевое слово дали бы ошибку конфига. Вызов через hyprctl проверяется только при нажатии.
conf = conf.replace("bind = $mainMod, G, hyprexpo:expo, toggle",
                    "bind = $mainMod, G, exec, hyprctl dispatch hyprexpo:expo toggle   # плагин грузит hyprpm", 1)
conf = conf.replace("hyprexpo-gesture = 3, vertical, expo",
                    "# hyprexpo-gesture = 3, vertical, expo   (ключевое слово плагина; на ноутбуке с тачпадом — вернуть)", 1)
open(os.path.join(OUT, "config/hypr/hyprland.conf"), "w").write(conf)

os.makedirs(os.path.join(OUT, "config/hypr/machines"), exist_ok=True)
open(os.path.join(OUT, "config/hypr/machines/laptop-msi.conf"), "w").write(
    "# machine.conf ноутбука MSI (Ubuntu 26.04, AMD 680M + RTX 4050) — для справки.\n"
    "# Это вырезанные из hyprland.conf куски как есть.\n\n" + "\n".join(laptop)
    + "\n# gpu.conf пишет ~/.local/bin/hypr-gpu-select (на ноутбуке, в набор не входит)\n")

open(os.path.join(OUT, "config/hypr/machines/desktop.conf"), "w").write("""# machine.conf домашнего ПК: Ryzen 5 5600 + RTX 5060 Ti 16 ГБ (одна видеокарта NVIDIA), Arch Linux.
# install.sh копирует этот файл в ~/.config/hypr/machine.conf, если его там ещё нет.

################
### МОНИТОРЫ ###
################
# Сейчас — любой монитор с максимальной частотой. Узнать имя и режимы: hyprctl monitors all
# и потом прописать точно, например:
#   monitor = DP-1, 2560x1440@165, 0x0, 1
#   monitor = HDMI-A-1, 1920x1080@60, 2560x0, 1
monitor = , highrr, auto, 1

#################
### ВИДЕОКАРТА ###
#################
# NVIDIA, драйвер nvidia-open (для RTX 50xx — только открытый модуль).
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct
# Если курсор мерцает или пропадает — раскомментировать:
# cursor {
#     no_hardware_cursors = true
# }

# Меню программ для Dolphin «Открыть с помощью» (пакет archlinux-xdg-menu)
env = XDG_MENU_PREFIX,arch-

# Обзор рабочих столов hyprexpo. В Arch плагины ставит hyprpm (см. README):
#   hyprpm update && hyprpm add https://github.com/hyprwm/hyprland-plugins && hyprpm enable hyprexpo
exec-once = hyprpm reload -n

######################
### РАБОЧИЕ СТОЛЫ  ###
######################
# 1–5 видны на панели всегда, 6–10 появляются по мере надобности.
workspace = 1, persistent:true, default:true
workspace = 2, persistent:true
workspace = 3, persistent:true
workspace = 4, persistent:true
workspace = 5, persistent:true
""")

# ---------- скрипты ----------
BIN_SKIP = {"agent", "agent-browser", "claude", "grok", "helm", "uv", "uvx", "nv",
            "lens-launch", "waywallen-layer-shell", "hypr-gpu-select", "hypr-check",
            "hypr-wifi-menu", "ani2xcur.py"}
bindir = os.path.join(H, ".local/bin")
for f in sorted(os.listdir(bindir)):
    p = os.path.join(bindir, f)
    if f in BIN_SKIP or not keep(p) or os.path.isdir(p) or os.path.islink(p):
        continue
    if f.startswith("hypr") or f in ("mpv-pip", "mpv-pip-hypr", "firefox"):
        copy(f".local/bin/{f}", f"bin/{f}")
copy(".local/bin/ani2xcur.py", "tools/ani2xcur.py")  # tools/ не чистится, файл просто обновится
for laptop_only in ("hypr-gpu-select", "hypr-check", "nv"):
    copy(f".local/bin/{laptop_only}", f"laptop-only/{laptop_only}")

# ---------- тема курсора, обои, аватар ----------
copy(".icons/Furina", "icons/Furina")
copy(".icons/default/index.theme", "icons/default/index.theme")
for w in ["yofukashi-night.png", "sddm-shinobu.png"]:
    copy(f"Pictures/wallpapers/{w}", f"wallpapers/{w}")
copy(".face", "face.png")

print("ok")
