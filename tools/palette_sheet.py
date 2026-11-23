"""Лист палитры: цвет × материал, одной картинкой.

Палитра — две независимые оси, поэтому и лист показывает обе:

1. МАТЕРИАЛЫ — один и тот же цвет на восьми поверхностях. Видно, чем бумага отличается
   от металла: числом ступеней света, бликом, холодностью тени.
2. ЦВЕТА — по семействам, от светлого к тёмному. Любой берётся на любой материал
   (стекло и растения — только часть).
3. КОМНАТЫ — подсказка, какие цвета взять на комнату. Не палитра, а рекомендация.

    python tools/palette_sheet.py            # assets/_source/palette.png
    python tools/palette_sheet.py --out путь.png

Образцы схематичные: ступени и блик те же, что у шейдера, но фактуры нет. Точный вид —
в Rendered или на листе material_sheet.py.
"""

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "blockout"))
import palette as P  # noqa: E402
import swatch as S  # noqa: E402

BG = (238, 236, 232)
INK = (40, 42, 48)
SOFT = (90, 92, 98)
LINE = (200, 198, 194)

# Какие цвета показывать на матрице материалов: нейтрали, тёплое, холодное, зелёное
SAMPLE = ["black", "grey", "snow", "red_mid", "yellow_mid", "green_mid", "blue_mid",
          "brown_mid"]

BALL = 84
CHIP_W, CHIP_H = 132, 46
PAD = 28


def font(size):
    for name in ("segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def hex_rgb(hexcol):
    h = hexcol.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def main():
    ap = argparse.ArgumentParser(description="Лист палитры")
    ap.add_argument("--out", default="assets/_source/palette.png")
    a = ap.parse_args()

    f_title, f_head, f_lbl, f_small = font(24), font(16), font(13), font(11)
    kinds = P.KIND_ORDER
    left = 150
    width = max(PAD * 2 + left + len(kinds) * (BALL + 22), PAD * 2 + 130 + 6 * (CHIP_W + 10))

    # --- высоты разделов --------------------------------------------------
    h1 = 70 + len(SAMPLE) * (BALL + 10) + 20
    fam_rows = len(P.FAMILIES)
    h2 = 70 + fam_rows * (CHIP_H + 30) + 20
    h3 = 70 + len(P.ROOMS) * 34 + 20
    height = PAD + 50 + h1 + h2 + h3 + PAD

    im = Image.new("RGB", (width, height), BG)
    dr = ImageDraw.Draw(im)
    dr.text((PAD, PAD - 6), "Палитра игры — цвет × материал", fill=INK, font=f_title)
    y = PAD + 44

    # --- 1. материалы -----------------------------------------------------
    dr.text((PAD, y), "1. Материалы: один и тот же цвет на разных поверхностях",
            fill=INK, font=f_head)
    y += 28
    x0 = PAD + left
    for i, kind in enumerate(kinds):
        cx = x0 + i * (BALL + 22)
        title = P.KIND_TITLE[kind].split(" (")[0]
        dr.text((cx, y), title, fill=SOFT, font=f_small)
    y += 20
    for color in SAMPLE:
        dr.text((PAD, y + BALL // 2 - 8), color, fill=SOFT, font=f_lbl)
        for i, kind in enumerate(kinds):
            cx = x0 + i * (BALL + 22)
            if kind not in P.kinds_for(color):
                dr.text((cx + BALL // 2 - 4, y + BALL // 2 - 8), "—", fill=LINE, font=f_lbl)
                continue
            ball = S.sphere(P.srgb(P.COLORS[color]), kind, BALL)
            im.paste(S.to_pil(ball), (cx, y), S.to_pil(ball))
        y += BALL + 10
    y += 28

    # --- 2. цвета по семействам -------------------------------------------
    dr.text((PAD, y), "2. Цвета: семейства от светлого к тёмному — любой на любой материал",
            fill=INK, font=f_head)
    y += 30
    for fam, tones in P.FAMILIES.items():
        dr.text((PAD, y + 12), P.FAMILY_TITLE[fam], fill=SOFT, font=f_lbl)
        x = PAD + 130
        for tone, hexcol in tones.items():
            dr.rectangle([x, y, x + CHIP_W, y + CHIP_H], fill=hex_rgb(hexcol), outline=LINE)
            cid = tone if fam == "neutral" else "%s_%s" % (fam, tone)
            dr.text((x + 2, y + CHIP_H + 3), cid, fill=SOFT, font=f_small)
            dr.text((x + 2, y + CHIP_H + 15), hexcol, fill=LINE, font=f_small)
            if tone == "vivid":
                dr.text((x + CHIP_W - 46, y + 4), "мелочь", fill=(255, 255, 255), font=f_small)
            x += CHIP_W + 10
        y += CHIP_H + 30
    y += 28

    # --- 3. комнаты: подсказка --------------------------------------------
    dr.text((PAD, y), "3. Комнаты — подсказка, какие цвета взять (не палитра)",
            fill=INK, font=f_head)
    y += 28
    for room, parts in P.ROOMS.items():
        dr.text((PAD, y + 4), room, fill=SOFT, font=f_lbl)
        x = PAD + 130
        for role, cid in parts.items():
            dr.rectangle([x, y, x + 56, y + 24], fill=hex_rgb(P.COLORS[cid]), outline=LINE)
            dr.text((x + 62, y + 5), "%s: %s" % (role, cid), fill=SOFT, font=f_small)
            x += 250
        y += 34

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = a.out if os.path.isabs(a.out) else os.path.join(root, a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im.crop((0, 0, width, min(height, y + PAD))).save(out)
    print("сохранено: %s (%dx%d)" % (out, width, min(height, y + PAD)))


if __name__ == "__main__":
    main()
