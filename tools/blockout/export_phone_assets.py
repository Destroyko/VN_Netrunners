"""Копирует кадры телефона в игру и обрезает маску экрана по его прямоугольнику.

    python tools/blockout/export_phone_assets.py

Из `assets/_source/blockout/renders/phone/` (их делает `phone_frames.py`) в `assets/ui/phone/` идут:
`phone_day|evening|night.png` (корпус с вырезанным экраном), `phone_screen.json` и
`phone_screen_mask.png`, обрезанная до экрана (по `x, y, w, h` из json): игра рисует по ней
скруглённый экран и обрезает по нему интерфейс телефона. Нужен Pillow.
"""

import json
import os
import shutil

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "_source", "blockout", "renders", "phone")
DST = os.path.join(ROOT, "assets", "ui", "phone")


def main() -> None:
    os.makedirs(DST, exist_ok=True)
    for name in ("phone_day.png", "phone_evening.png", "phone_night.png", "phone_screen.json"):
        shutil.copyfile(os.path.join(SRC, name), os.path.join(DST, name))
    with open(os.path.join(SRC, "phone_screen.json"), encoding="utf-8") as fh:
        info = json.load(fh)
    mask = Image.open(os.path.join(SRC, "phone_screen_mask.png")).convert("RGBA")
    box = (info["x"], info["y"], info["x"] + info["w"], info["y"] + info["h"])
    mask.crop(box).save(os.path.join(DST, "phone_screen_mask.png"))
    print("[phone] скопировано в %s, маска %dx%d" % (DST, info["w"], info["h"]))


if __name__ == "__main__":
    main()
