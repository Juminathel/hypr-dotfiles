import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Что играет (Firefox, mpv, Telegram…): значок состояния и название. Нет плееров — модуль скрыт.
// ЛКМ — меню hypr-media в fuzzel под значком (пауза, треки, ±10 с, выбор плеера),
// ПКМ — пауза, колесо — треки. Плеер: тот, что играет, иначе первый.
Mod {
    id: media
    required property var bar

    readonly property var players: Mpris.players.values
    readonly property var player: players.find(p => p.playbackState === MprisPlaybackState.Playing)
                                  ?? players[0] ?? null
    readonly property bool playing: player?.playbackState === MprisPlaybackState.Playing
    readonly property string title: (player?.trackTitle ?? "").replace(/\s+/g, " ").trim()

    function mmss(sec) {
        sec = Math.max(0, Math.floor(sec))
        return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0")
    }

    property bool fits: true    // на узком мониторе панель прячет музыку, чтобы осталось место заголовку
    visible: player !== null && fits
    text: (playing ? "󰐊" : player?.playbackState === MprisPlaybackState.Paused ? "󰏤" : "󰓛")
          + (title ? " " + (title.length > 24 ? title.slice(0, 23) + "…" : title) : "")
    color: playing ? Theme.subtext : Theme.overlay
    tip: player ? [title, player.trackArtist ?? "",
                   (player.identity ?? "") + (player.lengthSupported && player.length > 0
                        ? " · " + mmss(player.position) + " / " + mmss(player.length) : "")]
                  .filter(s => s).join("\n") : ""

    // позиция в подсказке обновляется, пока она видна
    Timer {
        running: media.containsMouse && media.playing
        interval: 1000; repeat: true
        onTriggered: media.player?.positionChanged()
    }

    onLeftClick: bar.menu("hypr-media")
    onRightClick: bar.run("$HOME/.local/bin/hypr-media toggle")
    // тачпад даёт много мелких шагов — копим до одного «щелчка» колеса, иначе листало бы по несколько треков
    property real acc: 0
    onWheel: wheel => {
        acc += wheel.angleDelta.y
        if (Math.abs(acc) < 120) return
        bar.run("$HOME/.local/bin/hypr-media " + (acc > 0 ? "prev" : "next"))
        acc = 0
    }
}
