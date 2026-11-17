"""
Детализация оставшихся комнат: комната соседки (светло-розовая, 2 монитора, системник под столом),
ванная, туалет, гостиная. Запускать после detail_hero_room.py и detail_corridor_kitchen.py.

Запуск: apartment_detail.blend -> вкладка Scripting -> Open этот файл -> Run Script.
Заменённые кубики уходят в скрытую коллекцию "blockout_old". Новое: коллекции
"mate_room_detail", "bath_wc_detail", "living_detail". Повторный запуск безопасен.
"""
import bpy, math
from mathutils import Vector

# ======================= helpers (те же, что в detail_hero_room.py) =======================
def flat(name, rgb, strength=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True  # цвет обновляется и при повторном запуске
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


# ======================= доп. helpers =======================
def rotate_parts(parts, deg, pivot):
    a = math.radians(deg); ca, sa = math.cos(a), math.sin(a); c = Vector(pivot)
    return [([Vector((c.x + (v.x - c.x) * ca - (v.y - c.y) * sa,
                      c.y + (v.x - c.x) * sa + (v.y - c.y) * ca, v.z)) for v in vs], fs, m)
            for vs, fs, m in parts]

def checker(x0, x1, y0, y1, t, ma, mb, z=0.004):
    P, i, x = [], 0, x0
    while x < x1 - 1e-6:
        y, j = y0, 0
        while y < y1 - 1e-6:
            P.append(box((x, y, 0), (min(x + t, x1), min(y + t, y1), z), ma if (i + j) % 2 == 0 else mb))
            y += t; j += 1
        x += t; i += 1
    return P

def wall_x(face, side, a0, a1, z0, z1, mat, holes=(), d=0.006):
    """Покрытие стены вдоль X (плоскость y=face, side=+1 в комнату к +Y) с проёмами (a0,a1,z0,z1)."""
    y0, y1 = min(face, face + side * d), max(face, face + side * d)
    rects = [(a0, a1, z0, z1)]
    for hx0, hx1, hz0, hz1 in holes:
        nr = []
        for rx0, rx1, rz0, rz1 in rects:
            if hx1 <= rx0 or hx0 >= rx1 or hz1 <= rz0 or hz0 >= rz1:
                nr.append((rx0, rx1, rz0, rz1)); continue
            if hx0 > rx0: nr.append((rx0, hx0, rz0, rz1))
            if hx1 < rx1: nr.append((hx1, rx1, rz0, rz1))
            cx0, cx1 = max(rx0, hx0), min(rx1, hx1)
            if hz0 > rz0: nr.append((cx0, cx1, rz0, hz0))
            if hz1 < rz1: nr.append((cx0, cx1, hz1, rz1))
        rects = nr
    return [box((x0, y0, zz0), (x1, y1, zz1), mat) for x0, x1, zz0, zz1 in rects]

def wall_y(face, side, a0, a1, z0, z1, mat, holes=(), d=0.006):
    """То же для стены вдоль Y (плоскость x=face)."""
    return swap_xy(wall_x(face, side, a0, a1, z0, z1, mat, holes, d))

def office_chair(cx, cy, turn, seat, back, base):
    P = []
    for i in range(5):
        a = i * 72 + 18
        P.append(box((cx, cy - 0.02, 0.04), (cx + 0.30, cy + 0.02, 0.07), base, rot_z=a, pivot=(cx, cy)))
        ex, ey = cx + 0.28 * math.cos(math.radians(a)), cy + 0.28 * math.sin(math.radians(a))
        P.append(box((ex - 0.025, ey - 0.025, 0), (ex + 0.025, ey + 0.025, 0.04), base))
    P += [box((cx - 0.025, cy - 0.025, 0.07), (cx + 0.025, cy + 0.025, 0.42), D["metal"]),
          box((cx - 0.25, cy - 0.24, 0.42), (cx + 0.25, cy + 0.24, 0.51), seat),
          box((cx - 0.03, cy + 0.22, 0.44), (cx + 0.03, cy + 0.27, 0.60), base),
          box((cx - 0.24, cy + 0.24, 0.56), (cx + 0.24, cy + 0.32, 1.22), back),      # высокая спинка
          box((cx - 0.15, cy + 0.235, 1.05), (cx + 0.15, cy + 0.24, 1.18), seat),     # подголовник
          box((cx - 0.16, cy + 0.235, 0.62), (cx + 0.16, cy + 0.24, 0.98), seat)]     # вставка
    for sx in (-1, 1):
        x = cx + sx * 0.245
        P.append(box((x - 0.015, cy - 0.02, 0.51), (x + 0.015, cy + 0.02, 0.67), base))
        P.append(box((x - 0.03, cy - 0.12, 0.67), (x + 0.03, cy + 0.14, 0.70), base))
    return rotate_parts(P, turn, (cx, cy))

# ======================= материалы (новые) =======================
D["pink_wall"] = flat("pink_wall_flat", (0.80, 0.58, 0.65))
D["pink"] = flat("pink_flat", (0.80, 0.38, 0.55))
D["pink_soft"] = flat("pink_soft_flat", (0.90, 0.72, 0.77))
D["white"] = flat("white_furn_flat", (0.92, 0.91, 0.90))
D["rgb"] = flat("rgb_pink_flat", (1.0, 0.35, 0.75), 2.0)
D["screen2"] = flat("screen_purple_flat", (0.55, 0.50, 0.80))
D["screen"] = bpy.data.materials["screen_flat"]
D["plumb"] = bpy.data.materials["plumb_flat"]
D["window"] = bpy.data.materials["window_flat"]
D["bed"] = bpy.data.materials["bed_flat"]
D["btile"] = flat("bath_tile_flat", (0.50, 0.66, 0.70))
D["btile2"] = flat("bath_tile_border_flat", (0.35, 0.50, 0.56))
D["bfloor_a"] = flat("bath_floor_a_flat", (0.42, 0.43, 0.44))
D["bfloor_b"] = flat("bath_floor_b_flat", (0.28, 0.29, 0.30))
D["water"] = flat("water_flat", (0.55, 0.72, 0.80))
D["towel"] = flat("towel_flat", (0.85, 0.62, 0.38))
D["towel2"] = flat("towel_blue_flat", (0.35, 0.50, 0.70))
D["curtain"] = flat("curtain_flat", (0.62, 0.55, 0.48))
D["sofa"] = bpy.data.materials["soft_flat"]
D["sofa2"] = flat("sofa_cushion_flat", (0.40, 0.38, 0.48))
D["lrug"] = flat("living_rug_flat", (0.55, 0.45, 0.35))
D["lrug2"] = flat("living_rug_inner_flat", (0.45, 0.35, 0.28))

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

MATE = fresh_collection("mate_room_detail")
BATH = fresh_collection("bath_wc_detail")
LIV = fresh_collection("living_detail")

for n in ["mate_bed", "mate_closet", "mate_desk", "mate_shelf",
          "bath_sink", "bath_tub", "bath_washer", "wc_pan",
          "liv_coffee", "liv_shelf", "liv_sofa", "liv_tv", "liv_tvstand"]:
    ob = bpy.data.objects.get(n)
    if ob and old not in ob.users_collection:
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        old.objects.link(ob)

# ======================= КОМНАТА СОСЕДКИ (x 3.66..7.34, y 0.15..2.94) =======================
# светло-розовые стены (тонкие панели поверх общих стен) + плинтус
P = []
P += wall_x(0.15, +1, 3.66, 7.34, 0, 2.70, D["pink_wall"], holes=[(4.80, 6.20, 0.90, 2.20)])  # юг, окно
P += wall_x(2.94, -1, 3.66, 7.34, 0, 2.70, D["pink_wall"], holes=[(5.13, 6.17, 0, 2.17)])     # север, дверь
P += wall_y(3.66, +1, 0.15, 2.94, 0, 2.70, D["pink_wall"])                                    # запад
P += wall_y(7.34, -1, 0.15, 2.94, 0, 2.70, D["pink_wall"])                                    # восток
P += wall_x(0.156, +1, 3.66, 7.34, 0, 0.07, D["white"], holes=[(4.80, 6.20, 0, 0.9)], d=0.012)
P += wall_y(3.666, +1, 0.15, 2.94, 0, 0.07, D["white"], d=0.012)
P += wall_y(7.334, -1, 0.15, 2.94, 0, 0.07, D["white"], d=0.012)
build("det_mate_walls", P, MATE)
build("det_mate_ceiling", [box((3.66, 0.15, 2.69), (7.34, 2.94, 2.695), D["pink_wall"])], MATE)

# стол у окна (белый), коврик для мыши, два монитора, системник ПОД столом
P = [box((5.00, 0.18, 0.72), (6.20, 0.80, 0.75), D["white"])]
for x in (5.02, 6.14):
    for y in (0.20, 0.74):
        P.append(box((x, y, 0), (x + 0.04, y + 0.04, 0.72), D["white"]))
P.append(box((5.02, 0.20, 0.55), (6.18, 0.22, 0.72), D["white"]))          # задняя царга
build("det_mate_desk", P, MATE)
build("det_mate_deskmat", [box((5.15, 0.48, 0.75), (6.05, 0.78, 0.753), D["pink"])], MATE)

def monitor(x0, x1, turn, pivot):
    cx = (x0 + x1) / 2
    P = [box((cx - 0.10, 0.24, 0.75), (cx + 0.10, 0.40, 0.765), D["white"]),
         box((cx - 0.02, 0.24, 0.765), (cx + 0.02, 0.27, 0.95), D["white"]),
         box((x0, 0.27, 0.90), (x1, 0.31, 1.24), D["white"]),
         box((x0 + 0.02, 0.31, 0.92), (x1 - 0.02, 0.315, 1.22), D["screen"] if turn > 0 else D["screen2"])]
    return rotate_parts(P, turn, pivot)
build("det_mate_monitor_l", monitor(5.04, 5.59, 12, (5.59, 0.30)), MATE)
build("det_mate_monitor_r", monitor(5.61, 6.16, -12, (5.61, 0.30)), MATE)
build("det_mate_keyboard", [box((5.35, 0.55, 0.753), (5.80, 0.69, 0.773), D["white"]),
                            box((5.36, 0.56, 0.773), (5.79, 0.68, 0.777), D["pink_soft"])], MATE)
build("det_mate_mouse", [box((5.90, 0.58, 0.753), (5.96, 0.67, 0.783), D["white"])], MATE)
build("det_mate_headphones", [box((6.02, 0.30, 0.75), (6.12, 0.40, 0.76), D["white"]),
                              box((6.065, 0.34, 0.76), (6.075, 0.36, 1.00), D["white"]),
                              box((6.01, 0.33, 0.88), (6.03, 0.37, 1.02), D["pink"]),
                              box((6.11, 0.33, 0.88), (6.13, 0.37, 1.02), D["pink"]),
                              box((6.02, 0.335, 1.00), (6.12, 0.365, 1.03), D["pink"])], MATE)
# системник под столом слева: белый корпус, розовая подсветка через стеклянный бок
P = [box((5.07, 0.24, 0.02), (5.29, 0.69, 0.47), D["white"]),
     box((5.29, 0.27, 0.06), (5.295, 0.66, 0.43), D["rgb"]),                  # стекло с RGB (смотрит в комнату)
     box((5.09, 0.69, 0.40), (5.27, 0.695, 0.415), D["rgb"])]                 # полоска спереди
for x in (5.08, 5.25):
    for y in (0.26, 0.64):
        P.append(box((x, y, 0), (x + 0.03, y + 0.03, 0.02), D["dark"]))
build("det_mate_pc_tower", P, MATE)

# игровое кресло (розово-белое), развёрнуто к комнате
build("det_mate_chair", office_chair(5.62, 1.12, -20, D["white"], D["pink"], D["dark"]), MATE)

# кровать у западной стены, изголовье у южной стены
P = [box((3.70, 0.33, 0.06), (4.60, 2.30, 0.28), D["white"]),
     box((3.73, 0.36, 0.28), (4.57, 2.27, 0.46), D["bed"]),
     box((3.705, 0.95, 0.22), (4.595, 2.30, 0.50), D["pink"]),                # одеяло
     box((3.70, 0.28, 0), (4.60, 0.33, 0.95), D["white"]),                     # изголовье
     box((3.75, 0.38, 0.46), (4.15, 0.68, 0.60), D["pink_soft"]),              # подушки
     box((4.18, 0.38, 0.46), (4.55, 0.68, 0.59), D["paper_flat"]),
     box((4.30, 0.75, 0.50), (4.48, 0.90, 0.72), D["pink_soft"]),              # плюшевая игрушка
     box((4.33, 0.78, 0.72), (4.45, 0.88, 0.82), D["pink_soft"]),
     box((4.32, 0.80, 0.82), (4.35, 0.84, 0.86), D["pink"]),
     box((4.43, 0.80, 0.82), (4.46, 0.84, 0.86), D["pink"])]
for y in (0.36, 2.24):
    for x in (3.71, 4.55):
        P.append(box((x, y, 0), (x + 0.04, y + 0.04, 0.06), D["white"]))
build("det_mate_bed", P, MATE)

# полка над кроватью на западной стене (раньше висела на окне)
P = [box((3.66, 0.90, 1.45), (3.90, 2.00, 1.475), D["white"])]
for y in (1.00, 1.88):
    P.append(box((3.66, y, 1.32), (3.70, y + 0.03, 1.45), D["white"]))
y = 0.95
for i, h in enumerate((0.20, 0.23, 0.18, 0.22, 0.19)):
    P.append(box((3.68, y, 1.475), (3.86, y + 0.035, 1.475 + h), (D["pink"], D["book_y"], D["art1"], D["pink_soft"], D["book_g"])[i]))
    y += 0.04
P += [box((3.70, 1.40, 1.475), (3.84, 1.54, 1.60), D["pot"]),
      box((3.73, 1.43, 1.60), (3.81, 1.51, 1.72), D["plant"]),
      box((3.70, 1.70, 1.475), (3.84, 1.84, 1.66), D["white"]),             # фигурка/шкатулка
      box((3.72, 1.72, 1.66), (3.82, 1.82, 1.70), D["pink"])]
build("det_mate_shelf", P, MATE)

# шкаф у восточной стены (фасад в -X, x=6.85)
P = [box((6.85, 0.30, 0.06), (7.34, 1.50, 2.10), D["white"]),
     box((6.87, 0.32, 0), (7.32, 1.48, 0.06), D["pink"]),
     box((6.845, 0.895, 0.08), (6.85, 0.905, 2.08), D["dark"])]
for y in (0.84, 0.94):
    P.append(box((6.825, y, 0.95), (6.845, y + 0.02, 1.25), D["pink"]))
build("det_mate_closet", P, MATE)

# шторы, подоконник, коврик, постеры, гирлянда
P = [box((4.55, 0.17, 2.30), (6.45, 0.21, 2.33), D["white"]),               # карниз
     box((4.58, 0.19, 0.25), (4.86, 0.25, 2.30), D["pink_soft"]),
     box((6.14, 0.19, 0.25), (6.42, 0.25, 2.30), D["pink_soft"]),
     box((4.78, 0.15, 0.86), (6.22, 0.30, 0.90), D["white"])]              # подоконник
build("det_mate_curtains", P, MATE)
build("det_mate_rug", [box((4.85, 1.45, 0), (6.35, 2.45, 0.010), D["pink_soft"]),
                       box((4.95, 1.55, 0.010), (6.25, 2.35, 0.013), D["pink"])], MATE)
build("det_mate_posters", [box((3.90, 0.156, 1.25), (4.55, 0.166, 2.00), D["art1"]),
                           box((3.95, 0.166, 1.30), (4.50, 0.170, 1.95), D["pink"]),
                           box((4.05, 0.170, 1.45), (4.40, 0.172, 1.80), D["paper_flat"]),
                           box((6.30, 0.156, 1.35), (6.75, 0.166, 1.85), D["screen2"])], MATE)
P = []
for i in range(14):  # гирлянда-огоньки под потолком вдоль южной и западной стены
    x = 3.80 + i * 0.25
    P.append(box((x - 0.02, 0.17, 2.52 + 0.04 * math.sin(i * 1.3)), (x + 0.02, 0.21, 2.56 + 0.04 * math.sin(i * 1.3)), D["lampshade"]))
for i in range(10):
    y = 0.40 + i * 0.25
    P.append(box((3.68, y - 0.02, 2.52 + 0.04 * math.sin(i * 1.7)), (3.72, y + 0.02, 2.56 + 0.04 * math.sin(i * 1.7)), D["lampshade"]))
build("det_mate_fairy_lights", P, MATE)

# ======================= ВАННАЯ (x 0.15..2.34, y 0.15..2.94) =======================
P = []
P += wall_y(0.15, +1, 0.15, 2.94, 0, 1.50, D["btile"])
P += wall_x(0.15, +1, 0.15, 2.34, 0, 1.50, D["btile"])
P += wall_y(2.34, -1, 0.15, 2.94, 0, 1.50, D["btile"])
P += wall_x(2.94, -1, 0.15, 2.34, 0, 1.50, D["btile"], holes=[(0.83, 1.87, 0, 2.17)])
P += wall_y(0.156, +1, 0.15, 2.94, 1.50, 1.56, D["btile2"])
P += wall_x(0.156, +1, 0.15, 2.34, 1.50, 1.56, D["btile2"])
P += wall_y(2.334, -1, 0.15, 2.94, 1.50, 1.56, D["btile2"])
P += checker(0.15, 2.34, 0.15, 2.94, 0.30, D["bfloor_a"], D["bfloor_b"])
build("det_bath_tiles", P, BATH)

# ванна + шторка + душ
P = [box((0.15, 0.20, 0), (0.85, 1.90, 0.55), D["plumb"]),
     box((0.21, 0.26, 0.40), (0.79, 1.84, 0.556), D["water"])]                 # вода
P += [box((0.15, 0.30, 0.70), (0.19, 0.36, 0.76), D["metal"]),             # смеситель
      box((0.19, 0.32, 0.72), (0.30, 0.34, 0.74), D["metal"]),
      box((0.15, 0.32, 0.76), (0.17, 0.34, 1.90), D["metal"]),             # штанга душа
      box((0.15, 0.27, 1.88), (0.28, 0.39, 1.92), D["metal"]),             # лейка
      box((0.85, 0.20, 2.00), (0.87, 1.90, 2.02), D["metal"]),             # карниз шторки
      box((0.84, 0.20, 0.60), (0.87, 0.95, 2.00), D["towel2"])]            # шторка (сдвинута)
build("det_bath_tub", P, BATH)

# раковина с тумбой + зеркало + полочка
P = [box((1.00, 0.15, 0.10), (1.55, 0.55, 0.78), D["white"]),
     box((1.02, 0.17, 0), (1.53, 0.53, 0.10), D["dark"]),
     box((1.275, 0.55, 0.12), (1.28, 0.555, 0.76), D["dark"]),
     box((1.22, 0.555, 0.60), (1.24, 0.575, 0.70), D["metal"]),
     box((1.31, 0.555, 0.60), (1.33, 0.575, 0.70), D["metal"]),
     box((0.98, 0.15, 0.78), (1.57, 0.57, 0.84), D["plumb"]),
     box((1.06, 0.22, 0.79), (1.49, 0.50, 0.841), D["metal"]),
     box((1.26, 0.16, 0.84), (1.30, 0.20, 1.00), D["metal"]),
     box((1.26, 0.20, 0.96), (1.30, 0.30, 0.99), D["metal"])]
build("det_bath_sink", P, BATH)
build("det_bath_mirror", [box((1.02, 0.15, 1.10), (1.53, 0.17, 1.80), D["trim"]),
                          box((1.05, 0.17, 1.13), (1.50, 0.175, 1.77), D["mirror"]),
                          box((1.02, 0.15, 1.00), (1.53, 0.27, 1.02), D["plumb"]),
                          box((1.06, 0.18, 1.02), (1.11, 0.23, 1.17), D["pink"]),
                          box((1.14, 0.18, 1.02), (1.18, 0.22, 1.12), D["art1"]),
                          box((1.42, 0.18, 1.02), (1.48, 0.24, 1.10), D["paper_flat"])], BATH)

# стиралка (фасад в +Y)
build("det_bath_washer", [box((1.72, 0.15, 0), (2.32, 0.75, 0.85), D["appl_flat"]),
                          box((1.74, 0.75, 0.70), (2.30, 0.755, 0.83), D["metal"]),
                          box((1.80, 0.755, 0.74), (1.98, 0.76, 0.79), D["dark"]),
                          box((1.82, 0.75, 0.18), (2.22, 0.755, 0.58), D["metal"]),
                          box((1.86, 0.755, 0.22), (2.18, 0.76, 0.54), D["dark"]),
                          box((1.90, 0.76, 0.26), (2.14, 0.762, 0.50), D["water"])], BATH)

# полотенцесушитель с полотенцами, коврик, корзина для белья
P = [box((2.30, 1.30, 0.80), (2.34, 1.33, 1.50), D["metal"]),
     box((2.30, 1.87, 0.80), (2.34, 1.90, 1.50), D["metal"])]
for z in (0.85, 1.05, 1.25, 1.45):
    P.append(box((2.28, 1.30, z), (2.31, 1.90, z + 0.025), D["metal"]))
P += [box((2.24, 1.35, 1.00), (2.29, 1.85, 1.48), D["towel"]),
      box((2.25, 1.40, 0.82), (2.29, 1.80, 1.06), D["towel2"])]
build("det_bath_towel_rail", P, BATH)
build("det_bath_mat", [box((0.95, 0.70, 0.004), (1.50, 1.10, 0.02), D["towel2"])], BATH)
build("det_bath_basket", [box((1.85, 2.40, 0), (2.25, 2.80, 0.55), D["wood"]),
                          box((1.88, 2.43, 0.55), (2.22, 2.77, 0.57), D["towel"])], BATH)
build("det_bath_lamp", [box((1.10, 1.40, 2.66), (1.40, 1.70, 2.70), D["trim"]),
                        box((1.12, 1.42, 2.645), (1.38, 1.68, 2.66), D["lampshade"])], BATH)

# ======================= ТУАЛЕТ (x 2.46..3.54, y 0.15..2.94) =======================
# унитаз перенесён к дальней (южной) стене: в блокауте стоял вплотную к двери
P = []
P += wall_y(2.46, +1, 0.15, 2.94, 0, 1.50, D["btile"])
P += wall_y(3.54, -1, 0.15, 2.94, 0, 1.50, D["btile"])
P += wall_x(0.15, +1, 2.46, 3.54, 0, 1.50, D["btile"])
P += wall_x(2.94, -1, 2.46, 3.54, 0, 1.50, D["btile"], holes=[(2.63, 3.47, 0, 2.17)])
P += wall_y(2.466, +1, 0.15, 2.94, 1.50, 1.56, D["btile2"])
P += wall_y(3.534, -1, 0.15, 2.94, 1.50, 1.56, D["btile2"])
P += wall_x(0.156, +1, 2.46, 3.54, 1.50, 1.56, D["btile2"])
P += checker(2.46, 3.54, 0.15, 2.94, 0.30, D["bfloor_a"], D["bfloor_b"])
build("det_wc_tiles", P, BATH)
build("det_wc_toilet", [box((2.82, 0.30, 0), (3.18, 0.62, 0.38), D["plumb"]),       # основание
                        box((2.80, 0.28, 0.38), (3.20, 0.86, 0.42), D["plumb"]),    # чаша
                        box((2.82, 0.30, 0.42), (3.18, 0.84, 0.44), D["white"]),    # сиденье
                        box((2.79, 0.16, 0.42), (3.21, 0.34, 0.85), D["plumb"]),    # бачок
                        box((2.80, 0.17, 0.85), (3.20, 0.33, 0.88), D["white"]),
                        box((2.97, 0.22, 0.88), (3.03, 0.28, 0.89), D["metal"])], BATH)
build("det_wc_extras", [box((3.50, 0.95, 0.70), (3.54, 1.05, 0.73), D["metal"]),      # держатель бумаги
                        box((3.44, 0.96, 0.62), (3.52, 1.04, 0.74), D["paper_flat"]),
                        box((2.50, 0.15, 1.40), (3.50, 0.35, 1.43), D["plumb"]),       # полочка
                        box((2.60, 0.18, 1.43), (2.75, 0.32, 1.60), D["paper_flat"]),
                        box((2.80, 0.18, 1.43), (2.95, 0.32, 1.60), D["paper_flat"]),
                        box((3.30, 0.20, 1.43), (3.38, 0.28, 1.58), D["book_g"]),
                        box((3.40, 0.40, 0), (3.52, 0.52, 0.45), D["metal"]),          # ёршик
                        box((2.55, 2.40, 0), (2.80, 2.60, 0.30), D["dark"]),           # ведро
                        box((2.85, 1.40, 2.66), (3.15, 1.70, 2.70), D["trim"]),
                        box((2.87, 1.42, 2.645), (3.13, 1.68, 2.66), D["lampshade"])], BATH)

# ======================= ГОСТИНАЯ (x 6.06..9.25, y 4.36..7.25) =======================
# диван спинкой к южной стене, лицом к ТВ на севере
P = [box((6.30, 4.45, 0.08), (8.30, 5.30, 0.40), D["sofa"]),
     box((6.30, 4.45, 0.40), (8.30, 4.70, 0.85), D["sofa"]),                 # спинка
     box((6.30, 4.45, 0.40), (6.48, 5.30, 0.62), D["sofa"]),                 # подлокотники
     box((8.12, 4.45, 0.40), (8.30, 5.30, 0.62), D["sofa"])]
for x0, x1 in ((6.48, 7.29), (7.31, 8.12)):
    P += [box((x0, 4.70, 0.40), (x1, 5.28, 0.50), D["sofa2"]),             # сиденья
          box((x0, 4.62, 0.50), (x1, 4.80, 0.82), D["sofa2"])]             # спинные подушки
P += [box((6.52, 4.80, 0.50), (6.80, 4.90, 0.75), D["art2"], rot_z=10),   # декоративные подушки
      box((7.85, 4.80, 0.50), (8.10, 4.90, 0.73), D["art1"], rot_z=-12),
      box((6.75, 4.70, 0.50), (7.10, 5.05, 0.53), D["towel2"])]             # плед
for x in (6.32, 8.24):
    for y in (4.47, 5.24):
        P.append(box((x, y, 0), (x + 0.04, y + 0.04, 0.08), D["dark"]))
build("det_liv_sofa", P, LIV)

# журнальный столик + мелочи, ковёр
P = [box((6.90, 5.60, 0.38), (7.80, 6.10, 0.42), D["wood"])]
for x in (6.93, 7.73):
    for y in (5.63, 6.03):
        P.append(box((x, y, 0), (x + 0.04, y + 0.04, 0.38), D["wood"]))
P += [box((6.95, 5.65, 0.12), (7.75, 6.05, 0.14), D["wood"]),
      box((7.00, 5.70, 0.42), (7.25, 5.88, 0.44), D["book_r"]),
      box((7.45, 5.75, 0.42), (7.52, 5.82, 0.52), D["paper_flat"]),
      box((7.55, 5.90, 0.42), (7.70, 5.95, 0.44), D["dark"])]                # пульт
build("det_liv_coffee_table", P, LIV)
build("det_liv_rug", [box((6.55, 5.40, 0), (8.15, 6.45, 0.010), D["lrug"]),
                      box((6.65, 5.50, 0.010), (8.05, 6.35, 0.013), D["lrug2"])], LIV)

# ТВ-тумба и телевизор
P = [box((6.60, 7.05, 0.06), (8.20, 7.25, 0.50), D["shelf_flat"]),
     box((6.62, 7.07, 0), (8.18, 7.23, 0.06), D["dark"])]
for x in (7.13, 7.67):
    P.append(box((x - 0.005, 7.045, 0.08), (x + 0.005, 7.05, 0.48), D["dark"]))
P += [box((7.15, 7.045, 0.08), (7.65, 7.05, 0.48), D["dark"]),              # открытая ниша
      box((7.20, 7.10, 0.10), (7.48, 7.22, 0.16), D["worktop"]),            # приставка
      box((6.70, 7.10, 0.50), (6.84, 7.20, 0.80), D["pot"]),                # ваза
      box((8.00, 7.10, 0.50), (8.12, 7.20, 0.70), D["paper_flat"])]
build("det_liv_tv_stand", P, LIV)
build("det_liv_tv", [box((7.30, 7.08, 0.50), (7.50, 7.20, 0.52), D["dark"]),
                     box((7.38, 7.16, 0.52), (7.42, 7.19, 0.62), D["dark"]),
                     box((6.95, 7.14, 0.58), (7.85, 7.18, 1.10), D["dark"]),
                     box((6.97, 7.135, 0.60), (7.83, 7.14, 1.08), D["screen"])], LIV)

# стеллаж у восточной стены (фасад в -X, x=8.90)
P = [box((8.90, 4.50, 0), (9.25, 4.53, 1.90), D["wood"]),
     box((8.90, 5.47, 0), (9.25, 5.50, 1.90), D["wood"]),
     box((9.22, 4.53, 0), (9.25, 5.47, 1.90), D["wood"])]
for z in (0.0, 0.45, 0.90, 1.35, 1.87):
    P.append(box((8.90, 4.53, z), (9.25, 5.47, z + 0.03), D["wood"]))
y = 4.56
for i, h in enumerate((0.30, 0.26, 0.33, 0.28, 0.24, 0.31, 0.27, 0.29)):
    P.append(box((8.94, y, 0.93), (9.20, y + 0.045, 0.93 + h), (D["book_r"], D["book_g"], D["book_y"], D["art1"])[i % 4]))
    y += 0.05
P += [box((8.95, 4.60, 0.03), (9.20, 4.95, 0.33), D["closet_flat"]),
      box((8.95, 5.05, 0.03), (9.20, 5.42, 0.30), D["paper_flat"]),
      box((8.96, 5.10, 0.93), (9.18, 5.35, 1.08), D["pot"]),
      box((9.00, 5.15, 1.08), (9.14, 5.30, 1.25), D["plant"]),
      box((8.95, 4.60, 1.38), (9.20, 4.80, 1.60), D["art2"]),
      box((8.95, 4.95, 1.38), (9.18, 5.40, 1.46), D["book_y"]),
      box((8.97, 5.00, 0.48), (9.18, 5.40, 0.75), D["dark"])]               # колонка/проигрыватель
build("det_liv_bookcase", P, LIV)

# торшер у дивана, большое растение, шторы на северном окне, люстра, картина
build("det_liv_floor_lamp", [box((8.40, 4.55, 0), (8.62, 4.77, 0.03), D["dark"]),
                             box((8.50, 4.65, 0.03), (8.52, 4.67, 1.45), D["dark"]),
                             box((8.36, 4.51, 1.40), (8.66, 4.81, 1.65), D["lampshade"])], LIV)
P = [box((6.15, 6.85, 0), (6.45, 7.15, 0.35), D["pot"])]
for k, (ang, h) in enumerate(((0, 1.30), (40, 1.10), (-50, 1.20), (95, 0.95), (140, 1.05), (-120, 0.90))):
    P.append(box((6.24, 6.995, 0.35), (6.36 + 0.10, 7.005, 0.35 + h), D["plant"] if k % 2 else D["book_g"],
                 rot_z=ang, pivot=(6.30, 7.00)))
build("det_liv_big_plant", P, LIV)
build("det_liv_curtains", [box((6.80, 7.10, 2.30), (8.80, 7.14, 2.33), D["dark"]),
                           box((6.82, 7.12, 0.05), (7.10, 7.20, 2.30), D["curtain"]),
                           box((8.50, 7.12, 0.05), (8.78, 7.20, 2.30), D["curtain"])], LIV)
build("det_liv_ceiling_lamp", [box((7.25, 5.65, 2.55), (7.35, 5.75, 2.70), D["dark"]),
                               box((7.05, 5.45, 2.45), (7.55, 5.95, 2.55), D["lampshade"])], LIV)
build("det_liv_picture", [box((6.06, 4.85, 1.20), (6.09, 6.05, 1.90), D["dark"]),
                          box((6.09, 4.90, 1.25), (6.095, 6.00, 1.85), D["paper_flat"]),
                          box((6.095, 5.00, 1.35), (6.10, 5.60, 1.70), D["art1"]),
                          box((6.095, 5.40, 1.30), (6.10, 5.90, 1.55), D["art2"])], LIV)

# ======================= Камера для туалета (раньше не было) =======================
def look_at_cam(name, loc, target, lens):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        scene.collection.objects.link(cam)
    cam.data.lens = lens
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return cam
look_at_cam("wc", (3.00, 2.85, 1.55), (3.00, 0.40, 0.75), 20)

print("mate:", len(MATE.objects), " bath/wc:", len(BATH.objects), " living:", len(LIV.objects))
