"""Записать в сцену настройки качества EEVEE (тени, число сэмплов), чтобы окно Blender не зернило.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_lit.blend ^
        --python tools\\blockout\\room_quality.py

Значения те же, что ставит room_frames.setup для кадров; здесь они сохраняются в самом файле,
и окно Blender в режиме Rendered берёт их без запуска скрипта света. Файл сохраняется.
"""

import bpy

sc = bpy.context.scene
e = sc.eevee
e.taa_samples = 128             # окно: по умолчанию 16, зерно на чёрном пластике
e.taa_render_samples = 256
e.shadow_ray_count = 8
e.shadow_step_count = 24
e.shadow_resolution_scale = 2.0
e.light_threshold = 0.00001
bpy.ops.wm.save_mainfile()
print("[quality] окно 128, рендер 256, лучи теней 8")
