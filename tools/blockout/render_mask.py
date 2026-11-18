"""Маска интерактивных объектов: один кадр вместо десятка спрайтов.

Задача: игрок наводит мышь на монитор или дверь, и предмет должен откликнуться —
обводкой или подсветкой. Резать сцену на слои-спрайты для этого не нужно.

Рендерим с той же камеры второй кадр, где каждый интерактивный предмет залит своим
ровным цветом, а всё остальное чёрное. Движок берёт пиксель маски под курсором
и сразу знает, на что наведено: попадание считается по силуэту предмета, а не по
прямоугольнику. Обводка рисуется шейдером по той же маске, поверх обычного фона.

Что помечается: объекты в коллекции `interactive` либо с именем на `hit_`.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_detail.blend ^
        --python tools\\blockout\\render_mask.py -- --render room_desk

Рядом с PNG кладётся JSON: цвет -> имя объекта. Сцена не сохраняется.
"""

import json
import os
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bl_common as B  # noqa: E402

MARK_COLLECTION = "interactive"
MARK_PREFIX = "hit_"

# Цвета берутся с большим шагом по каналам: после сжатия PNG и масштабирования
# в движке соседние значения не должны слипаться
STEP = 36


def flat_mat(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (*rgb, 1.0)
    em.inputs[1].default_value = 1.0
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return mat


def pick_targets():
    """Что считается интерактивным. Имя объекта — ключ, по которому его узнает игра."""
    col = bpy.data.collections.get(MARK_COLLECTION)
    out = []
    if col:
        out.extend(col.all_objects)
    for ob in bpy.data.objects:
        if ob.name.startswith(MARK_PREFIX) and ob not in out:
            out.append(ob)
    return [o for o in out if o.type == "MESH"]


def colors_for(n):
    """n различимых цветов. Чёрный занят фоном, поэтому начинаем с шага."""
    out = []
    i = 1
    while len(out) < n:
        r = (i * STEP) % 256
        g = (i * STEP * 3) % 256
        b = (i * STEP * 7) % 256
        if (r, g, b) != (0, 0, 0):
            out.append((r, g, b))
        i += 1
    return out


def main():
    def extra(p):
        p.add_argument("--names", default="",
                       help="пометить объекты по именам через запятую — на пробу, "
                            "пока в сцене нет коллекции interactive")

    a = B.args(extra)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    # Ни сглаживания, ни фильтра: цвет должен дойти до пикселя ровно таким, каким задан
    sc.eevee.taa_render_samples = 1
    sc.render.filter_size = 0.0

    targets = pick_targets()
    if a.names:
        for n in (x.strip() for x in a.names.split(",")):
            ob = bpy.data.objects.get(n)
            if ob is None:
                raise SystemExit("нет объекта %s" % n)
            if ob not in targets:
                targets.append(ob)
    if not targets:
        raise SystemExit("нет интерактивных объектов: коллекция '%s' или имена на '%s'"
                         % (MARK_COLLECTION, MARK_PREFIX))

    black = flat_mat("mask_background", (0.0, 0.0, 0.0))
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        ob.data.materials.clear()
        ob.data.materials.append(black)

    table = {}
    for ob, (r, g, b) in zip(targets, colors_for(len(targets))):
        # цвет задаём в линейном пространстве, чтобы в файл попали именно эти байты
        lin = tuple((c / 255.0) ** 2.2 for c in (r, g, b))
        mat = flat_mat("mask_" + ob.name, lin)
        ob.data.materials.clear()
        ob.data.materials.append(mat)
        table["#%02X%02X%02X" % (r, g, b)] = ob.name

    out_dir = B.resolve(a.out) if a.out else B.resolve("assets/_source/blockout/mask")
    files = B.render({o.name: o for o in bpy.data.objects if o.type == "CAMERA"},
                     out_dir, "_mask", a.render)
    for f in files:
        with open(os.path.splitext(f)[0] + ".json", "w", encoding="utf-8") as fh:
            json.dump(table, fh, ensure_ascii=False, indent=1)
    print("[mask] объектов: %d, кадров: %d" % (len(targets), len(files)))
    for col, name in table.items():
        print("   %s  %s" % (col, name))


main()
