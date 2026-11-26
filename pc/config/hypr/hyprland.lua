-- Hyprland 0.57+ — общий конфиг на Lua (переведён с hyprland.conf: с 0.57 Hyprland читает
-- только hyprland.lua, старый формат больше не поддерживается).
-- Всё, что зависит от компьютера (мониторы, видеокарта, правила столов), — в machine.lua.
-- Справка по API: /usr/share/hypr/stubs/hl.meta.lua, https://wiki.hypr.land/configuring/
--
-- Важно для скриптов: `hyprctl dispatch` теперь тоже принимает Lua, например
--   hyprctl dispatch 'hl.dsp.focus({workspace = "3"})'
-- Python-скрипты в ~/.local/bin переводят старые команды сами (hypr_dsp.py).

local HOME = os.getenv("HOME")
local CFG  = HOME .. "/.config/hypr"
local BIN  = HOME .. "/.local/bin/"

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local exec = hl.dsp.exec_cmd

-- какая панель запустится — решает так же, как ~/.local/bin/hypr-bar:
-- ~/.config/hypr/bar (waybar | quickshell), иначе quickshell, если установлен
local function bar_choice()
    local f = io.open(CFG .. "/bar", "r")
    if f then
        local c = (f:read("l") or ""):gsub("%s+", "")
        f:close()
        if c ~= "" then return c end
    end
    return file_exists("/usr/bin/quickshell") and "quickshell" or "waybar"
end

----------------
--- МОНИТОРЫ ---
----------------

-- Мониторы, видеокарта и правила столов — в machine.lua (у каждого компьютера свои).
require(CFG .. "/machine.lua")

hl.config({
    misc = {
        vrr                     = 2,      -- переменная частота: только для полноэкранных приложений
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        focus_on_activate       = true,
    },
})

-- Тулкиты — нативный Wayland вместо XWayland
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
-- Qt-программы берут шрифты, тему и значки из настроек Plasma (как в KDE): без этого
-- Dolphin/Kate/Discover рисуются стандартным мелким шрифтом и не видят kdeglobals.
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("SDL_VIDEODRIVER", "wayland,x11")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Курсор (как в KDE: kcminputrc cursorTheme=Furina, cursorSize=32)
hl.env("XCURSOR_THEME", "Furina")
hl.env("XCURSOR_SIZE", "32")
hl.env("HYPRCURSOR_THEME", "Furina")   -- у Furina нет формата hyprcursor — Hyprland сам берёт XCursor
hl.env("HYPRCURSOR_SIZE", "32")
-- LibreOffice: в Hyprland сам выбирает старый вид «gen» (Windows 7, XWayland); kf6 — как в KDE
hl.env("SAL_USE_VCLPLUGIN", "kf6")

------------------
--- ПРИЛОЖЕНИЯ ---
------------------

local terminal    = "foot"
local fileManager = "dolphin"
local browser     = "firefox"
local menu        = "fuzzel"
local mainMod     = "SUPER"

------------------
--- АВТОЗАПУСК ---
------------------

-- то, что раньше было exec-once: только при старте Hyprland, не при перечитывании конфига
hl.on("hyprland.start", function()
    -- ПЕРВЫМ ДЕЛОМ: отдать окружение systemd и D-Bus, и только потом поднимать порталы.
    -- Иначе D-Bus активирует xdg-desktop-portal-gtk без WAYLAND_DISPLAY, тот висит 120 с,
    -- и всё это время flatpak-приложения ждут портал. GTK-бэкенд портала после прошлого
    -- сеанса висит в failed — сбросить и поднять заново, потом фронтенд.
    hl.exec_cmd("sh -c 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE XDG_MENU_PREFIX SAL_USE_VCLPLUGIN; systemctl --user reset-failed xdg-desktop-portal-gtk.service; systemctl --user restart xdg-desktop-portal-gtk.service xdg-desktop-portal-hyprland.service; systemctl --user restart xdg-desktop-portal.service'")

    -- Курсор, который рисует сам Hyprland (над панелью)
    hl.exec_cmd("hyprctl setcursor Furina 32")

    -- путь агента у дистрибутивов разный: Ubuntu — libexec в x86_64-linux-gnu, Arch — /usr/lib
    hl.exec_cmd([[sh -c 'for p in /usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1 /usr/lib/polkit-kde-authentication-agent-1 /usr/libexec/polkit-kde-authentication-agent-1; do [ -x "$p" ] && exec "$p"; done']])
    -- Индексатор файлов Baloo (поиск Alt+Пробел и Dolphin). Сам он стартует только в KDE/GNOME
    -- (OnlyShowIn, graphical-session.target), в Hyprland — нет, и новые файлы не попадали в поиск.
    hl.exec_cmd("systemctl --user start kde-baloo.service")

    -- Панель: Quickshell (~/.config/quickshell), если установлен, иначе waybar
    -- (с отдельным GTK-конфигом ~/.config/hypr/gtk — breeze-dark для значков трея).
    -- Выбрать руками: echo waybar > ~/.config/hypr/bar (или quickshell). См. ~/.local/bin/hypr-bar.
    -- hypr-respawn перезапускает, пока жив этот Hyprland.
    hl.exec_cmd(BIN .. "hypr-respawn " .. BIN .. "hypr-bar")
    -- kded6 (его будят KDE-программы) забирает трей у панели — сторож возвращает
    hl.exec_cmd(BIN .. "hypr-respawn " .. BIN .. "hypr-tray-guard")
    -- значки трея Wine/Proton и старых X11 (XEmbed) → обычный трей
    hl.exec_cmd(BIN .. "hypr-respawn xembedsniproxy")
    -- Всплывающие окна держатся запущенными, чтобы открываться без задержки (hypr_popup.py)
    hl.exec_cmd(BIN .. "hypr-respawn " .. BIN .. "hypr-search --daemon")
    hl.exec_cmd(BIN .. "hypr-respawn " .. BIN .. "hypr-cliphist-pick --daemon")
    -- окна громкости и Wi-Fi нужны только waybar: у Quickshell они свои (Volume/WifiPopup.qml)
    if bar_choice() == "waybar" then
        hl.exec_cmd(BIN .. "hypr-respawn " .. BIN .. "hypr-volume --daemon")
        hl.exec_cmd(BIN .. "hypr-respawn " .. BIN .. "hypr-wifi --daemon")
    end
    -- История буфера обмена (Super+V)
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    -- Рабочие столы без дыр: опустел 3-й — 4-й съезжает на его место
    hl.exec_cmd(BIN .. "hypr-respawn " .. BIN .. "hypr-ws-compact")
    -- Панель Alt+Tab держится запущенной, чтобы появляться без задержки
    hl.exec_cmd(BIN .. "hypr-respawn " .. BIN .. "hypr-alttab daemon")
    hl.exec_cmd("mako")
    -- Обои живые: waywallen (Flathub) рисует, waywallen-layer-shell выводит на экран
    -- (README, «Живые обои»). Вернуть статичные: эти две строки закомментировать, hyprpaper — раскомментировать.
    hl.exec_cmd("flatpak run --branch=stable --arch=x86_64 --command=waywallen org.waywallen.waywallen --no-ui")
    hl.exec_cmd(BIN .. "hypr-respawn " .. BIN .. "waywallen-layer-shell")
    -- hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle")
    -- Ночной режим: после заката экран плавно теплеет, к рассвету — обратно (по солнцу над Алматы).
    -- hyprsunset меняет цвет (wlsunset на NVIDIA не работает), hypr-nightlight считает солнце.
    -- Температура: hypr-nightlight 4000 (меньше — теплее); выключить: hypr-nightlight off.
    hl.exec_cmd(BIN .. "hypr-respawn hyprsunset --identity")
    hl.exec_cmd(BIN .. "hypr-respawn " .. BIN .. "hypr-nightlight daemon")
    hl.exec_cmd("blueman-applet")
end)

-------------------
--- ВНЕШНИЙ ВИД ---
-------------------

hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(89b4faee)", "rgba(cba6f7ee)" }, angle = 45 },
            inactive_border = "rgba(45475aaa)",
        },
        resize_on_border = true,
        -- tearing действует ТОЛЬКО на окна с правилом immediate (игры ниже)
        allow_tearing = true,
        layout        = "dwindle",
    },

    decoration = {
        rounding         = 8,
        rounding_power   = 2,
        active_opacity   = 1.0,
        inactive_opacity = 0.95,

        shadow = {
            enabled      = true,
            range        = 12,
            render_power = 3,
            color        = "rgba(00000055)",
        },

        blur = {
            enabled           = true,
            size              = 4,
            passes            = 2,
            new_optimizations = true,
            ignore_opacity    = true,
            xray              = true,
        },
    },

    animations = {
        enabled = true,
    },

    binds = {
        -- По умолчанию 300 мс: после каждого щелчка колеса следующий игнорировался —
        -- отсюда пауза между столами при Super+колесо.
        scroll_event_delay = 0,
    },

    dwindle = {
        preserve_split = true,
        smart_split    = false,
        force_split    = 2,   -- новое окно всегда справа/снизу (0 = по положению курсора)
    },

    master = {
        new_status = "master",
    },
})

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}    } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}  } })

hl.animation({ leaf = "global",     enabled = true, speed = 8,    bezier = "default" })
hl.animation({ leaf = "border",     enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",    enabled = true, speed = 4,    bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",  enabled = true, speed = 3.5,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",     enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

------------
--- ВВОД ---
------------

hl.config({
    input = {
        kb_layout          = "us,ru",
        kb_options         = "grp:win_space_toggle,caps:escape",
        numlock_by_default = true,
        follow_mouse       = 1,
        sensitivity        = 0,

        touchpad = {
            natural_scroll       = true,
            tap_to_click         = true,
            disable_while_typing = true,
            scroll_factor        = 0.5,
        },
    },

    gestures = {
        workspace_swipe_distance     = 300,
        workspace_swipe_cancel_ratio = 0.3,
        workspace_swipe_create_new   = true,
        workspace_swipe_forever      = false,
    },
})

-- Мышь SIGMACHIP — как в KDE (kcminputrc): скорость -0.2, без ускорения
hl.device({
    name          = "sigmachip-usb-mouse",
    sensitivity   = -0.2,
    accel_profile = "flat",
})

-- Жесты трэкпада
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })   -- соседний стол
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 4, direction = "pinchin",    action = "close" })       -- щипок — закрыть окно
hl.gesture({ fingers = 3, direction = "swipe", mods = "SUPER",     action = "move" })
hl.gesture({ fingers = 3, direction = "swipe", mods = "SUPER ALT", action = "resize" })

-- Обзор рабочих столов hyprexpo (Super+G) пока отключён: в Hyprland 0.57 нет hyprpm.
-- Когда плагин появится — hl.plugin.load("<путь к libhyprexpo.so>") в machine.lua и бинд на Super+G.

------------------
--- КЛАВИАТУРА ---
------------------

local function key(mods, k)
    if mods == "" then return k end
    return mods .. " + " .. k
end

local function bind(mods, k, action, opts)
    hl.bind(key(mods, k), action, opts)
end

bind(mainMod, "Return", exec(terminal))
bind(mainMod, "Q",      hl.dsp.window.close())
bind(mainMod, "E",      exec(fileManager))
bind(mainMod, "B",      exec(browser))
bind(mainMod, "D",      exec(menu))
bind("ALT",   "Space",  exec(BIN .. "hypr-popup-show search"))   -- быстрый поиск
bind(mainMod .. " + SHIFT", "V", hl.dsp.window.float())           -- было Super+V — отдано истории буфера
bind(mainMod, "V",      exec(BIN .. "hypr-popup-show cliphist"))  -- история буфера с превью картинок
bind(mainMod, "F",      hl.dsp.window.fullscreen())
bind(mainMod, "P",      hl.dsp.window.pseudo())
bind(mainMod, "T",      hl.dsp.layout("togglesplit"))
bind(mainMod .. " + SHIFT", "M", hl.dsp.exit())

-- Меню питания и шпаргалка
bind(mainMod, "Escape", exec("hypr-power"))
bind(mainMod, "slash",  exec("hypr-help-toggle"))
bind(mainMod .. " + SHIFT", "Escape", exec("hyprlock"))

-- «Картинка в картинке» (Firefox, mpv-pip, mpv после Ctrl+P) таскается обычной ЛКМ, без Super.
-- Firefox и mpv просят композитор передвинуть окно, Hyprland этого не делает — поэтому на
-- нажатие ЛКМ над PiP запускаем то же перетаскивание, что Super+ЛКМ, на отпускание — завершаем.
-- (Раньше это делал скрипт hypr-pip-drag, но в 0.57 перетаскивание запускается только из бинда.)
local function is_pip(w)
    if not w or not w.floating then return false end
    local t = w.title or ""
    return t == "Picture-in-Picture" or t == "Картинка в картинке"
        or w.class == "mpv-pip"
        or (w.class == "mpv" and w.pinned)
end

local function pip_under_cursor()
    local c = hl.get_cursor_pos()
    if not c then return false end
    for _, w in ipairs(hl.get_windows()) do
        if is_pip(w) and w.visible and w.at and w.size
            and w.at.x <= c.x and c.x < w.at.x + w.size.x
            and w.at.y <= c.y and c.y < w.at.y + w.size.y then
            return true
        end
    end
    return false
end

local pip_dragging = false

-- Клик мимо шпаргалки или окон с панели закрывает их (hypr-popup-dismiss).
-- non_consuming: клик не перехватывается, приложение получает его как обычно.
hl.bind("mouse:272", function()
    hl.exec_cmd(BIN .. "hypr-popup-dismiss")
    if pip_under_cursor() then
        pip_dragging = true
        return hl.dispatch(hl.dsp.window.drag())
    end
end, { non_consuming = true })

hl.bind("mouse:272", function()
    if pip_dragging then
        pip_dragging = false
        return hl.dispatch(hl.dsp.window.drag())   -- кнопка отпущена — перетаскивание заканчивается
    end
end, { non_consuming = true, release = true })

-- Фокус (hjkl)
bind(mainMod, "h", hl.dsp.focus({ direction = "left" }))
bind(mainMod, "l", hl.dsp.focus({ direction = "right" }))
bind(mainMod, "k", hl.dsp.focus({ direction = "up" }))
bind(mainMod, "j", hl.dsp.focus({ direction = "down" }))
-- Стрелки влево/вправо — соседний стол на этом мониторе, вверх/вниз — фокус
bind(mainMod, "left",  hl.dsp.focus({ workspace = "m-1" }))
bind(mainMod, "right", hl.dsp.focus({ workspace = "m+1" }))
bind(mainMod, "up",    hl.dsp.focus({ direction = "up" }))
bind(mainMod, "down",  hl.dsp.focus({ direction = "down" }))
-- перенести текущее окно на соседний стол
bind(mainMod .. " + SHIFT", "left",  hl.dsp.window.move({ workspace = "m-1" }))
bind(mainMod .. " + SHIFT", "right", hl.dsp.window.move({ workspace = "m+1" }))

-- Перемещение окна
bind(mainMod .. " + SHIFT", "h", hl.dsp.window.move({ direction = "left" }))
bind(mainMod .. " + SHIFT", "l", hl.dsp.window.move({ direction = "right" }))
bind(mainMod .. " + SHIFT", "k", hl.dsp.window.move({ direction = "up" }))
bind(mainMod .. " + SHIFT", "j", hl.dsp.window.move({ direction = "down" }))
-- Окно на соседний монитор целиком
bind(mainMod .. " + ALT", "left",  hl.dsp.window.move({ monitor = "l" }))
bind(mainMod .. " + ALT", "right", hl.dsp.window.move({ monitor = "r" }))
bind(mainMod .. " + ALT", "h",     hl.dsp.window.move({ monitor = "l" }))
bind(mainMod .. " + ALT", "l",     hl.dsp.window.move({ monitor = "r" }))

-- Размер (держать — повторяется)
bind(mainMod .. " + CTRL", "h", hl.dsp.window.resize({ x = -40, y = 0,   relative = true }), { repeating = true })
bind(mainMod .. " + CTRL", "l", hl.dsp.window.resize({ x = 40,  y = 0,   relative = true }), { repeating = true })
bind(mainMod .. " + CTRL", "k", hl.dsp.window.resize({ x = 0,   y = -40, relative = true }), { repeating = true })
bind(mainMod .. " + CTRL", "j", hl.dsp.window.resize({ x = 0,   y = 40,  relative = true }), { repeating = true })

-- Рабочие столы 1–10 (через hypr-ws: столы живут на главном мониторе, см. machine.lua)
for i = 1, 10 do
    local k = tostring(i % 10)   -- 10 → клавиша 0
    bind(mainMod,              k, exec(BIN .. "hypr-ws go " .. i))
    bind(mainMod .. " + SHIFT", k, exec(BIN .. "hypr-ws move " .. i))
end
-- Новый пустой стол справа от текущего; если справа занято — остальные сдвигаются на +1
bind(mainMod,              "N", exec(BIN .. "hypr-ws-insert go"))     -- просто перейти
bind(mainMod .. " + SHIFT", "N", exec(BIN .. "hypr-ws-insert move"))   -- унести туда активное окно
bind(mainMod, "mouse_down", hl.dsp.focus({ workspace = "m+1" }))
bind(mainMod, "mouse_up",   hl.dsp.focus({ workspace = "m-1" }))
-- боковые кнопки мыши: назад (BTN_SIDE) — предыдущий стол, вперёд (BTN_EXTRA) — следующий;
-- hypr-ws-step заодно показывает окошко с номером стола (только для мыши, не для клавиатуры)
bind("", "mouse:275", exec(BIN .. "hypr-ws-step -1"))
bind("", "mouse:276", exec(BIN .. "hypr-ws-step +1"))
-- Win+Tab — панель как на Alt+Tab, но листаются рабочие столы (по недавности), а не окна
-- (дальше — submap wintab ниже)
bind(mainMod,              "TAB", exec(BIN .. "hypr-alttab-ctl start-ws"))
bind(mainMod .. " + SHIFT", "TAB", exec(BIN .. "hypr-alttab-ctl start-ws-prev"))

-- --- ПЕРЕКЛЮЧЕНИЕ ОКОН (Alt+Tab) ---
-- Alt+Tab как в Windows (hypr-alttab): держишь Alt, Tab — следующее окно (по недавности, все
-- столы и мониторы), Shift+Tab — назад, отпустил Alt — остался. Esc — отмена.
-- Мышью: навёл — выбрал, щёлкнул — перешёл.
-- В submap alttab переключает сам демон. Бинды зовут sh-скрипт hypr-alttab-ctl (пишет слово
-- в FIFO демона) — Python на каждое нажатие давал задержку ~40 мс.
bind("ALT",         "TAB", exec(BIN .. "hypr-alttab-ctl start"))
bind("ALT + SHIFT", "TAB", exec(BIN .. "hypr-alttab-ctl start-prev"))

-- Список всех окон со всех столов через fuzzel
bind("ALT", "grave", exec("hypr-switch"))
bind("SUPER", "grave", exec("hypr-switch"))   -- то же на Win+`

-- Перебор окон внутри текущего стола
bind("ALT + CTRL", "TAB", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top" }))
end)
bind("ALT + CTRL + SHIFT", "TAB", function()
    hl.dispatch(hl.dsp.window.cycle_next({ next = false }))
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top" }))
end)

local function alttab(cmd, reset)
    return function()
        hl.dispatch(exec(BIN .. "hypr-alttab-ctl " .. cmd))
        if reset then hl.dispatch(hl.dsp.submap("reset")) end
    end
end

hl.define_submap("alttab", function()
    bind("ALT",         "TAB", exec(BIN .. "hypr-alttab-ctl next"))
    bind("ALT + SHIFT", "TAB", exec(BIN .. "hypr-alttab-ctl prev"))
    bind("ALT", "escape", alttab("cancel", true))
    bind("",    "escape", alttab("cancel", true))
end)

-- То же для Win+Tab (рабочие столы): листаем с зажатым Win, отпустили — перешли
hl.define_submap("wintab", function()
    bind("SUPER",         "TAB", exec(BIN .. "hypr-alttab-ctl next"))
    bind("SUPER + SHIFT", "TAB", exec(BIN .. "hypr-alttab-ctl prev"))
    bind("SUPER", "escape", alttab("cancel", true))
    bind("",      "escape", alttab("cancel", true))
end)

-- Отпустили Alt (или Win) — выбор сделан. Бинды отпускания внутри submap в Hyprland 0.57
-- срабатывают ненадёжно: Alt/Win нажат ещё до входа в submap, и отпускание туда часто не доходит.
-- Поэтому бинды общие (submap_universal), не мешают другим (non_consuming) и сами проверяют,
-- открыта ли панель. С модификатором и без — на случай разного порядка событий.
local function alttab_release(submap)
    return function()
        if hl.get_current_submap() == submap then
            hl.dispatch(exec(BIN .. "hypr-alttab-ctl end"))
            hl.dispatch(hl.dsp.submap("reset"))
        end
    end
end
for _, k in ipairs({ "ALT + Alt_L", "Alt_L", "ALT + Alt_R", "Alt_R" }) do
    hl.bind(k, alttab_release("alttab"), { release = true, transparent = true, non_consuming = true, submap_universal = true })
end
for _, k in ipairs({ "SUPER + Super_L", "Super_L", "SUPER + Super_R", "Super_R" }) do
    hl.bind(k, alttab_release("wintab"), { release = true, transparent = true, non_consuming = true, submap_universal = true })
end

-- Мышь: Super+ЛКМ — двигать, Super+ПКМ — менять размер
bind(mainMod, "mouse:272", hl.dsp.window.drag(),   { mouse = true })
bind(mainMod, "mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Скриншоты
local shot_area = [[grim -g "$(slurp)" - | wl-copy]]
local shot_full = [[grim - | wl-copy]]
local shot_file = [[grim -g "$(slurp)" ~/Pictures/$(date +%Y-%m-%d_%H-%M-%S).png]]
bind("",      "Print", exec(shot_area))
bind("SHIFT", "Print", exec(shot_full))
bind(mainMod, "Print", exec(shot_file))
-- На клавиатуре ноутбука MSI клавиша PrtSc присылает Pause, а не Print
bind("",      "Pause", exec(shot_area))
bind("SHIFT", "Pause", exec(shot_full))
bind(mainMod, "Pause", exec(shot_file))
bind(mainMod .. " + SHIFT", "S", exec(shot_area))   -- как в Windows: область в буфер
bind(mainMod .. " + SHIFT", "P", exec("hyprpicker -a"))

-- btop как диспетчер задач в Windows; повторное нажатие закрывает
bind("CTRL + SHIFT", "Escape", function()
    local found = false
    for _, w in ipairs(hl.get_windows()) do
        if w.class == "btop-popup" then
            found = true
            hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address }))
        end
    end
    if not found then
        hl.dispatch(exec("foot --app-id=btop-popup -e btop"))
    end
end)

-- Мультимедиа и яркость (работают при зажатии и на экране блокировки)
local held   = { locked = true, repeating = true }
local locked = { locked = true }
bind("", "XF86AudioRaiseVolume",  exec("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), held)
bind("", "XF86AudioLowerVolume",  exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      held)
bind("", "XF86AudioMute",         exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     held)
bind("", "XF86AudioMicMute",      exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   held)
-- hypr-brightness сам выберет рабочий путь (sysfs или logind по D-Bus)
bind("", "XF86MonBrightnessUp",   exec("hypr-brightness +5"), held)
bind("", "XF86MonBrightnessDown", exec("hypr-brightness -5"), held)
bind("", "XF86AudioNext",  exec("playerctl next"),       locked)
bind("", "XF86AudioPause", exec("playerctl play-pause"), locked)
bind("", "XF86AudioPlay",  exec("playerctl play-pause"), locked)
bind("", "XF86AudioPrev",  exec("playerctl previous"),   locked)

-- Крышка ноутбука НАМЕРЕННО не обрабатывается: засыпанием занимается logind (HandleLidSwitch=suspend).

------------------------
--- ПРАВИЛА ДЛЯ ОКОН ---
------------------------

local OPAQUE = "1.0 override 1.0 override"   -- без прозрачности, даже когда окно не в фокусе

hl.window_rule({
    name = "hypr-help",                       -- шпаргалка по Super+/
    match = { class = "^hypr-help$" },
    float = true, center = true, rounding = 12,
})

hl.window_rule({
    name = "cliphist-picker",                 -- история буфера Super+V
    match = { class = "^(hypr-cliphist|Hypr-cliphist)$" },
    float = true, size = "600 720", rounding = 12,
})

hl.window_rule({
    name = "wifi-popup",                      -- выбор Wi-Fi (nmtui) по клику на значок сети
    match = { class = "^wifi-popup$" },
    float = true, center = true, size = "700 560", rounding = 12,
})

hl.window_rule({
    name = "volume-popup",                    -- окна громкости и Wi-Fi; позицию задаёт hypr-panel-popup
    match = { class = "^(hypr-volume|Hypr-volume|hypr-wifi|Hypr-wifi)$" },
    float = true, rounding = 12,
})

hl.window_rule({
    -- Постоянные всплывающие окна (hypr_popup.py): живут спрятанными на скрытом столе и по
    -- вызову переезжают на текущий. Без анимации, иначе окно «выплывает» ~0.35 с.
    name = "resident-popups",
    match = { class = "^(hypr-search|hypr-cliphist|hypr-volume|hypr-wifi)$" },
    workspace = "special:hypr-popups silent",
    no_anim = true,
})

hl.window_rule({
    name = "hypr-search",                     -- быстрый поиск Alt+Space; позицию задаёт скрипт
    match = { class = "^hypr-search$" },
    float = true,
    -- окно прозрачное, рамку и скругление рисует сам скрипт вокруг видимой панели
    rounding = 0, border_size = 0, no_shadow = true, no_blur = true,
})

hl.window_rule({
    name = "kde-network-popup",               -- настройки сети KDE по ПКМ на значке сети
    match = { class = "^kcm_networkmanagement$" },
    float = true, center = true, size = "1000 680",
})

hl.window_rule({
    -- Панель Alt+Tab: по центру, поверх всего, без фокуса при появлении. no_focus НЕ ставить:
    -- с ним Hyprland не отдаёт панели мышь (выбор щелчком). Tab/отпускание Alt ловят бинды.
    -- Без тени и размытия: при закрытии панель на миг прозрачная, они остались бы пустым прямоугольником.
    name = "alttab-overlay",
    match = { class = "^(hypr-alttab|Hypr-alttab)$" },
    float = true, center = true, pin = true,
    no_initial_focus = true, no_anim = true, no_shadow = true, no_blur = true,
    border_size = 0, rounding = 14,
    opacity = OPAQUE,
})

hl.window_rule({
    name = "btop-popup",                      -- btop по клику на RAM в панели
    match = { class = "^btop-popup$" },
    float = true, center = true, size = "1100 650", rounding = 12,
})

hl.window_rule({
    -- Telegram не перехватывает фокус при новом сообщении — только уведомление
    name = "telegram-no-steal-focus",
    match = { class = "^(org.telegram.desktop|TelegramDesktop)$" },
    suppress_event = "activate activatefocus",
})

hl.window_rule({
    -- JetBrains (PyCharm и др.): при открытом модальном диалоге мышь на главном окне отдаёт ему
    -- фокус, IDE просит «активировать» диалог обратно, Hyprland дёргает курсор в центр диалога —
    -- и так по кругу. Запросы активации от IDE игнорируем.
    name = "jetbrains-no-steal-focus",
    match = { class = "^jetbrains-.*$" },
    suppress_event = "activate activatefocus",
    focus_on_activate = false,
})

hl.window_rule({
    name = "suppress-maximize",               -- игнорировать запросы на разворот от приложений
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",              -- чинит перетаскивание в XWayland
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

hl.window_rule({
    name = "float-kde-dialogs",               -- системные диалоги — плавающими по центру
    match = { class = "^(org.kde.polkit-kde-authentication-agent-1|pavucontrol|blueman-manager|nm-connection-editor|wdisplays|udiskie)$" },
    float = true, center = true,
})

hl.window_rule({
    name = "float-file-dialogs",              -- диалоги открытия/сохранения файлов
    match = { title = "^(Open File|Save File|Открыть файл|Сохранить файл|Выберите файл)(.*)$" },
    float = true, center = true, size = "900 600",
})

hl.window_rule({
    -- mpv-pip: маленькое окно поверх всех в правом нижнем углу (Ctrl+P в mpv — то же через mpv-pip-hypr)
    name = "mpv-pip",
    match = { class = "^mpv-pip$" },
    float = true, pin = true, no_blur = true, opacity = OPAQUE,
    keep_aspect_ratio = true,
    size = "576 324",
    move = "monitor_w-window_w-16 monitor_h-window_h-16",
})

hl.window_rule({
    name = "mpv-ctrlp-pip-opaque",            -- обычный mpv в режиме PiP — без прозрачности
    match = { class = "^mpv$", float = true, pin = true },
    opacity = OPAQUE,
})

hl.window_rule({
    name = "pip-on-top",                      -- Picture-in-Picture поверх всех, без блюра
    match = { title = "^(Picture-in-Picture|Картинка в картинке)$" },
    float = true, pin = true, no_blur = true, opacity = OPAQUE,
    move = "monitor_w-window_w-20 monitor_h-window_h-40",
    size = "640 360",
})

hl.window_rule({
    -- Главное окно Steam (XWayland) — в сетку как обычное окно (друзья и диалоги не трогаются)
    name = "steam-client-tile",
    match = { class = "^steam$", title = "^Steam$" },
    tile = true,
})

hl.window_rule({
    name = "steam-friends-float",             -- список друзей Steam — узкое плавающее окно
    match = { class = "^steam$", title = "^(Friends List|Список друзей)$" },
    float = true, size = "360 700",
})

hl.window_rule({
    -- Игры Steam: без эффектов и с tearing — ниже задержка ввода.
    -- Если разрывы картинки будут мешать — убери immediate.
    name = "steam-games",
    match = { class = "^(steam_app_\\d+|gamescope|steam_proton)$" },
    immediate = true, no_blur = true, no_anim = true, rounding = 0, border_size = 0,
})

hl.window_rule({
    -- окна игр через Wine/Proton иногда открываются за краем экрана (x < 0) — плавающие ставим в центр
    name = "games-center",
    match = { class = "^(steam_app_\\d+|steam_proton)$", float = true },
    center = true,
})

hl.window_rule({
    -- игры всегда открываются на главном мониторе. XWayland раскладывает мониторы по-своему
    -- (в ряд по номеру: HDMI первым), и игры через Wine промахиваются мимо экрана
    name = "games-main-monitor",
    match = { class = "^(steam_app_\\d+|steam_proton)$" },
    monitor = "DP-2",
})

hl.window_rule({
    -- Cyberpunk открывается окном 1024x768 за краем экрана — сразу на весь главный монитор.
    -- Другие игры с той же бедой — добавить их заголовок сюда через |
    name = "games-force-fullscreen",
    match = { class = "^steam_app_\\d+$", title = "^(Cyberpunk 2077.*)$" },
    fullscreen = true,
})

hl.window_rule({
    -- Wallpaper Engine (app 431960) — не игра: перебиваем steam-games, обычное окно в сетке
    name = "wallpaper-engine-normal",
    match = { class = "^steam_app_431960$" },
    tile = true, immediate = false, no_anim = false, rounding = 8, border_size = 2,
})

hl.window_rule({
    -- PortProton и всё, что запущено через Wine (класс окна = имя .exe): плавающие окна
    -- «как в Windows» — сами выбирают размер и позицию, в сетку не встают.
    -- Полноэкранные игры от этого не страдают: fullscreen перекрывает float.
    -- steam_proton — игры, запущенные через Proton вне Steam (так делает PortProton);
    -- игры из самого Steam получают класс steam_app_N и сюда не попадают.
    name = "wine-float",
    match = { class = "^(.*\\.exe|steam_proton|ru\\.linux_gaming\\.PortProton|[Pp]ort[Pp]roton)$" },
    float = true,
})

hl.window_rule({
    name = "games-no-effects",                -- полноэкранным окнам — ноль эффектов
    match = { fullscreen = true },
    no_blur = true, rounding = 0, border_size = 0,
})

-------------------------
--- ПРАВИЛА ДЛЯ СЛОЁВ ---
-------------------------

hl.layer_rule({ name = "blur-waybar",        match = { namespace = "waybar" },        blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ name = "blur-qs-bar",        match = { namespace = "qs-bar" },        blur = true, ignore_alpha = 0.3 })
-- без анимации: плашка EN/RU (тоже уведомление mako) появляется сразу
hl.layer_rule({ name = "blur-notifications", match = { namespace = "notifications" }, blur = true, ignore_alpha = 0.3, no_anim = true })
hl.layer_rule({ name = "blur-launcher",      match = { namespace = "launcher" },      blur = true, ignore_alpha = 0.3 })

--------------------------------
--- ЛОКАЛЬНЫЕ ПЕРЕОПРЕДЕЛЕНИЯ ---
--------------------------------
-- Всё личное клади в local.lua — он не перезапишется при обновлении этого файла.
if file_exists(CFG .. "/local.lua") then
    require(CFG .. "/local.lua")
end
