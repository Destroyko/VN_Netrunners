"""Два кадра комнаты героя со светом: общий вид и вид на ПК.

Работает поверх рабочей сцены и ничего в ней не сохраняет: камеры и свет создаются на
время рендера, файл остаётся за разработчиком. Свои камеры можно положить в сцену под
именами `room_main` и `room_pc` — тогда скрипт возьмёт их, а не расчётные.

    & "...\\blender.exe" -b assets\\_source\\blockout\\apartment_work_palette.blend ^
        --python tools\\blockout\\room_frames.py -- --phase evening --render main,pc

Кадры:
- main — кровать, стол, шкаф, настенная полка и календарь в одном кадре, чтобы не крутиться
  по комнате в поисках предмета;
- pc — системный блок и стол: сюда вставляется флешка.

Свет собирается из трёх источников, как в настоящей комнате: окно (небо), лампа и монитор.
Силы и цвета по фазам суток — таблица PHASES ниже; подбор идёт по рендеру глазами.
Файлы: <папка>/room_<кадр>_<фаза>.png.
"""

import math
import os
import sys

import bmesh
import bpy
import mathutils

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bl_common as B  # noqa: E402
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402
import matte_wallpaper as W  # noqa: E402
import room_exterior as X  # noqa: E402

# Расчётные камеры: положение, цель, фокусное. Комната по x 0–3,3 и y 4,5–7,3, окно в стене y≈7,3
# ext_blur — размытие того, что за окном, в пикселях кадра шириной 1920; ext_depth — глубина кадра
# (м от камеры), дальше которой всё считается улицей. Размытие считается в компоновщике по
# глубине, а не диафрагмой камеры: диафрагма мылила бы и стол, и всё остальное в комнате
CAMERAS = {
    "main": {"loc": (1.6, 4.6, 1.45), "target": (1.6, 7.0, 1.0), "lens": 20.0, "ext_blur": 6.0, "ext_depth": 3.4},
    "pc":   {"loc": (1.3, 5.9, 1.40), "target": (2.2, 6.95, 0.90), "lens": 32.0, "ext_blur": 14.0, "ext_depth": 3.0},
}

# Окно: центр и размер светящегося прямоугольника снаружи стены
WINDOW = {"centre": (1.96, 7.95, 1.65), "size": (1.6, 2.0)}
# Монитор: экран смотрит на -y, лампа монитора стоит перед ним
MONITOR = {"centre": (1.87, 6.75, 0.98), "size": (0.5, 0.28)}

# Фазы суток. sky — цвет и сила мира; window — свет из окна; lamp — торшер (мощность, цвет,
# радиус действия); monitor — свет монитора, едва заметный; fill — подсветка потолка.
# floor и tint — отклик материалов на свет (cel_shader.light_group): до какой доли тон гаснет
# без света и насколько цвет света окрашивает поверхность
PHASES = {
    # День: свет в комнату идёт из окна. Небо мира светит на всё без учёта стен (EEVEE не
    # затеняет его комнатой), поэтому оно слабое: при силе 1,0 комната освещалась как под
    # открытым небом, а floor 1,0 убирал отклик на свет вовсе — ни теней, ни градиентов
    # sun — солнце: цвет, сила, куда идёт луч (x к востоку, -y в комнату, -z вниз), угол
    # диска в градусах. Окно слабее: пока оно заливало комнату до верхней ступени cel-света,
    # солнце ничего не добавляло, и полос от жалюзи не было видно
    "day":     {"sky": ((0.62, 0.72, 0.90), 0.1), "window": ((1.00, 0.97, 0.92), 300.0),
                "lamp": 0.0, "lamp_color": (1.0, 0.5, 0.12), "lamp_reach": 1.2,
                "monitor": 0.0, "fill": 10.0, "floor": 0.5, "tint": 0.0,
                "shadow": 0.2, "night": (0.5, 0.6, 1.0), "grad": 0.55, "vignette": 0.2,
                "sun": ((1.0, 0.94, 0.82), 9.0, (-0.5, -0.75, -0.45), 0.6)},
    "evening": {"sky": ((0.80, 0.45, 0.35), 0.15), "window": ((1.00, 0.55, 0.30), 380.0),
                "lamp": 26.0, "lamp_color": (1.0, 0.42, 0.10), "lamp_reach": 1.2, "halo": 0.0, "lamp_side": 1.0,
                "monitor": 3.0, "fill": 8.0, "floor": 0.55, "tint": 0.6,
                "shadow": 0.35, "night": (0.55, 0.5, 0.95), "grad": 0.6, "vignette": 0.28},
    "night":   {"sky": ((0.05, 0.08, 0.20), 0.02), "window": ((0.25, 0.40, 1.00), 5.0),
                "lamp": 26.0, "lamp_color": (1.0, 0.38, 0.08), "lamp_reach": 1.2, "halo": 0.0, "lamp_side": 1.0,
                "monitor": 1.5, "fill": 0.0, "floor": 0.07, "tint": 0.85,
                "shadow": 0.6, "night": (0.22, 0.40, 1.0), "grad": 0.65, "vignette": 0.3},
}


def extra(p):
    p.add_argument("--res", default="2560,1440", help="размер кадра: ширина,высота")
    p.add_argument("--samples", type=int, default=256)
    p.add_argument("--pc", default="both", help="on, off или both: состояние ПК (экран и его свет)")


def make_camera(name):
    """Своя камера frame_<кадр> из сцены или расчётная."""
    own = bpy.data.objects.get("frame_" + name)
    if own is not None and own.type == "CAMERA":
        return own
    spec = CAMERAS[name]
    cd = bpy.data.cameras.new("rf_" + name)
    cd.lens = spec["lens"]
    cd.clip_start = 0.05
    ob = bpy.data.objects.new("rf_" + name, cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = spec["loc"]
    tgt = mathutils.Vector(spec["target"])
    ob.rotation_euler = (tgt - ob.location).to_track_quat("-Z", "Y").to_euler()
    return ob


def area(name, centre, size, color, power, facing, spread=180.0, specular=1.0):
    """Прямоугольный источник. facing — куда светит: единичный вектор."""
    la = bpy.data.lights.new(name, "AREA")
    la.shape = "RECTANGLE"
    la.size, la.size_y = size
    la.color = color
    la.energy = power
    la.spread = math.radians(spread)
    # Блик от света в cel-материале — ступенчатое пятно: у близких ламп он выглядит
    # как луч прожектора на мебели, поэтому у них блик убавляем
    la.specular_factor = specular
    ob = bpy.data.objects.new(name, la)
    ob.location = centre
    ob.rotation_euler = mathutils.Vector(facing).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    return ob


def shade_glow(on):
    """Абажур торшера светится, когда лампа включена: без этого свет ниоткуда не берётся."""
    ob = bpy.data.objects.get("FloorLamp_Cover")
    if ob is None or not ob.material_slots:
        return
    if "_shade_off" not in ob:
        ob["_shade_off"] = ob.material_slots[0].material.name if ob.material_slots[0].material else ""
    if on:
        name = "rf_shade_glow"
        mat = bpy.data.materials.get(name)
        if mat is None:
            mat = bpy.data.materials.new(name)
            mat.use_nodes = True
            # цвет задан прямо, а не из палитры: светлый оранжевый палитры при свечении
            # выгорает в жёлтый, а абажуру нужен тёплый оранжевый
            C.build(mat.node_tree, (1.0, 0.45, 0.12), kind="glow")
            for n in mat.node_tree.nodes:
                if n.type == "EMISSION":
                    n.inputs["Strength"].default_value = 0.75
        ob.material_slots[0].material = mat
        # абажур не должен закрывать собственный свет: тень от него гасила бы всю комнату
        ob.visible_shadow = False
    else:
        ob.visible_shadow = True
        orig = bpy.data.materials.get(ob["_shade_off"])
        if orig is not None:
            ob.material_slots[0].material = orig


HALO_RADIUS = 0.42           # м: ореол вокруг абажура; не шире расстояния от лампы до боковой стены (0,44 м)


def lamp_halo(power):
    """Ореол вокруг абажура: будто внутри горит лампочка, а не светится сама ткань.

    Плоский диск с мягким радиальным свечением стоит перед абажуром лицом к комнате (обе
    камеры смотрят вдоль +y). Шар пробивал бы стену и давал на ней резкий край. Виден только
    камере: на свет, тени и блики сцены он не влияет. power — яркость ореола; 0 — без ореола."""
    shade = bpy.data.objects.get("FloorLamp_Cover")
    if shade is None or power <= 0.0:
        return
    bpy.context.view_layer.update()
    # центр абажура — по граням его слота (слот 0), а не по всему торшеру со стойкой
    pts = [shade.matrix_world @ shade.data.vertices[vi].co
           for poly in shade.data.polygons if poly.material_index == 0 for vi in poly.vertices]
    centre = mathutils.Vector((sum(v[i] for v in pts) / len(pts) for i in range(3)))
    centre.z = (min(v.z for v in pts) + max(v.z for v in pts)) / 2.0
    r = HALO_RADIUS
    bm = bmesh.new()
    bm.faces.new([bm.verts.new(c) for c in ((-r, 0, -r), (r, 0, -r), (r, 0, r), (-r, 0, r))])
    me = bpy.data.meshes.new("rf_halo")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("rf_halo", me)
    ob.location = (centre.x, centre.y - 0.12, centre.z)
    bpy.context.scene.collection.objects.link(ob)
    ob.visible_shadow = False
    ob.visible_glossy = False
    ob.visible_diffuse = False
    ob.visible_transmission = False
    ob.visible_volume_scatter = False

    mat = bpy.data.materials.get("rf_halo") or bpy.data.materials.new("rf_halo")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    # 1 в центре диска, 0 на краю: расстояние от центра по сгенерированным координатам
    tc = nt.nodes.new("ShaderNodeTexCoord")
    off = nt.nodes.new("ShaderNodeVectorMath")
    off.operation = "SUBTRACT"
    off.inputs[1].default_value = (0.5, 0.5, 0.5)
    nt.links.new(tc.outputs["Generated"], off.inputs[0])
    ln = nt.nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    nt.links.new(off.outputs[0], ln.inputs[0])
    fall = nt.nodes.new("ShaderNodeMath")
    fall.operation = "MULTIPLY_ADD"
    fall.use_clamp = True
    fall.inputs[1].default_value = -2.0
    fall.inputs[2].default_value = 1.0
    nt.links.new(ln.outputs["Value"], fall.inputs[0])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 2.2
    nt.links.new(fall.outputs[0], pw.inputs[0])
    k = nt.nodes.new("ShaderNodeMath")
    k.operation = "MULTIPLY"
    k.use_clamp = True
    k.inputs[1].default_value = 0.55
    nt.links.new(pw.outputs[0], k.inputs[0])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1.0, 0.52, 0.18, 1.0)
    em.inputs["Strength"].default_value = power
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(k.outputs[0], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    try:
        mat.surface_render_method = "BLENDED"
        mat.use_backface_culling = True
    except Exception:
        pass
    me.materials.append(mat)


def lamp_cones(power, color, half_angle=50.0, blend=0.7):
    """Свет торшера двумя конусами: вверх и вниз из отверстий абажура.

    У настоящего абажура открыты верх и низ: пятно на стене над лампой и под ней, а по бокам
    свет слабый. Точечная лампа светила бы шаром. half_angle — половина угла конуса,
    blend — мягкость края (0 — резкий)."""
    lamp = bpy.data.objects.get("FloorLamp_Light")
    if lamp is None or power <= 0.0:
        return
    bpy.context.view_layer.update()
    pos = lamp.matrix_world.translation.copy()
    for name, tilt in (("rf_lamp_up", math.pi), ("rf_lamp_down", 0.0)):
        la = bpy.data.lights.new(name, "SPOT")
        la.energy = power
        la.color = color
        la.spot_size = math.radians(half_angle * 2.0)
        la.spot_blend = blend
        la.shadow_soft_size = 0.15
        la.specular_factor = 0.0
        la.use_custom_distance = True
        la.cutoff_distance = 8.0
        ob = bpy.data.objects.new(name, la)
        ob.location = pos
        ob.rotation_euler = (tilt, 0.0, 0.0)       # прожектор по умолчанию смотрит вниз (-z)
        bpy.context.scene.collection.objects.link(ob)


def clear_post():
    sc = bpy.context.scene
    ng = bpy.data.node_groups.get("rf_post")
    if ng is not None:
        if sc.compositing_node_group is ng:
            sc.compositing_node_group = None
        bpy.data.node_groups.remove(ng)


def post(vignette, frame=None):
    """Постобработка кадра в компоновщике: размытие улицы за окном и мягкая виньетка.

    Улица — всё, что глубже `ext_depth` кадра: она размывается нормированной сверткой, то есть
    только по пикселям улицы, и цвет жалюзи и рамы в неё не подмешивается. Комната остаётся
    резкой. Затем края темнее на долю vignette. Группа rf_post создаётся на время рендера и
    убирается в clear(); чужой компоновщик сцены не трогается."""
    sc = bpy.context.scene
    clear_post()
    spec = CAMERAS.get(frame or "", {})
    blur_px = spec.get("ext_blur", 0.0) * sc.render.resolution_x / 1920.0
    if (vignette <= 0.0 and blur_px <= 0.0) or sc.compositing_node_group is not None:
        return
    vl = bpy.context.view_layer
    vl.use_pass_z = True
    ng = bpy.data.node_groups.new("rf_post", "CompositorNodeTree")
    ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    n = ng.nodes
    rl = n.new("CompositorNodeRLayers")
    rl.scene = sc
    rl.layer = vl.name
    out = n.new("NodeGroupOutput")
    colour = rl.outputs["Image"]

    def mix(blend, a, b, fac=1.0):
        node = n.new("ShaderNodeMix")
        node.data_type = "RGBA"
        node.blend_type = blend
        node.inputs[0].default_value = fac
        ng.links.new(a, node.inputs[6])
        ng.links.new(b, node.inputs[7])
        return node.outputs[2]

    def blur(src, px):
        node = n.new("CompositorNodeBlur")
        node.inputs["Size"].default_value = (px, px)
        ng.links.new(src, node.inputs["Image"])
        return node.outputs[0]

    if blur_px > 0.0:
        far = n.new("ShaderNodeMath")
        far.operation = "GREATER_THAN"
        far.inputs[1].default_value = spec["ext_depth"]
        ng.links.new(rl.outputs["Depth"], far.inputs[0])
        masked = mix("MULTIPLY", colour, far.outputs[0])
        street = mix("DIVIDE", blur(masked, blur_px), blur(far.outputs[0], blur_px))
        edge = blur(far.outputs[0], 1.5)
        node = n.new("ShaderNodeMix")
        node.data_type = "RGBA"
        node.blend_type = "MIX"
        ng.links.new(edge, node.inputs[0])
        ng.links.new(colour, node.inputs[6])
        ng.links.new(street, node.inputs[7])
        colour = node.outputs[2]

    if vignette > 0.0:
        ell = n.new("CompositorNodeEllipseMask")
        ell.inputs["Position"].default_value = (0.5, 0.5)
        ell.inputs["Size"].default_value = (1.25, 1.25)
        shade = blur(ell.outputs[0], 260.0 * sc.render.resolution_x / 1280.0)
        ma = n.new("ShaderNodeMath")
        ma.operation = "MULTIPLY_ADD"
        ma.inputs[1].default_value = vignette
        ma.inputs[2].default_value = 1.0 - vignette
        ng.links.new(shade, ma.inputs[0])
        colour = mix("MULTIPLY", colour, ma.outputs[0])

    ng.links.new(colour, out.inputs[0])
    sc.compositing_node_group = ng


SCREEN = "pal_glow_screen"


def set_pc(on):
    """Монитор включён или выключен: экран светится серо-белым или чёрный.

    Номер слота экрана запоминается на объекте (`_screen_slot`) при первом вызове,
    пока в слоте ещё стоит материал свечения: в выключенном виде там чёрный пластик.
    """
    ob = bpy.data.objects.get("Foot")
    glow = bpy.data.materials.get(SCREEN)
    black = bpy.data.materials.get("pal_plastic_black")
    if ob is None or glow is None or black is None:
        return False
    if "_screen_slot" not in ob:
        for i, sl in enumerate(ob.material_slots):
            if sl.material == glow:
                ob["_screen_slot"] = i
    if "_screen_slot" not in ob:
        return False
    ob.material_slots[ob["_screen_slot"]].material = glow if on else black
    return True


def screen_quad(cam):
    """Углы экрана в кадре (доли 0..1, начало слева сверху) для слоя экрана в игре.

    Берутся грани объекта монитора со слотом экрана. Формат тот же, что у screen_quads.py.
    """
    from bpy_extras.object_utils import world_to_camera_view
    ob = bpy.data.objects.get("Foot")
    if ob is None or "_screen_slot" not in ob:
        return None
    sc = bpy.context.scene
    idx = ob["_screen_slot"]
    pts = {}
    for poly in ob.data.polygons:
        if poly.material_index != idx:
            continue
        for vi in poly.vertices:
            w = ob.matrix_world @ ob.data.vertices[vi].co
            pts[vi] = w
    if len(pts) < 4:
        return None
    pr = []
    for w in pts.values():
        c = world_to_camera_view(sc, cam, w)
        pr.append((round(c.x, 4), round(1.0 - c.y, 4), c.z))
    tl = min(pr, key=lambda q: q[0] + q[1])
    br = max(pr, key=lambda q: q[0] + q[1])
    tr = max(pr, key=lambda q: q[0] - q[1])
    bl = min(pr, key=lambda q: q[0] - q[1])
    corners = [[tl[0], tl[1]], [tr[0], tr[1]], [br[0], br[1]], [bl[0], bl[1]]]
    inside = all(0.0 <= c[0] <= 1.0 and 0.0 <= c[1] <= 1.0 for c in corners)
    return {"corners": corners, "fully_visible": inside}


def clear():
    """Убрать всё, что скрипт добавил в сцену: источники и расчётные камеры, абажур вернуть."""
    for ob in list(bpy.data.objects):
        if ob.name.startswith("rf_"):
            data = ob.data
            bpy.data.objects.remove(ob)
            if data is not None and data.users == 0:
                if isinstance(data, bpy.types.Mesh):
                    bpy.data.meshes.remove(data)
                else:
                    (bpy.data.lights if ob_is_light(data) else bpy.data.cameras).remove(data)
    clear_post()
    lamp = bpy.data.objects.get("FloorLamp_Light")
    if lamp is not None:
        lamp.hide_render = False
    shade_glow(False)
    C.set_light_response(1.0, 0.0, 0.0)


def ob_is_light(data):
    return isinstance(data, bpy.types.Light)


def build_light(phase, pc=True):
    sc = bpy.context.scene
    clear()
    ph = PHASES[phase]
    w = sc.world or bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    color, strength = ph["sky"]
    bg.inputs["Color"].default_value = (*color, 1.0)
    bg.inputs["Strength"].default_value = strength

    # Прежние лампы сцены гасим: свет собираем заново и считаем сами
    for o in bpy.data.objects:
        if o.type == "LIGHT" and o.name != "FloorLamp_Light":
            o.hide_render = True
    lamp = bpy.data.objects.get("FloorLamp_Light")
    if lamp is not None:
        # Основная часть света уходит конусами вверх и вниз через отверстия абажура
        # (lamp_cones), через стенки идёт только доля lamp_side
        lamp.data.energy = ph["lamp"] * ph.get("lamp_side", 1.0)
        lamp.data.color = ph["lamp_color"]
        lamp.data.shadow_soft_size = 0.2
        lamp.data.specular_factor = 0.0
        # Свет лампы живёт в радиусе метров: в cel-ступенях любой слабый источник
        # даёт резкое пятно через всю комнату, поэтому его обрезаем по расстоянию
        # Радиус влияния EEVEE считает сам по силе света, и у слабой лампы он мал: граница
        # даёт на стене резкий круг (цвет света внутри и снаружи разный). Радиус задан
        # больше комнаты, затухание остаётся естественным
        lamp.data.use_custom_distance = True
        lamp.data.cutoff_distance = 8.0
        lamp.hide_render = ph["lamp"] <= 0.0
        shade_glow(ph["lamp"] > 0.0)
        lamp_halo(ph.get("halo", 0.0))
        lamp_cones(ph["lamp"] * 1.2, ph["lamp_color"])

    X.apply_phase(phase)                   # вид из окна: дома, небо, огни окон

    C.unify_light_groups()                 # материалы из браузера ассетов несут свои копии узла
    C.set_light_response(ph["floor"], ph["tint"], ph["shadow"], ph["night"], ph["grad"])
    W.apply()

    wcol, wpow = ph["window"]
    # блик окна отключён: светящийся прямоугольник за стеклом отражался в нём и заливал вид белым
    area("rf_window", WINDOW["centre"], WINDOW["size"], wcol, wpow, (0.0, -1.0, 0.0), specular=0.0)
    if ph["monitor"] > 0.0 and pc:
        mon = area("rf_monitor", MONITOR["centre"], MONITOR["size"], (0.80, 0.84, 0.92),
                   ph["monitor"], (0.0, -1.0, -0.15), spread=70.0, specular=0.0)
        mon.data.use_custom_distance = True
        mon.data.cutoff_distance = 0.9
    # Солнце: узкий источник даёт резкие тени предметов и полосы света сквозь жалюзи.
    # Окно — большой мягкий прямоугольник, его тени размыты и полос не дают. Блик отключён
    # по той же причине, что у окна: ступенчатое пятно на мебели читается прожектором
    sun = ph.get("sun")
    if sun:
        scol, spower, sdir, sangle = sun
        la = bpy.data.lights.new("rf_sun", "SUN")
        la.color = scol
        la.energy = spower
        la.angle = math.radians(sangle)
        la.specular_factor = 0.0
        ob = bpy.data.objects.new("rf_sun", la)
        ob.rotation_euler = mathutils.Vector(sdir).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.collection.objects.link(ob)
    # слабая подсветка сверху: без неё углы уходят в чёрное и теряют форму
    area("rf_fill", (1.7, 5.9, 2.55), (2.4, 2.4), (1.0, 0.95, 0.9), ph["fill"], (0.0, 0.0, -1.0))


def setup(phase, samples=64, pc=True):
    """Настройки рендера и свет фазы. Одинаково для командной строки и окна Blender."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.eevee.taa_render_samples = samples
    # Окно Blender считает сэмплы отдельно (по умолчанию 16): на тёмном пластике это крупное зерно
    sc.eevee.taa_samples = 128
    B.flat_color(sc)
    # Тени: при малом числе лучей слабо освещённые поверхности зернят (чёрный пластик
    # выглядит дырявым), поэтому лучей и шагов больше, чем по умолчанию
    sc.eevee.shadow_ray_count = 8
    sc.eevee.shadow_step_count = 24
    sc.eevee.shadow_resolution_scale = 2.0
    # EEVEE обрезает свет там, где его сила падает ниже порога: при плавных переходах
    # граница видна как круг на стене. Порог ниже, и круг уходит за пределы кадра
    sc.eevee.light_threshold = 0.00001
    set_pc(pc)
    build_light("day" if phase == "morning" else phase, pc)


def gui(phase="night", view="main", pc="on"):
    """Показать свет в окне Blender (скрипт для вкладки Scripting: room_light_gui.py).

    phase: day, evening, night или off (убрать всё, что добавил скрипт).
    view: main или pc — смотреть через расчётную камеру; none — вид не трогать.
    Окна 3D переключаются в режим Rendered. Сцену с включённым светом лучше не сохранять:
    источники rf_* останутся в файле (убираются запуском с phase=off).
    """
    if phase == "off":
        clear()
        for area in bpy.context.screen.areas:
            if area.type == "VIEW_3D":
                for sp in area.spaces:
                    if sp.type == "VIEW_3D":
                        sp.shading.type = "MATERIAL"
        return
    setup(phase, samples=32, pc=(pc != "off"))
    if view != "none":
        bpy.context.scene.camera = make_camera(view)
        post(PHASES["day" if phase == "morning" else phase].get("vignette", 0.0), view)
    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            for sp in area.spaces:
                if sp.type == "VIEW_3D":
                    sp.shading.type = "RENDERED"
                    if view != "none":
                        sp.region_3d.view_perspective = "CAMERA"


def main():
    a = B.args(extra)
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = (int(v) for v in a.res.split(","))

    wanted = [x.strip() for x in (a.render or "main,pc").split(",") if x.strip()]
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    out = a.out if os.path.isabs(a.out) else os.path.join(root, a.out) if a.out else \
        os.path.join(root, "assets", "_source", "blockout", "renders", "room_frames")
    os.makedirs(out, exist_ok=True)
    modes = ["on", "off"] if a.pc == "both" else [a.pc]
    quads = {}
    for mode in modes:
        setup(a.phase, a.samples, pc=(mode == "on"))
        for name in wanted:
            cam = make_camera(name)
            sc.camera = cam
            post(PHASES["day" if a.phase == "morning" else a.phase].get("vignette", 0.0), name)
            path = os.path.join(out, "room_%s_%s_pc_%s.png" % (name, a.phase, mode))
            sc.render.filepath = path
            bpy.ops.render.render(write_still=True)
            print("[room] %s" % path)
            quads[name] = screen_quad(cam)
    # Положение экрана не зависит от фазы и состояния ПК: одно на кадр
    import json
    with open(os.path.join(out, "room_screen.json"), "w", encoding="utf-8") as fh:
        json.dump({"pc": quads}, fh, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
