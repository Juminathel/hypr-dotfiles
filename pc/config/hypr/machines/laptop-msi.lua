-- machine.lua ноутбука MSI (AMD 680M + RTX 4050) — для справки, перевод machines/laptop-msi.conf.
-- ВНИМАНИЕ: laptop-only/hypr-gpu-select пишет gpu.conf в старом формате. Для Hyprland 0.57+
-- он должен писать gpu.lua (строки вида hl.env("AQ_DRM_DEVICES", "/dev/dri/card1:/dev/dri/card0")).
-- Подробности про гибридную графику — в machines/laptop-msi.conf.

local CFG = os.getenv("HOME") .. "/.config/hypr"
local ACER = "desc:Acer Technologies RL242Y E 83457AC324708"

-- eDP-1 1920x1080@144; Acer — главный, СПРАВА от ноутбука (по модели, а не по разъёму)
hl.monitor({ output = "eDP-1", mode = "1920x1080@144", position = "0x0", scale = 1 })
hl.monitor({ output = ACER, mode = "1920x1080@100", position = "1920x0", scale = 1 })
-- LG ULTRAWIDE 2560x1080 — тоже главный, когда подключён вместо Acer
hl.monitor({ output = "desc:LG Electronics LG ULTRAWIDE 0x00093C63", mode = "2560x1080@100", position = "1920x0", scale = 1 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- Порядок GPU (AQ_DRM_DEVICES и __GLX_VENDOR_LIBRARY_NAME) выбирает hypr-gpu-select
local f = io.open(CFG .. "/gpu.lua", "r")
if f then
    f:close()
    require(CFG .. "/gpu.lua")
end

-- Аппаратное декодирование видео — через AMD (Mesa)
hl.env("LIBVA_DRIVER_NAME", "radeonsi")
hl.env("VDPAU_DRIVER", "radeonsi")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- Обзор рабочих столов (пакет hyprland-plugin-hyprexpo)
-- hl.plugin.load("/usr/lib/x86_64-linux-gnu/hyprland/plugins/libhyprexpo.so")

-- Acer — главный: столы 1–10 (Win+N через hypr-ws). Без Acer эти столы переезжают на ноутбук.
for i = 1, 10 do
    hl.workspace_rule({ workspace = tostring(i), monitor = ACER, persistent = i <= 5, default = i == 1 })
end
-- Ноутбук при Acer: один стол 11 (не persistent: без Acer он пустеет и пропадает)
hl.workspace_rule({ workspace = "11", monitor = "eDP-1", default = true })
