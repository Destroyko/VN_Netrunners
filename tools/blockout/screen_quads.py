"""Где в кадре находится экран монитора — четырьмя углами.

Монитор нельзя оставлять частью фона. Если компьютер включён, экран должен светиться
и показывать хоть что-то, пока герой стоит в комнате, — а фон статичен. Значит
содержимое экрана кладётся отдельным слоем поверх фона.

Чтобы положить его точно, игре нужны координаты четырёхугольника, в который экран
попал в этом кадре. Скрипт берёт плоскость экрана в сцене, проецирует её углы
камерой и пишет их в долях кадра (0..1, начало — левый верхний угол, как в Godot).

Помечаются объекты с именем на `screen_` либо из коллекции `screens`.

    & "...blender.exe" -b сцена.blend --python tools\\blockout\\screen_quads.py -- ^
        --render room_desk

Рядом с JSON ничего не рендерится: это только геометрия. Контент на экран игра
натягивает сама — хоть рабочий стол, хоть заставку.
"""

import json
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bl_common as B  # noqa: E402

MARK_COLLECTION = "screens"
MARK_PREFIX = "screen_"


def targets():
    col = bpy.data.collections.get(MARK_COLLECTION)
    out = list(col.all_objects) if col else []
    for ob in bpy.data.objects:
        if ob.name.startswith(MARK_PREFIX) and ob not in out:
            out.append(ob)
    return [o for o in out if o.type == "MESH"]


def quad(scene, cam, ob):
    """Четыре угла экрана в долях кадра, по часовой от левого верхнего.

    Берём габариты объекта и его переднюю грань: у плоскости экрана это те четыре
    точки, которые видит камера.
    """
    import mathutils
    pts = [ob.matrix_world @ mathutils.Vector(c) for c in ob.bound_box]
    flat = []
    for p in pts:
        co = world_to_camera_view(scene, cam, p)
        # у Blender начало внизу слева, у Godot — вверху слева
        flat.append((round(co.x, 4), round(1.0 - co.y, 4), round(co.z, 4)))
    # ближние к камере восемь точек схлопываем в четыре крайние
    xs = sorted(f[0] for f in flat)
    ys = sorted(f[1] for f in flat)
    x0, x1 = xs[0], xs[-1]
    y0, y1 = ys[0], ys[-1]
    return {"corners": [[x0, y0], [x1, y0], [x1, y1], [x0, y1]],
            "depth": round(sum(f[2] for f in flat) / len(flat), 3)}


def main():
    a = B.args()
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = B.RES
    scr = targets()
    if not scr:
        raise SystemExit("нет экранов: коллекция '%s' или имена на '%s'"
                         % (MARK_COLLECTION, MARK_PREFIX))

    cams = {o.name: o for o in bpy.data.objects if o.type == "CAMERA"}
    wanted = (list(cams) if a.render == "all"
              else [s.strip() for s in a.render.split(",") if s.strip()])
    if not wanted:
        raise SystemExit("укажите камеру: --render room_desk")

    out_dir = B.resolve(a.out) if a.out else B.resolve("assets/_source/blockout/screens")
    os.makedirs(out_dir, exist_ok=True)

    for name in wanted:
        cam = cams.get(name)
        if cam is None:
            raise SystemExit("нет камеры %s" % name)
        scene.camera = cam
        data = {}
        for ob in scr:
            key = (ob.name[len(MARK_PREFIX):] if ob.name.startswith(MARK_PREFIX)
                   else ob.name)
            q = quad(scene, cam, ob)
            inside = all(0.0 <= c[0] <= 1.0 and 0.0 <= c[1] <= 1.0 for c in q["corners"])
            q["fully_visible"] = inside
            data[key] = q
        path = os.path.join(out_dir, "screens_%s.json" % name)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=1)
        print("[screens] %s: %s" % (name, ", ".join(sorted(data))))
        print("          -> %s" % path)


main()
