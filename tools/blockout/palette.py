"""Палитра игры: цвета и материалы — две независимые оси.

Раньше палитра была свалена по назначению: «стены комнаты героя», «акценты», «ткань».
Это путало: нейтральный серый нужен и пластику, и металлу, и ткани, а ДСП бывает любого
цвета. Теперь так:

    ЦВЕТ (59 штук, по семействам) × МАТЕРИАЛ (8 типов) = то, что можно взять

Цвет — это только оттенок. Материал (cel_shader.MATERIALS) — то, как поверхность ведёт
себя со светом: ступени, блик, фактура. Один красный на бумаге и на металле — один цвет,
два вида. Комнаты в палитру не входят: ROOMS ниже — подсказка, не набор материалов.

Имя материала: pal_<материал>_<цвет>, например pal_plastic_red_vivid. Материал идёт
первым, чтобы поиск `pal_plastic` в Blender сразу показал весь пластик.

Цвета в sRGB (#rrggbb) — так их видно глазом и так их правит человек. Blender работает
в линейном пространстве, перевод делает srgb().

Правила подбора (docs/art/blender-scenes.md):
- насыщенность низкая, светлота высокая — пастель; чистые яркие (`vivid`) только для
  мелочи размером с ладонь: карандаши, кнопки, провода;
- тень считает шейдер, а не палитра: холоднее цвета, а не просто темнее.
"""

import re

# --- Цвета по семействам --------------------------------------------------
# Тона внутри семейства: light — светлый, mid — основной, dark — тёмный,
# deep — самый тёмный, vivid — чистый яркий (только для мелочи).
# Нейтрали идут без префикса семейства: black, graphite, grey, silver, snow, cream.
FAMILIES = {
    "neutral": {   # от почти чёрного к светлому — общие для всех материалов
        "black":    "#1C1E23",   # системный блок, выключенный экран
        "graphite": "#4B4F58",
        "grey":     "#8D929B",
        "silver":   "#C7CBD2",
        "snow":     "#E6EAEF",   # сантехника, холодный белый
        "cream":    "#F2EDE4",   # потолок, бумага, тёплый белый
    },
    "steel":   {"light": "#BEC5CC", "mid": "#6E7B88", "dark": "#4B5560"},
    "brown":   {"light": "#D8B98E", "mid": "#B2875A", "dark": "#8A6248", "deep": "#6B4A32"},
    "sand":    {"light": "#EDE3D2", "mid": "#D6C3A5", "dark": "#C9A98A"},
    "red":     {"light": "#E3A8A0", "mid": "#C25B52", "dark": "#8C4A4A", "vivid": "#D8453C"},
    "orange":  {"light": "#EBC09A", "mid": "#D4824A", "dark": "#A8674F", "vivid": "#E87B2E"},
    "yellow":  {"light": "#F0DC9F", "mid": "#E0B255", "dark": "#B8913F", "vivid": "#F0C330"},
    "lime":    {"light": "#C5D69A", "mid": "#9BB356", "dark": "#6B8A3A", "vivid": "#86C040"},
    "green":   {"light": "#9DB0A6", "mid": "#6E9E6A", "dark": "#466A4A", "vivid": "#3E9E5C"},
    "olive":   {"light": "#B7BA9A", "mid": "#8A8F6B", "dark": "#5F6347"},
    "teal":    {"light": "#BDD8D3", "mid": "#4FA3A3", "dark": "#2F6F73", "vivid": "#3FB3C4"},
    "blue":    {"light": "#A9BDD9", "mid": "#5E7C9E", "dark": "#46587A", "deep": "#2E3A55",
                "vivid": "#3A72C4"},
    "violet":  {"light": "#BDB2D6", "mid": "#8A7BB0", "dark": "#5E4F86", "vivid": "#7C5BC0"},
    "pink":    {"light": "#DDB4C0", "mid": "#D98FA6", "dark": "#8A6B80", "vivid": "#E86E92"},
    "magenta": {"light": "#E6B0D0", "dark": "#8C3A70", "vivid": "#C8479B"},
}

# Подписи для каталогов в Blender (Asset Browser) и для листов
FAMILY_TITLE = {
    "neutral": "Нейтрали", "steel": "Сталь", "brown": "Коричневый", "sand": "Песочный",
    "red": "Красный", "orange": "Оранжевый", "yellow": "Жёлтый", "lime": "Салатовый",
    "green": "Зелёный", "olive": "Оливковый", "teal": "Бирюзовый", "blue": "Синий",
    "violet": "Фиолетовый", "pink": "Розовый", "magenta": "Малиновый",
}
TONE_TITLE = {"light": "светлый", "mid": "средний", "dark": "тёмный", "deep": "глубокий",
              "vivid": "яркий"}

# --- Материалы ------------------------------------------------------------
# Профили (ступени, блик, фактура) живут в cel_shader.MATERIALS. Здесь — порядок
# и подписи; какие цвета на каких материалах бывают — ниже
KIND_ORDER = ("wall", "paper", "fabric", "wood", "plastic", "metal", "glass", "plant", "glow")
KIND_TITLE = {
    "wall": "Стена (матовая краска)", "paper": "Бумага", "fabric": "Ткань",
    "wood": "Дерево и ДСП", "plastic": "Пластик", "metal": "Металл",
    "glass": "Стекло", "plant": "Растения", "glow": "Свечение",
}

# Любой цвет годится на любой из этих материалов: ДСП бывает любого цвета,
# крашеный металл и цветной пластик тоже
FREE_KINDS = ("wall", "paper", "fabric", "wood", "plastic", "metal")

# Стекло и растения ограничены: красное оконное стекло и бирюзовые листья — не то,
# что понадобится в квартире. Стекло — нейтрали и лёгкие холодные оттенки, растения —
# зелёные, салатовые, оливковые и коричневый для ствола и горшка
GLASS_COLORS = {"black", "graphite", "grey", "silver", "snow", "cream", "teal_light",
                "teal_mid", "blue_light", "green_light", "brown_mid", "violet_light"}
PLANT_FAMILIES = ("green", "lime", "olive")
PLANT_EXTRA = {"brown_mid", "brown_dark"}

# Свечение — светодиоды, лампочки, индикаторы. Годятся чистые яркие тона (`vivid`) и
# несколько светлых для тёплой лампы и холодного отсвета: цвет горящего света редко
# бывает тёмным или грязным
GLOW_EXTRA = {"snow", "cream", "yellow_light", "orange_light", "teal_light", "blue_light"}


def _build():
    colors, family_of = {}, {}
    for fam, tones in FAMILIES.items():
        for tone, hexcol in tones.items():
            cid = tone if fam == "neutral" else "%s_%s" % (fam, tone)
            colors[cid] = hexcol
            family_of[cid] = fam
    return colors, family_of


COLORS, FAMILY_OF = _build()


def tone_of(color):
    """Тон цвета: 'mid' у red_mid; у нейтралей — их собственное имя."""
    fam = FAMILY_OF[color]
    return color if fam == "neutral" else color[len(fam) + 1:]


def kinds_for(color):
    """На каких материалах бывает этот цвет."""
    kinds = list(FREE_KINDS)
    if color in GLASS_COLORS:
        kinds.append("glass")
    if FAMILY_OF[color] in PLANT_FAMILIES or color in PLANT_EXTRA:
        kinds.append("plant")
    if tone_of(color) == "vivid" or color in GLOW_EXTRA:
        kinds.append("glow")
    return tuple(k for k in KIND_ORDER if k in kinds)


def mat_name(kind, color):
    """Имя материала: материал первым — поиск `pal_plastic` показывает весь пластик."""
    return "pal_%s_%s" % (kind, color)


def all_colors():
    """Все цвета: id -> #hex."""
    return dict(COLORS)


def all_materials():
    """Все материалы, которые собирает библиотека: список словарей."""
    out = []
    for kind in KIND_ORDER:
        for color, hexcol in COLORS.items():
            if kind in kinds_for(color):
                out.append({"name": mat_name(kind, color), "kind": kind, "color": color,
                            "hex": hexcol, "family": FAMILY_OF[color]})
    return out


# --- Комнаты: подсказка, а не палитра ------------------------------------
# Какие цвета разумно взять на комнату. Это рекомендация для расстановки: материалы
# стен и пола берутся из общей палитры так же, как всё остальное
ROOMS = {
    "hero":     {"wall": "blue_dark", "floor": "graphite", "accent": "teal_mid"},
    "mate":     {"wall": "pink_light", "floor": "sand_dark", "accent": "red_mid"},
    "living":   {"wall": "green_light", "floor": "brown_mid", "accent": "yellow_mid"},
    "kitchen":  {"wall": "sand_light", "floor": "silver", "accent": "lime_light"},
    "bath":     {"wall": "teal_light", "floor": "snow", "accent": "lime_light"},
    "wc":       {"wall": "green_light", "floor": "snow", "accent": "grey"},
    "corridor": {"wall": "sand_mid", "floor": "brown_mid", "accent": "brown_deep"},
    "hall":     {"wall": "sand_mid", "floor": "grey", "accent": "brown_deep"},
}

# --- Прежние имена --------------------------------------------------------
# Старая палитра называлась pal_<группа>_<цвет>_<материал>. Сцены разработчика уже
# содержат такие материалы на реальных объектах, поэтому они не должны отвалиться:
# refresh_palette.py находит старое имя здесь и переименовывает в новое.
# Ключ — то, что стояло между «pal_» и «_<материал>».
LEGACY = {
    # нейтрали
    "neutral_black_tech": "black", "neutral_grey_dark": "graphite", "neutral_grey_mid": "grey",
    "neutral_grey_light": "silver", "neutral_white_cool": "snow", "neutral_white_warm": "cream",
    # дерево и металл
    "wood_wood_light": "brown_light", "wood_wood_mid": "brown_mid", "wood_wood_dark": "brown_deep",
    "metal_metal_light": "steel_light", "metal_metal_dark": "steel_mid",
    # акценты
    "accent_red": "red_mid", "accent_yellow": "yellow_mid", "accent_green": "green_mid",
    "accent_teal": "teal_mid", "accent_violet": "violet_mid", "accent_pink": "pink_mid",
    "accent_orange": "orange_mid", "accent_blue": "blue_mid", "accent_lime": "lime_mid",
    "accent_brown": "brown_dark",
    # яркие
    "bright_red": "red_vivid", "bright_orange": "orange_vivid", "bright_yellow": "yellow_vivid",
    "bright_lime": "lime_vivid", "bright_green": "green_vivid", "bright_cyan": "teal_vivid",
    "bright_blue": "blue_vivid", "bright_violet": "violet_vivid", "bright_magenta": "magenta_vivid",
    "bright_pink": "pink_vivid",
    # ткань
    "fabric_cream": "sand_light", "fabric_blue": "blue_mid", "fabric_olive": "olive_mid",
    "fabric_rust": "orange_dark", "fabric_sand": "sand_mid", "fabric_sage": "green_light",
    "fabric_plum": "pink_dark", "fabric_mustard": "yellow_dark", "fabric_slate": "steel_mid",
    "fabric_wine": "red_dark",
    # стены и полы комнат
    "room.hero_wall": "blue_dark", "room.hero_floor": "graphite", "room.hero_accent": "teal_mid",
    "room.mate_wall": "pink_light", "room.mate_floor": "sand_dark", "room.mate_accent": "red_mid",
    "room.living_wall": "green_light", "room.living_floor": "brown_mid",
    "room.living_accent": "yellow_mid",
    "room.kitchen_wall": "sand_light", "room.kitchen_floor": "silver",
    "room.kitchen_accent": "lime_light",
    "room.bath_wall": "teal_light", "room.bath_floor": "snow", "room.bath_accent": "lime_light",
    "room.wc_wall": "green_light", "room.wc_floor": "snow", "room.wc_accent": "grey",
    "room.corridor_wall": "sand_mid", "room.corridor_floor": "brown_mid",
    "room.corridor_accent": "brown_deep",
    "room.hall_wall": "sand_mid", "room.hall_floor": "grey", "room.hall_accent": "brown_deep",
}


def parse_name(name):
    """Разобрать имя материала: (материал, цвет, старое_ли_имя) или None.

    Понимает и новый вид pal_plastic_red_vivid, и прежний pal_neutral_black_tech_plastic.
    Суффикс дубля .001 отбрасывается.
    """
    base = re.sub(r"\.\d{3}$", "", name)
    if not base.startswith("pal_"):
        return None
    rest = base[4:]
    for kind in KIND_ORDER:
        if rest.startswith(kind + "_"):
            color = rest[len(kind) + 1:]
            if color in COLORS:
                return kind, color, False
    for kind in KIND_ORDER:
        if rest.endswith("_" + kind):
            key = rest[:-len(kind) - 1]
            if key in LEGACY:
                return kind, LEGACY[key], True
    return None


# --- Свет -----------------------------------------------------------------
# Время суток задаётся не цветом стен, а светом: цвет источника, цвет общей
# заливки и её сила. Планировка при этом не меняется — в этом весь смысл сцены
PHASE = {
    "morning": {"key": "#FFE2CC", "fill": "#8FA3C4", "fill_power": 0.60, "key_power": 700.0},
    "day":     {"key": "#FFF6E8", "fill": "#9FB0C8", "fill_power": 0.55, "key_power": 900.0},
    "evening": {"key": "#FFBE86", "fill": "#7A6E8A", "fill_power": 0.35, "key_power": 520.0},
    # ночью «окно» — это уличный фонарь и луна: холодно и слабо
    "night":   {"key": "#5C78B0", "fill": "#2E3650", "fill_power": 0.16, "key_power": 60.0},
}

# Искусственный свет: он же источник настроения ночью и акцент днём
LAMP = {
    "desk_warm":   {"color": "#FFD9A0", "power": 60.0},
    "ceiling":     {"color": "#FFF0D8", "power": 120.0},
    "monitor":     {"color": "#9FD8FF", "power": 28.0},
    "led_red":     {"color": "#FF5A4A", "power": 4.0},
    "led_blue":    {"color": "#4AC8FF", "power": 4.0},
    "street_cold": {"color": "#A8C4FF", "power": 90.0},
}


def srgb(hexcol):
    """#rrggbb -> линейный RGB. Blender считает свет в линейном пространстве,
    а палитру человек правит в sRGB — иначе цвета выходят темнее задуманного."""
    h = hexcol.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)
