# Блокаут города для карты навигации (docs/world/locations.md, docs/art/blender-scenes.md).
#
# Карта — изометрия: ортографическая камера под углом, один ракурс у всех зданий.
#
# Три правила, которые задал разработчик:
#
# 1. **Город больше кадра.** Строим заведомо больше, чем видно, и кадрируем так, чтобы
#    по краям дома обрезались: карта — кусок города, а не остров с границами.
# 2. **Район неоднороден.** Офисы — в высотках, торговый центр — длинная коробка
#    с парковкой, трущобы — плотная мелкая застройка.
# 3. **Город не в клеточку.** Кварталы разного размера, проспект идёт по диагонали,
#    есть река с мостами, а жилой квартал — это дома по периметру с двором внутри,
#    а не кубик посреди участка. Ровная сетка одинаковых квадратов — первое, что
#    выдаёт сгенерированный город.
#
# Кликабельные локации (список — docs/world/locations.md) стоят внутри кадра и разнесены
# по разным кварталам: между ними обычная застройка, и дорога стоит времени.
# Фоновые дома не кликаются и живут в подложке.
#
# Запуск (PowerShell):
#   & "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" -b `
#     --python tools\blockout\city.py -- --render map
#   ... -- --sprites   # кликабельные здания отдельными кадрами
#   ... -- --mark      # подсветить кликабельные: все ли в кадре

import math
import os
import random
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bl_common as B  # noqa: E402

FLOOR = 3.0          # высота этажа
COLS, ROWS = 11, 11  # кварталов; в кадр попадает примерно пять на пять
VIEW = 820.0         # ширина кадра в метрах: по ней режутся края города
WALK_KMH = 4.5       # пешком; отсюда считается время дороги

BLOCK_SIZES = [84, 96, 108, 120, 132]   # сторона квартала в метрах — разная
STREET_W = [20, 22, 24, 24, 28]         # обычные улицы
AVENUE_W = 46                           # проспект: шире и заметнее
AVENUE_AT = 5                           # индекс улицы-проспекта в каждом направлении

# Диагональный проспект и река: (точка на оси, угол в градусах, ширина)
DIAGONAL = ((660.0, 560.0), 28.0, 42.0)
RIVER = ((520.0, 980.0), -22.0, 90.0)
BRIDGE_STREETS = [3, 6, 9]              # на каких улицах (индексы по Y) есть мосты

# Зоны. (этажи от, этажи до, как застраивается)
ZONE_RULES = {
    "downtown":   (11, 21, "towers"),
    "residential": (4, 8, "perimeter"),
    "slums":      (2, 3, "slums"),
    "commercial": (1, 3, "big"),
    "industrial": (1, 2, "sheds"),
}
# Кварталы, где col + row == 9, оставлены пустыми под жильё намеренно: по этой
# диагонали проходит река. Иначе ей негде течь — локации забивают центр кадра,
# и подбор оси уводит её за край.
ZONES = {
    (6, 5): "downtown", (7, 5): "downtown", (6, 6): "downtown", (7, 6): "downtown",
    (7, 4): "downtown", (8, 5): "downtown", (8, 4): "downtown",
    (3, 3): "slums", (4, 3): "slums", (3, 4): "slums", (2, 3): "slums", (3, 2): "slums",
    (6, 2): "commercial", (5, 1): "commercial",
    (8, 2): "industrial", (9, 2): "industrial", (9, 3): "industrial",
}
PARK_BLOCK = (4, 6)

# Кликабельные локации: ключ -> (квартал, четверть, четвертей, этажей, тон, что это)
# Четверть квартала: 0 ЮЗ, 1 ЮВ, 2 СЗ, 3 СВ. «Четвертей» 2 — занимает половину квартала.
LANDMARKS = {
    "home":     ((3, 5), 0, 1, 5, "facade_a", "жилой дом героя: ПК, сон, еда"),
    "school":   ((4, 4), 3, 1, 3, "facade_c", "вечерняя школа: обучение"),
    "market":   ((3, 3), 1, 1, 1, "facade_c", "барахолка: задел, стоит в трущобах"),
    "station":  ((5, 2), 0, 2, 3, "facade_b", "вокзал: задел"),
    "hospital": ((5, 3), 2, 2, 6, "facade_b", "больница: мать героя"),
    "mall":     ((6, 2), 2, 2, 2, "facade_a", "торговый центр: хаб, спортзал, парковка"),
    "tower_b":  ((6, 5), 1, 1, 15, "facade_c", "бизнес-центр"),
    "tower_a":  ((7, 5), 3, 1, 21, "facade_b", "высотка: офисы и узлы сети"),
    "elite":    ((4, 7), 2, 2, 8, "facade_a", "элитный квартал: задел, окнами в парк"),
}
MALL_PARKING = ((6, 2), 0)

placed = []      # занятые прямоугольники: (x0, y0, x1, y1)
registry = []    # то же плюс имя — для проверки «кто стоит в реке»
RIVER_AXIS = RIVER   # рабочая ось реки: fit_river() сдвигает её под сетку улиц


# --- сетка улиц ---------------------------------------------------------------

def street_lines(rnd, count):
    """Улицы по одной оси: позиция и ширина. Шаг между ними гуляет."""
    lines, x = [], 0.0
    for i in range(count + 1):
        w = AVENUE_W if i == AVENUE_AT else rnd.choice(STREET_W)
        lines.append((x, w))
        x += w + rnd.choice(BLOCK_SIZES)
    return lines


def blocks_of(lines):
    """Кварталы между улицами: (начало, длина)."""
    out = []
    for i in range(len(lines) - 1):
        start = lines[i][0] + lines[i][1]
        out.append((start, lines[i + 1][0] - start))
    return out


def block_rect(col, row):
    x, w = BX[col]
    y, d = BY[row]
    return x, y, w, d


def quarter_rect(col, row, q, span=1):
    """Четверть квартала (или половина при span=2) с отступом от улицы."""
    x, y, w, d = block_rect(col, row)
    hw, hd = w / 2, d / 2
    qx = x + (q % 2) * hw
    qy = y + (q // 2) * hd
    return qx + 3, qy + 3, hw * span - 6, hd - 6


# --- что мешает ставить дома --------------------------------------------------

def in_water(x, y, w, d, pad=6.0):
    """Залезает ли пятно в реку (с запасом на набережную)."""
    centre, angle, width = RIVER_AXIS
    return B.band_hits((x, y, x + w, y + d), centre, angle, width, pad)


def fit_river():
    """Сдвинуть реку перпендикулярно её оси, пока она не режет то, что стоит жёстко:
    парк, парковку и кликабельные здания.

    Кварталы собираются из случайных шагов, а локации расставлены руками — ось реки
    при любом сиде может пройти прямо по больнице. Подбирать числа вручную после
    каждого сида бессмысленно, поэтому двигается река, а не город.
    """
    centre, angle, width = RIVER
    a = math.radians(angle)
    n = (-math.sin(a), math.cos(a))
    fixed = []
    for blk, q, span, *_ in LANDMARKS.values():
        x, y, w, d = quarter_rect(blk[0], blk[1], q, span)
        fixed.append((x, y, x + w, y + d))
    for blk in (PARK_BLOCK,):
        x, y, w, d = block_rect(*blk)
        fixed.append((x, y, x + w, y + d))
    x, y, w, d = quarter_rect(MALL_PARKING[0][0], MALL_PARKING[0][1], MALL_PARKING[1])
    fixed.append((x, y, x + w, y + d))

    # Ось ищем по двум условиям сразу: не резать локации и при этом быть видной.
    # Сдвига мало — отодвинутая река уходит за край кадра, и смысла в ней нет.
    vx, vy = view_centre()
    reach = VIEW / 2.8           # половина стороны кадра в плане, грубо
    best = None
    for turn in range(-80, 81, 5):
        ang = angle + turn
        aa = math.radians(ang)
        nn = (-math.sin(aa), math.cos(aa))
        for step in range(-24, 25):
            off = step * 16.0
            c = (centre[0] + nn[0] * off, centre[1] + nn[1] * off)
            if any(B.band_hits(r, c, ang, width, 10.0) for r in fixed):
                continue
            seen = sum(1 for t in range(-100, 101)
                       if abs(c[0] + math.cos(aa) * t * 10 - vx) < reach
                       and abs(c[1] + math.sin(aa) * t * 10 - vy) < reach)
            score = (seen, -abs(turn), -abs(off))
            if best is None or score > best[0]:
                best = (score, (c, ang, width))
    if best is None:
        print("[blockout] ВНИМАНИЕ: реке не нашлось места, не задев локации")
        return RIVER
    (seen, _, _), axis = best
    print(f"[blockout] ось реки: поворот {axis[1] - angle:+.0f}°, "
          f"в кадре {seen * 10} м русла")
    return axis


def blocked(x, y, w, d):
    """Пересекается ли пятно с рекой, проспектом или уже поставленным домом."""
    if in_water(x, y, w, d):
        return True
    if B.band_hits((x, y, x + w, y + d), DIAGONAL[0], DIAGONAL[1], DIAGONAL[2], 2.0):
        return True
    for px0, py0, px1, py1 in placed:
        if x < px1 and px0 < x + w and y < py1 and py0 < y + d:
            return True
    return False


def put(name, x, y, w, d, floors, tone, shade, entry=False, force=False):
    if not force and blocked(x, y, w, d):
        return 0
    placed.append((x, y, x + w, y + d))
    registry.append((name, x, y, w, d))
    h = floors * FLOOR
    B.box(f"{name}_body", (x, y, 0.0), (w, d, h), tone, shade)
    B.box(f"{name}_roof", (x - 0.4, y - 0.4, h), (w + 0.8, d + 0.8, 0.7), "roof", shade)
    if entry:
        B.box(f"{name}_entry", (x + w / 2 - 1.5, y - 0.5, 0.0), (3.0, 0.7, 3.2),
              "accent", shade)
    if floors >= 10:
        B.box(f"{name}_step", (x + w * 0.18, y + d * 0.18, h + 0.7),
              (w * 0.64, d * 0.64, FLOOR * 2.5), tone, shade)
        B.box(f"{name}_cap", (x + w * 0.36, y + d * 0.36, h + 0.7 + FLOOR * 2.5),
              (w * 0.28, d * 0.28, FLOOR * 1.2), "roof", shade)
    return 1


# --- земля, вода, дороги ------------------------------------------------------

def ground(shade):
    w = BX[-1][0] + BX[-1][1] + 60
    d = BY[-1][0] + BY[-1][1] + 60
    B.box("ground", (-30, -30, -0.3), (w, d, 0.3), "road", shade)
    for col in range(COLS):
        for row in range(ROWS):
            x, y, bw, bd = block_rect(col, row)
            B.box(f"pave_{col}_{row}", (x, y, 0.0), (bw, bd, 0.05), "pavement", shade)
    # Проспект и река кладутся поверх кварталов: они режут сетку, а не обходят её
    long_side = max(w, d) * 1.6
    B.slab("avenue", (*DIAGONAL[0], 0.09), (long_side, DIAGONAL[2], 0.06),
           DIAGONAL[1], "road", shade)
    # Разделительная полоса: без неё проспект не отличить от обычной улицы
    B.slab("avenue_median", (*DIAGONAL[0], 0.16), (long_side, 5.0, 0.3),
           DIAGONAL[1], "green", shade)
    rc, ra_deg, rw = RIVER_AXIS
    B.slab("river", (*rc, 0.04), (long_side, rw, 0.06), ra_deg, "water", shade)
    # Набережные по обеим сторонам реки
    a = math.radians(ra_deg)
    for i, side in enumerate((-1, 1)):
        off = side * (rw / 2 + 5)
        c = (rc[0] - math.sin(a) * off, rc[1] + math.cos(a) * off)
        B.slab(f"quay_{i}", (*c, 0.1), (long_side, 10.0, 0.1), ra_deg, "pavement", shade)
    bridges(shade)


def bridges(shade):
    """Мост — продолжение улицы через реку, а не плашка посреди воды.

    Раньше мост поворачивался на угол реки плюс 90° вместе со своей длинной
    стороной — и ложился ВДОЛЬ течения. В кадре это читалось как баржа.
    Теперь мост идёт по улице (вдоль X) и перекрывает полосу воды целиком:
    её горизонтальная протяжённость — ширина реки, делённая на косинус наклона.
    """
    rc, ra_deg, rw = RIVER_AXIS
    a = math.radians(ra_deg)
    span = rw / abs(math.cos(a)) + 80
    city_w = BX[-1][0] + BX[-1][1]
    for n, idx in enumerate(BRIDGE_STREETS):
        if idx >= len(LY):
            continue
        y0, road_w = LY[idx]
        ystreet = y0 + road_w / 2
        x = rc[0] + math.cos(a) * (ystreet - rc[1]) / math.sin(a)
        if not -40 < x < city_w + 40:
            continue
        deck = max(road_w, 18.0)
        B.slab(f"bridge_{n}", (x, ystreet, 1.1), (span, deck, 1.5), 0.0, "bridge", shade)
        for side in (-1, 1):
            B.slab(f"bridge_{n}_rail{side}", (x, ystreet + side * (deck / 2 - 1.0), 2.6),
                   (span, 2.0, 1.5), 0.0, "pavement", shade)


def avenue_front(shade, rnd):
    """Фронт проспекта: дома стоят вдоль него, повёрнутые по его оси.

    Без этого диагональ выглядит просекой через пустырь: обычная застройка
    в клетку к ней не прилегает, и вдоль проспекта остаются дыры.
    """
    (cx, cy), angle, width = DIAGONAL
    a = math.radians(angle)
    n, depth = 0, 19.0
    reach = max(BX[-1][0] + BX[-1][1], BY[-1][0] + BY[-1][1])
    t = -reach * 0.7
    while t < reach * 0.7:
        length = rnd.uniform(34.0, 56.0)
        floors = rnd.randint(5, 9)
        for side in (-1, 1):
            off = side * (width / 2 + depth / 2 + 2.0)
            bx = cx + math.cos(a) * t - math.sin(a) * off
            by = cy + math.sin(a) * t + math.cos(a) * off
            if in_water(bx - depth, by - depth, depth * 2, depth * 2, 2.0):
                continue
            half = max(length, depth) / 2
            if any(bx - half < p2 and p0 < bx + half and by - half < p3 and p1 < by + half
                   for p0, p1, p2, p3 in placed):
                continue
            placed.append((bx - half, by - half, bx + half, by + half))
            registry.append((f"av_{n}", bx - half, by - half, half * 2, half * 2))
            h = floors * FLOOR
            B.slab(f"av_{n}", (bx, by, 0.0), (length, depth, h), angle,
                   rnd.choice(TONES), shade)
            B.slab(f"av_{n}_roof", (bx, by, h), (length + 0.8, depth + 0.8, 0.7),
                   angle, "roof", shade)
            n += 1
        t += length + rnd.uniform(6.0, 16.0)
    return n


def park(shade):
    x, y, w, d = block_rect(*PARK_BLOCK)
    placed.append((x, y, x + w, y + d))
    registry.append(("park", x, y, w, d))
    B.box("park_lawn", (x, y, 0.06), (w, d, 0.06), "green", shade)
    rows = int(d // 34)
    cols = int(w // 34)
    for i in range(rows * cols):
        tx = x + 14 + (i % cols) * 34
        ty = y + 14 + (i // cols) * 34
        B.box(f"park_trunk_{i}", (tx, ty, 0.0), (1.0, 1.0, 3.0), "roof", shade)
        B.box(f"park_crown_{i}", (tx - 2.5, ty - 2.5, 3.0), (6.0, 6.0, 5.0), "green", shade)
    B.box("park_bench", (x + 8, y + d - 10, 0.1), (3.0, 0.8, 0.5), "accent", shade)


def parking(shade):
    (col, row), q = MALL_PARKING
    x, y, w, d = quarter_rect(col, row, q)
    placed.append((x, y, x + w, y + d))
    registry.append(("mall_lot", x, y, w, d))
    B.box("mall_lot", (x, y, 0.06), (w, d, 0.06), "road", shade)
    for r in range(int(d // 12)):
        for c in range(int(w // 2.7)):
            B.box(f"mall_car_{r}_{c}", (x + 3 + c * 2.7, y + 4 + r * 12.0, 0.12),
                  (1.9, 4.4, 1.5), "appl", shade)


# --- типы застройки -----------------------------------------------------------

def build_perimeter(name, x, y, w, d, lo, hi, tones, rnd, shade):
    """Жилой квартал: пластины вдоль улиц, двор внутри.

    Так застроена половина реальных городов, и именно этого не хватало: кубик
    посреди участка читается как макет, а периметр — как квартал.
    """
    n, depth = 0, rnd.choice([14.0, 16.0, 18.0])
    gap = rnd.choice([8.0, 12.0, 16.0])      # разрыв в углу: двор должен дышать
    sides = [
        (x, y, w - gap, depth),
        (x + w - depth, y, depth, d - gap),
        (x + gap, y + d - depth, w - gap, depth),
        (x, y + gap, depth, d - gap),
    ]
    for i, (sx, sy, sw, sd) in enumerate(sides):
        if sw < 18 or sd < 10:
            continue
        # Длинную пластину режем на секции разной этажности — дом не монолит
        along = sw if sw > sd else sd
        cuts = max(1, int(along // rnd.choice([34, 42, 50])))
        for c in range(cuts):
            if sw > sd:
                px, pw = sx + c * sw / cuts, sw / cuts - 1.5
                py, pd = sy, sd
            else:
                px, pw = sx, sw
                py, pd = sy + c * sd / cuts, sd / cuts - 1.5
            n += put(f"{name}_p{i}{c}", px, py, pw, pd,
                     rnd.randint(lo, hi), rnd.choice(tones), shade)
    if rnd.random() < 0.4 and w > 70 and d > 70:
        n += put(f"{name}_yard", x + w / 2 - 12, y + d / 2 - 10, 24, 20,
                 rnd.randint(lo, lo + 1), rnd.choice(tones), shade)
    return n


def build_towers(name, x, y, w, d, lo, hi, tones, rnd, shade):
    """Даунтаун: башни с разрывами, разного пятна и высоты."""
    n = 0
    for i in range(rnd.choice([2, 3, 3, 4])):
        tw = rnd.uniform(0.28, 0.44) * w
        td = rnd.uniform(0.28, 0.44) * d
        tx = x + rnd.uniform(0, max(1.0, w - tw))
        ty = y + rnd.uniform(0, max(1.0, d - td))
        n += put(f"{name}_t{i}", tx, ty, tw, td,
                 rnd.randint(lo, hi), rnd.choice(tones), shade)
    return n


def build_slums(name, x, y, w, d, lo, hi, tones, rnd, shade):
    """Трущобы: мелкие дома почти вплотную, проходы вместо улиц."""
    n, step = 0, rnd.choice([18.0, 20.0, 22.0])
    for i in range(int(w // step)):
        for j in range(int(d // step)):
            if rnd.random() < 0.12:        # пустыри и проходы
                continue
            sw = step - rnd.uniform(3.0, 6.0)
            sd = step - rnd.uniform(3.0, 6.0)
            n += put(f"{name}_s{i}{j}", x + i * step, y + j * step, sw, sd,
                     rnd.randint(lo, hi), rnd.choice(tones), shade)
    return n


def build_big(name, x, y, w, d, lo, hi, tones, rnd, shade):
    """Торговля: один крупный объём, место вокруг остаётся под подъезды."""
    bw, bd = w * rnd.uniform(0.6, 0.8), d * rnd.uniform(0.5, 0.7)
    return put(f"{name}_b", x + (w - bw) / 2, y + (d - bd) / 2, bw, bd,
               rnd.randint(lo, hi), rnd.choice(tones), shade)


def build_sheds(name, x, y, w, d, lo, hi, tones, rnd, shade):
    """Промзона: длинные ангары поперёк квартала."""
    n, count = 0, rnd.choice([2, 3])
    for i in range(count):
        sd = d / count - 8
        n += put(f"{name}_h{i}", x + 4, y + i * (d / count), w - 8, sd,
                 rnd.randint(lo, hi), rnd.choice(tones), shade)
    return n


BUILDERS = {"perimeter": build_perimeter, "towers": build_towers, "slums": build_slums,
            "big": build_big, "sheds": build_sheds}
TONES = ["facade_a", "facade_b", "facade_c"]


def landmarks(shade, mark=False):
    for key, (blk, q, span, floors, tone, _what) in LANDMARKS.items():
        x, y, w, d = quarter_rect(blk[0], blk[1], q, span)
        put(f"bld_{key}", x, y, w, d, floors,
            "accent" if mark else tone, shade, entry=True, force=True)


def filler(shade, rnd):
    count = 0
    for col in range(COLS):
        for row in range(ROWS):
            if (col, row) == PARK_BLOCK:
                continue
            zone = ZONES.get((col, row), "residential")
            lo, hi, kind = ZONE_RULES[zone]
            x, y, w, d = block_rect(col, row)
            count += BUILDERS[kind](f"fill_{col}_{row}", x + 2, y + 2, w - 4, d - 4,
                                    lo, hi, TONES, rnd, shade)
    return count


# --- отчёт и кадр -------------------------------------------------------------

def centre_of(key):
    blk, q, span, *_ = LANDMARKS[key]
    x, y, w, d = quarter_rect(blk[0], blk[1], q, span)
    return x + w / 2, y + d / 2


def audit():
    """Проверка, которую нельзя делать на глаз: кто стоит в воде.

    Один раз мост уже оказался лежащим вдоль реки, и в кадре это выглядело
    как баржа — заметно, только если смотреть прицельно.
    """
    bad = [n for n, x, y, w, d in registry if in_water(x, y, w, d, 0.0)]
    if bad:
        print(f"[blockout] ВНИМАНИЕ: в реке стоят {len(bad)} объектов: "
              f"{', '.join(bad[:8])}")
    else:
        print("[blockout] в реке ничего не стоит, кроме мостов")


def walk_report():
    hx, hy = centre_of("home")
    speed = WALK_KMH * 1000 / 60
    w = BX[-1][0] + BX[-1][1]
    print(f"[blockout] город {w:.0f}x{BY[-1][0] + BY[-1][1]:.0f} м, "
          f"в кадре {VIEW:.0f} м по горизонтали — края домов обрезаются")
    print("[blockout] пешком от дома героя (по улицам, не напрямую):")
    for key in LANDMARKS:
        if key == "home":
            continue
        x, y = centre_of(key)
        dist = abs(x - hx) + abs(y - hy)
        print(f"  {key:9} {dist:5.0f} м — {dist / speed:4.1f} мин")
    x, y, bw, bd = block_rect(*PARK_BLOCK)
    dist = abs(x + bw / 2 - hx) + abs(y + bd / 2 - hy)
    print(f"  {'park':9} {dist:5.0f} м — {dist / speed:4.1f} мин")


def view_centre():
    pts = [centre_of(k) for k in LANDMARKS]
    return sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)


def main():
    def extra(p):
        p.add_argument("--sprites", action="store_true",
                       help="кликабельные здания отдельными кадрами, прозрачный фон (8.1)")
        p.add_argument("--iso", choices=["dimetric", "true"], default="dimetric",
                       help="dimetric 2:1 — пиксельная сетка; true — истинная изометрия")
        p.add_argument("--seed", type=int, default=7, help="сид сетки улиц и застройки")
        p.add_argument("--view", type=float, default=VIEW,
                       help="ширина кадра в метрах: чем меньше, тем ближе план")
        p.add_argument("--mark", action="store_true",
                       help="подсветить кликабельные здания — проверить, все ли в кадре")

    a = B.args(extra)
    B.reset()
    placed.clear()
    registry.clear()
    rnd = random.Random(a.seed)
    global BX, BY
    global LX, LY
    LX = street_lines(rnd, COLS)
    LY = street_lines(rnd, ROWS)
    BX = blocks_of(LX)
    BY = blocks_of(LY)
    global RIVER_AXIS
    RIVER_AXIS = fit_river()

    ground(a.shade)
    park(a.shade)
    parking(a.shade)
    landmarks(a.shade, a.mark)
    fills = avenue_front(a.shade, rnd)      # фронт проспекта — до квартальной застройки
    fills += filler(a.shade, rnd)
    B.light(a.phase, a.shade)

    elev = 26.565 if a.iso == "dimetric" else 35.264
    cx, cy = view_centre()
    cams = {"map": B.iso_camera("map", (cx, cy, 14.0), a.view, elev)}

    root = os.path.normpath(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..",
        "assets", "_source", "blockout"))
    out = B.resolve(a.out) or os.path.join(root, "renders_city")

    print(f"[blockout] кликабельных зданий {len(LANDMARKS)}, фоновых {fills}, "
          f"плюс парк, парковка, река с мостами и проспект")
    audit()
    walk_report()

    if a.sprites:
        sprites(out, a, elev)
        return
    B.finish(cams, a, out, os.path.join(root, "city.blend"))


def sprites(out, a, elev):
    """По спрайту на кликабельное здание: один ракурс, один масштаб, прозрачный фон."""
    sc = bpy.context.scene
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 512
    span = max(b[3] for b in LANDMARKS.values()) * FLOOR * 1.6
    cams = {}
    for key in LANDMARKS:
        cx, cy = centre_of(key)
        cams[key] = B.iso_camera(f"spr_{key}", (cx, cy, 14.0), span, elev)
    others = tuple(f"bld_{o}_" for o in LANDMARKS)
    hide = {key: tuple(m for m in others if m != f"bld_{key}_") +
            ("ground", "pave_", "park_", "fill_", "mall_", "avenue", "river",
             "quay_", "bridge_") for key in LANDMARKS}
    files = B.render(cams, out, f"_spr_{a.shade}", "all", hide)
    print(f"[blockout] спрайтов: {len(files)}")


main()
