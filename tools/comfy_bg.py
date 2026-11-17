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

# Размер арта по умолчанию. Генерация идёт вдвое крупнее: делится нацело на арт
# (правило целого деления, ai-pipeline.md 4.1) и на 8 для латента.
# Меняется ключами --art и --gen: какое разрешение фонов взять за базовое — открытый вопрос
ART = (640, 360)
GEN = (1280, 720)

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
         "dark outline on objects, two or three tones per material, sharp highlights, "
         # один и тот же набор цветов во всех кадрах комнаты — это и держит её целой
         "deep muted blue walls, dark grey floor, warm brown wooden furniture, "
         "pale bedding, black computer hardware")

# Свет по фазе суток. Он же решает, какой кадр блокаута брать (--shade lit --phase ...),
# но вход берём всегда плоский: lit-рендер навязывает генератору свою светотень
PHASES = {
    "day": ("daytime, bright daylight pouring through the window and falling across the floor, "
            "the window is the brightest block in the frame, clear light and shade, "
            "the room itself stays dim and shadowed away from the window"),
    "night": ("night, lights off, the room lit only by the blue glow of a computer monitor "
              "and a warm desk lamp, deep shadows, dark window with distant city lights"),
}

# Содержание кадров. Одна комната — один промпт: «и ещё на заднем плане» модель смешает
SCENES = {
    # Четыре вида одной комнаты из одной точки: игрок поворачивается стрелками.
    # Общее во всех промптах — стены, пол и свет: иначе комната развалится между кадрами
    "room_desk": "a small rented bedroom of a young programmer, looking at the desk wall: "
                 "a desk with a modern black tower PC and a widescreen flat monitor, "
                 "keyboard, mug, scattered papers, an office chair, a shelf with books above "
                 "the desk, a window covered by closed vertical slat blinds, narrow upright slats, behind the desk, "
                 "cables running along the floor",
    "room_closet": "a small rented bedroom, looking at the wardrobe wall: a tall wooden "
                   "wardrobe with its doors shut, a chest of drawers beside it, cardboard "
                   "boxes and folded clothes stacked on top, a worn rug on the floor",
    "room_door": "a small rented bedroom, looking at the door wall: the room door shut, "
                 "a coat and a bag hanging on wall hooks beside it, a cork board covered "
                 "with pinned notes, photos and a calendar page, a light switch",
    "room_bed": "a small rented bedroom, looking at the bed wall: an unmade single bed with "
                "pale rumpled bedding and a pillow, a bedside table with a phone and a lamp, "
                "a laundry basket, a poster taped to the wall above the bed",
    "room_pc": "the desk of a young programmer seen close up: a modern black tower PC with "
               "a side panel, a widescreen flat monitor with a glowing screen, a mechanical "
               "keyboard, a mug, papers and sticky notes, tangled cables, a window covered by "
               "closed vertical slat blinds, narrow upright slats, above the desk",
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
          refine: float = 0.0, art=None, colors: int = 48, pixel: bool = True,
          gen=None, control="", control_strength=0.7, control_end=0.75,
          control_start=0.0) -> dict:
    """API-граф: блокаут -> VAEEncode -> KSampler(denoise) -> пиксель-ноды -> два файла.

    control — файл патча ControlNet. Тогда схема другая: вместо «сжать силу переписывания,
    чтобы удержать планировку» геометрию держит карта глубины, а модель рисует с чистого
    шума на полной силе. Это снимает выбор между планировкой и стилем (5.8, 5.10).

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
        # блокаут рендерится в 1280x720; если генерация другого размера, подгоняем здесь,
        # чтобы не пересобирать сцену ради каждого разрешения
        "fit":   {"class_type": "ImageScale",
                  "inputs": {"image": ["load", 0], "upscale_method": "nearest-exact",
                             "width": (gen or GEN)[0], "height": (gen or GEN)[1],
                             "crop": "disabled"}},
        "enc":   {"class_type": "VAEEncode",
                  "inputs": {"pixels": ["fit", 0], "vae": ["vae", 0]}},
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
                             "width": (art or ART)[0], "height": (art or ART)[1], "scale": 1,
                             "method": "dominant", "pre_colors": max(PRE_COLORS, colors * 2)}},
        "pal":   {"class_type": "SK_Palette",
                  "inputs": {"image": ["pp", 0], "source": "hex" if palette_hex else "auto",
                             "colors": colors, "preset": "PICO-8", "dither": "none",
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
    if control:
        # Карта глубины: в Blender ближнее тёмное, ControlNet ждёт наоборот
        g["inv"] = {"class_type": "ImageInvert", "inputs": {"image": ["fit", 0]}}
        g["patch"] = {"class_type": "ModelPatchLoader", "inputs": {"name": control}}
        g["cnet"] = {"class_type": "ZImageFunControlnet",
                     "inputs": {"model": ["lora", 0], "model_patch": ["patch", 0],
                                "vae": ["vae", 0], "strength": control_strength,
                                "image": ["inv", 0], "start_percent": control_start,
                                "end_percent": control_end}}
        g["shift"]["inputs"]["model"] = ["cnet", 0]
        # С чистого шума: геометрию держит управление, а не исходная картинка —
        # иначе в кадре остаются гладкие градиенты и пластиковые тени рендера
        g["lat"] = {"class_type": "EmptySD3LatentImage",
                    "inputs": {"width": (gen or GEN)[0], "height": (gen or GEN)[1],
                               "batch_size": 1}}
        g["samp"]["inputs"]["latent_image"] = ["lat", 0]
        g["samp"]["inputs"]["denoise"] = 1.0
        del g["enc"]
    if not pixel:
        # Без пиксельной сетки: на 1280x720 и выше квантование в сетку теряет смысл —
        # пиксели уже мельче, чем видит глаз, и картинка просто грубеет. Остаётся
        # сведение палитры, чтобы цвета между фонами были общие
        g["pal"]["inputs"]["image"] = [src, 0]
        del g["pp"]
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
    ap.add_argument("--shade", default="flat", choices=["flat", "lit", "depth"],
                    help="вход: плоский кадр, со светом фазы или карта глубины (ControlNet)")
    ap.add_argument("--in-dir", default=BLOCKOUT_DIR, help="где лежат кадры блокаута")
    ap.add_argument("--out", default=OUT_DIR, help="куда класть результат")
    ap.add_argument("--palette", default="", help="строка #hex #hex … вместо палитры из кадра")
    ap.add_argument("--sampling", default="flow", choices=["flow", "img_to_img_velocity"],
                    help="режим ModelSamplingAuraFlow")
    ap.add_argument("--refine", type=float, default=0.0,
                    help="второй проход такой силы: стиль по готовой композиции")
    ap.add_argument("--control", default="",
                    help="файл ControlNet из model_patches; 'auto' — первый попавшийся")
    ap.add_argument("--control-strength", type=float, default=0.6,
                    help="сила: 0.7+ оставляет мебель коробками, 0.45 теряет планировку")
    ap.add_argument("--control-end", type=float, default=0.5,
                    help="доля шагов с управлением; остаток модель дорисовывает сама")
    ap.add_argument("--control-start", type=float, default=0.0)
    ap.add_argument("--art", default="%dx%d" % ART,
                    help="размер арта, например 1280x720 (какой базовый — открытый вопрос)")
    ap.add_argument("--gen", default="",
                    help="размер генерации; пусто — вдвое больше арта, но не крупнее 1920")
    ap.add_argument("--colors", type=int, default=48, help="цветов в палитре")
    ap.add_argument("--no-pixel", action="store_true",
                    help="без пиксельной сетки: от 1280x720 квантование только грубит")
    ap.add_argument("--keep-raw", action="store_true",
                    help="сохранить и кадр до пикселизации (для разбора)")
    a = ap.parse_args()

    art = tuple(int(v) for v in a.art.lower().split("x"))
    if a.gen:
        gen = tuple(int(v) for v in a.gen.lower().split("x"))
    else:
        gen = (art[0] * 2, art[1] * 2) if art[0] * 2 <= 1920 else art
    if gen[0] % 8 or gen[1] % 8:
        raise SystemExit("размер генерации %dx%d не делится на 8 (латент)" % gen)
    if gen[0] % art[0] or gen[1] % art[1]:
        print("[!] %dx%d не делится нацело на %dx%d — будут полосы (ai-pipeline.md 4.1)"
              % (gen + art))

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

    control = a.control
    if control == "auto":
        info = json.loads(get("/object_info/ModelPatchLoader").decode("utf-8"))
        files = info["ModelPatchLoader"]["input"]["required"]["name"][0]
        if not files:
            raise SystemExit("в models/model_patches пусто — положите туда файл ControlNet")
        control = files[0]
        print("ControlNet: %s, сила %.2f, до %d%% шагов"
              % (control, a.control_strength, round(a.control_end * 100)))

    total = len(scenes) * len(phases) * len(denoises)
    done = 0
    print("кадров: %d, сид %d, выход %s" % (total, seed, out_dir))

    for scene in scenes:
        for phase in phases:
            # при --shade lit вход свой на каждую фазу: свет в кадре задаётся блокаутом,
            # промптом его не получить — он добавит лампу, но комнату не затемнит
            if a.shade == "depth":
                name = "blk_%s_depth.png" % scene
            elif a.shade == "lit":
                name = "blk_%s_lit_%s.png" % (scene, phase)
            else:
                name = "blk_%s_flat.png" % scene
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
                suffix += "_%d" % art[0]
                tag = "%s_%s_%s" % (scene, phase, suffix)
                t0 = time.time()
                hist = run(graph(ref, prompt, dn, seed, steps, tag, a.palette, a.sampling,
                                 a.refine, art, a.colors, not a.no_pixel, gen, control,
                                 a.control_strength, a.control_end, a.control_start), client)
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
