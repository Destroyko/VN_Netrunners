# Блокаут района для карты навигации (docs/art/ai-pipeline.md, раздел 8).
#
# Карта — изометрия, а не «вид сверху под углом»: ортографическая камера под углом,
# один и тот же ракурс у всех зданий. Блокаут нужен именно за этим — генератор
# не держит единый угол между отдельными прогонами.
#
# Район застраивается кварталами: важные локации стоят в разных концах и между ними
# обычные дома, иначе герою некуда идти и дорога ничего не стоит по времени
# (../gameplay/core-loop.md: перемещение тратит время). Кликабельных зданий — список
# из docs/world/locations.md, их рисуем все сразу, даже те, чей контент будет позже.
# Остальное — фоновая застройка: она не кликается и живёт в подложке.
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
CELL = 12.0       # клетка плана в метрах; на карте это 32 px (раздел 8.2)
FLOOR = 3.0       # высота этажа
BLOCK = 8         # квартал — 8×8 клеток, внутри четыре участка 4×4
ROAD = 2          # ширина улицы в клетках
COLS, ROWS = 4, 4  # кварталов по горизонтали и вертикали
WALK_KMH = 4.5    # пешком; отсюда считается время дороги

# Кликабельные локации: ключ -> (квартал (col, row), участок, участков, этажей, тон, что это)
# Участок — индекс 0..3 внутри квартала: 0 ЮЗ, 1 ЮВ, 2 СЗ, 3 СВ.
# «Участков» — 1 (обычный дом) или 2 (занимает ещё и соседний по горизонтали).
# Локации разнесены по разным концам намеренно: дорога должна стоить времени,
# а дом героя не должен стоять вплотную к больнице и вокзалу.
LANDMARKS = {
    "home":     ((0, 1), 0, 1, 5, "facade_a", "жилой дом героя: ПК, сон, еда"),
    "school":   ((0, 0), 3, 1, 3, "facade_c", "вечерняя школа: обучение"),
    "market":   ((1, 0), 1, 1, 1, "facade_c", "барахолка: задел"),
    "station":  ((2, 0), 0, 2, 3, "facade_b", "вокзал: задел"),
    "hospital": ((1, 2), 2, 2, 4, "facade_b", "больница: мать героя"),
    "mall":     ((2, 2), 0, 2, 2, "facade_a", "торговый центр: хаб, внутри спортзал"),
    "tower_b":  ((3, 1), 1, 1, 9, "facade_c", "бизнес-центр"),
    "tower_a":  ((3, 2), 3, 1, 12, "facade_b", "высотка: офисы и узлы сети"),
    "elite":    ((3, 3), 2, 2, 6, "facade_a", "элитный квартал: задел"),
}
# Целый квартал под парк: скамейка — «ждать вне дома» (../gameplay/time.md)
PARK_BLOCK = (0, 3)

STEP = BLOCK + ROAD          # шаг сетки кварталов
GRID = (COLS * STEP + ROAD, ROWS * STEP + ROAD)
FILL_TONES = ["facade_a", "facade_b", "facade_c"]


def block_origin(col, row):
    return ROAD + col * STEP, ROAD + row * STEP


def plot_origin(col, row, plot):
    """Левый нижний угол участка 4×4 внутри квартала."""
    bx, by = block_origin(col, row)
    return bx + (plot % 2) * (BLOCK // 2), by + (plot // 2) * (BLOCK // 2)


def ground(shade):
    w, d = GRID[0] * CELL, GRID[1] * CELL
    B.box("ground", (0, 0, -0.3), (w, d, 0.3), "road", shade)
    # Тротуары — это кварталы целиком; дороги остаются полосами между ними
    for col in range(COLS):
        for row in range(ROWS):
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
        tx = x + 6 + (i % 3) * 20
        ty = y + 6 + (i // 3) * 20
        B.box(f"park_trunk_{i}", (tx, ty, 0.0), (0.8, 0.8, 2.6), "roof", shade)
        B.box(f"park_crown_{i}", (tx - 1.8, ty - 1.8, 2.6), (4.4, 4.4, 4.0), "green", shade)
    B.box("park_bench", (x + 4, y + size - 6, 0.1), (3.0, 0.8, 0.5), "accent", shade)


def house(name, x, y, w, d, floors, tone, shade, entry=True):
    """Дом: корпус, парапет, вход. Больше коробок не нужно — остальное дорисует генератор."""
    h = floors * FLOOR
    B.box(f"{name}_body", (x, y, 0.0), (w, d, h), tone, shade)
    B.box(f"{name}_roof", (x - 0.4, y - 0.4, h), (w + 0.8, d + 0.8, 0.7), "roof", shade)
    if entry:
        # Вход на южном фасаде: камера стоит с юго-востока, оттуда он и виден
        B.box(f"{name}_entry", (x + w / 2 - 1.5, y - 0.5, 0.0), (3.0, 0.7, 3.2),
              "accent", shade)
    if floors >= 7:
        B.box(f"{name}_step", (x + w * 0.2, y + d * 0.2, h + 0.7),
              (w * 0.5, d * 0.5, FLOOR * 2), tone, shade)


def landmarks(shade):
    taken = set()
    for key, (blk, plot, span, floors, tone, _what) in LANDMARKS.items():
        col, row = blk
        px, py = plot_origin(col, row, plot)
        w = (BLOCK // 2) * span - 1
        d = (BLOCK // 2) - 1
        house(f"bld_{key}", px * CELL, py * CELL, w * CELL, d * CELL,
              floors, tone, shade)
        for s in range(span):
            taken.add((col, row, plot + s))
    return taken


def filler(shade, taken, seed=7):
    """Фоновая застройка: обычные дома, которые не кликаются.

    Их задача — чтобы важные здания стояли не вплотную. Расстояние между локациями
    и есть стоимость дороги во времени.
    """
    rnd = random.Random(seed)
    count = 0
    for col in range(COLS):
        for row in range(ROWS):
            if (col, row) == PARK_BLOCK:
                continue
            for plot in range(4):
                if (col, row, plot) in taken:
                    continue
                px, py = plot_origin(col, row, plot)
                # Форма и этажность гуляют, иначе район превращается в шахматы
                w = (BLOCK // 2) - rnd.choice([1, 1, 2])
                d = (BLOCK // 2) - rnd.choice([1, 2])
                floors = rnd.choice([3, 4, 4, 5, 5, 6, 9])
                off_x = rnd.choice([0.0, 0.5])
                off_y = rnd.choice([0.0, 0.5])
                house(f"fill_{col}{row}{plot}", (px + off_x) * CELL, (py + off_y) * CELL,
                      w * CELL, d * CELL, floors, FILL_TONES[(col + row + plot) % 3],
                      shade, entry=False)
                count += 1
    return count


def walk_report():
    """Сколько идти от дома до каждой локации — ради этого район и расширен."""
    def centre(key):
        blk, plot, span, *_ = LANDMARKS[key]
        px, py = plot_origin(blk[0], blk[1], plot)
        return (px + (BLOCK // 2) * span / 2) * CELL, (py + BLOCK // 4) * CELL

    hx, hy = centre("home")
    speed = WALK_KMH * 1000 / 60      # метров в минуту
    print(f"[blockout] район {GRID[0]}x{GRID[1]} клеток = "
          f"{GRID[0] * CELL:.0f}x{GRID[1] * CELL:.0f} м, "
          f"на карте {GRID[0] * 32}x{GRID[1] * 32} px при клетке 32 px")
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


def main():
    def extra(p):
        p.add_argument("--sprites", action="store_true",
                       help="кликабельные здания отдельными кадрами, прозрачный фон (8.1)")
        p.add_argument("--iso", choices=["dimetric", "true"], default="dimetric",
                       help="dimetric 2:1 — пиксельная сетка; true — истинная изометрия")
        p.add_argument("--seed", type=int, default=7, help="сид фоновой застройки")

    a = B.args(extra)
    B.reset()
    ground(a.shade)
    park(a.shade)
    taken = landmarks(a.shade)
    fills = filler(a.shade, taken, a.seed)
    B.light(a.phase, a.shade)

    elev = 26.565 if a.iso == "dimetric" else 35.264
    cx, cy = GRID[0] * CELL / 2, GRID[1] * CELL / 2
    # Охват считаем, а не подбираем: в изометрии район занимает по экрану свою
    # диагональ, а высотки добавляют сверху. Иначе кадр режет край района.
    diag = (GRID[0] + GRID[1]) * CELL * math.cos(math.radians(45))
    top = max(b[3] for b in LANDMARKS.values()) * FLOOR + 6
    vert = diag * math.sin(math.radians(elev)) + top * math.cos(math.radians(elev))
    span = diag * 1.04
    cams = {"map": B.iso_camera("map", (cx, cy, top * 0.3), span, elev)}
    # Карта не 16:9: квадратный район в изометрии — широкий плоский ромб. Кадр режем
    # по нему, иначе половина картинки уходит в пустоту сверху и снизу.
    if not a.sprites:
        sc = bpy.context.scene
        sc.render.resolution_y = int(B.RES[0] * vert * 1.06 / span / 2) * 2

    root = os.path.normpath(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..",
        "assets", "_source", "blockout"))
    out = a.out or os.path.join(root, "renders_city")

    print(f"[blockout] кликабельных зданий {len(LANDMARKS)}, фоновых {fills}, "
          f"всего {len(LANDMARKS) + fills} плюс парк")
    walk_report()

    if a.sprites:
        sprites(out, a, elev)
        return
    B.finish(cams, a, out, os.path.join(root, "city.blend"))


def sprites(out, a, elev):
    """По спрайту на кликабельное здание: один ракурс, один масштаб, прозрачный фон.

    Масштаб общий — иначе здания окажутся разного размера на карте, а это главная
    ошибка, которую блокаут и должен снять. Фоновая застройка сюда не идёт:
    она живёт в подложке и не кликается.
    """
    sc = bpy.context.scene
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 512
    span = max(b[3] for b in LANDMARKS.values()) * FLOOR * 1.9
    cams = {}
    for key, (blk, plot, sp, *_rest) in LANDMARKS.items():
        px, py = plot_origin(blk[0], blk[1], plot)
        cx = (px + (BLOCK // 2) * sp / 2) * CELL
        cy = (py + BLOCK // 4) * CELL
        cams[key] = B.iso_camera(f"spr_{key}", (cx, cy, 8.0), span, elev)
    others = tuple(f"bld_{o}_" for o in LANDMARKS)
    hide = {key: tuple(m for m in others if m != f"bld_{key}_") +
            ("ground", "pave_", "park_", "fill_") for key in LANDMARKS}
    files = B.render(cams, out, f"_spr_{a.shade}", "all", hide)
    print(f"[blockout] спрайтов: {len(files)}")


main()
