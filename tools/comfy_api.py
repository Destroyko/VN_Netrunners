"""Транспорт до ComfyUI: очередь, ожидание, загрузка и выгрузка файлов.

Вынесено из comfy_bg.py, когда генерация фонов отменилась (18.11.2026): сама
генерация фонов больше не нужна, а способ разговаривать с ComfyUI нужен —
портреты персонажей делаются так же (docs/art/ai-pipeline.md, раздел 9).

Здесь нет ничего про содержание картинки: только как отправить граф и забрать результат.
"""

import json
import mimetypes
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

SERVER = "http://127.0.0.1:8188"

# Z-Image Turbo + пиксель-LoRA (ai-pipeline.md 4.2)
UNET = "z_image_turbo_bf16.safetensors"
LORA = "spritekiln_zimage_pixel_art.safetensors"
CLIP = "qwen_3_4b.safetensors"
VAE = "ae.safetensors"
STEPS = 8          # столько шагов у дистиллированной модели при denoise 1.0
CFG = 1.0
SAMPLER = "res_multistep"
SCHEDULER = "simple"

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
