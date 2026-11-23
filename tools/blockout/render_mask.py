"""Маска интерактивных объектов: один кадр вместо десятка спрайтов.

Задача: игрок наводит мышь на монитор или дверь, и предмет должен откликнуться —
обводкой или подсветкой. Резать сцену на слои-спрайты для этого не нужно.

Рендерим с той же камеры второй кадр, где каждый интерактивный предмет залит своим
ровным цветом, а всё остальное чёрное. Движок берёт пиксель маски под курсором
и сразу знает, на что наведено: попадание считается по силуэту предмета, а не по
прямоугольнику. Обводка рисуется шейдером по той же маске, поверх обычного фона.

Что помечается: объекты в коллекции `interactive` либо с именем на `hit_`. Имя после
префикса — это `id` объекта в данных локации (`data/locations/*.json`): `hit_monitor`
даёт в таблице `monitor`, который игра уже знает.

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
    # Blender подмешивает в восьмибитный вывод шум (дизеринг) против полос на градиентах.
    # В обычном кадре он невидим, а в маске цвет — это данные: сдвиг на единицу даёт
    # «чужой» цвет, которого нет в таблице. Замерено: без этого 23 цвета вместо 3
    sc.render.dither_intensity = 0.0

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

    # Фон кадра — чисто чёрный: в сцене у мира свой цвет (у комнаты героя около #121419),
    # и он попал бы в маску как «чужой» цвет, которого нет в таблице
    world = bpy.data.worlds.new("mask_world")
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg is not None:
        bg.inputs[0].default_value = (0.0, 0.0, 0.0, 1.0)
        bg.inputs[1].default_value = 1.0
    sc.world = world
    sc.render.film_transparent = False

    black = flat_mat("mask_background", (0.0, 0.0, 0.0))
    # Сначала чернеем ВСЁ, что может нести материал, а не только меши: кривые (провода),
    # слоты со связью «объект» и узлы Set Material внутри Geometry Nodes — иначе их
    # исходные материалы остаются в кадре и дают цвета, которых нет в таблице
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            ob.data.materials.clear()
            ob.data.materials.append(black)
        else:
            for slot in ob.material_slots:
                slot.material = black
    for ob in bpy.data.objects:
        for slot in ob.material_slots:
            if slot.link == "OBJECT":
                slot.material = black
    for group in bpy.data.node_groups:
        for node in group.nodes:
            if node.type == "SET_MATERIAL":
                try:
                    node.inputs["Material"].default_value = black
                except Exception:
                    pass

    table = {}
    for ob, (r, g, b) in zip(targets, colors_for(len(targets))):
        # цвет задаём в линейном пространстве, чтобы в файл попали именно эти байты;
        # преобразование точное (кусочное sRGB), а не степень 2.2 — иначе байты разойдутся
        lin = tuple(((c / 255.0) / 12.92 if c / 255.0 <= 0.04045
                     else ((c / 255.0 + 0.055) / 1.055) ** 2.4) for c in (r, g, b))
        mat = flat_mat("mask_" + ob.name, lin)
        ob.data.materials.clear()
        ob.data.materials.append(mat)
        # Префикс отрезаем: в таблицу идёт ровно тот id, что стоит в данных локации
        # (data/locations/*.json, поле objects[].id) — третьей сущности не заводим
        key = ob.name[len(MARK_PREFIX):] if ob.name.startswith(MARK_PREFIX) else ob.name
        table["#%02X%02X%02X" % (r, g, b)] = key

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
