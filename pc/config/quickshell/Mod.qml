import QtQuick

// Один модуль панели: текст/значок + подсказка + щелчки и колесо.
// Обработчики: onLeftClick, onRightClick, onMiddleClick (сигналы) и onWheel (у MouseArea).
MouseArea {
    id: mod

    property alias text: label.text
    property color color: Theme.text
    property string tip: ""
    property Component tipContent: null
    property int fontSize: Theme.fontSize
    property string fontFamily: Theme.font
    property bool bold: false
    property bool tipOff: false        // не показывать подсказку (открыто окно этого значка)
    property int pad: 9
    property alias label: label

    signal leftClick()
    signal rightClick()
    signal middleClick()

    property real maxWidth: Infinity   // длиннее — текст сокращается многоточием
    implicitWidth: Math.min(label.implicitWidth, maxWidth - pad * 2) + pad * 2
    implicitHeight: Theme.barHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor

    // кликабельные модули — лёгкая подсветка под курсором (как :hover в waybar)
    Rectangle {
        anchors.fill: parent
        color: Theme.hover
        visible: mod.containsMouse && mod.cursorShape === Qt.PointingHandCursor
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) rightClick()
        else if (mouse.button === Qt.MiddleButton) middleClick()
        else leftClick()
    }

    Text {
        id: label
        anchors.centerIn: parent
        width: Math.min(implicitWidth, mod.maxWidth - mod.pad * 2)
        elide: Text.ElideRight
        color: mod.color
        font.family: mod.fontFamily
        font.pixelSize: mod.fontSize
        font.bold: mod.bold
        textFormat: Text.PlainText
    }

    Tip {
        target: mod
        hovered: mod.containsMouse && !mod.tipOff
        text: mod.tip
        content: mod.tipContent
    }
}
