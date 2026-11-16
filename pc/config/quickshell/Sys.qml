pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Общие данные для всех панелей (по одной на монитор): память, температура, батарея,
// сеть, подсветка, раскладка, submap. Опрос раз в 5 с, как interval в waybar.
Singleton {
    id: sys

    // память, ГиБ
    property real memUsed: 0
    property real memTotal: 0
    property int memPct: 0

    // температура процессора, °C (-1 — датчика нет)
    property int temp: -1

    // батарея (hasBat = false на ПК — модуль скрыт)
    property bool hasBat: false
    property int batCap: 0
    property string batStatus: ""      // Charging / Discharging / Full / Not charging
    property real batWatts: 0
    property real batHours: -1         // до разряда/до полной, ч

    // подсветка экрана (на ПК нет — модуль скрыт)
    property bool hasLight: false
    property int lightPct: 0

    // сеть
    property string netType: ""        // wifi / ethernet / "" — нет соединения
    property string netName: ""        // SSID или имя подключения
    property string netDev: ""
    property int netSignal: 0
    property string netIp: ""
    property string netDown: ""
    property string netUp: ""
    property real _rx: -1
    property real _tx: -1
    property real _t: 0

    // заголовок последнего активного окна каждого стола: { id стола: заголовок }
    // (то же поле lastwindowtitle, по которому waybar пишет заголовок на каждом мониторе)
    property var titles: ({})
    property var wsWindows: ({})

    // раскладка и submap
    property string layout: ""
    property string submap: ""

    // ---------- опрос /proc и /sys ----------
    // Температура: сначала датчик процессора (k10temp/coretemp/zenpower), иначе thermal_zone0.
    // (на ПК thermal_zone0 — это Wi-Fi-карта, она отдаёт «No data»)
    readonly property string pollScript: `
awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{printf "mem %.3f %.3f %d\\n", (t-a)/1048576, t/1048576, (t-a)*100/t}' /proc/meminfo
t=
for h in /sys/class/hwmon/hwmon*; do
  case $(cat $h/name 2>/dev/null) in k10temp|coretemp|zenpower) t=$(cat $h/temp1_input 2>/dev/null); break;; esac
done
[ -z "$t" ] && t=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
echo "temp \${t:--1000}"
for b in /sys/class/power_supply/BAT*; do
  [ -e "$b/capacity" ] || continue
  p=$(cat $b/power_now 2>/dev/null); [ -z "$p" ] && p=$(( $(cat $b/current_now 2>/dev/null || echo 0) * $(cat $b/voltage_now 2>/dev/null || echo 0) / 1000000 ))
  e=$(cat $b/energy_now 2>/dev/null || cat $b/charge_now 2>/dev/null || echo 0)
  f=$(cat $b/energy_full 2>/dev/null || cat $b/charge_full 2>/dev/null || echo 0)
  echo "bat $(cat $b/capacity) \${p:-0} $e $f $(cat $b/status | tr ' ' _)"
  break
done
for l in /sys/class/backlight/*; do
  [ -e "$l/brightness" ] || continue
  echo "light $(cat $l/brightness) $(cat $l/max_brightness)"
  break
done
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null | while IFS=: read -r dev type state con; do
  [ "$state" = connected ] || continue
  case $type in wifi|ethernet) ;; *) continue;; esac
  sig=0
  [ "$type" = wifi ] && sig=$(nmcli -t -f IN-USE,SIGNAL dev wifi list ifname "$dev" --rescan no 2>/dev/null | awk -F: '$1=="*"{print $2; exit}')
  ip=$(ip -4 -br addr show dev "$dev" | awk '{print $3}')
  echo "net $type $dev \${sig:-0} \${ip:--} $(cat /sys/class/net/$dev/statistics/rx_bytes) $(cat /sys/class/net/$dev/statistics/tx_bytes) $con"
  break
done
echo end
`

    function bits(bytesPerSec) {
        let b = bytesPerSec * 8
        const u = ["b/s", "kb/s", "Mb/s", "Gb/s"]
        let i = 0
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++ }
        return (i === 0 ? Math.round(b) : b.toFixed(1)) + u[i]
    }

    function parse(out) {
        let bat = false, light = false, net = false
        for (const line of out.split("\n")) {
            const f = line.split(" ")
            switch (f[0]) {
            case "mem":
                memUsed = parseFloat(f[1]); memTotal = parseFloat(f[2]); memPct = parseInt(f[3])
                break
            case "temp": {
                const t = parseInt(f[1])
                temp = t > -1000 ? Math.round(t / 1000) : -1
                break
            }
            case "bat": {
                bat = true
                batCap = parseInt(f[1])
                const p = parseFloat(f[2]) / 1e6, e = parseFloat(f[3]), full = parseFloat(f[4])
                batStatus = f[5].replace(/_/g, " ")
                batWatts = p
                const ew = e / 1e6, fw = full / 1e6     // Вт·ч (или А·ч — тогда часы всё равно верны пропорционально)
                if (p > 0.1 && batStatus === "Discharging") batHours = ew / p
                else if (p > 0.1 && batStatus === "Charging") batHours = (fw - ew) / p
                else batHours = -1
                break
            }
            case "light":
                light = true
                lightPct = Math.round(parseInt(f[1]) * 100 / Math.max(1, parseInt(f[2])))
                break
            case "net": {
                net = true
                netType = f[1]; netDev = f[2]; netSignal = parseInt(f[3]); netIp = f[4]
                netName = f.slice(7).join(" ")
                const rx = parseFloat(f[5]), tx = parseFloat(f[6]), now = Date.now() / 1000
                if (_rx >= 0 && now > _t) {
                    netDown = bits((rx - _rx) / (now - _t))
                    netUp = bits((tx - _tx) / (now - _t))
                }
                _rx = rx; _tx = tx; _t = now
                break
            }
            }
        }
        hasBat = bat
        hasLight = light
        if (!net) { netType = ""; netName = ""; netDev = ""; netIp = ""; _rx = -1 }
    }

    Process {
        id: poll
        command: ["sh", "-c", sys.pollScript]
        stdout: StdioCollector { onStreamFinished: sys.parse(this.text) }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: sys.refresh()
    }
    // обновить сразу (после прокрутки подсветки и т.п.)
    function refresh() { if (!poll.running) poll.running = true }

    // ---------- раскладка клавиатуры ----------
    Process {
        id: kbd
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const k = JSON.parse(this.text).keyboards.find(k => k.main)
                    if (!k) return
                    const names = k.layout.split(",")
                    sys.layout = (names[k.active_layout_index] ?? names[0] ?? "").trim()
                } catch (e) {}
            }
        }
    }
    Process {
        id: wsq
        property bool again: false
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const t = {}, n = {}
                    for (const w of JSON.parse(this.text)) {
                        if (w.id === undefined) continue
                        t[w.id] = w.windows > 0 ? (w.lastwindowtitle ?? "") : ""
                        n[w.id] = w.windows
                    }
                    sys.titles = t
                    sys.wsWindows = n
                } catch (e) {}
            }
        }
        onExited: if (again) { again = false; running = true }
    }
    function refreshTitles() {
        if (wsq.running) wsq.again = true
        else wsq.running = true
    }

    Component.onCompleted: { kbd.running = true; refreshTitles() }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") kbd.running = true
            else if (event.name === "submap") sys.submap = event.data
            else if (["workspace", "workspacev2", "focusedmon", "activewindow", "windowtitle", "windowtitlev2",
                      "openwindow", "closewindow", "movewindow", "movewindowv2", "moveworkspace",
                      "createworkspace", "destroyworkspace"].includes(event.name))
                sys.refreshTitles()
        }
    }
}
