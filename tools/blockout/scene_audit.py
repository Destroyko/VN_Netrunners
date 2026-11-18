"""Что в сцене: прокси, ассеты и забытые дубли.

Когда прокси заменяют настоящей мебелью, старый объект легко оставить на месте:
в окне он прячется за новым, а в кадре вылезает — две кровати, два стола. Скрипт
ищет такие пары по пересечению габаритов и заодно показывает, что из прокси ещё стоит.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_work.blend ^
        --python tools\\blockout\\scene_audit.py

Ничего не меняет и не сохраняет: только отчёт.
"""

import os
import sys

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

PROXY_PREFIX = "det_"
OVERLAP = 0.45      # доля пересечения объёмов, после которой считаем дублем

# Стены, полы и потолки пересекаются с чем угодно — в поиске дублей они только мешают
ARCH = {"architecture", "rooms", "floors", "ceilings", "walls_exterior",
        "walls_interior", "windows", "cameras", "blockout_old"}


def world_box(ob):
    """Габариты объекта в мировых координатах."""
    corners = [ob.matrix_world @ __import__("mathutils").Vector(c) for c in ob.bound_box]
    xs = [c.x for c in corners]
    ys = [c.y for c in corners]
    zs = [c.z for c in corners]
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def volume(lo, hi):
    return max(0.0, hi[0] - lo[0]) * max(0.0, hi[1] - lo[1]) * max(0.0, hi[2] - lo[2])


def overlap_share(a, b):
    """Какая доля меньшего объёма попадает в пересечение."""
    lo = tuple(max(a[0][i], b[0][i]) for i in range(3))
    hi = tuple(min(a[1][i], b[1][i]) for i in range(3))
    inter = volume(lo, hi)
    small = min(volume(*a), volume(*b))
    return 0.0 if small <= 0 else inter / small


def is_arch(ob):
    """Архитектура: сама комната, а не мебель в ней."""
    return any(c.name in ARCH for c in ob.users_collection)


def final_polys(ob, depsgraph):
    """Полигоны с учётом модификаторов.

    Считать len(ob.data.polygons) нельзя: модификатор «Упростить» не меняет
    исходную сетку, и объект с 43 600 полигонов в базе может давать в рендер
    6 500. Правильное число — у вычисленной копии объекта.
    """
    try:
        ev = ob.evaluated_get(depsgraph)
        me = ev.to_mesh()
        n = len(me.polygons)
        ev.to_mesh_clear()
        return n
    except Exception:
        return len(ob.data.polygons)


def renders(ob):
    """Попадёт ли объект в кадр: объект и все его коллекции не скрыты при рендере."""
    if ob.hide_render:
        return False
    return not any(c.hide_render for c in ob.users_collection)


def main():
    depsgraph = bpy.context.evaluated_depsgraph_get()
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and renders(o)]
    polys = {o.name: final_polys(o, depsgraph) for o in meshes}
    boxes = {o.name: world_box(o) for o in meshes}

    proxies = sorted(o.name for o in meshes if o.name.startswith(PROXY_PREFIX))
    print("[audit] в кадр попадает объектов: %d, из них прокси: %d"
          % (len(meshes), len(proxies)))

    # Дубли: прокси, внутри которого стоит что-то другое
    pairs = []
    for name in proxies:
        for other in meshes:
            if other.name == name or other.name.startswith(PROXY_PREFIX):
                continue
            if is_arch(other):
                continue
            share = overlap_share(boxes[name], boxes[other.name])
            if share >= OVERLAP:
                pairs.append((name, other.name, share))
    if pairs:
        print("\n[audit] похоже на забытые прокси — внутри них стоит новая мебель:")
        best = {}
        for proxy, other, share in pairs:
            # у ассета из интернета десятки мелких частей — показываем, сколько их
            cur = best.setdefault(proxy, [0.0, other, 0])
            cur[2] += 1
            if share > cur[0]:
                cur[0], cur[1] = share, other
        for proxy, (share, other, count) in sorted(best.items(), key=lambda kv: -kv[1][0]):
            tail = (", частей рядом: %d" % count) if count > 1 else ""
            print("   %-22s <- %-28s %.0f%%%s" % (proxy, other, share * 100, tail))
        print("   (удалить прокси или убрать его в blockout_old)")
    else:
        print("\n[audit] забытых прокси не видно")

    if proxies:
        print("\n[audit] прокси, которые ещё в кадре:")
        for i in range(0, len(proxies), 4):
            print("   " + ", ".join(proxies[i:i + 4]))

    # Тяжёлые объекты: ассеты из интернета иногда несут десятки тысяч полигонов
    heavy = sorted(((polys[o.name], o.name) for o in meshes
                    if polys[o.name] > 5000), reverse=True)
    if heavy:
        print("\n[audit] тяжёлые объекты (фон их не оправдывает):")
        for n, name in heavy[:10]:
            ob = bpy.data.objects[name]
            raw = len(ob.data.polygons)
            tail = "  (в сетке %d, упрощает модификатор)" % raw if raw != n else ""
            print("   %-28s %6d полигонов%s" % (name, n, tail))
    total = sum(polys.values())
    print("\n[audit] полигонов в кадре всего: %d" % total)


main()
