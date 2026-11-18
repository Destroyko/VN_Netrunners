"""Cel-шейдер одной функцией: ступенчатый свет, цветная тень, фактура.

Один источник на все скрипты. Раньше шейдер жил в двух местах — в библиотеке
материалов и в наложении стиля на сцену, — и они начали расходиться: фактуру
добавили только в одно. Теперь оба зовут build() отсюда.

Что делает шейдер и почему (docs/art/blender-scenes.md, «Стиль: признаки»):
- Diffuse, а не Principled: у Principled блик виден даже при Specular 0, а в этом
  стиле бликов нет совсем;
- Shader to RGB -> Color Ramp в режиме Constant: свет ступенями, без растяжек;
- нижняя ступень холоднее и темнее — тень цветная, иначе кадр валится в контраст;
- неоднородность тона и штрихи: ровная заливка читается как вектор, а не как рисунок.
"""

DEFAULTS = {"tones": 3, "texture": 0.1, "scale": 10.0, "hatch": 0.8}


def shades(rgb, tones=3):
    """Ступени одного цвета. Тень не просто темнее — она холоднее."""
    ks = (0.55, 1.0) if tones == 2 else (0.45, 0.74, 1.0)
    out = []
    for k in ks:
        r, g, b = (min(1.0, c * k) for c in rgb)
        if k < 1.0:
            cool = (1.0 - k) * 0.5
            r *= 1.0 - cool * 0.35
            b = min(1.0, b * (1.0 + cool * 0.45))
        out.append((r, g, b))
    return out


def build(nt, rgb, tones=None, texture=None, scale=None, hatch=None):
    """Собрать шейдер в пустом дереве узлов материала. Возвращает выходную ноду."""
    tones = DEFAULTS["tones"] if tones is None else tones
    texture = DEFAULTS["texture"] if texture is None else texture
    scale = DEFAULTS["scale"] if scale is None else scale
    hatch = DEFAULTS["hatch"] if hatch is None else hatch

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

    tn = shades(rgb, tones)
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

    emit = nt.nodes.new("ShaderNodeEmission")
    emit.location = (520, 20)
    nt.links.new(src, emit.inputs[0])
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    return tn[-1]
