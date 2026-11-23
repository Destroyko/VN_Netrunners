"""Свет комнаты в окне Blender: открыть во вкладке Scripting и нажать Run Script (Alt+P).

Меняйте две строки ниже и запускайте снова: свет и вид переключаются на месте.

    PHASE — day, evening, night или off (убрать свет, который добавил скрипт);
    VIEW  — main, pc (смотреть через камеру кадра) или none (вид не трогать);
    PC    — on или off: компьютер включён (экран и его свет) или выключен.

Окно 3D переключается в режим Rendered (EEVEE), вид идёт через расчётную камеру.
Двигать мебель и красить материалы можно и в этом режиме: рендер обновляется сам.
Сохраняя файл, поставьте PHASE = "off" и запустите ещё раз: иначе источники света rf_*
останутся в сцене. Подробности: docs/art/blender-scenes.md, «Свет комнаты».
"""

import os
import sys

import bpy

PHASE = "night"
VIEW = "main"
PC = "on"

TOOLS = r"C:\PROJECTS\VN-netrunners\tools\blockout"
if TOOLS not in sys.path:
    sys.path.append(TOOLS)

import importlib  # noqa: E402

import room_frames as R  # noqa: E402

importlib.reload(R)
R.gui(PHASE, VIEW, PC)
print("[room] свет: %s, вид: %s" % (PHASE, VIEW))
