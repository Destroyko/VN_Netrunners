"""Рендер камер из готовой .blend-сцены.

`apartment.py` собирает сцену из коробок с нуля. Но когда коробки заменены на
детальные прокси руками (или скриптом внутри Blender), истина уже в файле, а не
в коде — пересборка стёрла бы эту работу. Этот скрипт ничего не строит: он открывает
готовую сцену и рендерит из неё кадры тем же способом, что и блокаут, включая карту
глубины для ControlNet.

    & "...\\blender.exe" -b assets\\_source\\blockout\\apartment_detail.blend ^
        --python tools\\blockout\\render_blend.py -- --render room_desk --depth

Имена файлов: `blk_<камера>_flat.png`, `blk_<камера>_depth.png`. Карта глубины осталась
от конвейера с ControlNet, который для фонов отменён (`docs/art/blender-scenes.md`);
для обычного рендера она не нужна, но и не мешает.
"""

import os
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bl_common as B  # noqa: E402


def extra(p):
    p.add_argument("--cam", default="",
                   help="подвинуть камеру только на этот рендер: "
                        "имя:x,y,z[:цель_x,цель_y,цель_z] — сцена не меняется")
    p.add_argument("--lens", type=float, default=0.0,
                   help="фокусное для той же камеры, 0 — оставить как есть")


def move_camera(spec, lens):
    """Подбор ракурса без правки .blend: сцена остаётся за разработчиком."""
    import mathutils
    parts = spec.split(":")
    name = parts[0]
    ob = bpy.data.objects.get(name)
    if ob is None or ob.type != "CAMERA":
        raise SystemExit("нет камеры %s" % name)
    if len(parts) > 1 and parts[1]:
        ob.location = tuple(float(v) for v in parts[1].split(","))
    if len(parts) > 2 and parts[2]:
        tgt = mathutils.Vector(tuple(float(v) for v in parts[2].split(",")))
        ob.rotation_euler = (tgt - ob.location).to_track_quat("-Z", "Y").to_euler()
    if lens:
        ob.data.lens = lens
    print("[blockout] камера %s: %s, %.0f мм"
          % (name, tuple(round(v, 2) for v in ob.location), ob.data.lens))


def main():
    a = B.args(extra)
    if a.cam:
        move_camera(a.cam, a.lens)
    sc = bpy.context.scene
    # Размер кадра и движок задаём сами: в чужой сцене они могут быть любыми
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = B.RES
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"

    cams = {o.name: o for o in bpy.data.objects if o.type == "CAMERA"}
    if not cams:
        raise SystemExit("в сцене нет камер")
    if not a.render:
        print("[blockout] камеры сцены: " + ", ".join(sorted(cams)))
        return

    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                        "assets", "_source", "blockout", "renders")
    out = B.resolve(a.out) if a.out else os.path.normpath(root)

    if a.depth:
        near, far = (float(v) for v in a.depth_range.split(","))
        B.depth_setup(near, far)
        suffix = "_depth"
    else:
        suffix = "_flat" if a.shade == "flat" else "_lit_%s" % a.phase
        if a.shade == "lit":
            B.light(a.phase, a.shade)

    files = B.render(cams, out, suffix, a.render)
    print("[blockout] отрендерено: %d" % len(files))


main()
