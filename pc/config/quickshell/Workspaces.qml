import QtQuick
import Quickshell
import Quickshell.Hyprland

// Номера рабочих столов ЭТОГО монитора (all-outputs: false).
// Главный монитор — столы 1–10 (1–5 всегда видны: persistent в hyprland.conf).
// Второй монитор — столы 11–20, подписаны 1–10 (их держит hypr-ws-compact).
Row {
    id: root
    required property var monitor   // HyprlandMonitor
    signal activated()               // щёлкнули по столу — панель закроет свои окна
    spacing: 2

    readonly property var list: Hyprland.workspaces.values
        .filter(w => w.id > 0 && w.monitor === root.monitor)
        .sort((a, b) => a.id - b.id)

    Repeater {
        model: root.list

        delegate: MouseArea {
            id: btn
            required property var modelData
            readonly property var ws: modelData
            readonly property bool active: ws.active
            readonly property bool empty: (ws.toplevels?.values.length ?? 0) === 0
            readonly property bool urgent: ws.urgent ?? false

            implicitWidth: Math.max(36, num.implicitWidth + 18)
            implicitHeight: Theme.barHeight
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // ws.activate() шлёт старое `dispatch workspace N`, а Hyprland 0.57+ ждёт Lua
            onClicked: { root.activated(); Hyprland.dispatch(`hl.dsp.focus({workspace = "${ws.id}"})`) }

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 3
                anchors.bottomMargin: 3
                radius: 7
                color: btn.urgent ? Theme.red
                     : btn.active ? Theme.blue
                     : btn.containsMouse ? Qt.rgba(205 / 255, 214 / 255, 244 / 255, 0.20)
                     : !btn.empty ? Qt.rgba(205 / 255, 214 / 255, 244 / 255, 0.10)
                     : "transparent"
            }
            Text {
                id: num
                anchors.centerIn: parent
                text: btn.ws.id > 10 ? btn.ws.id - 10 : btn.ws.id
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: !btn.empty || btn.active
                color: (btn.urgent || btn.active) ? Theme.crust
                     : btn.containsMouse ? Theme.text
                     : btn.empty ? Theme.dim
                     : Theme.text
            }
        }
    }
}
