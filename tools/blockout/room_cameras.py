"""Камеры комнаты героя: оставить две, `frame_main` (вид на комнату) и `frame_pc` (вид на ПК).

Старые камеры блокаута (`room_bed`, `room_closet`, `room_desk`, `room_door`, `room_pc`,
`room_pc_v2`) удаляются. Камеры других комнат не трогаются. Две новые берут положение
и фокусное из таблицы `room_frames.CAMERAS`; когда разработчик подберёт финальный ракурс
руками, он просто двигает эти камеры, а скрипт кадров подхватывает их по имени.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_lit.blend ^
        --python tools\\blockout\\room_cameras.py

Файл сохраняется (Blender оставляет прежнюю версию как `.blend1`).
"""

import os
import sys

import bpy
import mathutils

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import room_frames as R  # noqa: E402

OLD = ("room_bed", "room_closet", "room_desk", "room_door", "room_pc", "room_pc_v2")


def ensure(name, spec, coll):
    ob = bpy.data.objects.get(name)
    if ob is not None:
        return ob
    cd = bpy.data.cameras.new(name)
    cd.lens = spec["lens"]
    cd.clip_start = 0.05
    ob = bpy.data.objects.new(name, cd)
    coll.objects.link(ob)
    ob.location = spec["loc"]
    tgt = mathutils.Vector(spec["target"])
    ob.rotation_euler = (tgt - ob.location).to_track_quat("-Z", "Y").to_euler()
    return ob


def main():
    coll = bpy.data.collections.get("cameras") or bpy.context.scene.collection
    main_cam = ensure("frame_main", R.CAMERAS["main"], coll)
    ensure("frame_pc", R.CAMERAS["pc"], coll)
    removed = []
    for name in OLD:
        ob = bpy.data.objects.get(name)
        if ob is None:
            continue
        data = ob.data
        bpy.data.objects.remove(ob)
        if data is not None and data.users == 0:
            bpy.data.cameras.remove(data)
        removed.append(name)
    bpy.context.scene.camera = main_cam
    print("[cameras] удалено: %s; осталось в комнате: frame_main, frame_pc" % ", ".join(removed))
    bpy.ops.wm.save_mainfile()


main()
