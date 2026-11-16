"""Достать граф ComfyUI из метаданных PNG и сохранить файлом, который загружается в редактор.

ComfyUI пишет в PNG два JSON: `workflow` — то, что открывается перетаскиванием в редактор,
и `prompt` — то, что реально исполнялось. Нода `SK Save Pixel Art` метаданные не пишет вовсе,
поэтому в графе нужен обычный `Save Image` (у нас с префиксом META).

    D:\\AI\\ComfyUI\\python_embeded\\python.exe tools/comfy_workflow.py <png> [-o файл.json]
    D:\\AI\\ComfyUI\\python_embeded\\python.exe tools/comfy_workflow.py <png> --show
"""

import argparse
import json
import os
import struct
import zlib


def read_chunks(path):
    """Текстовые чанки PNG: tEXt и сжатый zTXt."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("это не PNG: %s" % path)
    pos, out = 8, {}
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8].decode("latin-1")
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == "tEXt":
            key, _, val = body.partition(b"\x00")
            out[key.decode("latin-1")] = val.decode("utf-8", "replace")
        elif ctype == "zTXt":
            key, _, rest = body.partition(b"\x00")
            out[key.decode("latin-1")] = zlib.decompress(rest[1:]).decode("utf-8", "replace")
        if ctype == "IEND":
            break
    return out


def summary(prompt_json):
    """Коротко: какие ноды и с какими значениями отработали."""
    lines = []
    for nid, node in sorted(prompt_json.items()):
        fixed = {k: v for k, v in node.get("inputs", {}).items() if not isinstance(v, list)}
        if fixed:
            lines.append("%-6s %-26s %s" % (nid, node.get("class_type", "?"),
                                            json.dumps(fixed, ensure_ascii=False)[:150]))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="Граф ComfyUI из метаданных PNG")
    ap.add_argument("png")
    ap.add_argument("-o", "--out", help="куда сохранить workflow (по умолчанию рядом с png)")
    ap.add_argument("--show", action="store_true", help="показать настройки, ничего не сохранять")
    args = ap.parse_args()

    ch = read_chunks(args.png)
    if "workflow" not in ch and "prompt" not in ch:
        raise SystemExit("метаданных нет — так пишет SK Save Pixel Art; нужен обычный Save Image")

    if args.show or "workflow" not in ch:
        print(summary(json.loads(ch["prompt"])))
        if "workflow" not in ch:
            print("\n(в файле только prompt: в редактор он не загрузится)")
        return

    out = args.out or os.path.splitext(args.png)[0] + "_workflow.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(json.loads(ch["workflow"]), f, ensure_ascii=False, indent=1)
    print("сохранено: %s" % out)


if __name__ == "__main__":
    main()
