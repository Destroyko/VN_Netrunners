"""Матовые обои: убрать блеск у материалов с `wallpaper` в имени.

Чужие обои (скачанный ассет) идут с картой шероховатости и бликом: в свете торшера на
стене появляются отблески, и она выглядит глянцевой. Скрипт отвязывает карты блеска и
ставит шероховатость 1, блик 0: узор и цвет остаются, блеск уходит.

    & "...blender.exe" -b assets\_source\blockout\apartment_work_palette_light.blend ^
        --python tools\blockout\matte_wallpaper.py

Файл сохраняется. Скрипт кадров (`room_frames.py`) вызывает то же самое на время рендера,
так что рендер получается матовым, даже если файл ещё не правили.
"""

import bpy

KEYS = ("wallpaper",)


def apply():
    """Возвращает число изменённых материалов."""
    done = 0
    for mat in bpy.data.materials:
        if not any(k in mat.name.lower() for k in KEYS) or not mat.use_nodes:
            continue
        changed = False
        for node in mat.node_tree.nodes:
            if node.type != "BSDF_PRINCIPLED":
                continue
            for name, value in (("Roughness", 1.0), ("Specular IOR Level", 0.0),
                                ("Coat Weight", 0.0)):
                sock = node.inputs.get(name)
                if sock is None:
                    continue
                for link in list(sock.links):
                    mat.node_tree.links.remove(link)
                sock.default_value = value
                changed = True
        done += 1 if changed else 0
    return done


if __name__ == "__main__":
    print("[wallpaper] материалов: %d" % apply())
    bpy.ops.wm.save_mainfile()
