"""Переход между двумя кадрами: последовательность картинок.

Для проверки, во что обходится движение камеры в игре. Рендерит N кадров между
двумя положениями камеры — поворот взгляда, приближение к столу, отход назад.
Результат складывается в папку и годится для AnimatedSprite в Godot.

    & "...blender.exe" -b сцена.blend --python tools\\blockout\\render_move.py -- ^
        --cam room_desk --to "1.42,5.2,1.35:1.42,7.4,1.05" --frames 12

`--to` — куда приехать: позиция и (через двоеточие) цель. Старт берётся у камеры
как она стоит. Движение идёт по сглаженной кривой, а не линейно: резкий старт
и остановка читаются как рывок.
"""

import math
import os
import sys

import bpy
import mathutils

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bl_common as B  # noqa: E402


def ease(t):
    """Плавный разгон и торможение (косинусная дуга)."""
    return 0.5 - 0.5 * math.cos(math.pi * t)


def main():
    def extra(p):
        p.add_argument("--cam", required=True, help="имя камеры, с которой начинаем")
        p.add_argument("--to", required=True,
                       help="x,y,z[:цель_x,цель_y,цель_z] — конечное положение")
        p.add_argument("--frames", type=int, default=12, help="сколько кадров в переходе")
        p.add_argument("--lens-to", type=float, default=0.0,
                       help="фокусное в конце, 0 — не менять")

    a = B.args(extra)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = B.RES
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    B.flat_color(sc)

    cam = bpy.data.objects.get(a.cam)
    if cam is None or cam.type != "CAMERA":
        raise SystemExit("нет камеры %s" % a.cam)

    parts = a.to.split(":")
    loc_b = mathutils.Vector(tuple(float(v) for v in parts[0].split(",")))
    loc_a = cam.location.copy()
    rot_a = cam.rotation_euler.copy()
    lens_a = cam.data.lens
    lens_b = a.lens_to or lens_a

    rot_b = rot_a
    if len(parts) > 1:
        tgt = mathutils.Vector(tuple(float(v) for v in parts[1].split(",")))
        rot_b = (tgt - loc_b).to_track_quat("-Z", "Y").to_euler()

    out = B.resolve(a.out) if a.out else B.resolve("assets/_source/blockout/move")
    os.makedirs(out, exist_ok=True)
    qa = rot_a.to_quaternion()
    qb = rot_b.to_quaternion()

    for i in range(a.frames):
        t = ease(i / max(1, a.frames - 1))
        cam.location = loc_a.lerp(loc_b, t)
        # поворот — через кватернионы: по углам Эйлера камеру закручивает
        cam.rotation_euler = qa.slerp(qb, t).to_euler()
        cam.data.lens = lens_a + (lens_b - lens_a) * t
        sc.camera = cam
        sc.render.filepath = os.path.join(out, "mv_%s_%03d.png" % (a.cam, i))
        bpy.ops.render.render(write_still=True)

    print("[move] кадров: %d -> %s" % (a.frames, out))


main()
