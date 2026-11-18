"""Обновить материалы палитры прямо в сцене.

`Append` делает копию: материал, подключённый к сцене, живёт своей жизнью и после
пересборки библиотеки не меняется. Этот скрипт проходит по материалам сцены с именем
`pal_*`, находит их цвет в палитре и пересобирает шейдер заново — цвет, ступени,
фактуру. Сцена сохраняется.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_work.blend ^
        --python tools\\blockout\\refresh_palette.py

Можно задать фактуру: `-- --texture 0.12 --hatch 0.5 --tex-scale 8`.
Материалы не из палитры (`pal_*`) скрипт не трогает.
"""

import os
import re
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[::2], argv[1::2]))
    texture = float(opts.get("--texture", C.DEFAULTS["texture"]))
    scale = float(opts.get("--tex-scale", C.DEFAULTS["scale"]))
    hatch = float(opts.get("--hatch", C.DEFAULTS["hatch"]))
    dry = "--dry" in argv

    # ключ палитры -> цвет; имя материала получено заменой "/" на "_"
    table = {("pal_" + k.replace("/", "_")): v for k, v in P.all_colors().items()}

    done, skipped = [], []
    for mat in bpy.data.materials:
        if not mat.name.startswith("pal_"):
            continue
        # у копий Blender добавляет .001 — отрезаем только этот суффикс:
        # в именах комнат точка своя (pal_room.hero_wall), её трогать нельзя
        base = re.sub(r"\.\d{3}$", "", mat.name)
        hexcol = table.get(base)
        if hexcol is None:
            skipped.append(mat.name)
            continue
        if not dry:
            mat.use_nodes = True
            light = C.build(mat.node_tree, P.srgb(hexcol), None, texture, scale, hatch)
            mat.diffuse_color = (*light, 1.0)
        done.append(mat.name)

    print("[refresh] обновлено: %d (фактура %.2f, штрих %.2f)" % (len(done), texture, hatch))
    if skipped:
        print("[refresh] нет в палитре, пропущены: " + ", ".join(sorted(skipped)))
    if dry:
        print("[refresh] проба: ничего не записано")
        return
    if bpy.data.filepath:
        bpy.ops.wm.save_mainfile()
        print("[refresh] сцена сохранена: %s" % bpy.data.filepath)
    else:
        print("[refresh] сцена без имени — сохраните сами")


main()
