"""Кадры смартфона для игры: корпус по трём фазам света, маска экрана и его размеры.

    & "...blender.exe" -b assets\\_source\\blockout\\smartphone_example.blend ^
        --python tools\\blockout\\phone_frames.py [-- --height 2000 --samples 128]

Сцену разработчика скрипт не меняет и не сохраняет: свет и камеру ставит на время рендера, материалы
пересобирает в памяти тем же cel-шейдером, что у комнат. Модель стоит как нарисована (криво): скрипт сам
находит экран (слот материала `pal_fabric_black`), берёт нормаль экрана и ставит ортографическую камеру
прямо на него, «верх» кадра — вдоль длинной стороны экрана.

Выход в `assets/_source/blockout/renders/phone/`:
- `phone_<фаза>.png` — корпус с прозрачным фоном и **вырезанным экраном** для day, evening, night: игра кладёт
  его поверх интерфейса, и рамка сама обрезает интерфейс по скруглённым углам;
- `phone_screen_mask.png` — белый закруглённый экран на прозрачном: по нему игра обрезает слой
  интерфейса по форме экрана;
- `phone_screen.json` — размер кадра, прямоугольник экрана в пикселях, радиус скругления углов и
  безопасный отступ для интерфейса (`safe_inset`): иконки и подписи не должны заходить ближе.
"""

import json
import math
import os
import sys

import bpy
import mathutils

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "_source", "blockout", "renders", "phone")
BODY = "Body phone"
SCREEN_MATERIAL = "pal_fabric_black"
MARGIN = 0.05            # поля вокруг корпуса, доля высоты

# Свет по фазам. key — основной источник (цвет, мощность Вт); fill — холодная подсветка с другой стороны;
# floor, tint, shadow — отклик материалов на свет (`cel_shader.set_light_response`), как у комнат
PHASES = {
    "day":     {"key": ((1.00, 0.97, 0.92), 60.0), "fill": ((0.70, 0.80, 1.00), 10.0),
                "world": ((0.62, 0.72, 0.90), 0.35), "floor": 0.5, "tint": 0.0, "shadow": 0.2},
    "evening": {"key": ((1.00, 0.55, 0.30), 45.0), "fill": ((0.50, 0.45, 0.90), 6.0),
                "world": ((0.80, 0.45, 0.35), 0.15), "floor": 0.5, "tint": 0.6, "shadow": 0.35},
    "night":   {"key": ((1.00, 0.42, 0.10), 18.0), "fill": ((0.25, 0.40, 1.00), 4.0),
                "world": ((0.05, 0.08, 0.20), 0.05), "floor": 0.18, "tint": 0.85, "shadow": 0.5},
}


def rebuild_materials():
    """Пересобрать материалы палитры тем же шейдером, что у комнат (в памяти)."""
    for mat in bpy.data.materials:
        if not mat.name.startswith("pal_"):
            continue
        parsed = P.parse_name(mat.name)
        if parsed is None:
            continue
        kind, color, _ = parsed
        mat.use_nodes = True
        light = C.build(mat.node_tree, P.srgb(P.COLORS[color]), None, None, None, None, kind)
        C.surface(mat, kind)
        mat.diffuse_color = (*light, 1.0)
    C.unify_light_groups()


def screen_frame(ob):
    """Центр экрана, нормаль наружу, «верх» и «право» в плоскости экрана (мировые координаты).

    Оси — главные направления облака вершин экрана: самая короткая — нормаль, самая длинная — «верх».
    Среднее по нормалям граней не годится: скруглённые края тянут его в сторону."""
    import numpy as np
    me = ob.data
    index = [i for i, s in enumerate(ob.material_slots) if s.material and s.material.name == SCREEN_MATERIAL][0]
    verts = sorted({v for p in me.polygons if p.material_index == index for v in p.vertices})
    pts = np.array([tuple(ob.matrix_world @ me.vertices[v].co) for v in verts])
    centre_np = pts.mean(axis=0)
    values, vectors = np.linalg.eigh(np.cov((pts - centre_np).T))     # по возрастанию
    normal = mathutils.Vector(vectors[:, 0]).normalized()
    up = mathutils.Vector(vectors[:, 2]).normalized()
    centre = mathutils.Vector(centre_np)
    body = [ob.matrix_world @ v.co for v in me.vertices]
    body_centre = sum(body, mathutils.Vector()) / len(body)
    if (centre - body_centre).dot(normal) < 0.0:        # наружу: экран лежит с этой стороны корпуса
        normal = -normal
    if up.z < 0.0:
        up = -up
    right = up.cross(normal)                              # камера смотрит против нормали
    dims = [round(float((pts @ vectors[:, k]).max() - (pts @ vectors[:, k]).min()) * 100, 2) for k in (2, 1, 0)]
    print("[phone] экран, см (длина, ширина, толщина облака): %s" % dims)
    return centre, normal, up, right, len(verts)


def setup_scene(ob, centre, normal, up, right, height_px):
    sc = bpy.context.scene
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
    h = max((p - centre).dot(up) for p in pts) - min((p - centre).dot(up) for p in pts)
    w = max((p - centre).dot(right) for p in pts) - min((p - centre).dot(right) for p in pts)
    mid = centre + up * ((max((p - centre).dot(up) for p in pts) + min((p - centre).dot(up) for p in pts)) / 2) \
        + right * ((max((p - centre).dot(right) for p in pts) + min((p - centre).dot(right) for p in pts)) / 2)
    frame_h = h * (1.0 + 2 * MARGIN)
    frame_w = w + h * 2 * MARGIN
    sc.render.resolution_y = height_px
    sc.render.resolution_x = int(round(height_px * frame_w / frame_h))
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    cam_data = bpy.data.cameras.new("phone_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = frame_h
    cam_data.sensor_fit = "VERTICAL"
    cam = bpy.data.objects.new("phone_cam", cam_data)
    sc.collection.objects.link(cam)
    cam.location = mid + normal * 0.6
    basis = mathutils.Matrix((right, up, normal)).transposed()     # столбцы: x кадра, y кадра, назад
    cam.rotation_euler = basis.to_euler()
    sc.camera = cam
    return mid, frame_h, frame_w


def lights(phase, mid, normal, up, right):
    for o in [o for o in bpy.data.objects if o.name.startswith("pf_")]:
        data = o.data
        bpy.data.objects.remove(o)
        bpy.data.lights.remove(data)
    ph = PHASES[phase]
    sc = bpy.context.scene
    world = sc.world or bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*ph["world"][0], 1.0)
    bg.inputs["Strength"].default_value = ph["world"][1]
    for name, (color, power), pos in (
            ("pf_key", ph["key"], mid + normal * 0.45 - right * 0.22 + up * 0.25),
            ("pf_fill", ph["fill"], mid + normal * 0.45 + right * 0.30 - up * 0.10)):
        la = bpy.data.lights.new(name, "AREA")
        la.shape = "RECTANGLE"
        la.size, la.size_y = 0.30, 0.30
        la.color = color
        la.energy = power
        la.specular_factor = 0.0
        ob = bpy.data.objects.new(name, la)
        ob.location = pos
        ob.rotation_euler = (mid - pos).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(ob)
    C.set_light_response(ph["floor"], ph["tint"], ph["shadow"], (0.3, 0.45, 1.0), 0.0)


def punch_screen(ob):
    """Экран вырезается из кадра корпуса (прозрачный): материал слота экрана заменяется на holdout."""
    mat = bpy.data.materials.new("pf_hole")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    hole = nt.nodes.new("ShaderNodeHoldout")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(hole.outputs[0], out.inputs["Surface"])
    for slot in ob.material_slots:
        if slot.material and slot.material.name == SCREEN_MATERIAL:
            slot.material = mat


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[phone] %s" % path)


def screen_mask(ob, path):
    """Экран белым, всё остальное вырезано: по маске игра обрезает интерфейс."""
    sc = bpy.context.scene
    vl = bpy.context.view_layer
    mat = bpy.data.materials.new("pf_white")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    vl.material_override = mat
    # корпус вокруг экрана — вырезан: рисуем только грани экрана, остальные гасим дубликатом объекта
    hide = bpy.data.objects.new("pf_hold", ob.data.copy())
    hide.matrix_world = ob.matrix_world
    sc.collection.objects.link(hide)
    index = [i for i, s in enumerate(ob.material_slots) if s.material and s.material.name == SCREEN_MATERIAL][0]
    # у копии оставляем только грани корпуса (всё, кроме экрана) и делаем её holdout
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(hide.data)
    for f in [f for f in bm.faces if f.material_index == index]:
        bm.faces.remove(f)
    bm.to_mesh(hide.data)
    bm.free()
    hide.is_holdout = True
    ob_holdout = ob.is_holdout
    ob.is_holdout = False
    sc.render.filter_size = 0.5
    render(path)
    bpy.data.objects.remove(hide)
    vl.material_override = None
    ob.is_holdout = ob_holdout


def measure(mask_path):
    """Прямоугольник экрана и радиус скругления по маске."""
    img = bpy.data.images.load(mask_path)
    w, h = img.size
    px = list(img.pixels)
    alpha = [px[i * 4 + 3] for i in range(w * h)]
    xs, ys = [], []
    for y in range(h):
        row = alpha[y * w:(y + 1) * w]
        hit = [x for x, a in enumerate(row) if a > 0.5]
        if hit:
            xs += [hit[0], hit[-1]]
            ys.append(y)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)

    def at(x, y):          # y в Blender растёт вверх
        return alpha[(h - 1 - y) * w + x] > 0.5

    # вдоль диагонали от левого верхнего угла рамки до первого пикселя экрана
    d = 0
    while not at(x0 + d, y0 + d) and d < min(x1 - x0, y1 - y0):
        d += 1
    radius = d / (math.sqrt(2.0) - 1.0)
    bpy.data.images.remove(img)
    return {"x": x0, "y": y0, "w": x1 - x0 + 1, "h": y1 - y0 + 1, "corner_radius": round(radius, 1),
            "image_w": w, "image_h": h}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    height = int(argv[argv.index("--height") + 1]) if "--height" in argv else 2000
    samples = int(argv[argv.index("--samples") + 1]) if "--samples" in argv else 128
    os.makedirs(OUT, exist_ok=True)
    sc = bpy.context.scene
    ob = bpy.data.objects[BODY]
    rebuild_materials()
    centre, normal, up, right, faces = screen_frame(ob)
    mid, frame_h, frame_w = setup_scene(ob, centre, normal, up, right, height)
    sc.eevee.taa_render_samples = samples
    # сначала маска экрана (пока слот ещё называется по материалу), потом корпус с вырезанным экраном
    mask_path = os.path.join(OUT, "phone_screen_mask.png")
    screen_mask(ob, mask_path)
    info = measure(mask_path)
    punch_screen(ob)
    for phase in PHASES:
        lights(phase, mid, normal, up, right)
        render(os.path.join(OUT, "phone_%s.png" % phase))
    radius = info["corner_radius"]
    info["safe_inset"] = int(math.ceil(radius * 0.45 + info["h"] * 0.004))
    info["aspect"] = round(info["w"] / info["h"], 4)
    info["note"] = ("Интерфейс телефона кладётся в прямоугольник x, y, w, h и обрезается по phone_screen_mask.png; "
                    "иконки и подписи не ближе safe_inset пикселей к краю.")
    with open(os.path.join(OUT, "phone_screen.json"), "w", encoding="utf-8") as fh:
        json.dump(info, fh, ensure_ascii=False, indent=2)
    print("[phone] экран: %s" % info)


if __name__ == "__main__":
    main()
