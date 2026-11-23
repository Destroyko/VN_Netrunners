"""Обновить материалы палитры прямо в сцене.

`Append` и перетаскивание из браузера ассетов делают **копию**: материал, попавший
в сцену, живёт своей жизнью и после пересборки библиотеки не меняется. Этот скрипт
проходит по материалам сцены с именем `pal_*`, находит их цвет в палитре и пересобирает
шейдер заново — цвет, ступени, блик, фактуру. Сцена сохраняется.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_work.blend ^
        --python tools\\blockout\\refresh_palette.py

**Прежние имена переименовываются сами.** До 23.11.2026 материалы звались
`pal_neutral_black_tech_plastic`, теперь — `pal_plastic_black`. Скрипт узнаёт старое имя
по таблице palette.LEGACY, переименовывает и пересобирает; цвет при этом остаётся тем же
побайтно, объекты не теряют материал. Что именно переименовано, печатается списком.

Ключи: `--dry` — только показать, ничего не менять; `--texture 0.12 --hatch 0.5
--tex-scale 8` — переопределить фактуру у всех сразу. Без них фактуру задаёт профиль
материала (у металла почти нет, у ткани сильная).

По умолчанию трогаются только материалы палитры (`pal_*`). Но в сцене, собранной
скриптами детализации, материалы называются иначе — `wood_flat`, `metal_flat`.
Для них есть `--all`: он берёт цвет, который у материала уже есть, и надевает
тот же cel-шейдер. Так стиль ложится на всю сцену, откуда бы ни пришли материалы.
"""

import os
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
    # None — значит «как в профиле материала». Явный ключ перекрывает профиль у всех
    texture = float(opts["--texture"]) if "--texture" in opts else None
    scale = float(opts["--tex-scale"]) if "--tex-scale" in opts else None
    hatch = float(opts["--hatch"]) if "--hatch" in opts else None
    dry = "--dry" in argv
    every = "--all" in argv

    done, renamed, skipped = [], [], []
    for mat in list(bpy.data.materials):
        is_pal = mat.name.startswith("pal_")
        if not is_pal and not every:
            continue
        if not is_pal:
            # Материал не из палитры: цвет берём тот, что у него уже есть
            if not dry:
                rgb = own_color(mat)
                mat.use_nodes = True
                light = C.build(mat.node_tree, rgb, None, texture, scale, hatch)
                mat.diffuse_color = (*light, 1.0)
            done.append(mat.name)
            continue

        parsed = P.parse_name(mat.name)
        if parsed is None:
            skipped.append(mat.name)
            continue
        kind, color, legacy = parsed
        if not dry:
            mat.use_nodes = True
            light = C.build(mat.node_tree, P.srgb(P.COLORS[color]), None,
                            texture, scale, hatch, kind)
            mat.diffuse_color = (*light, 1.0)
        if legacy:
            new = P.mat_name(kind, color)
            renamed.append((mat.name, new))
            if not dry:
                # Если новое имя занято (дубль .001), Blender сам добавит суффикс
                mat.name = new
        done.append(mat.name)

    print("[refresh] обновлено: %d" % len(done))
    if renamed:
        print("[refresh] переименовано по-новому (цвет прежний):")
        for old, new in renamed:
            print("   %-38s -> %s" % (old, new))
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
