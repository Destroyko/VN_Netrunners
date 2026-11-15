"""Сборка слоёв фона из библиотеки зданий.

Небо, облака и окна строятся кодом, здания берутся из assets/_source/buildings.
На выходе — отдельные PNG со прозрачностью под параллакс.

Запуск (нужны numpy, scipy и Pillow — они есть во встроенном Python у ComfyUI):

    D:\\AI\\ComfyUI\\python_embeded\\python.exe tools/bg_build.py --seed 21

Почему не системный Python: 3.15 слишком новый, колёс под него нет (docs/art/ai-pipeline.md).
"""

import argparse
import glob
import os
import re

import numpy as np
from PIL import Image

W, H = 768, 360                    # кадр шире видимых 640×360: запас под сдвиг параллакса
GROUND = 362                       # все планы стоят на одном нижнем крае

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "_source", "buildings")
OUT = os.path.join(ROOT, "assets", "backgrounds")

# Опорные цвета неба: доля высоты -> цвет. Тёплая полоса поднята на высоту крыш,
# иначе её закрывают дома.
SKY_STOPS = [(0.00, (5, 7, 22)), (0.32, (20, 24, 64)), (0.52, (56, 48, 112)),
             (0.64, (120, 76, 134)), (0.72, (214, 138, 132)), (0.80, (150, 86, 124)),
             (1.00, (70, 46, 92))]
HAZE = np.array([150, 120, 160], float)        # к этому цвету тонируются дальние планы
CLOUD_TINT = np.array([196, 174, 206], float)
WINDOW_COLORS = [(242, 196, 141), (255, 238, 194), (199, 139, 160), (150, 200, 210)]

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6],
                   [3, 11, 1, 9], [15, 7, 13, 5]], float) / 16.0 - 0.5

# Цвет ручной разметки зоны окон. Размечается в редакторе прямо на спрайте здания:
# что закрашено — то фасад, окна ставятся только туда. Программа заливает разметку
# цветом стены, так что в кадр она не попадает.
MARKER = np.array([255, 0, 255], float)

# план: (высота этажа в пикселях, дымка, шаг окон по x, по y, размер окна (ш, в), доля горящих)
# Высота дома считается как этажи × высота этажа — тогда пятиэтажка и небоскрёб встают
# в верных пропорциях. Этажность берётся из имени файла (`bld_16f_a.png`).
# Окна мельчают с удалением — это второй источник ощущения расстояния после дымки.
PLANES = {
    "far": (3.4, 0.60, 3, 5, (1, 2), 0.14),
    "mid": (6.8, 0.22, 5, 7, (2, 3), 0.22),
}
NEAR = {"floor": 10.0, "crop": (55, 90), "top": (262, 300), "darken": 0.42,
        "step": (7, 9), "win": (3, 4), "lit": 0.07}
FLOORS_DEFAULT = 9     # если этажность в имени не указана

# Доля окон, которые меняют состояние между вариантами свечения. Больше — и мерцание
# превращается в стробоскоп: в живом городе за раз гаснет пара окон, а не половина.
FLICKER = 0.06
VARIANTS = 4
SIDE_GAP = 0.18        # с какой разницы в яркости кромок считаем, что боковая грань видна


# ---------------------------------------------------------------- здания

def load_clean(path):
    """Загрузить здание, обрезать поля, отсечь «ножки» и тень под домом."""
    a = np.asarray(Image.open(path).convert("RGBA")).astype(float)
    rgb, alpha = a[..., :3], a[..., 3] / 255.0
    op = alpha >= 0.5
    if not op.any():
        return None
    rows = op.sum(1)
    body = rows[rows > 0]
    typical = np.median(body)
    keep = (rows >= max(2, rows.max() * 0.25)) & (rows <= typical * 1.6 + 4)
    ys = np.where(keep)[0]
    if len(ys) == 0:
        return None
    y0, y1 = ys.min(), ys.max() + 1
    xs = np.where(op[y0:y1].any(0))[0]
    return rgb[y0:y1, xs.min():xs.max() + 1], alpha[y0:y1, xs.min():xs.max() + 1]


def strip_windows(rgb, alpha):
    """Стереть окна, нарисованные моделью: они никогда не лежат ровной сеткой."""
    op = alpha >= 0.5
    if not op.any():
        return rgb
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    base = np.percentile(lum[op], 40)
    out = rgb.copy()
    wins = op & (lum > base + 14)
    for x in range(rgb.shape[1]):
        col = op[:, x] & ~wins[:, x]
        if col.sum() >= 3:
            out[wins[:, x], x] = np.median(rgb[col, x], axis=0)
    return out


def facade_zone(rgb, alpha):
    """Найти ручную разметку зоны окон и закрасить её цветом стены.

    Размечать можно любой формы и в несколько кусков: это просто маска. Без разметки
    зона вычисляется автоматически — по близости к основному тону фасада.
    """
    op = alpha >= 0.5
    m = op & (np.abs(rgb - MARKER).sum(-1) < 60)
    if m.sum() < 20:
        return rgb, None
    body = op & ~m
    out = rgb.copy()
    out[m] = np.median(rgb[body], axis=0) if body.any() else MARKER
    return out, m


def draw_windows(rgb, alpha, rng, step_x, step_y, win=(2, 3), zone=None):
    """Вписать сетку погашенных окон. Горящие не рисуются здесь — они уходят в отдельный слой.

    Возвращает фасад и список ячеек (y, x, h, w, цвет свечения): из него потом собираются
    варианты свечения для мерцания.
    """
    op = alpha >= 0.5
    h, w = op.shape
    if h < 16 or w < 8:
        return rgb, []
    out = rgb.copy()
    facade = np.median(rgb[op], axis=0)
    dark = facade * 0.70
    ww, wh = win
    if zone is not None:
        front, roof = zone, 0                       # размечено руками — доверяем разметке
    else:
        # иначе фронтальная грань угадывается по цвету: боковая другого тона,
        # там сетка легла бы горизонтально и сломала перспективу
        front = op & (np.sqrt(((rgb - facade) ** 2).sum(-1)) < 34)
        rows = op.sum(1)
        roof = 0
        for y in range(h):
            if rows[y] >= rows.max() * 0.6:
                roof = y + 3
                break
    cells = []
    for y in range(roof + 2, h - 4 - wh, step_y):
        for x in range(2, w - 2 - ww + 1, step_x):
            if not front[y:y + wh, x:x + ww].all():
                continue
            out[y:y + wh, x:x + ww] = dark          # погашенные читаются как дом
            col = (WINDOW_COLORS[0] if rng.random() < 0.75
                   else WINDOW_COLORS[int(rng.integers(1, 4))])
            cells.append((y, x, wh, ww, col))
    return out, cells


def scaled(rgb, alpha, target_h):
    k = target_h / rgb.shape[0]
    im = Image.fromarray(np.dstack([rgb, alpha * 255]).astype(np.uint8))
    im = im.resize((max(4, int(round(rgb.shape[1] * k))), target_h), Image.NEAREST)
    a = np.asarray(im).astype(float)
    return a[..., :3], a[..., 3] / 255.0


def _blit(plane, rgb, alpha, x, top):
    bh, bw = alpha.shape
    xs0, xs1 = max(0, x), min(W, x + bw)
    ys0, ys1 = max(0, top), min(H, top + bh)
    if xs1 <= xs0 or ys1 <= ys0:
        return
    a = alpha[ys0 - top:ys1 - top, xs0 - x:xs1 - x][..., None]
    c = rgb[ys0 - top:ys1 - top, xs0 - x:xs1 - x]
    dst = plane[ys0:ys1, xs0:xs1]
    dst[..., :3] = dst[..., :3] * (1 - a) + c * a
    dst[..., 3:] = np.maximum(dst[..., 3:], a)


def _lights(lights, cells, rng, lit_p, x, top, haze=0.0, mul=1.0):
    """Разложить горящие окна по вариантам свечения: каждый следующий чуть отличается."""
    if not cells:
        return
    base = rng.random(len(cells)) < lit_p
    for v, layer in enumerate(lights):
        state = base if v == 0 else base ^ (rng.random(len(cells)) < FLICKER)
        for (cy, cx, ch, cw, col), on in zip(cells, state):
            if not on:
                continue
            c = (np.array(col, float) * (1 - haze) + HAZE * haze) * mul
            ys, xs = top + cy, x + cx
            if 0 <= ys and ys + ch <= H and 0 <= xs and xs + cw <= W:
                layer[ys:ys + ch, xs:xs + cw, :3] = c
                layer[ys:ys + ch, xs:xs + cw, 3] = 1.0


def side_bias(rgb, alpha):
    """Насколько одна сторона дома темнее другой. Больше нуля — тень слева, меньше — справа.

    У домов с видимой боковой гранью тень и уходящая вглубь крыша смотрят в одну сторону.
    Модель рисует её то влево, то вправо, поэтому библиотеку надо приводить к одному виду,
    иначе в ряду окажутся дома с противоположным светом и перспективой.
    """
    op = alpha >= 0.5
    if not op.any():
        return 0.0
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    k = max(2, int(op.shape[1] * 0.2))
    left, right = lum[:, :k][op[:, :k]], lum[:, -k:][op[:, -k:]]
    if left.size < 10 or right.size < 10:
        return 0.0
    hi = max(left.mean(), right.mean())
    return 0.0 if hi <= 1 else (right.mean() - left.mean()) / hi


def storeys(path):
    """Этажность из имени файла: `bld_16f_a.png` -> 16. Без неё берём значение по умолчанию."""
    m = re.search(r"_(\d+)f", os.path.basename(path))
    return int(m.group(1)) if m else FLOORS_DEFAULT


def plan_height(path, floor_px, rng):
    """Высота дома на плане: этажи × высота этажа, плюс небольшой разброс."""
    return max(14, int(round(storeys(path) * floor_px * rng.uniform(0.92, 1.08))))


def _prepare(path, rng, target_h, flip_p):
    """Здание: обрезать, отмасштабировать, отразить, разобраться с зоной окон."""
    got = load_clean(path)
    if got is None:
        return None
    rgb, alpha = got
    rgb, alpha = scaled(rgb, alpha, target_h)
    # Отражаем до окон, иначе сетка съедет. У домов с боковой гранью отражение не случайное,
    # а приводящее к общему виду: тень и перспектива всегда уходят вправо.
    bias = side_bias(rgb, alpha)
    flip = bias > 0 if abs(bias) > SIDE_GAP else rng.random() < flip_p
    if flip:
        rgb, alpha = rgb[:, ::-1], alpha[:, ::-1]
    rgb, zone = facade_zone(rgb, alpha)
    if zone is None:
        rgb = strip_windows(rgb, alpha)              # без разметки стираем окна модели
    return rgb, alpha, zone


def build_plane(files, rng, floor_px, haze, step_x, step_y, win, lit_p, variants=4):
    """Ряд домов с перекрытием плюс варианты слоя свечения."""
    plane = np.zeros((H, W, 4), float)
    lights = [np.zeros((H, W, 4), float) for _ in range(variants)]
    order = list(files)
    rng.shuffle(order)
    x, i = -int(rng.integers(0, 30)), 0
    while x < W + 20:
        path = order[i % len(order)]
        got = _prepare(path, rng, plan_height(path, floor_px, rng), 0.4)
        i += 1
        if got is None:
            continue
        rgb, alpha, zone = got
        rgb, cells = draw_windows(rgb, alpha, rng, step_x, step_y, win, zone)
        rgb = rgb * (1 - haze) + HAZE * haze
        top = GROUND - alpha.shape[0]
        _blit(plane, rgb, alpha, x, top)
        _lights(lights, cells, rng, lit_p, x, top, haze)
        x += int(alpha.shape[1] * rng.uniform(0.55, 0.85))
    return plane, lights


def build_near(files, rng, variants=4):
    """Ближний план: верхушки домов вдоль нижнего края, почти чёрные."""
    plane = np.zeros((H, W, 4), float)
    lights = [np.zeros((H, W, 4), float) for _ in range(variants)]
    order = list(files)
    rng.shuffle(order)
    x, i = -int(rng.integers(10, 60)), 0
    while x < W + 20:
        path = order[i % len(order)]
        got = _prepare(path, rng, plan_height(path, NEAR["floor"], rng), 0.5)
        i += 1
        if got is None:
            continue
        rgb, alpha, zone = got
        k = int(rng.integers(*NEAR["crop"]))         # оставляем только верхушку
        rgb, alpha = rgb[:k], alpha[:k]
        zone = None if zone is None else zone[:k]
        rgb, cells = draw_windows(rgb, alpha, rng, *NEAR["step"], NEAR["win"], zone)
        rgb = rgb * NEAR["darken"]
        top = int(rng.integers(*NEAR["top"]))
        tail = H - (top + alpha.shape[0])          # дом уходит под обрез кадра
        if tail > 0:
            rgb = np.concatenate([rgb, np.repeat(rgb[-1:], tail, axis=0)])
            alpha = np.concatenate([alpha, np.repeat(alpha[-1:], tail, axis=0)])
        _blit(plane, rgb, alpha, x, top)
        _lights(lights, cells, rng, 0.07, x, top, mul=NEAR["darken"])
        x += int(alpha.shape[1] * rng.uniform(0.5, 0.8))
    return plane, lights


# ---------------------------------------------------------------- небо и облака

def sky_rows():
    ys = np.linspace(0, 1, H)
    s = np.zeros((H, 3))
    for c in range(3):
        s[:, c] = np.interp(ys, [p[0] for p in SKY_STOPS], [p[1][c] for p in SKY_STOPS])
    return s


def build_sky(rng, stars=240):
    img = np.repeat(sky_rows()[:, None, :], W, axis=1)
    for _ in range(stars):
        x = int(rng.integers(0, W))
        y = int(abs(rng.normal(0, 0.38)) * H * 0.7) % H
        img[y, x] = np.maximum(img[y, x], np.array([255, 252, 240]) * rng.uniform(0.5, 1))
    return img


def value_noise(gx, gy, rng):
    """Шум на решётке. По горизонтали замыкается сам на себя — слой можно крутить бесконечно."""
    grid = rng.random((gy + 1, gx))
    xs, ys = np.arange(W) * gx / W, np.arange(H) * gy / H
    x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
    fx, fy = xs - x0, ys - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    x1, x0 = (x0 + 1) % gx, x0 % gx
    a = grid[y0][:, x0] * (1 - fx) + grid[y0][:, x1] * fx
    b = grid[y0 + 1][:, x0] * (1 - fx) + grid[y0 + 1][:, x1] * fx
    return a * (1 - fy[:, None]) + b * fy[:, None]


def build_clouds(seed, band_center=0.40, band_width=0.11, cover=0.26, dither=0.055):
    """Цвет облака — смесь неба на этой высоте с подсветкой, края размыты дизерингом.

    Это работает потому, что небо — градиент по вертикали, а облака едут по горизонтали:
    замешанный для строки цвет остаётся верным при любом сдвиге.
    """
    rng = np.random.default_rng(seed)
    v = np.zeros((H, W))
    amp = 1.0
    for gx, gy in ((5, 13), (10, 26), (20, 52), (40, 104)):
        v += amp * value_noise(gx, gy, rng)
        amp *= 0.5
    v = (v - v.min()) / (v.max() - v.min())
    y = np.arange(H)[:, None] / H
    drift = value_noise(3, 1, np.random.default_rng(seed + 77))[0] * 0.09 - 0.045
    v = v * np.exp(-((y - (band_center + drift[None, :])) ** 2) / (2 * band_width ** 2))

    noise = np.tile(BAYER4, (H // 4 + 1, W // 4 + 1))[:H, :W] * dither
    sky = sky_rows()
    out = np.zeros((H, W, 4), float)
    qs = np.quantile(v, [1 - cover, 1 - cover * 0.68, 1 - cover * 0.42,
                         1 - cover * 0.22, 1 - cover * 0.08])
    for t, k in zip(qs, (0.14, 0.26, 0.40, 0.56, 0.74)):
        m = (v + noise) >= t
        col = sky[:, None, :] * (1 - k) + CLOUD_TINT[None, None, :] * k
        out[m, :3] = np.broadcast_to(col, (H, W, 3))[m]
        out[m, 3] = 1.0
    return out


# ---------------------------------------------------------------- сборка

def save(path, arr, opaque=False):
    a = arr.copy()
    if opaque:
        a = np.dstack([a, np.ones((H, W))])
    a[..., 3] *= 255.0          # альфа внутри лежит в 0..1, в файл нужна 0..255
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(path)


def main():
    ap = argparse.ArgumentParser(description="Сборка слоёв фона меню")
    ap.add_argument("--seed", type=int, default=21)
    ap.add_argument("--name", default="bg_menu")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--preview", action="store_true", help="сохранить склейку всех слоёв")
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(SRC, "*.png")))
    if not files:
        raise SystemExit("нет зданий в %s" % SRC)
    os.makedirs(args.out, exist_ok=True)
    rng = np.random.default_rng(args.seed)

    far, far_lights = build_plane(files, rng, *PLANES["far"], variants=VARIANTS)
    mid, mid_lights = build_plane(files, rng, *PLANES["mid"], variants=VARIANTS)
    near, near_lights = build_near(files, rng, variants=VARIANTS)
    layers = {"sky": build_sky(rng), "clouds": build_clouds(args.seed),
              "far": far, "mid": mid, "near": near}
    lights = {"far": far_lights, "mid": mid_lights, "near": near_lights}

    for key, arr in layers.items():
        save(os.path.join(args.out, "%s_%s.png" % (args.name, key)), arr, opaque=(key == "sky"))
    for key, group in lights.items():
        for v, arr in enumerate(group, 1):
            save(os.path.join(args.out, "%s_%s_lights%d.png" % (args.name, key, v)), arr)

    print("зданий: %d, сид: %d, вариантов свечения: %d -> %s"
          % (len(files), args.seed, VARIANTS, args.out))

    if args.preview:
        canvas = layers["sky"].copy()
        for key in ("clouds", "far", "mid", "near"):
            for arr in (layers[key], lights.get(key, [None])[0]):
                if arr is None:
                    continue
                a = arr[..., 3:4]
                canvas = canvas * (1 - a) + arr[..., :3] * a
        im = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8))
        im.resize((W * 3, H * 3), Image.NEAREST).save(
            os.path.join(args.out, "%s_preview_x3.png" % args.name))


if __name__ == "__main__":
    main()
