-- machine.lua домашнего ПК: Ryzen 5 5600 + RTX 5060 Ti 16 ГБ (одна видеокарта NVIDIA), Arch Linux.
-- install.sh копирует этот файл в ~/.config/hypr/machine.lua, если его там ещё нет.

----------------
--- МОНИТОРЫ ---
----------------
-- Узнать имена и режимы: hyprctl monitors all
-- Mi Monitor 2560x1440 (DP-2) — главный, на нём столы 1–5; HDMI-A-1 1366x768 — слева от него.
-- Поменять местами: HDMI на position = "2560x0", DP-2 на "0x0".
hl.monitor({ output = "DP-2",     mode = "2560x1440@240", position = "1366x0", scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "preferred",     position = "0x0",    scale = 1 })
hl.monitor({ output = "",         mode = "preferred",     position = "auto",   scale = "auto" })   -- любой другой

-------------------
--- ВИДЕОКАРТА ---
-------------------
-- NVIDIA, драйвер nvidia-open (для RTX 50xx — только открытый модуль).
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
-- Если курсор мерцает или пропадает — раскомментировать:
-- hl.config({ cursor = { no_hardware_cursors = true } })

-- Меню программ для Dolphin «Открыть с помощью» (пакет archlinux-xdg-menu)
hl.env("XDG_MENU_PREFIX", "arch-")

-----------------------
--- РАБОЧИЕ СТОЛЫ  ---
-----------------------
-- 1–5 на главном мониторе видны на панели всегда, 6–10 появляются по мере надобности.
for i = 1, 10 do
    hl.workspace_rule({
        workspace  = tostring(i),
        monitor    = "DP-2",
        persistent = i <= 5,
        default    = i == 1,
    })
end
