import QtQuick
import Quickshell

// Всплывающая подсказка под элементом панели (как tooltip в waybar).
// Появляется через 400 мс наведения. Содержимое — text, либо свой элемент в content.
PopupWindow {
    id: tip

    required property Item target
    property bool hovered: false
    property string text: ""
    property Component content: null

    anchor.item: target
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: -6   // отступ вниз от панели (у якоря отрицательный — наружу)

    color: "transparent"
    implicitWidth: box.implicitWidth
    implicitHeight: box.implicitHeight
    visible: false

    Timer {
        id: delay
        interval: 400
        onTriggered: tip.visible = tip.hovered && (tip.text !== "" || tip.content !== null)
    }
    onHoveredChanged: {
        if (hovered) delay.restart()
        else { delay.stop(); visible = false }
    }

    Rectangle {
        id: box
        color: Theme.tipBg
        border.color: Theme.tipBorder
        border.width: 1
        radius: 8
        implicitWidth: (tip.content ? loader.implicitWidth : label.implicitWidth) + 20
        implicitHeight: (tip.content ? loader.implicitHeight : label.implicitHeight) + 12

        Text {
            id: label
            visible: !tip.content
            anchors.centerIn: parent
            text: tip.text
            textFormat: Text.PlainText
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 14
        }
        Loader {
            id: loader
            anchors.centerIn: parent
            sourceComponent: tip.content
            active: tip.visible
        }
    }
}
