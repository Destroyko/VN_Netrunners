"""Заменить материал палитры в слоте объекта: `--obj имя --slot номер --to материал`.

Нужен, когда предмету надо сменить цвет, не открывая сцену руками (например, обивка стула).
Новый материал берётся из сцены или собирается по имени палитры (`pal_<тип>_<цвет>`).

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_work_palette_light.blend ^
        --python tools\\blockout\\swap_material.py -- --obj chair.002 --slot 0 --to pal_fabric_grey

Файл сохраняется.
"""

import os
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402


def get_material(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    kind, color, _ = P.parse_name(name)
    if kind is None or color not in P.COLORS:
        raise SystemExit("нет материала %s и имя не из палитры" % name)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    light = C.build(mat.node_tree, P.srgb(P.COLORS[color]), kind=kind)
    C.surface(mat, kind)
    mat.diffuse_color = (*light, 1.0)
    return mat


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[::2], argv[1::2]))
    ob = bpy.data.objects.get(opts.get("--obj", ""))
    if ob is None:
        raise SystemExit("нет объекта %s" % opts.get("--obj"))
    slot = int(opts.get("--slot", 0))
    mat = get_material(opts["--to"])
    old = ob.material_slots[slot].material
    ob.material_slots[slot].material = mat
    print("[swap] %s[%d]: %s -> %s" % (ob.name, slot, old.name if old else None, mat.name))
    bpy.ops.wm.save_mainfile()


main()
