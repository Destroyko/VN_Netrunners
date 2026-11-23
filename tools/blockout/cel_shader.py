"""Cel-шейдер одной функцией: ступенчатый свет, цветная тень, фактура, тип материала.

Один источник на все скрипты. Раньше шейдер жил в двух местах — в библиотеке
материалов и в наложении стиля на сцену, — и они начали расходиться.

Что делает шейдер и почему (docs/art/blender-scenes.md, «Стиль: признаки»):
- Shader to RGB -> Color Ramp в режиме Constant: свет ступенями, без растяжек;
- нижняя ступень холоднее и темнее — тень цветная, иначе кадр валится в контраст;
- неоднородность тона и штрихи: ровная заливка читается как вектор, а не как рисунок.

**Цвет и материал разделены.** Цвет — параметр, тип материала — профиль: он решает,
сколько ступеней у света, насколько холодная тень, есть ли блик и какая фактура.
Один и тот же красный на бумаге, дереве и металле выглядит по-разному, и для этого
не нужно заводить три красных.
"""

# Профили материалов. Числа подобраны так, чтобы тип читался с первого взгляда,
# но кадр не распадался: блики только там, где без них предмет не узнать
MATERIALS = {
    # матовое и мягкое: свет ложится ровно, бликов нет совсем
    "paper":   {"tones": 2, "texture": 0.13, "scale": 16.0, "hatch": 0.9,
                "spec": 0.0, "cool": 1.0},
    "fabric":  {"tones": 3, "texture": 0.17, "scale": 7.0, "hatch": 0.4,
                "spec": 0.0, "cool": 1.1},
    "wall":    {"tones": 3, "texture": 0.10, "scale": 10.0, "hatch": 0.8,
                "spec": 0.0, "cool": 1.0},
    # дерево: фактура вдоль волокон, едва заметный широкий блик
    "wood":    {"tones": 3, "texture": 0.11, "scale": 9.0, "hatch": 1.4,
                "spec": 0.10, "gloss": 0.42, "cool": 0.8},
    # пластик: ровный, мягкий блик пятном
    "plastic": {"tones": 2, "texture": 0.05, "scale": 12.0, "hatch": 0.0,
                "spec": 0.22, "gloss": 0.30, "cool": 0.9},
    # металл: узкий яркий блик и холодная контрастная тень — без этого не металл
    "metal":   {"tones": 3, "texture": 0.04, "scale": 18.0, "hatch": 0.2,
                "spec": 0.32, "gloss": 0.12, "cool": 1.4},
    # стекло: сквозь него видно. Оттенок почти не виден (alpha — доля непрозрачности),
    # зато блик остаётся плотным: стекло узнают по бликам, а не по цвету
    "glass":   {"tones": 2, "texture": 0.0, "scale": 10.0, "hatch": 0.0,
                "spec": 0.75, "gloss": 0.06, "cool": 1.0, "alpha": 0.16},
    # растения: мягкая фактура, лёгкий влажный отблеск
    "plant":   {"tones": 3, "texture": 0.15, "scale": 13.0, "hatch": 0.6,
                "spec": 0.12, "gloss": 0.35, "cool": 0.9},
    # свечение: не освещаемая поверхность, а источник. Ступеней, тени и блика нет —
    # цвет палитры умножается на силу. Сила 2.5 ярче белого, и канал упирается
    # в единицу: светодиод выглядит горящим, а не просто светлым
    "glow":    {"tones": 1, "texture": 0.0, "scale": 10.0, "hatch": 0.0,
                "spec": 0.0, "cool": 1.0, "emit": 2.5},
}
DEFAULT_KIND = "wall"


DEFAULTS = {"tones": 3, "texture": 0.1, "scale": 10.0, "hatch": 0.8}


def shades(rgb, tones=3, cool=1.0):
    """Ступени одного цвета. Тень не просто темнее — она холоднее.

    cool — насколько холоднее: у металла тень уходит в синеву сильнее, у дерева
    остаётся тёплой. Это половина того, чем материалы отличаются на глаз.
    """
    ks = (0.55, 1.0) if tones == 2 else (0.45, 0.74, 1.0)
    out = []
    for k in ks:
        r, g, b = (min(1.0, c * k) for c in rgb)
        if k < 1.0:
            shift = (1.0 - k) * 0.5 * cool
            r *= 1.0 - shift * 0.35
            b = min(1.0, b * (1.0 + shift * 0.45))
        out.append((r, g, b))
    return out


def _build_glow(nt, rgb, strength):
    """Свечение: Emission напрямую, без cel-рампы. Возвращает цвет для режима Solid."""
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (300, 0)
    em = nt.nodes.new("ShaderNodeEmission")
    em.location = (80, 0)
    em.inputs["Color"].default_value = (*rgb, 1.0)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return rgb


# Переход света в ступенях: "CONSTANT" — резкие полосы, "LINEAR" — плавный градиент.
# Разработчик (23.11.2026): полосы на стенах и предметах выглядят слишком мультяшно,
# переход должен быть плавным. Блик остаётся ступенчатым.
RAMP_MODE = "LINEAR"

LIGHT_VERSION = 7        # меняется при правке узла: сцены с прежней версией пересоберут его сами


def light_group():
    """Общий узел «отклик на свет» VN_Light: один на все материалы.

    Ступень цвета выбирается по яркости света, но сама ступень не темнеет: самая тёмная —
    цвет материала с поправкой на тень, и сколько света ни убавь, ночь не наступает, а цвет
    света теряется. Узел добавляет два числа, общие для всей сцены (они лежат внутри
    узла, поэтому правятся в одном месте, а не в каждом материале):
    - floor — до какой доли тон гаснет без света. 1 — как раньше, 0,2 — ночь;
    - tint — насколько цвет света окрашивает поверхность. 0 — не окрашивает.
    Освещённое остаётся ярким, слабо освещённое становится тёмным ступенями.
    """
    import bpy
    g = bpy.data.node_groups.get("VN_Light")
    if g is not None:
        if g.get("ver") == LIGHT_VERSION:
            return g
        g.name = "VN_Light_old"             # прежняя версия: материалы перейдут на новую при обновлении
    g = bpy.data.node_groups.new("VN_Light", "ShaderNodeTree")
    g["ver"] = LIGHT_VERSION
    g.interface.new_socket("Color", in_out="OUTPUT", socket_type="NodeSocketColor")
    g.interface.new_socket("Tone", in_out="INPUT", socket_type="NodeSocketColor")
    g.interface.new_socket("Light", in_out="INPUT", socket_type="NodeSocketColor")
    nodes, links = g.nodes, g.links
    gin = nodes.new("NodeGroupInput")
    gin.location = (-900, 0)
    gout = nodes.new("NodeGroupOutput")
    gout.location = (900, 0)

    lum = nodes.new("ShaderNodeRGBToBW")
    lum.location = (-700, -120)
    links.new(gin.outputs["Light"], lum.inputs[0])

    # ступени отклика: чем светлее, тем ближе множитель к единице
    steps = nodes.new("ShaderNodeValToRGB")
    steps.location = (-500, -200)
    steps.color_ramp.interpolation = RAMP_MODE
    els = steps.color_ramp.elements
    els[0].position = 0.0
    els[0].color = (0.0, 0.0, 0.0, 1.0)
    for pos, v in ((0.453, 0.75), (0.787, 1.0)):
        els.new(pos).color = (v, v, v, 1.0)
    links.new(lum.outputs[0], steps.inputs[0])

    floor = nodes.new("ShaderNodeValue")
    floor.name = floor.label = "floor"
    floor.location = (-500, -420)
    floor.outputs[0].default_value = 1.0
    inv = nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    inv.location = (-300, -420)
    links.new(floor.outputs[0], inv.inputs[1])
    resp = nodes.new("ShaderNodeMath")
    resp.operation = "MULTIPLY_ADD"
    resp.use_clamp = True
    resp.location = (-100, -250)
    links.new(steps.outputs[0], resp.inputs[0])
    links.new(inv.outputs[0], resp.inputs[1])
    links.new(floor.outputs[0], resp.inputs[2])

    # цвет света: сам свет, нормированный на яркость, чтобы он менял оттенок, а не тон
    den = nodes.new("ShaderNodeMath")
    den.operation = "MAXIMUM"
    den.inputs[1].default_value = 0.001
    den.location = (-500, 120)
    links.new(lum.outputs[0], den.inputs[0])
    rec = nodes.new("ShaderNodeMath")
    rec.operation = "DIVIDE"
    rec.inputs[0].default_value = 1.0
    rec.location = (-300, 120)
    links.new(den.outputs[0], rec.inputs[1])
    hue = nodes.new("ShaderNodeVectorMath")
    hue.operation = "SCALE"
    hue.location = (-100, 120)
    links.new(gin.outputs["Light"], hue.inputs[0])
    links.new(rec.outputs[0], hue.inputs["Scale"])
    tint = nodes.new("ShaderNodeValue")
    tint.name = tint.label = "tint"
    tint.location = (-100, 320)
    tint.outputs[0].default_value = 0.0
    mixc = nodes.new("ShaderNodeMix")
    mixc.data_type = "RGBA"
    mixc.clamp_result = True
    mixc.location = (120, 140)
    mixc.inputs[6].default_value = (1.0, 1.0, 1.0, 1.0)
    # окраска светом растёт с яркостью: у далёкого слабого света оттенок нормируется в полный,
    # и лампа красила бы оранжевым всю стену, до которой почти не доходит
    tw = nodes.new("ShaderNodeMath")
    tw.operation = "MULTIPLY"
    tw.use_clamp = True
    tw.inputs[1].default_value = 8.0
    tw.location = (-300, 320)
    links.new(lum.outputs[0], tw.inputs[0])
    tf = nodes.new("ShaderNodeMath")
    tf.operation = "MULTIPLY"
    tf.location = (-100, 420)
    links.new(tint.outputs[0], tf.inputs[0])
    links.new(tw.outputs[0], tf.inputs[1])
    links.new(tf.outputs[0], mixc.inputs[0])
    links.new(hue.outputs[0], mixc.inputs[7])

    # теневой тон: чем меньше света, тем сильнее цвет тянется к ночному оттенку, сохраняя
    # яркость. Без этого в тени вещи остаются своего цвета (коричневый стул, жёлтый шкаф),
    # а ночная комната должна быть единой синевой, где лампа создаёт контраст
    tl = nodes.new("ShaderNodeRGBToBW")
    tl.location = (-500, -620)
    links.new(gin.outputs["Tone"], tl.inputs[0])
    night = nodes.new("ShaderNodeRGB")
    night.name = night.label = "night"
    night.location = (-500, -780)
    night.outputs[0].default_value = (0.30, 0.45, 1.0, 1.0)
    nlum = nodes.new("ShaderNodeVectorMath")
    nlum.operation = "SCALE"
    nlum.location = (-300, -700)
    links.new(night.outputs[0], nlum.inputs[0])
    links.new(tl.outputs[0], nlum.inputs["Scale"])
    nbright = nodes.new("ShaderNodeVectorMath")
    nbright.operation = "SCALE"
    nbright.location = (-100, -700)
    nbright.inputs["Scale"].default_value = 1.1      # синий светлее по яркости, чем по цвету
    links.new(nlum.outputs[0], nbright.inputs[0])
    shadow = nodes.new("ShaderNodeValue")
    shadow.name = shadow.label = "shadow"
    shadow.location = (-300, -900)
    shadow.outputs[0].default_value = 0.0
    dark = nodes.new("ShaderNodeMath")
    dark.operation = "SUBTRACT"
    dark.inputs[0].default_value = 1.0
    dark.location = (-300, -560)
    links.new(steps.outputs[0], dark.inputs[1])
    wgt = nodes.new("ShaderNodeMath")
    wgt.operation = "MULTIPLY"
    wgt.use_clamp = True
    wgt.location = (-100, -560)
    links.new(dark.outputs[0], wgt.inputs[0])
    links.new(shadow.outputs[0], wgt.inputs[1])
    shade = nodes.new("ShaderNodeMix")
    shade.data_type = "RGBA"
    shade.clamp_result = True
    shade.location = (120, -560)
    links.new(wgt.outputs[0], shade.inputs[0])
    links.new(gin.outputs["Tone"], shade.inputs[6])
    links.new(nbright.outputs[0], shade.inputs[7])

    mul = nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    mul.location = (360, 0)
    links.new(shade.outputs[2], mul.inputs[0])
    links.new(mixc.outputs[2], mul.inputs[1])
    dim = nodes.new("ShaderNodeVectorMath")
    dim.operation = "SCALE"
    dim.location = (580, 0)
    links.new(mul.outputs[0], dim.inputs[0])
    links.new(resp.outputs[0], dim.inputs["Scale"])
    # посадка на пол: тёмный градиент у пола (grad), 0 — выключен. Затемнение в контактах
    # через узел Ambient Occlusion не годится: в EEVEE он внутри Shader to RGB даёт единицу
    geo = nodes.new("ShaderNodeNewGeometry")
    geo.location = (360, -820)
    sep = nodes.new("ShaderNodeSeparateXYZ")
    sep.location = (560, -820)
    links.new(geo.outputs["Position"], sep.inputs[0])
    grad = nodes.new("ShaderNodeValue")
    grad.name = grad.label = "grad"
    grad.location = (360, -1000)
    grad.outputs[0].default_value = 0.0
    g1 = nodes.new("ShaderNodeMath")
    g1.operation = "SUBTRACT"
    g1.inputs[0].default_value = 1.0
    g1.location = (560, -1000)
    links.new(grad.outputs[0], g1.inputs[1])
    gm = nodes.new("ShaderNodeMapRange")
    gm.location = (760, -840)
    gm.clamp = True
    gm.inputs["From Min"].default_value = 0.0
    gm.inputs["From Max"].default_value = 0.45       # высота градиента от пола, метры
    gm.inputs["To Max"].default_value = 1.0
    links.new(sep.outputs["Z"], gm.inputs["Value"])
    links.new(g1.outputs[0], gm.inputs["To Min"])

    land = nodes.new("ShaderNodeVectorMath")
    land.operation = "SCALE"
    land.location = (1300, 0)
    links.new(dim.outputs[0], land.inputs[0])
    links.new(gm.outputs[0], land.inputs["Scale"])
    links.new(land.outputs[0], gout.inputs["Color"])
    return g


def unify_light_groups():
    """Слить копии узла света VN_Light.001, .002 ... в основной. Возвращает число слитых.

    Материал из браузера ассетов приносит с собой свою копию узла: имя `VN_Light` уже занято
    сценой. У копии свои числа floor и tint (дневные), и предмет с таким материалом не темнеет
    ночью. Копии той же версии, что основной узел, перенаправляются на него.
    """
    import bpy
    main = bpy.data.node_groups.get("VN_Light")
    if main is None:
        return 0
    n = 0
    for mat in bpy.data.materials:
        if not mat.use_nodes or mat.node_tree is None:
            continue
        for node in mat.node_tree.nodes:
            tree = getattr(node, "node_tree", None)
            if node.type == "GROUP" and tree is not None and tree is not main                     and tree.name.startswith("VN_Light.") and tree.get("ver") == main.get("ver"):
                node.node_tree = main
                n += 1
    for g in list(bpy.data.node_groups):
        if g.name.startswith("VN_Light.") and g.users == 0:
            bpy.data.node_groups.remove(g)
    return n


def set_light_response(floor=None, tint=None, shadow=None, night=None, grad=None):
    """Выставить числа общего узла VN_Light одним вызовом на всю сцену.

    shadow — насколько неосвещённое тянется к ночному оттенку (0 — не тянется),
    night — этот оттенок (r, g, b)."""
    import bpy
    g = bpy.data.node_groups.get("VN_Light")
    if g is None:
        return False
    if floor is not None:
        g.nodes["floor"].outputs[0].default_value = floor
    if tint is not None:
        g.nodes["tint"].outputs[0].default_value = tint
    if shadow is not None:
        g.nodes["shadow"].outputs[0].default_value = shadow
    if night is not None:
        g.nodes["night"].outputs[0].default_value = (*night, 1.0)
    if grad is not None:
        g.nodes["grad"].outputs[0].default_value = grad
    return True


def _grain_coords(nt, geo, k):
    """Координаты шума, растянутые в штрихи на ЛЮБОЙ грани, а не вдоль одной оси объекта.

    Раньше шум сжимался по локальной оси Y объекта, и штрихи были только на гранях, где эта ось
    лежит в плоскости: на грани, перпендикулярной ей, получалась «мазня» (спинка кровати, бок
    шкафа). Теперь направление считается по самой грани: на вертикальных гранях волокно идёт
    вверх (сжатие по горизонтали в плоскости грани), на горизонтальных вдоль X (сжатие по Y).
    Координаты мировые, поэтому двигать предмет можно, но узор при этом сдвигается.
    k — во сколько раз сжимается поперечная ось (чем больше, тем тоньше штрихи).
    """
    n = geo.outputs["True Normal"]
    up = nt.nodes.new("ShaderNodeCombineXYZ")
    up.inputs["Z"].default_value = 1.0
    up.location = (-700, -420)
    cr = nt.nodes.new("ShaderNodeVectorMath")
    cr.operation = "CROSS_PRODUCT"
    cr.location = (-520, -420)
    nt.links.new(n, cr.inputs[0])
    nt.links.new(up.outputs[0], cr.inputs[1])
    nz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nz.location = (-520, -600)
    nt.links.new(n, nz.inputs[0])
    az = nt.nodes.new("ShaderNodeMath")
    az.operation = "ABSOLUTE"
    az.location = (-340, -600)
    nt.links.new(nz.outputs["Z"], az.inputs[0])
    horiz = nt.nodes.new("ShaderNodeMath")
    horiz.operation = "GREATER_THAN"
    horiz.inputs[1].default_value = 0.7
    horiz.location = (-160, -600)
    nt.links.new(az.outputs[0], horiz.inputs[0])
    along_y = nt.nodes.new("ShaderNodeCombineXYZ")
    along_y.inputs["Y"].default_value = 1.0
    along_y.location = (-340, -420)
    mixh = nt.nodes.new("ShaderNodeMix")
    mixh.data_type = "VECTOR"
    mixh.location = (-160, -420)
    nt.links.new(horiz.outputs[0], mixh.inputs[0])
    nt.links.new(cr.outputs[0], mixh.inputs[4])
    nt.links.new(along_y.outputs[0], mixh.inputs[5])
    nrm = nt.nodes.new("ShaderNodeVectorMath")
    nrm.operation = "NORMALIZE"
    nrm.location = (20, -420)
    nt.links.new(mixh.outputs[1], nrm.inputs[0])
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.location = (200, -420)
    nt.links.new(geo.outputs["Position"], dot.inputs[0])
    nt.links.new(nrm.outputs[0], dot.inputs[1])
    amt = nt.nodes.new("ShaderNodeMath")
    amt.operation = "MULTIPLY"
    amt.inputs[1].default_value = k - 1.0
    amt.location = (380, -420)
    nt.links.new(dot.outputs["Value"], amt.inputs[0])
    shift = nt.nodes.new("ShaderNodeVectorMath")
    shift.operation = "SCALE"
    shift.location = (560, -420)
    nt.links.new(nrm.outputs[0], shift.inputs[0])
    nt.links.new(amt.outputs[0], shift.inputs["Scale"])
    out = nt.nodes.new("ShaderNodeVectorMath")
    out.operation = "ADD"
    out.location = (740, -420)
    nt.links.new(geo.outputs["Position"], out.inputs[0])
    nt.links.new(shift.outputs[0], out.inputs[1])
    return out.outputs[0]


def build(nt, rgb, tones=None, texture=None, scale=None, hatch=None, kind=None, pattern=None):
    """Собрать шейдер в пустом дереве узлов материала. Возвращает цвет света.

    pattern — узор поверх цвета (слот узора): {"image": картинка, "strength": доля яркости,
    "lo", "hi": границы яркости картинки, "scale": (x, y, z) для UV}. Цвет остаётся палитровым,
    узор светлит и темнит тот же тон, а свет и тень считает обычный шейдер.

    kind — профиль материала из MATERIALS. Он задаёт значения по умолчанию,
    а переданные явно их перекрывают: так можно взять «металл» и всё же
    приглушить ему фактуру для конкретного предмета.
    """
    prof = MATERIALS.get(kind or DEFAULT_KIND, MATERIALS[DEFAULT_KIND])
    if "emit" in prof:
        return _build_glow(nt, rgb, prof["emit"])
    tones = prof["tones"] if tones is None else tones
    texture = prof["texture"] if texture is None else texture
    scale = prof["scale"] if scale is None else scale
    hatch = prof["hatch"] if hatch is None else hatch
    spec = prof.get("spec", 0.0)
    gloss = prof.get("gloss", 0.25)
    cool = prof.get("cool", 1.0)

    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (700, 0)
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.location = (-250, 0)
    dif.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    s2rgb = nt.nodes.new("ShaderNodeShaderToRGB")
    s2rgb.location = (-60, 0)
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.location = (120, 0)
    ramp.color_ramp.interpolation = RAMP_MODE

    tn = shades(rgb, tones, cool)
    els = ramp.color_ramp.elements
    while len(els) > 1:
        els.remove(els[-1])
    els[0].position = 0.0
    els[0].color = (*tn[0], 1.0)
    for i, t in enumerate(tn[1:], start=1):
        els.new(i / len(tn) + 0.12).color = (*t, 1.0)

    nt.links.new(dif.outputs[0], s2rgb.inputs[0])
    nt.links.new(s2rgb.outputs[0], ramp.inputs[0])

    src = ramp.outputs[0]
    if texture > 0.0:
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        geo.location = (-700, -260)
        pos = geo.outputs["Position"]
        vec = pos
        if hatch > 0.0:
            vec = _grain_coords(nt, geo, 1.0 + hatch * 10.0)
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.location = (120, -260)
        noise.inputs["Scale"].default_value = scale
        noise.inputs["Detail"].default_value = 2.0
        noise.inputs["Roughness"].default_value = 0.5
        nt.links.new(vec, noise.inputs["Vector"])
        rng = nt.nodes.new("ShaderNodeMapRange")
        rng.location = (320, -260)
        rng.inputs["From Min"].default_value = 0.0
        rng.inputs["From Max"].default_value = 1.0
        rng.inputs["To Min"].default_value = 1.0 - texture
        rng.inputs["To Max"].default_value = 1.0 + texture
        nt.links.new(noise.outputs["Fac"], rng.inputs["Value"])
        mul = nt.nodes.new("ShaderNodeVectorMath")
        mul.location = (480, -120)
        mul.operation = "MULTIPLY"
        nt.links.new(ramp.outputs[0], mul.inputs[0])
        nt.links.new(rng.outputs[0], mul.inputs[1])
        src = mul.outputs[0]

    if pattern:
        # слот узора: яркость картинки лишь светлит и темнит тон, цвет остаётся палитровым
        uv = nt.nodes.new("ShaderNodeTexCoord")
        uv.location = (-250, -520)
        mp2 = nt.nodes.new("ShaderNodeMapping")
        mp2.location = (-60, -520)
        mp2.inputs["Scale"].default_value = tuple(pattern.get("scale", (1.0, 1.0, 1.0)))
        nt.links.new(uv.outputs["UV"], mp2.inputs["Vector"])
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.location = (120, -520)
        tex.image = pattern["image"]
        tex.extension = "REPEAT"
        nt.links.new(mp2.outputs[0], tex.inputs["Vector"])
        bw = nt.nodes.new("ShaderNodeRGBToBW")
        bw.location = (320, -520)
        nt.links.new(tex.outputs["Color"], bw.inputs[0])
        pr = nt.nodes.new("ShaderNodeMapRange")
        pr.location = (480, -520)
        pr.clamp = True
        k = pattern.get("strength", 0.18)
        pr.inputs["From Min"].default_value = pattern["lo"]
        pr.inputs["From Max"].default_value = pattern["hi"]
        pr.inputs["To Min"].default_value = 1.0 - k
        pr.inputs["To Max"].default_value = 1.0 + k
        nt.links.new(bw.outputs[0], pr.inputs["Value"])
        pm = nt.nodes.new("ShaderNodeVectorMath")
        pm.operation = "SCALE"
        pm.location = (660, -380)
        nt.links.new(src, pm.inputs[0])
        nt.links.new(pr.outputs[0], pm.inputs["Scale"])
        src = pm.outputs[0]

    # отклик на свет: ночью без света тон гаснет, цвет света окрашивает поверхность
    lg = nt.nodes.new("ShaderNodeGroup")
    lg.node_tree = light_group()
    lg.location = (360, -40)
    nt.links.new(src, lg.inputs["Tone"])
    nt.links.new(s2rgb.outputs[0], lg.inputs["Light"])
    src = lg.outputs["Color"]

    if spec > 0.0:
        # Блик тоже ступенчатый: гладкий блик выдал бы фотореализм, а резкое
        # пятно читается как «металл» или «пластик» и остаётся в стиле
        gl = nt.nodes.new("ShaderNodeBsdfGlossy")
        gl.location = (-250, 240)
        gl.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
        gl.inputs["Roughness"].default_value = gloss
        g2rgb = nt.nodes.new("ShaderNodeShaderToRGB")
        g2rgb.location = (-60, 240)
        gramp = nt.nodes.new("ShaderNodeValToRGB")
        gramp.location = (120, 240)
        gramp.color_ramp.interpolation = "CONSTANT"
        ge = gramp.color_ramp.elements
        while len(ge) > 1:
            ge.remove(ge[-1])
        ge[0].position = 0.0
        ge[0].color = (0.0, 0.0, 0.0, 1.0)
        # порог тем выше, чем слабее блик: у дерева он виден только на самом краю
        # Тёмному материалу блик слабее: плоская грань перед ярким окном отражает его целиком,
        # и пятно в полную силу превращало чёрный корпус днём в белый
        lum = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
        k = spec * max(0.1, min(1.0, lum / 0.12))
        ge.new(1.0 - spec * 0.55).color = (k, k, k, 1.0)
        nt.links.new(gl.outputs[0], g2rgb.inputs[0])
        nt.links.new(g2rgb.outputs[0], gramp.inputs[0])
        add = nt.nodes.new("ShaderNodeVectorMath")
        add.location = (480, 120)
        add.operation = "ADD"
        nt.links.new(src, add.inputs[0])
        nt.links.new(gramp.outputs[0], add.inputs[1])
        src = add.outputs[0]

    emit = nt.nodes.new("ShaderNodeEmission")
    emit.location = (620, 20)
    nt.links.new(src, emit.inputs[0])
    alpha = prof.get("alpha")
    if alpha is None:
        nt.links.new(emit.outputs[0], out.inputs["Surface"])
    else:
        # Прозрачный материал: смесь прозрачного и закрашенного. Доля закрашенного —
        # alpha плюс сам блик, поэтому стекло почти невидимо, а блик на нём плотный
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        tr.location = (620, -160)
        mix = nt.nodes.new("ShaderNodeMixShader")
        mix.location = (860, 0)
        fac = nt.nodes.new("ShaderNodeMath")
        fac.location = (620, 220)
        fac.operation = "ADD"
        fac.use_clamp = True
        fac.inputs[1].default_value = alpha
        if spec > 0.0:
            nt.links.new(gramp.outputs[0], fac.inputs[0])
        else:
            fac.inputs[0].default_value = 0.0
        nt.links.new(fac.outputs[0], mix.inputs[0])
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(emit.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
    return tn[-1]


def surface(mat, kind):
    """Режим поверхности материала. Стекло рисуется с настоящей прозрачностью (Blended):
    в режиме Dithered прозрачность зашумлена и при малом числе проходов зернит."""
    try:
        mat.surface_render_method = "BLENDED" if kind == "glass" else "DITHERED"
    except Exception:
        pass
