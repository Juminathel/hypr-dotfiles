import QtQuick
import Quickshell

// Часы в две строки: время, под ним дата помельче. Щелчок — полная дата с днём недели.
// Подсказка — календарь на месяц, номера недель справа.
MouseArea {
    id: clock
    property bool alt: false

    implicitWidth: (alt ? full.implicitWidth : col.implicitWidth) + 18
    implicitHeight: Theme.barHeight
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: alt = !alt

    SystemClock { id: sc; precision: SystemClock.Minutes }

    Column {
        id: col
        visible: !clock.alt
        anchors.centerIn: parent
        spacing: -3
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(sc.date, "HH:mm")
            color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(sc.date, "dd.MM.yyyy")
            color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.bold: true
        }
    }
    Text {
        id: full
        visible: clock.alt
        anchors.centerIn: parent
        text: Qt.formatDate(sc.date, "ddd, dd MMMM yyyy")
        color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.bold: true
    }

    Tip {
        target: clock
        hovered: clock.containsMouse
        content: Component {
            Column {
                id: cal
                spacing: 4
                readonly property date today: sc.date
                readonly property var weeks: {
                    const y = today.getFullYear(), m = today.getMonth()
                    const first = new Date(y, m, 1)
                    const shift = (first.getDay() + 6) % 7           // неделя с понедельника
                    const start = new Date(y, m, 1 - shift)
                    const rows = []
                    for (let r = 0; r < 6; r++) {
                        const days = []
                        for (let d = 0; d < 7; d++) {
                            const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + r * 7 + d)
                            days.push(day)
                        }
                        if (r > 0 && days[0].getMonth() !== m) break
                        // ISO-номер недели — по четвергу
                        const th = days[3]
                        const jan4 = new Date(th.getFullYear(), 0, 4)
                        const week = 1 + Math.round(((th - jan4) / 86400000 - 3 + (jan4.getDay() + 6) % 7) / 7)
                        rows.push({ days: days, week: week })
                    }
                    return rows
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(today, "MMMM yyyy")
                    color: Theme.yellow; font.family: Theme.font; font.pixelSize: 13; font.bold: true
                }
                Grid {
                    columns: 8
                    columnSpacing: 6
                    rowSpacing: 2
                    Repeater {
                        model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс", ""]
                        Text {
                            required property string modelData
                            width: 22; horizontalAlignment: Text.AlignRight
                            text: modelData
                            color: Theme.subtext; font.family: Theme.font; font.pixelSize: 12
                        }
                    }
                    Repeater {
                        model: cal.weeks.length * 8
                        Text {
                            required property int index
                            readonly property var row: cal.weeks[Math.floor(index / 8)]
                            readonly property int c: index % 8
                            readonly property var day: c < 7 ? row.days[c] : null
                            readonly property bool isToday: day !== null && day.toDateString() === cal.today.toDateString()
                            readonly property bool other: day !== null && day.getMonth() !== cal.today.getMonth()
                            width: 22; horizontalAlignment: Text.AlignRight
                            text: c === 7 ? "W" + row.week : (other ? "" : day.getDate())
                            color: c === 7 ? Theme.blue : isToday ? Theme.peach : c >= 5 ? Theme.red : Theme.text
                            font.family: Theme.font; font.pixelSize: 12
                            font.bold: isToday
                            font.underline: isToday
                        }
                    }
                }
            }
        }
    }
}
