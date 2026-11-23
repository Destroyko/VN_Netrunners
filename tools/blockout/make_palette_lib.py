"""Библиотека материалов: палитра как каталог ассетов Blender.

Зачем не просто .blend с материалами. Выпадающий список материалов в Blender показывает
только то, что уже лежит в текущем файле: подключили два пластика — видите два. Чтобы
брать из всей палитры, материалы нужны в **браузере ассетов**: там они лежат плиткой
с цветными превью, разложены по каталогам «материал → семейство цвета», и берутся
перетаскиванием на объект. В сцену при этом попадает только то, что взяли.

Что собирает скрипт (папка assets/_source/palette_library/):
- palette_materials.blend — материалы, помеченные как ассеты, с превью и тегами;
- blender_assets.cats.txt — каталоги: Пластик / Красный, Металл / Синий и так далее.

    & "...blender.exe" -b --python tools\\blockout\\make_palette_lib.py

Один раз в Blender: Edit -> Preferences -> File Paths -> Asset Libraries -> «+» и указать
папку assets/_source/palette_library. Дальше — окно Asset Browser (рабочее пространство
Shading или любое окно, переключённое на Asset Browser), библиотека «VN Palette».

Повторный запуск перезаписывает всё целиком: источник истины — palette.py.
"""

import os
import sys
import uuid

import bpy

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import cel_shader as C  # noqa: E402
import palette as P  # noqa: E402
import swatch as S  # noqa: E402

LIB_DIR = "assets/_source/palette_library"
LIB_FILE = "palette_materials.blend"
CATS_FILE = "blender_assets.cats.txt"
PREVIEW = 96

_NS = uuid.UUID("5f3a1c3e-0b9e-4d1e-9a6e-2c7a1d4b8e10")


def catalog_id(path):
    """Стабильный идентификатор каталога: при пересборке не меняется, и назначения живут."""
    return str(uuid.uuid5(_NS, path))


def catalog_paths():
    """Все каталоги: материал и под ним семейства цвета, которые на нём бывают."""
    paths = {}
    for kind in P.KIND_ORDER:
        paths[P.KIND_TITLE[kind]] = None
        fams = []
        for color in P.COLORS:
            if kind in P.kinds_for(color) and P.FAMILY_OF[color] not in fams:
                fams.append(P.FAMILY_OF[color])
        for fam in fams:
            paths["%s/%s" % (P.KIND_TITLE[kind], P.FAMILY_TITLE[fam])] = None
    return list(paths)


def write_catalogs(folder):
    """blender_assets.cats.txt: формат — UUID:путь/каталога:краткое имя."""
    lines = [
        "# This is an Asset Catalog Definition file for Blender.",
        "#",
        "# Empty lines and lines starting with `#` will be ignored.",
        "# The first non-ignored line should be the version indicator.",
        '# Other lines are of the format "UUID:catalog/path/for/assets:simple catalog name"',
        "",
        "VERSION 1",
        "",
    ]
    for path in catalog_paths():
        lines.append("%s:%s:%s" % (catalog_id(path), path, path.replace("/", "-")))
    with open(os.path.join(folder, CATS_FILE), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    return len(catalog_paths())


def cel_material(spec):
    """Один материал палитры: цвет плюс тип поверхности.

    Шейдер собирает cel_shader — он же в style_cel.py, чтобы вид материала
    в окне Blender совпадал с видом в рендере. Ступени, фактуру и блик задаёт
    профиль типа, а не отдельные числа на каждый материал.
    """
    mat = bpy.data.materials.new(spec["name"])
    mat.use_nodes = True
    light = C.build(mat.node_tree, P.srgb(spec["hex"]), None, None, None, None, spec["kind"])
    # Цвет в режиме Solid — чтобы сцена читалась и без рендера
    mat.diffuse_color = (*light, 1.0)
    return mat


def make_asset(mat, spec):
    """Пометить материал как ассет: каталог, теги, описание и превью."""
    mat.asset_mark()
    data = mat.asset_data
    path = "%s/%s" % (P.KIND_TITLE[spec["kind"]], P.FAMILY_TITLE[spec["family"]])
    data.catalog_id = catalog_id(path)
    try:
        data.catalog_simple_name = path.replace("/", "-")
    except Exception:
        pass
    tone = P.tone_of(spec["color"])
    data.description = "%s · %s, %s · %s" % (
        P.KIND_TITLE[spec["kind"]], P.FAMILY_TITLE[spec["family"]].lower(),
        P.TONE_TITLE.get(tone, tone), spec["hex"])
    # теги дают поиск поперёк каталогов: «red» найдёт красное на всех материалах
    for tag in (spec["kind"], spec["family"], tone):
        data.tags.new(tag, skip_if_exists=True)


def set_preview(mat, spec):
    """Положить в превью шарик с теми же ступенями и бликом, что у шейдера."""
    arr = S.sphere(P.srgb(spec["hex"]), spec["kind"], PREVIEW)
    arr = arr[::-1]                               # у Blender строки идут снизу вверх
    pv = mat.preview_ensure()
    pv.image_size = (PREVIEW, PREVIEW)
    pv.image_pixels_float.foreach_set(arr.reshape(-1).tolist())


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.engine = "BLENDER_EEVEE"

    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    folder = os.path.normpath(os.path.join(root, LIB_DIR))
    os.makedirs(folder, exist_ok=True)

    specs = P.all_materials()
    previews = failed = 0
    for spec in specs:
        mat = cel_material(spec)
        make_asset(mat, spec)
        try:
            set_preview(mat, spec)
            previews += 1
        except Exception as exc:            # превью — украшение, сборка важнее
            failed += 1
            if failed == 1:
                print("[palette] превью не записалось: %s" % exc)

    cats = write_catalogs(folder)
    path = os.path.join(folder, LIB_FILE)
    # compress: образцы — плоские заливки и жмутся почти в ничто
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    kb = os.path.getsize(path) / 1024.0
    print("[palette] материалов: %d, превью: %d, каталогов: %d, файл %.0f КБ"
          % (len(specs), previews, cats, kb))
    print("[palette] -> %s" % folder)


main()
