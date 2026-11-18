"""Стиль сцены: ступенчатый свет, пастель, без бликов.

Накладывает на готовую сцену единый вид — тот, что описан в docs/art/blender-scenes.md,
раздел «Стиль: признаки». Материалы не делаются по одному на предмет: берётся базовый
цвет, который у объекта уже есть, и оборачивается в cel-шейдер. Поэтому скрипт
работает и на блокауте, и на сцене с чужими ассетами.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_detail.blend ^
        --python tools\\blockout\\style_cel.py -- --render room_desk --phase day

Ключи как у render_blend.py плюс --steps (число ступеней света) и --warm (теплота света).
Сцена не сохраняется: это режим показа, правки остаются за разработчиком.
"""

import os
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bl_common as B  # noqa: E402

# Пастельная палитра: светлота высокая, насыщенность низкая. Тёмно-синие стены
# и тёмный пол — решение разработчика (17.11.2026), остальное подобрано под них
TINT = {
    "wall": (0.33, 0.38, 0.52),
    "floor": (0.26, 0.24, 0.26),
    "wood": (0.62, 0.47, 0.33),
    "bed": (0.86, 0.84, 0.80),
    "pc": (0.16, 0.17, 0.20),
}


def base_color(mat):
    """Цвет, который у материала уже есть: Emission из блокаута или Principled."""
    if not mat or not mat.use_nodes:
        return (0.6, 0.6, 0.62)
    for n in mat.node_tree.nodes:
        if n.type == "EMISSION":
            return tuple(n.inputs[0].default_value)[:3]
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return tuple(n.inputs["Base Color"].default_value)[:3]
    return (0.6, 0.6, 0.62)


def shade(rgb, k):
    return tuple(min(1.0, max(0.0, c * k)) for c in rgb)


def celify(mat, steps=3):
    """Ступенчатый свет вместо плавного: Shader to RGB -> Color Ramp (Constant).

    Нижняя ступень — не чёрная, а тёмный холодный оттенок того же цвета: в этом стиле
    тень цветная, иначе кадр валится в контраст, которого в референсе нет.
    """
    if not mat:
        return
    col = base_color(mat)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    # Diffuse, а не Principled: в Principled блик живёт даже при Specular 0
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    s2rgb = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    # тень холоднее и темнее, свет — сам цвет
    tones = [shade(col, 0.45), shade(col, 0.72), col][-steps:]
    tones[0] = (tones[0][0] * 0.92, tones[0][1] * 0.96, min(1.0, tones[0][2] * 1.08))
    els = ramp.color_ramp.elements
    while len(els) > 1:
        els.remove(els[-1])
    els[0].position = 0.0
    els[0].color = (*tones[0], 1.0)
    for i, t in enumerate(tones[1:], start=1):
        e = els.new(i / len(tones) + 0.12)
        e.color = (*t, 1.0)
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2rgb.inputs[0])
    nt.links.new(s2rgb.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emit.inputs[0])
    nt.links.new(emit.outputs[0], out.inputs["Surface"])


def soft_light(phase="day", warm=1.0):
    """Мягкий общий свет плюс окно. Глухих тёмных углов в этом стиле нет."""
    sc = bpy.context.scene
    world = bpy.data.worlds.get("cel_world") or bpy.data.worlds.new("cel_world")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    # В свежесозданном мире ноды Background может не быть — ищем по типу, а не по имени
    bg = next((n for n in nt.nodes if n.type == "BACKGROUND"), None)
    if bg is None:
        bg = nt.nodes.new("ShaderNodeBackground")
        out = next((n for n in nt.nodes if n.type == "OUTPUT_WORLD"), None)
        if out is None:
            out = nt.nodes.new("ShaderNodeOutputWorld")
        nt.links.new(bg.outputs[0], out.inputs["Surface"])
    fill = {"day": (0.52, 0.56, 0.68, 1.0), "night": (0.10, 0.12, 0.20, 1.0)}
    bg.inputs[0].default_value = fill.get(phase, fill["day"])
    bg.inputs[1].default_value = 0.55 if phase == "day" else 0.18

    # Окно комнаты героя: большой источник — значит мягкая тень
    for name, loc, size, energy, col in (
        ("cel_window", (1.7, 7.05, 1.55), 2.6, 900.0 * warm, (1.0, 0.95, 0.86)),
    ):
        lamp = bpy.data.lights.get(name) or bpy.data.lights.new(name, type="AREA")
        lamp.size = size
        lamp.energy = energy if phase == "day" else energy * 0.08
        lamp.color = col
        ob = bpy.data.objects.get(name)
        if ob is None:
            ob = bpy.data.objects.new(name, lamp)
            sc.collection.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (1.5708, 0.0, 3.1416)


def main():
    def extra(p):
        p.add_argument("--tones", type=int, default=3, help="ступеней света: 2 или 3")
        p.add_argument("--warm", type=float, default=1.0, help="сила света из окна")

    a = B.args(extra)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
    # в чужой сцене процент может стоять любой — иначе кадр молча выходит вдвое меньше
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.eevee.taa_render_samples = 64

    for mat in bpy.data.materials:
        celify(mat, a.tones)
    soft_light(a.phase, a.warm)

    cams = {o.name: o for o in bpy.data.objects if o.type == "CAMERA"}
    out = B.resolve(a.out) if a.out else B.resolve("assets/_source/blockout/cel")
    files = B.render(cams, out, "_cel_%s" % a.phase, a.render)
    print("[cel] отрендерено: %d" % len(files))


main()
