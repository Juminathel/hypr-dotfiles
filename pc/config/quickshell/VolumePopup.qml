import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Окно громкости под значком звука (вместо hypr-volume):
//   вывод      — выбор устройства (если их несколько), громкость, выключить звук
//   микрофон   — громкость, выключить
//   программы  — громкость каждой программы, которая сейчас играет звук
//   «микшер…»  — полный pavucontrol
Pop {
    id: pop

    readonly property var nodes: Pipewire.nodes.values
    readonly property var sinks: nodes.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var streams: nodes.filter(n => n.audio && !n.isSink && n.isStream)
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    // громкость видна, только если узел «привязан»
    PwObjectTracker { objects: pop.sinks.concat(pop.streams, [pop.source]) }

    // Короткие имена устройств — активный порт («Line Out», «HDMI / DisplayPort»):
    // в PipeWire его нет, берём у pactl. Пока не пришло — короткое имя узла.
    property var ports: ({})
    function label(n) { return ports[n.name] || n.nickname || n.description || n.name }
    Process {
        id: portq
        command: ["pactl", "-f", "json", "list", "sinks"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const m = {}
                    for (const s of JSON.parse(this.text)) {
                        const p = (s.ports || []).find(p => p.name === s.active_port)
                        if (p) m[s.name] = p.description
                    }
                    pop.ports = m
                } catch (e) {}
            }
        }
    }
    onOpened: portq.running = true

    function icon(n, mic) {
        if (!n?.audio) return ""
        if (n.audio.muted) return mic ? "󰍭" : "󰝟"
        if (mic) return "󰍬"
        const v = n.audio.volume * 100
        return v < 34 ? "󰕿" : v < 67 ? "󰖀" : "󰕾"
    }

    // строка: [значок-кнопка выкл] [ползунок] [NN%]
    component VolRow: Row {
        id: vr
        required property var node
        property bool mic: false
        width: parent.width
        spacing: 6
        readonly property int pct: Math.round((node?.audio?.volume ?? 0) * 100)
        readonly property bool muted: node?.audio?.muted ?? false

        MouseArea {
            width: 32; height: 28
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (vr.node?.audio) vr.node.audio.muted = !vr.node.audio.muted
            Rectangle {
                anchors.fill: parent; radius: 8
                color: parent.containsMouse ? Qt.rgba(69 / 255, 71 / 255, 90 / 255, 0.6) : "transparent"
            }
            Text {
                anchors.centerIn: parent
                text: pop.icon(vr.node, vr.mic)
                color: vr.muted ? Theme.red : Theme.text
                font.family: Theme.iconFont; font.pixelSize: 20
            }
        }
        Slider {
            width: parent.width - 32 - 46 - 2 * parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            value: vr.pct
            muted: vr.muted
            onMoved: v => { if (vr.node?.audio) vr.node.audio.volume = v / 100 }
        }
        Text {
            width: 46
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: vr.pct + "%"
            color: "#9399b2"
            font.family: Theme.font; font.pixelSize: 13
        }
    }

    component Section: Text {
        topPadding: 6
        color: "#7f849c"
        font.family: Theme.font; font.pixelSize: 12
    }
    component Caption: Text {
        width: parent.width
        elide: Text.ElideRight
        color: "#bac2de"
        font.family: Theme.font; font.pixelSize: 13
    }

    Text {
        text: "звук"
        color: Theme.blue
        font.family: Theme.font; font.pixelSize: 15; font.bold: true
    }

    Section { text: "вывод" }
    // несколько устройств — список, текущее отмечено
    Repeater {
        model: pop.sinks.length > 1 ? pop.sinks : []
        delegate: MouseArea {
            id: so
            required property var modelData
            readonly property bool cur: modelData === pop.sink
            width: parent.width; height: 28
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Pipewire.preferredDefaultAudioSink = modelData
            Rectangle {
                anchors.fill: parent; radius: 8
                color: so.cur ? "#313244" : so.containsMouse ? Qt.rgba(69 / 255, 71 / 255, 90 / 255, 0.6) : "transparent"
                border.color: so.cur ? "#45475a" : "transparent"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 10; width: parent.width - 40
                elide: Text.ElideRight
                text: pop.label(so.modelData)
                color: so.cur ? Theme.text : Theme.subtext
                font.family: Theme.font; font.pixelSize: 13
            }
            Text {
                visible: so.cur
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right; anchors.rightMargin: 10
                text: "󰄬"; color: Theme.green
                font.family: Theme.iconFont; font.pixelSize: 14
            }
        }
    }
    Caption { visible: pop.sinks.length <= 1 && pop.sink !== null; text: pop.sink ? pop.label(pop.sink) : "" }
    VolRow { visible: pop.sink !== null; node: pop.sink }

    Section { visible: pop.source !== null; text: "микрофон" }
    VolRow { visible: pop.source !== null; node: pop.source; mic: true }

    Section { visible: pop.streams.length > 0; text: "программы" }
    Repeater {
        model: pop.streams
        delegate: Column {
            id: st
            required property var modelData
            width: parent.width
            readonly property var p: modelData.properties ?? {}
            readonly property string app: p["application.name"] || p["application.process.binary"] || modelData.name || "?"
            readonly property string media: p["media.name"] || ""
            Caption { text: !st.media || st.media === st.app ? st.app : st.app + " — " + st.media }
            VolRow { node: st.modelData }
        }
    }

    Rectangle { width: parent.width; height: 1; color: "#313244" }
    Item {
        width: parent.width; height: 26
        MouseArea {
            anchors.right: parent.right
            width: mixer.implicitWidth + 14; height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { Quickshell.execDetached(["pavucontrol"]); pop.open = false }
            Rectangle {
                anchors.fill: parent; radius: 8
                color: parent.containsMouse ? Qt.rgba(69 / 255, 71 / 255, 90 / 255, 0.6) : "transparent"
            }
            Text {
                id: mixer
                anchors.centerIn: parent
                text: "микшер…"
                color: Theme.blue
                font.family: Theme.font; font.pixelSize: 13
            }
        }
    }
}
