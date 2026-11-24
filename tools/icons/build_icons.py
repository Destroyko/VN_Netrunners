"""Собирает иконки интерфейса из исходных значков в `assets/_source/icons/glyphs/`.

    python tools/icons/build_icons.py

Исходник значка — SVG на сетке 48×48 с метками цвета `{fg}` (основной) и `{accent}` (акцент). Цвета берутся
из `data/ui_theme.json` (роли `text` и `accent`), цвет плашки — из палитры комнат (`tools/blockout/palette.py`)
по имени в `assets/_source/icons/icons.json`. Выход в `assets/ui/icons/`:

- `glyph/<имя>.svg` — значок без плашки (рабочий стол ПК);
- `tile/<имя>.svg` — значок на плашке с закруглёнными углами (телефон), 96×96.

Правила стиля — `docs/art/icons.md`. Скрипт только пишет текстовые SVG, зависимостей нет (палитру читает
из репозитория).
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "_source", "icons")
OUT = os.path.join(ROOT, "assets", "ui", "icons")
sys.path.insert(0, os.path.join(ROOT, "tools", "blockout"))
import palette as P  # noqa: E402

TILE = 96
TILE_RADIUS = 22
GLYPH_SIZE = 56           # значок внутри плашки, остальное — поле


def theme_colors():
    with open(os.path.join(ROOT, "data", "ui_theme.json"), encoding="utf-8") as fh:
        return json.load(fh)["colors"]


def paint(svg: str, fg: str, accent: str) -> str:
    return svg.replace("{fg}", fg).replace("{accent}", accent)


def glyph_svg(body: str) -> str:
    """Значок отдельно: viewBox 48×48, растеризуется в 96 px (чёткий на 2×)."""
    return body.replace("<svg ", '<svg width="96" height="96" ', 1)


def tile_svg(body: str, tile_hex: str) -> str:
    inner = body[body.index(">") + 1:body.rindex("</svg>")]
    offset = (TILE - GLYPH_SIZE) / 2.0
    scale = GLYPH_SIZE / 48.0
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
            '<rect width="%d" height="%d" rx="%d" fill="%s"/>'
            '<g transform="translate(%g %g) scale(%g)">%s</g></svg>'
            % (TILE, TILE, TILE, TILE, TILE, TILE, TILE_RADIUS, tile_hex, offset, offset, scale, inner))


def main() -> int:
    colors = theme_colors()
    with open(os.path.join(SRC, "icons.json"), encoding="utf-8") as fh:
        icons = json.load(fh)["icons"]
    os.makedirs(os.path.join(OUT, "glyph"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "tile"), exist_ok=True)
    missing = []
    for name, spec in icons.items():
        path = os.path.join(SRC, "glyphs", name + ".svg")
        if not os.path.isfile(path):
            missing.append(name)
            continue
        with open(path, encoding="utf-8") as fh:
            body = paint(fh.read().strip(), colors["text"], colors["accent"])
        with open(os.path.join(OUT, "glyph", name + ".svg"), "w", encoding="utf-8") as fh:
            fh.write(glyph_svg(body))
        with open(os.path.join(OUT, "tile", name + ".svg"), "w", encoding="utf-8") as fh:
            fh.write(tile_svg(body, P.COLORS[spec["tile"]]))
    print("[icons] собрано: %d" % (len(icons) - len(missing)))
    for name in missing:
        print("[icons] нет значка: %s" % name)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
