"""Маски кликабельных объектов комнаты героя: точная форма вместо прямоугольников.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_lit.blend ^
        --python tools\\blockout\\room_masks.py [-- --frames main,pc]

Для каждого объекта кадра рендерится силуэт той же камерой, что и фон: белое пятно на прозрачном
фоне, в 1280×720. Остальная сцена на это время «вырезана» (holdout), поэтому то, что стоит
перед предметом (стул перед столом), закрывает его силуэт, а предметы с разных мест не
пересекаются. Силуэты не зависят от времени суток и от состояния ПК: на один кадр один набор.

Маски кладутся в `assets/masks/<локация>_<объект>.png`; игра берёт их по полю `mask` объекта в
`data/locations/` (`docs/gameplay/locations.md`). Какие предметы входят в объект — таблица GROUPS
ниже: имена корневых объектов сцены, дочерние входят сами.

Сцену скрипт не сохраняет.
"""

import os
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import room_frames as R  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "masks")
SIZE = (1280, 720)

# кадр → локация игры
LOCATION = {"main": "loc_room", "pc": "loc_room_desk"}

WINDOW = ["окно", "Vertical Blinds B", "Подоконник_1"]
DESK = ["Table top", "Gaming Desktop", "Modern Monitor", "Black Office Computer PC",
        "Logitech Speaker.001", "Logitech Speaker.002", "Wireless dell keyboard and mouse kit",
        "Notepad", "Pencil", "Customizable Cactus (Geometry Nodes)", "Chive / Herbs / Potted plant",
        "Chive / Herbs / Potted plant.003", "Easter Bunny Statue.001", "Easter Bunny Statue.002",
        "Shy Bunny Statue", "Office Chair Black", "Scool bagpack"]
WARDROBE = ["Dark wood dresser", "Red jacket", "Coat Rack", "Clothes Hanger"]

# кадр → объект игры → корни предметов сцены
GROUPS = {
    "main": {
        "bed": ["IKEA MALM Bed"],
        "window": WINDOW,
        "to_desk": DESK,
        "wardrobe": WARDROBE,
    },
    "pc": {
        "monitor": ["Modern Monitor"],
        "system_block": ["Black Office Computer PC"],
        "window": WINDOW,
    },
}


# Что не входит в силуэт, хотя висит на предмете: подкладка «Model» под столом и тени-накладки
# (`decal_*`, например под рюкзаком: они лежат на полу и дали бы на маске пятно)
EXCLUDE = {"Model"}


def with_children(names):
    found = set()
    for name in names:
        ob = bpy.data.objects.get(name)
        if ob is None:
            print("[masks] нет объекта: %s" % name)
            continue
        stack = [ob]
        while stack:
            cur = stack.pop()
            if cur.name not in EXCLUDE and not cur.name.startswith("decal"):
                found.add(cur.name)
            stack.extend(cur.children)
    return found


def white_material():
    mat = bpy.data.materials.get("rf_mask") or bpy.data.materials.new("rf_mask")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return mat


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    frames = argv[argv.index("--frames") + 1].split(",") if "--frames" in argv else list(GROUPS)
    sc = bpy.context.scene
    vl = bpy.context.view_layer
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = SIZE
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.filter_size = 0.6
    sc.eevee.taa_render_samples = 4
    sc.view_settings.view_transform = "Standard"
    sc.compositing_node_group = None
    R.clear()
    vl.material_override = white_material()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    os.makedirs(OUT, exist_ok=True)
    for frame in frames:
        sc.camera = R.make_camera(frame)
        for object_id, roots in GROUPS[frame].items():
            inside = with_children(roots)
            for o in meshes:
                o.is_holdout = o.name not in inside
            path = os.path.join(OUT, "%s_%s.png" % (LOCATION[frame], object_id))
            sc.render.filepath = path
            bpy.ops.render.render(write_still=True)
            print("[masks] %s" % path)
    for o in meshes:
        o.is_holdout = False
    vl.material_override = None


if __name__ == "__main__":
    main()
