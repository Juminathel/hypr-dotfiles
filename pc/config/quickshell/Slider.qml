import QtQuick

// Ползунок 0..to: тянуть мышью, щёлкнуть в любое место, колесо ±5.
// value — то, что показывать; moved(v) — пользователь двигает (v — целое).
Item {
    id: s
    property real value: 0
    property real to: 100
    property bool muted: false
    signal moved(int v)

    implicitHeight: 22
    implicitWidth: 200

    readonly property real frac: Math.max(0, Math.min(1, value / to))

    Rectangle {   // желоб
        anchors.verticalCenter: parent.verticalCenter
        x: 8; width: parent.width - 16; height: 6; radius: 4
        color: "#45475a"
        Rectangle {   // заполненная часть
            width: parent.width * s.frac; height: parent.height; radius: 4
            color: s.muted ? Theme.dim : Theme.blue
        }
    }
    Rectangle {   // ручка
        anchors.verticalCenter: parent.verticalCenter
        x: 8 + (parent.width - 16) * s.frac - width / 2
        width: 16; height: 16; radius: 8
        color: area.containsMouse || area.pressed ? "#ffffff" : Theme.text
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function pick(x) {
            const f = Math.max(0, Math.min(1, (x - 8) / (width - 16)))
            s.moved(Math.round(f * s.to))
        }
        onPressed: mouse => pick(mouse.x)
        onPositionChanged: mouse => { if (pressed) pick(mouse.x) }
        onWheel: wheel => s.moved(Math.max(0, Math.min(s.to, Math.round(s.value) + (wheel.angleDelta.y > 0 ? 5 : -5))))
    }
}
