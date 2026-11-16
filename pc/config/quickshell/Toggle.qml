import QtQuick

// Переключатель вкл/выкл. checked — состояние, toggled(on) — щёлкнули.
Rectangle {
    id: t
    property bool checked: false
    signal toggled(bool on)

    implicitWidth: 44
    implicitHeight: 24
    radius: 12
    color: checked ? Theme.blue : "#45475a"
    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
        y: 2
        x: t.checked ? t.width - width - 2 : 2
        width: 20; height: 20; radius: 10
        color: Theme.text
        Behavior on x { NumberAnimation { duration: 120 } }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: t.toggled(!t.checked)
    }
}
