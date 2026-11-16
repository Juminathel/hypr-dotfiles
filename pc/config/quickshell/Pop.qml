import QtQuick
import Quickshell
import Quickshell.Hyprland

// Выпадающее окно под значком панели (громкость, Wi-Fi).
// Закрывается: повторным щелчком по значку, щелчком мимо (HyprlandFocusGrab), Esc.
// Пока открыто — получает клавиатуру (нужно для Esc и поля пароля).
PopupWindow {
    id: pop

    required property Item opener   // значок, под которым выпадает
    required property var bar       // окно панели: щелчки по ней не считаются «мимо»
    property bool open: false
    property int popWidth: 380
    default property alias content: col.data

    signal opened()

    anchor.item: opener
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: -6

    color: "transparent"
    implicitWidth: popWidth
    implicitHeight: col.implicitHeight + 28
    visible: open
    onOpenChanged: if (open) opened()

    // Захват включаем чуть позже показа: если окно ещё не появилось на экране,
    // Hyprland сразу снимает захват — и окно закрывалось тем же щелчком, что открыло.
    property bool grabbing: false
    onVisibleChanged: {
        if (visible) grabDelay.restart()
        else { grabDelay.stop(); grabbing = false }
    }
    Timer { id: grabDelay; interval: 50; onTriggered: pop.grabbing = pop.visible }

    HyprlandFocusGrab {
        windows: [pop, pop.bar]
        active: pop.grabbing
        onCleared: {
            console.info("popup: щелчок мимо — закрываю")
            pop.open = false
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(30 / 255, 30 / 255, 46 / 255, 0.94)
        radius: 10
        border.color: Theme.blue
        border.width: 2

        FocusScope {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: pop.open = false

            Column {
                id: col
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 4
            }
        }
    }
}
