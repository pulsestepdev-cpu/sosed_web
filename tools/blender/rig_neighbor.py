# Сосед: модель из Tripo в T-позе -> скелет, веса, все анимации -> один GLB.
# blender -b -P tools/blender/rig_neighbor.py -- <neighbor_tpose.glb> <выход.glb> [сохранить.blend]
# Общий механизм (осям углов, кистям, решателю) — в rig_core.py; здесь точки тела и анимации соседа.
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rig_core import *
import rig_core as rc

SRC, DST, BLEND = args()
load_model(SRC, 1.75)

# ---------------------------------------------------------------- скелет
# точки сняты по срезам сетки (рост 1.75): плечи на 1.24, локоть x≈0.50, запястье x≈0.72,
# тазобедренный 0.72, колено 0.39, щиколотка 0.10
CENTER = [  # имя, голова, хвост, родитель
    ("Hips",   (0, 0.03, 0.74), (0, 0.03, 0.86), None),
    ("Spine",  (0, 0.03, 0.86), (0, 0.04, 0.98), "Hips"),
    ("Spine1", (0, 0.04, 0.98), (0, 0.05, 1.10), "Spine"),
    ("Spine2", (0, 0.05, 1.10), (0, 0.05, 1.32), "Spine1"),
    ("Neck",   (0, 0.05, 1.32), (0, 0.03, 1.44), "Spine2"),
    ("Head",   (0, 0.03, 1.44), (0, 0.03, 1.76), "Neck"),
    ("Belly",  (0, -0.02, 0.88), (0, -0.20, 0.88), "Spine"),
]
SIDE = [  # для левой стороны (+X); правая — зеркально
    ("Shoulder", (0.04, 0.05, 1.28), (0.22, 0.06, 1.24), "Spine2"),
    ("Arm",      (0.22, 0.06, 1.24), (0.50, 0.06, 1.225), "Shoulder"),
    ("ForeArm",  (0.50, 0.06, 1.225), (0.72, 0.05, 1.21), "Arm"),
    ("Hand",     (0.72, 0.05, 1.21), (0.787, 0.035, 1.21), "ForeArm"),
    ("UpLeg",    (0.12, 0.04, 0.72), (0.14, 0.05, 0.39), "Hips"),
    ("Leg",      (0.14, 0.05, 0.39), (0.16, 0.08, 0.10), "UpLeg"),
    ("Foot",     (0.16, 0.08, 0.10), (0.19, -0.06, 0.03), "Leg"),
    ("ToeBase",  (0.19, -0.06, 0.03), (0.20, -0.14, 0.03), "Foot"),
]
# Пальцы (по срезам кисти: ладонь вниз, большой палец смотрит вперёд, в -Y)
FINGERS = {  # имя: (костяшка, кончик)
    "Index":  ((0.785, -0.010, 1.210), (0.862, -0.013, 1.203)),
    "Middle": ((0.790, 0.023, 1.212), (0.880, 0.023, 1.203)),
    "Ring":   ((0.785, 0.058, 1.210), (0.877, 0.061, 1.202)),
    "Pinky":  ((0.780, 0.088, 1.205), (0.856, 0.095, 1.200)),
}
THUMB = [(0.725, 0.005, 1.195), (0.750, -0.035, 1.185), (0.765, -0.058, 1.183), (0.780, -0.075, 1.183)]
build_skeleton(CENTER, SIDE, FINGERS, THUMB,
               grip=((0.805, 0.035, 1.15), (0.805, -0.045, 1.15)),
               phone=((0.778, 0.02, 1.1665), (0.858, 0.02, 1.1665)))
make_weights()
# Живот: вся передняя часть пуза — на кости Belly (тепловая карта отдаёт её позвоночнику),
# чтобы живот целиком сплющивался о пол и колыхался.
def belly_k(co):
    x, y, z = co
    if y > 0.0 or abs(x) > 0.30 or not 0.62 < z < 1.16:
        return 0.0
    return smooth((-y - 0.02) / 0.12) * smooth(min(z - 0.62, 1.16 - z) / 0.12) * smooth((0.30 - abs(x)) / 0.12)
boost_group("Belly", belly_k)
report_weights()

def stand(t=0.0, breath=1.0):
    """Базовая стойка: руки опущены (живот мешает прижать), лёгкое дыхание."""
    p = Pose()
    b = S(t) * breath
    p.both("Arm", rx=-4, ry=64, rz=0)
    p.both("ForeArm", rz=-14)
    p.both("Hand", rz=-6)
    hand(p, "B", "relax", base="flat")
    p.both("Shoulder", ry=2 - 1.2 * b)
    p.both("UpLeg", rx=-2, ry=-1)
    p.both("Leg", rx=3)
    p.both("Foot", rx=-1)
    p.add("Spine", rx=-3 - 0.6 * b)
    p.add("Spine2", rx=-1 - 0.8 * b)
    p.add("Head", rx=3)
    p.belly = 0.5 + 0.5 * b
    return p

def lie_back_pose(p, k=1.0):
    """Поза лёжа на спине (k = 0..1 — насколько уже лёг)."""
    p.add("Hips", rx=-90 * k)
    p.move(y=0.25 * k, z=-0.52 * k)
    return p

def lie_front_pose(p, k=1.0):
    """Лёжа на животе: живот сплющивается о пол (не держит тело, как мяч), грудь и щека на полу."""
    p.add("Hips", rx=88 * k)
    p.move(y=-0.25 * k, z=-0.595 * k)
    p.squash += max(0.0, k)
    return p



@anim("idle", 90)
def a_idle(t):
    p = stand(t)
    p.move(x=0.008 * S(t))
    p.add("Hips", ry=-1.2 * S(t))
    p.add("Spine1", ry=1.0 * S(t))
    p.add("Head", rz=5 * S(t * 0.5 + 0.1), rx=1.5 * S(t * 2))
    p.both("Arm", rx=2 * S(t))
    return p

def walk_pose(t, drunk=0.0):
    p = stand(t * 2, breath=0.3)
    ph = t
    sw = S(ph)                      # >0 — левая нога впереди
    for s, sh in (("L", 0.0), ("R", 0.5)):
        x = S(ph + sh)              # вынос ноги вперёд
        c = C(ph + sh)              # >0 — нога в переносе
        p.side(s, "UpLeg", rx=-22 * x, ry=-3 - 4 * drunk)
        p.side(s, "Leg", rx=6 + 38 * max(0.0, c) ** 1.5)
        p.side(s, "Foot", rx=-14 * x + 10 * max(0.0, -c) * max(0.0, -x))
        p.side(s, "Arm", rx=16 * x * (1 - 0.5 * drunk), ry=-4 * drunk)
        p.side(s, "ForeArm", rz=-14 - 10 * max(0.0, -x))
    p.move(x=0.03 * sw, z=-0.006 - 0.034 * sw * sw)  # переваливается с ноги на ногу
    p.add("Hips", ry=-4 * sw, rz=6 * sw)
    p.add("Spine", rz=-4 * sw, rx=2)
    p.add("Spine2", rz=-4 * sw, ry=3 * sw)
    p.add("Head", rz=3 * sw, ry=-3 * sw)
    p.belly = 0.5 + 0.5 * S(2 * ph + 0.15)   # живот потряхивает в такт шагам
    return p

@anim("walk", 32)
def a_walk(t):
    return walk_pose(t)

@anim("walk_drunk", 48)
def a_walk_drunk(t):
    p = walk_pose(t, drunk=1.0)
    w = S(t) + 0.35 * S(2 * t + 0.3)    # шатает неравномерно
    p.move(x=0.05 * w)
    p.add("Hips", ry=6 * w)
    p.add("Spine", ry=-8 * w, rx=6)
    p.add("Spine2", ry=-6 * w)
    p.add("Head", ry=10 * S(t + 0.2), rx=10 + 5 * S(2 * t))
    p.both("Arm", ry=-16, rx=-6)       # руки в стороны — ловит равновесие
    p.side("L", "Arm", ry=8 * w); p.side("R", "Arm", ry=-8 * w)
    return p

# Начальные углы для решателя (он их уточняет перед записью анимаций).
DRINK = {"Arm": [-62.0, 10.0, -38.0], "ForeArm": [0.0, 0.0, -110.0], "Hand": [0.0, -15.0, 10.0]}
# поза подъёма (рука поднята, ещё не запрокинул): бутылка стоймя перед грудью; от неё — к DRINK
DRINK_LIFT = {"Arm": [-52.0, 18.0, -38.0], "ForeArm": [0.0, 0.0, -100.0], "Hand": [0.0, 10.0, 10.0]}
# поднёс горлышко к губам, бутылка почти горизонтально, голова ещё прямо
DRINK_APPROACH = {"Arm": [-80.0, 15.0, -38.0], "ForeArm": [30.0, 0.0, -60.0], "Hand": [0.0, -10.0, -20.0]}
PHONE = {"Arm": [-26.0, 10.0, -18.0], "ForeArm": [0.0, 0.0, -92.0], "Hand": [0.0, -10.0, 8.0]}
BULB = {"Arm": [-10.0, -140.0, -10.0], "ForeArm": [0.0, 0.0, -20.0], "Hand": [0.0, 0.0, 0.0]}

def drink_phase(t):
    """0 — рука опущена, 1 — бутылка у груди, 2 — горлышко у губ, 3 — пьёт запрокинув."""
    return keys(t, [(0, 0), (0.18, 1), (0.27, 2), (0.37, 3), (0.68, 3), (0.76, 2), (0.84, 1), (0.96, 0)])

@anim("drink", 90)
def a_drink(t):
    p = stand(t)
    ph = drink_phase(t)
    tilt = max(0.0, min(1.0, ph - 2))
    gulp = S(t * 6) * tilt
    # правая рука: опущена -> у груди -> у губ -> запрокинул; позы подбирает solve()
    stages = [None, DRINK_LIFT, DRINK_APPROACH, DRINK]
    i = min(2, int(ph)); f = ph - i
    for b in ("Arm", "ForeArm", "Hand"):
        a0 = stages[i][b] if stages[i] else [0.0, 0.0, 0.0]
        p.side("R", b, *[lerp(a0[k], stages[i + 1][b][k], f) for k in range(3)])
    p.add("Head", rx=-24 * tilt + 2 * gulp)
    p.add("Neck", rx=-10 * tilt)
    p.add("Spine2", rx=-6 * tilt)
    # левая гладит живот
    p.side("L", "Arm", rx=-22, ry=12, rz=-12)
    p.side("L", "ForeArm", rz=-62 + 6 * S(t * 3))
    after = keys(t, [(0.72, 0), (0.85, 1), (0.95, 0)])   # «а-а-ах»
    p.both("Shoulder", ry=-6 * after)
    p.add("Head", rx=-6 * after)
    p.belly += 0.6 * tilt
    return p

@anim("work", 60)
def a_work(t):
    """Шпаклюет стену перед собой: правая рука со шпателем ходит вверх-вниз."""
    p = stand(t, breath=0.4)
    st = S(t * 2)          # два мазка за цикл
    p.add("Spine", rx=6)
    p.add("Spine1", rz=10 + 4 * st)
    p.side("R", "Arm", rx=-62 - 22 * st, ry=4, rz=-8)
    p.side("R", "ForeArm", rz=-30 + 10 * st)
    p.side("R", "Hand", ry=25)
    p.side("R", "Shoulder", ry=-4 - 4 * max(0.0, st))
    # левая держит ведро/мастерок у пояса
    p.side("L", "Arm", rx=-30, ry=6, rz=-6)
    p.side("L", "ForeArm", rz=-80)
    p.add("Head", rx=-6 - 6 * st, rz=8)
    p.move(z=-0.008 - 0.008 * st)
    p.both("Leg", rx=6)
    return p

@anim("bulb", 60)
def a_bulb(t):
    """Меняет лампочку: правая снизу держит лампочку над головой и вкручивает — поворот кисти,
    перехват, снова поворот. Левая держится за стремянку."""
    p = stand(t, breath=0.4)
    p.add("Spine", rx=-6); p.add("Spine2", rx=-6)
    p.add("Head", rx=-32, rz=-8)
    for b in ("Arm", "ForeArm", "Hand"):     # углы в BULB подбирает solve(): ладонь под лампочкой
        p.side("R", b, *BULB[b])
    p.side("R", "ForeArm", rx=bulb_twist(t))  # проворот предплечья = вращение лампочки
    p.side("L", "Arm", rx=-45, ry=12, rz=-8)
    p.side("L", "ForeArm", rz=-45)
    return p

def bulb_u(t):
    return (t * 3) % 1.0                      # три оборота за клип

def bulb_twist(t):
    u = bulb_u(t)
    # 0..0.6 крутит (пальцы сжаты), 0.6..0.72 разжимает, 0.72..1 возвращает кисть назад
    return keys(u, [(0, -35), (0.6, 35), (0.72, 35), (1, -35)])

@anim("phone", 60)
def a_phone(t):
    """Телефон в правой руке у груди экраном к лицу, большой палец листает; левая на животе."""
    p = stand(t, breath=0.6)
    for b in ("Arm", "ForeArm", "Hand"):     # углы в PHONE подбирает solve(): телефон экраном к глазам
        p.side("R", b, *PHONE[b])
    p.side("L", "Arm", rx=-22, ry=12, rz=-12)
    p.side("L", "ForeArm", rz=-62)
    p.add("Head", rx=22 + 2 * S(t * 2), rz=-8 + 3 * S(t))
    p.add("Neck", rx=8)
    p.add("Spine2", rx=6)
    laugh = keys(t, [(0, 0), (0.55, 0), (0.62, 1), (0.85, 1), (0.95, 0)])   # хмыкает
    p.both("Shoulder", ry=-4 * laugh * (0.5 + 0.5 * S(t * 12)))
    return p

@anim("kick", 48)
def a_kick(t):
    """«Тренер»: стойка, лоу-кик правой, назад в стойку, подпрыгивает."""
    p = stand(t, breath=0.0)
    guard_fists(p)
    k = keys(t, [(0, 0), (0.18, 0.4), (0.32, 1), (0.42, 1), (0.6, 0), (1, 0)])
    chamber = keys(t, [(0, 0), (0.18, 1), (0.3, 0.3), (0.45, 0.6), (0.6, 0), (1, 0)])
    p.add("Hips", rz=28 * k)
    p.add("Spine1", rz=-14 * k, ry=6 * k)
    p.add("Head", rz=-12 * k)
    p.side("R", "UpLeg", rx=-48 * k - 20 * chamber, ry=-22 * k)
    p.side("R", "Leg", rx=70 * chamber + 6)
    p.side("R", "Foot", rx=25 * k)
    p.side("L", "UpLeg", rx=-6 * k, rz=-20 * k)
    p.side("L", "Leg", rx=14 * k)
    p.side("L", "Foot", rx=8 * k)
    hop = abs(S(t * 2)) * keys(t, [(0, 1), (0.1, 0), (0.62, 0), (0.75, 1), (1, 1)])
    p.move(z=0.02 * hop - 0.03 * k)
    p.both("Leg", rx=8)
    p.belly = 0.5 + 0.5 * S(t * 4)
    return p

def guard_fists(p, k=1.0):
    p.both("Arm", rx=-42 * k, ry=-2 * k, rz=-12 * k)
    p.both("ForeArm", rz=-122 * k)
    p.both("Hand", rz=-20 * k)
    p.add("Spine", rx=6 * k)
    p.add("Head", rx=6 * k)
    p.both("UpLeg", ry=-3 * k)
    p.both("Leg", rx=10 * k)

@anim("angry", 60)
def a_angry(t):
    """«Да ну нахуй!»: замах обеими, топает, трясёт кулаками."""
    p = stand(t, breath=0.0)
    raise_ = keys(t, [(0, 0), (0.15, -0.25), (0.3, 1), (0.42, 1), (0.52, -0.2), (0.62, 0)])
    shake = keys(t, [(0.5, 0), (0.62, 1), (0.92, 1), (1, 0)])
    stomp = keys(t, [(0.3, 0), (0.42, 1), (0.5, 0)])
    p.both("Arm", ry=-140 * raise_, rx=-15 * raise_)
    p.both("ForeArm", rz=-30 * abs(raise_))
    p.add("Head", rx=-22 * raise_)
    p.add("Spine2", rx=-10 * raise_)
    p.add("Spine", rx=12 * stomp)
    p.side("R", "UpLeg", rx=-40 * stomp)
    p.side("R", "Leg", rx=70 * stomp)
    p.move(z=-0.03 * keys(t, [(0.45, 0), (0.5, 1), (0.6, 0)]))
    # трясёт кулаками перед грудью
    s = S(t * 10) * shake
    p.both("Arm", rx=-40 * shake, rz=-12 * shake, ry=-8 * shake)
    p.both("ForeArm", rz=-105 * shake + 12 * s)
    p.both("Hand", rz=-20 * shake)
    p.add("Head", rx=8 * shake + 4 * s, rz=6 * s)
    p.add("Spine", rx=8 * shake)
    p.belly += 0.5 * s
    return p

@anim("suspicious", 90)
def a_suspicious(t):
    """«Э… Кто здесь?»: ладонь козырьком, оглядывается."""
    p = stand(t, breath=0.5)
    look = keys(t, [(0, 0), (0.15, 1), (0.4, 1), (0.55, -1), (0.8, -1), (1, 0)])
    hand = keys(t, [(0, 0), (0.12, 1), (0.9, 1), (1, 0)])
    p.add("Head", rz=40 * look, rx=-4)
    p.add("Spine1", rz=12 * look)
    p.add("Spine", rx=8 * hand)
    p.side("R", "Arm", rx=-55 * hand, ry=-18 * hand, rz=-30 * hand)
    p.side("R", "ForeArm", rz=-110 * hand)
    p.side("R", "Hand", ry=20 * hand)
    p.both("Leg", rx=6 * hand)
    return p

@anim("catch", 45, loop=False)
def a_catch(t):
    """«А ну пошёл отсюда!»: выпад, хватает обеими, швыряет вбок."""
    p = stand(t, breath=0.0)
    lunge = keys(t, [(0, 0), (0.25, 1), (0.5, 1), (0.8, 0.3), (1, 0)])
    grab = keys(t, [(0, 0), (0.2, 1), (0.45, 1), (0.55, 0.6), (0.8, 0), (1, 0)])
    throw = keys(t, [(0.4, 0), (0.6, 1), (0.8, 1), (1, 0)])
    p.add("Spine", rx=18 * lunge)
    p.add("Spine1", rz=35 * throw - 10 * lunge)
    p.add("Hips", rz=10 * throw)
    p.side("R", "UpLeg", rx=-35 * lunge)
    p.side("R", "Leg", rx=30 * lunge)
    p.side("L", "UpLeg", rx=18 * lunge)
    p.move(y=-0.12 * lunge, z=-0.06 * lunge)
    p.both("Arm", rx=-70 * grab, ry=-10 * grab, rz=-10 * grab)
    p.both("ForeArm", rz=-40 * grab)
    p.side("L", "Arm", rx=-30 * throw, ry=-20 * throw)
    p.side("R", "Arm", rx=20 * throw, ry=20 * throw)
    p.add("Head", rx=-10 * grab, rz=-20 * throw)
    return p

@anim("oath", 75, loop=False)
def a_oath(t):
    """«Всё, сегодня больше не пью!»: рука на груди, правая клятвенно вверх, рубит воздух."""
    p = stand(t)
    raise_ = keys(t, [(0, 0), (0.2, 1), (0.6, 1), (0.72, 0.4), (0.82, 0.4), (1, 0)])
    chop = keys(t, [(0.6, 0), (0.7, 1), (0.82, 1), (1, 0)])
    chest = keys(t, [(0, 0), (0.15, 1), (0.85, 1), (1, 0)])
    p.side("R", "Arm", ry=-150 * raise_ + 86 * chop, rx=-6 * raise_ - 75 * chop, rz=-10 * raise_)
    p.side("R", "ForeArm", rz=-60 * raise_ + 40 * chop)
    p.side("R", "Hand", rx=-10 * raise_)
    p.side("L", "Arm", rx=-40 * chest, ry=10 * chest, rz=-30 * chest)
    p.side("L", "ForeArm", rz=-115 * chest)
    p.add("Head", rx=-14 * raise_ + 10 * chop)
    p.add("Spine2", rx=-8 * raise_)
    p.belly += 0.5 * raise_            # гордо выпятил живот
    return p

@anim("dance", 64)
def a_dance(t):
    """Пьяный танец под песню: пружинит, крутит тазом, машет руками над головой."""
    p = stand(t * 2, breath=0.0)
    b = S(t * 4)                 # 4 доли за цикл
    sw = S(t * 2)
    p.move(x=0.05 * sw, z=-0.02 - 0.02 * abs(b))
    p.both("Leg", rx=10 + 8 * abs(b))
    p.both("UpLeg", rx=-6 - 4 * abs(b))
    p.add("Hips", ry=8 * sw, rz=10 * S(t * 2 + 0.25))
    p.add("Spine", ry=-10 * sw)
    p.add("Spine2", ry=-6 * sw)
    p.add("Head", ry=14 * S(t * 2 + 0.1), rx=-8 + 6 * b)
    p.side("L", "Arm", ry=-150 + 25 * sw, rx=-10)
    p.side("L", "ForeArm", rz=-15 + 15 * b)
    p.side("R", "Arm", ry=-125 - 25 * sw, rx=-20)
    p.side("R", "ForeArm", rz=-25 - 15 * b)
    p.both("Hand", rz=20 * b)
    p.belly = 0.5 + 0.5 * b
    return p

@anim("fall_back", 42, loop=False)
def a_fall_back(t):
    """Поскользнулся (банан, мыло): ноги вперёд, руки вверх, бух на спину."""
    p = stand(0, breath=0.0)
    slip = keys(t, [(0, 0), (0.22, 1), (0.5, 0.6), (0.75, 0.15), (1, 0)])
    fall = bounce((t - 0.12) / 0.6) if t > 0.12 else 0.0
    p.side("R", "UpLeg", rx=-75 * slip)
    p.side("L", "UpLeg", rx=-30 * slip)
    p.both("Leg", rx=8)
    p.both("Arm", ry=-50 * slip, rx=-30 * slip)
    p.both("ForeArm", rz=-30 * slip)
    p.add("Head", rx=25 * slip)
    p.move(z=0.06 * keys(t, [(0, 0), (0.15, 1), (0.3, 0)]))
    lie_back_pose(p, fall)
    lying_back_limbs(p, smooth((t - 0.45) / 0.5))
    return p

def lying_back_limbs(p, k):
    """Руки и ноги, раскинутые по полу (поверх стойки), k = 0..1."""
    p.both("Arm", ry=-30 * k, rx=24 * k)
    p.both("ForeArm", rz=10 * k)
    p.both("UpLeg", ry=-8 * k, rx=0)
    p.both("Leg", rx=6 * k)
    p.both("Foot", rx=20 * k)
    p.add("Head", rx=-2 * k)
    p.add("Spine", rx=3 * k)

@anim("lie_back", 90)
def a_lie_back(t):
    p = stand(t, breath=0.0)
    lie_back_pose(p)
    lying_back_limbs(p, 1.0)
    p.belly = 0.5 + 0.5 * S(t)
    p.add("Head", rz=6 * S(t * 0.5))
    return p

@anim("sleep", 120)
def a_sleep(t):
    """Спит на спине: руки на животе, живот ходит ходуном (храп)."""
    p = stand(0, breath=0.0)
    lie_back_pose(p)
    lying_back_limbs(p, 1.0)
    p.both("Arm", rx=-40, ry=42, rz=-30)      # кисти на живот (как поза с телефоном)
    p.both("ForeArm", rz=-91)
    snore = keys(t, [(0, 0), (0.45, 1), (0.55, 1), (1, 0)])
    p.belly = 1.4 * snore - 0.2
    p.add("Head", ry=18, rx=-6 + 4 * snore)
    p.add("Spine2", rx=-3 * snore)
    return p

@anim("fall_forward", 50, loop=False)
def a_fall_forward(t):
    """Отключился: качнулся, колени подогнулись, плашмя лицом вперёд (в салат)."""
    p = stand(0, breath=0.0)
    sway = keys(t, [(0, 0), (0.15, 1), (0.3, -0.5), (0.4, 0)])
    buckle = keys(t, [(0.2, 0), (0.42, 1), (0.6, 0.2), (1, 0)])
    fall = bounce((t - 0.3) / 0.55) if t > 0.3 else 0.0
    p.add("Spine", ry=8 * sway, rx=-6 * sway)
    p.add("Head", ry=-15 * sway, rx=20 * buckle)
    p.both("Leg", rx=40 * buckle)
    p.both("UpLeg", rx=-30 * buckle)
    p.move(z=-0.1 * buckle)
    p.both("Arm", ry=10 * buckle)
    lie_front_pose(p, fall)
    k = smooth((t - 0.55) / 0.4)
    p.both("Arm", ry=22 * k, rx=-2 * k)
    p.both("ForeArm", rz=8 * k, rx=-80 * k)
    p.add("Head", rx=18 * k, rz=25 * k)
    p.both("Foot", rx=60 * k)
    return p

# ---------------------------------------------------------------- финал: лицом в салат
# Стоит за столом (столешница 0.77 м, миска с салатом — в ~0.6 м перед ним). Ноги стоят на полу, сгибается
# в поясе, лицо падает в миску. Удар — в момент FACEPLANT_HIT (доля клипа); игра сдвигает соседа так, чтобы
# голова попала в миску, и в этот момент — брызги салата, «ПЛЮХ!», замедление.
FACEPLANT_HIT = 0.6
FACEPLANT_BEND = 78.5     # на столько сгибается: лицо — в салат, а не над ним (проверяет --animcheck)

def faceplant_pose(p, bend, settle=0.0):
    """Согнулся в поясе на bend градусов: бёдра вертикально (стопы на полу), зад чуть назад."""
    p.add("Hips", rx=bend * 0.55)
    p.both("UpLeg", rx=-bend * 0.55 - 6 * settle)
    p.both("Leg", rx=10 + 6 * settle)
    p.both("Foot", rx=-4 - 2 * settle)
    p.add("Spine", rx=bend * 0.2)
    p.add("Spine1", rx=bend * 0.15)
    p.add("Spine2", rx=bend * 0.1)
    p.move(y=0.1 * bend / FACEPLANT_BEND, z=-0.03 * bend / FACEPLANT_BEND - 0.02 * settle)

@anim("faceplant", 60, loop=False)
def a_faceplant(t):
    """Лицом в салат: качнулся, глаза в кучу, колени ватные — и плашмя лицом в миску. Отскок, обмяк."""
    p = stand(0, breath=0.0)
    sway = keys(t, [(0, 0), (0.12, 1), (0.25, -0.7), (0.36, 0.3), (0.42, 0)])
    p.add("Spine", ry=10 * sway, rz=6 * sway)
    p.add("Head", ry=-16 * sway, rz=-10 * sway, rx=8 * abs(sway))
    p.both("Leg", rx=12 * keys(t, [(0.1, 0), (0.3, 1), (0.42, 0.4)]))
    # падение: медленно клонится, потом быстрее (ease-in), удар, отскок, обмяк
    f = keys(t, [(0.36, 0), (FACEPLANT_HIT, 1)], ease=lambda x: x * x)
    bounce_ = keys(t, [(FACEPLANT_HIT, 0), (FACEPLANT_HIT + 0.06, -0.12), (FACEPLANT_HIT + 0.14, 0.04), (FACEPLANT_HIT + 0.22, 0)])
    settle = keys(t, [(FACEPLANT_HIT, 0), (1, 1)])
    faceplant_pose(p, FACEPLANT_BEND * (f + bounce_), settle)
    p.add("Head", rx=14 * f)                                     # лицом, а не лбом
    # руки: висят, при падении — вперёд, после удара шлёпаются на стол по бокам миски и свисают
    fall_arm = keys(t, [(0.4, 0), (FACEPLANT_HIT, 1), (FACEPLANT_HIT + 0.12, 0.6), (1, 0.4)])
    p.both("Arm", rx=-60 * fall_arm, ry=-12 * fall_arm, rz=8 * fall_arm)
    p.both("ForeArm", rz=-10 * fall_arm)
    flop = keys(t, [(FACEPLANT_HIT, 0), (FACEPLANT_HIT + 0.1, 1)])
    p.both("Arm", ry=14 * flop)
    p.belly = 0.6 - 0.8 * settle
    return p

@anim("faceplant_sleep", 120)
def a_faceplant_sleep(t):
    """Спит лицом в салате: спина поднимается от храпа, руки свисают со стола."""
    p = stand(0, breath=0.0)
    faceplant_pose(p, FACEPLANT_BEND, 1.0)
    p.add("Head", rx=14)
    p.both("Arm", rx=-24, ry=-12 + 14, rz=3)
    p.both("ForeArm", rz=-4)
    snore = keys(t, [(0, 0), (0.45, 1), (0.55, 1), (1, 0)])
    p.add("Spine1", rx=-2.5 * snore)
    p.add("Spine2", rx=-2 * snore)
    p.both("Arm", rx=2 * snore)
    p.belly = 0.2 * snore - 0.2
    return p

# ---------------------------------------------------------------- поимка: за шею и трясёт, вертушка
# Герой стоит лицом к соседу; расстояние игра считает по клипу (руки — у шеи героя, стопа — у его головы).
GRAB_NECK = (0.075, -0.6, 1.36)      # куда тянутся кисти (левая; правая — зеркально): шея героя, приподнятого на ~8 см
KICK_HIT = 0.55                      # момент удара вертушки (доля клипа)
GRAB = {"Arm": [-80.0, 10.0, -20.0], "ForeArm": [0.0, 0.0, -30.0], "Hand": [0.0, 0.0, 0.0]}

def arm_pose(p, s, table, k=1.0):
    for b in ("Arm", "ForeArm", "Hand"):
        p.side(s, b, *[v * k for v in table[b]])

@anim("grab_shake", 24)
def a_grab_shake(t):
    """Схватил за шею обеими руками, приподнял и трясёт (два рывка за цикл; такт — как у клипа героя choked)."""
    p = stand(0, breath=0.0)
    s = S(t * 2)
    p.add("Spine", rx=5 + 3 * s)       # не наваливается: головы не сталкиваются
    p.add("Spine1", rx=2)
    arm_pose(p, "L", GRAB)
    arm_pose(p, "R", GRAB)
    p.both("Arm", rx=-7 * s)                     # толкает-тянет
    p.both("ForeArm", rz=6 * s)
    p.add("Head", rx=-8 + 4 * s, rz=4 * S(t * 4))
    p.both("UpLeg", ry=-6, rx=-4); p.both("Leg", rx=12)
    p.move(z=-0.03, y=0.01 * s)
    p.belly = 0.6 + 0.4 * s
    return p

@anim("fight_stance", 30)
def a_fight_stance(t):
    """Стойка кикбоксера: кулаки у подбородка, пружинит на носках, правая нога сзади."""
    p = stand(t, breath=0.0)
    guard_fists(p)
    hop = abs(S(t * 2))
    p.move(z=0.025 * hop - 0.02, x=0.02 * S(t))
    p.side("R", "UpLeg", rx=14); p.side("L", "UpLeg", rx=-10)
    p.both("Foot", rx=8 * hop)
    p.add("Hips", rz=-14); p.add("Spine1", rz=10)
    p.add("Head", rx=4 + 2 * hop)
    p.both("Arm", rx=-4 * S(t * 2))
    p.belly = 0.5 + 0.5 * hop
    return p

@anim("spin_kick", 45, loop=False)
def a_spin_kick(t):
    """Вертушка в прыжке: шаг вперёд, оборот, правая нога на высоте головы — удар — приземлился в стойку."""
    p = stand(t, breath=0.0)
    guard_fists(p, keys(t, [(0, 1), (0.3, 0.6), (0.7, 0.6), (0.9, 1)]))
    p.move(y=-0.38 * keys(t, [(0.05, 0), (KICK_HIT, 1)]))
    spin = keys(t, [(0.1, 0), (KICK_HIT, -270), (0.8, -360)])
    p.add("Hips", rz=spin)
    hop = keys(t, [(0.3, 0), (KICK_HIT - 0.05, 1), (KICK_HIT + 0.12, 1), (0.82, 0)])
    p.move(z=0.16 * hop)
    leg = keys(t, [(0.25, 0), (KICK_HIT - 0.05, 1), (KICK_HIT + 0.12, 1), (0.85, 0)])
    lean = keys(t, [(0.25, 0), (KICK_HIT - 0.05, 1), (KICK_HIT + 0.1, 1), (0.85, 0)])
    p.add("Hips", ry=48 * lean)                  # корпус — от ноги
    p.side("L", "UpLeg", ry=-44 * lean)          # опорная — отвесно
    p.side("R", "UpLeg", ry=-92 * leg, rx=-10 * leg)
    chamber = keys(t, [(0.25, 0), (0.38, 1), (KICK_HIT - 0.04, 0), (KICK_HIT + 0.12, 0), (0.85, 0.6), (1, 0)])
    p.side("R", "Leg", rx=80 * chamber)
    p.side("R", "Foot", rx=20 * leg)
    p.add("Head", ry=-25 * lean)
    p.both("Leg", rx=10 * keys(t, [(0.82, 0), (0.88, 1), (1, 0)]))   # приземление
    p.belly = 0.5 + 0.5 * hop
    return p

@anim("lie_forward", 120)
def a_lie_forward(t):
    p = stand(0, breath=0.0)
    lie_front_pose(p)
    p.both("Arm", ry=22, rx=-2)
    p.both("ForeArm", rz=8, rx=-80)
    p.add("Head", rx=18, rz=25)
    p.both("Foot", rx=60)
    snore = keys(t, [(0, 0), (0.45, 1), (0.55, 1), (1, 0)])
    p.belly = 0.3 + 0.5 * snore
    p.move(z=0.012 * snore)
    p.both("Shoulder", ry=-3 * snore)
    return p

@anim("get_up", 60, loop=False)
def a_get_up(t):
    """Поднимается с пола (из lie_back): садится, подтягивает ноги, встаёт, отряхивается."""
    p = stand(0, breath=0.0)
    lie = 1 - keys(t, [(0.3, 0), (0.8, 1)])           # 1 — лежит
    sit = keys(t, [(0, 0), (0.3, 1), (0.55, 1), (0.8, 0)])   # корпус поднят от пола
    knees = keys(t, [(0.2, 0), (0.45, 1), (0.7, 1), (0.88, 0)])
    lie_back_pose(p, lie)
    lying_back_limbs(p, keys(t, [(0, 1), (0.25, 0)]))
    p.add("Spine", rx=60 * sit)
    p.add("Spine1", rx=20 * sit)
    p.add("Head", rx=10 * sit)
    p.both("UpLeg", rx=-70 * knees * lie - 40 * knees * (1 - lie))
    p.both("Leg", rx=110 * knees * lie + 70 * knees * (1 - lie))
    p.both("Foot", rx=-30 * knees * lie)
    p.move(z=-0.12 * knees * (1 - lie), y=-0.1 * knees * lie)
    p.both("Arm", rx=30 * sit, ry=20 * sit)
    dust = keys(t, [(0.82, 0), (0.88, 1), (0.95, 1), (1, 0)])
    p.side("R", "Arm", rx=-20 * dust, rz=-20 * dust)
    p.side("R", "ForeArm", rz=-40 * dust * (0.6 + 0.4 * S(t * 10)))
    return p

# ---------------------------------------------------------------- бытовые дела по распорядку
# Почти все дела сосед делает спиной к камере (лицом к стене или предмету), поэтому движения крупные:
# локти, плечи, наклоны корпуса — чтобы читалось сзади и сбоку. Темп спокойный, бытовой.
# Углы рук в таблицах ниже (поверх стойки, левая рука; правая — зеркально) подбирает solve().
AKIMBO = {"Arm": [12.0, -34.0, -10.0], "ForeArm": [0.0, 0.0, -100.0], "Hand": [0.0, 0.0, 0.0]}      # рука в боку
BRUSH = {"Arm": [-50.0, -20.0, -30.0], "ForeArm": [0.0, 0.0, -110.0], "Hand": [0.0, 0.0, 0.0]}     # кулак со щёткой у рта
WASH_SCOOP = {"Arm": [-50.0, 0.0, -20.0], "ForeArm": [-60.0, 0.0, -30.0], "Hand": [0.0, 0.0, 0.0]}  # ладони ковшиком
WASH_FACE = {"Arm": [-60.0, -10.0, -30.0], "ForeArm": [-40.0, 0.0, -120.0], "Hand": [0.0, 0.0, 0.0]}  # ладони у лица
JAR_SHELF = {"Arm": [-95.0, -5.0, -15.0], "ForeArm": [-60.0, 0.0, -20.0], "Hand": [0.0, 0.0, 0.0]}  # тянется к полке
JAR_EYE = {"Arm": [-55.0, -5.0, -25.0], "ForeArm": [-60.0, 0.0, -80.0], "Hand": [0.0, 0.0, 0.0]}    # банка у глаз
BEHIND = {"Arm": [30.0, 10.0, -60.0], "ForeArm": [0.0, 0.0, -70.0], "Hand": [0.0, 0.0, 0.0]}       # руки за спиной
WIPE = {"Arm": [-60.0, -40.0, -40.0], "ForeArm": [0.0, 0.0, -120.0], "Hand": [0.0, 0.0, 0.0]}      # запястьем по лбу

def arm_mix(p, s, a, b, f):
    """Рука s ('L'/'R') между таблицами a и b (None — рука как в стойке), f = 0..1."""
    for bn in ("Arm", "ForeArm", "Hand"):
        va = a[bn] if a else (0.0, 0.0, 0.0)
        vb = b[bn] if b else (0.0, 0.0, 0.0)
        p.side(s, bn, *[lerp(va[k], vb[k], f) for k in range(3)])

def arm_path(p, s, stages, ph):
    """Рука по цепочке поз stages (None — стойка): ph = 0..len-1 — дробный номер позы."""
    i = max(0, min(len(stages) - 2, int(ph)))
    arm_mix(p, s, stages[i], stages[i + 1], ph - i)

def bend_over(p, b, knees=0.0):
    """Наклон вперёд в поясе на b градусов (стопы на месте, бёдра почти отвесно; живот мешает —
    гнётся и спиной). knees — насколько присесть (градусы): бедро вперёд, голень назад, таз ниже."""
    p.add("Hips", rx=b * 0.55)
    p.both("UpLeg", rx=-b * 0.55 - knees)
    p.both("Leg", rx=2 * knees)
    p.both("Foot", rx=-knees)
    p.add("Spine", rx=b * 0.2)
    p.add("Spine1", rx=b * 0.15)
    p.add("Spine2", rx=b * 0.1)
    a = math.radians(knees)
    p.move(y=0.04 * math.sin(a), z=-0.62 * (1 - math.cos(a)))

@anim("brush", 120)
def a_brush(t):
    """Чистит зубы: правый кулак со щёткой у рта, локоть в сторону — частые короткие движения;
    левая рука в боку, голова чуть набок. В конце нагибается к раковине сплюнуть."""
    p = stand(t, breath=0.4)
    spit = keys(t, [(0, 0), (0.74, 0), (0.81, 1), (0.89, 1), (0.96, 0), (1, 0)])
    other = keys(t, [(0, 0), (0.3, 0), (0.37, 1), (0.64, 1), (0.71, 0), (1, 0)])   # то правая, то левая сторона
    go = 1 - spit
    sc = S(t * 16) * go                     # 16 движений щёткой за клип
    bend_over(p, 34 * spit, knees=4 * spit)
    p.add("Spine", rx=3)
    arm_mix(p, "R", None, BRUSH, 1 - 0.25 * spit)
    p.side("R", "Arm", rx=-4 * sc, rz=7 * sc - 8 * other, ry=-10 * other)
    p.side("R", "ForeArm", rx=14 * sc)
    p.side("R", "Shoulder", ry=-3 - 2 * sc)
    arm_mix(p, "L", None, AKIMBO, 1.0)
    p.add("Head", rx=-4 + 16 * spit + 2 * sc, rz=-6 + 12 * other, ry=6 - 10 * other)
    p.add("Neck", rx=6 * spit)
    p.belly += 0.2 * sc
    return p

@anim("wash", 120)
def a_wash(t):
    """Умывается: наклон к раковине, ладони ковшиком черпают воду и плещут в лицо (два раза),
    трёт лицо; выпрямляется, трясёт головой и стряхивает воду с рук."""
    p = stand(t, breath=0.3)
    # 0 — руки опущены, 1 — ладони ковшиком над раковиной, 2 — ладони у лица
    ph = keys(t, [(0, 0), (0.1, 1), (0.17, 1), (0.25, 2), (0.4, 2), (0.47, 1), (0.53, 1), (0.6, 2),
                  (0.72, 2), (0.8, 0), (1, 0)])
    lean = keys(t, [(0, 0), (0.08, 1), (0.72, 1), (0.8, 0), (1, 0)])
    bend_over(p, 30 * lean, knees=6 * lean)
    for s in ("L", "R"):
        arm_path(p, s, [None, WASH_SCOOP, WASH_FACE], ph)
    scoop = keys(t, [(0.1, 0), (0.13, 1), (0.17, 0)]) + keys(t, [(0.47, 0), (0.5, 1), (0.53, 0)])
    p.both("Arm", rx=8 * scoop)                                   # черпнул
    rub = keys(t, [(0.27, 0), (0.3, 1), (0.37, 1), (0.4, 0)]) + keys(t, [(0.62, 0), (0.65, 1), (0.69, 1), (0.72, 0)])
    p.both("Arm", ry=7 * rub * S(t * 20))                         # трёт лицо вверх-вниз
    splash = keys(t, [(0.22, 0), (0.25, 1), (0.3, 0)]) + keys(t, [(0.57, 0), (0.6, 1), (0.65, 0)])
    face = max(0.0, ph - 1)
    p.add("Head", rx=8 * lean - 4 * face - 6 * splash)              # голова навстречу ладоням, плеск — вздрогнул
    p.both("Shoulder", ry=-5 * splash)
    # выпрямился: трясёт головой («бр-р»), плечи к ушам, стряхивает воду с кистей
    shake = keys(t, [(0.78, 0), (0.82, 1), (0.92, 1), (0.97, 0)])
    w = S(t * 18)
    p.add("Head", rz=16 * shake * w, ry=-5 * shake * w)
    p.add("Neck", rz=6 * shake * w)
    p.add("Spine2", rz=-3 * shake * w)
    p.both("Shoulder", ry=-6 * shake)
    p.both("Arm", rx=-22 * shake, ry=-8 * shake)
    p.both("ForeArm", rz=-55 * shake + 18 * shake * w)
    p.both("Hand", rz=25 * shake * w)
    p.belly += 0.4 * shake * w
    return p

@anim("inspect", 150)
def a_inspect(t):
    """Проверяет закатки / заначку: тянется к полке, берёт банку двумя руками, подносит к глазам,
    вертит, смотрит на просвет, кивает и ставит обратно."""
    p = stand(t, breath=0.4)
    # 0 — руки опущены, 1 — у полки, 2 — банка у глаз
    ph = keys(t, [(0, 0), (0.12, 1), (0.19, 1), (0.31, 2), (0.71, 2), (0.82, 1), (0.89, 1), (1, 0)])
    up = keys(t, [(0, 0), (0.12, 1), (0.19, 1), (0.28, 0), (0.75, 0), (0.82, 1), (0.89, 1), (0.97, 0)])
    for s in ("L", "R"):
        arm_path(p, s, [None, JAR_SHELF, JAR_EYE], ph)
    p.add("Spine2", rx=-5 * up); p.both("Shoulder", ry=-5 * up)    # тянется вверх
    p.add("Head", rx=-12 * up)
    look = keys(t, [(0.31, 0), (0.35, 1), (0.67, 1), (0.71, 0)])
    u = max(0.0, min(1.0, (t - 0.33) / 0.36))
    turn = look * S(u * 2)                                        # вертит банку: одна рука вперёд, другая назад
    p.side("L", "Arm", rx=-12 * turn, rz=-6 * turn)
    p.side("R", "Arm", rx=12 * turn, rz=6 * turn)
    p.add("Spine1", rz=-5 * turn)
    light = keys(t, [(0.44, 0), (0.5, 1), (0.56, 1), (0.62, 0)])  # на просвет: выше и голову назад
    p.both("Arm", rx=-18 * light)
    p.add("Head", rx=6 * look - 16 * light, ry=10 * look * S(u + 0.25), rz=8 * turn)
    p.add("Spine", rx=6 * look * (1 - light))                     # склонился к банке
    nod = keys(t, [(0.64, 0), (0.67, 1), (0.7, 0)])               # «порядок»
    p.add("Head", rx=8 * nod)
    return p

@anim("repair", 150)
def a_repair(t):
    """Чинит машину: согнулся над капотом, правая внизу качает ключом, левая упирается в машину;
    прикипевшая гайка — рывок плечом; выпрямляется, вытирает лоб, держится за поясницу."""
    p = stand(t, breath=0.3)
    up = keys(t, [(0, 0), (0.56, 0), (0.65, 1), (0.86, 1), (0.95, 0), (1, 0)])
    work = 1 - up
    bend_over(p, 56 * work + 4, knees=10 * work + 2)
    r = S(t * 9)                                                  # качки ключом
    hard = keys(t, [(0.42, 0), (0.47, 1), (0.52, 1), (0.55, 0)])
    rr = r * (1 - hard)
    p.side("R", "Arm", rx=(-52 - 12 * rr - 10 * hard) * work, ry=-26 * work, rz=(-10 + 6 * rr) * work)
    p.side("R", "ForeArm", rz=(-55 - 16 * rr) * work, rx=24 * rr * work)
    p.side("R", "Shoulder", ry=(-3 * rr - 6 * hard) * work)
    p.side("L", "Arm", rx=-80 * work, ry=2 * work, rz=-12 * work)  # упёрся ладонью в крыло
    p.side("L", "ForeArm", rz=-6 * work)
    p.side("L", "Hand", ry=-35 * work)
    p.add("Spine1", rz=(3 * rr + 10 * hard) * work)
    p.add("Hips", rz=-2 * rr * work)
    p.add("Head", rx=10 * work, rz=-6 * hard * work)
    # передых: правой — по лбу, левая — на поясницу, прогнулся
    wipe = keys(t, [(0.62, 0), (0.69, 1), (0.8, 1), (0.86, 0)])
    arm_mix(p, "R", None, WIPE, wipe)
    p.side("R", "Arm", rz=10 * wipe * S(max(0.0, t - 0.69) / 0.11 * 1.5))
    p.add("Head", rx=18 * wipe)                                   # лбом навстречу руке
    back = keys(t, [(0.6, 0), (0.68, 1), (0.86, 1), (0.93, 0)])
    arm_mix(p, "L", None, BEHIND, back)
    p.add("Spine", rx=-8 * back)
    p.add("Head", rx=-10 * back * (1 - wipe))
    p.belly += 0.6 * back
    return p

ITEM = {"Arm": [-58.0, -14.0, -26.0], "ForeArm": [0.0, 0.0, -95.0], "Hand": [0.0, 0.0, 0.0]}   # находка у глаз
TOSS = {"Arm": [-105.0, -30.0, -5.0], "ForeArm": [0.0, 0.0, -112.0], "Hand": [0.0, -45.0, 0.0]}  # кисть над плечом

@anim("rummage", 150)
def a_rummage(t):
    """Разбирает хлам в сундуке: согнулся, перебирает руками по очереди; вынимает что-то,
    разглядывает, вертит и швыряет через плечо; снова лезет в сундук."""
    p = stand(t, breath=0.2)
    out = keys(t, [(0, 0), (0.32, 0), (0.41, 1), (0.63, 1), (0.73, 0), (1, 0)])
    dig = 1 - out
    bend_over(p, 60 * dig + 14 * out, knees=16 * dig + 4)
    d = S(t * 7)
    for s, k in (("L", 1), ("R", -1)):                        # руки по очереди
        p.side(s, "Arm", rx=(-48 - 16 * d * k) * dig, ry=-6 * dig, rz=-14 * dig)
        p.side(s, "ForeArm", rz=(-28 - 14 * d * k) * dig)
    p.add("Spine1", rz=6 * d * dig)
    p.add("Head", rx=14 * dig, rz=-5 * d * dig)
    # находка: правая подносит к глазам, вертит — и не глядя швыряет через плечо назад
    ph = keys(t, [(0, 0), (0.36, 0), (0.44, 1), (0.55, 1), (0.6, 2), (0.63, 2), (0.72, 3), (1, 3)])
    arm_path(p, "R", [None, ITEM, TOSS, None], ph)
    look = keys(t, [(0.36, 0), (0.44, 1), (0.55, 1), (0.6, 0)])
    p.side("R", "ForeArm", rx=30 * look * S(t * 6))
    p.add("Head", rx=-4 * look, ry=12 * look * S(t * 3))
    p.side("L", "Arm", rx=-20 * out)
    p.side("L", "ForeArm", rz=-20 * out)
    throw = keys(t, [(0.55, 0), (0.6, 1), (0.64, 1), (0.72, 0)])
    p.add("Spine1", rz=-12 * throw)
    p.add("Head", rz=-12 * throw, rx=6 * throw)
    return p

@anim("gaze", 180)
def a_gaze(t):
    """Смотрит на голубей: руки за спиной, голова медленно следит за птицами, кивает;
    правой рукой подманивает «гули-гули», покачивается с пятки на носок."""
    p = stand(t, breath=0.8)
    wave = keys(t, [(0, 0), (0.5, 0), (0.56, 1), (0.74, 1), (0.8, 0), (1, 0)])
    arm_mix(p, "L", None, BEHIND, 1.0)
    arm_mix(p, "R", None, BEHIND, 1 - wave)
    p.side("R", "Arm", rx=-40 * wave, ry=-6 * wave, rz=-20 * wave)
    p.side("R", "ForeArm", rz=-70 * wave)
    p.side("R", "Hand", ry=(15 + 25 * max(0.0, S(t * 12))) * wave)   # кисть манит
    p.add("Spine", rx=5 * wave)
    follow = keys(t, [(0, 0), (0.12, -1), (0.22, -1), (0.34, 0.6), (0.46, 0.6), (0.56, 0.1), (0.76, 0.1),
                      (0.86, 1), (0.94, 1), (1, 0)])
    p.add("Head", rz=22 * follow)
    p.add("Neck", rz=8 * follow)
    p.add("Spine2", rz=4 * follow)
    nod = keys(t, [(0.38, 0), (0.41, 1), (0.44, 0), (0.47, 1), (0.5, 0)])
    p.add("Head", rx=4 + 8 * nod + 4 * wave)
    p.both("Shoulder", ry=-3 * wave * (0.5 + 0.5 * S(t * 20)))     # посмеивается
    rock = S(t * 2)                                                 # с пятки на носок
    p.add("Hips", ry=1.5 * S(t), rx=0.8 * rock)
    p.both("UpLeg", rx=-0.8 * rock)
    p.move(x=0.008 * S(t))
    return p

@anim("stretch", 180)
def a_stretch(t):
    """Дышит воздухом: потягивается руками вверх с прогибом, руки в боки — два глубоких вдоха
    (живот и грудь), разминает шею кругом головы."""
    p = stand(t, breath=0.0)
    up = keys(t, [(0, 0), (0.06, 0), (0.2, 1), (0.34, 1), (0.44, 0), (1, 0)])
    hips = keys(t, [(0.38, 0), (0.48, 1), (0.86, 1), (0.96, 0)])
    p.both("Arm", ry=-150 * up, rx=-10 * up)
    p.both("ForeArm", rz=-16 * up)
    p.both("Hand", rz=10 * up)
    sw = keys(t, [(0.2, 0), (0.24, 1), (0.28, -1), (0.32, 0)])      # качнулся вбок
    p.add("Spine", rx=-5 * up, ry=6 * sw)
    p.add("Spine2", rx=-7 * up, ry=4 * sw)
    p.add("Head", rx=-18 * up)
    p.both("Shoulder", ry=-6 * up)
    for s in ("L", "R"):
        arm_mix(p, s, None, AKIMBO, hips)
    br = keys(t, [(0.48, 0), (0.55, 1), (0.62, 0), (0.69, 1), (0.76, 0)])
    p.add("Spine2", rx=-5 * br)
    p.both("Shoulder", ry=-6 * br)
    p.both("Arm", ry=-5 * br * hips)                                # локти в стороны на вдохе
    p.add("Head", rx=-6 * br)
    p.belly = 0.3 + 0.9 * up + 1.1 * br
    nw = keys(t, [(0.76, 0), (0.8, 1), (0.9, 1), (0.94, 0)])
    a = 2 * math.pi * max(0.0, min(1.0, (t - 0.78) / 0.14))
    p.add("Head", ry=16 * nw * math.sin(a), rx=12 * nw * math.cos(a))
    p.add("Neck", ry=6 * nw * math.sin(a), rx=4 * nw * math.cos(a))
    return p

# ---------------------------------------------------------------- кисти по клипам
# Накладываются поверх позы тела (там уже стоит расслабленная кисть "relax").
def h_drink(p, t):
    hand(p, "R", "bottle")                               # бутылка в руке весь клип
    hand(p, "L", "spread", keys(t, [(0, 0), (0.2, 0.7), (0.8, 0.7), (1, 0)]))   # ладонь на животе

def h_work(p, t):
    hand(p, "R", "handle")                               # шпатель
    hand(p, "L", "handle", 0.9)                          # ведро / мастерок

def h_bulb(p, t):
    grip = keys(bulb_u(t), [(0, 1), (0.6, 1), (0.7, 0.35), (0.92, 0.35), (1, 1)])   # перехват
    hand(p, "R", "bulb", grip)
    hand(p, "L", "handle")                    # за стремянку

def h_phone(p, t):
    hand(p, "R", "phone")
    hand(p, "L", "spread", 0.6)               # ладонь на животе
    # большой палец листает: два свайпа и пара тычков за клип
    thumb_curl(p, "R", keys(t, [(0, 0), (0.1, 22), (0.2, 0), (0.35, 22), (0.45, 0),
                                (0.62, 18), (0.67, 0), (0.78, 18), (0.83, 0), (1, 0)]))
    p.side("R", "HandThumb1", rz=keys(t, [(0, 0), (0.1, -14), (0.2, 6), (0.35, -14), (0.45, 6), (0.6, 0)]))

def h_kick(p, t):
    hand(p, "B", "fist")

def h_angry(p, t):
    hand(p, "B", "spread", keys(t, [(0.12, 0), (0.3, 1), (0.42, 1), (0.52, 0)]))   # руки вверх — растопырил
    hand(p, "B", "fist", keys(t, [(0, 0), (0.12, 1), (0.25, 0), (0.5, 0), (0.6, 1), (0.92, 1), (1, 0)]))

def h_suspicious(p, t):
    hand(p, "R", "flat", keys(t, [(0, 0), (0.12, 1), (0.9, 1), (1, 0)]))          # ладонь козырьком

def h_catch(p, t):
    hand(p, "B", "spread", keys(t, [(0, 0), (0.15, 1), (0.22, 0)]))
    hand(p, "B", "fist", keys(t, [(0.15, 0), (0.25, 1), (0.6, 1), (0.68, 0)]))   # схватил — держит — бросил
    hand(p, "B", "spread", keys(t, [(0.6, 0), (0.68, 1), (0.85, 1), (1, 0)]))

def h_oath(p, t):
    hand(p, "R", "flat", keys(t, [(0, 0), (0.18, 1), (0.9, 1), (1, 0)]))          # клятвенная ладонь
    hand(p, "L", "flat", keys(t, [(0, 0), (0.15, 1), (0.85, 1), (1, 0)]))         # ладонь на груди

def h_dance(p, t):
    hand(p, "B", "spread", 0.6 + 0.4 * S(t * 4))
    hand(p, "R", "fist", max(0.0, S(t * 2)) * 0.8)       # то кулак, то пятерня

def h_walk_drunk(p, t):
    hand(p, "B", "spread", 0.5 + 0.3 * S(t * 2))

def h_fall_back(p, t):
    hand(p, "B", "spread", keys(t, [(0, 0), (0.15, 1), (0.55, 1), (0.9, 0.2)]))

def h_get_up(p, t):
    hand(p, "B", "flat", keys(t, [(0.05, 0), (0.25, 1), (0.6, 1), (0.8, 0)]))     # упирается в пол

def h_lie_front(p, t):
    hand(p, "B", "flat")                     # ладони плашмя на полу, пальцы не втыкаются в пол

def h_fall_forward(p, t):
    hand(p, "B", "spread", keys(t, [(0.3, 0), (0.5, 1), (0.7, 1), (0.9, 0)]))
    hand(p, "B", "flat", keys(t, [(0.7, 0), (0.9, 1)]))

def h_faceplant(p, t):
    hand(p, "B", "spread", keys(t, [(0.4, 0), (0.55, 1), (0.68, 0.3)]))
    hand(p, "B", "relax", 0.6, base="flat")

def h_grab(p, t):
    hand(p, "B", "handle")                   # сжал шею

def h_fight(p, t):
    hand(p, "B", "fist")

def h_sleep(p, t):
    hand(p, "B", "relax", 0.5, base="flat")              # расслабленно, пальцы чуть сильнее согнуты

def h_brush(p, t):
    hand(p, "R", "handle")                               # щётка в кулаке
    hand(p, "L", "flat", 0.8)                            # ладонь на боку

def h_wash(p, t):
    face = keys(t, [(0.2, 0), (0.25, 1), (0.42, 1), (0.47, 0), (0.55, 0), (0.6, 1), (0.74, 1), (0.8, 0)])
    hand(p, "B", "flat", 0.6 + 0.4 * face)               # ковшик -> ладони на лице
    hand(p, "B", "spread", keys(t, [(0.78, 0), (0.82, 1), (0.92, 1), (0.97, 0)]))   # стряхивает воду

def h_inspect(p, t):
    hold = keys(t, [(0.14, 0), (0.19, 1), (0.82, 1), (0.88, 0)])
    hand(p, "B", "spread", keys(t, [(0.04, 0), (0.12, 1), (0.16, 0), (0.85, 0), (0.9, 0.6), (1, 0)]))
    hand(p, "B", "bottle", 0.7 * hold)                   # трёхлитровая банка в обеих руках

def h_repair(p, t):
    work = 1 - keys(t, [(0, 0), (0.56, 0), (0.65, 1), (0.86, 1), (0.95, 0), (1, 0)])
    hand(p, "R", "handle", work)                         # ключ
    hand(p, "L", "flat", 0.6 + 0.4 * work)               # ладонь на капоте / на пояснице

def h_rummage(p, t):
    out = keys(t, [(0, 0), (0.32, 0), (0.41, 1), (0.63, 1), (0.73, 0), (1, 0)])
    hand(p, "B", "claw", (1 - out) * (0.6 + 0.4 * S(t * 7)))   # перебирает
    hand(p, "R", "handle", keys(t, [(0.34, 0), (0.38, 1), (0.59, 1), (0.62, 0)]))   # находка в кулаке
    hand(p, "R", "spread", keys(t, [(0.59, 0), (0.62, 1), (0.67, 1), (0.74, 0)]))   # бросил

def h_gaze(p, t):
    wave = keys(t, [(0, 0), (0.5, 0), (0.56, 1), (0.74, 1), (0.8, 0), (1, 0)])
    hand(p, "L", "handle", 0.5)                          # за спиной держит запястье
    hand(p, "R", "handle", 0.5 * (1 - wave))
    hand(p, "R", "fist", wave * (0.3 + 0.35 * (1 + S(t * 12))))   # «гули-гули» — манит пальцами

def h_stretch(p, t):
    up = keys(t, [(0, 0), (0.06, 0), (0.2, 1), (0.34, 1), (0.44, 0), (1, 0)])
    hand(p, "B", "spread", up)
    hand(p, "B", "flat", 0.8 * keys(t, [(0.38, 0), (0.48, 1), (0.86, 1), (0.96, 0)]))   # ладони на боках

HAND_LAYER = {"drink": h_drink, "work": h_work, "bulb": h_bulb, "phone": h_phone, "kick": h_kick,
              "angry": h_angry, "suspicious": h_suspicious, "catch": h_catch, "oath": h_oath,
              "dance": h_dance, "walk_drunk": h_walk_drunk, "fall_back": h_fall_back,
              "get_up": h_get_up, "sleep": h_sleep, "lie_back": h_sleep, "lie_forward": h_lie_front,
              "fall_forward": h_fall_forward, "faceplant": h_faceplant, "faceplant_sleep": h_faceplant,
              "grab_shake": h_grab, "fight_stance": h_fight, "spin_kick": h_fight,
              "brush": h_brush, "wash": h_wash, "inspect": h_inspect, "repair": h_repair,
              "rummage": h_rummage, "gaze": h_gaze, "stretch": h_stretch}

# ---------------------------------------------------------------- решатель: предметы в руке
# Точки лица в позе покоя — сняты рендером головы с метками высоты (губы ~1.43, глаза ~1.55).
MOUTH = (0.0, -0.115, 1.433)    # чуть за губами: горлышко входит в рот
EYES = (0.0, -0.11, 1.55)
HEAD_C = (0.0, 0.0, 1.56)

def neck_cost(want):
    """Горлышко (конец бутылки длиной 26 см) — во рту, бутылка смотрит в направлении want."""
    g_head, g_axis = bone_rest("RightHandGrip")
    c = posed_point("RightHandGrip", g_head)
    axis = posed_dir("RightHandGrip", g_axis)                 # к горлышку
    neck_tip = c + axis * 0.13
    mouth = posed_point("Head", MOUTH)
    clear = max(0.0, 0.16 - (c - posed_point("Head", HEAD_C)).length) * 100   # кулак не в голове
    return ((neck_tip - mouth).length * 100) ** 2 + 300 * (1 - axis.dot(want.normalized())) + clear ** 2 * 4

def drink_cost():          # запрокинул: дно вверх
    return neck_cost(Vector((0.15, 0.55, -0.82)))

def approach_cost():       # поднёс к губам: бутылка почти горизонтально
    return neck_cost(Vector((0.15, 0.9, -0.35)))

def bulb_cost():
    """Ладонь вверх, лампочка (центр хвата) над головой впереди."""
    g_head, _ = bone_rest("RightHandGrip")
    c = posed_point("RightHandGrip", g_head)
    palm = posed_dir("RightHand", (0, 0, -1))
    return ((c - Vector((-0.14, -0.16, 1.76))).length * 100) ** 2 + 300 * (1 - palm.z)

def phone_cost():
    ph_head, ph_axis = bone_rest("RightHandPhone")
    c = posed_point("RightHandPhone", ph_head)
    up = posed_dir("RightHandPhone", ph_axis)                 # длинная сторона телефона
    normal = posed_dir("RightHandPhone", (0, 0, -1))          # куда смотрит экран
    eyes = posed_point("Head", EYES)
    target = Vector((-0.10, -0.36, 1.26))                     # правее центра, у груди, над животом
    to_eyes = (eyes - c).normalized()
    return ((c - target).length * 100) ** 2 + 400 * (1 - normal.dot(to_eyes)) + 150 * max(0.0, 0.7 - up.z)

def lift_cost():
    """Фаза подъёма (рука поднята, ещё не запрокинул): бутылка стоймя перед грудью."""
    g_head, g_axis = bone_rest("RightHandGrip")
    c = posed_point("RightHandGrip", g_head)
    axis = posed_dir("RightHandGrip", g_axis)
    target = Vector((-0.12, -0.36, 1.22))
    return ((c - target).length * 100) ** 2 + 300 * (1 - axis.dot(Vector((0.1, -0.15, 1)).normalized()))

solve_thumbs()
solve("drink", DRINK, at(a_drink, h_drink, 0.5), drink_cost)
solve("lift", DRINK_LIFT, at(a_drink, h_drink, 0.18), lift_cost)
solve("approach", DRINK_APPROACH, at(a_drink, h_drink, 0.27), approach_cost)
solve_starts("bulb", BULB, at(a_bulb, h_bulb, 0.1), bulb_cost, [
    {"Arm": [-30, -120, -20], "ForeArm": [40, 0, -60], "Hand": [0, 40, 0]},
    {"Arm": [-60, -90, -10], "ForeArm": [-40, 0, -90], "Hand": [0, -40, 0]},
])
solve_starts("phone", PHONE, at(a_phone, h_phone, 0.0), phone_cost, [
    {"Arm": [-40, 20, -30], "ForeArm": [60, 0, -110], "Hand": [0, 0, 0]},
    {"Arm": [-40, 20, -30], "ForeArm": [-60, 0, -110], "Hand": [0, 0, 0]},
    {"Arm": [-55, 15, -20], "ForeArm": [80, 0, -90], "Hand": [0, 30, 20]},
    {"Arm": [-55, 15, -20], "ForeArm": [-80, 0, -90], "Hand": [0, -30, 20]},
])

def grab_cost():
    """Левая кисть (центр хвата) — у шеи героя слева, ладонь к шее (внутрь, к -X)."""
    g_head, _ = bone_rest("LeftHandGrip")
    c = posed_point("LeftHandGrip", g_head)
    return ((c - Vector(GRAB_NECK)).length * 100) ** 2 + 120 * (1 - posed_dir("LeftHand", (0, 0, -1)).dot(Vector((-1, 0, -0.2)).normalized()))
solve_starts("grab", GRAB, at(a_grab_shake, h_grab, 0.0), grab_cost, [
    {"Arm": [-70, 20, -30], "ForeArm": [40, 0, -40], "Hand": [0, 0, 0]},
    {"Arm": [-90, 0, -10], "ForeArm": [-40, 0, -20], "Hand": [0, 30, 0]},
    {"Arm": [-75, 25, -40], "ForeArm": [80, 0, -60], "Hand": [0, -20, 0]},
])

# --- бытовые дела: руки к точкам тела (точки — в осях покоя, едут вместе с костью-хозяином)
PALM = (0.755, 0.035, 1.19)        # центр ладони левой кисти в T-позе (правая — зеркально)

def sname(s):
    return "Left" if s == "L" else "Right"

def mir(v, s):
    return Vector((v[0] if s == "L" else -v[0], v[1], v[2]))

def palm_pt(s):
    return posed_point(sname(s) + "Hand", mir(PALM, s))

def grip_pt(s):
    n = sname(s) + "HandGrip"
    return posed_point(n, bone_rest(n)[0])

def wrist_pt(s):
    n = sname(s) + "Hand"
    return posed_point(n, rc.arm_data.bones[n].head_local)

def elbow_pt(s):
    n = sname(s) + "ForeArm"
    return posed_point(n, rc.arm_data.bones[n].head_local)

def on(bone, v, s="L"):
    """Точка v (для левой стороны; для правой — зеркально) на кости bone в текущей позе."""
    return lambda: posed_point(bone, mir(v, s))

def dir_on(bone, v, s="L"):
    return lambda: posed_dir(bone, mir(v, s))

def reach(s, target, point=palm_pt, elbow=None, palm=None, fingers=None, axis=None,
          w_elbow=0.25, w_dir=150, avoid=()):
    """Цена для solve(): точка кисти s (ладонь / кулак / запястье) — в target, локоть — у elbow,
    ладонь смотрит в palm, пальцы — в fingers, ось предмета в кулаке — в axis. avoid — [(центр, радиус)]:
    шары (голова, живот), куда не должны залезать кисть и локоть. Цели — функции от текущей позы."""
    hn = sname(s) + "Hand"
    def cost():
        c = ((point(s) - target()).length * 100) ** 2
        if elbow is not None:
            c += w_elbow * ((elbow_pt(s) - elbow()).length * 100) ** 2
        if palm is not None:
            c += w_dir * (1 - posed_dir(hn, (0, 0, -1)).dot(palm().normalized()))
        if fingers is not None:
            c += w_dir * (1 - posed_dir(hn, mir((1, 0, 0), s)).dot(fingers().normalized()))
        if axis is not None:
            gn = sname(s) + "HandGrip"
            c += w_dir * (1 - posed_dir(gn, bone_rest(gn)[1]).dot(axis().normalized()))
        for ctr, rad in avoid:
            for q in (wrist_pt(s), elbow_pt(s), palm_pt(s)):
                c += (max(0.0, rad - (q - ctr()).length) * 100) ** 2 * 4
        return c
    return cost

def arm_only(s, table, base=lambda: stand(0)):
    """Поза для решателя: стойка + одна рука по таблице."""
    def mk():
        p = base()
        arm_mix(p, s, None, table, 1.0)
        return p
    return mk

def solve_wide(label, table, make_pose, cost, starts, **lim):
    """solve_starts с другими пределами суставов (рука в боку и за спиной: плечо уходит назад
    сильнее, чем в остальных клипах)."""
    old = {k: list(v) for k, v in LIMITS.items()}
    LIMITS.update(lim)
    solve_starts(label, table, make_pose, cost, starts)
    LIMITS.clear()
    LIMITS.update(old)

WIDE_ARM = [(-150, 90), (-165, 90), (-120, 60)]
HEAD_BALL = (on("Head", (0, -0.02, 1.53)), 0.13)
BELLY_BALL = (on("Spine", (0, -0.06, 0.92)), 0.2)
# рука в боку: ладонь на боку над тазом, пальцы вперёд-вниз, локоть в сторону и чуть назад
solve_wide("akimbo", AKIMBO, arm_only("L", AKIMBO), reach("L", on("Spine", (0.275, 0.03, 0.98)),
    elbow=on("Spine", (0.5, 0.1, 1.06)), palm=dir_on("Spine", (-1, 0, -0.1)), fingers=dir_on("Spine", (0, -0.5, -0.85)),
    w_elbow=0.05, avoid=[BELLY_BALL]), [
    {"Arm": [61, 18, -70], "ForeArm": [0, 0, -95], "Hand": [0, 0, 0]},
    {"Arm": [45, 10, -50], "ForeArm": [30, 0, -100], "Hand": [0, 0, 0]},
], Arm=WIDE_ARM)
# руки за спиной: кисть у поясницы ладонью к спине, локоть назад
solve_wide("behind", BEHIND, arm_only("L", BEHIND), reach("L", on("Spine", (0.05, 0.25, 0.93)),
    elbow=on("Spine", (0.3, 0.2, 1.0)), palm=dir_on("Spine", (0, -1, 0)), w_elbow=0.05, avoid=[BELLY_BALL]), [
    {"Arm": [60, 20, -60], "ForeArm": [0, 0, -80], "Hand": [0, 0, 0]},
    {"Arm": [70, 25, -100], "ForeArm": [40, 0, -90], "Hand": [0, 0, 0]},
    {"Arm": [40, 20, -40], "ForeArm": [-60, 0, -90], "Hand": [0, 0, 0]},
], Arm=WIDE_ARM)
# щётка: кулак справа у рта, щётка смотрит в рот, локоть в сторону
solve_starts("brush", BRUSH, at(a_brush, h_brush, 0.0), reach("R", on("Head", (0.085, -0.155, 1.455), "R"),
    point=grip_pt, elbow=on("Spine2", (0.36, -0.12, 1.18), "R"), axis=dir_on("Head", (-1, -0.3, 0), "R"),
    w_elbow=0.05, avoid=[HEAD_BALL]), [
    {"Arm": [-40, -30, -40], "ForeArm": [40, 0, -120], "Hand": [0, 0, 0]},
    {"Arm": [-60, -10, -20], "ForeArm": [-40, 0, -110], "Hand": [0, 20, 0]},
])
# умывание: ладони ковшиком над раковиной (ладонь вверх, пальцы вперёд) и ладони на щеках (пальцы вверх)
solve_starts("scoop", WASH_SCOOP, at(a_wash, h_wash, 0.17), reach("L", on("Spine2", (0.06, -0.38, 1.06)),
    palm=lambda: Vector((-0.4, 0, 1)), fingers=lambda: Vector((0, -1, -0.3)), avoid=[BELLY_BALL]), [
    {"Arm": [-40, 10, -30], "ForeArm": [-80, 0, -40], "Hand": [0, 0, 0]},
])
solve_starts("face", WASH_FACE, at(a_wash, h_wash, 0.35), reach("L", on("Head", (0.055, -0.15, 1.49)),
    elbow=on("Spine2", (0.3, -0.2, 1.22)), palm=dir_on("Head", (-0.35, 1, 0)), fingers=dir_on("Head", (0, -0.2, 1)),
    w_elbow=0.05), [
    {"Arm": [-70, 0, -40], "ForeArm": [-80, 0, -120], "Hand": [0, 0, 0]},
    {"Arm": [-50, -20, -20], "ForeArm": [40, 0, -130], "Hand": [0, 0, 0]},
])
# банка: ладони с боков (к банке), у полки — впереди на уровне макушки, у глаз — перед лицом
solve_starts("shelf", JAR_SHELF, at(a_inspect, h_inspect, 0.15), reach("L", on("Spine2", (0.08, -0.38, 1.52)),
    palm=lambda: Vector((-1, 0, 0)), fingers=lambda: Vector((0, -1, 0.2))), [
    {"Arm": [-100, -20, -20], "ForeArm": [-80, 0, -20], "Hand": [0, 0, 0]},
])
solve_starts("jar", JAR_EYE, at(a_inspect, h_inspect, 0.33), reach("L", on("Spine2", (0.09, -0.37, 1.36)),
    palm=lambda: Vector((-1, 0, 0)), fingers=lambda: Vector((0, -1, 0.4)), avoid=[HEAD_BALL]), [
    {"Arm": [-60, -10, -40], "ForeArm": [-80, 0, -70], "Hand": [0, 0, 0]},
    {"Arm": [-50, 0, -20], "ForeArm": [40, 0, -90], "Hand": [0, 0, 0]},
])
# вытирает лоб тыльной стороной кисти (голова навстречу): ладонь от лица, локоть в сторону
solve_starts("wipe", WIPE, at(a_repair, h_repair, 0.69), reach("R", on("Head", (0.0, -0.16, 1.62), "R"),
    elbow=on("Spine2", (0.3, -0.18, 1.36), "R"), palm=dir_on("Head", (0, -1, 0), "R"), w_elbow=0.05,
    avoid=[HEAD_BALL]), [
    {"Arm": [-80, -60, -30], "ForeArm": [0, 0, -130], "Hand": [0, 0, 0]},
    {"Arm": [-100, -30, -40], "ForeArm": [60, 0, -110], "Hand": [0, 0, 0]},
])

record(HAND_LAYER)
export(DST, BLEND)
