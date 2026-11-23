"""Мелочь на сцене комнаты героя: мусорное ведро под стол и кружка на стол.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_lit.blend ^
        --python tools\\blockout\\room_props.py

- мусорное ведро (`Trash can`) переезжает под стол героя (стоит у ножки, виден под столешницей) и
  становится тёмно-серым;
- кружка `prop_mug` (белый цилиндр с ручкой) ставится на левый край стола, у клавиатуры.

Повторный запуск ничего не дублирует: ведро ставится в те же координаты, кружка создаётся
один раз. Положение правится руками в Blender. Файл сохраняется.
"""

import math
import os
import sys

import bpy
import bmesh

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402

CAN_CENTRE = (1.78, 6.90)       # центр ведра под столом (x, y), метры
MUG_AT = (1.52, 6.74)           # кружка на столе
DESK_TOP = 0.78                 # высота столешницы


def material(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        kind, color, _ = P.parse_name(name)
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        light = C.build(mat.node_tree, P.srgb(P.COLORS[color]), kind=kind)
        C.surface(mat, kind)
        mat.diffuse_color = (*light, 1.0)
    return mat


def recolor_can():
    """Ведро тёмно-серое: ярко-зелёный пластик выбивался из приглушённой палитры."""
    body = bpy.data.objects.get("Circle")
    if body is None or not body.material_slots:
        return False
    body.material_slots[0].material = material("pal_plastic_steel_dark")
    return True


def move_can():
    root = bpy.data.objects.get("Trash can")
    body = bpy.data.objects.get("Circle")
    if root is None or body is None:
        return False
    # положение считается по самому ведру, а не по пустышке-родителю
    import mathutils
    pts = [body.matrix_world @ mathutils.Vector(c) for c in body.bound_box]
    cx = (min(p.x for p in pts) + max(p.x for p in pts)) / 2
    cy = (min(p.y for p in pts) + max(p.y for p in pts)) / 2
    root.location.x += CAN_CENTRE[0] - cx
    root.location.y += CAN_CENTRE[1] - cy
    return True


def make_mug():
    if bpy.data.objects.get("prop_mug") is not None:
        return False
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=0.04, radius2=0.04, depth=0.09)
    mesh = bpy.data.meshes.new("prop_mug")
    bm.to_mesh(mesh)
    bm.free()
    mug = bpy.data.objects.new("prop_mug", mesh)
    bpy.context.scene.collection.objects.link(mug)
    mug.location = (MUG_AT[0], MUG_AT[1], DESK_TOP + 0.045)
    mug.data.materials.append(material("pal_plastic_snow"))

    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.012, radius2=0.012, depth=0.05)
    hmesh = bpy.data.meshes.new("prop_mug_handle")
    bm.to_mesh(hmesh)
    bm.free()
    handle = bpy.data.objects.new("prop_mug_handle", hmesh)
    bpy.context.scene.collection.objects.link(handle)
    handle.parent = mug
    handle.location = (0.05, 0.0, 0.0)
    handle.rotation_euler = (0.0, math.radians(90), 0.0)
    handle.data.materials.append(material("pal_plastic_snow"))
    return True


def main():
    print("[props] ведро перенесено: %s, перекрашено: %s, кружка создана: %s"
          % (move_can(), recolor_can(), make_mug()))
    bpy.ops.wm.save_mainfile()


if __name__ == "__main__":
    main()
