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
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402

OUT = "assets/_source/blockout/palette_materials.blend"


def cel_material(name, hexcol, tones=3, texture=None, scale=None, hatch=None):
    """Один материал палитры. Шейдер собирает cel_shader — он же в style_cel.py,
    чтобы вид материала в окне Blender совпадал с видом в рендере."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    light = C.build(mat.node_tree, P.srgb(hexcol), tones, texture, scale, hatch)
    # Чтобы материал пережил сохранение без пользователей
    mat.use_fake_user = True
    # Цвет в режиме Solid — чтобы сцена читалась и без рендера
    mat.diffuse_color = (*light, 1.0)
    return mat


def main():
    # Аргументы после -- : те же ручки фактуры, что у style_cel.py
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[::2], argv[1::2]))
    texture = float(opts.get("--texture", C.DEFAULTS["texture"]))
    scale = float(opts.get("--tex-scale", C.DEFAULTS["scale"]))
    hatch = float(opts.get("--hatch", C.DEFAULTS["hatch"]))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.engine = "BLENDER_EEVEE"

    made = 0
    for key, hexcol in P.all_colors().items():
        cel_material("pal_" + key.replace("/", "_"), hexcol,
                     texture=texture, scale=scale, hatch=hatch)
        made += 1

    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    path = os.path.normpath(os.path.join(root, OUT))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path)
    print("[palette] материалов: %d (фактура %.2f, штрих %.2f) -> %s"
          % (made, texture, hatch, path))


main()
