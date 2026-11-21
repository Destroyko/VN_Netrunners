"""Лист палитры: все цвета игры одной картинкой, с ступенями cel-шейдинга.

Палитру нельзя держать только списком шестнадцатеричных кодов — по ним не видно,
дружат цвета между собой или нет. Этот лист показывает каждый цвет в трёх тонах,
как он и ляжет в кадре.

    python tools/palette_sheet.py            # assets/_source/palette.png
    python tools/palette_sheet.py --out путь.png
"""

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "blockout"))
import palette as P  # noqa: E402

SW, SH = 150, 54          # размер образца
PAD, GAP = 28, 8
LABEL_H = 18


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def to_rgb255(lin):
    return tuple(int(round(linear_to_srgb(c) * 255)) for c in lin)


def font(size):
    for name in ("segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def groups():
    """Цвета по разделам, в том порядке, в каком о них думают."""
    out = [("Нейтрали — общие для всей игры", P.NEUTRAL),
           ("Дерево", P.WOOD), ("Металл", P.METAL),
           ("Акценты — предметы покрупнее: кружка, книга, коробка", P.ACCENT),
           ("Яркие — только мелочь: карандаши, кнопки, провода", P.BRIGHT),
           ("Ткань — ковры, шторы, покрывала", P.FABRIC)]
    for room, d in P.ROOM.items():
        out.append(("Комната: %s" % room, d))
    return out


def main():
    ap = argparse.ArgumentParser(description="Лист палитры")
    ap.add_argument("--out", default="assets/_source/palette.png")
    a = ap.parse_args()

    gs = groups()
    cols = max(len(d) for _, d in gs)
    width = PAD * 2 + cols * (SW + GAP)
    height = PAD * 2 + len(gs) * (SH + LABEL_H + GAP + 14) + 90

    im = Image.new("RGB", (width, height), (238, 236, 232))
    dr = ImageDraw.Draw(im)
    f_head = font(22)
    f_grp = font(15)
    f_lbl = font(12)

    dr.text((PAD, PAD - 6), "Палитра игры — каждый цвет в трёх тонах cel-шейдинга",
            fill=(40, 42, 48), font=f_head)

    y = PAD + 34
    for title, d in gs:
        dr.text((PAD, y), title, fill=(70, 74, 82), font=f_grp)
        y += LABEL_H + 2
        x = PAD
        for name, hexcol in d.items():
            tones = P.shades(hexcol, 3)
            # три полосы: тень, полутон, свет — как ляжет на предмет
            for i, t in enumerate(tones):
                dr.rectangle([x, y + i * (SH // 3), x + SW, y + (i + 1) * (SH // 3)],
                             fill=to_rgb255(t))
            dr.rectangle([x, y, x + SW, y + SH], outline=(200, 198, 194))
            dr.text((x + 2, y + SH + 2), "%s  %s" % (name, hexcol),
                    fill=(90, 92, 98), font=f_lbl)
            x += SW + GAP
        y += SH + LABEL_H + GAP + 6

    # свет по фазам: цвет источника и заливки
    dr.text((PAD, y), "Свет по времени суток — ключ и заливка", fill=(70, 74, 82), font=f_grp)
    y += LABEL_H + 2
    x = PAD
    for phase, d in P.PHASE.items():
        dr.rectangle([x, y, x + SW // 2, y + SH], fill=to_rgb255(P.srgb(d["key"])))
        dr.rectangle([x + SW // 2, y, x + SW, y + SH], fill=to_rgb255(P.srgb(d["fill"])))
        dr.rectangle([x, y, x + SW, y + SH], outline=(200, 198, 194))
        dr.text((x + 2, y + SH + 2), "%s  %s" % (phase, d["key"]),
                fill=(90, 92, 98), font=f_lbl)
        x += SW + GAP
    for lamp, d in P.LAMP.items():
        dr.rectangle([x, y, x + SW, y + SH], fill=to_rgb255(P.srgb(d["color"])))
        dr.rectangle([x, y, x + SW, y + SH], outline=(200, 198, 194))
        dr.text((x + 2, y + SH + 2), "%s" % lamp, fill=(90, 92, 98), font=f_lbl)
        x += SW + GAP

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = a.out if os.path.isabs(a.out) else os.path.join(root, a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im.save(out)
    print("сохранено: %s (%dx%d)" % (out, width, height))


if __name__ == "__main__":
    main()
