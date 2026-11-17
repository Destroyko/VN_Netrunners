# Общие кирпичи для блокаутов в Blender (docs/art/ai-pipeline.md, раздел 5.7).
# Только коробки: моделировать всерьёз нельзя, иначе этап съест время генератора.
#
# Запуск: blender --background --python tools/blockout/<сцена>.py -- <аргументы>
# Без --background сцена строится и остаётся открытой в редакторе.

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

# Рендерим в разрешении генерации: 1280x720 делится нацело и на 640x360, и на 320x180
# (правило целого деления, раздел 4.1). Дробное деление даёт полосы.
RES = (1280, 720)

# Цвета плоскостей. Главное требование раздела 5.6 — у каждой плоскости свой тон,
# иначе модель не понимает, где стена кончается и начинается пол.
PALETTE = {
    # Тона разведены сильно: в плоском режиме нет ни теней, ни текстуры, и соседние
    # плоскости близкого тона генератор склеивает в одну (раздел 5.6).
    "floor":    (0.13, 0.14, 0.15),   # тёмно-серый пол (схема разработчика 17.11.2026)
    "ceiling":  (0.42, 0.45, 0.54),
    "wall":     (0.25, 0.31, 0.45),   # комната синяя с тёмным оттенком
    "wall_in":  (0.21, 0.26, 0.39),   # внутренние перегородки темнее несущих
    # Стены вдоль Y ещё темнее: это второй разворот к свету, и без разницы в тоне
    # не видно, где дальняя стена переходит в боковую.
    "wall_y":   (0.17, 0.22, 0.33),
    "wall_in_y": (0.14, 0.18, 0.27),
    "window":   (0.99, 0.98, 0.92),   # источник света — самый светлый блок в кадре
    "door":     (0.38, 0.32, 0.27),
    "desk":     (0.20, 0.21, 0.24),
    "screen":   (0.38, 0.67, 0.47),   # экран светится, поэтому отдельным тоном
    "pc":       (0.07, 0.07, 0.09),   # корпус ПК чёрный: самый тёмный предмет в кадре
    "bed":      (0.74, 0.75, 0.78),   # кровать светлая: единственное светлое пятно внизу кадра
    "closet":   (0.32, 0.35, 0.43),
    "soft":     (0.33, 0.31, 0.40),   # диван, кресло
    "table":    (0.50, 0.40, 0.30),
    "counter":  (0.55, 0.56, 0.58),   # кухонный гарнитур, столешницы
    "appl":     (0.78, 0.79, 0.81),   # техника: холодильник, стиралка, плита
    "plumb":    (0.90, 0.92, 0.94),   # сантехника
    "shelf":    (0.28, 0.30, 0.36),
    "road":     (0.22, 0.22, 0.25),
    "pavement": (0.44, 0.44, 0.47),
    "green":    (0.27, 0.42, 0.26),
    "water":    (0.16, 0.26, 0.36),
    "bridge":   (0.34, 0.34, 0.38),
    "roof":     (0.30, 0.31, 0.35),
    "facade_a": (0.60, 0.58, 0.54),
    "facade_b": (0.52, 0.54, 0.58),
    "facade_c": (0.64, 0.60, 0.52),
    "accent":   (0.72, 0.42, 0.32),   # вывески и входы: куда игрок должен кликнуть
}

_mats = {}


def args(extra=None):
    """Аргументы после `--`: всё до него съедает сам Blender."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--shade", choices=["flat", "lit"], default="flat",
                   help="flat — плоские заливки на вход генератору (5.6); lit — со светом")
    p.add_argument("--phase", choices=["morning", "day", "evening", "night"], default="day",
                   help="фаза суток для --shade lit (раздел 7)")
    p.add_argument("--render", default="",
                   help="имена камер через запятую или all; пусто — только собрать сцену")
    p.add_argument("--out", default="", help="папка для рендеров")
    p.add_argument("--save", default="", help="куда сохранить .blend")
    if extra:
        extra(p)
    return p.parse_args(argv)


def reset():
    """Чистый лист: --factory-startup оставляет куб, камеру и лампу."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.eevee.taa_render_samples = 32
    sc.unit_settings.system = "METRIC"
    _mats.clear()


def mat(key, shade):
    """Материал по ключу палитры. В flat это Emission — цвет попадает в файл как есть."""
    name = f"{key}_{shade}"
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    col = (*PALETTE.get(key, (0.7, 0.7, 0.7)), 1.0)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    if shade == "flat":
        node = nt.nodes.new("ShaderNodeEmission")
        node.inputs["Color"].default_value = col
        node.inputs["Strength"].default_value = 1.0
    else:
        node = nt.nodes.new("ShaderNodeBsdfPrincipled")
        node.inputs["Base Color"].default_value = col
        node.inputs["Roughness"].default_value = 0.8
        if key == "screen":
            node.inputs["Emission Color"].default_value = col
            node.inputs["Emission Strength"].default_value = 2.0
        if key == "window":
            node.inputs["Emission Color"].default_value = col
            node.inputs["Emission Strength"].default_value = 1.5
    nt.links.new(node.outputs[0], out.inputs["Surface"])
    m.diffuse_color = col
    _mats[name] = m
    return m


def box(name, pos, size, key="wall", shade="flat", coll=None):
    """Коробка от угла: pos — минимальный угол (x, y, z), size — (w, d, h) в метрах.

    От угла, а не от центра: планировку в метрах так считать на порядок легче.
    """
    x, y, z = pos
    w, d, h = size
    verts = [(x, y, z), (x + w, y, z), (x + w, y + d, z), (x, y + d, z),
             (x, y, z + h), (x + w, y, z + h), (x + w, y + d, z + h), (x, y + d, z + h)]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
             (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat(key, shade))
    ob.color = (*PALETTE.get(key, (0.7, 0.7, 0.7)), 1.0)
    (coll or bpy.context.scene.collection).objects.link(ob)
    return ob


def slab(name, centre, size, angle=0.0, key="road", shade="flat", coll=None):
    """Плашка от центра, повёрнутая вокруг Z на angle градусов.

    Нужна для того, что не ложится на сетку: диагональный проспект, река, мосты.
    Город без таких линий выглядит как шахматная доска.
    """
    w, d, h = size
    ob = box(name, (-w / 2, -d / 2, 0.0), (w, d, h), key, shade, coll)
    ob.location = centre
    ob.rotation_euler = (0.0, 0.0, math.radians(angle))
    return ob


def side_of_axis(point, centre, angle):
    """Расстояние от точки до оси СО ЗНАКОМ: по разные стороны — разные знаки."""
    a = math.radians(angle)
    dx, dy = point[0] - centre[0], point[1] - centre[1]
    return -math.sin(a) * dx + math.cos(a) * dy


def dist_to_axis(point, centre, angle):
    """Расстояние от точки до оси, заданной центром и углом (градусы)."""
    return abs(side_of_axis(point, centre, angle))


def band_hits(rect, centre, angle, width, pad=0.0):
    """Пересекает ли прямоугольник (x0, y0, x1, y1) полосу вдоль оси.

    По углам со знаком, а не по расстоянию от центра: дом длиной в сто метров
    своим центром может быть далеко от реки, а углом стоять в воде.
    """
    x0, y0, x1, y1 = rect
    ds = [side_of_axis(p, centre, angle)
          for p in ((x0, y0), (x1, y0), (x0, y1), (x1, y1))]
    half = width / 2 + pad
    return min(ds) < half and max(ds) > -half


def wall(name, p1, p2, height, thick=0.12, key="wall", shade="flat",
         openings=(), coll=None, glaze=True, doors=True):
    """Стена между двумя точками в плане, с проёмами.

    Стены только осе-параллельные — для блокаута этого хватает, а код остаётся читаемым.
    Проём: (отступ от p1, ширина, низ, верх). Дверь — (x, 0.9, 0, 2.1),
    окно — (x, 1.4, 0.9, 2.2). Над проёмом остаётся перемычка, под окном — подоконная часть:
    без них стена разваливается на отдельные куски и в кадре это видно.
    """
    x1, y1 = p1
    x2, y2 = p2
    horiz = abs(x2 - x1) >= abs(y2 - y1)
    if not horiz and f"{key}_y" in PALETTE:
        key = f"{key}_y"
    length = abs(x2 - x1) if horiz else abs(y2 - y1)
    base = min(x1, x2) if horiz else min(y1, y2)
    other = y1 - thick / 2 if horiz else x1 - thick / 2

    def seg(off, width, z0, z1, tag):
        if width <= 1e-4 or z1 - z0 <= 1e-4:
            return
        if horiz:
            box(f"{name}_{tag}", (base + off, other, z0), (width, thick, z1 - z0),
                key, shade, coll)
        else:
            box(f"{name}_{tag}", (other, base + off, z0), (thick, width, z1 - z0),
                key, shade, coll)

    cuts = sorted(openings, key=lambda o: o[0])
    cursor = 0.0
    for i, (off, width, z0, z1) in enumerate(cuts):
        seg(cursor, off - cursor, 0.0, height, f"s{i}")
        seg(off, width, 0.0, z0, f"sill{i}")              # под окном
        seg(off, width, min(z1, height), height, f"lin{i}")  # перемычка
        # Проём с подоконником — окно: вставляем светлую плашку. Без неё в кадре
        # дыра в пустоту, а окно должно быть самым светлым блоком (раздел 5.6).
        if glaze and z0 > 0.01:
            if horiz:
                box(f"{name}_glass{i}", (base + off, other + thick * 0.35, z0),
                    (width, thick * 0.3, z1 - z0), "window", shade, coll)
            else:
                box(f"{name}_glass{i}", (other + thick * 0.35, base + off, z0),
                    (thick * 0.3, width, z1 - z0), "window", shade, coll)
        # Проём от пола и не шире метра — дверь, вешаем полотно. Проёмы шире
        # остаются открытыми: так в кадре видно, где комнаты соединяются.
        elif doors and z0 <= 0.01 and width <= 1.0:
            if horiz:
                box(f"{name}_door{i}", (base + off, other + thick * 0.3, 0.0),
                    (width, thick * 0.4, z1), "door", shade, coll)
            else:
                box(f"{name}_door{i}", (other + thick * 0.3, base + off, 0.0),
                    (thick * 0.4, width, z1), "door", shade, coll)
        cursor = off + width
    seg(cursor, length - cursor, 0.0, height, "end")


def room_shell(name, pos, size, height, floor=True, ceiling=False, shade="flat", coll=None):
    """Пол и потолок комнаты. Потолок по умолчанию выключен: мешает свету и обзору сверху."""
    x, y = pos
    w, d = size
    if floor:
        box(f"{name}_floor", (x, y, -0.04), (w, d, 0.04), "floor", shade, coll)
    if ceiling:
        box(f"{name}_ceil", (x, y, height), (w, d, 0.06), "ceiling", shade, coll)


def camera(name, loc, target, lens=35.0, ortho=None, level=True, shift=0.0):
    """Камера, направленная в точку.

    level=True держит цель на высоте камеры: наклон вниз заваливает вертикали,
    и комната начинает выглядеть снятой телефоном с рук. Чтобы опустить кадр
    и не завалить вертикали, двигаем не камеру, а объектив — shift (как у
    архитектурного «шифта»): отрицательный опускает кадр.
    """
    if level:
        target = (target[0], target[1], loc[2])
    cam = bpy.data.cameras.new(name)
    if ortho:
        cam.type = "ORTHO"
        cam.ortho_scale = ortho
    else:
        cam.lens = lens
    cam.shift_y = shift
    ob = bpy.data.objects.new(name, cam)
    ob.location = Vector(loc)
    direction = Vector(target) - Vector(loc)
    ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    return ob


def iso_camera(name, center, span, elevation=26.565, turn=45.0, height=None):
    """Ортографическая камера под изометрическим углом (раздел 8.2).

    elevation 26.565° — пиксельная диметрия 2:1 (вертикаль сжата ровно вдвое, сетка
    ложится на целые пиксели). 35.264° — истинная изометрия, но она в пикселях «плывёт».
    """
    # Камеру относим от сцены и даём запас по дальней отсечке: у ортокамеры
    # расстояние не меняет масштаб, зато короткий clip_end режет дальнюю половину
    # района — ромб выходит обрезанным, и это незаметно, пока не измеришь кадр.
    if height is None:
        height = span * 1.5
    cam = bpy.data.cameras.new(name)
    cam.type = "ORTHO"
    cam.ortho_scale = span
    cam.clip_start = 0.1
    cam.clip_end = height * 2 + span * 2
    ob = bpy.data.objects.new(name, cam)
    t = math.radians(turn)
    e = math.radians(elevation)
    d = height
    ob.location = (center[0] + math.cos(e) * math.sin(t) * d,
                   center[1] - math.cos(e) * math.cos(t) * d,
                   center[2] + math.sin(e) * d)
    ob.rotation_euler = (math.radians(90 - elevation), 0.0, t)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# Свет по фазам суток (раздел 7). Числа — (энергия солнца, цвет, угол над горизонтом,
# азимут, цвет и сила неба).
PHASES = {
    "morning": (3.0, (1.0, 0.86, 0.70), 18, 100, (0.55, 0.62, 0.78), 0.45),
    "day":     (5.0, (1.0, 0.97, 0.92), 55, 140, (0.62, 0.70, 0.85), 0.70),
    "evening": (2.2, (1.0, 0.70, 0.48), 10, 250, (0.45, 0.42, 0.50), 0.30),
    "night":   (0.25, (0.55, 0.66, 1.00), 40, 300, (0.07, 0.09, 0.16), 0.10),
}


def light(phase="day", shade="lit"):
    """В flat свет не нужен: Emission светится сам, а тени испортили бы заливки."""
    sc = bpy.context.scene
    if not sc.world:
        sc.world = bpy.data.worlds.new("World")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes.get("Background")
    if shade == "flat":
        if bg:
            bg.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
            bg.inputs["Strength"].default_value = 0.0
        return
    energy, color, elev, azim, sky, sky_s = PHASES[phase]
    if bg:
        bg.inputs["Color"].default_value = (*sky, 1.0)
        bg.inputs["Strength"].default_value = sky_s
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = energy
    sun.color = color
    sun.angle = math.radians(2.0)
    ob = bpy.data.objects.new("sun", sun)
    e, a = math.radians(elev), math.radians(azim)
    ob.rotation_euler = (math.radians(90) - e, 0.0, a)
    sc.collection.objects.link(ob)
    return ob


def lamp(name, pos, energy=60.0, color=(1.0, 0.85, 0.62), size=0.6):
    """Лампа в комнате — для night: без неё интерьер чёрный."""
    la = bpy.data.lights.new(name, "AREA")
    la.energy = energy
    la.color = color
    la.size = size
    ob = bpy.data.objects.new(name, la)
    ob.location = pos
    ob.rotation_euler = (math.radians(180), 0, 0)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def resolve(path):
    """Относительный путь — от корня репозитория.

    Рабочая папка у Blender своя, и `--out assets/...` иначе уезжает в корень диска.
    """
    if not path or os.path.isabs(path):
        return path
    root = os.path.normpath(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    return os.path.join(root, path)


def render(cams, out_dir, suffix="", only="", hide=None):
    """Рендер по списку камер. `only` — имена через запятую или all.

    hide: камера -> подстроки имён, которые на этом кадре не рендерим
    (вид сверху не должен упираться в потолок).
    """
    if not only:
        return []
    wanted = None if only == "all" else {s.strip() for s in only.split(",") if s.strip()}
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    done = []
    for name, ob in cams.items():
        if wanted is not None and name not in wanted:
            continue
        marks = (hide or {}).get(name, ())
        off = []
        for o in bpy.data.objects:
            if marks and any(m in o.name for m in marks) and not o.hide_render:
                o.hide_render = True
                off.append(o)
        sc.camera = ob
        path = os.path.join(out_dir, f"blk_{name}{suffix}.png")
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        for o in off:
            o.hide_render = False
        done.append(path)
        print(f"[blockout] {path}")
    return done


def finish(cams, a, default_out, default_blend, hide=None):
    """Сохранить .blend и отрендерить. Без --background остаёмся в редакторе."""
    out = resolve(a.out or default_out)
    blend = resolve(a.save or default_blend)
    suffix = "" if a.shade == "flat" else f"_{a.phase}"
    suffix = f"_{a.shade}{suffix}"
    files = render(cams, out, suffix, a.render, hide)
    if blend:
        os.makedirs(os.path.dirname(blend), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=blend)
        print(f"[blockout] .blend: {blend}")
    print(f"[blockout] камеры: {', '.join(cams)}")
    print(f"[blockout] отрендерено: {len(files)}")
