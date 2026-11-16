"""Перевод старых команд `hyprctl dispatch …` в Lua для Hyprland 0.57+.

С 0.57 Hyprland настраивается на Lua, и `hyprctl dispatch` принимает только Lua-выражение
(`hl.dsp.focus({workspace = "3"})`), а не старое `workspace 3`. Скрипты по-прежнему пишут
команды по-старому, а этот модуль переводит их:

    translate(["dispatch", "workspace", "3"])  → ["dispatch", 'hl.dsp.focus({workspace = "3"})']
    translate(["--batch", "dispatch a ; dispatch b"]) → ["eval", "hl.dispatch(…); hl.dispatch(…)"]

Остальные команды hyprctl (clients, monitors, cursorpos…) проходят без изменений.
Модуль, а не скрипт: его импортируют из ~/.local/bin.
"""


def q(s):
    """строка Lua в кавычках"""
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def _split_window(arg):
    """'3,address:0x1' → ('3', 'address:0x1'); без запятой — (arg, None)"""
    if "," in arg:
        a, w = arg.split(",", 1)
        return a.strip(), w.strip()
    return arg.strip(), None


def _win(w):
    return f", window = {q(w)}" if w else ""


def dsp(cmd):
    """одна старая команда диспетчера ('workspace 3') → Lua-выражение hl.dsp.…"""
    name, _, arg = cmd.strip().partition(" ")
    arg = arg.strip()

    if name == "workspace":
        return f"hl.dsp.focus({{workspace = {q(arg)}}})"
    if name == "focusmonitor":
        return f"hl.dsp.focus({{monitor = {q(arg)}}})"
    if name == "focuswindow":
        return f"hl.dsp.focus({{window = {q(arg)}}})"
    if name in ("movetoworkspace", "movetoworkspacesilent"):
        ws, w = _split_window(arg)
        follow = ", follow = false" if name.endswith("silent") else ""
        return f"hl.dsp.window.move({{workspace = {q(ws)}{follow}{_win(w)}}})"
    if name == "closewindow":
        return f"hl.dsp.window.close({{window = {q(arg)}}})" if arg else "hl.dsp.window.close()"
    if name == "alterzorder":
        mode, w = _split_window(arg)
        return f"hl.dsp.window.alter_zorder({{mode = {q(mode)}{_win(w)}}})"
    if name == "submap":
        return f"hl.dsp.submap({q(arg)})"
    if name == "exec":
        return f"hl.dsp.exec_cmd({q(arg)})"
    if name == "exit":
        return "hl.dsp.exit()"
    if name in ("setfloating", "settiled"):
        action = "enable" if name == "setfloating" else "disable"
        return f"hl.dsp.window.float({{action = {q(action)}{_win(arg)}}})"
    if name == "pin":
        return f"hl.dsp.window.pin({{action = \"toggle\"{_win(arg)}}})"
    if name in ("resizewindowpixel", "movewindowpixel"):
        # 'exact 576 324,address:0x1' или '40 0,address:0x1' (относительно)
        spec, w = _split_window(arg)
        parts = spec.split()
        relative = parts[0] != "exact"
        if not relative:
            parts = parts[1:]
        x, y = parts[0], parts[1]
        fn = "resize" if name == "resizewindowpixel" else "move"
        rel = "true" if relative else "false"
        return f"hl.dsp.window.{fn}({{x = {x}, y = {y}, relative = {rel}{_win(w)}}})"
    if name == "moveworkspacetomonitor":
        ws, mon = arg.split(None, 1)
        return f"hl.dsp.workspace.move({{workspace = {q(ws)}, monitor = {q(mon)}}})"
    raise ValueError(f"hypr_dsp: неизвестный диспетчер: {cmd!r}")


def translate(args):
    """аргументы старого вызова hyprctl → аргументы для Hyprland 0.57+"""
    args = list(args)
    if not args:
        return args
    if args[0] == "dispatch":
        return ["dispatch", dsp(" ".join(args[1:]))]
    if args[0] == "--batch":
        calls = []
        for part in " ".join(args[1:]).split(";"):
            part = part.strip()
            if not part:
                continue
            if not part.startswith("dispatch "):
                raise ValueError(f"hypr_dsp: в --batch поддерживается только dispatch: {part!r}")
            calls.append(f"hl.dispatch({dsp(part[len('dispatch '):])})")
        return ["eval", "; ".join(calls)]
    return args


def _fix_ws(d):
    # Hyprland 0.57: у особых столов (special:…) и у пустого specialWorkspace нет поля "id".
    # Раньше id был: у особых — отрицательный, у пустого — 0. Скрипты проверяют id > 0 —
    # возвращаем прежние значения, чтобы эти проверки работали как раньше.
    if "id" not in d and "name" in d and "type" in d and "address" in d:
        d["id"] = 0 if not d["name"] else -99
    return d


def loads(s):
    """json.loads для ответа `hyprctl … -j` с номерами особых столов, как до 0.57"""
    import json
    return json.loads(s, object_hook=_fix_ws)
