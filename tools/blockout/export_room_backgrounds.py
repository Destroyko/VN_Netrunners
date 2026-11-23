"""Копирует отрендеренные кадры комнаты героя в `assets/backgrounds` под имена игры.

    python tools/blockout/export_room_backgrounds.py

Кадры `room_<кадр>_<фаза>_pc_<on|off>.png` из `assets/_source/blockout/renders/room_frames/`
(их делает `room_frames.py`) ложатся как `bg_room_<кадр>_<время>_pc_<on|off>.png`; игра
подставляет `{time}` и `{pc}` в путь фона (`docs/gameplay/locations.md`). Кадр `main` — общий
вид комнаты (`loc_room`), `pc` — ПК вблизи (`loc_room_desk`). Утро в игре пока рисуется днём
(`locations.background_alias` в `data/balance.json`), поэтому отдельных файлов утра нет.

Скрипт только копирует: пустого или неполного набора не пропускает, а печатает, чего не хватает.
"""

import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "_source", "blockout", "renders", "room_frames")
DST = os.path.join(ROOT, "assets", "backgrounds")

FRAMES = ("main", "pc")
PHASES = ("day", "evening", "night")
STATES = ("on", "off")


def main() -> int:
    missing = []
    copied = 0
    for frame in FRAMES:
        for phase in PHASES:
            for state in STATES:
                src = os.path.join(SRC, "room_%s_%s_pc_%s.png" % (frame, phase, state))
                dst = os.path.join(DST, "bg_room_%s_%s_pc_%s.png" % (frame, phase, state))
                if not os.path.isfile(src):
                    missing.append(src)
                    continue
                shutil.copyfile(src, dst)
                copied += 1
    print("[export] скопировано: %d" % copied)
    for path in missing:
        print("[export] нет кадра: %s" % path)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
