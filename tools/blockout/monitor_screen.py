"""Включённый монитор: экран светится приглушённым бело-серым.

Экран монитора в сцене — грани того же объекта, что и подставка (`Foot`), с пустым слотом
материала. Скрипт кладёт в этот слот материал `pal_glow_screen`: свечение серо-белого, а не
белое. Так видно, что монитор включён, но не видно белой заливки на экране, и комнату
он не засвечивает: сила свечения ниже, чем у светодиодов (`glow` палитры, 2,5).

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_work_palette_light.blend ^
        --python tools\\blockout\\monitor_screen.py -- [--level 0.28] [--color 0.80,0.84,0.92]

`--level` — сила свечения (0,28: серый, не белый), `--color` — оттенок (слегка холодный).
Файл сохраняется. Повторный запуск обновляет уровень и цвет.
"""

import os
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import cel_shader as C  # noqa: E402

NAME = "pal_glow_screen"


def screen_material(level, color):
    mat = bpy.data.materials.get(NAME) or bpy.data.materials.new(NAME)
    mat.use_nodes = True
    C.build(mat.node_tree, color, kind="glow")
    for n in mat.node_tree.nodes:
        if n.type == "EMISSION":
            n.inputs["Strength"].default_value = level
    return mat


def apply(level=0.28, color=(0.80, 0.84, 0.92)):
    """Экран монитора получает материал свечения. Возвращает число граней экрана.

    Экран — самые крупные грани объекта `Foot`, обращённые лицом к комнате (с небольшим
    наклоном вверх). Они берут пустой слот материала, остальной корпус остаётся чёрным.
    """
    import mathutils
    mat = screen_material(level, color)
    ob = bpy.data.objects.get("Foot")
    if ob is None:
        return 0
    idx = next((i for i, sl in enumerate(ob.material_slots)
                if sl.material is None or sl.material.name == NAME), None)
    if idx is None:
        ob.data.materials.append(mat)
        idx = len(ob.material_slots) - 1
    else:
        ob.material_slots[idx].material = mat
    mw3 = ob.matrix_world.to_3x3()
    sc2 = ob.matrix_world.to_scale()[0] ** 2
    front = mathutils.Vector((0.0, -1.0, 0.0))
    n = 0
    for poly in ob.data.polygons:
        norm = (mw3 @ poly.normal).normalized()
        if poly.area * sc2 > 0.05 and norm.dot(front) > 0.95:
            poly.material_index = idx
            n += 1
    ob.data.update()
    return n


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[::2], argv[1::2]))
    level = float(opts.get("--level", 0.28))
    color = tuple(float(v) for v in opts.get("--color", "0.80,0.84,0.92").split(","))
    print("[screen] слотов: %d" % apply(level, color))
    bpy.ops.wm.save_mainfile()


if __name__ == "__main__":
    main()
