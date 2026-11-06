# Hyprland: перенос настроек на чистый Arch

Здесь всё, что делает внешний вид и поведение Hyprland на ноутбуке MSI: конфиги, скрипты, курсор, обои.
Цель — домашний ПК (Ryzen 5 5600, RTX 5060 Ti 16 ГБ, 32 ГБ RAM) на чистом Arch Linux.

```
hypr-dotfiles/
├── install.sh            установщик: раскладывает всё по местам, по желанию ставит пакеты
├── packages/
│   ├── base.txt          пакеты из репозиториев Arch (всё, что нужно этому набору)
│   ├── nvidia.txt        драйвер NVIDIA для RTX 5060 Ti
│   └── optional.txt      необязательное (значки Wine в трее, Steam, wireguard-tools)
├── config/               → ~/.config
│   ├── hypr/             hyprland.conf (общий), hyprlock, hypridle, hyprpaper
│   │   ├── machines/     desktop.conf — шаблон для ПК; laptop-msi.conf — как было на ноутбуке
│   │   └── gtk/          отдельные настройки GTK для waybar (тёмные значки трея, курсор)
│   ├── waybar/  mako/  fuzzel/  foot/  mpv/
│   └── gtk-3.0/  gtk-4.0/
├── bin/                  → ~/.local/bin   наши скрипты (список ниже)
├── icons/Furina          → ~/.icons       курсор Furina
├── wallpapers/           → ~/Pictures/wallpapers
├── face.png              → ~/.face        аватар (SDDM)
├── laptop-only/          только для ноутбука (выбор GPU и т.п.), на ПК не нужно
└── tools/ani2xcur.py     конвертер курсоров Windows (.ani/.cur) → XCursor, им сделан Furina
```

## Как в Arch принято с программами

В Arch **ничего не ставится «из коробки»**. После установки есть только базовая система и то,
что ты выбрал сам. Набора «офис + плеер + браузер» нет, и это сделано нарочно: ставишь ровно то,
чем пользуешься, через `pacman -S`. Чего нет в официальных репозиториях — из AUR (через `yay` или `paru`)
или из Flathub.

Здесь так и сделано:

- `packages/base.txt` — всё, без чего не работают конфиги и скрипты: Hyprland, waybar, mako, fuzzel,
  foot, PipeWire, NetworkManager, Python с GTK для наших окон, Dolphin, тема Breeze, шрифты.
- Браузер и Telegram — из **Flathub**, как на ноутбуке (`flatpak install flathub org.mozilla.firefox
  org.telegram.desktop`).
- Остальное ставь по мере надобности: `sudo pacman -S libreoffice-fresh`, `sudo pacman -S steam` и т.д.
  Посмотреть, что есть: `pacman -Ss <слово>`, вики — <https://wiki.archlinux.org>.

## Установка

### 1. Arch

Проще всего встроенным установщиком `archinstall` (есть на установочной флешке Arch):

- **Profile** → `Minimal`. Hyprland и остальное поставим своим списком. Готовый профиль Hyprland
  в archinstall тянет kitty, wofi, dunst — нам они не нужны.
- **Graphics driver** → `Nvidia (open kernel module)`. Для RTX 50xx подходит только открытый модуль.
- **Audio** → `pipewire`.
- **Network** → `NetworkManager`.
- **Additional repositories** → включить `multilib` (нужен Steam и 32-битным библиотекам NVIDIA).
- Создать своего пользователя с правами sudo.

### 2. Набор

Перенеси папку `hypr-dotfiles` на ПК (флешка или `scp`), потом от своего пользователя, **не** через sudo:

```sh
cd hypr-dotfiles
./install.sh --packages --nvidia
```

- `--packages` ставит `packages/base.txt`, `--nvidia` — ещё и `packages/nvidia.txt`.
  sudo спросится только для pacman.
- Без параметров установщик только раскладывает файлы. Это удобно, если пакеты уже стоят.
- Всё, что уже лежит на месте, установщик не затирает, а переименовывает в `*.bak-ДАТА`.

### 3. После установщика

```sh
sudo systemctl enable --now NetworkManager bluetooth
sudo systemctl enable sddm

flatpak install flathub org.mozilla.firefox org.telegram.desktop

# обзор столов (Super+G) — плагин hyprexpo
hyprpm update
hyprpm add https://github.com/hyprwm/hyprland-plugins
hyprpm enable hyprexpo
```

Перезагрузись, в SDDM выбери сеанс **Hyprland**. Шпаргалка по клавишам — **Super+/**.

## Что поправить под ПК

Всё, что зависит от компьютера, вынесено в **`~/.config/hypr/machine.conf`**. Установщик кладёт туда
шаблон `machines/desktop.conf`. Если `machine.conf` уже был, установщик оставляет прежний.

- **Мониторы.** В шаблоне стоит `monitor = , highrr, auto, 1` — любой монитор с максимальной частотой.
  Имена и режимы смотри командой `hyprctl monitors all`, потом пропиши точно, например
  `monitor = DP-1, 2560x1440@165, 0x0, 1`. Hyprland перечитывает конфиг сам.
- **NVIDIA.** Переменные уже в шаблоне. Если курсор мерцает или пропадает, раскомментируй там
  `no_hardware_cursors`.
- **Температура в waybar.** Сейчас стоит `"thermal-zone": 0`, как на ноутбуке. Для Ryzen обычно нужен датчик
  `k10temp`: найди его (`grep -l k10temp /sys/class/hwmon/*/name`) и пропиши в
  `~/.config/waybar/config.jsonc` → `"temperature"` → `"hwmon-path": "/sys/class/hwmon/hwmonN/temp1_input"`.
- **Батарея, яркость, тачпад.** На ПК их нет: модули waybar просто не покажутся,
  жесты трэкпада ни на что не влияют.
- **Wi-Fi.** Если у ПК нет Wi-Fi, список сетей в окне сети будет пустым, но **раздел VPN** в нём работает.
- **Столы.** Логика ноутбука (Acer главный, ноутбук держит стол 11) без этих мониторов отключается сама.
  Столы 1–10 живут на мониторе, где фокус.

## Сочетания клавиш (главное)

| Клавиши | Что делает |
|---|---|
| Super+Return / Super+D / Super+E / Super+B | терминал / запуск программ / Dolphin / браузер |
| **Alt+Space** | быстрый поиск: программы, открытые окна, файлы, калькулятор, Google |
| Super+V | история буфера обмена с превью картинок |
| Alt+Tab (держать) | переключение окон, как в Windows |
| Super+1…0, Super+Shift+1…0 | перейти на стол / отправить туда окно |
| Super+N / Super+Shift+N | вставить новый стол справа / то же с окном |
| Super+G | обзор всех столов |
| Super+h j k l (+Shift / +Ctrl) | фокус / переставить окно / размер |
| Super+F, Super+Shift+V, Super+P, Super+T | на весь экран, плавающее, псевдотайлинг, направление деления |
| Super+Space | раскладка EN/RU (плашка по центру) |
| Print, Super+Shift+S / Super+Print | область в буфер / в файл |
| Super+Escape / Super+Shift+Escape | меню питания / заблокировать |
| Ctrl+Shift+Esc | btop |
| **Super+/** | шпаргалка со всеми клавишами |

Клики по панели: значок сети — Wi-Fi и **VPN-переключатели**, правой кнопкой — настройки сети KDE;
громкость — микшер под значком; память — btop.

## Скрипты (`~/.local/bin`)

| Скрипт | Зачем |
|---|---|
| `hypr_popup.py`, `hypr-popup-show` | «постоянные» окна: поиск, буфер, Wi-Fi и громкость запущены заранее и живут спрятанными на скрытом столе, по вызову переезжают на экран за ~50 мс вместо ~350 |
| `hypr-search` | Alt+Space: программы, окна, файлы (индекс Baloo + папка Telegram), калькулятор |
| `hypr-cliphist-pick` | Super+V: история буфера (cliphist) с миниатюрами картинок |
| `hypr-wifi` | окно сетей: Wi-Fi вкл/выкл, подключение с паролем в строке, VPN-переключатели |
| `hypr-volume` | окно звука: устройство вывода, громкость, микрофон, громкость по программам |
| `hypr-panel-popup` | старое имя для окон панели, теперь просто зовёт `hypr-popup-show` |
| `hypr-popup-dismiss` | закрывает всплывающие окна кликом мимо (повешен на каждый клик) |
| `hypr-alttab` | Alt+Tab с панелью значков (постоянный процесс) |
| `hypr-switch`, `hypr-raise-or-run` | список всех окон; запуск из fuzzel «если открыто — перейти» |
| `hypr-ws`, `hypr-ws-insert`, `hypr-ws-compact` | столы на главном мониторе; вставка стола справа; сдвиг столов без дыр + плашка EN/RU |
| `hypr-help`, `hypr-help-toggle` | шпаргалка Super+/ |
| `hypr-power` | меню питания |
| `hypr-tray-guard` | возвращает трей waybar, если его перехватил kded6 из KDE |
| `hypr-respawn` | держит программу запущенной, пока жив этот сеанс Hyprland |
| `hypr-pip-drag`, `mpv-pip`, `mpv-pip-hypr` | «картинка в картинке» для mpv и Firefox |
| `hypr-brightness` | яркость без прав root (на ноутбуке) |
| `firefox` | обёртка: запускает Firefox из Flathub |

## Живые обои (по желанию)

На ноутбуке обои живые: **waywallen** (Flathub) рисует обои Wallpaper Engine, а на экран их выводит
`waywallen-layer-shell` из релизов `waywallen/waywallen-display`. На ПК по умолчанию стоят статичные
обои (hyprpaper, `~/.config/hypr/hyprpaper.conf`). Чтобы включить живые:

1. `flatpak install flathub org.waywallen.waywallen`.
2. Скачать `waywallen-layer-shell` (собран под Ubuntu, на Arch его лучше собрать заново) в `~/.local/bin`.
3. В `hyprland.conf` раскомментировать две строки waywallen и закомментировать `exec-once = hyprpaper`.

## Грабли, на которые уже наступили (чтобы не наступать снова)

- **Dolphin «Открыть с помощью» пустой.** KDE строит меню по `XDG_MENU_PREFIX`. В Arch для этого нужен
  пакет `archlinux-xdg-menu` и `XDG_MENU_PREFIX=arch-` (уже в `machine.conf`). Переменная должна попасть
  и в окружение D-Bus: этим занимается первая строка `exec-once` с `dbus-update-activation-environment`.
  Иначе служба kded6 пересоберёт кэш пустым. Починить сразу: `kbuildsycoca6 --noincremental`.
- **Пустой трей.** Программы KDE будят kded6, а тот отбирает трей у waybar. Это лечит `hypr-tray-guard`.
- **Курсор Adwaita над кнопками waybar.** GTK на Wayland берёт курсор из gsettings, а не из `settings.ini`.
  Поэтому waybar запускается с `GSETTINGS_BACKEND=keyfile` и своими настройками в `~/.config/hypr/gtk`.
- **Всплывающие окна.** Окна поиска, буфера, Wi-Fi и громкости живут на столе `special:hypr-popups`.
  Правило `pin = yes` с ними несовместимо. Своим скриптам, которые ищут «открытые» окна,
  нужен фильтр `workspace.id > 0`.
- **Фоновые программы** запускать только через `hypr-respawn`, не голым циклом. Иначе после выхода
  из Hyprland они продолжат крутиться.
- **Обзор столов.** Плагин hyprexpo в Arch грузит `hyprpm` уже после чтения конфига. Поэтому Super+G вызывает
  его через `hyprctl dispatch`, а жест `hyprexpo-gesture` закомментирован (на ПК нет тачпада).

## Обновить набор с ноутбука

Набор собран скриптом `tools/build-from-laptop.py` (запускать на ноутбуке). Если там что-то поменялось — запусти его заново,
или скопируй изменённый файл из `~/.config` и `~/.local/bin` в соответствующую папку здесь.
