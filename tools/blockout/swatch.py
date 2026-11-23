"""Образец материала: шарик с теми же ступенями света и бликом, что у шейдера.

Нужен в двух местах: превью в браузере ассетов Blender (чтобы выбирать цвет глазами,
а не по названию) и листы палитры. Поэтому только numpy, без Blender: модуль работает
и внутри Blender, и в обычном Python.

Образец схематичный. Он честно показывает главное — число ступеней, холодную тень
и блик металла или пластика, — но не повторяет фактуру и не заменяет рендер. Точный
вид материала смотреть в Rendered или на листе material_sheet.py.
"""

import numpy as np

import cel_shader as C


def _to_srgb(lin):
    """Линейный цвет -> sRGB: то, что человек видит на экране."""
    lin = np.clip(lin, 0.0, 1.0)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1.0 / 2.4) - 0.055)


def sphere(rgb_linear, kind, size=96):
    """Шарик, покрашенный материалом. Возвращает float32 (size, size, 4): sRGB + альфа.

    Освещение считается так же, как у шейдера: свет делится на ступени порогами
    Color Ramp (0 и i/N + 0.12), поверх ступеней добавляется ступенчатый блик.
    """
    prof = C.MATERIALS.get(kind, C.MATERIALS[C.DEFAULT_KIND])
    tones = C.shades(rgb_linear, prof["tones"], prof.get("cool", 1.0))
    tn = np.array(tones, dtype=np.float32)

    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2.0
    radius = size * 0.44
    x = (xs - c) / radius
    y = -(ys - c) / radius                      # вверх — положительное
    rr = x * x + y * y
    z = np.sqrt(np.clip(1.0 - rr, 0.0, 1.0))
    n = np.stack([x, y, z], axis=-1)

    light = np.array([-0.45, 0.55, 0.70], dtype=np.float32)
    light /= np.linalg.norm(light)
    ndl = np.clip(n @ light, 0.0, 1.0)
    value = 0.15 + 0.85 * ndl                   # в шейдере свет тоже не доходит до нуля

    # ступени: пороги те же, что в cel_shader.build
    idx = np.zeros(value.shape, dtype=np.int32)
    for i in range(1, len(tones)):
        idx += (value >= (i / len(tones) + 0.12)).astype(np.int32)
    col = tn[idx]

    spec = prof.get("spec", 0.0)
    if spec > 0.0:
        gloss = prof.get("gloss", 0.25)
        half = light + np.array([0.0, 0.0, 1.0], dtype=np.float32)
        half /= np.linalg.norm(half)
        ndh = np.clip(n @ half, 0.0, 1.0)
        # у металла блик маленький и резкий, у дерева — широкий и едва заметный
        cut = 1.0 - (0.02 + 0.5 * gloss * gloss)
        col = col + (ndh >= cut)[..., None].astype(np.float32) * spec

    rgb = _to_srgb(col).astype(np.float32)
    # мягкий край, чтобы шарик не рассыпался в пиксели на малых размерах
    alpha = np.clip((1.0 - np.sqrt(rr)) * radius, 0.0, 1.0).astype(np.float32)
    out = np.zeros((size, size, 4), dtype=np.float32)
    out[..., :3] = rgb
    out[..., 3] = alpha
    return out


def to_pil(arr):
    """float (h, w, 4) -> картинка Pillow."""
    from PIL import Image
    return Image.fromarray((np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGBA")
