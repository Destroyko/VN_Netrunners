"""Обои на палитре: цвет и свет наши, узор остаётся.

Скачанные обои, как и вся мебель, должны жить по общим правилам света (ступени, ночная
тень, цвет света). Но монолитная картинка сливается с соседними такими же. Скрипт берёт
у обоев **только узор** (яркость картинки цвета) и кладёт его на материал палитры:
цвет выбирается из палитры, узор лишь светлит и темнит тот же тон.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_work_palette_light.blend ^
        --python tools\\blockout\\pattern_wallpaper.py -- --color blue_dark --strength 0.18

Для каждого материала с `wallpaper` в имени, который где-то используется:
- картинка узора — та, что идёт в Base Color исходного материала;
- цвет палитры — заданный `--color` или ближайший к среднему цвету картинки (OKLab);
- результат — материал `pal_wall_<цвет>_ornament`, он заменяет исходный на всех объектах.
  Исходный остаётся без пользователей, пока его не удалят чисткой.
`--strength` — на сколько узор светлит и темнит тон (0,18 — плюс-минус 18 %), `--only` —
подстрока имени исходного материала, `--dry` — только показать. Файл сохраняется.
"""

import os
import sys

import bpy
import numpy as np

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402


def base_image(mat):
    """Картинка, которая идёт в Base Color: узор обоев."""
    for n in mat.node_tree.nodes:
        if n.type != "BSDF_PRINCIPLED":
            continue
        stack = [lk.from_node for lk in n.inputs["Base Color"].links]
        while stack:
            node = stack.pop()
            if node.type == "TEX_IMAGE" and node.image is not None:
                return node.image
            for sock in node.inputs:
                stack.extend(lk.from_node for lk in sock.links)
    return None


def stats(img):
    """Средний цвет (линейный) и границы яркости: 2 и 98 процентили."""
    w, h = img.size
    step = max(1, int(max(w, h) // 256))
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, img.channels)[::step, ::step, :3]
    if img.colorspace_settings.name == "sRGB":
        # pixels отдаёт значения как записаны, а узел яркости считает линейный цвет
        px = np.where(px <= 0.04045, px / 12.92, ((px + 0.055) / 1.055) ** 2.4)
    lum = px[..., 0] * 0.2126 + px[..., 1] * 0.7152 + px[..., 2] * 0.0722
    return px.reshape(-1, 3).mean(axis=0), float(np.percentile(lum, 2)), float(np.percentile(lum, 98))


def to_oklab(lin):
    m1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                   [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]])
    m2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                   [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]])
    return m2 @ np.cbrt(m1 @ np.asarray(lin, dtype=np.float64))


def nearest_color(lin):
    best, best_d = None, 1e9
    for name, hexcol in P.COLORS.items():
        if "wall" not in P.kinds_for(name):
            continue
        d = np.linalg.norm(to_oklab(lin) - to_oklab(P.srgb(hexcol)))
        if d < best_d:
            best, best_d = name, d
    return best


def make_material(src, color, strength):
    img = base_image(src)
    mean, lo, hi = stats(img)
    color = color or nearest_color(mean)
    base = "%s_ornament" % P.mat_name("wall", color)
    name, n, mat = base, 1, None
    # у каждой картинки узора свой материал: одинаковый цвет у двух обоев не склеивает узоры
    while bpy.data.materials.get(name) is not None:
        old = bpy.data.materials[name]
        if any(x.type == "TEX_IMAGE" and x.image == img for x in old.node_tree.nodes):
            mat = old
            break
        n += 1
        name = "%s%d" % (base, n)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    # материал пересобирается всегда: после правки шейдера повторный запуск обновляет и его
    pat = {"image": img, "strength": strength, "lo": lo, "hi": hi}
    light = C.build(mat.node_tree, P.srgb(P.COLORS[color]), texture=0.0, kind="wall", pattern=pat)
    C.surface(mat, "wall")
    mat.diffuse_color = (*light, 1.0)
    return mat, color, img.name


def rebuild_existing(strength):
    """Пересобрать готовые материалы с узором: после правки шейдера их картинка и цвет уже
    известны из самого материала, исходные обои для этого не нужны."""
    n = 0
    for mat in bpy.data.materials:
        if not mat.name.startswith("pal_wall_") or "_ornament" not in mat.name or not mat.use_nodes:
            continue
        img = next((x.image for x in mat.node_tree.nodes if x.type == "TEX_IMAGE" and x.image), None)
        if img is None:
            continue
        color = mat.name[len("pal_wall_"):mat.name.index("_ornament")]
        if color not in P.COLORS:
            continue
        _, lo, hi = stats(img)
        pat = {"image": img, "strength": strength, "lo": lo, "hi": hi}
        light = C.build(mat.node_tree, P.srgb(P.COLORS[color]), texture=0.0, kind="wall", pattern=pat)
        C.surface(mat, "wall")
        mat.diffuse_color = (*light, 1.0)
        n += 1
    return n


def main():
    dry = "--dry" in sys.argv
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    argv = [a for a in argv if a != "--dry"]
    opts = dict(zip(argv[::2], argv[1::2]))
    color = opts.get("--color")
    strength = float(opts.get("--strength", 0.18))
    only = opts.get("--only", "wallpaper").lower()

    if not dry:
        print("[pattern] пересобрано готовых: %d" % rebuild_existing(strength))
    done = 0
    for src in list(bpy.data.materials):
        if only not in src.name.lower() or not src.use_nodes or src.name.endswith("_ornament"):
            continue
        slots = [(ob, i) for ob in bpy.data.objects for i, sl in enumerate(ob.material_slots)
                 if sl.material == src]
        if not slots or base_image(src) is None:
            continue
        mat, col, imgname = make_material(src, color, strength)
        print("[pattern] %s: картинка %s -> %s, слотов %d" % (src.name, imgname, mat.name, len(slots)))
        if not dry:
            for ob, i in slots:
                ob.material_slots[i].material = mat
        done += 1
    print("[pattern] материалов: %d%s" % (done, " (пробный прогон)" if dry else ""))
    if not dry:
        bpy.ops.wm.save_mainfile()


main()
