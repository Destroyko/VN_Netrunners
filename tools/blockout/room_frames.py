"""Два кадра комнаты героя со светом: общий вид и вид на ПК.

Работает поверх рабочей сцены и ничего в ней не сохраняет: камеры и свет создаются на
время рендера, файл остаётся за разработчиком. Свои камеры можно положить в сцену под
именами `room_main` и `room_pc` — тогда скрипт возьмёт их, а не расчётные.

    & "...\\blender.exe" -b assets\\_source\\blockout\\apartment_work_palette.blend ^
        --python tools\\blockout\\room_frames.py -- --phase evening --render main,pc

Кадры:
- main — кровать, стол, шкаф, настенная полка и календарь в одном кадре, чтобы не крутиться
  по комнате в поисках предмета;
- pc — системный блок и стол: сюда вставляется флешка.

Свет собирается из трёх источников, как в настоящей комнате: окно (небо), лампа и монитор.
Силы и цвета по фазам суток — таблица PHASES ниже; подбор идёт по рендеру глазами.
Файлы: <папка>/room_<кадр>_<фаза>.png.
"""

import math
import os
import sys

import bpy
import mathutils

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bl_common as B  # noqa: E402

# Расчётные камеры: положение, цель, фокусное. Комната по x 0–3,3 и y 4,5–7,3, окно в стене y≈7,3
CAMERAS = {
    "main": {"loc": (1.6, 4.6, 1.45), "target": (1.6, 7.0, 1.0), "lens": 20.0},
    "pc":   {"loc": (1.3, 5.9, 1.40), "target": (2.2, 6.95, 0.90), "lens": 32.0},
}

# Окно: центр и размер светящегося прямоугольника снаружи стены
WINDOW = {"centre": (1.96, 7.95, 1.65), "size": (1.6, 2.0)}
# Монитор: экран смотрит на -y, лампа монитора стоит перед ним
MONITOR = {"centre": (1.87, 6.75, 0.98), "size": (0.5, 0.28)}

# Фазы суток. sky — цвет и сила мира; window — цвет и мощность окна; lamp — мощность лампы
# и точки (0 — выключена); monitor — мощность света монитора; fill — слабая подсветка потолка
PHASES = {
    "day":     {"sky": ((0.62, 0.72, 0.90), 1.0), "window": ((1.00, 0.97, 0.92), 260.0),
                "lamp": 0.0, "monitor": 0.0, "fill": 70.0},
    "evening": {"sky": ((0.95, 0.50, 0.32), 0.50), "window": ((1.00, 0.55, 0.30), 750.0),
                "lamp": 80.0, "monitor": 18.0, "fill": 25.0},
    "night":   {"sky": ((0.10, 0.14, 0.30), 0.15), "window": ((0.45, 0.55, 1.00), 120.0),
                "lamp": 80.0, "monitor": 30.0, "fill": 12.0},
}


def extra(p):
    p.add_argument("--res", default="1280,720", help="размер кадра: ширина,высота")
    p.add_argument("--samples", type=int, default=48)


def make_camera(name):
    """Своя камера frame_<кадр> из сцены или расчётная."""
    own = bpy.data.objects.get("frame_" + name)
    if own is not None and own.type == "CAMERA":
        return own
    spec = CAMERAS[name]
    cd = bpy.data.cameras.new("rf_" + name)
    cd.lens = spec["lens"]
    cd.clip_start = 0.05
    ob = bpy.data.objects.new("rf_" + name, cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = spec["loc"]
    tgt = mathutils.Vector(spec["target"])
    ob.rotation_euler = (tgt - ob.location).to_track_quat("-Z", "Y").to_euler()
    return ob


def area(name, centre, size, color, power, facing, spread=180.0, specular=1.0):
    """Прямоугольный источник. facing — куда светит: единичный вектор."""
    la = bpy.data.lights.new(name, "AREA")
    la.shape = "RECTANGLE"
    la.size, la.size_y = size
    la.color = color
    la.energy = power
    la.spread = math.radians(spread)
    # Блик от света в cel-материале — ступенчатое пятно: у близких ламп он выглядит
    # как луч прожектора на мебели, поэтому у них блик убавляем
    la.specular_factor = specular
    ob = bpy.data.objects.new(name, la)
    ob.location = centre
    ob.rotation_euler = mathutils.Vector(facing).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build_light(phase):
    sc = bpy.context.scene
    ph = PHASES[phase]
    w = sc.world or bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    color, strength = ph["sky"]
    bg.inputs["Color"].default_value = (*color, 1.0)
    bg.inputs["Strength"].default_value = strength

    # Прежние лампы сцены гасим: свет собираем заново и считаем сами
    for o in bpy.data.objects:
        if o.type == "LIGHT" and o.name != "FloorLamp_Light":
            o.hide_render = True
    lamp = bpy.data.objects.get("FloorLamp_Light")
    if lamp is not None:
        lamp.data.energy = ph["lamp"]
        lamp.data.shadow_soft_size = 0.2
        lamp.data.specular_factor = 0.0
        # Свет лампы живёт в радиусе метров: в cel-ступенях любой слабый свет даёт
        # резкое пятно через всю комнату, поэтому его обрезаем по расстоянию
        lamp.data.use_custom_distance = True
        lamp.data.cutoff_distance = 1.7
        lamp.hide_render = ph["lamp"] <= 0.0

    wcol, wpow = ph["window"]
    area("rf_window", WINDOW["centre"], WINDOW["size"], wcol, wpow, (0.0, -1.0, 0.0))
    if ph["monitor"] > 0.0:
        area("rf_monitor", MONITOR["centre"], MONITOR["size"], (0.55, 0.72, 1.0),
             ph["monitor"], (0.0, -1.0, -0.15), spread=70.0, specular=0.0)
    # слабая подсветка сверху: без неё углы уходят в чёрное и теряют форму
    area("rf_fill", (1.7, 5.9, 2.55), (2.4, 2.4), (1.0, 0.95, 0.9), ph["fill"], (0.0, 0.0, -1.0))


def main():
    a = B.args(extra)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = (int(v) for v in a.res.split(","))
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.eevee.taa_render_samples = a.samples
    B.flat_color(sc)
    build_light("day" if a.phase == "morning" else a.phase)

    wanted = [s.strip() for s in (a.render or "main,pc").split(",") if s.strip()]
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    out = a.out if os.path.isabs(a.out) else os.path.join(root, a.out) if a.out else \
        os.path.join(root, "assets", "_source", "blockout", "renders", "room_frames")
    os.makedirs(out, exist_ok=True)
    for name in wanted:
        sc.camera = make_camera(name)
        path = os.path.join(out, "room_%s_%s.png" % (name, a.phase))
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("[room] %s" % path)


main()
