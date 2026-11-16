import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Трей: ЛКМ — открыть программу, ПКМ — её меню, СКМ — второе действие, колесо — прокрутка.
Row {
    id: root
    required property var bar   // окно панели — от него открываются меню
    spacing: 8
    leftPadding: visible ? 9 : 0
    rightPadding: leftPadding
    visible: SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items

        delegate: MouseArea {
            id: item
            required property SystemTrayItem modelData
            implicitWidth: 16
            implicitHeight: Theme.barHeight
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            function showMenu() {
                const p = item.mapToItem(root.bar.contentItem, 0, item.height)
                modelData.display(root.bar, p.x, p.y + 4)
            }

            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) modelData.secondaryActivate()
                else if (mouse.button === Qt.RightButton || modelData.onlyMenu) {
                    if (modelData.hasMenu) showMenu()
                } else modelData.activate()
            }
            onWheel: wheel => modelData.scroll(wheel.angleDelta.y / 120, false)

            IconImage {
                anchors.centerIn: parent
                implicitSize: 16
                // у части программ значок приходит как «имя?path=папка»
                source: {
                    let icon = item.modelData.icon
                    if (icon.includes("?path=")) {
                        const [name, path] = icon.split("?path=")
                        icon = `file://${path}/${name.slice(name.lastIndexOf("/") + 1)}`
                    }
                    // flatpak-программы шлют путь внутри своей песочницы (/app/share/icons/…),
                    // снаружи его нет — берём значок по имени: flatpak выкладывает их в систему
                    if (icon.startsWith("file:///app/") || icon.startsWith("/app/"))
                        icon = Quickshell.iconPath(icon.slice(icon.lastIndexOf("/") + 1), "application-x-executable")
                    return icon
                }
            }

            Tip {
                target: item
                hovered: item.containsMouse
                text: item.modelData.tooltipTitle || item.modelData.title || item.modelData.id
            }
        }
    }
}
