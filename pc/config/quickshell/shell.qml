//@ pragma UseQApplication
//@ pragma IconTheme breeze-dark
// Панель Hyprland на Quickshell — замена waybar с той же логикой (см. Bar.qml).
// UseQApplication — без него не открываются меню программ в трее (ПКМ).
// Значки трея — тёмная тема breeze-dark (раньше для этого waybar запускался с отдельным GTK-конфигом).
// Правишь файлы — Quickshell перезагружает панель сам, перезапускать не нужно.
import QtQuick
import Quickshell

ShellRoot {
    Variants {
        model: Quickshell.screens
        Bar {}
    }
}
