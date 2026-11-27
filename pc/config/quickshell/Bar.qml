import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

// Панель на одном мониторе — повторяет waybar/config.jsonc:
//   слева   — рабочие столы, submap
//   центр   — заголовок активного окна этого монитора
//   справа  — музыка, звук, микрофон, подсветка, сеть, память, температура, батарея, трей, раскладка, часы
// Вид — одна плоская полупрозрачная полоса во всю ширину (как waybar ноутбука).
PanelWindow {
    id: bar
    required property var modelData       // ShellScreen
    screen: modelData
    readonly property var monitor: Hyprland.monitorFor(modelData)

    WlrLayershell.layer: WlrLayer.Bottom  // как "layer": "bottom" — полноэкранные окна поверх
    WlrLayershell.namespace: "qs-bar"     // по нему blur в hyprland.conf и hypr-popup-dismiss

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barHeight
    color: Theme.panel
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.panelLine }

    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]) }

    // меню в fuzzel под значком (hypr-nmdm, hypr-pwmenu, hypr-media; повторный клик закрывает).
    // В $XDG_RUNTIME_DIR/hypr-panel-popup пишем, у какого x открыли: hypr-popup-dismiss, сработав
    // на этот же клик, не закроет только что открытое меню (см. его описание).
    function menu(script) {
        run('printf "menu %s\\n" "$(hyprctl cursorpos | cut -d, -f1)" > "$XDG_RUNTIME_DIR/hypr-panel-popup"; '
            + 'exec "$HOME/.local/bin/' + script + '"')
    }
    // Прежние окна звука и сети (VolumePopup.qml, WifiPopup.qml) больше не открываются, оставлены про запас.

    // общий вид блоков: без подложек, просто ряд модулей на общей полосе
    component Block: Item {
        default property alias items: row.data
        property alias row: row
        implicitWidth: row.implicitWidth + 8
        implicitHeight: Theme.barHeight
        Row { id: row; x: 4; height: parent.height; spacing: 0 }
    }

    // ───────────── слева ─────────────
    Block {
        id: leftBlock
        anchors.left: parent.left
        Workspaces { monitor: bar.monitor }
        Mod {
            visible: Sys.submap !== ""
            text: Sys.submap
            color: Theme.peach
            bold: true
        }
    }

    // ───────────── центр: заголовок окна ─────────────
    // separate-outputs: на каждом мониторе — последнее активное окно ЭТОГО монитора;
    // на пустом столе блок исчезает целиком.
    readonly property int wsId: monitor?.activeWorkspace?.id ?? -1
    readonly property string winTitle: Sys.titles[wsId] ?? ""
    readonly property bool wsEmpty: (Sys.wsWindows[wsId] ?? 0) === 0
    // место под заголовок по центру между боковыми блоками
    function roomWith(rightW) { return width - 2 * Math.max(leftBlock.width, rightW) - 2 * 8 - 8 }
    readonly property real titleRoom: roomWith(rightBlock.width)
    // Заголовок важнее музыки: на узком втором мониторе, если заголовок целиком не влезает рядом
    // с музыкой, музыка прячется. Ширину правого блока без музыки считаем по остальным модулям.
    readonly property bool titleShown: !wsEmpty && winTitle !== ""
    readonly property real rightNoMedia: rightBlock.row.children
        .filter(c => c !== media && c.visible).reduce((w, c) => w + c.width, 0) + 8
    readonly property bool mediaFits: !titleShown
        || roomWith(rightNoMedia + media.implicitWidth) >= titleMod.label.implicitWidth + titleMod.pad * 2

    Block {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: bar.titleShown && bar.titleRoom >= 120
        Mod {
            id: titleMod
            pad: 10
            color: Theme.subtext
            cursorShape: Qt.ArrowCursor
            text: bar.winTitle.length > 40 ? bar.winTitle.slice(0, 39) + "…" : bar.winTitle
            // заголовок по центру не должен наезжать на боковые блоки (узкий второй монитор)
            maxWidth: bar.titleRoom
        }
    }

    // ───────────── справа ─────────────
    readonly property PwNode sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [bar.sink] }
    readonly property int vol: Math.round((sink?.audio?.volume ?? 0) * 100)
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [bar.source] }
    readonly property int micVol: Math.round((source?.audio?.volume ?? 0) * 100)
    readonly property bool micMuted: source?.audio?.muted ?? false

    Block {
        id: rightBlock
        anchors.right: parent.right

        // музыка/видео: значок появляется, только когда что-то играет
        Media { id: media; bar: bar; fits: bar.mediaFits }

        // звук: ЛКМ — pwmenu в fuzzel под значком, ПКМ — без звука, колесо — ±5%
        Mod {
            id: volMod
            visible: bar.sink !== null
            readonly property bool bt: (bar.sink?.name ?? "").startsWith("bluez")
            text: bar.muted ? "󰝟"
                : (bt ? "󰂰" : ["󰕿", "󰖀", "󰕾"][Math.min(2, Math.floor(bar.vol / (100 / 3)))]) + " " + bar.vol + "%"
            color: bar.muted ? Theme.overlay : Theme.text
            tip: bar.sink?.description ?? ""
            onLeftClick: bar.menu("hypr-pwmenu")
            onRightClick: if (bar.sink) bar.sink.audio.muted = !bar.sink.audio.muted
            onWheel: wheel => {
                if (!bar.sink) return
                const step = wheel.angleDelta.y > 0 ? 5 : -5
                const v = Math.max(0, Math.min(100, Math.round((bar.vol + step) / 5) * 5))
                bar.sink.audio.volume = v / 100
            }
        }

        // микрофон: ЛКМ — выкл/вкл, ПКМ — pavucontrol на вкладке «Устройства ввода»,
        // колесо — ±5% (до 150%)
        Mod {
            visible: bar.source !== null
            text: bar.micMuted ? "󰍭" : "󰍬 " + bar.micVol + "%"
            color: bar.micMuted ? Theme.red : Theme.subtext
            tip: "Микрофон: " + (bar.source?.description ?? "")
            onLeftClick: if (bar.source) bar.source.audio.muted = !bar.source.audio.muted
            onRightClick: bar.run("pavucontrol -t 4")
            onWheel: wheel => {
                if (!bar.source) return
                const step = wheel.angleDelta.y > 0 ? 5 : -5
                const v = Math.max(0, Math.min(150, Math.round((bar.micVol + step) / 5) * 5))
                bar.source.audio.volume = v / 100
            }
        }

        // подсветка (на ноутбуке)
        Mod {
            visible: Sys.hasLight
            text: "☀ " + Sys.lightPct + "%"
            color: Theme.text
            onWheel: wheel => {
                bar.run("hypr-brightness " + (wheel.angleDelta.y > 0 ? "+5" : "-5"))
                Sys.refresh()
            }
        }

        // сеть: только значок, подробности в подсказке.
        // ЛКМ — networkmanager-dmenu в fuzzel (Wi-Fi, VPN, кабель), ПКМ — настройки KDE
        Mod {
            id: netMod
            text: Sys.netType === "wifi" ? "󰖩" : Sys.netType === "ethernet" ? "󰈀" : "󰖪"
            color: Sys.netType === "" ? Theme.red : Theme.text
            fontFamily: Theme.iconFont
            fontSize: 17
            tip: Sys.netType === "" ? "Нет сети"
               : (Sys.netType === "wifi" ? Sys.netName + " (" + Sys.netSignal + "%)" : "Кабель " + Sys.netDev)
                 + "\n" + Sys.netIp + (Sys.netDown ? "\n↓" + Sys.netDown + " ↑" + Sys.netUp : "")
            onLeftClick: bar.menu("hypr-nmdm")
            onRightClick: bar.run("kcmshell6 kcm_networkmanagement")
        }

        // память; щелчок — btop
        Mod {
            text: "󰍛 " + Sys.memUsed.toFixed(1) + "G"
            color: Theme.subtext
            tip: Sys.memUsed.toFixed(1) + "G / " + Sys.memTotal.toFixed(1) + "G (" + Sys.memPct + "%)"
            onLeftClick: bar.run("foot --app-id=btop-popup -e btop")
        }

        // температура
        Mod {
            visible: Sys.temp >= 0
            text: Sys.temp + "°C"
            color: Sys.temp >= 85 ? Theme.red : Theme.subtext
            cursorShape: Qt.ArrowCursor
        }

        // батарея: уровень видно по значку и цвету, процент — только ниже 25%
        Mod {
            id: battery
            visible: Sys.hasBat
            readonly property bool charging: Sys.batStatus === "Charging"
            readonly property bool plugged: Sys.batStatus === "Full" || Sys.batStatus === "Not charging"
            readonly property string state: Sys.batCap <= 12 ? "critical" : Sys.batCap <= 25 ? "warning"
                                          : Sys.batCap <= 50 ? "half" : ""
            readonly property bool alarm: state === "critical" && !charging && !plugged
            readonly property string icon: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
                                           [Math.max(0, Math.min(9, Math.floor(Sys.batCap / 10)))]
            text: charging ? "󰂄" : plugged ? "󰚥"
                : icon + ((state === "warning" || state === "critical") ? " " + Sys.batCap + "%" : "")
            fontSize: 17
            property bool blink: false
            color: (charging || plugged) ? Theme.green
                 : alarm ? (blink ? Theme.red : Theme.crust)
                 : state === "warning" ? Theme.peach
                 : state === "half" ? Theme.yellow
                 : Theme.green
            cursorShape: Qt.ArrowCursor
            tip: {
                let t = Sys.batCap + "%"
                if (Sys.batHours > 0) {
                    const h = Math.floor(Sys.batHours), m = Math.round((Sys.batHours - h) * 60)
                    t += " · " + (charging ? "до полной " : "осталось ") + h + " ч " + m + " мин"
                }
                return t + "\n" + Sys.batWatts.toFixed(1) + " Вт"
            }
            Rectangle {
                z: -1
                anchors.fill: parent
                color: Theme.red
                visible: battery.alarm && !battery.blink
            }
            Timer {
                running: battery.alarm
                interval: 500; repeat: true
                onTriggered: battery.blink = !battery.blink
                onRunningChanged: if (!running) battery.blink = false
            }
        }

        Tray { bar: bar }

        // раскладка — у часов: там её не сдвигают ни длинный заголовок окна, ни название трека
        Mod {
            visible: Sys.layout !== ""
            text: Sys.layout
            color: Theme.subtext
            bold: true
            onLeftClick: bar.run("hyprctl switchxkblayout current next")
        }

        Clock {}
    }
}
