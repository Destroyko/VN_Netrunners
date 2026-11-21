"""Обновить материалы палитры прямо в сцене.

`Append` делает копию: материал, подключённый к сцене, живёт своей жизнью и после
пересборки библиотеки не меняется. Этот скрипт проходит по материалам сцены с именем
`pal_*`, находит их цвет в палитре и пересобирает шейдер заново — цвет, ступени,
фактуру. Сцена сохраняется.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_work.blend ^
        --python tools\\blockout\\refresh_palette.py

Можно задать фактуру: `-- --texture 0.12 --hatch 0.5 --tex-scale 8`.

По умолчанию трогаются только материалы палитры (`pal_*`). Но в сцене, собранной
скриптами детализации, материалы называются иначе — `wood_flat`, `metal_flat`.
Для них есть `--all`: он берёт цвет, который у материала уже есть, и надевает
тот же cel-шейдер. Так стиль ложится на всю сцену, откуда бы ни пришли материалы.
"""

import os
import re
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402


def own_color(mat):
    """Цвет, который у материала уже есть: Emission из скриптов детализации,
    Principled из чужих ассетов, иначе серый."""
    if mat.use_nodes and mat.node_tree:
        for n in mat.node_tree.nodes:
            if n.type == "EMISSION":
                return tuple(n.inputs[0].default_value)[:3]
        for n in mat.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                return tuple(n.inputs["Base Color"].default_value)[:3]
    return tuple(mat.diffuse_color)[:3]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[::2], argv[1::2]))
    texture = float(opts.get("--texture", C.DEFAULTS["texture"]))
    scale = float(opts.get("--tex-scale", C.DEFAULTS["scale"]))
    hatch = float(opts.get("--hatch", C.DEFAULTS["hatch"]))
    dry = "--dry" in argv
    every = "--all" in argv

    # Имя материала: pal_<ключ палитры>_<тип>, где в ключе "/" заменён на "_".
    # Разбираем обратно, чтобы знать и цвет, и каким профилем его собирать
    table = {}
    for k, v in P.all_colors().items():
        base = "pal_" + k.replace("/", "_")
        for kind in P.kinds_for(k):
            table["%s_%s" % (base, kind)] = (v, kind)
        # имена без типа остались от прежней библиотеки — понимаем и их
        table.setdefault(base, (v, None))

    done, skipped = [], []
    for mat in bpy.data.materials:
        if not every and not mat.name.startswith("pal_"):
            continue
        if every and not mat.name.startswith("pal_"):
            # Материал не из палитры: цвет берём тот, что у него уже есть
            if not dry:
                rgb = own_color(mat)
                mat.use_nodes = True
                light = C.build(mat.node_tree, rgb, None, texture, scale, hatch)
                mat.diffuse_color = (*light, 1.0)
            done.append(mat.name)
            continue
        # у копий Blender добавляет .001 — отрезаем только этот суффикс:
        # в именах комнат точка своя (pal_room.hero_wall), её трогать нельзя
        base = re.sub(r"\.\d{3}$", "", mat.name)
        found = table.get(base)
        if found is None:
            skipped.append(mat.name)
            continue
        hexcol, kind = found
        if not dry:
            mat.use_nodes = True
            light = C.build(mat.node_tree, P.srgb(hexcol), None,
                            texture, scale, hatch, kind)
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
