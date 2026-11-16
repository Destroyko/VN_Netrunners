# Блокаут города для карты навигации (docs/art/ai-pipeline.md, раздел 8).
#
# Карта — изометрия, а не «вид сверху под углом»: ортографическая камера под углом,
# один и тот же ракурс у всех зданий. Блокаут нужен именно за этим — генератор
# не держит единый угол между отдельными прогонами.
#
# Два правила, которые задал разработчик:
#
# 1. **Город больше кадра.** Строим заведомо больше, чем видно, и кадрируем так,
#    чтобы по краям дома обрезались. Карта должна читаться как кусок города,
#    а не как остров с границами, за которыми пустота.
# 2. **Район — не однородная застройка.** Офисы стоят в высотках, торговый центр —
#    длинная коробка с парковкой, трущобы — плотная мелкая застройка. Иначе все дома
#    одной высоты и место ничем не отличается от соседнего.
#
# Кликабельные локации (список — docs/world/locations.md) стоят внутри кадра и разнесены
# по разным кварталам: между ними обычная застройка, и дорога стоит времени
# (../gameplay/core-loop.md). Фоновые дома не кликаются и живут в подложке.
#
# Запуск (PowerShell):
#   & "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" -b `
#     --python tools\blockout\city.py -- --render map
#   ... -- --sprites            # кликабельные здания отдельными кадрами

import math
import os
import random
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bl_common as B  # noqa: E402

# Клетка 12 м: дом в три клетки — это 36 м по фасаду, обычная пятиэтажка. Мельче
# брать нельзя: при клетке 8 м весь район укладывался в 300 м и дорога от дома
# до вокзала занимала три минуты — то есть ничего.
CELL = 12.0        # клетка плана в метрах; на карте это 32 px (раздел 8.2)
FLOOR = 3.0        # высота этажа
BLOCK = 8          # квартал — 8×8 клеток, внутри четыре участка 4×4
ROAD = 2           # ширина улицы в клетках
COLS, ROWS = 7, 7  # кварталов с нашей застройкой; в кадр попадает примерно пять на пять
PAD = 2            # кварталы вокруг: город обязан продолжаться за краем кадра
VIEW = 800.0       # ширина кадра в метрах: по ней режутся края города
WALK_KMH = 4.5     # пешком; отсюда считается время дороги

# Зоны застройки: что за место и как оно выглядит.
# (этажи от, этажи до, участков в ряд, тона) — «участков в ряд» дробит участок 4×4
# на мелкие: 2 — это четыре домика вместо одного дома.
ZONE_RULES = {
    # Разрыв между зонами должен быть заметным. Когда жильё поднялось до 11 этажей,
    # высотки перестали читаться как высотки, а трущобы — как трущобы.
    "downtown":   (11, 20, 1, ["facade_b", "facade_c"]),
    "residential": (4, 8, 1, ["facade_a", "facade_b", "facade_c"]),
    "slums":      (2, 3, 2, ["facade_c", "facade_a"]),
    "commercial": (1, 3, 1, ["facade_a", "facade_b"]),
}
# Квартал -> зона. Не перечисленные кварталы — жилые.
ZONES = {
    (4, 3): "downtown", (5, 3): "downtown", (4, 4): "downtown", (5, 4): "downtown",
    (5, 2): "downtown", (6, 3): "downtown",
    (1, 1): "slums", (2, 1): "slums", (1, 2): "slums", (0, 1): "slums",
    (3, 2): "commercial", (4, 1): "commercial",
}
PARK_BLOCK = (2, 4)   # целый квартал зелени: скамейка — «ждать вне дома»

# Кликабельные локации: ключ -> (квартал, участок, участков, этажей, тон, что это)
# Участок — индекс 0..3 внутри квартала: 0 ЮЗ, 1 ЮВ, 2 СЗ, 3 СВ.
# Все они внутри кадра; фоновая застройка вокруг уходит за его край.
LANDMARKS = {
    "home":     ((1, 3), 0, 1, 5, "facade_a", "жилой дом героя: ПК, сон, еда"),
    "school":   ((2, 2), 3, 1, 3, "facade_c", "вечерняя школа: обучение"),
    "market":   ((1, 1), 1, 1, 1, "facade_c", "барахолка: задел, стоит в трущобах"),
    "station":  ((3, 1), 0, 2, 3, "facade_b", "вокзал: задел"),
    "hospital": ((2, 3), 2, 2, 6, "facade_b", "больница: мать героя"),
    "mall":     ((3, 2), 2, 2, 2, "facade_a", "торговый центр: хаб, спортзал, парковка"),
    "tower_b":  ((4, 3), 1, 1, 14, "facade_c", "бизнес-центр"),
    "tower_a":  ((5, 3), 3, 1, 20, "facade_b", "высотка: офисы и узлы сети"),
    "elite":    ((3, 4), 2, 2, 8, "facade_a", "элитный квартал: задел, окнами в парк"),
}
MALL_PARKING = ((3, 2), 0)   # квартал и участок под парковку торгового центра

STEP = BLOCK + ROAD
GRID = ((COLS + 2 * PAD) * STEP + ROAD, (ROWS + 2 * PAD) * STEP + ROAD)
# Кварталы с отрицательными индексами — это рамка PAD: обычная жилая застройка,
# которая попадает в кадр только краем.
SPAN_COLS = range(-PAD, COLS + PAD)
SPAN_ROWS = range(-PAD, ROWS + PAD)


def zone_of(col, row):
    return ZONES.get((col, row), "residential")


def block_origin(col, row):
    return ROAD + (col + PAD) * STEP, ROAD + (row + PAD) * STEP


def plot_origin(col, row, plot):
    bx, by = block_origin(col, row)
    return bx + (plot % 2) * (BLOCK // 2), by + (plot // 2) * (BLOCK // 2)


def ground(shade):
    w, d = GRID[0] * CELL, GRID[1] * CELL
    B.box("ground", (0, 0, -0.3), (w, d, 0.3), "road", shade)
    for col in SPAN_COLS:
        for row in SPAN_ROWS:
            bx, by = block_origin(col, row)
            B.box(f"pave_{col}_{row}", (bx * CELL, by * CELL, 0.0),
                  (BLOCK * CELL, BLOCK * CELL, 0.05), "pavement", shade)


def park(shade):
    col, row = PARK_BLOCK
    bx, by = block_origin(col, row)
    x, y = bx * CELL, by * CELL
    size = BLOCK * CELL
    B.box("park_lawn", (x, y, 0.06), (size, size, 0.06), "green", shade)
    for i in range(9):
        tx = x + 9 + (i % 3) * 30
        ty = y + 9 + (i // 3) * 30
        B.box(f"park_trunk_{i}", (tx, ty, 0.0), (1.0, 1.0, 3.0), "roof", shade)
        B.box(f"park_crown_{i}", (tx - 2.5, ty - 2.5, 3.0), (6.0, 6.0, 5.0), "green", shade)
    B.box("park_bench", (x + 6, y + size - 8, 0.1), (3.0, 0.8, 0.5), "accent", shade)


def parking(shade):
    """Парковка торгового центра: асфальт и ряды машин.

    Машины мельче тумбочки, но без них площадка читается как пустырь, а масштаб
    здания теряется — это тот случай, когда мелочь работает на композицию.
    """
    (col, row), plot = MALL_PARKING
    px, py = plot_origin(col, row, plot)
    x, y = px * CELL, py * CELL
    size = (BLOCK // 2) * CELL - CELL
    B.box("mall_lot", (x, y, 0.06), (size, size, 0.06), "road", shade)
    for r in range(4):
        for c in range(7):
            B.box(f"mall_car_{r}_{c}", (x + 3 + c * 2.6, y + 4 + r * 11.0, 0.12),
                  (1.9, 4.4, 1.5), "appl", shade)


def house(name, x, y, w, d, floors, tone, shade, entry=True):
    h = floors * FLOOR
    B.box(f"{name}_body", (x, y, 0.0), (w, d, h), tone, shade)
    B.box(f"{name}_roof", (x - 0.4, y - 0.4, h), (w + 0.8, d + 0.8, 0.7), "roof", shade)
    if entry:
        # Вход на южном фасаде: камера стоит с юго-востока, оттуда он и виден
        B.box(f"{name}_entry", (x + w / 2 - 1.5, y - 0.5, 0.0), (3.0, 0.7, 3.2),
              "accent", shade)
    if floors >= 10:
        # Высоткам — ступень и надстройка, иначе они просто длинные бруски
        B.box(f"{name}_step", (x + w * 0.18, y + d * 0.18, h + 0.7),
              (w * 0.64, d * 0.64, FLOOR * 2.5), tone, shade)
        B.box(f"{name}_cap", (x + w * 0.36, y + d * 0.36, h + 0.7 + FLOOR * 2.5),
              (w * 0.28, d * 0.28, FLOOR * 1.2), "roof", shade)


def landmarks(shade, mark=False):
    """mark — покрасить кликабельные акцентным тоном: проверка, видно ли их в кадре.

    Для подачи генератору не годится, это служебный режим.
    """
    taken = {(MALL_PARKING[0][0], MALL_PARKING[0][1], MALL_PARKING[1])}
    for key, (blk, plot, span, floors, tone, _what) in LANDMARKS.items():
        col, row = blk
        px, py = plot_origin(col, row, plot)
        w = (BLOCK // 2) * span - 1
        d = (BLOCK // 2) - 1
        house(f"bld_{key}", px * CELL, py * CELL, w * CELL, d * CELL,
              floors, "accent" if mark else tone, shade)
        for s in range(span):
            taken.add((col, row, plot + s))
    return taken


def filler(shade, taken, seed=7):
    """Фоновая застройка по зонам. Не кликается, живёт в подложке.

    Её задача двойная: развести важные здания друг от друга и показать, что город
    продолжается за кадром.
    """
    rnd = random.Random(seed)
    count = 0
    for col in SPAN_COLS:
        for row in SPAN_ROWS:
            if (col, row) == PARK_BLOCK:
                continue
            lo, hi, split, tones = ZONE_RULES[zone_of(col, row)]
            for plot in range(4):
                if (col, row, plot) in taken:
                    continue
                px, py = plot_origin(col, row, plot)
                half = BLOCK // 2
                for sx in range(split):
                    for sy in range(split):
                        cellw = half / split
                        w = cellw - (1.0 if split == 1 else 0.4)
                        d = cellw - (1.0 if split == 1 else 0.4)
                        if split == 1:
                            w -= rnd.choice([0.0, 0.0, 1.0])
                            d -= rnd.choice([0.0, 1.0])
                        x = (px + sx * cellw + rnd.choice([0.0, 0.3])) * CELL
                        y = (py + sy * cellw + rnd.choice([0.0, 0.3])) * CELL
                        house(f"fill_{col}{row}{plot}_{sx}{sy}", x, y,
                              w * CELL, d * CELL, rnd.randint(lo, hi),
                              rnd.choice(tones), shade, entry=False)
                        count += 1
    return count


def walk_report():
    def centre(key):
        blk, plot, span, *_ = LANDMARKS[key]
        px, py = plot_origin(blk[0], blk[1], plot)
        return (px + (BLOCK // 2) * span / 2) * CELL, (py + BLOCK // 4) * CELL

    hx, hy = centre("home")
    speed = WALK_KMH * 1000 / 60
    print(f"[blockout] город {GRID[0]}x{GRID[1]} клеток = "
          f"{GRID[0] * CELL:.0f}x{GRID[1] * CELL:.0f} м, "
          f"в кадре {VIEW:.0f} м по горизонтали — края домов обрезаются")
    print("[blockout] пешком от дома героя (по улицам, не напрямую):")
    for key in LANDMARKS:
        if key == "home":
            continue
        x, y = centre(key)
        dist = abs(x - hx) + abs(y - hy)
        print(f"  {key:9} {dist:5.0f} м — {dist / speed:4.1f} мин")
    px, py = block_origin(*PARK_BLOCK)
    dist = abs(px * CELL - hx) + abs(py * CELL - hy)
    print(f"  {'park':9} {dist:5.0f} м — {dist / speed:4.1f} мин")


def view_centre():
    """Кадр строим вокруг середины между кликабельными локациями, а не города."""
    xs, ys = [], []
    for blk, plot, span, *_ in LANDMARKS.values():
        px, py = plot_origin(blk[0], blk[1], plot)
        xs.append((px + (BLOCK // 2) * span / 2) * CELL)
        ys.append((py + BLOCK // 4) * CELL)
    return sum(xs) / len(xs), sum(ys) / len(ys)


def main():
    def extra(p):
        p.add_argument("--sprites", action="store_true",
                       help="кликабельные здания отдельными кадрами, прозрачный фон (8.1)")
        p.add_argument("--iso", choices=["dimetric", "true"], default="dimetric",
                       help="dimetric 2:1 — пиксельная сетка; true — истинная изометрия")
        p.add_argument("--seed", type=int, default=7, help="сид фоновой застройки")
        p.add_argument("--view", type=float, default=VIEW,
                       help="ширина кадра в метрах: чем меньше, тем ближе план")
        p.add_argument("--mark", action="store_true",
                       help="подсветить кликабельные здания — проверить, все ли в кадре")

    a = B.args(extra)
    B.reset()
    ground(a.shade)
    park(a.shade)
    parking(a.shade)
    taken = landmarks(a.shade, a.mark)
    fills = filler(a.shade, taken, a.seed)
    B.light(a.phase, a.shade)

    elev = 26.565 if a.iso == "dimetric" else 35.264
    cx, cy = view_centre()
    cams = {"map": B.iso_camera("map", (cx, cy, 14.0), a.view, elev)}

    root = os.path.normpath(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..",
        "assets", "_source", "blockout"))
    out = B.resolve(a.out) or os.path.join(root, "renders_city")

    print(f"[blockout] кликабельных зданий {len(LANDMARKS)}, фоновых {fills}, "
          f"всего {len(LANDMARKS) + fills}, плюс парк и парковка")
    walk_report()

    if a.sprites:
        sprites(out, a, elev)
        return
    B.finish(cams, a, out, os.path.join(root, "city.blend"))


def sprites(out, a, elev):
    """По спрайту на кликабельное здание: один ракурс, один масштаб, прозрачный фон.

    Масштаб общий — иначе здания окажутся разного размера на карте, а это главная
    ошибка, которую блокаут и должен снять. Фоновая застройка сюда не идёт.
    """
    sc = bpy.context.scene
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 512
    span = max(b[3] for b in LANDMARKS.values()) * FLOOR * 1.6
    cams = {}
    for key, (blk, plot, sp, *_rest) in LANDMARKS.items():
        px, py = plot_origin(blk[0], blk[1], plot)
        cx = (px + (BLOCK // 2) * sp / 2) * CELL
        cy = (py + BLOCK // 4) * CELL
        cams[key] = B.iso_camera(f"spr_{key}", (cx, cy, 14.0), span, elev)
    others = tuple(f"bld_{o}_" for o in LANDMARKS)
    hide = {key: tuple(m for m in others if m != f"bld_{key}_") +
            ("ground", "pave_", "park_", "fill_", "mall_") for key in LANDMARKS}
    files = B.render(cams, out, f"_spr_{a.shade}", "all", hide)
    print(f"[blockout] спрайтов: {len(files)}")


main()
