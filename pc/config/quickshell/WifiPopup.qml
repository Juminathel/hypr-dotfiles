import QtQuick
import Quickshell
import Quickshell.Io

// Окно Wi-Fi под значком сети (вместо hypr-wifi):
//   переключатель в заголовке — включить/выключить Wi-Fi
//   щелчок по сети            — подключиться; нужен пароль — под сетью появится поле ввода
//   щелчок по текущей сети ✓  — отключиться
//   vpn                       — WireGuard (WARP) и VPN-плагины NetworkManager, вкл/выкл
//   «настройки сети…»         — полные настройки KDE (то же, что ПКМ по значку)
// Список сразу из кэша NetworkManager, в фоне — новый поиск; пока открыто — обновление раз в 8 с.
Pop {
    id: pop

    readonly property var bars: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    readonly property var vpnText: ({ "activated": "подключён", "activating": "подключаюсь…",
                                      "deactivating": "отключаюсь…", "": "выключен" })

    property bool radio: false
    property var nets: []           // [{ssid, sig, sec, cur, saved}] — текущая первой
    property var vpns: []           // [{name, uuid, state}]
    property var vpnBusy: ({})      // uuid → activating/deactivating
    property var vpnErr: ({})       // uuid → текст ошибки
    property bool busy: false       // подключаемся/отключаемся
    property string pwFor: ""       // SSID, для которой открыто поле пароля
    property string status: ""
    property bool statusErr: false

    // строка nmcli -t: поля через «:», двоеточие внутри поля экранировано «\:»
    function splitT(line) {
        const out = []
        let cur = "", esc = false
        for (const ch of line) {
            if (esc) { cur += ch; esc = false }
            else if (ch === "\\") esc = true
            else if (ch === ":") { out.push(cur); cur = "" }
            else cur += ch
        }
        out.push(cur)
        return out
    }

    function setStatus(text, err) { status = text; statusErr = !!err }

    // ---------- чтение состояния ----------
    Process {
        id: reload
        property bool again: false
        command: ["sh", "-c", `
printf 'radio\\t%s\\n' "$(nmcli radio wifi)"
nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan no | sed 's/^/wifi\\t/'
nmcli -t -f UUID,STATE connection show --active | sed 's/^/active\\t/'
nmcli -t -f NAME,UUID,TYPE connection show | sed 's/^/conn\\t/'
for u in $(nmcli -t -f UUID,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1}'); do
  printf 'saved\\t%s\\n' "$(nmcli -g 802-11-wireless.ssid connection show "$u")"
done`]
        stdout: StdioCollector { onStreamFinished: pop.apply(this.text) }
        onExited: if (again) { again = false; running = true }
    }
    function refresh() { if (reload.running) reload.again = true; else reload.running = true }

    function apply(out) {
        const nets = {}, active = {}, saved = {}, vpns = []
        let radio = false
        for (const line of out.split("\n")) {
            const tab = line.indexOf("\t")
            if (tab < 0) continue
            const kind = line.slice(0, tab), rest = line.slice(tab + 1)
            if (kind === "radio") radio = rest.trim() === "enabled"
            else if (kind === "saved") saved[rest] = true
            else if (kind === "active") { const f = splitT(rest); active[f[0]] = f[1] }
            else if (kind === "wifi") {
                const f = splitT(rest)
                const ssid = f[1] ?? ""
                if (!ssid) continue   // скрытые сети
                const sig = parseInt(f[2] || "0"), sec = !["", "--"].includes((f[3] ?? "").trim())
                const old = nets[ssid] ?? { sig: 0, cur: false }
                nets[ssid] = { ssid: ssid, sig: Math.max(sig, old.sig), sec: sec, cur: f[0] === "*" || old.cur }
            } else if (kind === "conn") {
                const f = splitT(rest)
                if (f[2] === "wireguard" || f[2] === "vpn") vpns.push({ name: f[0], uuid: f[1] })
            }
        }
        pop.radio = radio
        const list = Object.values(nets)
        for (const n of list) n.saved = !!saved[n.ssid]
        list.sort((a, b) => (b.cur - a.cur) || (b.sig - a.sig))
        for (const v of vpns) v.state = active[v.uuid] ?? ""
        vpns.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()))
        pop.vpns = vpns
        // не перестраиваем список, пока подключаемся или вводят пароль
        if (!busy && pwFor === "") pop.nets = radio ? list : []
        if (!busy) {
            const cur = list.find(n => n.cur)
            if (!statusErr || cur)
                setStatus(cur ? `подключено к «${cur.ssid}»` : (radio ? "не подключено" : ""))
        }
    }

    // ---------- действия ----------
    Process {
        id: connectProc
        property string ssid: ""
        property bool withPw: false
        stdout: StdioCollector {
            onStreamFinished: {
                const r = {}
                for (const l of this.text.split("\n")) { const i = l.indexOf(" "); if (i > 0) r[l.slice(0, i)] = l.slice(i + 1) }
                pop.connectDone(connectProc.ssid, r.rc === "0", r.prof === "1", r.msg ?? "", connectProc.withPw)
            }
        }
    }
    function doConnect(ssid, password) {
        busy = true
        setStatus(`подключаюсь к «${ssid}»…`)
        connectProc.ssid = ssid
        connectProc.withPw = !!password
        connectProc.command = ["sh", "-c", `
ssid=$1; pw=$2; prof=
for u in $(nmcli -t -f UUID,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1}'); do
  [ "$(nmcli -g 802-11-wireless.ssid connection show "$u")" = "$ssid" ] && { prof=$u; break; }
done
if [ -n "$prof" ]; then
  [ -n "$pw" ] && nmcli connection modify "$prof" wifi-sec.psk "$pw"
  out=$(timeout 60 nmcli connection up "$prof" 2>&1)
elif [ -n "$pw" ]; then
  out=$(timeout 60 nmcli device wifi connect "$ssid" password "$pw" 2>&1)
else
  out=$(timeout 60 nmcli device wifi connect "$ssid" 2>&1)
fi
echo "rc $?"
echo "prof \${prof:+1}"
echo "msg $(printf '%s' "$out" | tail -n1)"`, "sh", ssid, password ?? ""]
        connectProc.running = true
    }
    function connectDone(ssid, ok, hadProfile, msg, withPw) {
        const n = nets.find(n => n.ssid === ssid)
        if (!ok && n?.sec && !withPw) {
            busy = false
            setStatus(hadProfile ? "пароль не подошёл" : "нужен пароль", true)
            pwFor = ssid
            return
        }
        busy = false
        if (ok) setStatus(`подключено к «${ssid}»`)
        else setStatus(msg || `не удалось подключиться к «${ssid}»`, true)
        refresh()
    }

    Process {
        id: oneShot   // отключиться / радио — потом обновить
        property int after: 200
        onExited: { pop.busy = false; refreshLater.interval = after; refreshLater.restart() }
    }
    Timer { id: refreshLater; onTriggered: pop.refresh() }

    function pickNet(n) {
        if (busy) return
        if (n.cur) {
            busy = true
            setStatus(`отключаюсь от «${n.ssid}»…`)
            oneShot.after = 200
            oneShot.command = ["sh", "-c", "d=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2==\"wifi\"{print $1; exit}'); nmcli device disconnect \"${d:-wlan0}\""]
            oneShot.running = true
            return
        }
        pwFor = ""
        if (n.sec && !n.saved) pwFor = n.ssid
        else doConnect(n.ssid)
    }

    function setRadio(on) {
        setStatus(on ? "включаю Wi-Fi…" : "")
        radio = on
        oneShot.after = on ? 1500 : 200
        oneShot.command = ["nmcli", "radio", "wifi", on ? "on" : "off"]
        oneShot.running = true
    }

    // VPN — у каждого свой процесс, поэтому через Component
    Component {
        id: vpnProc
        Process {
            property string uuid
            property bool on
            stdout: StdioCollector { id: o }
            stderr: StdioCollector { id: e }
            onExited: code => {
                const b = Object.assign({}, pop.vpnBusy); delete b[uuid]; pop.vpnBusy = b
                if (code !== 0) {
                    const lines = (e.text || o.text).trim().split("\n")
                    const msg = (lines[lines.length - 1] || "").split(": ").pop().slice(0, 60)
                    const er = Object.assign({}, pop.vpnErr); er[uuid] = msg || "не удалось"; pop.vpnErr = er
                }
                pop.refresh()
                destroy()
            }
        }
    }
    function vpnToggle(v, on) {
        const b = Object.assign({}, vpnBusy); b[v.uuid] = on ? "activating" : "deactivating"; vpnBusy = b
        const er = Object.assign({}, vpnErr); delete er[v.uuid]; vpnErr = er
        const p = vpnProc.createObject(pop, { uuid: v.uuid, on: on,
            command: ["timeout", "60", "nmcli", "connection", on ? "up" : "down", v.uuid] })
        p.running = true
    }

    Process { id: rescan; command: ["nmcli", "device", "wifi", "rescan"]; onExited: { refreshLater.interval = 2500; refreshLater.restart() } }
    Timer { interval: 8000; repeat: true; running: pop.visible; onTriggered: pop.refresh() }

    onOpened: {
        pwFor = ""
        refresh()
        rescan.running = true
    }
    Component.onCompleted: refresh()

    // ---------- вид ----------
    component Hover: Rectangle {
        property bool on: false
        anchors.fill: parent; radius: 8
        color: on ? Qt.rgba(69 / 255, 71 / 255, 90 / 255, 0.6) : "transparent"
    }
    component Small: Text {
        color: "#7f849c"
        font.family: Theme.font; font.pixelSize: 12
    }

    Item {
        width: parent.width; height: 26
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "wi-fi"
            color: Theme.blue
            font.family: Theme.font; font.pixelSize: 15; font.bold: true
        }
        Toggle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: pop.radio
            onToggled: on => pop.setRadio(on)
        }
    }

    Small {
        visible: pop.status !== ""
        width: parent.width
        elide: Text.ElideRight
        text: pop.status
        color: pop.statusErr ? Theme.red : "#9399b2"
    }

    Small { topPadding: 6; text: "сети" }

    Flickable {
        width: parent.width
        height: Math.min(330, Math.max(30, netCol.implicitHeight))
        contentHeight: netCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: netCol
            width: parent.width
            spacing: 2

            Small {
                visible: pop.nets.length === 0
                leftPadding: 8; topPadding: 6
                text: pop.radio ? "ищу сети…" : "Wi-Fi выключен"
            }

            Repeater {
                model: pop.nets
                delegate: Column {
                    id: row
                    required property var modelData
                    readonly property var n: modelData
                    width: netCol.width
                    spacing: 2

                    MouseArea {
                        width: parent.width; height: 34
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pop.pickNet(row.n)
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: row.n.cur ? "#45475a" : parent.containsMouse ? Qt.rgba(69 / 255, 71 / 255, 90 / 255, 0.6) : "transparent"
                            border.width: 2
                            border.color: row.n.cur ? Theme.blue : "transparent"
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10; spacing: 10
                            width: parent.width - 20
                            Text {
                                text: pop.bars[Math.min(Math.floor(row.n.sig / 20), 4)]
                                color: row.n.sig < 35 ? "#7f849c" : Theme.blue
                                font.family: Theme.iconFont; font.pixelSize: 18
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 30 - 60
                                elide: Text.ElideRight
                                text: row.n.ssid
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 14
                            }
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right; anchors.rightMargin: 10
                            spacing: 8
                            Text { visible: row.n.sec; text: "󰌾"; color: "#7f849c"; font.family: Theme.iconFont; font.pixelSize: 14 }
                            Text { visible: row.n.cur; text: "󰄬"; color: Theme.green; font.family: Theme.iconFont; font.pixelSize: 14 }
                        }
                    }

                    // поле пароля под сетью
                    Rectangle {
                        visible: pop.pwFor === row.n.ssid
                        width: parent.width; height: 32
                        radius: 8
                        color: "#313244"
                        border.color: pw.activeFocus ? Theme.blue : "#45475a"
                        onVisibleChanged: if (visible) { pw.text = ""; pw.forceActiveFocus() }
                        TextInput {
                            id: pw
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 14
                            clip: true
                            onAccepted: if (text) { const s = pop.pwFor; pop.pwFor = ""; pop.doConnect(s, text) }
                            Keys.onEscapePressed: pop.open = false
                            Text {
                                visible: !pw.text
                                anchors.verticalCenter: parent.verticalCenter
                                text: `пароль «${row.n.ssid}», Enter`
                                color: "#6c7086"
                                font: pw.font
                            }
                        }
                    }
                }
            }
        }
    }

    Small { visible: pop.vpns.length > 0; topPadding: 6; text: "vpn" }
    Repeater {
        model: pop.vpns
        delegate: Item {
            id: vrow
            required property var modelData
            readonly property var v: modelData
            readonly property string state: pop.vpnBusy[v.uuid] ?? v.state
            readonly property string err: pop.vpnErr[v.uuid] ?? ""
            readonly property bool on: state === "activated"
            width: parent.width; height: 40
            Text {
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                text: "󰦝"
                color: vrow.on ? Theme.green : "#7f849c"
                font.family: Theme.iconFont; font.pixelSize: 17
            }
            Column {
                x: 40
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 40 - 54
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: vrow.v.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14
                }
                Small {
                    text: vrow.err || (pop.vpnText[vrow.state] ?? vrow.state)
                    color: vrow.err ? Theme.red : vrow.on ? Theme.green : "#7f849c"
                }
            }
            Toggle {
                anchors.right: parent.right; anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                checked: vrow.state === "activated" || vrow.state === "activating"
                onToggled: on => pop.vpnToggle(vrow.v, on)
            }
        }
    }

    Rectangle { width: parent.width; height: 1; color: "#313244" }
    Item {
        width: parent.width; height: 26
        MouseArea {
            anchors.right: parent.right
            width: link.implicitWidth + 14; height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { Quickshell.execDetached(["kcmshell6", "kcm_networkmanagement"]); pop.open = false }
            Hover { on: parent.containsMouse }
            Text {
                id: link
                anchors.centerIn: parent
                text: "настройки сети…"
                color: Theme.blue
                font.family: Theme.font; font.pixelSize: 13
            }
        }
    }
}
