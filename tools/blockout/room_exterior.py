"""Вид из окна героя: ряды многоэтажек через дорогу, небо и земля, по фазам суток.

    & "...blender.exe" -b assets\\_source\\blockout\\apartment_lit.blend ^
        --python tools\\blockout\\room_exterior.py [-- --seed 11 --dry --rebuild]

Компас сцены: окна квартиры героя смотрят на юг (солнечная сторона). Ось +Y сцены — юг,
+X — запад. Солнце днём и на закате приходит из-за домов напротив (room_frames, ключ `sun`).

Сцена. Квартира на 7-м этаже: пол комнаты z = 0, земля z = -17 (6 этажей по 2,8 м). Напротив
через двор и дорогу идут ряды домов; чем дальше ряд, тем он выше и тем сильнее скрыт дымкой:

    front — панельные пяти-девятиэтажки в 40 м от фасада: их крыши ниже и выше глаза героя;
    mid   — девять-шестнадцать этажей;
    far1, far2 — высотки на горизонте, почти силуэты.

Дома — простые коробки с общим материалом `ext_facade`: окна считаются шейдером по мировым
координатам (одна клетка = секция 3 м × этаж 2,8 м), поэтому геометрии почти нет и окна на
соседних корпусах сходятся по сетке. Свет в окнах, цвет фасадов, дымка и небо меняются по
фазе (`EXT_PHASES`, `apply_phase`). Всё в коллекции `exterior`: скрипт пересоздаёт её целиком.

Материалы излучают сами и не берут свет сцены, объекты не отбрасывают тень (иначе дома на юге
гасили бы солнце в комнате). Положение и высоты рядов — таблица ROWS; слева по x — запад.
"""

import math
import os
import random
import sys

import bpy
import bmesh

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

COLLECTION = "exterior"
GROUND_Z = -17.0            # земля под окнами (7-й этаж, 6 × 2,8 м)
WALL_Y = 7.55               # внешняя грань фасада дома героя
FLOOR_H = 2.8               # этаж панельного дома
BAY_W = 3.0                 # секция по ширине (окно + простенок)
CLIP_END = 4000.0           # дальняя плоскость камер: небо стоит далеко

# Ряды домов: имя, расстояние от фасада до ближнего торца (м), глубина корпуса, этажи (от, до),
# длина секции (от, до), разрыв между домами (от, до), диапазон по x. fixed — дома, поставленные
# вручную (x от, x до, этажи): они лежат в зоне обзора окна героя (x примерно 0–40), чтобы кадр
# собирался из слоёв: низкий дом спереди, разрыв, средний ряд, силуэт высотки сзади
ROWS = [
    {"name": "front", "y": 40.0, "depth": 12.0, "floors": (5, 9),   "len": (40, 70), "gap": (7, 15),  "x": (-260, 300),
     "fixed": [(-70, 8, 5), (20, 80, 9)]},
    {"name": "mid",   "y": 95.0, "depth": 14.0, "floors": (9, 16),  "len": (50, 90), "gap": (14, 30), "x": (-500, 600),
     "fixed": [(-100, 10, 11), (30, 120, 14)]},
    {"name": "far1",  "y": 170.0, "depth": 18.0, "floors": (14, 24), "len": (28, 60), "gap": (20, 45), "x": (-800, 900),
     "fixed": [(-5, 45, 22)]},
    {"name": "far2",  "y": 300.0, "depth": 20.0, "floors": (18, 30), "len": (30, 70), "gap": (25, 60), "x": (-1300, 1400)},
]

# Фасады: четыре тёмных графитовых цвета панелей с лёгким оттенком (при дневном свете),
# выбираются случайно на корпус. Светло-серые дома за окном выглядели стерильно
FACADE_COLORS = [(0.46, 0.44, 0.41), (0.40, 0.43, 0.47), (0.47, 0.41, 0.39), (0.42, 0.44, 0.43)]
ROAD_Z = GROUND_Z + 0.02

# Параметры по фазам. tone — множитель цвета всего, что освещено небом (фасад обращён к нам
# и в тени, поэтому темнее крыш); roof_k — на сколько крыши светлее фасадов; haze — цвет
# дымки, haze_dist — расстояние, на котором она набирает силу (м), haze_max — потолок;
# glass — цвет тёмного стекла; p_lit — доля окон со светом; lit_k — яркость света в окнах;
# sky_h и sky_z — небо у горизонта и в зените; lamp — яркость уличных фонарей
EXT_PHASES = {
    "day": {
        "tone": (0.86, 0.88, 0.92), "roof_k": 1.18,
        "haze": (0.76, 0.83, 0.93), "haze_dist": 380.0, "haze_max": 0.85,
        "glass": (0.30, 0.40, 0.52), "p_lit": 0.0, "lit_k": 0.0,
        "sky_h": (0.82, 0.88, 0.95), "sky_z": (0.42, 0.60, 0.88), "lamp": 0.0,
    },
    "evening": {
        "tone": (0.36, 0.30, 0.38), "roof_k": 2.0,
        "haze": (0.92, 0.50, 0.34), "haze_dist": 230.0, "haze_max": 0.85,
        "glass": (0.38, 0.26, 0.30), "p_lit": 0.14, "lit_k": 0.9,
        "sky_h": (0.98, 0.58, 0.36), "sky_z": (0.22, 0.26, 0.52), "lamp": 0.35,
    },
    "night": {
        "tone": (0.075, 0.095, 0.19), "roof_k": 1.0,
        "haze": (0.13, 0.15, 0.30), "haze_dist": 300.0, "haze_max": 0.80,
        "glass": (0.03, 0.04, 0.085), "p_lit": 0.30, "lit_k": 1.0,
        "sky_h": (0.17, 0.19, 0.36), "sky_z": (0.012, 0.018, 0.07), "lamp": 1.0,
    },
}


# ---------- узлы -------------------------------------------------------------------

class G:
    """Помощник сборки графа: каждая операция сама ставит узел и сшивает входы."""

    def __init__(self, nt):
        self.nt = nt
        self.x = -1600
        self.row = 0

    def _loc(self, node):
        self.x += 180
        self.row = (self.row + 1) % 6
        node.location = (self.x, -self.row * 160)

    def _feed(self, node, values):
        for i, v in enumerate(values):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                node.inputs[i].default_value = v
            else:
                self.nt.links.new(v, node.inputs[i])

    def math(self, op, a=None, b=None, clamp=False):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        self._loc(n)
        self._feed(n, (a, b))
        return n.outputs[0]

    def value(self, label, v=0.0):
        n = self.nt.nodes.new("ShaderNodeValue")
        n.label = n.name = label
        n.outputs[0].default_value = v
        self._loc(n)
        return n.outputs[0]

    def rgb(self, label, c):
        n = self.nt.nodes.new("ShaderNodeRGB")
        n.label = n.name = label
        n.outputs[0].default_value = (*c, 1.0)
        self._loc(n)
        return n.outputs[0]

    def mix(self, fac, a, b, blend="MIX"):
        n = self.nt.nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        n.blend_type = blend
        self._loc(n)
        self._feed(n, (fac,))
        for idx, v in ((6, a), (7, b)):
            if isinstance(v, tuple):
                n.inputs[idx].default_value = (*v, 1.0) if len(v) == 3 else v
            else:
                self.nt.links.new(v, n.inputs[idx])
        return n.outputs[2]

    def scale(self, vec, k):
        n = self.nt.nodes.new("ShaderNodeVectorMath")
        n.operation = "SCALE"
        self._loc(n)
        self.nt.links.new(vec, n.inputs[0])
        self.nt.links.new(k, n.inputs["Scale"]) if not isinstance(k, (int, float)) else \
            setattr(n.inputs["Scale"], "default_value", k)
        return n.outputs[0]

    def sep(self, vec):
        n = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self._loc(n)
        self.nt.links.new(vec, n.inputs[0])
        return n.outputs["X"], n.outputs["Y"], n.outputs["Z"]

    def combine(self, x=None, y=None, z=None):
        n = self.nt.nodes.new("ShaderNodeCombineXYZ")
        self._loc(n)
        for name, v in (("X", x), ("Y", y), ("Z", z)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[name].default_value = v
            else:
                self.nt.links.new(v, n.inputs[name])
        return n.outputs[0]

    def noise(self, vec, w):
        n = self.nt.nodes.new("ShaderNodeTexWhiteNoise")
        n.noise_dimensions = "4D"
        self._loc(n)
        self.nt.links.new(vec, n.inputs["Vector"])
        self.nt.links.new(w, n.inputs["W"])
        return n.outputs["Value"]

    def ramp(self, fac, stops, interp="CONSTANT"):
        n = self.nt.nodes.new("ShaderNodeValToRGB")
        n.color_ramp.interpolation = interp
        self._loc(n)
        els = n.color_ramp.elements
        els[0].position = stops[0][0]
        els[1].position = stops[1][0]
        for pos, _ in stops[2:]:                # новые точки встают по порядку позиций
            els.new(pos)
        for el, (_, col) in zip(els, stops):
            el.color = (*col, 1.0)
        self.nt.links.new(fac, n.inputs["Fac"])
        return n.outputs["Color"]

    def geometry(self):
        n = self.nt.nodes.new("ShaderNodeNewGeometry")
        self._loc(n)
        return n.outputs["Position"], n.outputs["Normal"]

    def object_random(self):
        n = self.nt.nodes.new("ShaderNodeObjectInfo")
        self._loc(n)
        return n.outputs["Random"]

    def finish(self, colour):
        em = self.nt.nodes.new("ShaderNodeEmission")
        self._loc(em)
        self.nt.links.new(colour, em.inputs["Color"])
        out = self.nt.nodes.new("ShaderNodeOutputMaterial")
        out.location = (self.x + 200, 0)
        self.nt.links.new(em.outputs[0], out.inputs["Surface"])


def _new_material(name):
    # материал переиспользуется на месте: объекты, которым его назначили руками, не теряют слот
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.node_tree.nodes.clear()
    return mat


def _haze(g, colour):
    """Дымка: цвет уходит в цвет неба тем сильнее, чем дальше от камеры (глубина вида)."""
    n = g.nt.nodes.new("ShaderNodeCameraData")
    g._loc(n)
    depth = n.outputs["View Z Depth"]
    k = g.math("DIVIDE", depth, g.value("haze_dist", 300.0))
    e = g.math("EXPONENT", g.math("MULTIPLY", k, -1.0))
    fall = g.math("SUBTRACT", 1.0, e)
    fac = g.math("MULTIPLY", fall, g.value("haze_max", 0.8), clamp=True)
    return g.mix(fac, colour, g.rgb("haze", (0.5, 0.5, 0.6)))


def make_facade(name="ext_facade", windows=True):
    """Панельный дом: сетка 3 м по мировым координатам, секции из шести колонок (лестница,
    комнаты, кухни, лоджия), рамы и подоконники, свет в части окон, дымка. windows=False —
    те же стены без окон: надстройки на крыше (выход на кровлю, машинное отделение)."""
    mat = _new_material(name)
    g = G(mat.node_tree)
    gt = lambda a, b: g.math("GREATER_THAN", a, b)
    lt = lambda a, b: g.math("LESS_THAN", a, b)
    mul = lambda a, b: g.math("MULTIPLY", a, b)
    add = lambda a, b: g.math("ADD", a, b)
    sub = lambda a, b: g.math("SUBTRACT", a, b)
    div = lambda a, b: g.math("DIVIDE", a, b)
    absv = lambda a: g.math("ABSOLUTE", a)
    clamp01 = lambda a: g.math("ADD", a, 0.0, clamp=True)

    pos, nrm = g.geometry()
    px, py, pz = g.sep(pos)
    nx, ny, nz = g.sep(nrm)
    absnx, absnz = absv(nx), absv(nz)
    side = gt(absnx, 0.5)                              # торцевая стена
    vert = lt(absnz, 0.5)                              # вертикальная грань: не крыша
    # горизонталь вдоль фасада: x для стен, обращённых к нам, y для торцов
    hx = add(px, mul(side, sub(py, px)))
    u = div(hx, BAY_W)
    v = div(sub(pz, GROUND_Z), FLOOR_H)
    iu, fu = g.math("FLOOR", u), g.math("FRACT", u)
    iv, fv = g.math("FLOOR", v), g.math("FRACT", v)
    tone = g.rgb("tone", (1.0, 1.0, 1.0))
    tint = lambda c: g.mix(1.0, c, tone, blend="MULTIPLY")

    # стены: цвет корпуса, швы панелей, тёмный цоколь, тон фазы; крыши светлее
    rnd = g.object_random()
    base = g.ramp(rnd, [(0.0, FACADE_COLORS[0]), (0.25, FACADE_COLORS[1]),
                        (0.50, FACADE_COLORS[2]), (0.75, FACADE_COLORS[3])])
    seam = g.math("ADD", lt(fv, 0.03), lt(fu, 0.015), clamp=True)
    plinth = mul(lt(iv, 0.5), lt(fv, 0.20))
    wall_k = mul(sub(1.0, mul(seam, 0.12)), sub(1.0, mul(plinth, 0.28)))
    wall = tint(g.scale(base, wall_k))
    roof_k = add(1.0, mul(gt(nz, 0.5), sub(g.value("roof_k", 1.0), 1.0)))
    wall = g.scale(wall, roof_k)
    if not windows:
        g.finish(_haze(g, wall))
        return mat

    # колонка секции: ширина окна (доля клетки), низ и верх окна (доли этажа), сдвиг по высоте
    # (лестничное окно стоит на межэтажной площадке), перемычки (0, 1 или 2), флаги лестницы и лоджии
    cols = [
        dict(w=0.30, v0=0.25, v1=0.85, shift=0.5, mull=0, stair=1, loggia=0),   # лестница
        dict(w=0.64, v0=0.30, v1=0.80, shift=0.0, mull=1, stair=0, loggia=0),   # комната
        dict(w=0.42, v0=0.34, v1=0.80, shift=0.0, mull=0, stair=0, loggia=0),   # кухня
        dict(w=0.86, v0=0.10, v1=0.84, shift=0.0, mull=2, stair=0, loggia=1),   # лоджия
        dict(w=0.64, v0=0.30, v1=0.80, shift=0.0, mull=1, stair=0, loggia=0),   # комната
        dict(w=0.42, v0=0.34, v1=0.80, shift=0.0, mull=0, stair=0, loggia=0),   # кухня
    ]
    n = len(cols)
    seed = mul(rnd, 50.0)
    cell = g.combine(iu, iv, 0.0)
    r = [g.noise(cell, add(seed, k)) for k in (0.0, 17.0, 31.0, 43.0, 59.0, 71.0)]
    r1, r2, r3, r4, r5, r6 = r

    # секция из шести колонок; у каждой второй она зеркальна, чтобы ритм не повторялся по линейке
    sec = g.math("FLOOR", div(iu, float(n)))
    mirror = gt(g.noise(g.combine(sec, 0.0, 7.0), seed), 0.5)
    km = g.math("FLOORED_MODULO", iu, float(n))
    km = add(km, mul(mirror, sub(float(n - 1), mul(km, 2.0))))
    key = div(add(km, 0.5), float(n))
    pos_k = [i / n for i in range(n)]
    hw_f, v0_f, v1_f = g.sep(g.ramp(key, [(p, (c["w"] / 2, c["v0"], c["v1"])) for p, c in zip(pos_k, cols)]))
    shift_f, mull_f, stair_f = g.sep(g.ramp(key, [(p, (c["shift"], c["mull"] * 0.5, c["stair"])) for p, c in zip(pos_k, cols)]))
    loggia_f, _, _ = g.sep(g.ramp(key, [(p, (c["loggia"], 0.0, 0.0)) for p, c in zip(pos_k, cols)]))

    # торцы глухие; окно на каждой четвёртой клетке, лестничного вида
    mod4 = g.math("FLOORED_MODULO", iu, 4.0)
    side_col = mul(gt(mod4, 0.5), lt(mod4, 1.5))
    sel = lambda a, b: add(a, mul(side, sub(b, a)))
    hw = sel(hw_f, 0.15)
    v0, v1 = sel(v0_f, 0.25), sel(v1_f, 0.85)
    shift = sel(shift_f, 0.5)
    mullv = sel(mull_f, 0.0)
    stair = sel(stair_f, 1.0)
    loggia = sel(loggia_f, 0.0)
    vs = add(v, shift)
    ivs, fvs = g.math("FLOOR", vs), g.math("FRACT", vs)
    gate = mul(mul(sel(1.0, side_col), vert), gt(ivs, sub(stair, 0.5)))   # лестничное окно — со 2-го этажа
    du = absv(sub(fu, 0.5))
    box = lambda dw, dh: mul(mul(lt(du, add(hw, dw)), mul(gt(fvs, sub(v0, dh)), lt(fvs, add(v1, dh)))), gate)
    in_glass, in_frame = box(0.0, 0.0), box(0.03, 0.03)
    in_sill = mul(mul(lt(du, add(hw, 0.05)), mul(gt(fvs, sub(v0, 0.075)), lt(fvs, sub(v0, 0.03)))),
                  mul(gate, mul(sub(1.0, stair), sub(1.0, loggia))))

    # стекло: градиент по высоте окна (сверху светлее), тень откоса под верхней рамой, шторы
    wv = clamp01(div(sub(fvs, v0), sub(v1, v0)))
    grad = mul(add(0.80, mul(wv, 0.40)), sub(1.0, mul(gt(wv, 0.90), 0.30)))
    glass = g.scale(g.rgb("glass", (0.1, 0.1, 0.1)), mul(add(0.85, mul(r2, 0.3)), grad))
    curtain = tint(g.ramp(r5, [(0.0, (0.95, 0.88, 0.72)), (0.25, (0.82, 0.88, 0.95)),
                               (0.50, (0.90, 0.90, 0.88)), (0.75, (0.80, 0.62, 0.58))]))
    glass = g.mix(mul(lt(r6, 0.38), add(0.45, mul(r3, 0.30))), glass, curtain)

    # свет: окна жилых комнат тёплые и холодные случайно, лестница светится чаще и холодным
    lit_k = g.value("lit_k", 1.0)
    p_eff = mul(g.value("p_lit", 0.0), add(0.55, rnd))
    lit_n = lt(r1, p_eff)
    lit_s = lt(r1, g.math("MULTIPLY", p_eff, 1.8, clamp=True))
    lit = add(lit_n, mul(stair, sub(lit_s, lit_n)))
    warm = g.ramp(r2, [(0.0, (1.0, 0.70, 0.38)), (0.50, (1.0, 0.82, 0.55)),
                       (0.80, (0.80, 0.90, 1.0)), (0.95, (0.50, 0.65, 1.0))])
    bright = add(0.55, mul(r3, 0.45))
    warm_col = g.scale(warm, mul(bright, lit_k))
    cold_col = g.scale(g.rgb("stair_light", (0.74, 0.95, 0.90)), mul(add(0.5, mul(r3, 0.25)), lit_k))
    win_col = g.mix(lit, glass, g.mix(stair, warm_col, cold_col))

    # лоджия: половина открытые (тёмная ниша с ограждением), половина остеклённые
    opened = mul(loggia, lt(r4, 0.5))
    win_col = g.mix(opened, win_col, g.scale(win_col, 0.4))
    win_col = g.mix(mul(opened, lt(fvs, add(v0, 0.30))), win_col, g.scale(wall, 0.88))

    # рама, подоконник, перемычки и форточка
    frame = tint(g.scale(base, 1.12))
    sill = tint(g.scale(base, 1.30))
    wu = absv(div(sub(fu, 0.5), hw))
    one = mul(mul(gt(mullv, 0.25), lt(mullv, 0.75)), lt(wu, 0.035))
    two = mul(gt(mullv, 0.75), lt(absv(sub(wu, 0.333)), 0.035))
    transom = mul(lt(absv(sub(wv, 0.72)), 0.025), mul(sub(1.0, loggia), sub(1.0, stair)))
    bars = mul(mul(g.math("ADD", g.math("ADD", one, two), transom, clamp=True), in_glass), sub(1.0, opened))

    # подъезд: тёмная дверь на первом этаже в колонке лестницы и козырёк над ней
    front = mul(vert, sub(1.0, side))
    ground = mul(mul(stair_f, lt(iv, 0.5)), front)
    door = mul(ground, mul(lt(fv, 0.72), lt(du, 0.30)))
    canopy = mul(ground, mul(mul(gt(fv, 0.72), lt(fv, 0.80)), lt(du, 0.36)))
    door_lit = mul(gt(lit_k, 0.01), lt(r1, 0.9))
    door_col = g.mix(door_lit, g.scale(g.rgb("glass", (0.1, 0.1, 0.1)), 0.5),
                     g.scale(g.rgb("door_light", (1.0, 0.84, 0.56)), mul(lit_k, 0.85)))

    col = wall
    col = g.mix(in_sill, col, sill)
    col = g.mix(in_frame, col, frame)
    col = g.mix(in_glass, col, win_col)
    col = g.mix(bars, col, frame)
    col = g.mix(canopy, col, g.scale(wall, 0.65))
    col = g.mix(door, col, door_col)
    g.finish(_haze(g, col))
    return mat


def make_flat(name, base):
    """Однотонная поверхность (земля, дорога, столбы): цвет × тон фазы, с той же дымкой."""
    mat = _new_material(name)
    g = G(mat.node_tree)
    col = g.mix(1.0, base, g.rgb("tone", (1.0, 1.0, 1.0)), blend="MULTIPLY")
    g.finish(_haze(g, col))
    return mat


def make_lamp():
    """Светящиеся фонари: яркость задаёт фаза (днём погашены)."""
    mat = _new_material("ext_lamp")
    g = G(mat.node_tree)
    col = g.scale(g.rgb("lamp_col", (1.0, 0.72, 0.38)), g.value("lamp", 0.0))
    g.finish(_haze(g, col))
    return mat


def make_sky():
    """Небо: градиент от горизонта к зениту по высоте на далёком заднике."""
    mat = _new_material("ext_sky")
    g = G(mat.node_tree)
    pos, _ = g.geometry()
    _, _, pz = g.sep(pos)
    mr = g.nt.nodes.new("ShaderNodeMapRange")
    g._loc(mr)
    mr.clamp = True
    mr.inputs["From Min"].default_value = GROUND_Z
    mr.inputs["From Max"].default_value = 420.0
    g.nt.links.new(pz, mr.inputs["Value"])
    t = g.math("POWER", mr.outputs[0], 0.55)
    col = g.mix(t, g.rgb("sky_h", (0.8, 0.85, 0.95)), g.rgb("sky_z", (0.4, 0.6, 0.9)))
    g.finish(col)
    return mat


# ---------- геометрия --------------------------------------------------------------

def _box(name, x0, x1, y0, y1, z0, z1, mat, coll):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x = x0 + (v.co.x + 0.5) * (x1 - x0)
        v.co.y = y0 + (v.co.y + 0.5) * (y1 - y0)
        v.co.z = z0 + (v.co.z + 0.5) * (z1 - z0)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    coll.objects.link(ob)
    ob.data.materials.append(mat)
    ob.visible_shadow = False
    return ob


def _plane_y(name, x0, x1, z0, z1, y, mat, coll):
    """Вертикальный задник лицом к -y (к комнате)."""
    bm = bmesh.new()
    vs = [bm.verts.new(c) for c in ((x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1))]
    bm.faces.new(vs)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    coll.objects.link(ob)
    ob.data.materials.append(mat)
    ob.visible_shadow = False
    return ob


def _plane_z(name, x0, x1, y0, y1, z, mat, coll):
    bm = bmesh.new()
    vs = [bm.verts.new(c) for c in ((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z))]
    bm.faces.new(vs)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new(name, mesh)
    coll.objects.link(ob)
    ob.data.materials.append(mat)
    ob.visible_shadow = False
    return ob


def _place(coll, mat, wall_mat, rng, row, name, xs, xe, floors):
    """Дом: коробка на всю высоту, выход на кровлю и антенна без окон (материал wall_mat).
    Торцы лежат на сетке секций, чтобы окна соседних домов ложились ровно."""
    xs, xe = round(xs / BAY_W) * BAY_W, round(xe / BAY_W) * BAY_W
    y0 = WALL_Y + row["y"]
    z1 = GROUND_Z + floors * FLOOR_H
    ob = _box(name, xs, xe, y0, y0 + row["depth"], GROUND_Z, z1, mat, coll)
    seg = xe - xs
    if rng.random() < 0.75:
        w = rng.uniform(3.5, 6.0)
        cx = xs + rng.uniform(2, max(2.5, seg - w - 2))
        _box(name + "_roofbox", cx, cx + w, y0 + 2, y0 + 2 + w, z1, z1 + rng.uniform(2.4, 3.4), wall_mat, coll)
    if rng.random() < 0.5:
        cx = xs + rng.uniform(1, seg - 1)
        _box(name + "_mast", cx, cx + 0.35, y0 + 3, y0 + 3.35, z1, z1 + rng.uniform(4, 9), wall_mat, coll)
    return ob


def build_buildings(coll, mat, wall_mat, rng):
    count = 0
    for row in ROWS:
        fixed = row.get("fixed", [])
        for i, (x0, x1, fl) in enumerate(fixed):
            _place(coll, mat, wall_mat, rng, row, "ext_%s_fix%d" % (row["name"], i), x0, x1, fl)
            count += 1
        # случайные дома заполняют остальное, не заходя на ручные
        if fixed:
            strips = [(row["x"][0], min(f[0] for f in fixed) - 10), (max(f[1] for f in fixed) + 10, row["x"][1])]
        else:
            strips = [row["x"]]
        for lo, hi in strips:
            x = lo + rng.uniform(0, 20)
            while x < hi:
                length = rng.uniform(*row["len"])
                if row["name"] in ("front", "mid"):          # длина кратна секции в шесть колонок
                    length = max(2, round(length / (6 * BAY_W))) * 6 * BAY_W
                sections = rng.choice([1, 1, 2, 3]) if row["name"] in ("front", "mid") else 1
                seg = length / sections
                floors = rng.randint(*row["floors"])
                for s in range(sections):
                    if s:
                        floors = max(row["floors"][0], min(row["floors"][1], floors + rng.choice([-4, -2, 2, 4])))
                    _place(coll, mat, wall_mat, rng, row, "ext_%s_%02d_%d" % (row["name"], count, s),
                           x + s * seg, x + (s + 1) * seg, floors)
                x += length + rng.uniform(*row["gap"])
                count += 1
    return count


def build_ground(coll, mats):
    span = 3000.0
    _plane_z("ext_ground", -span, span, WALL_Y, 1500.0, GROUND_Z, mats["ground"], coll)
    # дорога между двором и первым рядом: ближний край 22 м от фасада, ширина 12 м
    _plane_z("ext_road", -span, span, WALL_Y + 22.0, WALL_Y + 34.0, ROAD_Z, mats["road"], coll)
    # фонари вдоль дороги: столб и светящаяся голова
    for i in range(-12, 14):
        x = i * 22.0
        _box("ext_pole_%d" % i, x, x + 0.25, WALL_Y + 20.4, WALL_Y + 20.65, GROUND_Z, GROUND_Z + 8.0, mats["pole"], coll)
        _box("ext_lamphead_%d" % i, x - 0.4, x + 0.65, WALL_Y + 20.2, WALL_Y + 20.9, GROUND_Z + 8.0,
             GROUND_Z + 8.25, mats["lamp"], coll)


def build_sky(coll, mat):
    # Далёкий задник: за самым дальним рядом, шире любого кадра
    _plane_y("ext_sky", -6000.0, 6000.0, GROUND_Z - 20.0, 1500.0, 1800.0, mat, coll)


# ---------- фазы -------------------------------------------------------------------

def apply_phase(phase):
    """Выставить цвета и свет в окнах для фазы; нет коллекции — ничего не делать."""
    if bpy.data.collections.get(COLLECTION) is None:
        return False
    ph = EXT_PHASES["day" if phase == "morning" else phase]
    for mat in bpy.data.materials:
        if not mat.name.startswith("ext_") or mat.node_tree is None:
            continue
        for node in mat.node_tree.nodes:
            key = node.label
            if key == "tone":
                node.outputs[0].default_value = (*ph["tone"], 1.0)
            elif key == "haze":
                node.outputs[0].default_value = (*ph["haze"], 1.0)
            elif key == "glass":
                node.outputs[0].default_value = (*ph["glass"], 1.0)
            elif key == "sky_h":
                node.outputs[0].default_value = (*ph["sky_h"], 1.0)
            elif key == "sky_z":
                node.outputs[0].default_value = (*ph["sky_z"], 1.0)
            elif key in ("roof_k", "haze_dist", "haze_max", "p_lit", "lit_k", "lamp"):
                node.outputs[0].default_value = ph[key]
    # камеры должны видеть далёкое небо
    for cam in bpy.data.cameras:
        cam.clip_end = max(cam.clip_end, CLIP_END)
    return True


def soften_window_glass():
    """Стекло окна героя почти прозрачное: у общего стекла палитры плотный блик, и днём
    небо с лампами отражались в нём сплошной белой пеленой, закрывая дома напротив."""
    import cel_shader as C
    import palette as P
    ob = bpy.data.objects.get("окно")
    if ob is None:
        return False
    name = "pal_glass_window"
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        prof = C.MATERIALS["glass"]
        saved = dict(prof)
        prof.update(spec=0.18, alpha=0.10)
        try:
            light = C.build(mat.node_tree, P.srgb(P.COLORS["snow"]), kind="glass")
        finally:
            prof.clear()
            prof.update(saved)
        C.surface(mat, "glass")
        mat.diffuse_color = (*light, 1.0)
    for slot in ob.material_slots:
        if slot.material is not None and slot.material.name.startswith("pal_glass"):
            slot.material = mat
    # стекло не отбрасывает тень: иначе оно глушит солнце и свет окна, и комната остаётся без них
    ob.visible_shadow = False
    return True


# ---------- сборка -----------------------------------------------------------------

def refresh_materials():
    """Пересобрать узлы фасада в готовой коллекции; дома остаются там, где их поставили.
    Надстройки (`*_roofbox`, `*_mast`) переходят на ext_wall; свои блоки на крыше назначайте им же."""
    make_facade()
    wall = make_facade("ext_wall", windows=False)
    coll = bpy.data.collections[COLLECTION]
    for ob in coll.objects:
        if ob.name.endswith(("_roofbox", "_mast")) and ob.data is not None:
            ob.data.materials.clear()
            ob.data.materials.append(wall)
    apply_phase("day")


def build(seed=11):
    old = bpy.data.collections.get(COLLECTION)
    if old is not None:
        for ob in list(old.objects):
            mesh = ob.data
            bpy.data.objects.remove(ob)
            if mesh is not None and mesh.users == 0:
                bpy.data.meshes.remove(mesh)
        bpy.data.collections.remove(old)
    coll = bpy.data.collections.new(COLLECTION)
    bpy.context.scene.collection.children.link(coll)

    facade = make_facade()
    wall = make_facade("ext_wall", windows=False)
    mats = {
        "ground": make_flat("ext_ground", (0.34, 0.37, 0.33)),
        "road": make_flat("ext_road", (0.22, 0.23, 0.26)),
        "pole": make_flat("ext_pole", (0.18, 0.19, 0.21)),
        "lamp": make_lamp(),
    }
    sky = make_sky()
    rng = random.Random(seed)
    n = build_buildings(coll, facade, wall, rng)
    build_ground(coll, mats)
    build_sky(coll, sky)
    soften_window_glass()
    apply_phase("day")
    return n


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    seed = int(argv[argv.index("--seed") + 1]) if "--seed" in argv else 11
    # Коллекцию правят руками: без явного --rebuild дома и их положение не трогаются,
    # обновляются только материалы (окна, стены) и надстройки получают материал без окон
    if bpy.data.collections.get(COLLECTION) is not None and "--rebuild" not in argv:
        print("[exterior] коллекция `%s` уже есть: обновляю материалы; пересоздать с нуля — --rebuild" % COLLECTION)
        refresh_materials()
    else:
        print("[exterior] домов: %d" % build(seed))
    if "--dry" not in argv:
        bpy.ops.wm.save_mainfile()


if __name__ == "__main__":
    main()
