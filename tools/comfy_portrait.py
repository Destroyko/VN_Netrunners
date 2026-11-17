"""Портрет персонажа для окна диалога: 192x384, пиксель-арт.

Отдельно от comfy_bg.py: там img2img от блокаута, тут генерация по тексту, другой размер
и другая постобработка. Общее — модель и правило целого деления (генерация 384x768, ровно
вдвое больше арта).

    python tools/comfy_portrait.py hero neutral
    python tools/comfy_portrait.py hero neutral --colors 24,32,48     # подбор палитры

ComfyUI должен быть запущен. Нужен только stdlib.
"""

import argparse
import os
import random
import sys
import time
import urllib.error
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy_bg as B  # общий транспорт: очередь, ожидание, скачивание

ART = (192, 384)      # размер в окне диалога (style-guide.md)
GEN = (384, 768)      # ровно вдвое: правило целого деления (ai-pipeline.md 4.1)
OUT_DIR = "assets/_source/portraits"

# Внешность НЕ УТВЕРЖДЕНА (ai-pipeline.md 10.4) — это пробные строки для проверки стиля.
# Без утверждённой строки каждая генерация даёт нового человека, поэтому в игру так нельзя
LOOKS = {
    "hero": "young man, 24 years old, messy dark hair, brown eyes, thin pale build, "
            "plain grey t-shirt",
    "roommate": "young woman, 20 years old, short black bob haircut, grey eyes, pale skin, "
                "thin build, oversized dark hoodie",
    "landlord": "heavy man in his fifties, receding grey hair, stubble, tired face, "
                "old track jacket",
    "mother": "woman in her fifties, grey hair tied back, tired kind face, "
              "simple cardigan",
}

EMOTIONS = {
    "neutral": "calm neutral expression, looking straight ahead",
    "smile": "warm smile, relaxed eyes",
    "surprise": "surprised, eyes wide, eyebrows raised, mouth slightly open",
    "anger": "angry, brows drawn together, mouth set hard",
    "sad": "sad, eyes lowered, mouth turned down",
    "embarrassed": "embarrassed, looking aside, faint blush on the cheeks",
    "thoughtful": "thoughtful, eyes to the side, one eyebrow slightly raised",
}

# Стиль портрета. Ключевое отличие от фона — «крупные плоские массы цвета и тёмный контур»:
# именно этим референс отличается от уменьшенного рендера (ai-pipeline.md 5.10)
STYLE = ("pixel art character portrait, detailed modern pixel art, crisp hard pixels, "
         "large flat areas of solid colour, dark outline around the figure, "
         "strong readable shapes, two or three tones per material, sharp specular highlights, "
         "waist up, facing the viewer, centred, plain flat dark background, "
         "near-future grounded setting, muted palette with a few saturated accents")


def graph(prompt: str, seed: int, steps: int, colors: int, tag: str, outline: str) -> dict:
    """Текст -> Z-Image с пиксель-LoRA -> пиксельная сетка 192x384."""
    return {
        "unet":  {"class_type": "UNETLoader",
                  "inputs": {"unet_name": B.UNET, "weight_dtype": "default"}},
        "lora":  {"class_type": "LoraLoaderModelOnly",
                  "inputs": {"model": ["unet", 0], "lora_name": B.LORA, "strength_model": 1.0}},
        "shift": {"class_type": "ModelSamplingAuraFlow",
                  "inputs": {"model": ["lora", 0], "shift": 3.0, "sampling": "flow"}},
        "clip":  {"class_type": "CLIPLoader",
                  "inputs": {"clip_name": B.CLIP, "type": "lumina2", "device": "default"}},
        "vae":   {"class_type": "VAELoader", "inputs": {"vae_name": B.VAE}},
        "pos":   {"class_type": "CLIPTextEncode",
                  "inputs": {"clip": ["clip", 0], "text": prompt}},
        "neg":   {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["pos", 0]}},
        "lat":   {"class_type": "EmptySD3LatentImage",
                  "inputs": {"width": GEN[0], "height": GEN[1], "batch_size": 1}},
        "samp":  {"class_type": "KSampler",
                  "inputs": {"model": ["shift", 0], "seed": seed, "steps": steps, "cfg": B.CFG,
                             "sampler_name": B.SAMPLER, "scheduler": B.SCHEDULER,
                             "positive": ["pos", 0], "negative": ["neg", 0],
                             "latent_image": ["lat", 0], "denoise": 1.0}},
        "dec":   {"class_type": "VAEDecode",
                  "inputs": {"samples": ["samp", 0], "vae": ["vae", 0]}},
        "raw":   {"class_type": "SaveImage",
                  "inputs": {"images": ["dec", 0], "filename_prefix": "vn/praw_" + tag}},
        "pp":    {"class_type": "SK_PixelPerfect",
                  "inputs": {"image": ["dec", 0], "mode": "fixed_size",
                             "width": ART[0], "height": ART[1], "scale": 1,
                             "method": "dominant", "pre_colors": max(colors * 2, 48)}},
        "pal":   {"class_type": "SK_Palette",
                  "inputs": {"image": ["pp", 0], "source": "auto", "colors": colors,
                             "preset": "PICO-8", "dither": "none", "dither_strength": 0.5,
                             "shared_palette": True, "hex_palette": ""}},
        "clean": {"class_type": "SK_Cleanup",
                  # контур персонажу нужен: без него портрет сливается с фоном окна
                  "inputs": {"image": ["pal", 0], "speck_size": 0, "max_contrast": 0.12,
                             "outline": outline, "outline_color": "#140c1c",
                             "outline_diagonal": False, "darken": 0.3}},
        "art":   {"class_type": "SaveImage",
                  "inputs": {"images": ["clean", 0], "filename_prefix": "vn/part_" + tag}},
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Портрет персонажа через ComfyUI")
    ap.add_argument("who", help="персонаж: %s" % ", ".join(LOOKS))
    ap.add_argument("emotion", nargs="?", default="neutral",
                    help="эмоция или через запятую: %s" % ", ".join(EMOTIONS))
    ap.add_argument("--colors", default="32", help="цветов в палитре, можно через запятую")
    ap.add_argument("--steps", type=int, default=8)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--outline", default="outer_color",
                    choices=["none", "outer_auto", "outer_color", "inner_auto", "inner_color"])
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--keep-raw", action="store_true")
    a = ap.parse_args()

    if a.who not in LOOKS:
        raise SystemExit("нет такого персонажа: %s (есть: %s)" % (a.who, ", ".join(LOOKS)))
    emotions = [e.strip() for e in a.emotion.split(",")]
    for e in emotions:
        if e not in EMOTIONS:
            raise SystemExit("нет такой эмоции: %s (есть: %s)" % (e, ", ".join(EMOTIONS)))
    palettes = [int(c) for c in a.colors.split(",")]

    try:
        B.get("/system_stats")
    except urllib.error.URLError as exc:
        raise SystemExit("ComfyUI не отвечает на %s: %s" % (B.SERVER, exc))

    out_dir = B.repo_path(a.out)
    client = uuid.uuid4().hex
    seed = a.seed or random.randint(1, 2 ** 31)
    print("портретов: %d, сид %d, выход %s" % (len(emotions) * len(palettes), seed, out_dir))

    for emotion in emotions:
        prompt = "%s, %s, %s" % (STYLE, LOOKS[a.who], EMOTIONS[emotion])
        for colors in palettes:
            tag = "%s_%s_c%d" % (a.who, emotion, colors)
            t0 = time.time()
            hist = B.run(graph(prompt, seed, a.steps, colors, tag, a.outline), client)
            names = {"art": "chr_%s_%s_c%d" % (a.who, emotion, colors)}
            if a.keep_raw:
                names["raw"] = "praw_%s_%s_c%d" % (a.who, emotion, colors)
            files = B.save_outputs(hist, out_dir, names)
            print("%s, %.1f с -> %s"
                  % (tag, time.time() - t0, ", ".join(os.path.basename(f) for f in files)))


if __name__ == "__main__":
    main()
