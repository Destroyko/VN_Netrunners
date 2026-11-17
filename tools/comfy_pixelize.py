"""Готовый кадр -> пиксель-арт. Перебор настроек без повторной генерации.

Отдельно от comfy_bg.py нарочно: генерация кадра занимает минуту, а подбор пиксельной
сетки и палитры — это десятки вариантов. Гонять ради них модель заново незачем,
картинка уже есть. Сюда же сводится вопрос «пиксель или флэт»: один и тот же кадр
прогоняется в оба вида и сравнивается глазами.

    python tools/comfy_pixelize.py кадр.png --art 640x360 --colors 24,32,48
    python tools/comfy_pixelize.py кадр.png --art 320x180,640x360 --colors 32 --outline outer_auto

ComfyUI должен быть запущен. Нужен только stdlib.
"""

import argparse
import os
import sys
import time
import urllib.error
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_bg as B  # общий транспорт: загрузка, очередь, скачивание

OUT_DIR = "assets/_source/blockout/pixel"


def graph(image_ref: str, art, colors: int, tag: str, outline: str, dither: str,
          darken: float, speck: int, method: str) -> dict:
    """Только постобработка: ни модели, ни VAE — кадр уже нарисован."""
    return {
        "load":  {"class_type": "LoadImage", "inputs": {"image": image_ref}},
        "pp":    {"class_type": "SK_PixelPerfect",
                  "inputs": {"image": ["load", 0], "mode": "fixed_size",
                             "width": art[0], "height": art[1], "scale": 1,
                             "method": method, "pre_colors": max(80, colors * 2)}},
        "pal":   {"class_type": "SK_Palette",
                  "inputs": {"image": ["pp", 0], "source": "auto", "colors": colors,
                             "preset": "PICO-8", "dither": dither,
                             "dither_strength": 0.5, "shared_palette": True,
                             "hex_palette": ""}},
        "clean": {"class_type": "SK_Cleanup",
                  "inputs": {"image": ["pal", 0], "speck_size": speck,
                             "max_contrast": 0.12, "outline": outline,
                             "outline_color": "#140c1c", "outline_diagonal": False,
                             "darken": darken}},
        "art":   {"class_type": "SaveImage",
                  "inputs": {"images": ["clean", 0], "filename_prefix": "vn/px_" + tag}},
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Пикселизация готового кадра")
    ap.add_argument("image", help="путь к готовому кадру (png)")
    ap.add_argument("--art", default="640x360", help="размеры через запятую: 640x360,320x180")
    ap.add_argument("--colors", default="32", help="число цветов через запятую")
    ap.add_argument("--outline", default="none",
                    choices=["none", "outer_auto", "outer_color", "inner_auto", "inner_color"])
    ap.add_argument("--dither", default="none",
                    choices=["none", "bayer-2", "bayer-4", "bayer-8", "floyd-steinberg"])
    ap.add_argument("--darken", type=float, default=0.2)
    ap.add_argument("--speck", type=int, default=0,
                    help="чистка мелких кластеров; с дизерингом вешает прогон (4.3)")
    ap.add_argument("--method", default="dominant",
                    choices=["dominant", "median", "mean", "nearest"],
                    help="как сводится блок пикселей: dominant держит формы, "
                         "nearest даёт остроту, но выбрасывает детали")
    ap.add_argument("--out", default=OUT_DIR)
    a = ap.parse_args()

    src = B.repo_path(a.image)
    if not os.path.exists(src):
        raise SystemExit("нет файла: %s" % src)
    sizes = [tuple(int(v) for v in s.lower().split("x")) for s in a.art.split(",")]
    palettes = [int(c) for c in a.colors.split(",")]

    try:
        B.get("/system_stats")
    except urllib.error.URLError as e:
        raise SystemExit("ComfyUI не отвечает на %s: %s" % (B.SERVER, e))

    ref = B.upload(src)
    out_dir = B.repo_path(a.out)
    client = uuid.uuid4().hex
    stem = os.path.splitext(os.path.basename(src))[0]
    print("вариантов: %d, выход %s" % (len(sizes) * len(palettes), out_dir))

    for art in sizes:
        for colors in palettes:
            tag = "%s_%d_c%d" % (stem, art[0], colors)
            if a.method != "dominant":
                tag += "_" + a.method
            if a.outline != "none":
                tag += "_ol"
            if a.dither != "none":
                tag += "_" + a.dither
            t0 = time.time()
            hist = B.run(graph(ref, art, colors, tag, a.outline, a.dither,
                               a.darken, a.speck, a.method), client)
            files = B.save_outputs(hist, out_dir, {"art": tag})
            print("%dx%d, %d цветов, %.1f с -> %s"
                  % (art[0], art[1], colors, time.time() - t0,
                     ", ".join(os.path.basename(f) for f in files)))


if __name__ == "__main__":
    main()
