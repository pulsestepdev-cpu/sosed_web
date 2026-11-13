# Герой: модель из Tripo в T-позе -> скелет с пальцами, веса, анимации под механики игры -> один GLB.
# blender -b -P tools/blender/rig_hero.py -- <hero_3d.glb> <выход.glb> [сохранить.blend]
# Общий механизм (оси углов, кисти, решатель, запись) — в rig_core.py.
#
# Прятки: клипы hide_* разовые — показывают, как герой залезает в укрытие; дальше игра его скрывает.
# Корневое смещение (шаги в шкаф, нырок под кровать) — в кости Hips, по умолчанию вперёд (-Y).
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rig_core import *
import rig_core as rc

SRC, DST, BLEND = args()
load_model(SRC, 1.75)

# ---------------------------------------------------------------- скелет
# точки сняты по срезам сетки (рост 1.75): плечи 1.165, руки на 1.15, запястье x≈0.65,
# тазобедренный ~0.71, колено 0.38, щиколотка 0.11; голова крупная (1.30..1.76), кепка с козырьком
CENTER = [
    ("Hips",   (0, 0.04, 0.72), (0, 0.04, 0.84), None),
    ("Spine",  (0, 0.04, 0.84), (0, 0.04, 0.96), "Hips"),
    ("Spine1", (0, 0.04, 0.96), (0, 0.05, 1.06), "Spine"),
    ("Spine2", (0, 0.05, 1.06), (0, 0.05, 1.24), "Spine1"),
    ("Neck",   (0, 0.05, 1.24), (0, 0.03, 1.32), "Spine2"),
    ("Head",   (0, 0.03, 1.32), (0, 0.03, 1.76), "Neck"),
]
SIDE = [
    ("Shoulder", (0.04, 0.06, 1.21), (0.24, 0.07, 1.165), "Spine2"),
    ("Arm",      (0.24, 0.07, 1.165), (0.46, 0.07, 1.15), "Shoulder"),
    ("ForeArm",  (0.46, 0.07, 1.15), (0.65, 0.07, 1.14), "Arm"),
    ("Hand",     (0.65, 0.07, 1.14), (0.785, 0.06, 1.13), "ForeArm"),
    ("UpLeg",    (0.12, 0.04, 0.70), (0.145, 0.05, 0.38), "Hips"),
    ("Leg",      (0.145, 0.05, 0.38), (0.17, 0.07, 0.11), "UpLeg"),
    ("Foot",     (0.17, 0.07, 0.11), (0.20, -0.10, 0.04), "Leg"),
    ("ToeBase",  (0.20, -0.10, 0.04), (0.21, -0.20, 0.04), "Foot"),
]
# Кисть крупная, пальцы слеплены «варежкой» (по виду сверху), ладонь вниз, большой палец вперёд
FINGERS = {
    "Index":  ((0.785, 0.018, 1.130), (0.865, 0.012, 1.123)),
    "Middle": ((0.790, 0.053, 1.130), (0.875, 0.053, 1.123)),
    "Ring":   ((0.785, 0.088, 1.128), (0.870, 0.090, 1.122)),
    "Pinky":  ((0.775, 0.120, 1.125), (0.845, 0.125, 1.120)),
}
THUMB = [(0.66, 0.03, 1.12), (0.69, -0.01, 1.10), (0.72, -0.04, 1.088), (0.75, -0.065, 1.08)]
build_skeleton(CENTER, SIDE, FINGERS, THUMB,
               grip=((0.80, 0.07, 1.08), (0.80, -0.01, 1.08)),
               phone=((0.775, 0.055, 1.097), (0.855, 0.055, 1.097)))
make_weights()
report_weights()

# точки лица в позе покоя (рендер головы с метками высоты)
MOUTH = (0.0, -0.14, 1.357)
EYES = (0.0, -0.10, 1.453)

# ---------------------------------------------------------------- базовые позы
L_THIGH = (rc.arm_data.bones["LeftUpLeg"].tail_local - rc.arm_data.bones["LeftUpLeg"].head_local).length
L_SHIN = (rc.arm_data.bones["LeftLeg"].tail_local - rc.arm_data.bones["LeftLeg"].head_local).length

def leg_ik(p, s, drop, fwd=0.0, flat=1.0):
    """Нога s: таз опущен на drop (м), стопа впереди таза на fwd (м). Стопа остаётся ровной (flat)."""
    h = L_THIGH + L_SHIN - drop
    d = max(abs(L_THIGH - L_SHIN) + 1e-3, min(L_THIGH + L_SHIN - 1e-4, math.hypot(h, fwd)))
    knee = math.pi - math.acos(max(-1, min(1, (L_THIGH ** 2 + L_SHIN ** 2 - d * d) / (2 * L_THIGH * L_SHIN))))
    thigh = math.atan2(fwd, h) + math.acos(max(-1, min(1, (L_THIGH ** 2 + d * d - L_SHIN ** 2) / (2 * L_THIGH * d))))
    a, b = math.degrees(thigh), math.degrees(knee)
    p.side(s, "UpLeg", rx=-a)
    p.side(s, "Leg", rx=b)
    p.side(s, "Foot", rx=(a - b) * flat)

def crouch(p, drop, lean=None, back=None):
    """Присесть: таз вниз на drop и назад, корпус наклонён вперёд для равновесия, стопы на месте."""
    back = 0.35 * drop if back is None else back
    lean = 75 * drop if lean is None else lean
    p.move(y=back, z=-drop)
    for s in ("L", "R"):
        leg_ik(p, s, drop, back)
    p.add("Spine", rx=lean * 0.5)
    p.add("Spine1", rx=lean * 0.3)
    p.add("Spine2", rx=lean * 0.2)
    p.add("Head", rx=-lean * 0.6)       # голова смотрит вперёд, а не в пол

def stand(t=0.0, breath=1.0):
    p = Pose()
    b = S(t) * breath
    p.both("Arm", rx=-4, ry=76)
    p.both("ForeArm", rz=-14)
    p.both("Hand", rz=-4)
    hand(p, "B", "relax", base="flat")
    p.both("Shoulder", ry=1 - 1.2 * b)
    p.both("UpLeg", rx=-1, ry=-1)
    p.both("Leg", rx=2)
    p.add("Spine", rx=1 - 0.6 * b)
    p.add("Spine2", rx=-0.8 * b)
    p.add("Head", rx=2)
    return p

def arm_pose(p, s, table, k=1.0):
    for b in ("Arm", "ForeArm", "Hand"):
        p.side(s, b, *[v * k for v in table[b]])

def blend(tables, ph):
    """Плавный переход по цепочке поз: ph = 0..len-1 (дробное). None — без добавки (стойка)."""
    i = max(0, min(len(tables) - 2, int(ph))); f = ph - i
    out = {}
    for b in ("Arm", "ForeArm", "Hand"):
        a0 = tables[i][b] if tables[i] else [0.0] * 3
        a1 = tables[i + 1][b] if tables[i + 1] else [0.0] * 3
        out[b] = [lerp(a0[k], a1[k], f) for k in range(3)]
    return out

# Позы рук: углы подбирает решатель (внизу). Начальные значения — грубые.
REACH_LOW = {"Arm": [-60.0, 0.0, -10.0], "ForeArm": [0.0, 0.0, -10.0], "Hand": [0.0, 0.0, 0.0]}
REACH_MID = {"Arm": [-80.0, -10.0, -10.0], "ForeArm": [0.0, 0.0, -10.0], "Hand": [0.0, 0.0, 0.0]}
HOLD_CHEST = {"Arm": [-30.0, 0.0, -20.0], "ForeArm": [0.0, 0.0, -100.0], "Hand": [0.0, 0.0, 0.0]}
HOLD_UP = {"Arm": [-20.0, -150.0, -10.0], "ForeArm": [0.0, 0.0, -10.0], "Hand": [0.0, 0.0, 0.0]}
MOUTH_L = {"Arm": [-40.0, 10.0, -30.0], "ForeArm": [0.0, 0.0, -130.0], "Hand": [0.0, 0.0, 0.0]}
DOOR = {"Arm": [-80.0, -10.0, 10.0], "ForeArm": [0.0, 0.0, -20.0], "Hand": [0.0, 0.0, 0.0]}
BRIM = {"Arm": [-60.0, -40.0, -30.0], "ForeArm": [0.0, 0.0, -120.0], "Hand": [0.0, 0.0, 0.0]}   # пальцы на козырьке
# козырёк кепки (поза покоя): кончик ~(0, -0.285, 1.60), у лба ~(0, -0.13, 1.49) — снято по рендеру сбоку
BRIM_PT = (-0.05, -0.25, 1.575)

# ---------------------------------------------------------------- анимации: ходьба
@anim("idle", 90)
def a_idle(t):
    p = stand(t)
    p.move(x=0.006 * S(t))
    p.add("Hips", ry=-1 * S(t))
    p.add("Head", rz=14 * keys(t, [(0, 0), (0.2, 0), (0.3, 1), (0.5, 1), (0.6, -1), (0.8, -1), (0.9, 0)]))  # зыркает
    p.both("Arm", rx=2 * S(t))
    return p

def walk_pose(t, amp=1.0, breath=0.3):
    p = stand(t * 2, breath)
    sw = S(t)
    for s, sh in (("L", 0.0), ("R", 0.5)):
        x = S(t + sh); c = C(t + sh)
        p.side(s, "UpLeg", rx=-24 * x * amp, ry=-2)
        p.side(s, "Leg", rx=6 + 42 * max(0.0, c) ** 1.5 * amp)
        p.side(s, "Foot", rx=-14 * x * amp + 10 * max(0.0, -c) * max(0.0, -x))
        p.side(s, "Arm", rx=20 * x * amp)
        p.side(s, "ForeArm", rz=-12 - 14 * max(0.0, -x))
    p.move(x=0.015 * sw, z=-0.006 - 0.036 * sw * sw * amp)
    p.add("Hips", rz=6 * sw)
    p.add("Spine", rz=-4 * sw, rx=3)
    p.add("Spine2", rz=-3 * sw)
    p.add("Head", rz=2 * sw)
    return p

@anim("walk", 30)
def a_walk(t):
    return walk_pose(t)

@anim("sneak", 48)
def a_sneak(t):
    """Крадётся: пригнулся, высоко поднимает колени, ставит ногу на носок; руки перед собой «лапками»."""
    p = stand(t, 0.0)
    crouch(p, 0.10, lean=22)
    sw = S(t)
    for s, sh in (("L", 0.0), ("R", 0.5)):
        x = S(t + sh); c = C(t + sh)
        lift = max(0.0, c) ** 1.2
        p.side(s, "UpLeg", rx=-18 * x - 30 * lift)
        p.side(s, "Leg", rx=55 * lift)
        p.side(s, "Foot", rx=20 * lift + 8)            # тянет носок
    p.move(z=0.02 * abs(sw), x=0.02 * sw)
    p.add("Spine1", rz=-6 * sw)
    p.add("Head", rz=10 * S(t * 0.5), rx=-4)        # зыркает по сторонам
    p.both("Arm", rx=-55, ry=-8, rz=-14)
    p.both("ForeArm", rz=-75)
    p.both("Hand", rz=40)                           # кисти свисают «лапками»
    p.side("L", "Arm", rx=6 * sw); p.side("R", "Arm", rx=-6 * sw)
    return p

# ---------------------------------------------------------------- анимации: тайники и предметы
@anim("search_low", 60)
def a_search_low(t):
    """Шарит внизу (шкафчик под раковиной, ботинок, канистры): присел, рука роется."""
    p = stand(t, 0.4)
    crouch(p, 0.30, lean=38)
    r = S(t * 2); q = S(t * 3 + 0.2)
    arm_pose(p, "R", REACH_LOW)
    p.side("R", "Arm", rx=7 * r, rz=8 * q)
    p.side("R", "ForeArm", rz=-10 * max(0.0, q))
    p.side("L", "Arm", rx=-35, ry=-6, rz=-10)       # левая на колене
    p.side("L", "ForeArm", rz=-40)
    p.add("Head", rz=8 * S(t), ry=6 * r)
    p.add("Spine1", rz=-6 * r)
    return p

@anim("search_mid", 60)
def a_search_mid(t):
    """Шарит на уровне груди (бачок, банки, ящик с инструментами), вытягивая шею."""
    p = stand(t, 0.4)
    p.add("Spine", rx=10)
    r = S(t * 2); q = S(t * 3 + 0.2)
    arm_pose(p, "R", REACH_MID)
    p.side("R", "Arm", rx=6 * r, rz=8 * q)
    p.side("R", "ForeArm", rz=-12 * max(0.0, q))
    p.side("L", "Arm", rx=-60, ry=-4, rz=-6)        # левой придерживает крышку
    p.side("L", "ForeArm", rz=-30)
    p.add("Head", rz=-6 + 6 * S(t), rx=-6)
    p.both("Leg", rx=4); p.side("R", "UpLeg", rx=-6)
    return p

def take_phase(t):
    return keys(t, [(0, 0), (0.3, 1), (0.42, 1), (0.7, 2), (1, 2)])

@anim("take", 36, loop=False)
def a_take(t):
    """Берёт предмет: тянется, хватает, прижимает к груди, оглядывается."""
    p = stand(t, 0.0)
    ph = take_phase(t)
    arm_pose(p, "R", blend([None, REACH_MID, HOLD_CHEST], ph))
    p.add("Spine", rx=10 * keys(t, [(0, 0), (0.3, 1), (0.6, 0)]))
    p.add("Head", rz=30 * keys(t, [(0.6, 0), (0.75, 1), (0.88, -1), (1, 0)]))
    return p

@anim("swap", 75)
def a_swap(t):
    """Подмена: левой держит ёмкость, правой подливает/подкладывает, на середине оглядывается."""
    p = stand(t, 0.3)
    p.add("Spine", rx=8)
    arm_pose(p, "R", HOLD_CHEST)
    arm_pose(p, "L", HOLD_CHEST)
    pour = keys(t, [(0, 0), (0.15, 1), (0.4, 1), (0.5, 0), (0.7, 0), (0.8, 1), (0.95, 1), (1, 0)])
    p.side("R", "Arm", ry=-12 * pour, rx=-8 * pour)
    p.side("R", "Hand", rx=-55 * pour)               # наклоняет бутылку
    look = keys(t, [(0.4, 0), (0.5, 1), (0.66, 1), (0.74, 0)])
    p.add("Head", rz=55 * look, rx=-6 * look)        # «никто не видит?»
    p.add("Spine1", rz=15 * look)
    return p

@anim("success", 48, loop=False)
def a_success(t):
    """«Есть!»: вскинул добычу над головой, подпрыгнул, кулак второй руки — «йес»."""
    p = stand(t, 0.0)
    ph = keys(t, [(0, 0), (0.25, 1), (0.85, 1), (1, 0.6)])
    arm_pose(p, "R", blend([HOLD_CHEST, HOLD_UP], ph))
    jump = keys(t, [(0.15, 0), (0.25, -1), (0.38, 1), (0.52, 0), (0.6, -0.4), (0.7, 0)])
    crouch(p, max(0.0, -jump) * 0.12, lean=8 * max(0.0, -jump))
    p.move(z=0.11 * max(0.0, jump))
    p.both("Foot", rx=30 * max(0.0, jump))           # в прыжке тянет носки
    pump = keys(t, [(0.45, 0), (0.55, 1), (0.62, 0.3), (0.7, 1), (0.78, 0.3), (0.86, 1), (1, 0.6)])
    p.side("L", "Arm", rx=-40 - 10 * pump, ry=-10, rz=-20)
    p.side("L", "ForeArm", rz=-120 + 25 * (1 - pump))
    p.add("Head", rx=-15 * ph)
    p.add("Spine2", rx=-8 * ph)
    return p

@anim("laugh", 45)
def a_laugh(t):
    """Хихикает в кулак: согнулся, плечи трясутся, другой рукой держится за живот."""
    p = stand(t, 0.0)
    shake = S(t * 6)
    p.add("Spine", rx=12 + 3 * shake)
    p.add("Spine2", rx=4 + 2 * shake)
    arm_pose(p, "L", MOUTH_L)
    p.side("R", "Arm", rx=-30, ry=4, rz=-14)
    p.side("R", "ForeArm", rz=-80)
    p.both("Shoulder", ry=-5 * max(0.0, shake))
    p.add("Head", rx=6 + 4 * shake, rz=10 * S(t))
    p.move(z=-0.01 * abs(shake))
    return p

@anim("caught", 45, loop=False)
def a_caught(t):
    """Попался: подпрыгнул от испуга, руки вверх, потом сжался — «сдаюсь»."""
    p = stand(t, 0.0)
    jump = keys(t, [(0, 0), (0.1, 1), (0.25, 0)])
    up = keys(t, [(0, 0), (0.1, 1), (0.4, 1), (0.55, 0)])          # руки взлетели вверх
    shrink = keys(t, [(0.4, 0), (0.6, 1), (1, 1)])                  # «сдаюсь»: ладони вверх у плеч
    p.move(z=0.09 * jump)
    p.both("Foot", rx=25 * jump)
    # плечо в сторону почти горизонтально, проворот плеча (rx) ставит согнутое предплечье вертикально
    p.both("Arm", ry=-116 * up - 62 * shrink, rx=-20 * up - 85 * shrink)
    p.both("ForeArm", rz=-20 * up - 95 * shrink)
    crouch(p, 0.06 * shrink, lean=10 * shrink)
    p.both("Shoulder", ry=-10 * shrink)              # втянул голову в плечи
    p.add("Head", rx=-10 * jump + 12 * shrink)
    return p

# ---------------------------------------------------------------- анимации: прятки
# Все клипы пряток начинаются лицом к укрытию (игра ставит героя в точку подхода и разворачивает),
# корневое смещение (Hips, -Y — вперёд) ведёт его внутрь / под / за укрытие. Расстояния — под мебель
# из tools/build_level_3d.gd (точки подхода — Hero3D.HIDES).

def on_fours(p, k):
    """На четвереньках с силой k: таз опущен и наклонён, бёдра вертикально, голени по полу, руки в пол."""
    p.move(z=-0.36 * k)
    p.add("Hips", rx=80 * k)
    p.both("UpLeg", rx=-80 * k)                      # бёдра вниз, к полу
    p.both("Leg", rx=92 * k)                         # голени лежат на полу
    p.both("Foot", rx=50 * k)
    p.add("Spine", rx=4 * k); p.add("Spine1", rx=4 * k)   # грудь ниже — кепка проходит под столешницу (0.72 м)
    p.add("Head", rx=-26 * k)                        # смотрит вперёд-вниз
    p.both("Arm", rx=-70 * k, ry=4 * k)              # руки к полу, локти согнуты
    p.both("ForeArm", rz=-40 * k)

@anim("hide_table", 54, loop=False)
def a_hide_table(t):
    """Под стол на четвереньках: опустился на колени, упёрся руками и прополз под столешницу, оглянулся."""
    p = stand(0, 0.0)
    on_fours(p, keys(t, [(0, 0), (0.28, 1)]))
    go = keys(t, [(0.3, 0), (0.82, 1)], ease=lambda f: f)
    p.move(y=-0.55 * go)
    if 0.3 < t < 0.82:                               # ползёт: левая рука с правым коленом, потом наоборот
        w = S((t - 0.3) / 0.52 * 2)
        p.side("L", "Arm", rx=-16 * w); p.side("R", "Arm", rx=16 * w)
        p.side("R", "UpLeg", rx=-14 * w); p.side("L", "UpLeg", rx=14 * w)
        p.add("Hips", rz=5 * w); p.add("Spine1", rz=-4 * w)
        p.move(z=0.012 * abs(w))
    look = keys(t, [(0.84, 0), (0.95, 1)])
    p.add("Head", rz=35 * look, ry=-10 * look)      # оглянулся: не видит ли сосед
    return p

@anim("hide_wardrobe", 60, loop=False)
def a_hide_wardrobe(t):
    """В шкаф: открыл дверцу правой, шагнул внутрь, развернулся и прикрыл дверцу за собой."""
    p = walk_pose(keys(t, [(0.25, 0), (0.7, 1)]) * 2, amp=0.7) if 0.25 < t < 0.7 else stand(t, 0.0)
    door = keys(t, [(0, 0), (0.12, 1), (0.25, 1), (0.32, 0)])
    sweep = keys(t, [(0.1, 0), (0.25, 1)])
    arm_pose(p, "R", DOOR, door)
    p.side("R", "Arm", rz=60 * sweep * door)         # тянет дверцу на себя и вбок
    p.move(y=-0.65 * keys(t, [(0.25, 0), (0.7, 1)]))
    p.add("Head", rx=12 * keys(t, [(0.3, 0), (0.45, 1), (0.6, 0)]))   # пригнулся под перекладиной
    turn = keys(t, [(0.68, 0), (0.88, 1)])
    p.add("Hips", rz=180 * turn)
    close = keys(t, [(0.82, 0), (0.92, 1), (1, 0.6)])
    arm_pose(p, "L", DOOR, close)
    p.side("L", "Arm", rz=-40 * close)
    return p

@anim("hide_curtain", 66, loop=False)
def a_hide_curtain(t):
    """В ванну за шторку: лицом к ванне отдёрнул шторку, перешагнул бортик, развернулся к зрителю и задёрнул."""
    p = stand(0, 0.0)
    grab = keys(t, [(0, 0), (0.12, 1), (0.3, 1), (0.4, 0)])
    aside = keys(t, [(0.12, 0), (0.28, 1)])
    arm_pose(p, "L", DOOR, grab)
    p.side("L", "Arm", rz=-70 * aside * grab, ry=-10 * aside * grab)    # отводит шторку в сторону
    # перешагивает бортик ванны: сначала правая, потом левая
    r = keys(t, [(0.28, 0), (0.37, 1), (0.46, 0)])
    l = keys(t, [(0.42, 0), (0.51, 1), (0.6, 0)])
    p.side("R", "UpLeg", rx=-88 * r); p.side("R", "Leg", rx=100 * r); p.side("R", "Foot", rx=-10 * r)
    p.side("L", "UpLeg", rx=-88 * l); p.side("L", "Leg", rx=100 * l); p.side("L", "Foot", rx=-10 * l)
    p.move(y=-0.62 * keys(t, [(0.3, 0), (0.58, 1)]), z=0.04 * (r + l) + 0.06 * keys(t, [(0.38, 0), (0.55, 1)]))
    p.add("Spine", rx=6 * (r + l))
    p.both("Arm", ry=-10 * (r + l))                  # балансирует
    turn = keys(t, [(0.58, 0), (0.74, 1)])
    p.add("Hips", rz=180 * turn)                     # развернулся лицом к зрителю
    close = keys(t, [(0.72, 0), (0.82, 1), (0.94, 1), (1, 0.4)])
    sweep = keys(t, [(0.76, 0), (0.94, 1)])
    arm_pose(p, "R", DOOR, close)
    p.side("R", "Arm", rz=50 * (1 - sweep) * close)  # тянет шторку поперёк
    p.add("Head", rz=-25 * keys(t, [(0.8, 0), (0.9, 1), (1, 1)]))
    return p

@anim("hide_bed", 45, loop=False)
def a_hide_bed(t):
    """Под кровать: присел, руки назад, нырок «рыбкой» вперёд и проскользил на пузе."""
    p = stand(0, 0.0)
    ready = keys(t, [(0, 0), (0.25, 1), (0.35, 0.6), (0.45, 0)])
    crouch(p, 0.28 * ready, lean=40 * ready)
    p.both("Arm", rx=40 * ready, ry=-8 * ready)      # замах руками назад
    dive = keys(t, [(0.3, 0), (0.55, 1)])
    p.add("Hips", rx=86 * dive)
    p.add("Head", rx=-35 * dive, rz=0)               # голова вперёд, под кровать
    p.both("Arm", ry=-160 * dive, rx=-10 * dive)      # руки вперёд «рыбкой»
    p.both("ForeArm", rz=-6 * dive)
    p.both("Foot", rx=55 * dive)
    p.move(y=-0.35 * dive - 0.75 * keys(t, [(0.5, 0), (1, 1)], ease=lambda f: 1 - (1 - f) ** 2),
           z=-0.55 * dive + 0.06 * keys(t, [(0.3, 0), (0.42, 1), (0.55, 0)]))
    return p

@anim("hide_sofa", 36, loop=False)
def a_hide_sofa(t):
    """За диван: быстро присел за спинку, голову в плечи, обхватил колени."""
    p = stand(0, 0.0)
    down = keys(t, [(0, 0), (0.35, 1)])
    crouch(p, 0.42 * down, lean=40 * down)
    p.add("Head", rx=25 * down)
    p.move(y=0.12 * keys(t, [(0, 0), (0.35, 1)]))     # шаг назад за спинку
    hug = keys(t, [(0.3, 0), (0.7, 1)])
    p.both("Arm", rx=-55 * hug, rz=-20 * hug)
    p.both("ForeArm", rz=-80 * hug)
    p.both("Shoulder", ry=-8 * hug)
    return p

@anim("hide_skis", 40, loop=False)
def a_hide_skis(t):
    """За лыжи: шаг назад к стене, вытянулся в струнку на носках, руки по швам, втянул живот."""
    p = stand(0, 0.0)
    back = keys(t, [(0, 0), (0.45, 1)])
    p.move(y=0.30 * back)
    st = keys(t, [(0.0, 0), (0.15, 1), (0.3, 0)])    # шаг назад
    p.side("R", "UpLeg", rx=25 * st); p.side("R", "Leg", rx=30 * st)
    flat = keys(t, [(0.4, 0), (0.7, 1)])
    p.move(z=0.04 * flat)
    p.both("Foot", rx=28 * flat)                      # на носках
    p.both("Arm", ry=12 * flat, rx=4 * flat)          # руки по швам
    p.both("ForeArm", rz=12 * flat)
    p.add("Spine", rx=-5 * flat); p.add("Spine2", rx=-5 * flat)
    p.add("Head", rx=-10 * flat, rz=-30 * keys(t, [(0.7, 0), (0.85, 1), (1, 1)]))  # косится наружу
    return p

def foot_at(p, s, hy, hz, fy, fh, flat=1.0):
    """Стопа s на опоре: таз сдвинут вперёд на hy и вверх на hz, стопа — вперёд на fy, на высоте fh (м)."""
    leg_ik(p, s, fh - hz, fy - hy, flat)

def tuck(p, k):
    """Ноги поджаты (перемахнуть препятствие)."""
    p.both("UpLeg", rx=-78 * k)
    p.both("Leg", rx=105 * k)
    p.both("Foot", rx=20 * k)

@anim("hide_over", 54, loop=False)
def a_hide_over(t):
    """За диван: лицом к дивану — нога на сиденье, руки на спинку, перемахнул через спинку,
    присел за ней и развернулся к зрителю. Сиденье 0.45 м в 0.43 м впереди, спинка 0.9 м, приземление — 1.5 м."""
    p = stand(0, 0.0)
    hy = keys(t, [(0, 0), (0.18, 0.32), (0.4, 0.72), (0.6, 1.2), (0.68, 1.4)])
    hz = keys(t, [(0, 0), (0.1, -0.04), (0.2, 0.1), (0.4, 0.44), (0.5, 0.56), (0.6, 0.46), (0.68, 0.28), (0.78, -0.4)])
    p.move(y=-hy, z=hz)
    over = keys(t, [(0.38, 0), (0.46, 1), (0.62, 1), (0.7, 0)])
    land = keys(t, [(0.62, 0), (0.78, 1)])
    if t < 0.46:                                     # шагает на сиденье: правая, за ней левая
        foot_at(p, "R", hy, hz, keys(t, [(0.04, 0), (0.18, 0.68)]), keys(t, [(0.04, 0), (0.12, 0.55), (0.18, 0.45)]))
        foot_at(p, "L", hy, hz, keys(t, [(0.2, 0), (0.36, 0.78)]), keys(t, [(0.2, 0), (0.3, 0.6), (0.36, 0.45)]))
        k = 1 - over
        for s in ("L", "R"):                         # ноги — по ИК, плавно переходят в «поджал»
            for b in ("UpLeg", "Leg", "Foot"):
                r = p.r[("Left" if s == "L" else "Right") + b]
                r[0] *= k
        tuck(p, over)
    elif t < 0.66:
        tuck(p, over)
    else:
        foot_at(p, "L", hy, hz, hy + 0.05, 0.0)       # приземлился: ноги на пол, присел
        foot_at(p, "R", hy, hz, hy + 0.05, 0.0)
        tuck(p, 1 - keys(t, [(0.66, 0), (0.78, 1)]))
    lean = keys(t, [(0.15, 0), (0.4, 1), (0.6, 1), (0.74, 0.1)])
    p.add("Spine", rx=18 * lean); p.add("Spine1", rx=12 * lean); p.add("Head", rx=-14 * lean)
    reach = keys(t, [(0.25, 0), (0.4, 1), (0.6, 1), (0.7, 0)])
    p.both("Arm", rx=-70 * reach, ry=-10 * reach)    # руки на спинку
    p.both("ForeArm", rz=-20 * reach)
    p.both("Arm", rx=-40 * land, rz=-25 * land)      # присел, обхватил колени
    p.both("ForeArm", rz=-70 * land)
    p.add("Hips", rz=180 * keys(t, [(0.8, 0), (0.94, 1)]))   # за спинкой — лицом к зрителю
    p.add("Head", rx=6 * land)
    return p

@anim("hide_climb", 60, loop=False)
def a_hide_climb(t):
    """За мешки / коробки (1.1–1.3 м): лицом к ним — руки наверх, подтянулся, лёг животом
    и перевалился кувырком на ту сторону, ноги мелькнули в воздухе. Передняя грань — 0.43 м, задняя — 1.0 м."""
    p = stand(0, 0.0)
    # таз переваливается через задний край, голова сразу вниз: за мешками всего 0.5 м до стены
    hy = keys(t, [(0, 0), (0.14, 0.2), (0.34, 0.5), (0.5, 0.7), (0.62, 0.85), (0.75, 1.02), (0.85, 1.06)])
    hz = keys(t, [(0, 0), (0.1, -0.08), (0.2, 0.3), (0.34, 0.6), (0.5, 0.7), (0.62, 0.68), (0.75, 0.56), (0.85, 0.25)])
    p.move(y=-hy, z=hz)
    pitch = keys(t, [(0.14, 0), (0.34, 55), (0.5, 80), (0.62, 135), (0.75, 165), (0.85, 175)])
    p.add("Hips", rx=pitch)
    p.both("UpLeg", rx=-0.25 * pitch)                # ноги не по оси тела — болтаются
    kick = keys(t, [(0.2, 0), (0.3, 1), (0.6, 1), (0.75, 0)])
    w = S(t * 6)
    p.side("L", "UpLeg", rx=-20 * kick * w); p.side("R", "UpLeg", rx=20 * kick * w)   # дрыгает ногами
    p.both("Leg", rx=25 + 35 * kick * (0.5 + 0.5 * w))
    p.both("Foot", rx=25 * kick)
    up = keys(t, [(0, 0), (0.14, 1), (0.5, 1), (0.62, 0)])
    p.both("Arm", rx=-150 * up, ry=-20 * up)         # руки вверх — на мешки
    p.both("ForeArm", rz=-15 * up)
    roll = keys(t, [(0.55, 0), (0.7, 1)])
    p.both("Arm", rx=-80 * roll, ry=10 * roll)       # руки вперёд — встречает пол
    p.add("Head", rx=-35 * keys(t, [(0.1, 0), (0.3, 1), (0.6, 0)]) + 20 * roll)
    return p

@anim("hide_hood", 48, loop=False)
def a_hide_hood(t):
    """За машину: разбег и «прыжок через капот» как в боевике — сел бедром на капот (0.88 м),
    проехал поперёк (1.9 м), спрыгнул за машину лицом к зрителю и присел. Капот — в 0.34 м впереди."""
    p = stand(0, 0.0)
    hy = keys(t, [(0, 0), (0.16, 0.2), (0.3, 0.6), (0.6, 2.05), (0.76, 2.62)])
    hz = keys(t, [(0, 0), (0.12, -0.1), (0.2, 0.02), (0.28, 0.32), (0.6, 0.3), (0.7, 0.12), (0.76, 0.0), (0.86, -0.42)])
    p.move(y=-hy, z=hz)
    run = keys(t, [(0, 1), (0.16, 1), (0.22, 0)])
    if t < 0.22:                                      # два быстрых шага
        p.side("L", "UpLeg", rx=-30 * S(t / 0.22) * run); p.side("R", "UpLeg", rx=30 * S(t / 0.22) * run)
        p.side("L", "Leg", rx=30 * max(0.0, C(t / 0.22)) * run); p.side("R", "Leg", rx=30 * max(0.0, -C(t / 0.22)) * run)
    sit = keys(t, [(0.2, 0), (0.3, 1), (0.6, 1), (0.72, 0)])
    p.both("UpLeg", rx=-82 * sit)                    # сидит на капоте, ноги вперёд
    p.both("Leg", rx=18 * sit)
    p.both("Foot", rx=-10 * sit)
    p.add("Spine", rx=-10 * sit)                     # откинулся назад
    turn = keys(t, [(0.18, 0), (0.32, -90), (0.6, -110), (0.76, -180)])
    p.add("Hips", rz=turn)
    p.side("R", "Arm", rx=30 * sit, ry=20 * sit)     # правая — опора на капот
    p.side("L", "Arm", ry=-60 * sit, rx=-20 * sit)   # левая — в сторону, для равновесия
    p.side("L", "ForeArm", rz=-30 * sit)
    land = keys(t, [(0.72, 0), (0.86, 1)])
    if t > 0.7:
        for s in ("L", "R"):
            foot_at(p, s, 0.0, hz, 0.03, 0.0)
    p.add("Spine", rx=30 * land); p.add("Head", rx=-10 * land)
    p.both("Arm", rx=-35 * land, rz=-25 * land)
    p.both("ForeArm", rz=-65 * land)
    p.add("Head", rz=25 * S(keys(t, [(0.86, 0), (1, 1)], ease=lambda f: f)))   # выглядывает
    return p

# ---------------------------------------------------------------- победный танец
def moonwalk(p, ph, amp=1.0):
    """Лунная походка: колено согнуто и пятка поднята у одной ноги, другая прямая скользит назад; ph — фаза двух шагов."""
    for s, sh in (("L", 0.0), ("R", 0.5)):
        q = (ph + sh) % 1.0
        bent = keys(q, [(0, 0), (0.06, 1), (0.44, 1), (0.5, 0)], ease=smooth) if q < 0.5 else 0.0
        if q < 0.5:                                   # на носке: относительно тела едет вперёд
            th = lerp(16, -10, q / 0.5)
        else:                                         # прямая: скользит назад
            th = lerp(-10, 16, (q - 0.5) / 0.5)
        kn = 42 * bent
        p.side(s, "UpLeg", rx=th * amp - 8 * bent)
        p.side(s, "Leg", rx=kn + 2)
        p.side(s, "Foot", rx=(-th * amp - kn) * (1 - bent) + (36 - th * amp - kn + 8) * bent)
    p.move(z=-0.02)

@anim("dance", 210)
def a_dance(t):
    """Победный танец в духе поп-короля 80-х (7 с, по кругу): поза «рука на козырьке», лунная походка
    в профиль, оборот на носке, стойка на носках, мах ногой с рукой вверх, скользящий шаг вбок обратно."""
    p = stand(t * 7, 0.3)
    x0 = 0.45                                         # центр: уходит влево и возвращается
    # --- путь и разворот
    mw = keys(t, [(0.12, 0), (0.45, 1)], ease=lambda f: f)
    glide = keys(t, [(0.74, 0), (0.92, 1)], ease=lambda f: f)
    p.move(x=x0 - 0.9 * mw + 0.9 * glide)
    rz = keys(t, [(0.07, 0), (0.12, 90), (0.45, 90), (0.54, 360), (1.0, 360)])
    p.add("Hips", rz=rz)
    # --- поза «рука на козырьке» (начало и конец цикла)
    hat = keys(t, [(0, 1), (0.08, 1), (0.12, 0), (0.55, 0), (0.6, 1), (0.66, 1), (0.7, 0), (0.92, 0), (0.97, 1), (1, 1)])
    arm_pose(p, "R", BRIM, hat)
    p.add("Head", rx=16 * hat, rz=-10 * hat)
    p.side("L", "Arm", ry=-20 * hat, rx=-10 * hat)   # левая чуть в сторону
    pop = keys(t, [(0.0, 0), (0.04, 1), (0.08, 0)])  # «щелчок» коленом
    p.side("R", "UpLeg", rx=-12 * pop, ry=8 * pop); p.side("R", "Leg", rx=24 * pop); p.side("R", "Foot", rx=20 * pop)
    # --- лунная походка
    if 0.12 <= t < 0.45:
        moonwalk(p, (t - 0.12) / 0.33 * 2.0)
        p.add("Spine", rx=6); p.add("Head", rx=-4)
        sw = S((t - 0.12) / 0.33 * 2.0)
        p.both("Arm", rx=-10, ry=-6); p.both("ForeArm", rz=-40)
        p.side("L", "Arm", rx=10 * sw); p.side("R", "Arm", rx=-10 * sw)
    # --- оборот на носке
    spin = keys(t, [(0.45, 0), (0.47, 1), (0.53, 1), (0.55, 0)])
    p.side("R", "Arm", ry=-110 * spin, rx=-20 * spin)
    p.side("L", "Arm", rx=-40 * spin, rz=-40 * spin); p.side("L", "ForeArm", rz=-90 * spin)
    p.side("L", "UpLeg", rx=-35 * spin); p.side("L", "Leg", rx=60 * spin)      # левая нога поджата
    p.side("R", "Foot", rx=25 * spin); p.move(z=0.03 * spin)
    # --- стойка на носках
    toe = keys(t, [(0.55, 0), (0.58, 1), (0.63, 1), (0.66, 0)])
    p.both("Foot", rx=48 * toe); p.both("Leg", rx=22 * toe); p.both("UpLeg", rx=-12 * toe, ry=4 * toe)
    p.move(z=0.06 * toe); p.add("Spine", rx=8 * toe)
    # --- мах ногой и рука вверх
    kick = keys(t, [(0.66, 0), (0.69, 1), (0.71, 0.3), (0.73, 1), (0.76, 0)])
    point = keys(t, [(0.66, 0), (0.69, 1), (0.74, 1), (0.78, 0)])
    p.side("R", "UpLeg", rx=-55 * kick, ry=-12 * kick); p.side("R", "Leg", rx=55 * (1 - kick) * point)
    p.side("R", "Arm", ry=-140 * point, rx=-30 * point)
    p.side("L", "Arm", ry=-30 * point, rx=-30 * point); p.side("L", "ForeArm", rz=-100 * point)
    p.add("Head", rx=-18 * point, rz=12 * point)     # «и-хи!»
    p.add("Spine2", rx=-8 * point)
    # --- скользящий шаг вбок, обратно на середину
    if 0.74 <= t < 0.92:
        g = (t - 0.74) / 0.18 * 3.0
        for s, sh in (("L", 0.0), ("R", 0.5)):
            u = max(0.0, S(g + sh))
            p.side(s, "Leg", rx=30 * u); p.side(s, "UpLeg", rx=-12 * u); p.side(s, "Foot", rx=28 * u)
        p.add("Hips", ry=4 * S(g)); p.add("Head", rz=-8 * S(g * 0.5))
        p.both("Arm", rx=-8, ry=-4); p.both("ForeArm", rz=-55)
        p.both("Shoulder", ry=-4 * abs(S(g)))
    return p

# ---------------------------------------------------------------- кисти по клипам
def h_sneak(p, t):
    hand(p, "B", "claw")

def h_search(p, t):
    hand(p, "R", "claw", 0.6 + 0.4 * S(t * 3))
    hand(p, "L", "flat", 0.6)

def h_take(p, t):
    hand(p, "R", "spread", keys(t, [(0, 0), (0.2, 1), (0.3, 0)]))
    hand(p, "R", "bottle", keys(t, [(0.25, 0), (0.35, 1)]))

def h_swap(p, t):
    hand(p, "R", "bottle"); hand(p, "L", "bottle")

def h_success(p, t):
    hand(p, "R", "bottle")
    hand(p, "L", "fist", keys(t, [(0.4, 0), (0.5, 1)]))

def h_laugh(p, t):
    hand(p, "L", "fist", 0.6)
    hand(p, "R", "spread", 0.5)

def h_caught(p, t):
    hand(p, "B", "spread", keys(t, [(0, 0), (0.1, 1), (0.45, 1), (0.6, 0.4)]))

def h_hide_hug(p, t):
    hand(p, "B", "fist", keys(t, [(0.6, 0), (1, 0.6)]))

def h_hide_door(p, t):
    hand(p, "R", "handle", keys(t, [(0.05, 0), (0.12, 1), (0.25, 1), (0.32, 0)]))
    hand(p, "L", "handle", keys(t, [(0.82, 0), (0.92, 1)]))

def h_hide_curtain(p, t):
    hand(p, "L", "handle", keys(t, [(0.05, 0), (0.12, 1), (0.35, 1), (0.45, 0)]))
    hand(p, "R", "handle", keys(t, [(0.72, 0), (0.82, 1)]))

def h_hide_bed(p, t):
    hand(p, "B", "flat", keys(t, [(0.3, 0), (0.5, 1)]))

def h_hide_skis(p, t):
    hand(p, "B", "flat", keys(t, [(0.4, 0), (0.7, 1)]))

def h_hide_table(p, t):
    hand(p, "B", "flat", keys(t, [(0.12, 0), (0.28, 1)]))

def h_hide_over(p, t):
    hand(p, "B", "handle", keys(t, [(0.3, 0), (0.4, 1), (0.6, 1), (0.68, 0)]))
    hand(p, "B", "fist", keys(t, [(0.72, 0), (0.9, 0.6)]))

def h_hide_climb(p, t):
    hand(p, "B", "spread", keys(t, [(0.05, 0), (0.15, 1), (0.6, 1), (0.7, 0.5)]))

def h_hide_hood(p, t):
    hand(p, "B", "flat", keys(t, [(0.2, 0), (0.3, 1), (0.62, 1), (0.72, 0)]))
    hand(p, "B", "fist", keys(t, [(0.8, 0), (0.95, 0.6)]))

def point_finger(p, s, k):
    """Кулак с вытянутым указательным."""
    hand(p, s, "fist", k)
    p.side(s, "HandIndex1", ry=-76 * k); p.side(s, "HandIndex2", ry=-82 * k); p.side(s, "HandIndex3", ry=-60 * k)

def h_dance(p, t):
    hat = keys(t, [(0, 1), (0.08, 1), (0.12, 0), (0.55, 0), (0.6, 1), (0.66, 1), (0.7, 0), (0.92, 0), (0.97, 1), (1, 1)])
    hand(p, "R", "handle", hat)
    point_finger(p, "R", keys(t, [(0.66, 0), (0.69, 1), (0.74, 1), (0.78, 0)]))
    hand(p, "L", "spread", keys(t, [(0.45, 0), (0.48, 1), (0.53, 1), (0.56, 0)]))
    hand(p, "L", "fist", 0.5 * keys(t, [(0.12, 0), (0.16, 1), (0.42, 1), (0.45, 0)]))

HAND_LAYER = {"sneak": h_sneak, "search_low": h_search, "search_mid": h_search, "take": h_take,
              "swap": h_swap, "success": h_success, "laugh": h_laugh, "caught": h_caught,
              "hide_table": h_hide_table, "hide_sofa": h_hide_hug, "hide_wardrobe": h_hide_door,
              "hide_curtain": h_hide_curtain, "hide_bed": h_hide_bed, "hide_skis": h_hide_skis,
              "hide_over": h_hide_over, "hide_climb": h_hide_climb, "hide_hood": h_hide_hood, "dance": h_dance}

# ---------------------------------------------------------------- решатель: руки к целям
def grip_cost(side, target, palm=None, axis=None, wp=200, wa=200):
    """Центр хвата руки side — в точке target; ладонь (нормаль) смотрит в palm; ось хвата — в axis."""
    n = side + "HandGrip"
    head, ax = bone_rest(n)
    def cost():
        c = posed_point(n, head)
        v = ((c - Vector(target)).length * 100) ** 2
        if palm is not None:
            v += wp * (1 - posed_dir(side + "Hand", (0, 0, -1)).dot(Vector(palm).normalized()))
        if axis is not None:
            v += wa * (1 - posed_dir(n, ax).dot(Vector(axis).normalized()))
        return v
    return cost

def mouth_cost():
    """Кулак у рта: тыльная часть пальцев (точка ладони) — перед губами."""
    head, _ = bone_rest("LeftHandPhone")
    c = posed_point("LeftHandPhone", head)
    m = posed_point("Head", MOUTH) + Vector((0, -0.05, -0.01))
    face = (posed_point("Head", MOUTH) - c).normalized()
    return ((c - m).length * 100) ** 2 + 150 * (1 - posed_dir("LeftHand", (0, 0, -1)).dot(face))

solve_thumbs()
ARM_STARTS = [
    {"Arm": [-40, 20, -30], "ForeArm": [60, 0, -100], "Hand": [0, 0, 0]},
    {"Arm": [-70, -20, -10], "ForeArm": [-40, 0, -40], "Hand": [0, 20, 0]},
    {"Arm": [-20, -120, -10], "ForeArm": [40, 0, -30], "Hand": [0, -30, 0]},
]
solve_starts("reachLo", REACH_LOW, at(a_search_low, h_search, 0.0),
             grip_cost("Right", (-0.12, -0.40, 0.42), palm=(0, 0, -1), wp=150), ARM_STARTS)
solve_starts("reachMid", REACH_MID, at(a_search_mid, h_search, 0.0),
             grip_cost("Right", (-0.12, -0.50, 0.98), palm=(0, -0.3, -1), wp=150), ARM_STARTS)
solve_starts("chest", HOLD_CHEST, at(a_swap, None, 0.0),
             grip_cost("Right", (-0.07, -0.33, 1.02), palm=(0.3, 0, 1), axis=(0, 0, 1), wp=120, wa=150), ARM_STARTS)
solve_starts("up", HOLD_UP, at(a_success, None, 0.6),
             grip_cost("Right", (-0.38, -0.08, 1.58), axis=(0, 0, 1), wa=120), ARM_STARTS)   # вбок над плечом: кепка крупная
solve_starts("mouthL", MOUTH_L, at(a_laugh, None, 0.0), mouth_cost, ARM_STARTS)
solve_starts("door", DOOR, at(a_hide_wardrobe, None, 0.12),
             grip_cost("Right", (-0.20, -0.48, 1.0), palm=(1, 0, 0), wp=100), ARM_STARTS)

def brim_cost():
    """Пальцы правой — на козырьке (голова в позе наклонена, поэтому точка — от позы головы)."""
    head, _ = bone_rest("RightHandGrip")
    c = posed_point("RightHandGrip", head)
    return ((c - posed_point("Head", BRIM_PT)).length * 100) ** 2 + 60 * (1 - posed_dir("RightHand", (0, 0, -1)).dot(Vector((0, 0.3, -1)).normalized()))
solve_starts("brim", BRIM, at(a_dance, h_dance, 0.02), brim_cost, ARM_STARTS + [
    {"Arm": [-90, -60, -40], "ForeArm": [0, 0, -130], "Hand": [0, 0, 0]}])

record(HAND_LAYER)
export(DST, BLEND)
