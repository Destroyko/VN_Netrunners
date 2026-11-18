"""Библиотека материалов: палитра как готовые cel-шейдеры в .blend.

Чтобы цвет брался из общего списка, а не из комплекта каждого ассета, материалы
нужны готовыми. Скрипт собирает их из palette.py и кладёт в один файл, который
подключается к любой сцене:

    File -> Append (или Link) -> palette_materials.blend -> Material -> выбрать

Имя материала повторяет имя цвета: `pal_wood_mid`, `pal_room.hero_wall`,
`pal_accent_teal`. Material Preview в окне Blender показывает их как есть.

Пересобрать:

    & "...blender.exe" -b --python tools\\blockout\\make_palette_lib.py

Повторный запуск перезаписывает файл целиком — правки в самом .blend не хранятся,
источник истины остаётся в palette.py.
"""

import os
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402

OUT = "assets/_source/blockout/palette_materials.blend"


def cel_material(name, hexcol, tones=3):
    """Один материал: ступенчатый свет, без блика.

    Diffuse, а не Principled: у Principled блик виден даже при Specular 0,
    а в этом стиле бликов нет совсем (docs/art/blender-scenes.md).
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (600, 0)
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.location = (-200, 0)
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2rgb = nt.nodes.new("ShaderNodeShaderToRGB")
    s2rgb.location = (0, 0)
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.location = (180, 0)
    ramp.color_ramp.interpolation = "CONSTANT"
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.location = (430, 0)

    tn = P.shades(hexcol, tones)
    els = ramp.color_ramp.elements
    while len(els) > 1:
        els.remove(els[-1])
    els[0].position = 0.0
    els[0].color = (*tn[0], 1.0)
    for i, t in enumerate(tn[1:], start=1):
        els.new(i / len(tn) + 0.12).color = (*t, 1.0)

    nt.links.new(dif.outputs[0], s2rgb.inputs[0])
    nt.links.new(s2rgb.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emit.inputs[0])
    nt.links.new(emit.outputs[0], out.inputs["Surface"])

    # Чтобы материал пережил сохранение без пользователей
    mat.use_fake_user = True
    # Цвет в окне вида Solid — чтобы сцена читалась и без рендера
    mat.diffuse_color = (*tn[-1], 1.0)
    return mat


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.engine = "BLENDER_EEVEE"

    made = 0
    for key, hexcol in P.all_colors().items():
        cel_material("pal_" + key.replace("/", "_"), hexcol)
        made += 1

    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    path = os.path.normpath(os.path.join(root, OUT))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path)
    print("[palette] материалов: %d -> %s" % (made, path))


main()
