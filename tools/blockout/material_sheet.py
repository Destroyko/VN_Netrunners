"""Лист материалов: один цвет на разных поверхностях.

Показывает, ради чего разделены цвет и тип. Строит ряд одинаковых предметов,
красит их одним цветом, но разными материалами, и рендерит под тем же светом,
что и сцены игры.

    & "...blender.exe" -b --python tools\\blockout\\material_sheet.py -- ^
        --color "#C25B52" --kinds paper,fabric,wood,plastic,metal,glass

Без ключей берёт красный акцент и все типы из профилей.
"""

import os
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bl_common as B  # noqa: E402
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402


def material(name, rgb, kind):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    C.build(mat.node_tree, rgb, None, None, None, None, kind)
    return mat


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[::2], argv[1::2]))
    hexcol = opts.get("--color", "#C25B52")
    kinds = [k.strip() for k in opts.get("--kinds", ",".join(C.MATERIALS)).split(",")]
    out = opts.get("--out", "assets/_source/material_sheet.png")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1700, 560
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.eevee.taa_render_samples = 64
    B.flat_color(sc)

    rgb = P.srgb(hexcol)
    step = 2.4
    width = step * (len(kinds) - 1)

    for i, kind in enumerate(kinds):
        x = -width / 2 + i * step
        # Шар показывает, как ложится свет; куб рядом — как выглядит плоскость
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.85, location=(x, 0.0, 0.9),
                                             segments=48, ring_count=24)
        ball = bpy.context.object
        bpy.ops.object.shade_smooth()
        ball.data.materials.append(material("ms_%s_ball" % kind, rgb, kind))
        bpy.ops.mesh.primitive_cube_add(size=1.1, location=(x, -1.7, 0.55))
        cube = bpy.context.object
        cube.rotation_euler = (0.0, 0.0, 0.5)
        cube.data.materials.append(material("ms_%s_cube" % kind, rgb, kind))

    # Пол, чтобы предметы не висели в пустоте
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    floor = bpy.context.object
    floor.data.materials.append(material("ms_floor", P.srgb("#C7CBD2"), "wall"))

    # Свет как в сценах: невысокая заливка плюс один большой источник
    world = bpy.data.worlds.new("ms_world")
    sc.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.52, 0.56, 0.68, 1.0)
    bg.inputs[1].default_value = 0.55

    lamp = bpy.data.lights.new("ms_key", type="AREA")
    lamp.size = 6.0
    lamp.energy = 900.0
    lamp.color = (1.0, 0.95, 0.86)
    lob = bpy.data.objects.new("ms_key", lamp)
    sc.collection.objects.link(lob)
    lob.location = (-3.0, -6.0, 6.0)
    lob.rotation_euler = (0.75, 0.0, -0.45)

    cam_data = bpy.data.cameras.new("ms_cam")
    cam_data.lens = 50.0
    cam = bpy.data.objects.new("ms_cam", cam_data)
    sc.collection.objects.link(cam)
    # Дистанция растёт с числом материалов: на восьми крайние шарики иначе обрезаются
    cam.location = (0.0, -(10.0 + 2.7 * len(kinds)), 4.6)
    cam.rotation_euler = (1.40, 0.0, 0.0)
    sc.camera = cam

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = out if os.path.isabs(out) else os.path.join(root, "..", out)
    path = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                         "..", "..", out)) if not os.path.isabs(out) else out
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[sheet] %s: %s" % (", ".join(kinds), path))


main()
