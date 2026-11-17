"""
Заменяет кубики главной комнаты (hero_*) на узнаваемые low-poly прокси:
стол на ножках с тумбой, офисный стул, монитор на подставке, клавиатура,
кровать с изголовьем и одеялом, шкаф с дверцами и ручками, жалюзи и т.д.

Запуск: открыть apartment.blend -> вкладка Scripting -> Open этот файл -> Run Script.
Старые кубики не удаляются: они уходят в скрытую коллекцию "blockout_old".
Каждый предмет - один объект с origin внизу по центру, его удобно двигать руками.
Повторный запуск безопасен: сначала удаляет то, что создал прошлый запуск.
"""
import bpy, math
from mathutils import Vector

# ---------- материалы (в стиле существующих *_flat: Emission, плоский цвет) ----------
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

M = {n: bpy.data.materials[n] for n in
     ["desk_flat", "pc_flat", "screen_flat", "soft_flat", "bed_flat", "paper_flat",
      "shelf_flat", "closet_flat", "blind_flat"]}
M["dark"] = flat("dark_flat", (0.04, 0.04, 0.05))
M["metal"] = flat("metal_flat", (0.30, 0.31, 0.34))
M["wood"] = flat("wood_flat", (0.36, 0.27, 0.19))
M["blanket"] = flat("blanket_flat", (0.20, 0.33, 0.42))
M["led"] = flat("led_flat", (0.45, 0.85, 1.0), 2.0)
M["lampshade"] = flat("lampshade_flat", (0.95, 0.85, 0.62), 1.5)
M["book_r"] = flat("book_red_flat", (0.45, 0.16, 0.14))
M["book_g"] = flat("book_green_flat", (0.20, 0.36, 0.26))
M["book_y"] = flat("book_yellow_flat", (0.70, 0.58, 0.25))
M["cork"] = flat("cork_flat", (0.55, 0.42, 0.27))
M["pot"] = flat("pot_flat", (0.62, 0.33, 0.22))
M["plant"] = flat("plant_flat", (0.22, 0.45, 0.25))
M["plant2"] = flat("plant_dark_flat", (0.15, 0.33, 0.19))

# ---------- генерация геометрии ----------
def box(mn, mx, mat, rot_z=0.0, pivot=None):
    """Бокс по мировым min/max; rot_z (градусы) вокруг pivot (по умолчанию центр)."""
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

def rotate_parts(parts, deg, pivot):
    a = math.radians(deg); ca, sa = math.cos(a), math.sin(a); c = Vector(pivot)
    return [([Vector((c.x + (v.x - c.x) * ca - (v.y - c.y) * sa,
                      c.y + (v.x - c.x) * sa + (v.y - c.y) * ca, v.z)) for v in vs], fs, m)
            for vs, fs, m in parts]

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
    # origin: низ по центру
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

# ---------- подготовка коллекций ----------
scene = bpy.context.scene
old = bpy.data.collections.get("blockout_old") or bpy.data.collections.new("blockout_old")
if old.name not in scene.collection.children:
    scene.collection.children.link(old)
new = bpy.data.collections.get("hero_detail")
if new:  # повторный запуск: чистим прошлый результат
    for ob in list(new.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
else:
    new = bpy.data.collections.new("hero_detail")
    scene.collection.children.link(new)

REPLACE = ["hero_desk", "hero_monitor", "hero_tower", "hero_chair", "hero_bed", "hero_pillow",
           "hero_nightstand", "hero_closet", "hero_dresser", "hero_blind", "hero_shelf_n",
           "hero_books", "hero_board"]
for n in REPLACE:
    ob = bpy.data.objects.get(n)
    if ob and old not in ob.users_collection:
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        old.objects.link(ob)
old.hide_viewport = True
old.hide_render = True

D = M
P = []  # временный список деталей

# ---------- СТОЛ (0.75..2.40, 6.75..7.40, h 0.75) с тумбой справа ----------
P = [box((0.75, 6.75, 0.72), (2.40, 7.40, 0.75), D["wood"])]
for x in (0.78, 1.94):
    for y in (6.78, 7.33):
        P.append(box((x, y, 0), (x + 0.04, y + 0.04, 0.72), D["metal"]))
P.append(box((1.98, 6.78, 0), (2.37, 7.37, 0.72), D["desk_flat"]))          # тумба
for z in (0.24, 0.48):
    P.append(box((1.99, 6.77, z), (2.36, 6.78, z + 0.012), D["dark"]))       # щели ящиков
for z in (0.12, 0.36, 0.60):
    P.append(box((2.14, 6.755, z), (2.21, 6.77, z + 0.02), D["metal"]))      # ручки
build("det_desk", P, new)

# ---------- МОНИТОР на подставке ----------
P = [box((1.50, 6.92, 0.75), (1.70, 7.10, 0.765), D["dark"]),               # основание
     box((1.58, 7.02, 0.765), (1.62, 7.05, 0.93), D["dark"]),                # ножка
     box((1.28, 6.97, 0.90), (1.92, 7.02, 1.27), D["dark"]),                 # корпус
     box((1.30, 6.965, 0.92), (1.90, 6.97, 1.25), D["screen_flat"])]         # экран
build("det_monitor", P, new)

# ---------- клавиатура, мышь, кружка, настольная лампа (слева за кружкой) ----------
P = [box((1.36, 6.80, 0.75), (1.82, 6.95, 0.77), D["dark"]),
     box((1.37, 6.81, 0.77), (1.81, 6.94, 0.775), D["metal"])]
build("det_keyboard", P, new)
build("det_mouse", [box((1.90, 6.84, 0.75), (1.96, 6.93, 0.78), D["dark"])], new)
build("det_mug", [box((1.05, 6.86, 0.75), (1.13, 6.94, 0.86), D["paper_flat"]),
                  box((1.13, 6.885, 0.78), (1.16, 6.915, 0.83), D["paper_flat"])], new)
# лампа слева за кружкой, плафон смотрит вправо, на клавиатуру
build("det_desk_lamp", [box((0.82, 7.14, 0.75), (0.96, 7.28, 0.77), D["dark"]),
                        box((0.87, 7.20, 0.77), (0.89, 7.22, 1.15), D["dark"]),
                        box((0.85, 7.16, 1.10), (1.07, 7.26, 1.17), D["dark"]),
                        box((0.86, 7.17, 1.095), (1.06, 7.25, 1.10), D["lampshade"])], new)

# ---------- СИСТЕМНИК на столе справа (вместо лампы) ----------
TX, TZ = 2.12, 0.75   # левый край и высота столешницы
P = [box((TX, 6.85, TZ + 0.02), (TX + 0.22, 7.30, TZ + 0.47), D["pc_flat"]),
     box((TX + 0.02, 6.845, TZ + 0.40), (TX + 0.20, 6.85, TZ + 0.415), D["led"]),   # LED-полоска
     box((TX + 0.08, 6.845, TZ + 0.30), (TX + 0.14, 6.85, TZ + 0.36), D["metal"])]  # кнопка/порты
for x in (TX + 0.01, TX + 0.18):
    for y in (6.87, 7.25):
        P.append(box((x, y, TZ), (x + 0.03, y + 0.03, TZ + 0.02), D["dark"]))     # ножки
build("det_pc_tower", P, new)

# ---------- ОФИСНОЕ КРЕСЛО (чуть отодвинуто и развёрнуто, как будто с него встали) ----------
cx, cy = 1.70, 6.22
CHAIR_TURN = 28  # градусы; 0 = ровно к столу
P = []
for i in range(5):  # пятилучевая крестовина
    a = i * 72 + 18
    P.append(box((cx, cy - 0.02, 0.04), (cx + 0.30, cy + 0.02, 0.07), D["dark"], rot_z=a, pivot=(cx, cy)))
    ex, ey = cx + 0.28 * math.cos(math.radians(a)), cy + 0.28 * math.sin(math.radians(a))
    P.append(box((ex - 0.025, ey - 0.025, 0), (ex + 0.025, ey + 0.025, 0.04), D["dark"]))
P += [box((cx - 0.025, cy - 0.025, 0.07), (cx + 0.025, cy + 0.025, 0.42), D["metal"]),   # газлифт
      box((cx - 0.24, cy - 0.22, 0.42), (cx + 0.24, cy + 0.24, 0.50), D["soft_flat"]),   # сиденье
      box((cx - 0.03, cy - 0.27, 0.44), (cx + 0.03, cy - 0.22, 0.60), D["dark"]),        # кронштейн спинки
      box((cx - 0.22, cy - 0.30, 0.58), (cx + 0.22, cy - 0.24, 1.00), D["soft_flat"])]   # спинка
for sx in (-1, 1):  # подлокотники
    x = cx + sx * 0.235
    P.append(box((x - 0.015, cy - 0.02, 0.50), (x + 0.015, cy + 0.02, 0.66), D["dark"]))
    P.append(box((x - 0.03, cy - 0.14, 0.66), (x + 0.03, cy + 0.12, 0.69), D["dark"]))
build("det_chair", rotate_parts(P, CHAIR_TURN, (cx, cy)), new)

# ---------- КРОВАТЬ (0.10..1.05, 4.55..6.60), изголовье у y=6.60 ----------
P = [box((0.10, 4.55, 0.06), (1.05, 6.56, 0.28), D["wood"]),                 # рама
     box((0.13, 4.58, 0.28), (1.02, 6.53, 0.46), D["bed_flat"]),             # матрас
     box((0.105, 4.555, 0.22), (1.045, 5.95, 0.49), D["blanket"]),           # одеяло
     box((0.10, 6.56, 0), (1.05, 6.62, 0.90), D["wood"]),                    # изголовье
     box((0.10, 4.53, 0), (1.05, 4.57, 0.40), D["wood"]),                    # изножье
     box((0.16, 6.20, 0.46), (0.97, 6.50, 0.60), D["paper_flat"])]           # подушка
for x in (0.10, 1.01):
    P.append(box((x, 4.60, 0), (x + 0.04, 4.64, 0.06), D["wood"]))
build("det_bed", P, new)

# ---------- ВЫСОКАЯ ТУМБА в углу + вазон (сансевиерия) ----------
NH = 0.95  # высота тумбы
P = [box((0.12, 6.65, 0.04), (0.57, 7.10, NH), D["shelf_flat"]),
     box((0.14, 6.67, 0), (0.55, 7.08, 0.04), D["dark"])]                    # цоколь
for z in (0.36, 0.66):
    P.append(box((0.13, 6.64, z), (0.56, 6.65, z + 0.012), D["dark"]))       # щели ящиков
for z in (0.22, 0.52, 0.80):
    P.append(box((0.30, 6.63, z), (0.39, 6.645, z + 0.02), D["metal"]))      # ручки
build("det_nightstand", P, new)

px, py = 0.345, 6.875  # центр горшка
P = [box((px - 0.10, py - 0.10, NH), (px + 0.10, py + 0.10, NH + 0.18), D["pot"]),
     box((px - 0.11, py - 0.11, NH + 0.16), (px + 0.11, py + 0.11, NH + 0.20), D["pot"]),  # ободок
     box((px - 0.09, py - 0.09, NH + 0.18), (px + 0.09, py + 0.09, NH + 0.185), D["dark"])] # земля
blades = [(0, 0.00, 0.00, 0.50), (35, 0.06, 0.03, 0.40), (-40, -0.06, 0.03, 0.36),
          (80, 0.04, -0.06, 0.44), (-75, -0.05, -0.05, 0.30), (15, -0.07, 0.06, 0.26),
          (120, 0.07, -0.02, 0.32), (-120, 0.01, 0.07, 0.38), (60, -0.02, -0.02, 0.22)]
for k, (ang, dx, dy, h) in enumerate(blades):
    bx, by = px + dx, py + dy
    mat = D["plant"] if k % 2 == 0 else D["plant2"]
    P.append(box((bx - 0.04, by - 0.006, NH + 0.18), (bx + 0.04, by + 0.006, NH + 0.18 + h), mat,
                 rot_z=ang, pivot=(bx, by)))
build("det_plant", P, new)

# ---------- ШКАФ (фасад смотрит в -X, x=2.86) ----------
P = [box((2.86, 5.75, 0.06), (3.38, 7.20, 2.10), D["closet_flat"]),
     box((2.88, 5.77, 0), (3.36, 7.18, 0.06), D["dark"]),                    # цоколь
     box((2.855, 6.47, 0.08), (2.86, 6.48, 2.08), D["dark"])]                # щель между дверцами
for y in (6.40, 6.53):
    P.append(box((2.83, y, 0.95), (2.855, y + 0.02, 1.25), D["metal"]))      # ручки
build("det_closet", P, new)

# ---------- КОМОД (фасад в -X, x=2.92) ----------
P = [box((2.92, 4.45, 0.04), (3.38, 5.50, 0.88), D["closet_flat"]),
     box((2.94, 4.47, 0), (3.36, 5.48, 0.04), D["dark"])]
for z in (0.32, 0.60):
    P.append(box((2.915, 4.47, z), (2.92, 5.48, z + 0.012), D["dark"]))
for z in (0.18, 0.46, 0.74):
    P.append(box((2.895, 4.92, z), (2.92, 5.03, z + 0.02), D["metal"]))
build("det_dresser", P, new)

# ---------- ЖАЛЮЗИ на окне за столом (ламели с просветами) ----------
P = [box((0.98, 7.19, 2.16), (2.44, 7.30, 2.24), D["blind_flat"])]           # карниз
z = 1.30
while z < 2.14:  # жалюзи приподняты: низ окна открыт
    P.append(box((1.00, 7.21, z), (2.42, 7.28, z + 0.028), D["blind_flat"]))
    z += 0.055
P.append(box((1.00, 7.20, 1.27), (2.42, 7.29, 1.30), D["blind_flat"]))       # нижняя планка
build("det_blind", P, new)

# ---------- ПОЛКА с книгами: на левой (западной) стене над тумбочкой ----------
# Строим как раньше (вдоль северной стены), затем поворачиваем на 90° и переносим на стену x≈0.
SHELF_PIVOT = (1.40, 7.29)
SHELF_OFFSET = Vector((-1.27, -0.52, 0))   # сдвиг после поворота: к стене x=0.02, y 6.12..7.42
def move_to_wall(parts):
    parts = rotate_parts(parts, 90, SHELF_PIVOT)
    return [([v + SHELF_OFFSET for v in vs], fs, m) for vs, fs, m in parts]

P = [box((0.75, 7.18, 1.85), (2.05, 7.40, 1.875), D["wood"]),
     box((0.85, 7.36, 1.70), (0.88, 7.40, 1.85), D["metal"]),
     box((1.92, 7.36, 1.70), (1.95, 7.40, 1.85), D["metal"])]
build("det_shelf", move_to_wall(P), new)
cols = [D["book_r"], D["book_g"], D["book_y"], D["shelf_flat"], D["paper_flat"], D["book_r"], D["closet_flat"]]
hs = [0.22, 0.19, 0.24, 0.20, 0.17, 0.23, 0.21, 0.18, 0.22, 0.19]
P, x = [], 0.86
for i, h in enumerate(hs):
    w = 0.03 + (i % 3) * 0.008
    P.append(box((x, 7.22, 1.875), (x + w, 7.38, 1.875 + h), cols[i % len(cols)]))
    x += w + 0.004
P.append(box((x + 0.01, 7.22, 1.875), (x + 0.04, 7.38, 1.875 + 0.20), D["book_g"], rot_z=0))
P.append(box((1.55, 7.24, 1.875), (1.80, 7.38, 1.94), D["book_y"]))         # стопка лёжа
P.append(box((1.57, 7.25, 1.94), (1.79, 7.37, 1.98), D["book_r"]))
build("det_books", move_to_wall(P), new)

# ---------- ПРОБКОВАЯ ДОСКА с бумажками (на стене за камерой) ----------
P = [box((1.35, 4.33, 1.35), (2.20, 4.36, 1.95), D["wood"]),
     box((1.38, 4.36, 1.38), (2.17, 4.365, 1.92), D["cork"])]
for (x, zz) in ((1.45, 1.70), (1.70, 1.55), (1.92, 1.72), (1.55, 1.45)):
    P.append(box((x, 4.365, zz), (x + 0.15, 4.37, zz + 0.18), D["paper_flat"]))
build("det_board", P, new)

print("hero_detail: создано объектов:", len(new.objects))

# ---------- Альтернативная камера для крупного плана компа (старую room_pc не трогаем) ----------
def look_at_cam(name, loc, target, lens):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        scene.collection.objects.link(cam)
    cam.data.lens = lens
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    return cam

look_at_cam("room_pc_v2", (1.85, 5.55, 1.30), (1.55, 7.10, 0.98), 30)
