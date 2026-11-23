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
                "spec": 0.55, "gloss": 0.12, "cool": 1.4},
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


def build(nt, rgb, tones=None, texture=None, scale=None, hatch=None, kind=None):
    """Собрать шейдер в пустом дереве узлов материала. Возвращает цвет света.

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
    ramp.color_ramp.interpolation = "CONSTANT"

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
        coord = nt.nodes.new("ShaderNodeTexCoord")
        coord.location = (-250, -260)
        vec = coord.outputs["Object"]
        if hatch > 0.0:
            # Растягиваем координаты по одной оси: тот же шум становится мазками
            mp = nt.nodes.new("ShaderNodeMapping")
            mp.location = (-60, -260)
            mp.inputs["Scale"].default_value = (1.0, 1.0 + hatch * 10.0, 1.0)
            nt.links.new(vec, mp.inputs["Vector"])
            vec = mp.outputs["Vector"]
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
        ge.new(1.0 - spec * 0.55).color = (spec, spec, spec, 1.0)
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
