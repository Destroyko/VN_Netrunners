"""Упростить тяжёлые объекты сцены.

Скачанные ассеты приносят геометрию щедро: смоделированные складки одеяла, фаски
на каждой доске, болты в ручках. При нашем шейдинге это почти не видно — свет
ступенчатый, тени мягкие, бликов нет, — а рендер и работа в окне от этого тяжелеют.
Для одного кадра неважно, для перехода из двенадцати кадров уже заметно.

Важно: упрощается **геометрия**, а не материал. Матовый материал полигонов не убирает.

    # посмотреть, что будет (ничего не меняется)
    & "...blender.exe" -b сцена.blend --python tools\\blockout\\decimate_heavy.py

    # применить и сохранить
    & "...blender.exe" -b сцена.blend --python tools\\blockout\\decimate_heavy.py -- --apply

Ключи: `--over 5000` (с какого числа считать тяжёлым), `--target 2500` (к скольким
полигонам вести), `--only имя,имя` (только эти объекты), `--mode planar|collapse`.

Про режимы. `collapse` сжимает сетку пропорционально и годится для мягких форм —
ткани, подушек. `planar` схлопывает плоские участки, сохраняя углы: для мебели,
коробок и всего рукотворного он даёт лучший силуэт при меньшем числе граней.
У `planar` вместо доли задаётся угол: грани, отличающиеся меньше чем на него,
сливаются. По умолчанию 5°.

**Модификатор не применяется.** Он остаётся на объекте, исходная сетка цела, и
упрощение в любой момент можно снять или настроить. На рендер это влияет сразу —
модификатор считается при рендере, — а вот `len(mesh.polygons)` будет показывать
старое число: настоящее видно только у вычисленной копии (так и делает scene_audit).
"""

import os
import sys

import bpy

LIMIT = 5000        # тяжёлым считаем объект сверх этого
TARGET = 2500       # к стольким полигонам стремимся


def polys_of(ob, depsgraph):
    """Полигоны с учётом модификаторов — то, что реально пойдёт в рендер."""
    try:
        ev = ob.evaluated_get(depsgraph)
        me = ev.to_mesh()
        n = len(me.polygons)
        ev.to_mesh_clear()
        return n
    except Exception:
        return len(ob.data.polygons)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[::2], argv[1::2]))
    limit = int(opts.get("--over", LIMIT))
    target = int(opts.get("--target", TARGET))
    only = {s.strip() for s in opts.get("--only", "").split(",") if s.strip()}
    apply = "--apply" in argv
    mode = opts.get("--mode", "collapse")
    angle = float(opts.get("--angle", 5.0))

    dg0 = bpy.context.evaluated_depsgraph_get()
    heavy = []
    for ob in bpy.data.objects:
        if ob.type != "MESH" or not ob.data.polygons:
            continue
        if only and ob.name not in only:
            continue
        # Считаем итог с модификаторами: иначе скрипт предлагает упростить то,
        # что уже упрощено модификатором, и врёт в обе стороны
        n = polys_of(ob, dg0)
        if n > limit:
            heavy.append((n, ob))
    heavy.sort(reverse=True, key=lambda p: p[0])

    if not heavy:
        print("[decimate] тяжелее %d полигонов объектов нет" % limit)
        return

    before = sum(polys_of(o, dg0) for o in bpy.data.objects
                 if o.type == "MESH" and o.data.polygons)
    print("[decimate] кандидатов: %d (порог %d, цель %d)" % (len(heavy), limit, target))

    saved = 0
    for n, ob in heavy:
        ratio = min(1.0, target / float(n))
        if not apply:
            print("   %-28s %7d -> %6d  (коэффициент %.3f)"
                  % (ob.name, n, int(n * ratio), ratio))
            saved += n - int(n * ratio)
            continue
        # Старый модификатор того же имени заменяем, чтобы не копились
        old = ob.modifiers.get("decimate_auto")
        if old:
            ob.modifiers.remove(old)
        mod = ob.modifiers.new("decimate_auto", "DECIMATE")
        if mode == "planar":
            mod.decimate_type = "DISSOLVE"
            mod.angle_limit = angle * 3.14159265 / 180.0
        else:
            mod.decimate_type = "COLLAPSE"
            mod.ratio = ratio
        # Модификатор оставляем: исходная сетка цела, упрощение можно снять
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        after = len(me.polygons)
        ev.to_mesh_clear()
        print("   %-28s %7d -> %6d" % (ob.name, n, after))
        saved += n - after

    dg = bpy.context.evaluated_depsgraph_get()
    total = sum(polys_of(o, dg) for o in bpy.data.objects
                if o.type == "MESH" and o.data.polygons)
    if apply:
        print("[decimate] было %d, стало %d (минус %d)" % (before, total, saved))
        if bpy.data.filepath:
            bpy.ops.wm.save_mainfile()
            print("[decimate] сцена сохранена: %s" % bpy.data.filepath)
    else:
        print("[decimate] это проба; с ключом --apply стало бы %d вместо %d"
              % (before - saved, before))


main()
