"""
Детализация коридора, прихожей и кухни (продолжение detail_hero_room.py).

Запуск: apartment_detail.blend -> вкладка Scripting -> Open этот файл -> Run Script.
Заменённые кубики уходят в скрытую коллекцию "blockout_old" (не удаляются).
Новые предметы: коллекции "corridor_detail" и "kitchen_detail", префикс det_.
Повторный запуск безопасен: сначала удаляет то, что создал прошлый запуск.
"""
import bpy, math
from mathutils import Vector

# ======================= helpers (те же, что в detail_hero_room.py) =======================
def flat(name, rgb, strength=1.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (*rgb, 1)
    em.inputs[1].default_value = strength
    nt.links.new(em.outputs[0], out.inputs[0])
    return m

def box(mn, mx, mat, rot_z=0.0, pivot=None):
    (x0, y0, z0), (x1, y1, z1) = mn, mx
    vs = [Vector((x, y, z)) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    if rot_z:
        c = Vector(pivot) if pivot else Vector(((x0 + x1) / 2, (y0 + y1) / 2, 0))
        a = math.radians(rot_z)
        ca, sa = math.cos(a), math.sin(a)
        vs = [Vector((c.x + (v.x - c.x) * ca - (v.y - c.y) * sa,
                      c.y + (v.x - c.x) * sa + (v.y - c.y) * ca, v.z)) for v in vs]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return vs, faces, mat

def swap_xy(parts):
    """Отразить детали по диагонали x<->y (чтобы строить двери/полки в стенах вдоль Y)."""
    out = []
    for vs, fs, m in parts:
        out.append(([Vector((v.y, v.x, v.z)) for v in vs], [tuple(reversed(f)) for f in fs], m))
    return out

def build(name, parts, coll):
    verts, faces, fmats, mats = [], [], [], []
    for vs, fs, mat in parts:
        if mat not in mats:
            mats.append(mat)
        off = len(verts)
        verts += vs
        for f in fs:
            faces.append(tuple(i + off for i in f))
            fmats.append(mats.index(mat))
    xs, ys, zs = [v.x for v in verts], [v.y for v in verts], [v.z for v in verts]
    o = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)))
    me = bpy.data.meshes.new(name)
    me.from_pydata([v - o for v in verts], [], faces)
    for m in mats:
        me.materials.append(m)
    for p, mi in zip(me.polygons, fmats):
        p.material_index = mi
    me.update()
    ob = bpy.data.objects.new(name, me)
    ob.location = o
    coll.objects.link(ob)
    return ob

# ======================= материалы =======================
D = {n: bpy.data.materials[n] for n in
     ["counter_flat", "appl_flat", "table_flat", "door_flat", "closet_flat", "soft_flat",
      "shelf_flat", "paper_flat", "blind_flat", "pc_flat"]}
D["dark"] = flat("dark_flat", (0.04, 0.04, 0.05))
D["metal"] = flat("metal_flat", (0.30, 0.31, 0.34))
D["wood"] = flat("wood_flat", (0.36, 0.27, 0.19))
D["lampshade"] = flat("lampshade_flat", (0.95, 0.85, 0.62), 1.5)
D["plant"] = flat("plant_flat", (0.22, 0.45, 0.25))
D["pot"] = flat("pot_flat", (0.62, 0.33, 0.22))
D["book_r"] = flat("book_red_flat", (0.45, 0.16, 0.14))
D["book_g"] = flat("book_green_flat", (0.20, 0.36, 0.26))
D["book_y"] = flat("book_yellow_flat", (0.70, 0.58, 0.25))
D["trim"] = flat("trim_flat", (0.78, 0.77, 0.73))
D["door_panel"] = flat("door_panel_flat", (0.46, 0.39, 0.33))
D["cab"] = flat("kitchen_cab_flat", (0.66, 0.58, 0.46))
D["worktop"] = flat("worktop_flat", (0.17, 0.17, 0.19))
D["tile"] = flat("tile_flat", (0.80, 0.82, 0.79))
D["floor_a"] = flat("kitchen_floor_a_flat", (0.30, 0.29, 0.28))
D["floor_b"] = flat("kitchen_floor_b_flat", (0.22, 0.21, 0.21))
D["rug"] = flat("rug_flat", (0.42, 0.19, 0.17))
D["rug2"] = flat("rug_border_flat", (0.62, 0.48, 0.30))
D["mat"] = flat("doormat_flat", (0.24, 0.18, 0.13))
D["mirror"] = flat("mirror_flat", (0.62, 0.70, 0.78))
D["art1"] = flat("art_blue_flat", (0.25, 0.42, 0.62))
D["art2"] = flat("art_orange_flat", (0.80, 0.48, 0.25))
D["fruit"] = flat("fruit_flat", (0.85, 0.55, 0.15))
D["apple"] = flat("apple_flat", (0.65, 0.15, 0.12))
D["coat2"] = flat("coat_dark_flat", (0.18, 0.20, 0.26))

# ======================= коллекции =======================
scene = bpy.context.scene
old = bpy.data.collections.get("blockout_old") or bpy.data.collections.new("blockout_old")
if old.name not in scene.collection.children:
    scene.collection.children.link(old)
old.hide_viewport = True
old.hide_render = True

def fresh_collection(name):
    c = bpy.data.collections.get(name)
    if c:
        for ob in list(c.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
    else:
        c = bpy.data.collections.new(name)
        scene.collection.children.link(c)
    return c

COR = fresh_collection("corridor_detail")
KIT = fresh_collection("kitchen_detail")

REPLACE = ["kit_counter", "kit_stove", "kit_upper", "kit_fridge", "kit_table",
           "hall_closet", "hall_shoes",
           "in_n_door0", "in_n_door1", "in_s_door0", "in_s_door1", "in_s_door2", "ext_e_door0"]
for n in REPLACE:
    ob = bpy.data.objects.get(n)
    if ob and old not in ob.users_collection:
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        old.objects.link(ob)

# ======================= ДВЕРИ (все межкомнатные + входная) =======================
def door_parts(a0, a1, wc, half=0.06, latch_hi=True, leaf_mat=None, both_sides=True):
    """Дверь в стене вдоль X: проём a0..a1 по X, центр стены по Y = wc."""
    leaf_mat = leaf_mat or D["door_flat"]
    P = [box((a0 + 0.01, wc - 0.02, 0), (a1 - 0.01, wc + 0.02, 2.08), leaf_mat)]
    lx = a1 - 0.09 if latch_hi else a0 + 0.09          # сторона ручки
    sgn = -1 if latch_hi else 1
    for side in (-1, 1):
        f = wc + side * 0.02                            # плоскость полотна
        o = lambda d: (min(f, f + side * d), max(f, f + side * d))
        y0, y1 = o(0.006)
        P += [box((a0 + 0.13, y0, 1.15), (a1 - 0.13, y1, 1.95), D["door_panel"]),
              box((a0 + 0.13, y0, 0.15), (a1 - 0.13, y1, 0.98), D["door_panel"])]
        y0, y1 = o(0.012)
        P.append(box((lx - 0.025, y0, 0.93), (lx + 0.025, y1, 1.07), D["metal"]))     # накладка
        y0, y1 = o(0.06)
        y0b, y1b = o(0.045)
        lx2 = lx + sgn * 0.13
        P.append(box((min(lx, lx2), y0b, 0.985), (max(lx, lx2), y1b, 1.015), D["metal"]))  # ручка
        P.append(box((lx - 0.01, y0, 0.99), (lx + 0.01, y1, 1.01), D["metal"]))
        if not both_sides and side == 1:
            continue
        w = wc + side * half                            # плоскость стены
        y0, y1 = (min(w, w + side * 0.015), max(w, w + side * 0.015))
        P += [box((a0 - 0.07, y0, 0), (a0, y1, 2.17), D["trim"]),                  # наличники
              box((a1, y0, 0), (a1 + 0.07, y1, 2.17), D["trim"]),
              box((a0 - 0.07, y0, 2.10), (a1 + 0.07, y1, 2.17), D["trim"])]
    return P

build("det_door_room_hero", door_parts(2.30, 3.20, 4.30), COR)
build("det_door_kitchen",   door_parts(4.30, 5.20, 4.30, latch_hi=False), COR)
build("det_door_bath",      door_parts(0.90, 1.80, 3.00), COR)
build("det_door_wc",        door_parts(2.70, 3.40, 3.00), COR)
build("det_door_room_mate", door_parts(5.20, 6.10, 3.00, latch_hi=False), COR)
# входная: стена вдоль Y (x=9.40, толщина 0.30) — строим в осях X и отражаем
P = door_parts(1.20, 2.20, 9.40, half=0.15, leaf_mat=D["worktop"])
P.append(box((1.69, 9.40 - 0.15 - 0.03, 1.48), (1.71, 9.40 - 0.02, 1.50), D["metal"]))  # глазок
build("det_door_front", swap_xy(P), COR)

# ======================= КОРИДОР =======================
# дорожка на полу
build("det_runner", [box((0.55, 3.28, 0), (6.95, 4.02, 0.008), D["rug2"]),
                     box((0.62, 3.35, 0.008), (6.88, 3.95, 0.012), D["rug"])], COR)

# плинтусы
P = []
for x0, x1 in ((0.15, 2.23), (3.27, 4.23), (5.27, 8.00)):            # северная стена (y=4.24)
    P.append(box((x0, 4.225, 0), (x1, 4.24, 0.07), D["trim"]))
for x0, x1 in ((0.15, 0.83), (1.87, 2.63), (3.47, 5.13), (6.17, 7.34)):  # южная (y=3.06)
    P.append(box((x0, 3.06, 0), (x1, 3.075, 0.07), D["trim"]))
P.append(box((0.15, 3.06, 0), (0.165, 4.24, 0.07), D["trim"]))     # торец
# прихожая
P.append(box((7.46, 0.15, 0), (7.475, 3.00, 0.07), D["trim"]))
P.append(box((7.46, 0.15, 0), (9.25, 0.165, 0.07), D["trim"]))
for y0, y1 in ((0.15, 1.13), (2.27, 4.24)):
    P.append(box((9.235, y0, 0), (9.25, y1, 0.07), D["trim"]))
build("det_baseboards", P, COR)

# потолочные светильники
for i, (x, y) in enumerate(((1.4, 3.65), (3.8, 3.65), (6.2, 3.65), (8.4, 2.1))):
    build(f"det_ceiling_lamp_{i}", [box((x - 0.17, y - 0.17, 2.66), (x + 0.17, y + 0.17, 2.70), D["trim"]),
                                    box((x - 0.15, y - 0.15, 2.645), (x + 0.15, y + 0.15, 2.66), D["lampshade"])], COR)

# картины в рамках
def frame_parts(a0, a1, z0, z1, wall, side, art, along_x=True):
    """Рамка на стене вдоль X (плоскость y=wall, side=+1/-1 куда торчит)."""
    o = lambda d: (min(wall, wall + side * d), max(wall, wall + side * d))
    y0, y1 = o(0.025)
    ya, yb = o(0.03)
    P = [box((a0, y0, z0), (a1, y1, z1), D["dark"]),
         box((a0 + 0.04, ya, z0 + 0.04), (a1 - 0.04, yb, z1 - 0.04), D["paper_flat"])]
    yc, yd = o(0.033)
    w, h = a1 - a0 - 0.16, z1 - z0 - 0.16
    P += [box((a0 + 0.08, yc, z0 + 0.08), (a0 + 0.08 + w * 0.6, yd, z0 + 0.08 + h * 0.7), art[0]),
          box((a0 + 0.08 + w * 0.45, yc, z0 + 0.08 + h * 0.4), (a1 - 0.08, yd, z1 - 0.08), art[1])]
    return P

build("det_picture_1", frame_parts(3.45, 4.05, 1.35, 1.85, 4.24, -1, (D["art1"], D["art2"])), COR)
build("det_picture_2", frame_parts(5.60, 6.40, 1.30, 1.85, 4.24, -1, (D["art2"], D["book_g"])), COR)
build("det_picture_3", frame_parts(6.70, 7.25, 1.40, 1.80, 4.24, -1, (D["book_r"], D["art1"])), COR)
build("det_picture_4", frame_parts(3.80, 4.95, 1.35, 1.80, 3.06, 1, (D["book_y"], D["art1"])), COR)

# выключатели у дверей (со стороны коридора)
P = []
for x, wall, side in ((3.30, 4.24, -1), (4.17, 4.24, -1), (1.90, 3.06, 1), (3.50, 3.06, 1), (5.07, 3.06, 1)):
    y0, y1 = min(wall, wall + side * 0.015), max(wall, wall + side * 0.015)
    P.append(box((x - 0.04, y0, 1.00), (x + 0.04, y1, 1.08), D["trim"]))
build("det_switches", P, COR)

# стеллаж в торце коридора (у стены x=0.15)
P = [box((0.15, 3.15, 0), (0.50, 3.18, 1.90), D["wood"]),
     box((0.15, 4.12, 0), (0.50, 4.15, 1.90), D["wood"]),
     box((0.15, 3.18, 0), (0.17, 4.12, 1.90), D["wood"])]
for z in (0.05, 0.50, 0.95, 1.40, 1.87):
    P.append(box((0.15, 3.18, z), (0.50, 4.12, z + 0.03), D["wood"]))
# содержимое полок
P += [box((0.20, 3.22, 0.08), (0.47, 3.60, 0.38), D["closet_flat"]),     # коробки
      box((0.20, 3.66, 0.08), (0.46, 4.05, 0.32), D["paper_flat"]),
      box((0.22, 3.25, 0.98), (0.45, 3.55, 1.20), D["shelf_flat"]),
      box((0.24, 3.80, 1.43), (0.40, 3.95, 1.60), D["pot"]),             # вазон
      box((0.30, 3.82, 1.60), (0.34, 3.93, 1.80), D["plant"]),
      box((0.28, 3.86, 1.60), (0.36, 3.89, 1.75), D["plant"], rot_z=50)]
y = 3.22
for i, h in enumerate((0.26, 0.22, 0.28, 0.24, 0.20, 0.27, 0.23)):     # книги
    P.append(box((0.21, y, 0.53), (0.44, y + 0.035, 0.53 + h), (D["book_r"], D["book_g"], D["book_y"], D["shelf_flat"])[i % 4]))
    y += 0.04
P += [box((0.21, 3.70, 0.98), (0.44, 4.05, 1.03), D["book_g"]),
      box((0.22, 3.72, 1.03), (0.43, 4.03, 1.07), D["book_y"])]
build("det_corridor_shelf", P, COR)

# ======================= ПРИХОЖАЯ =======================
# шкаф-купе у западной стены (фасад в +X, x=8.10), одна дверца с зеркалом
P = [box((7.50, 0.20, 0.06), (8.10, 1.60, 2.10), D["closet_flat"]),
     box((7.52, 0.22, 0), (8.08, 1.58, 0.06), D["dark"]),
     box((8.10, 0.89, 0.08), (8.105, 0.91, 2.08), D["dark"]),
     box((8.10, 0.98, 0.20), (8.108, 1.52, 1.95), D["mirror"]),
     box((8.10, 0.80, 0.95), (8.125, 0.82, 1.25), D["metal"]),
     box((8.10, 0.98, 0.95), (8.125, 1.00, 1.25), D["metal"])]
build("det_hall_closet", P, COR)

# обувная банкетка у восточной стены (фасад в -X, x=8.95) + обувь
P = [box((8.95, 0.30, 0), (8.98, 1.10, 0.40), D["wood"]),
     box((8.95, 0.30, 0), (9.33, 0.33, 0.40), D["wood"]),
     box((8.95, 1.07, 0), (9.33, 1.10, 0.40), D["wood"]),
     box((8.95, 0.30, 0.18), (9.33, 1.10, 0.20), D["wood"]),
     box((8.95, 0.30, 0.38), (9.33, 1.10, 0.40), D["wood"]),
     box((8.96, 0.32, 0.40), (9.32, 1.08, 0.46), D["soft_flat"])]
P = [p for i, p in enumerate(P) if i != 0]   # спереди открытая
for k, (y, mat) in enumerate(((0.38, D["dark"]), (0.62, D["book_r"]), (0.86, D["coat2"]))):
    for zz in (0.0, 0.20):
        if k == 2 and zz == 0.20:
            continue
        P += [box((9.00, y, zz + 0.0), (9.28, y + 0.08, zz + 0.09), mat),
              box((9.00, y + 0.09, zz + 0.0), (9.28, y + 0.17, zz + 0.09), mat)]
build("det_shoe_bench", P, COR)

# коврик у входной двери + пара обуви
build("det_doormat", [box((8.72, 1.28, 0), (9.22, 2.12, 0.012), D["mat"]),
                      box((8.85, 1.55, 0.012), (9.12, 1.64, 0.10), D["dark"]),
                      box((8.85, 1.68, 0.012), (9.12, 1.77, 0.10), D["dark"])], COR)

# вешалка с куртками на восточной стене (x=9.25)
P = [box((9.22, 2.45, 1.62), (9.25, 3.45, 1.74), D["wood"])]
for y in (2.60, 2.90, 3.20):
    P.append(box((9.15, y - 0.015, 1.66), (9.22, y + 0.015, 1.69), D["metal"]))
P += [box((9.08, 2.45, 0.95), (9.22, 2.76, 1.66), D["soft_flat"]),
      box((9.10, 2.74, 1.05), (9.22, 3.06, 1.66), D["coat2"]),
      box((9.17, 3.13, 1.30), (9.20, 3.27, 1.66), D["book_r"])]          # шарф/сумка
build("det_coat_rack", P, COR)

# домофон
build("det_intercom", [box((9.23, 2.30, 1.45), (9.25, 2.40, 1.65), D["trim"]),
                       box((9.225, 2.32, 1.55), (9.23, 2.38, 1.62), D["dark"])], COR)

# ======================= КУХНЯ =======================
# плитка на полу (шахматка поверх старого пола)
P = []
tx0, tx1, ty0, ty1, t = 3.46, 5.94, 4.36, 7.25, 0.40
i = 0
x = tx0
while x < tx1 - 1e-6:
    y, j = ty0, 0
    while y < ty1 - 1e-6:
        P.append(box((x, y, 0), (min(x + t, tx1), min(y + t, ty1), 0.004),
                     D["floor_a"] if (i + j) % 2 == 0 else D["floor_b"]))
        y += t; j += 1
    x += t; i += 1
build("det_kitchen_floor", P, KIT)

# нижние шкафы вдоль восточной стены (фасад в -X, x=5.38)
P = [box((5.38, 4.55, 0.10), (5.94, 6.95, 0.82), D["cab"]),
     box((5.42, 4.55, 0), (5.94, 6.95, 0.10), D["dark"]),                # цоколь
     box((5.33, 4.55, 0.82), (5.94, 6.95, 0.86), D["worktop"])]          # столешница
for y in (5.30, 5.90, 6.40):
    P.append(box((5.375, y - 0.005, 0.10), (5.38, y + 0.005, 0.82), D["dark"]))   # щели фасадов
for y0, y1 in ((4.55, 5.30), (5.90, 6.40), (6.40, 6.95)):
    P.append(box((5.375, y0, 0.62), (5.38, y1, 0.63), D["dark"]))        # ящик сверху
    c = (y0 + y1) / 2
    P.append(box((5.355, c - 0.08, 0.71), (5.375, c + 0.08, 0.73), D["metal"]))
    P.append(box((5.355, c - 0.08, 0.52), (5.375, c + 0.08, 0.54), D["metal"]))
# духовка под варочной панелью
P += [box((5.37, 5.33, 0.14), (5.38, 5.87, 0.78), D["appl_flat"]),
      box((5.365, 5.38, 0.24), (5.37, 5.82, 0.60), D["dark"]),
      box((5.33, 5.40, 0.68), (5.365, 5.80, 0.70), D["metal"])]
build("det_kitchen_counter", P, KIT)

# варочная панель + кастрюля
P = [box((5.40, 5.32, 0.86), (5.90, 5.88, 0.87), D["dark"])]
for (x, y) in ((5.52, 5.45), (5.52, 5.75), (5.78, 5.45), (5.78, 5.75)):
    P.append(box((x - 0.07, y - 0.07, 0.87), (x + 0.07, y + 0.07, 0.874), D["metal"]))
P += [box((5.44, 5.66, 0.874), (5.62, 5.84, 1.00), D["metal"]),
      box((5.42, 5.73, 0.97), (5.44, 5.77, 0.99), D["metal"]),
      box((5.62, 5.73, 0.97), (5.64, 5.77, 0.99), D["metal"]),
      box((5.43, 5.65, 1.00), (5.63, 5.85, 1.015), D["metal"])]
build("det_stove", P, KIT)

# мойка + смеситель
build("det_sink", [box((5.43, 6.42, 0.86), (5.86, 6.88, 0.865), D["metal"]),
                   box((5.47, 6.46, 0.850), (5.82, 6.84, 0.867), D["dark"]),
                   box((5.86, 6.61, 0.865), (5.89, 6.64, 1.16), D["metal"]),
                   box((5.70, 6.60, 1.13), (5.89, 6.65, 1.16), D["metal"]),
                   box((5.70, 6.61, 1.08), (5.73, 6.64, 1.13), D["metal"])], KIT)

# микроволновка, чайник, доска
build("det_microwave", [box((5.50, 4.60, 0.86), (5.92, 5.08, 1.14), D["appl_flat"]),
                        box((5.495, 4.64, 0.90), (5.50, 4.94, 1.10), D["dark"]),
                        box((5.495, 4.97, 0.92), (5.50, 5.04, 1.08), D["metal"])], KIT)
build("det_kettle", [box((5.48, 6.02, 0.86), (5.64, 6.18, 1.08), D["metal"]),
                     box((5.52, 6.06, 1.08), (5.60, 6.14, 1.11), D["dark"]),
                     box((5.62, 6.08, 0.93), (5.68, 6.12, 1.05), D["dark"]),
                     box((5.46, 6.00, 0.86), (5.66, 6.20, 0.88), D["dark"])], KIT)
build("det_cutting_board", [box((5.62, 5.95, 0.86), (5.66, 6.30, 1.18), D["wood"])], KIT)

# фартук из плитки
build("det_backsplash", [box((5.925, 4.55, 0.86), (5.94, 6.95, 1.50), D["tile"])], KIT)

# верхние шкафы + вытяжка
P = [box((5.60, 4.80, 1.50), (5.94, 6.60, 2.20), D["cab"])]
for y in (5.25, 5.70, 6.15):
    P.append(box((5.595, y - 0.005, 1.50), (5.60, y + 0.005, 2.20), D["dark"]))
for y in (5.20, 5.30, 6.10, 6.20):
    P.append(box((5.575, y - 0.01, 1.54), (5.595, y + 0.01, 1.70), D["metal"]))
P.append(box((5.52, 5.33, 1.40), (5.94, 5.87, 1.50), D["metal"]))       # вытяжка
build("det_upper_cabinets", P, KIT)

# холодильник (фасад в -Y, y=6.70)
P = [box((3.50, 6.70, 0), (4.10, 7.25, 1.85), D["appl_flat"]),
     box((3.51, 6.695, 1.13), (4.09, 6.70, 1.14), D["dark"]),
     box((3.56, 6.65, 0.75), (3.59, 6.695, 1.08), D["metal"]),
     box((3.56, 6.65, 1.20), (3.59, 6.695, 1.45), D["metal"]),
     box((3.75, 6.697, 1.30), (3.86, 6.70, 1.44), D["paper_flat"]),     # записки/магниты
     box((3.90, 6.697, 1.22), (3.98, 6.70, 1.32), D["art2"]),
     box((3.55, 6.80, 1.85), (3.85, 7.15, 2.05), D["closet_flat"])]      # коробка сверху
build("det_fridge", P, KIT)

# стол
P = [box((3.90, 5.00, 0.72), (4.90, 5.70, 0.75), D["table_flat"])]
for x in (3.94, 4.81):
    for y in (5.04, 5.61):
        P.append(box((x, y, 0), (x + 0.05, y + 0.05, 0.72), D["table_flat"]))
build("det_kitchen_table", P, KIT)

def chair_parts(cx, cy, back_dir):
    """Деревянный стул; back_dir: -1 спинка со стороны -Y, +1 со стороны +Y."""
    P = [box((cx - 0.20, cy - 0.20, 0.43), (cx + 0.20, cy + 0.20, 0.47), D["wood"])]
    for dx in (-0.18, 0.15):
        for dy in (-0.18, 0.15):
            P.append(box((cx + dx, cy + dy, 0), (cx + dx + 0.03, cy + dy + 0.03, 0.43), D["wood"]))
    by = cy + back_dir * 0.185
    for dx in (-0.18, 0.15):
        P.append(box((cx + dx, by - 0.015, 0.47), (cx + dx + 0.03, by + 0.015, 0.92), D["wood"]))
    P += [box((cx - 0.18, by - 0.015, 0.80), (cx + 0.18, by + 0.015, 0.92), D["wood"]),
          box((cx - 0.18, by - 0.012, 0.60), (cx + 0.18, by + 0.012, 0.65), D["wood"])]
    return P

build("det_kitchen_chair_1", chair_parts(4.40, 4.72, -1), KIT)
build("det_kitchen_chair_2", chair_parts(4.40, 5.98, +1), KIT)
# третий стул чуть отодвинут и развёрнут
P = chair_parts(3.70, 5.35, -1)
c = Vector((3.70, 5.35, 0)); a = math.radians(-70); ca, sa = math.cos(a), math.sin(a)
P = [([Vector((c.x + (v.x - c.x) * ca - (v.y - c.y) * sa, c.y + (v.x - c.x) * sa + (v.y - c.y) * ca, v.z))
       for v in vs], fs, m) for vs, fs, m in P]
build("det_kitchen_chair_3", P, KIT)

# на столе: ваза с фруктами, кружки, тарелка
P = [box((4.30, 5.24, 0.75), (4.52, 5.46, 0.81), D["paper_flat"]),
     box((4.33, 5.27, 0.81), (4.39, 5.33, 0.87), D["fruit"]),
     box((4.42, 5.30, 0.81), (4.48, 5.36, 0.87), D["apple"]),
     box((4.36, 5.37, 0.81), (4.42, 5.43, 0.86), D["book_g"]),
     box((4.62, 5.10, 0.75), (4.69, 5.17, 0.84), D["art1"]),
     box((4.05, 5.48, 0.75), (4.12, 5.55, 0.84), D["paper_flat"]),
     box((4.60, 5.42, 0.75), (4.82, 5.62, 0.758), D["paper_flat"])]
build("det_table_items", P, KIT)

# подвесная лампа над столом
build("det_pendant_lamp", [box((4.39, 5.34, 2.08), (4.41, 5.36, 2.70), D["dark"]),
                           box((4.28, 5.23, 1.95), (4.52, 5.47, 2.08), D["dark"]),
                           box((4.29, 5.24, 1.945), (4.51, 5.46, 1.95), D["lampshade"])], KIT)

# подоконник, рулонная штора, травы на подоконнике
P = [box((4.05, 7.08, 0.86), (5.35, 7.26, 0.90), D["trim"]),
     box((4.10, 7.19, 1.70), (5.30, 7.23, 2.20), D["blind_flat"]),
     box((4.10, 7.18, 1.68), (5.30, 7.24, 1.70), D["trim"])]
for x in (4.25, 4.45, 4.65):
    P += [box((x - 0.06, 7.10, 0.90), (x + 0.06, 7.22, 1.02), D["pot"]),
          box((x - 0.05, 7.12, 1.02), (x + 0.05, 7.20, 1.12), D["plant"])]
build("det_kitchen_window", P, KIT)

# настенные часы над столом (западная стена x=3.46)
build("det_wall_clock", [box((3.46, 5.20, 1.85), (3.49, 5.50, 2.15), D["dark"]),
                         box((3.49, 5.23, 1.88), (3.495, 5.47, 2.12), D["paper_flat"]),
                         box((3.495, 5.345, 2.00), (3.50, 5.355, 2.10), D["dark"]),
                         box((3.495, 5.35, 1.995), (3.50, 5.42, 2.005), D["dark"])], KIT)

print("corridor_detail:", len(COR.objects), " kitchen_detail:", len(KIT.objects))
