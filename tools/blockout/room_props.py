"""Мелочь на сцене комнаты героя: мусорное ведро под стол и кружка на стол.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_lit.blend ^
        --python tools\\blockout\\room_props.py

- мусорное ведро (`Trash can`) стоит у двери, вне кадра (под столом оно выглядело странно: там
  разработчик ставит рюкзак), и тёмно-серое;
- мягкие тени-накладки под настенной полкой и у подушек на изголовье кровати (`decal_*`):
  плоский градиент чёрного с прозрачностью, ложится поверх стены и изголовья;
- кружка `prop_mug` (белый цилиндр с ручкой) ставится на левый край стола, у клавиатуры;
- мягкая тень на полу под рюкзаком (`decal_bag_floor`): вещь без неё выглядит парящей.
  Запуск только этого: `-- --only contact` (остальное, в том числе кружка, не создаётся заново).

Повторный запуск ничего не дублирует: ведро ставится в те же координаты, кружка создаётся
один раз, накладки пересоздаются с текущими параметрами. Положение правится руками в Blender. Файл сохраняется.
"""

import math
import os
import sys

import bpy
import bmesh

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402

CAN_CENTRE = (0.33, 4.51)       # центр ведра (x, y), метры: у двери, вне кадра. Под стол разработчик ставит рюкзак
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


def decal(name, origin, u_axis, v_axis, u_size, v_size, alpha):
    """Мягкая тень-накладка: плоскость с градиентом прозрачности от тёмного к прозрачному.

    origin — угол плоскости, u_axis и v_axis — единичные направления сторон. Тёмный край у
    v = 0 (там, где предмет касается поверхности), к v = 1 тень гаснет; по краям u мягко
    сходит на нет. Накладка не отбрасывает тень и рисуется поверх (режим Blended).
    """
    import mathutils
    old = bpy.data.objects.get(name)
    if old is not None:                       # пересоздаём: параметры накладки правятся здесь
        mesh, mat_old = old.data, (old.material_slots[0].material if old.material_slots else None)
        bpy.data.objects.remove(old)
        bpy.data.meshes.remove(mesh)
        if mat_old is not None:
            bpy.data.materials.remove(mat_old)
    o = mathutils.Vector(origin)
    u = mathutils.Vector(u_axis) * u_size
    v = mathutils.Vector(v_axis) * v_size
    bm = bmesh.new()
    verts = [bm.verts.new(c) for c in (o, o + u, o + u + v, o + v)]
    face = bm.faces.new(verts)
    uv = bm.loops.layers.uv.new("UV")
    for loop, co in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uv].uv = co
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    ob.visible_shadow = False

    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.surface_render_method = "BLENDED"
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (900, 0)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    coord.location = (-700, 0)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    sep.location = (-500, 0)
    nt.links.new(coord.outputs["UV"], sep.inputs[0])
    fall = nt.nodes.new("ShaderNodeMapRange")          # вдоль v: от тени к прозрачному
    fall.location = (-300, 100)
    fall.interpolation_type = "SMOOTHSTEP"
    fall.clamp = True
    fall.inputs["To Min"].default_value = alpha
    fall.inputs["To Max"].default_value = 0.0
    nt.links.new(sep.outputs["Y"], fall.inputs["Value"])
    side = nt.nodes.new("ShaderNodeMath")              # |2u - 1|
    side.location = (-500, -250)
    side.operation = "PINGPONG"
    side.inputs[1].default_value = 0.5
    nt.links.new(sep.outputs["X"], side.inputs[0])
    edge = nt.nodes.new("ShaderNodeMapRange")          # у краёв по u тень сходит на нет
    edge.location = (-300, -250)
    edge.interpolation_type = "SMOOTHSTEP"
    edge.clamp = True
    edge.inputs["From Min"].default_value = 0.0
    edge.inputs["From Max"].default_value = 0.12
    nt.links.new(side.outputs[0], edge.inputs["Value"])
    mulf = nt.nodes.new("ShaderNodeMath")
    mulf.location = (-60, 0)
    mulf.operation = "MULTIPLY"
    nt.links.new(fall.outputs[0], mulf.inputs[0])
    nt.links.new(edge.outputs[0], mulf.inputs[1])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    tr.location = (160, -120)
    dark = nt.nodes.new("ShaderNodeEmission")
    dark.location = (160, -260)
    dark.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.location = (560, 0)
    nt.links.new(mulf.outputs[0], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(dark.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    ob.data.materials.append(mat)
    return True


def make_decals():
    """Тени-накладки: под настенной полкой и на изголовье у подушек."""
    # Полка: стена x = 0.152, шире полки по y, вниз от её нижнего края (z = 1.188)
    a = decal("decal_shelf", (0.152, 5.68, 1.188), (0, 1, 0), (0, 0, -1), 1.17, 0.45, 0.7)
    # Изголовье: передняя грань y = 6.972, тень от подушек и матраса, гаснет вверх по z
    b = decal("decal_headboard", (0.23, 6.972, 0.42), (1, 0, 0), (0, 0, 1), 1.0, 0.5, 0.65)
    return a, b


def blob(name, centre, size, alpha, parent=None):
    """Мягкая круглая тень на горизонтальной поверхности: плотная в центре, гаснет к краю.

    centre — (x, y, z) центра на поверхности, size — (по x, по y) в метрах. Накладка не
    отбрасывает тень, рисуется поверх (Blended). parent — предмет, с которым она двигается."""
    import mathutils
    old = bpy.data.objects.get(name)
    if old is not None:
        mesh, mat_old = old.data, (old.material_slots[0].material if old.material_slots else None)
        bpy.data.objects.remove(old)
        bpy.data.meshes.remove(mesh)
        if mat_old is not None:
            bpy.data.materials.remove(mat_old)
    hx, hy = size[0] / 2.0, size[1] / 2.0
    bm = bmesh.new()
    verts = [bm.verts.new((centre[0] + dx, centre[1] + dy, centre[2]))
             for dx, dy in ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy))]
    face = bm.faces.new(verts)
    uv = bm.loops.layers.uv.new("UV")
    for loop, co in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uv].uv = co
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    ob.visible_shadow = False
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.surface_render_method = "BLENDED"
    nt = mat.node_tree
    nt.nodes.clear()
    coord = nt.nodes.new("ShaderNodeTexCoord")
    off = nt.nodes.new("ShaderNodeVectorMath")
    off.operation = "SUBTRACT"
    off.inputs[1].default_value = (0.5, 0.5, 0.0)
    nt.links.new(coord.outputs["UV"], off.inputs[0])
    ln = nt.nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    nt.links.new(off.outputs[0], ln.inputs[0])
    fall = nt.nodes.new("ShaderNodeMapRange")       # 0 в центре, 0,5 на краю → тень alpha .. 0
    fall.interpolation_type = "SMOOTHSTEP"
    fall.clamp = True
    fall.inputs["From Min"].default_value = 0.12
    fall.inputs["From Max"].default_value = 0.5
    fall.inputs["To Min"].default_value = alpha
    fall.inputs["To Max"].default_value = 0.0
    nt.links.new(ln.outputs["Value"], fall.inputs["Value"])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    dark = nt.nodes.new("ShaderNodeEmission")
    dark.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(fall.outputs[0], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(dark.outputs[0], mix.inputs[2])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    ob.data.materials.append(mat)
    if parent is not None:
        ob.parent = parent
        ob.matrix_parent_inverse = parent.matrix_world.inverted()
    return ob


def make_contact_shadows():
    """Тень на полу под рюкзаком: размер по самому рюкзаку, чуть шире и смещена от окна и торшера."""
    import mathutils
    bag = bpy.data.objects.get("BACKPACK-fabric_blue")
    if bag is None:
        return False
    pts = [bag.matrix_world @ mathutils.Vector(c) for c in bag.bound_box]
    x0, x1 = min(p.x for p in pts), max(p.x for p in pts)
    y0, y1 = min(p.y for p in pts), max(p.y for p in pts)
    cx, cy = (x0 + x1) / 2.0 + 0.05, (y0 + y1) / 2.0 - 0.05      # свет сзади слева, тень вперёд и вправо
    blob("decal_bag_floor", (cx, cy, 0.009), ((x1 - x0) * 1.9, (y1 - y0) * 1.9), 0.8,
         parent=bpy.data.objects.get("Scool bagpack"))
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
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--only" in argv and argv[argv.index("--only") + 1] == "contact":
        print("[props] тени на полу: %s" % make_contact_shadows())
        bpy.ops.wm.save_mainfile()
        return
    print("[props] ведро перенесено: %s, перекрашено: %s, кружка создана: %s, тени-накладки: %s"
          % (move_can(), recolor_can(), make_mug(), make_decals()))
    bpy.ops.wm.save_mainfile()


if __name__ == "__main__":
    main()
