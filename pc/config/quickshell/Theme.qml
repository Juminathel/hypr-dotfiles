pragma Singleton
import QtQuick
import Quickshell

// Цвета Catppuccin Mocha и шрифт — те же, что в waybar/style.css.
// Панель — одна плоская полупрозрачная полоса; цвет только у состояний (активный стол, нет звука…).
Singleton {
    readonly property color panel:    Qt.rgba(17 / 255, 17 / 255, 27 / 255, 0.62)
    readonly property color panelLine: Qt.rgba(205 / 255, 214 / 255, 244 / 255, 0.06)  // линия под панелью
    readonly property color hover:    Qt.rgba(205 / 255, 214 / 255, 244 / 255, 0.08)
    readonly property color tipBg:    Qt.rgba(30 / 255, 30 / 255, 46 / 255, 0.96)
    readonly property color tipBorder: "#45475a"

    readonly property color text:     "#cdd6f4"
    readonly property color subtext:  "#a6adc8"
    readonly property color dim:      "#585b70"
    readonly property color overlay:  "#6c7086"
    readonly property color crust:    "#1e1e2e"
    readonly property color blue:     "#89b4fa"
    readonly property color red:      "#f38ba8"
    readonly property color yellow:   "#f9e2af"
    readonly property color sky:      "#89dceb"
    readonly property color green:    "#a6e3a1"
    readonly property color mauve:    "#cba6f7"
    readonly property color peach:    "#fab387"
    readonly property color pink:     "#f5c2e7"

    readonly property string font: "IBM Plex Mono"
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 15

    readonly property int barHeight: 32
}
