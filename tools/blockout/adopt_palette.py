"""Перевести сцену на палитру: чужие материалы -> pal_*.

За несколько дней работы в сцене копятся материалы из разных источников: у каждого
импортированного ассета свои, а `*_flat` от скриптов детализации несут цвета старой
блоковой палитры. Этот скрипт приводит их к общей палитре разом:

1. находит материалы, которых нет в палитре (не `pal_*`);
2. определяет цвет каждого и подбирает ближайший цвет палитры (по восприятию, Lab);
3. определяет тип материала по имени (металл, пластик, дерево, стекло, свечение...);
4. меняет материал на объектах, на узлах Set Material и на входах Geometry Nodes;
5. у материалов с картинкой-текстурой берёт цвет **по граням**: образец в точке UV
   грани, и каждая грань получает ближайший цвет палитры (так перекрашиваются
   карандаши в стакане: на одной цветной текстуре у них разные цвета);
6. удаляет материалы, оставшиеся без дела, и картинки, которые только они и держали.

    # сначала посмотреть, ничего не записывая
    & "...blender.exe" -b сцена.blend --python tools\\blockout\\adopt_palette.py -- --dry

    # применить; результат — НОВЫЙ файл рядом, исходный не меняется
    & "...blender.exe" -b сцена.blend --python tools\\blockout\\adopt_palette.py

Ключи: `--keep а,б` — что не трогать (по подстроке в имени; по умолчанию `wallpaper,calendar`
— обои и календарь разработчика); `--out путь` — куда писать; `--no-images` — не
перекрашивать материалы с картинками; `--no-purge` — не удалять лишнее.

Что скрипт НЕ делает. Он не угадывает смысл: тип материала берётся по имени, а у
безымянных (`Material #48`) ставится пластик и помечается «угадано» в отчёте. Отчёт
сохраняется рядом (`*_report.md`), его стоит просмотреть: спорные строки — те, где цвет
сдвинулся больше обычного или тип угадан по умолчанию.
"""

import collections
import os
import re
import sys

import bpy
import numpy as np

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bl_common as B  # noqa: E402
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402

KEEP_DEFAULT = ("wallpaper", "calendar")
DELTA_WARN = 9.0       # сдвиг цвета (ΔE по CIEDE2000), после которого строка попадает в «проверить»

# Подсказки типа по имени. Порядок важен: wheel_metal — металл, а не пластик, потому что
# «metal» проверяется раньше «wheel». Короткие подсказки (≤3 знака) сравниваются как
# целые слова: иначе «led» нашлось бы внутри «handled»
KIND_HINTS = (
    ("glass",   ("glass", "vidro", "window_glass")),
    ("glow",    ("led", "bulb")),
    ("metal",   ("metal", "matal", "steel", "chrome", "iron", "gold", "bars", "alum", "brass",
                 "copper", "mirror")),
    ("plastic", ("plastic", "rubber", "insulator", "pvc", "wheel", "keyboard", "plates",
                 "ceramic", "dark_flat", "black", "screen")),
    ("fabric",  ("fabric", "cloth", "curtain", "pillow", "blanket", "rug", "carpet", "towel",
                 "sofa", "lampshade", "linen", "doormat", "soft", "bedding")),
    ("paper",   ("paper", "book", "cover", "page", "stationery", "art_", "pink_flat", "poster",
                 "card")),
    ("wood",    ("wood", "plywood", "veneer", "desk", "furn", "floor", "parquet", "laminate",
                 "oak", "closet", "door", "table", "cab", "worktop", "shelf", "bookcase",
                 "dresser", "nightstand", "cupboard", "frame", "bed")),
    ("plant",   ("plant", "leaf", "leaves", "cactus", "flower")),
    ("wall",    ("wall", "trim", "ceiling", "plaster", "base")),
)
DEFAULT_KIND = "plastic"


# --- цвет: sRGB -> Lab ------------------------------------------------------

def to_srgb(lin):
    lin = np.clip(np.asarray(lin, dtype=np.float64), 0.0, 1.0)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)


def srgb_to_lab(rgb):
    """sRGB 0..1, форма (..., 3) -> Lab. Расстояние в Lab близко к воспринимаемому."""
    rgb = np.asarray(rgb, dtype=np.float64)
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    t = (lin @ m.T) / np.array([0.95047, 1.0, 1.08883])
    f = np.where(t > 0.008856, np.cbrt(t), 7.787 * t + 16.0 / 116.0)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]),
                     200 * (f[..., 1] - f[..., 2])], axis=-1)


def srgb_to_oklab(rgb):
    """sRGB 0..1 -> OKLab. Оттенок в нём честнее, чем в Lab: чистый синий остаётся синим,
    а в Lab он уезжает в пурпурный и «ближе» к фиолетовому, чем к синему."""
    rgb = np.asarray(rgb, dtype=np.float64)
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    l = np.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = np.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = np.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return np.stack([0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s], axis=-1)


def hex_to_srgb(hexcol):
    h = hexcol.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


_CAND = {}


def candidates(kind):
    """Цвета палитры, допустимые на этом материале, вместе с их Lab."""
    if kind not in _CAND:
        ids = [c for c in P.COLORS if kind in P.kinds_for(c)]
        _CAND[kind] = (ids, srgb_to_lab(np.array([hex_to_srgb(P.COLORS[c]) for c in ids])))
    return _CAND[kind]


def de2000(lab1, lab2):
    """Цветовое различие CIEDE2000 между наборами Lab: (N,3) и (M,3) -> матрица (N,M).

    Почему не расстояние в Lab: оно решает хроматичностью, а не оттенком, и тусклый
    коричневатый цвет (#9E866F, шкаф) оказывается «ближе» к оливковому, чем к коричневому
    дереву. CIEDE2000 это учитывает: на тех же цветах он выбирает brown_mid.
    """
    L1, a1, b1 = lab1[:, 0:1], lab1[:, 1:2], lab1[:, 2:3]
    L2, a2, b2 = lab2[None, :, 0], lab2[None, :, 1], lab2[None, :, 2]
    C1, C2 = np.hypot(a1, b1), np.hypot(a2, b2)
    Cb = (C1 + C2) / 2
    G = 0.5 * (1 - np.sqrt(Cb ** 7 / (Cb ** 7 + 25.0 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = np.hypot(a1p, b1), np.hypot(a2p, b2)
    h1 = np.degrees(np.arctan2(b1, a1p)) % 360
    h2 = np.degrees(np.arctan2(b2, a2p)) % 360
    dL, dC = L2 - L1, C2p - C1p
    dh = h2 - h1
    dh = np.where(dh > 180, dh - 360, np.where(dh < -180, dh + 360, dh))
    dH = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dh) / 2)
    Lb, Cbp = (L1 + L2) / 2, (C1p + C2p) / 2
    hb = np.where(np.abs(h1 - h2) > 180, (h1 + h2 + 360) / 2, (h1 + h2) / 2)
    T = (1 - 0.17 * np.cos(np.radians(hb - 30)) + 0.24 * np.cos(np.radians(2 * hb))
         + 0.32 * np.cos(np.radians(3 * hb + 6)) - 0.20 * np.cos(np.radians(4 * hb - 63)))
    Sl = 1 + 0.015 * (Lb - 50) ** 2 / np.sqrt(20 + (Lb - 50) ** 2)
    Sc, Sh = 1 + 0.045 * Cbp, 1 + 0.015 * Cbp * T
    dth = 30 * np.exp(-(((hb - 275) / 25) ** 2))
    Rt = -np.sin(np.radians(2 * dth)) * 2 * np.sqrt(Cbp ** 7 / (Cbp ** 7 + 25.0 ** 7))
    return np.sqrt((dL / Sl) ** 2 + (dC / Sc) ** 2 + (dH / Sh) ** 2 + Rt * (dC / Sc) * (dH / Sh))


def nearest(srgb, kind):
    """Ближайший цвет палитры. srgb — (3,) или (N,3); возвращает (id, ΔE) или массивы.

    Для свечения сравниваем по оттенку: у светодиода цвет почти всегда чистый и ярче
    любого цвета палитры, а по расстоянию чистый синий «ближе» к фиолетовому, чем к
    синему, потому что решает насыщенность, а не оттенок.
    """
    ids, lab = candidates(kind)
    src = srgb_to_lab(np.asarray(srgb, dtype=np.float64))
    single = src.ndim == 1
    src = src.reshape(-1, 3)
    d = de2000(src, lab)
    if kind == "glow":
        # цветной источник сравниваем по оттенку в OKLab, серый и белый — по CIEDE2000
        cand_ok = srgb_to_oklab(np.array([hex_to_srgb(P.COLORS[c]) for c in ids]))
        src_ok = srgb_to_oklab(np.asarray(srgb, dtype=np.float64)).reshape(-1, 3)
        chroma = np.hypot(src_ok[:, 1], src_ok[:, 2])
        cand_chroma = np.hypot(cand_ok[:, 1], cand_ok[:, 2])
        hue = np.degrees(np.arctan2(src_ok[:, 2], src_ok[:, 1]))
        cand_hue = np.degrees(np.arctan2(cand_ok[:, 2], cand_ok[:, 1]))
        dh = np.abs((hue[:, None] - cand_hue[None, :] + 180.0) % 360.0 - 180.0)
        by_hue = dh + 30.0 * np.abs(src_ok[:, None, 0] - cand_ok[None, :, 0])
        by_hue = np.where(cand_chroma[None, :] > 0.06, by_hue, 1e6)
        d = np.where((chroma > 0.06)[:, None], by_hue, d)
    best = d.argmin(axis=1)
    out_ids = [ids[i] for i in best]
    out_d = d[np.arange(len(best)), best]
    return (out_ids[0], float(out_d[0])) if single else (out_ids, out_d)


def blackbody_rgb(kelvin):
    """Приближённый цвет чёрного тела (Tanner Helland) -> линейный RGB."""
    t = max(1000.0, min(40000.0, kelvin)) / 100.0
    r = 255.0 if t <= 66 else 329.698727446 * ((t - 60) ** -0.1332047592)
    g = (99.4708025861 * np.log(t) - 161.1195681661) if t <= 66 \
        else 288.1221695283 * ((t - 60) ** -0.0755148492)
    b = 255.0 if t >= 66 else (0.0 if t <= 19 else 138.5177312231 * np.log(t - 10) - 305.0447927307)
    srgb = np.clip(np.array([r, g, b]) / 255.0, 0, 1)
    return tuple(np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4))


# --- разбор материала -------------------------------------------------------

def trace_image(sock, depth=0):
    """Идём от входа Base Color вглубь по цепочке узлов, пока не найдём картинку."""
    if not sock.is_linked or depth > 6:
        return None
    node = sock.links[0].from_node
    if node.type == "TEX_IMAGE":
        return node.image
    for inp in node.inputs:
        if inp.type == "RGBA" and inp.is_linked:
            img = trace_image(inp, depth + 1)
            if img:
                return img
    return None


def saturation(c):
    return max(c) - min(c)


def scan(nt, info, depth=0):
    """Собрать из дерева узлов: цвет, силу свечения, картинку, признак стекла."""
    for n in nt.nodes:
        t = n.type
        if t == "BSDF_PRINCIPLED":
            bc = n.inputs["Base Color"]
            if bc.is_linked:
                img = trace_image(bc)
                if img is not None:
                    info["image"] = info["image"] or img
            elif info["rgb"] is None:
                info["rgb"] = tuple(bc.default_value[:3])
            ec = n.inputs["Emission Color"]
            es = n.inputs["Emission Strength"].default_value
            if es > 1.0 and not ec.is_linked and max(ec.default_value[:3]) > 0.05:
                info["glow"] = max(info["glow"], es)
                info["rgb"] = tuple(ec.default_value[:3])
        elif t == "EMISSION":
            col, strength = n.inputs[0], n.inputs[1].default_value
            rgb = None
            if col.is_linked and col.links[0].from_node.type == "BLACKBODY":
                rgb = blackbody_rgb(col.links[0].from_node.inputs["Temperature"].default_value)
            elif not col.is_linked:
                rgb = tuple(col.default_value[:3])
            if rgb is not None and info["rgb"] is None:
                info["rgb"] = rgb
            info["glow"] = max(info["glow"], strength)
        elif t == "BSDF_GLASS":
            info["glass"] = True
            if info["rgb"] is None:
                info["rgb"] = tuple(n.inputs["Color"].default_value[:3])
        elif t == "GROUP" and n.node_tree is not None and depth < 3:
            # узловая группа: цвета лежат либо в её входах, либо внутри — берём самый
            # насыщенный, потому что серые входы обычно служебные
            cols = [tuple(i.default_value[:3]) for i in n.inputs
                    if i.type == "RGBA" and not i.is_linked]
            if cols and info["rgb"] is None:
                info["rgb"] = max(cols, key=saturation)
            scan(n.node_tree, info, depth + 1)
    return info


def probe(mat):
    """Что у материала внутри. Возвращает словарь с ключами rgb, glow, image, glass, cel."""
    info = {"rgb": None, "glow": 0.0, "image": None, "glass": False, "cel": False}
    if not mat.use_nodes or mat.node_tree is None:
        info["rgb"] = tuple(mat.diffuse_color[:3])
        return info
    nt = mat.node_tree
    if any(n.type == "SHADERTORGB" for n in nt.nodes):
        # наш cel-шейдер: цвет лежит в рампе, последняя ступень — полный цвет
        info["cel"] = True
        for n in nt.nodes:
            if n.type == "VALTORGB":
                info["rgb"] = tuple(n.color_ramp.elements[-1].color[:3])
        return info
    scan(nt, info)
    if info["rgb"] is None:
        info["rgb"] = tuple(mat.diffuse_color[:3])
    return info


def guess_kind(name, info):
    """Тип материала по имени. Возвращает (тип, откуда): имя / свойство / по умолчанию."""
    if info["glow"] > 1.0:
        return "glow", "свечение > 1"
    if info["glass"]:
        return "glass", "узел стекла"
    low = name.lower()
    words = set(re.split(r"[^a-z0-9а-я]+", low))
    for kind, hints in KIND_HINTS:
        for h in hints:
            if (len(h) <= 3 and h in words) or (len(h) > 3 and h in low):
                return kind, "имя"
    return DEFAULT_KIND, "угадано"


# --- ссылки на материалы -----------------------------------------------------

def material_refs():
    """Все места, где материал используется: слоты, узлы Set Material, входы модификаторов.

    Возвращает список (материал, функция-замена, держатель). Узлы и модификаторы
    учитываем потому, что материал, назначаемый через Geometry Nodes, ни в одном слоте
    не виден — а удалить его как «лишний» значило бы сломать модель.
    """
    refs = []
    for ob in bpy.data.objects:
        for slot in ob.material_slots:
            if slot.material:
                refs.append((slot.material, lambda m, s=slot: setattr(s, "material", m), ob.name))
        for mod in ob.modifiers:
            if mod.type != "NODES":
                continue
            try:
                keys = list(mod.keys())
            except TypeError:
                continue          # не все модификаторы отдают свои входы — такие пропускаем
            for key in keys:
                try:
                    val = mod[key]
                except Exception:
                    continue
                if isinstance(val, bpy.types.Material):
                    refs.append((val, lambda m, md=mod, k=key: md.__setitem__(k, m), ob.name))
    for group in bpy.data.node_groups:
        for n in group.nodes:
            if n.type == "SET_MATERIAL":
                inp = n.inputs["Material"]
                if inp.default_value is not None:
                    refs.append((inp.default_value,
                                 lambda m, i=inp: setattr(i, "default_value", m),
                                 "узел " + group.name))
    return refs


def get_pal(kind, color):
    """Материал палитры нужного типа и цвета; создаётся, если его ещё нет в сцене."""
    name = P.mat_name(kind, color)
    mat = bpy.data.materials.get(name)
    if mat is not None and mat.library is None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    light = C.build(mat.node_tree, P.srgb(P.COLORS[color]), None, None, None, None, kind)
    C.surface(mat, kind)
    mat.diffuse_color = (*light, 1.0)
    return mat


# --- картинки: цвет по граням ------------------------------------------------

_IMG_CACHE = {}


def image_array(img):
    """Пиксели картинки как (h, w, 3) в sRGB, либо None, если картинка не читается."""
    if img.name in _IMG_CACHE:
        return _IMG_CACHE[img.name]
    w, h = img.size
    arr = None
    if w * h > 0:
        buf = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
        arr = buf.reshape(h, w, 4)[..., :3]
        # Blender отдаёт пиксели 8-битных картинок как есть, в sRGB (проверено замером:
        # серый 128/255 приходит как 0.502, а не 0.216). Для float-картинок это линейные
        if img.is_float and img.colorspace_settings.name != "sRGB":
            arr = to_srgb(arr)
    _IMG_CACHE[img.name] = arr
    return arr


def plan_faces(me, slot_index, arr, kind):
    """Какой цвет палитры у каждой грани, лежащей в этом слоте.

    Возвращает (индексы граней, список id цветов) или None, если у меша нет UV.
    """
    uvl = me.uv_layers.active
    if uvl is None or len(me.polygons) == 0:
        return None
    uv = np.empty(len(me.loops) * 2, dtype=np.float32)
    uvl.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    n = len(me.polygons)
    start = np.empty(n, dtype=np.int32)
    total = np.empty(n, dtype=np.int32)
    midx = np.empty(n, dtype=np.int32)
    me.polygons.foreach_get("loop_start", start)
    me.polygons.foreach_get("loop_total", total)
    me.polygons.foreach_get("material_index", midx)
    sel = np.where(midx == slot_index)[0]
    if sel.size == 0:
        return None
    cent = np.add.reduceat(uv, start, axis=0) / total[:, None]
    u, v = cent[:, 0] % 1.0, cent[:, 1] % 1.0
    h, w, _ = arr.shape
    px = arr[(v * h).astype(np.int64).clip(0, h - 1), (u * w).astype(np.int64).clip(0, w - 1)]
    ids, _ = nearest(px[sel], kind)
    return sel, ids


# --- основной ход ------------------------------------------------------------

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = dict(zip(argv[::2], argv[1::2]))
    dry = "--dry" in argv
    keep = tuple(k.strip().lower() for k in
                 opts.get("--keep", ",".join(KEEP_DEFAULT)).split(",") if k.strip())
    do_images = "--no-images" not in argv
    purge = "--no-purge" not in argv

    src = bpy.data.filepath
    if not src:
        raise SystemExit("сцена без имени: сохраните её, чтобы было куда класть копию")
    stem = os.path.splitext(os.path.basename(src))[0]
    out = opts.get("--out") or os.path.join(os.path.dirname(src), stem + "_palette.blend")
    if os.path.abspath(out) == os.path.abspath(src):
        raise SystemExit("результат не должен затирать исходную сцену: %s" % src)

    def kept(name):
        return any(k in name.lower() for k in keep)

    # --- 0. прежние pal_-материалы: переименовать по-новому ---
    legacy = 0
    for m in list(bpy.data.materials):
        if m.library is None and m.name.startswith("pal_"):
            parsed = P.parse_name(m.name)
            if parsed and parsed[2]:
                legacy += 1
                if not dry:
                    kind, color, _ = parsed
                    m.use_nodes = True
                    C.build(m.node_tree, P.srgb(P.COLORS[color]), None, None, None, None, kind)
                    m.name = P.mat_name(kind, color)

    # --- 1. кого переводить ---
    refs = material_refs()
    holders = collections.defaultdict(set)
    for mat, _, who in refs:
        holders[mat.name].add(who)

    rows, plain, images = [], {}, {}
    for mat in sorted(bpy.data.materials, key=lambda m: -len(holders[m.name])):
        if mat.library is not None or mat.name.startswith("pal_"):
            continue
        if kept(mat.name):
            rows.append({"name": mat.name, "n": len(holders[mat.name]), "note": "оставлен по списку"})
            continue
        if not holders[mat.name]:
            continue                      # висит без дела: уйдёт при чистке
        info = probe(mat)
        kind, why = guess_kind(mat.name, info)
        if info["image"] is not None and do_images and info["glow"] <= 1.0:
            images[mat.name] = (mat, info, kind, why)
            continue
        if info["image"] is not None:
            rows.append({"name": mat.name, "n": len(holders[mat.name]), "note": "картинка, пропущен"})
            continue
        rgb = info["rgb"]
        if kind == "glass" and (rgb is None or max(rgb) == 0.0 and not info["glass"]):
            rgb = (0.85, 0.9, 1.0)
        if info["glow"] > 1.0 and (rgb is None or max(rgb) < 0.01):
            rgb = (1.0, 1.0, 1.0)
        color, de = nearest(to_srgb(rgb), kind)
        plain[mat.name] = (mat, kind, color)
        rows.append({"name": mat.name, "n": len(holders[mat.name]),
                     "src": "#%02X%02X%02X" % tuple(int(round(c * 255)) for c in to_srgb(rgb)),
                     "kind": kind, "why": why, "to": P.mat_name(kind, color), "de": de,
                     "cel": info["cel"]})

    # --- 2. картинки: цвет по граням ---
    face_plans = []      # (меш, индекс слота, индексы граней, id цветов, тип)
    img_rows = []
    seen_meshes = set()
    for name, (mat, info, kind, why) in images.items():
        arr = image_array(info["image"])
        used_by = sorted(holders[name])
        if arr is None:
            img_rows.append({"name": name, "n": len(used_by), "note": "картинка не читается, оставлен"})
            continue
        counts = collections.Counter()
        for obname in used_by:
            ob = bpy.data.objects.get(obname)
            if ob is None or ob.type != "MESH":
                continue
            for i, slot in enumerate(ob.material_slots):
                if slot.material is not mat or (ob.data.name, i) in seen_meshes:
                    continue
                seen_meshes.add((ob.data.name, i))
                plan = plan_faces(ob.data, i, arr, kind)
                if plan is None:
                    continue
                face_plans.append((ob.data, i, plan[0], plan[1], kind, mat))
                counts.update(plan[1])
        top = ", ".join("%s×%d" % (c, n) for c, n in counts.most_common(4))
        img_rows.append({"name": name, "n": len(used_by), "kind": kind, "why": why,
                         "note": "по граням: %d цветов (%s)" % (len(counts), top)})

    # --- 3. отчёт ---
    report = os.path.splitext(out)[0] + "_report.md"
    lines = ["# Отчёт перевода на палитру", "", "Сцена: `%s`" % os.path.basename(src), "",
             "| материал | объектов | было | тип | стало | ΔE |", "| --- | --- | --- | --- | --- | --- |"]
    for r in sorted((r for r in rows if "to" in r), key=lambda r: -r["de"]):
        lines.append("| %s | %d | %s | %s (%s) | `%s` | %.1f |"
                     % (r["name"], r["n"], r["src"], r["kind"], r["why"], r["to"], r["de"]))
    lines += ["", "## Материалы с картинкой (цвет по граням)", ""]
    lines += ["- **%s** (объектов %d): %s" % (r["name"], r["n"], r["note"]) for r in img_rows]
    lines += ["", "## Не тронуты", ""]
    lines += ["- **%s** (объектов %d): %s" % (r["name"], r["n"], r["note"])
              for r in rows if "to" not in r]
    with open(report, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    converted = [r for r in rows if "to" in r]
    warn = [r for r in converted if r["de"] > DELTA_WARN or r["why"] == "угадано"]
    print("[adopt] прежних pal_ к переименованию: %d" % legacy)
    print("[adopt] перевести целиком: %d материалов (%d из них уже в cel-шейдинге)"
          % (len(converted), sum(1 for r in converted if r["cel"])))
    print("[adopt] перевести по граням (картинки): %d материалов, граней-планов %d"
          % (len(images), len(face_plans)))
    print("[adopt] проверить глазами: %d (сдвиг цвета ΔE00 больше %.0f или тип угадан)"
          % (len(warn), DELTA_WARN))
    for r in sorted(warn, key=lambda r: -r["de"])[:25]:
        print("   %-30s %2d об. %s %s(%s) -> %-26s ΔE %.1f"
              % (r["name"][:30], r["n"], r["src"], r["kind"], r["why"], r["to"], r["de"]))
    for r in converted:
        if r["kind"] == "glow":
            print("   СВЕТ %-28s %2d об. %s -> %-26s" % (r["name"][:28], r["n"], r["src"], r["to"]))
    for r in img_rows:
        print("   ИМГ %-28s %2d об.: %s" % (r["name"][:28], r["n"], r["note"]))
    print("[adopt] отчёт: %s" % report)
    if dry:
        print("[adopt] проба: ничего не записано")
        return

    # --- 4. применить ---
    new_mats = {}
    for name, (mat, kind, color) in plain.items():
        new_mats[name] = get_pal(kind, color)
    for mat, setter, _ in material_refs():
        if mat.name in new_mats:
            setter(new_mats[mat.name])

    for me, slot_index, sel, ids, kind, old in face_plans:
        uniq = list(dict.fromkeys(ids))
        mats = {c: get_pal(kind, c) for c in uniq}
        me.materials[slot_index] = mats[uniq[0]]          # старый слот занимает первый цвет
        index_of = {uniq[0]: slot_index}
        for c in uniq[1:]:
            me.materials.append(mats[c])
            index_of[c] = len(me.materials) - 1
        n = len(me.polygons)
        midx = np.empty(n, dtype=np.int32)
        me.polygons.foreach_get("material_index", midx)
        for face, c in zip(sel, ids):
            midx[face] = index_of[c]
        me.polygons.foreach_set("material_index", midx)
        me.update()

    # --- 5. чистка ---
    removed_m = removed_i = removed_g = 0
    merged = 0
    # Двойники вида pal_plastic_black.001: после перестройки они идентичны основному
    # материалу (цвет и тип берутся из имени), так что сливаем их — иначе в сцене копятся
    # одинаковые материалы с разными именами
    for m in list(bpy.data.materials):
        base = re.sub(r"\.\d{3}$", "", m.name)
        if m.library is None and base != m.name and m.name.startswith("pal_"):
            twin = bpy.data.materials.get(base)
            if twin is not None and twin.library is None and P.parse_name(base):
                for mat, setter, _ in material_refs():
                    if mat is m:
                        setter(twin)
                bpy.data.materials.remove(m)
                merged += 1
    if purge:
        live = {m.name for m, _, _ in material_refs()}
        for m in list(bpy.data.materials):
            if m.library is None and not m.name.startswith("pal_") and m.name not in live \
                    and not kept(m.name):
                bpy.data.materials.remove(m)
                removed_m += 1
        for g in list(bpy.data.node_groups):
            if g.users == 0 or (g.users == 1 and g.use_fake_user):
                bpy.data.node_groups.remove(g)
                removed_g += 1
        used_images = set()
        trees = [m.node_tree for m in bpy.data.materials if m.node_tree]
        trees += [w.node_tree for w in bpy.data.worlds if w.node_tree]
        trees += list(bpy.data.node_groups)
        for t in trees:
            for n in t.nodes:
                if n.type in ("TEX_IMAGE", "TEX_ENVIRONMENT") and n.image:
                    used_images.add(n.image.name)
        for img in list(bpy.data.images):
            if img.type in ("IMAGE", "UV_TEST") and img.name not in used_images \
                    and img.users <= (1 if img.use_fake_user else 0):
                bpy.data.images.remove(img)
                removed_i += 1

    for sc in bpy.data.scenes:
        B.flat_color(sc)

    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    kb = os.path.getsize(out) / 1024.0
    pal_now = sum(1 for m in bpy.data.materials if m.name.startswith("pal_"))
    other_now = sum(1 for m in bpy.data.materials if not m.name.startswith("pal_"))
    print("[adopt] удалено: материалов %d, картинок %d, узловых групп %d; слито двойников %d"
          % (removed_m, removed_i, removed_g, merged))
    print("[adopt] в сцене теперь: pal_ %d, прочих %d | вид Standard | файл %.0f КБ"
          % (pal_now, other_now, kb))
    print("[adopt] сохранено: %s" % out)


main()
