"""Собирает иконки интерфейса для каждой темы из исходных значков в `assets/_source/icons/glyphs/`.

    python tools/icons/build_icons.py

Исходник значка — SVG на сетке 48×48 с метками цвета `{fg}` (основной) и `{accent}` (акцент). Цвета берутся
из темы (`data/themes/<id>/theme.json`, раздел `icons`), цвет плашки на телефоне — из палитры комнат
(`tools/blockout/palette.py`) по имени в `assets/_source/icons/icons.json`. Выход в `assets/ui/icons/<тема>/`:

- `glyph/<имя>.svg` — значок без плашки (рабочий стол ПК);
- `tile/<имя>.svg` — значок на плашке с закруглёнными углами, 96×96, только у тем с `"tiles": true` (телефон).

Новая тема получает значки сама: достаточно папки `data/themes/<id>/` с `theme.json`. Правила стиля —
`docs/art/icons.md`, темы — `docs/art/themes.md`. Скрипт пишет текстовые SVG, зависимостей нет.
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "_source", "icons")
THEMES = os.path.join(ROOT, "data", "themes")
OUT = os.path.join(ROOT, "assets", "ui", "icons")
sys.path.insert(0, os.path.join(ROOT, "tools", "blockout"))
import palette as P  # noqa: E402

TILE = 96
TILE_RADIUS = 22
GLYPH_SIZE = 56           # значок внутри плашки, остальное — поле


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
    with open(os.path.join(SRC, "icons.json"), encoding="utf-8") as fh:
        icons = json.load(fh)["icons"]
    missing = set()
    built = 0
    for theme_id in sorted(os.listdir(THEMES)):
        path = os.path.join(THEMES, theme_id, "theme.json")
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as fh:
            spec_icons = json.load(fh).get("icons", {})
        fg, accent, tiles = spec_icons.get("fg", "#E6EAEF"), spec_icons.get("accent", "#E87B2E"), bool(spec_icons.get("tiles", False))
        for kind in ("glyph", "tile"):
            os.makedirs(os.path.join(OUT, theme_id, kind), exist_ok=True)
        for name, spec in icons.items():
            glyph = os.path.join(SRC, "glyphs", name + ".svg")
            if not os.path.isfile(glyph):
                missing.add(name)
                continue
            with open(glyph, encoding="utf-8") as fh:
                body = paint(fh.read().strip(), fg, accent)
            with open(os.path.join(OUT, theme_id, "glyph", name + ".svg"), "w", encoding="utf-8") as fh:
                fh.write(glyph_svg(body))
            if tiles:
                with open(os.path.join(OUT, theme_id, "tile", name + ".svg"), "w", encoding="utf-8") as fh:
                    fh.write(tile_svg(body, P.COLORS[spec["tile"]]))
            built += 1
    print("[icons] собрано значков: %d" % built)
    for name in sorted(missing):
        print("[icons] нет значка: %s" % name)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
