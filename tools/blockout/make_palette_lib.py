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


def cel_material(name, hexcol, kind=None, texture=None, scale=None, hatch=None):
    """Один материал палитры: цвет плюс тип поверхности.

    Шейдер собирает cel_shader — он же в style_cel.py, чтобы вид материала
    в окне Blender совпадал с видом в рендере. Ступени, фактуру и блик задаёт
    профиль типа, а не отдельные числа на каждый материал.
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    light = C.build(mat.node_tree, P.srgb(hexcol), None, texture, scale, hatch, kind)
    # Чтобы материал пережил сохранение без пользователей
    mat.use_fake_user = True
    # Цвет в режиме Solid — чтобы сцена читалась и без рендера
    mat.diffuse_color = (*light, 1.0)
    return mat


def main():
    # Аргументы после -- : те же ручки фактуры, что у style_cel.py
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[::2], argv[1::2]))
    # Числа фактуры теперь берутся из профиля материала; ключи оставлены,
    # чтобы можно было прогнать всю библиотеку с другой силой фактуры
    texture = float(opts["--texture"]) if "--texture" in opts else None
    scale = float(opts["--tex-scale"]) if "--tex-scale" in opts else None
    hatch = float(opts["--hatch"]) if "--hatch" in opts else None

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.engine = "BLENDER_EEVEE"

    made = 0
    for key, hexcol in P.all_colors().items():
        base = "pal_" + key.replace("/", "_")
        for kind in P.kinds_for(key):
            # Имя говорит и цвет, и материал: pal_accent_red_metal
            cel_material("%s_%s" % (base, kind), hexcol, kind)
            made += 1

    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    path = os.path.normpath(os.path.join(root, OUT))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path)
    print("[palette] материалов: %d -> %s" % (made, path))


main()
