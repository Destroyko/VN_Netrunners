"""Календарь на стене: заменить на простой лист бумаги палитры.

Скачанный календарь с огромной цифрой «2026» бросается в глаза и пересвечивается у лампы
(реальный материал реагирует на свет сильнее ступенчатого). Лист палитры `pal_paper_sand_dark`
матовый, читается как бумага и не тянет на себя взгляд. Когда понадобится постер или
календарь по сюжету, его кладут тем же способом отдельным материалом.

    & "...blender.exe" -b assets\_source\blockout\apartment_work_palette_light.blend ^
        --python tools\blockout\calendar_paper.py

Файл сохраняется. Ключ `--keep`: ничего не менять (проверка). Исходный материал остаётся
в файле без пользователей, пока его не удалят чисткой.
"""

import os
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402

COLOR = "sand_dark"      # светлее выгорает в жёлтое у лампы


def paper_material():
    name = P.mat_name("paper", COLOR)
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        light = C.build(mat.node_tree, P.srgb(P.COLORS[COLOR]), kind="paper")
        C.surface(mat, "paper")
        mat.diffuse_color = (*light, 1.0)
    return mat


def apply():
    paper = paper_material()
    n = 0
    for ob in bpy.data.objects:
        for slot in ob.material_slots:
            nm = slot.material.name.lower() if slot.material else ""
            # прежний лист (sand_light) тоже заменяем: цвет подбирался по рендеру
            if "calendar" in nm or nm.startswith("pal_paper_sand_light"):
                slot.material = paper
                n += 1
    return n


if __name__ == "__main__":
    print("[calendar] слотов заменено: %d" % apply())
    bpy.ops.wm.save_mainfile()
