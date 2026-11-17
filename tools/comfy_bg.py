"""Фон из кадра блокаута: блокаут -> ComfyUI (img2img) -> пиксель-арт 640x360.

Зачем скрипт, а не редактор ComfyUI: фонов квартиры двенадцать (шесть кадров x день/ночь),
и каждый надо будет пересобрать, когда поменяется планировка или палитра. Руками это
двенадцать раз перетащить картинку и не перепутать поля. Источник истины по настройкам —
этот файл, как и по планировке — tools/blockout/apartment.py.

    python tools/comfy_bg.py room_desk --phase day
    python tools/comfy_bg.py room_desk --denoise 0.4,0.55,0.7,0.85     # подбор силы
    python tools/comfy_bg.py all --phase day,night --out assets/backgrounds

ComfyUI должен быть запущен (http://127.0.0.1:8188). Нужен только stdlib.
"""

import argparse
import json
import mimetypes
import os
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

SERVER = "http://127.0.0.1:8188"

# 1280x720 на входе и выходе генерации: делится нацело на 640x360 (правило целого деления,
# ai-pipeline.md 4.1) и на 8 для латента
GEN = (1280, 720)
ART = (640, 360)

BLOCKOUT_DIR = "assets/_source/blockout/renders"
OUT_DIR = "assets/_source/blockout/gen"

# Z-Image Turbo + пиксель-LoRA (ai-pipeline.md 4.2)
UNET = "z_image_turbo_bf16.safetensors"
LORA = "spritekiln_zimage_pixel_art.safetensors"
CLIP = "qwen_3_4b.safetensors"
VAE = "ae.safetensors"
STEPS = 8          # столько шагов у дистиллированной модели при denoise 1.0
CFG = 1.0
SAMPLER = "res_multistep"
SCHEDULER = "simple"
PRE_COLORS = 80    # до палитры: меньше — картинка грубеет ещё до сведения цветов

# Общая часть промпта — из style-guide.md («Шаблон промпта»). Негатива нет: при CFG 1
# он не работает, поэтому всё формулируется утвердительно
STYLE = ("pixel art, detailed modern pixel art, slightly chunky pixels, "
         "near-future grounded realistic setting, muted colors with subtle neon accents, "
         "limited palette, visual novel background, no people, empty room, "
         "realistic proportions and real-world scale, furniture sized for an adult, "
         "lived-in and cluttered, worn surfaces, large flat areas of solid colour, "
         "dark outline on objects, two or three tones per material, sharp highlights")

# Свет по фазе суток. Он же решает, какой кадр блокаута брать (--shade lit --phase ...),
# но вход берём всегда плоский: lit-рендер навязывает генератору свою светотень
PHASES = {
    "day": ("daytime, overcast daylight through the window, cool neutral light, "
            "soft shadows, the window is the brightest block in the frame"),
    "night": ("night, lights off, the room lit only by the blue glow of a computer monitor "
              "and a warm desk lamp, deep shadows, dark window with distant city lights"),
}

# Содержание кадров. Одна комната — один промпт: «и ещё на заднем плане» модель смешает
SCENES = {
    "room_desk": "a small rented bedroom of a young programmer: a desk against the wall "
                 "with a modern black tower PC and a widescreen flat monitor, keyboard, mug "
                 "and scattered "
                 "papers, a swivel chair, a window above the desk, cables on the floor, "
                 "deep muted blue walls, dark grey floor, pale bedding",
    "room_pc": "the desk of a young programmer seen close up: a modern black tower PC with "
               "a side panel, a widescreen flat monitor with a glowing screen, a mechanical "
               "keyboard, a mug, papers and sticky notes, tangled cables, a window frame "
               "above, deep muted blue wall, dark grey floor",
    "room_bed": "a small rented bedroom seen from the desk side: an unmade single bed with "
                "pale bedding, a bedside table with a phone, a wardrobe, a window with thin "
                "curtains, deep muted blue walls, dark grey floor",
    "room_door": "a small rented bedroom seen from the window: the room door standing ajar, "
                 "a tall wardrobe beside it, a bookshelf with clutter, a poster on the wall, "
                 "deep muted blue walls, dark grey floor",
    "kitchen": "a cramped kitchen of an old rented flat: a counter with a sink and a kettle, "
               "a small gas stove, wall cabinets, a tiny table with two stools, "
               "a fridge, a window above the sink, tiled splashback, linoleum floor",
    "corridor": "a narrow corridor of an old rented flat seen along its length: "
                "closed doors of the rooms on one side, a coat rack, a light bulb, "
                "patterned wallpaper, linoleum floor",
    "hall": "the entrance hall of an old rented flat seen from the front door: "
            "a shoe rack and shoes on the floor, coats on hooks, a mirror, "
            "the corridor leading deeper into the flat, linoleum floor",
}


def repo_path(path: str) -> str:
    """Пути считаем от корня репозитория, а не от текущей папки."""
    if os.path.isabs(path):
        return path
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(root, path)


def post(path: str, payload: dict) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(SERVER + path, data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def get(path: str) -> bytes:
    with urllib.request.urlopen(SERVER + path, timeout=60) as r:
        return r.read()


def upload(png: str) -> str:
    """Картинка кладётся в input ComfyUI через API: путь к папке знать не нужно."""
    name = os.path.basename(png)
    boundary = "----vn" + uuid.uuid4().hex
    ctype = mimetypes.guess_type(name)[0] or "image/png"
    parts = []
    for key, val in (("overwrite", "true"), ("type", "input"), ("subfolder", "blockout")):
        parts.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n"
                      % (boundary, key, val)).encode("utf-8"))
    parts.append(("--%s\r\nContent-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\n"
                  "Content-Type: %s\r\n\r\n" % (boundary, name, ctype)).encode("utf-8"))
    parts.append(open(png, "rb").read())
    parts.append(("\r\n--%s--\r\n" % boundary).encode("utf-8"))
    body = b"".join(parts)
    req = urllib.request.Request(SERVER + "/upload/image", data=body,
                                 headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    with urllib.request.urlopen(req, timeout=120) as r:
        info = json.loads(r.read().decode("utf-8"))
    sub = info.get("subfolder") or ""
    return (sub + "/" + info["name"]) if sub else info["name"]


def graph(image_ref: str, prompt: str, denoise: float, seed: int, steps: int,
          tag: str, palette_hex: str = "", sampling: str = "flow",
          refine: float = 0.0) -> dict:
    """API-граф: блокаут -> VAEEncode -> KSampler(denoise) -> пиксель-ноды -> два файла.

    refine > 0 добавляет второй проход от результата первого. Он нужен потому, что одним
    проходом геометрию и стиль не получить сразу: при denoise ниже 0.9 держится планировка,
    но кадр выходит плоско-векторным, а при 0.95 приходит пиксель-арт, но комната уже своя.
    Второй проход с низкой силой дорисовывает манеру по уже готовому содержанию.
    """
    g = {
        "unet":  {"class_type": "UNETLoader",
                  "inputs": {"unet_name": UNET, "weight_dtype": "default"}},
        "lora":  {"class_type": "LoraLoaderModelOnly",
                  "inputs": {"model": ["unet", 0], "lora_name": LORA, "strength_model": 1.0}},
        "shift": {"class_type": "ModelSamplingAuraFlow",
                  "inputs": {"model": ["lora", 0], "shift": 3.0, "sampling": sampling}},
        "clip":  {"class_type": "CLIPLoader",
                  "inputs": {"clip_name": CLIP, "type": "lumina2", "device": "default"}},
        "vae":   {"class_type": "VAELoader", "inputs": {"vae_name": VAE}},
        "pos":   {"class_type": "CLIPTextEncode",
                  "inputs": {"clip": ["clip", 0], "text": prompt}},
        # при CFG 1 негатив не участвует, но вход у KSampler обязательный
        "neg":   {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["pos", 0]}},
        "load":  {"class_type": "LoadImage", "inputs": {"image": image_ref}},
        "enc":   {"class_type": "VAEEncode",
                  "inputs": {"pixels": ["load", 0], "vae": ["vae", 0]}},
        "samp":  {"class_type": "KSampler",
                  "inputs": {"model": ["shift", 0], "seed": seed, "steps": steps, "cfg": CFG,
                             "sampler_name": SAMPLER, "scheduler": SCHEDULER,
                             "positive": ["pos", 0], "negative": ["neg", 0],
                             "latent_image": ["enc", 0], "denoise": denoise}},
        "dec":   {"class_type": "VAEDecode",
                  "inputs": {"samples": ["samp", 0], "vae": ["vae", 0]}},
        "raw":   {"class_type": "SaveImage",
                  "inputs": {"images": ["last", 0], "filename_prefix": "vn/raw_" + tag}},
        "pp":    {"class_type": "SK_PixelPerfect",
                  "inputs": {"image": ["last", 0], "mode": "fixed_size",
                             "width": ART[0], "height": ART[1], "scale": 1,
                             "method": "dominant", "pre_colors": PRE_COLORS}},
        "pal":   {"class_type": "SK_Palette",
                  "inputs": {"image": ["pp", 0], "source": "hex" if palette_hex else "auto",
                             "colors": 48, "preset": "PICO-8", "dither": "none",
                             "dither_strength": 0.5, "shared_palette": True,
                             "hex_palette": palette_hex}},
        "clean": {"class_type": "SK_Cleanup",
                  # speck_size 0: очистка мелких кластеров тут только съедает детали
                  "inputs": {"image": ["pal", 0], "speck_size": 0, "max_contrast": 0.12,
                             "outline": "none", "outline_color": "#140c1c",
                             "outline_diagonal": False, "darken": 0.2}},
        "art":   {"class_type": "SaveImage",
                  "inputs": {"images": ["clean", 0], "filename_prefix": "vn/art_" + tag}},
    }
    if refine > 0:
        g["enc2"] = {"class_type": "VAEEncode",
                     "inputs": {"pixels": ["dec", 0], "vae": ["vae", 0]}}
        g["samp2"] = {"class_type": "KSampler",
                      "inputs": {"model": ["shift", 0], "seed": seed + 1,
                                 "steps": min(32, max(STEPS, round(STEPS / refine))),
                                 "cfg": CFG, "sampler_name": SAMPLER, "scheduler": SCHEDULER,
                                 "positive": ["pos", 0], "negative": ["neg", 0],
                                 "latent_image": ["enc2", 0], "denoise": refine}}
        g["dec2"] = {"class_type": "VAEDecode",
                     "inputs": {"samples": ["samp2", 0], "vae": ["vae", 0]}}
    # куда смотрят пиксель-ноды: на второй проход, если он есть
    src = "dec2" if refine > 0 else "dec"
    g["raw"]["inputs"]["images"] = [src, 0]
    g["pp"]["inputs"]["image"] = [src, 0]
    return g


def run(g: dict, client: str) -> dict:
    res = post("/prompt", {"prompt": g, "client_id": client})
    pid = res["prompt_id"]
    waited = 0.0
    while True:
        hist = json.loads(get("/history/" + pid).decode("utf-8"))
        if pid in hist:
            return hist[pid]
        time.sleep(1.0)
        waited += 1.0
        if waited > 600:
            raise SystemExit("прогон не закончился за 10 минут: " + pid)


def save_outputs(hist: dict, out_dir: str, names: dict) -> list:
    """Скачать результат. names: node_id -> имя файла без расширения."""
    saved = []
    for node, data in hist.get("outputs", {}).items():
        if node not in names:
            continue
        for img in data.get("images", []):
            q = urllib.parse.urlencode({"filename": img["filename"],
                                        "subfolder": img.get("subfolder", ""),
                                        "type": img.get("type", "output")})
            blob = get("/view?" + q)
            dest = os.path.join(out_dir, names[node] + ".png")
            os.makedirs(out_dir, exist_ok=True)
            open(dest, "wb").write(blob)
            saved.append(dest)
    return saved


def main() -> None:
    ap = argparse.ArgumentParser(description="Фон из кадра блокаута через ComfyUI")
    ap.add_argument("scene", help="имя кадра (%s) или all" % ", ".join(SCENES))
    ap.add_argument("--phase", default="day", help="day, night или через запятую")
    ap.add_argument("--denoise", default="0.6",
                    help="сила переписывания, через запятую для подбора")
    ap.add_argument("--seed", type=int, default=0, help="0 — случайный")
    ap.add_argument("--steps", type=int, default=0,
                    help="0 — считать как %d/denoise, чтобы шагов фактически было столько же"
                         % STEPS)
    ap.add_argument("--shade", default="flat", choices=["flat", "lit"],
                    help="какой кадр блокаута брать на вход: плоский или со светом фазы")
    ap.add_argument("--in-dir", default=BLOCKOUT_DIR, help="где лежат кадры блокаута")
    ap.add_argument("--out", default=OUT_DIR, help="куда класть результат")
    ap.add_argument("--palette", default="", help="строка #hex #hex … вместо палитры из кадра")
    ap.add_argument("--sampling", default="flow", choices=["flow", "img_to_img_velocity"],
                    help="режим ModelSamplingAuraFlow")
    ap.add_argument("--refine", type=float, default=0.0,
                    help="второй проход такой силы: стиль по готовой композиции")
    ap.add_argument("--keep-raw", action="store_true",
                    help="сохранить и кадр до пикселизации (для разбора)")
    a = ap.parse_args()

    scenes = list(SCENES) if a.scene == "all" else [s.strip() for s in a.scene.split(",")]
    for s in scenes:
        if s not in SCENES:
            raise SystemExit("нет такого кадра: %s (есть: %s)" % (s, ", ".join(SCENES)))
    phases = [p.strip() for p in a.phase.split(",")]
    for p in phases:
        if p not in PHASES:
            raise SystemExit("нет такой фазы: %s (есть: %s)" % (p, ", ".join(PHASES)))
    denoises = [float(d) for d in a.denoise.split(",")]

    in_dir = repo_path(a.in_dir)
    out_dir = repo_path(a.out)
    client = uuid.uuid4().hex
    seed = a.seed or random.randint(1, 2 ** 31)

    try:
        get("/system_stats")
    except urllib.error.URLError as e:
        raise SystemExit("ComfyUI не отвечает на %s: %s" % (SERVER, e))

    total = len(scenes) * len(phases) * len(denoises)
    done = 0
    print("кадров: %d, сид %d, выход %s" % (total, seed, out_dir))

    for scene in scenes:
        for phase in phases:
            # при --shade lit вход свой на каждую фазу: свет в кадре задаётся блокаутом,
            # промптом его не получить — он добавит лампу, но комнату не затемнит
            name = ("blk_%s_lit_%s.png" % (scene, phase) if a.shade == "lit"
                    else "blk_%s_flat.png" % scene)
            src = os.path.join(in_dir, name)
            if not os.path.exists(src):
                raise SystemExit("нет кадра блокаута %s — сначала отрендерите apartment.py "
                                 "(--render %s --shade %s --phase %s)"
                                 % (src, scene, a.shade, phase))
            ref = upload(src)
            prompt = "%s, %s, %s" % (STYLE, SCENES[scene], PHASES[phase])
            for dn in denoises:
                steps = a.steps or min(32, max(STEPS, round(STEPS / dn)))
                suffix = "d%02d" % round(dn * 100)
                if a.refine > 0:
                    suffix += "_r%02d" % round(a.refine * 100)
                tag = "%s_%s_%s" % (scene, phase, suffix)
                t0 = time.time()
                hist = run(graph(ref, prompt, dn, seed, steps, tag, a.palette, a.sampling,
                                 a.refine), client)
                names = {"art": "bg_%s_%s_%s" % (scene, phase, suffix)}
                if a.keep_raw:
                    names["raw"] = "raw_%s_%s_%s" % (scene, phase, suffix)
                files = save_outputs(hist, out_dir, names)
                done += 1
                print("[%d/%d] %s denoise %.2f, шагов %d, %.1f с -> %s"
                      % (done, total, tag, dn, steps, time.time() - t0,
                         ", ".join(os.path.basename(f) for f in files)))


if __name__ == "__main__":
    main()
