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
полигонам вести), `--only имя,имя` (только эти объекты).
"""

import os
import sys

import bpy

LIMIT = 5000        # тяжёлым считаем объект сверх этого
TARGET = 2500       # к стольким полигонам стремимся


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[::2], argv[1::2]))
    limit = int(opts.get("--over", LIMIT))
    target = int(opts.get("--target", TARGET))
    only = {s.strip() for s in opts.get("--only", "").split(",") if s.strip()}
    apply = "--apply" in argv

    heavy = []
    for ob in bpy.data.objects:
        if ob.type != "MESH" or not ob.data.polygons:
            continue
        if only and ob.name not in only:
            continue
        n = len(ob.data.polygons)
        if n > limit:
            heavy.append((n, ob))
    heavy.sort(reverse=True, key=lambda p: p[0])

    if not heavy:
        print("[decimate] тяжелее %d полигонов объектов нет" % limit)
        return

    before = sum(len(o.data.polygons) for o in bpy.data.objects
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
        mod = ob.modifiers.new("decimate_auto", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        # применяем сразу: модификатор в сцене пришлось бы помнить и повторять
        ctx = bpy.context.copy()
        ctx["object"] = ob
        with bpy.context.temp_override(**ctx):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        after = len(ob.data.polygons)
        print("   %-28s %7d -> %6d" % (ob.name, n, after))
        saved += n - after

    total = sum(len(o.data.polygons) for o in bpy.data.objects
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
