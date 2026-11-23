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
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402
import matte_wallpaper as W  # noqa: E402

# Расчётные камеры: положение, цель, фокусное. Комната по x 0–3,3 и y 4,5–7,3, окно в стене y≈7,3
CAMERAS = {
    "main": {"loc": (1.6, 4.6, 1.45), "target": (1.6, 7.0, 1.0), "lens": 20.0},
    "pc":   {"loc": (1.3, 5.9, 1.40), "target": (2.2, 6.95, 0.90), "lens": 32.0},
}

# Окно: центр и размер светящегося прямоугольника снаружи стены
WINDOW = {"centre": (1.96, 7.95, 1.65), "size": (1.6, 2.0)}
# Монитор: экран смотрит на -y, лампа монитора стоит перед ним
MONITOR = {"centre": (1.87, 6.75, 0.98), "size": (0.5, 0.28)}

# Фазы суток. sky — цвет и сила мира; window — свет из окна; lamp — торшер (мощность, цвет,
# радиус действия); monitor — свет монитора, едва заметный; fill — подсветка потолка.
# floor и tint — отклик материалов на свет (cel_shader.light_group): до какой доли тон гаснет
# без света и насколько цвет света окрашивает поверхность
PHASES = {
    "day":     {"sky": ((0.62, 0.72, 0.90), 1.0), "window": ((1.00, 0.97, 0.92), 260.0),
                "lamp": 0.0, "lamp_color": (1.0, 0.5, 0.12), "lamp_reach": 1.2,
                "monitor": 0.0, "fill": 70.0, "floor": 1.0, "tint": 0.0,
                "shadow": 0.0, "night": (0.5, 0.6, 1.0)},
    "evening": {"sky": ((0.80, 0.45, 0.35), 0.15), "window": ((1.00, 0.55, 0.30), 380.0),
                "lamp": 12.0, "lamp_color": (1.0, 0.42, 0.10), "lamp_reach": 1.2,
                "monitor": 3.0, "fill": 8.0, "floor": 0.55, "tint": 0.6,
                "shadow": 0.35, "night": (0.55, 0.5, 0.95)},
    "night":   {"sky": ((0.05, 0.08, 0.20), 0.05), "window": ((0.25, 0.40, 1.00), 22.0),
                "lamp": 9.0, "lamp_color": (1.0, 0.38, 0.08), "lamp_reach": 1.2,
                "monitor": 1.5, "fill": 0.0, "floor": 0.26, "tint": 0.85,
                "shadow": 0.6, "night": (0.22, 0.40, 1.0)},
}


def extra(p):
    p.add_argument("--res", default="1280,720", help="размер кадра: ширина,высота")
    p.add_argument("--samples", type=int, default=64)


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


def shade_glow(on):
    """Абажур торшера светится, когда лампа включена: без этого свет ниоткуда не берётся."""
    ob = bpy.data.objects.get("FloorLamp_Cover")
    if ob is None or not ob.material_slots:
        return
    if "_shade_off" not in ob:
        ob["_shade_off"] = ob.material_slots[0].material.name if ob.material_slots[0].material else ""
    if on:
        name = "rf_shade_glow"
        mat = bpy.data.materials.get(name)
        if mat is None:
            mat = bpy.data.materials.new(name)
            mat.use_nodes = True
            # цвет задан прямо, а не из палитры: светлый оранжевый палитры при свечении
            # выгорает в жёлтый, а абажуру нужен тёплый оранжевый
            C.build(mat.node_tree, (1.0, 0.36, 0.08), kind="glow")
            for n in mat.node_tree.nodes:
                if n.type == "EMISSION":
                    n.inputs["Strength"].default_value = 0.9
        ob.material_slots[0].material = mat
        # абажур не должен закрывать собственный свет: тень от него гасила бы всю комнату
        ob.visible_shadow = False
    else:
        ob.visible_shadow = True
        orig = bpy.data.materials.get(ob["_shade_off"])
        if orig is not None:
            ob.material_slots[0].material = orig


def clear():
    """Убрать всё, что скрипт добавил в сцену: источники и расчётные камеры, абажур вернуть."""
    for ob in list(bpy.data.objects):
        if ob.name.startswith("rf_"):
            data = ob.data
            bpy.data.objects.remove(ob)
            if data is not None and data.users == 0:
                (bpy.data.lights if ob_is_light(data) else bpy.data.cameras).remove(data)
    lamp = bpy.data.objects.get("FloorLamp_Light")
    if lamp is not None:
        lamp.hide_render = False
    shade_glow(False)
    C.set_light_response(1.0, 0.0, 0.0)


def ob_is_light(data):
    return isinstance(data, bpy.types.Light)


def build_light(phase):
    sc = bpy.context.scene
    clear()
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
        lamp.data.color = ph["lamp_color"]
        lamp.data.shadow_soft_size = 0.2
        lamp.data.specular_factor = 0.0
        # Свет лампы живёт в радиусе метров: в cel-ступенях любой слабый источник
        # даёт резкое пятно через всю комнату, поэтому его обрезаем по расстоянию
        lamp.data.use_custom_distance = False       # жёсткий радиус рисует круг: затухание естественное
        lamp.hide_render = ph["lamp"] <= 0.0
        shade_glow(ph["lamp"] > 0.0)

    C.set_light_response(ph["floor"], ph["tint"], ph["shadow"], ph["night"])
    W.apply()

    wcol, wpow = ph["window"]
    area("rf_window", WINDOW["centre"], WINDOW["size"], wcol, wpow, (0.0, -1.0, 0.0))
    if ph["monitor"] > 0.0:
        mon = area("rf_monitor", MONITOR["centre"], MONITOR["size"], (0.55, 0.72, 1.0),
                   ph["monitor"], (0.0, -1.0, -0.15), spread=70.0, specular=0.0)
        mon.data.use_custom_distance = True
        mon.data.cutoff_distance = 0.9
    # слабая подсветка сверху: без неё углы уходят в чёрное и теряют форму
    area("rf_fill", (1.7, 5.9, 2.55), (2.4, 2.4), (1.0, 0.95, 0.9), ph["fill"], (0.0, 0.0, -1.0))


def setup(phase, samples=64):
    """Настройки рендера и свет фазы. Одинаково для командной строки и окна Blender."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.eevee.taa_render_samples = samples
    B.flat_color(sc)
    # Тени: при малом числе лучей слабо освещённые поверхности зернят (чёрный пластик
    # выглядит дырявым), поэтому лучей и шагов больше, чем по умолчанию
    sc.eevee.shadow_ray_count = 8
    sc.eevee.shadow_step_count = 24
    sc.eevee.shadow_resolution_scale = 2.0
    build_light("day" if phase == "morning" else phase)


def gui(phase="night", view="main"):
    """Показать свет в окне Blender (скрипт для вкладки Scripting: room_light_gui.py).

    phase: day, evening, night или off (убрать всё, что добавил скрипт).
    view: main или pc — смотреть через расчётную камеру; none — вид не трогать.
    Окна 3D переключаются в режим Rendered. Сцену с включённым светом лучше не сохранять:
    источники rf_* останутся в файле (убираются запуском с phase=off).
    """
    if phase == "off":
        clear()
        for area in bpy.context.screen.areas:
            if area.type == "VIEW_3D":
                for sp in area.spaces:
                    if sp.type == "VIEW_3D":
                        sp.shading.type = "MATERIAL"
        return
    setup(phase, samples=32)
    if view != "none":
        bpy.context.scene.camera = make_camera(view)
    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            for sp in area.spaces:
                if sp.type == "VIEW_3D":
                    sp.shading.type = "RENDERED"
                    if view != "none":
                        sp.region_3d.view_perspective = "CAMERA"


def main():
    a = B.args(extra)
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = (int(v) for v in a.res.split(","))
    setup(a.phase, a.samples)

    wanted = [s.strip() for s in (a.render or "main,pc").split(",") if s.strip()]
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    out = a.out if os.path.isabs(a.out) else os.path.join(root, a.out) if a.out else         os.path.join(root, "assets", "_source", "blockout", "renders", "room_frames")
    os.makedirs(out, exist_ok=True)
    for name in wanted:
        sc.camera = make_camera(name)
        path = os.path.join(out, "room_%s_%s.png" % (name, a.phase))
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("[room] %s" % path)


if __name__ == "__main__":
    main()
