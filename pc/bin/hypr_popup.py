"""Общая часть «постоянных» всплывающих окон: поиск (Alt+Space), буфер обмена (Super+V),
Wi-Fi и громкость с панели.

Зачем: запуск Python + GTK с нуля занимает ~0.3 с, и окно появлялось с заметной задержкой.
Теперь каждое окно — постоянно запущенный процесс (exec-once через hypr-respawn), его окно
создано заранее и живёт на скрытом специальном столе special:hypr-popups. Показать — одной
пачкой команд Hyprland перенести окно на текущий стол сразу в нужную точку и дать фокус;
спрятать — вернуть на скрытый стол. Окно не пересоздаётся и не мелькает в центре экрана.

Как зовут:  hypr-popup-show <вид>  → SIGUSR1 процессу (показать/спрятать),
                                     если процесса нет — запускает «<скрипт> --daemon --show».
closewindow (клик мимо в hypr-popup-dismiss, повторный клик по значку) не убивает окно:
GTK получает запрос на закрытие, и окно просто прячется.

Подключение в скрипте окна:
    res = Resident(win, kind="volume", app_id="hypr-volume", place="cursor", panel=True,
                   on_show=refresh)
    ...
    res.start()          # вместо win.show_all(); дальше Gtk.main()
  win.close() внутри окна (Esc, выбор пункта) — тоже просто прячет.
"""
import json
import os
import signal
import socket
import sys
import threading

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib  # noqa: E402

import subprocess  # noqa: E402

RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
HIDE_WS = "special:hypr-popups"
PANEL_STATE = os.path.join(RUN, "hypr-panel-popup")   # читает hypr-popup-dismiss

# при показе одного окна прячем/закрываем остальные всплывающие — чтобы не наслаивались
OTHER_POPUPS = {"hypr-search", "hypr-cliphist", "hypr-volume", "hypr-wifi", "hypr-help",
                "org.pulseaudio.pavucontrol", "pavucontrol", "kcm_networkmanagement",
                "btop-popup", "nm-connection-editor", "wifi-popup"}


def hypr(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True).stdout


def pidfile(kind):
    return os.path.join(RUN, f"hypr-popup-{kind}.pid")


def daemon_pid(kind):
    try:
        pid = int(open(pidfile(kind)).read())
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            if b"--daemon" not in f.read():
                return None
        return pid
    except (OSError, ValueError):
        return None


class Resident:
    def __init__(self, win, kind, app_id, place="cursor", panel=False, focus=True,
                 on_show=None, on_hide=None):
        self.win, self.kind, self.app_id = win, kind, app_id
        self.place = place          # cursor — под курсором у панели; top — сверху по центру; center
        self.panel = panel          # окно значка панели: пишет PANEL_STATE для hypr-popup-dismiss
        self.on_show, self.on_hide = on_show, on_hide
        # focus=False — не забирать фокус у активного окна и не переносить к себе курсор
        # (окна значков панели: фокус они получат, когда на них наведут мышь — follow_mouse)
        self.focus = focus
        self.addr = None
        self.visible = False
        self.want_show = "--show" in sys.argv
        win.connect("delete-event", self._on_delete)

    # ---------- запуск ----------
    def start(self):
        other = daemon_pid(self.kind)
        if other and other != os.getpid():
            # уже работает другой — просто попросить его показаться
            if self.want_show:
                os.kill(other, signal.SIGUSR1)
            sys.exit(0)
        with open(pidfile(self.kind), "w") as f:
            f.write(str(os.getpid()))
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, signal.SIGUSR1, self._sig_toggle)
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, signal.SIGUSR2, self._sig_hide)
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, signal.SIGTERM, self._sig_term)
        threading.Thread(target=self._events, daemon=True).start()
        self.win.show_all()
        GLib.timeout_add(30, self._find_addr)

    def _find_addr(self):
        try:
            clients = json.loads(hypr("clients", "-j") or "[]")
        except json.JSONDecodeError:
            return True
        me = next((c for c in clients if c["pid"] == os.getpid()), None)
        if me is None:
            return True             # окно ещё не появилось
        self.addr = me["address"]
        if me["workspace"]["name"] != HIDE_WS:   # правило не сработало — спрятать вручную
            hypr("dispatch", "movetoworkspacesilent", f"{HIDE_WS},address:{self.addr}")
        if self.want_show:
            self.want_show = False
            self.show()
        return False

    # ---------- сигналы ----------
    def _sig_toggle(self, *_):
        if self.addr is None:
            self.want_show = True
        elif self.visible:
            self.hide()
        else:
            self.show()
        return True

    def _sig_hide(self, *_):
        self.hide()
        return True

    def _sig_term(self, *_):
        try:
            if daemon_pid(self.kind) == os.getpid():
                os.remove(pidfile(self.kind))
        except OSError:
            pass
        os._exit(0)

    def _on_delete(self, *_):
        self.hide()
        return True                 # не уничтожать окно

    # ---------- смена стола — спрятать ----------
    def _events(self):
        path = os.path.join(RUN, "hypr", os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""),
                            ".socket2.sock")
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(path)
        except OSError:
            return
        buf = b""
        while True:
            data = s.recv(65536)
            if not data:
                os._exit(0)         # Hyprland завершился
            buf += data
            *lines, buf = buf.split(b"\n")
            if any(l.startswith(b"workspacev2>>") for l in lines):
                GLib.idle_add(self._ws_changed)

    def _ws_changed(self):
        if self.visible:
            self.hide()
        return False

    # ---------- показать / спрятать ----------
    def show(self):
        if self.addr is None:
            self.want_show = True
            return
        if self.on_show:
            self.on_show()
        try:
            mons = json.loads(hypr("monitors", "-j") or "[]")
            cx, cy = (float(v) for v in hypr("cursorpos").split(","))
        except (json.JSONDecodeError, ValueError):
            return
        if self.place == "cursor":
            m = next((m for m in mons if m["x"] <= cx < m["x"] + m["width"] / m["scale"]
                      and m["y"] <= cy < m["y"] + m["height"] / m["scale"]), None)
        else:
            m = None
        m = m or next((m for m in mons if m["focused"]), mons[0])
        mw, mh = m["width"] / m["scale"], m["height"] / m["scale"]
        w, h = self.win.get_size()
        if self.place == "cursor":
            x = min(max(8, cx - m["x"] - w / 2), mw - w - 8)   # значок — над серединой окна
            y = m["reserved"][1] + 6                           # сразу под панелью
        elif self.place == "top":
            x, y = (mw - w) / 2, mh * 0.12
        else:
            x, y = (mw - w) / 2, (mh - h) / 2
        gx, gy = int(m["x"] + x), int(m["y"] + y)
        ws = m["activeWorkspace"]["id"]
        a = self.addr
        cmds = [f"dispatch movetoworkspacesilent {ws},address:{a}",
                f"dispatch movewindowpixel exact {gx} {gy},address:{a}"]
        if self.focus:
            cmds.append(f"dispatch focuswindow address:{a}")
        hypr("--batch", " ; ".join(cmds))
        self.visible = True
        if self.panel:
            with open(PANEL_STATE, "w") as f:
                f.write(f"{self.kind} {int(cx)}\n")
        # остальные всплывающие — убрать (свои спрячутся, чужие закроются)
        try:
            others = [c for c in json.loads(hypr("clients", "-j") or "[]")
                      if c["class"] in OTHER_POPUPS and c["class"] != self.app_id
                      and c["workspace"]["id"] > 0]
        except json.JSONDecodeError:
            others = []
        if others:
            hypr("--batch", " ; ".join(f"dispatch closewindow address:{c['address']}"
                                       for c in others))

    def hide(self):
        if not self.visible or self.addr is None:
            return
        self.visible = False
        hypr("dispatch", "movetoworkspacesilent", f"{HIDE_WS},address:{self.addr}")
        if self.panel:
            try:
                if open(PANEL_STATE).read().split()[0] == self.kind:
                    os.remove(PANEL_STATE)
            except (OSError, IndexError):
                pass
        if self.on_hide:
            self.on_hide()
