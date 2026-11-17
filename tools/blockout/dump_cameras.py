"""Камеры из сцены Blender обратно в код.

Зачем: планировка и камеры живут в скриптах (`apartment.py`, `city.py`), а крутить
ракурс удобнее руками в окне. Без этого моста правки в редакторе теряются при следующей
пересборке сцены. Скрипт читает камеры открытой сцены и печатает готовые строки
`B.camera(...)` — остаётся вставить их в `cameras()`.

Два способа.

1. Прямо в Blender: вкладка Scripting -> Open -> этот файл -> Run Script.
   Строки окажутся в файле `cameras_dump.txt` рядом со сценой и в системной консоли
   (Window -> Toggle System Console).

2. Из командной строки по сохранённой сцене:

   & "C:\\Program Files\\Blender Foundation\\Blender 5.3\\blender.exe" -b ^
     assets\\_source\\blockout\\apartment.blend --python tools\\blockout\\dump_cameras.py

Высота камеры (`EYE`) и сдвиг объектива печатаются как есть: если двигали камеру
по Z, это видно в третьем числе позиции.
"""

import math
import os

import bpy


def target_of(ob, dist=3.0):
    """Куда смотрит камера: точка на луче взгляда.

    В коде камера задаётся позицией и целью, а в Blender — позицией и поворотом.
    Переводим одно в другое, чтобы строка получилась в том же виде, что в скрипте.
    """
    m = ob.matrix_world
    # камера в Blender смотрит вдоль своей -Z
    fwd = (m.to_3x3() @ __import__("mathutils").Vector((0.0, 0.0, -1.0))).normalized()
    loc = m.to_translation()
    return loc + fwd * dist


def main():
    lines = []
    cams = [o for o in bpy.data.objects if o.type == "CAMERA"]
    if not cams:
        print("[dump] в сцене нет камер")
        return
    for ob in sorted(cams, key=lambda o: o.name):
        loc = ob.matrix_world.to_translation()
        tgt = target_of(ob)
        d = ob.data
        lens = d.lens
        shift = d.shift_y
        ortho = ("ortho=%.3f, " % d.ortho_scale) if d.type == "ORTHO" else ""
        lines.append(
            '    c["%s"] = B.camera("%s", (%.2f, %.2f, %.2f), (%.2f, %.2f, %.2f), %s%.0f, '
            "shift=%.3f)" % (ob.name, ob.name, loc.x, loc.y, loc.z,
                             tgt.x, tgt.y, tgt.z, ortho, lens, shift))
    text = "\n".join(lines)
    print("\n[dump] вставить в cameras():\n")
    print(text)
    # Рядом со сценой, а в несохранённой — в папку блокаутов
    base = bpy.data.filepath
    out = (os.path.join(os.path.dirname(base), "cameras_dump.txt") if base
           else os.path.join(os.path.dirname(os.path.abspath(__file__)), "cameras_dump.txt"))
    with open(out, "w", encoding="utf-8") as f:
        f.write(text + "\n")
    print("\n[dump] сохранено: %s" % out)


main()
