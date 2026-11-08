# Сосед: модель из Tripo в T-позе -> чистка, скелет, автоматические веса, все анимации -> один GLB.
# blender -b -P tools/blender/rig_neighbor.py -- <neighbor_tpose.glb> <выход.glb> [сохранить.blend]
#
# Скелет — имена костей как у Mixamo (Hips, Spine, LeftArm...), плюс кость Belly для живота.
# Анимации задаются функциями позы от времени t (0..1). Углы — в градусах, в осях ПОКОЯ
# (T-поза, персонаж смотрит в -Y, его левая рука — в +X, вверх — +Z):
#   ноги/спина/голова (порядок XYZ):  rx+ — корпус/голова вперёд, бедро назад, голень сгибается,
#                                     стопа носком вниз; ry — наклон вбок; rz — поворот.
#   руки (порядок YXZ):  ry+ — опустить руку из T-позы, rx- — махнуть вперёд, rx+ — назад,
#                        rz- — завести внутрь, перед собой. Предплечье/кисть: rz- — согнуть.
# Правая сторона задаётся теми же числами, что левая (зеркалится автоматически).
import bpy, sys, math, mathutils
from mathutils import Vector, Euler, Quaternion

args = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = args[0], args[1]
BLEND = args[2] if len(args) > 2 else None
HEIGHT = 1.75
FPS = 30

# ---------------------------------------------------------------- модель
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS
bpy.ops.import_scene.gltf(filepath=SRC)
body = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
for o in list(bpy.context.scene.objects):
    if o != body:
        bpy.data.objects.remove(o, do_unlink=True)
body.name = "Body"
bpy.context.view_layer.objects.active = body
body.select_set(True)
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Tripo режет вершины по швам развёртки — сшиваем, потом упрощаем, не трогая швы UV
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0001)
bpy.ops.object.mode_set(mode="OBJECT")
tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
if tris > 40000:
    m = body.modifiers.new("dec", "DECIMATE")
    m.ratio = 40000 / tris
    m.delimit = {"UV", "SEAM"}
    bpy.ops.object.modifier_apply(modifier="dec")

# рост 1.75 м, стопы на полу, по центру
vs = [v.co for v in body.data.vertices]
mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
k = HEIGHT / (mx.z - mn.z)
off = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
for v in body.data.vertices:
    v.co = (v.co - off) * k
body.data.update()

# матовый материал вместо «мокрого пластика»
for mat in body.data.materials:
    nt = mat.node_tree
    for n in nt.nodes:
        if n.type == "BSDF_PRINCIPLED":
            for inp in ("Roughness", "Metallic"):
                for l in list(n.inputs[inp].links):
                    nt.links.remove(l)
            n.inputs["Roughness"].default_value = 0.85
            n.inputs["Metallic"].default_value = 0.0
            if "Specular IOR Level" in n.inputs:
                n.inputs["Specular IOR Level"].default_value = 0.25

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
# Пальцы (сняты по срезам кисти: ладонь вниз, большой палец смотрит вперёд, в -Y).
# Каждый палец — 3 фаланги от костяшки до кончика (доли 0.45 / 0.30 / 0.25).
FINGERS = {  # имя: (костяшка, кончик)
    "Index":  ((0.785, -0.010, 1.210), (0.862, -0.013, 1.203)),
    "Middle": ((0.790, 0.023, 1.212), (0.880, 0.023, 1.203)),
    "Ring":   ((0.785, 0.058, 1.210), (0.877, 0.061, 1.202)),
    "Pinky":  ((0.780, 0.088, 1.205), (0.856, 0.095, 1.200)),
}
THUMB = [(0.725, 0.005, 1.195), (0.750, -0.035, 1.185), (0.765, -0.058, 1.183), (0.780, -0.075, 1.183)]
for f, (a, b) in FINGERS.items():
    a, b = Vector(a), Vector(b)
    pts = [a, a.lerp(b, 0.45), a.lerp(b, 0.75), b]
    for i in range(3):
        SIDE.append(("Hand%s%d" % (f, i + 1), tuple(pts[i]), tuple(pts[i + 1]),
                     "Hand" if i == 0 else "Hand%s%d" % (f, i)))
for i in range(3):
    SIDE.append(("HandThumb%d" % (i + 1), THUMB[i], THUMB[i + 1], "Hand" if i == 0 else "HandThumb%d" % i))
# Точки для предметов (в Godot — BoneAttachment3D, центр предмета = голова кости):
#  HandGrip  — центр кулака; ось кости = ось бутылки, смотрит в сторону горлышка (к большому пальцу).
#  HandPhone — центр телефона, лежащего на ладони экраном от неё; ось кости = длинная сторона
#              телефона (вдоль пальцев), центр сдвинут к большому пальцу — телефон держат двумя руками.
SIDE.append(("HandGrip", (0.805, 0.035, 1.15), (0.805, -0.045, 1.15), "Hand"))
SIDE.append(("HandPhone", (0.778, -0.005, 1.1665), (0.858, -0.005, 1.1665), "Hand"))
FINGER_BONES = ["Hand%s%d" % (f, i) for f in FINGERS for i in (1, 2, 3)] + ["HandThumb%d" % i for i in (1, 2, 3)]
arm_data = bpy.data.armatures.new("Rig")
rig = bpy.data.objects.new("Rig", arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones
def add_bone(name, h, t, parent):
    b = eb.new(name)
    b.head, b.tail = Vector(h), Vector(t)
    b.roll = 0
    if parent:
        b.parent = eb[parent]
        b.use_connect = (b.parent.tail - b.head).length < 1e-4 and name != "Belly"
    b.use_deform = not name.endswith(("Grip", "Phone"))
for n, h, t, p in CENTER:
    add_bone(n, h, t, p)
for side, sx in (("Left", 1), ("Right", -1)):
    for n, h, t, p in SIDE:
        hp = (h[0] * sx, h[1], h[2]); tp = (t[0] * sx, t[1], t[2])
        add_bone(side + n, hp, tp, None if p is None else (p if p.startswith("Spine") or p == "Hips" else side + p))
bpy.ops.object.mode_set(mode="OBJECT")

# Автоматические веса. Сетка Tripo не замкнутая — тепловая карта на ней не сходится.
# Поэтому: замкнутая копия через voxel-remesh -> веса на ней -> перенос на настоящую сетку.
proxy = body.copy()
proxy.data = body.data.copy()
proxy.name = "WeightProxy"
bpy.context.scene.collection.objects.link(proxy)
proxy.data.materials.clear()
rm = proxy.modifiers.new("vox", "REMESH")
rm.mode = "VOXEL"
rm.voxel_size = 0.009
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = proxy
proxy.select_set(True)
bpy.ops.object.modifier_apply(modifier="vox")
dm = proxy.modifiers.new("dec", "DECIMATE")
dm.ratio = min(1.0, 30000 / max(1, len(proxy.data.polygons)))
bpy.ops.object.modifier_apply(modifier="dec")
print("PROXY polys=%d" % len(proxy.data.polygons))
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_NAME")   # пустые группы с именами костей + модификатор
dt = body.modifiers.new("wt", "DATA_TRANSFER")
dt.object = proxy
dt.use_vert_data = True
dt.data_types_verts = {"VGROUP_WEIGHTS"}
dt.vert_mapping = "POLYINTERP_NEAREST"
dt.layers_vgroup_select_src = "ALL"
dt.layers_vgroup_select_dst = "NAME"
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = body
body.select_set(True)
with bpy.context.temp_override(object=body):
    bpy.ops.object.datalayout_transfer(modifier="wt")
# модификатор переноса должен стоять перед арматурой
while body.modifiers[0].name != "wt":
    bpy.ops.object.modifier_move_up(modifier="wt")
bpy.ops.object.modifier_apply(modifier="wt")
bpy.data.objects.remove(proxy, do_unlink=True)

# Пальцы: на замкнутой копии они слиплись, поэтому долю кисти (Hand + все пальцы) делим заново —
# по расстоянию до оси каждой кости. Ладонь — «веер» отрезков от запястья к костяшкам.
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length
for side in ("Left", "Right"):
    bones = arm_data.bones
    chain = [side + "Hand"] + [side + n for n in FINGER_BONES]
    segs = {n: [(bones[n].head_local, bones[n].tail_local)] for n in chain[1:]}
    wrist = bones[side + "Hand"].head_local
    segs[chain[0]] = [(wrist, bones[side + "Hand%s1" % f].head_local) for f in FINGERS] + \
                     [(wrist, bones[side + "HandThumb1"].head_local)]
    gi = {body.vertex_groups[n].index: n for n in chain}
    groups = {n: body.vertex_groups[n] for n in chain}
    for v in body.data.vertices:
        total = sum(g.weight for g in v.groups if g.group in gi)
        if total < 1e-4:
            continue
        ws = {n: 1.0 / (min(seg_dist(v.co, a, b) for a, b in segs[n]) + 0.002) ** 8 for n in chain}
        s = sum(ws.values())
        for n in chain:
            w = total * ws[n] / s
            if w > 1e-3:
                groups[n].add([v.index], w, "REPLACE")
            else:
                groups[n].remove([v.index])
unweighted = sum(1 for v in body.data.vertices if not v.groups or max(g.weight for g in v.groups) < 1e-3)
print("WEIGHTS groups=%d unweighted_verts=%d of %d" % (len(body.vertex_groups), unweighted, len(body.data.vertices)))

# ---------------------------------------------------------------- позы
BONES = [b.name for b in arm_data.bones]
REST = {b.name: b.matrix_local.to_quaternion() for b in arm_data.bones}
ARMS = ("Shoulder", "Arm", "ForeArm", "Hand")

def lerp(a, b, f):
    return a + (b - a) * f

def smooth(f):
    f = max(0.0, min(1.0, f))
    return f * f * (3 - 2 * f)

def keys(t, pts, ease=smooth):
    """Плавная кривая по точкам [(время, значение), ...]; значения — числа."""
    if t <= pts[0][0]:
        return pts[0][1]
    for (t0, v0), (t1, v1) in zip(pts, pts[1:]):
        if t <= t1:
            return lerp(v0, v1, ease((t - t0) / (t1 - t0)))
    return pts[-1][1]

def bounce(f):
    """Падение с отскоком (как TRANS_BOUNCE, EASE_OUT)."""
    f = max(0.0, min(1.0, f))
    if f < 1 / 2.75: return 7.5625 * f * f
    if f < 2 / 2.75: f -= 1.5 / 2.75; return 7.5625 * f * f + 0.75
    if f < 2.5 / 2.75: f -= 2.25 / 2.75; return 7.5625 * f * f + 0.9375
    f -= 2.625 / 2.75; return 7.5625 * f * f + 0.984375

S = lambda x: math.sin(2 * math.pi * x)
C = lambda x: math.cos(2 * math.pi * x)

class Pose:
    def __init__(self):
        self.r = {n: [0.0, 0.0, 0.0] for n in BONES}
        self.loc = [0.0, 0.0, 0.0]     # смещение Hips в мировых осях (м)
        self.belly = 0.0               # «вдох» живота: 0 — как в модели
    def add(self, bone, rx=0.0, ry=0.0, rz=0.0):
        r = self.r[bone]; r[0] += rx; r[1] += ry; r[2] += rz
        return self
    def side(self, s, bone, rx=0.0, ry=0.0, rz=0.0):
        """s = 'L' / 'R'; числа — в «левых» обозначениях, правая сторона зеркалится."""
        if s == "R":
            return self.add("Right" + bone, rx, -ry, -rz)
        return self.add("Left" + bone, rx, ry, rz)
    def both(self, bone, rx=0.0, ry=0.0, rz=0.0):
        self.side("L", bone, rx, ry, rz); self.side("R", bone, rx, ry, rz)
        return self
    def move(self, x=0.0, y=0.0, z=0.0):
        self.loc[0] += x; self.loc[1] += y; self.loc[2] += z
        return self

# ---------------------------------------------------------------- кисти
# Пальцы: ry+ — сгиб к ладони (у всех трёх фаланг), rz — развести (+ к мизинцу).
# Большой палец: (к пальцам, к ладони, сгиб фаланг). «К пальцам» — разворот от «вперёд» к кончикам
# пальцев, «к ладони» — наклон вниз, под ладонь; фаланги гнутся вокруг собственной оси пальца.
# Позы кисти: (основные, средние, ногтевые фаланги), (большой: к пальцам, к ладони, согнуть), развести
HANDS = {
    "relax":  ((12, 18, 10), [5, 5, 10], 2),
    "flat":   ((0, 0, 0), [0, 0, 0], 0),
    "spread": ((-4, 0, 0), [-12, -5, 0], 10),
    "fist":   ((88, 100, 70), [45, 35, 35], -2),
    "bottle": ((52, 58, 40), [22, 45, 15], -1),     # обхват горлышка/бутылки Ø ~7 см
    "handle": ((75, 85, 55), [40, 35, 30], -2),    # ручка шпателя, ведра
    "phone":  ((6, 10, 30), [10, 25, 10], 0),      # пальцы прямые за телефоном, кончики за верхним краем, большой — на экране
    "bulb":   ((38, 42, 28), [30, 30, 15], 6),      # щепоть: держит лампочку
}

def hand(p, s, name, k=1.0, base="relax"):
    """Добавить позу кисти name поверх base с силой k (0..1). s = 'L' / 'R' / 'B' (обе)."""
    if s == "B":
        hand(p, "L", name, k, base); hand(p, "R", name, k, base)
        return p
    (c, th, sp), (c0, th0, sp0) = HANDS[name], HANDS[base]
    for i, f in enumerate(("Index", "Middle", "Ring", "Pinky")):
        m = 1 + 0.08 * i            # к мизинцу пальцы сгибаются чуть сильнее
        p.side(s, "Hand%s1" % f, ry=(c[0] - c0[0]) * m * k, rz=(sp - sp0) * (i - 1.2) * k)
        p.side(s, "Hand%s2" % f, ry=(c[1] - c0[1]) * m * k)
        p.side(s, "Hand%s3" % f, ry=(c[2] - c0[2]) * m * k)
    p.side(s, "HandThumb1", rz=(th[0] - th0[0]) * k, ry=(th[1] - th0[1]) * k)   # порядок ZYX, см. to_local
    thumb_curl(p, s, (th[2] - th0[2]) * k)
    return p

def thumb_curl(p, s, c):
    """Согнуть фаланги большого пальца на c градусов: ось сгиба ⟂ пальцу в плоскости ладони."""
    for n, m in (("HandThumb2", 0.7), ("HandThumb3", 1.0)):
        p.side(s, n, rx=0.83 * c * m, ry=0.55 * c * m)

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
    p.add("Hips", rx=88 * k)
    p.move(y=-0.25 * k, z=-0.46 * k)
    return p

# ---------------------------------------------------------------- анимации
ANIMS = {}
def anim(name, frames, loop=True):
    def deco(fn):
        ANIMS[name] = (fn, frames, loop)
        return fn
    return deco

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
PHONE = {"Arm": [-26.0, 10.0, -18.0], "ForeArm": [0.0, 0.0, -92.0], "Hand": [0.0, -10.0, 8.0]}

@anim("drink", 90)
def a_drink(t):
    p = stand(t)
    up = keys(t, [(0, 0), (0.22, 1), (0.72, 1), (0.88, 0), (1, 0)])
    tilt = keys(t, [(0, 0), (0.25, 0), (0.35, 1), (0.68, 1), (0.78, 0), (1, 0)])
    gulp = S(t * 6) * tilt
    # правая рука несёт бутылку ко рту: углы в DRINK подбирает solve() — горлышко в рот
    for b in ("Arm", "ForeArm", "Hand"):
        lift = DRINK_LIFT[b]
        p.side("R", b, *[up * lerp(lift[i], DRINK[b][i], tilt) for i in range(3)])
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
    """Меняет лампочку: руки вверх, правая крутит."""
    p = stand(t, breath=0.4)
    tw = S(t * 3)
    p.add("Spine", rx=-6); p.add("Spine2", rx=-6)
    p.add("Head", rx=-30)
    p.side("R", "Arm", ry=-150, rx=-10, rz=-10)
    p.side("R", "ForeArm", rz=-12, rx=40 * tw)
    p.side("R", "Hand", rx=30 * tw)
    p.side("L", "Arm", ry=-135, rx=-15, rz=-14)
    p.side("L", "ForeArm", rz=-20)
    p.move(z=0.01 * abs(tw))
    return p

@anim("phone", 60)
def a_phone(t):
    """Телефон (или геймпад) двумя руками перед животом, взгляд вниз."""
    p = stand(t, breath=0.6)
    tap = S(t * 8)
    for b in ("Arm", "ForeArm", "Hand"):     # углы в PHONE подбирает solve(): телефон экраном к глазам
        p.both(b, *PHONE[b])
    p.side("R", "Hand", rx=4 * tap)
    p.side("L", "Hand", rx=-4 * tap)
    p.add("Head", rx=26 + 2 * S(t * 2), rz=3 * S(t))
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
    p.both("Arm", ry=22 * k, rx=-20 * k)
    p.both("ForeArm", rz=8 * k)
    p.add("Head", rx=18 * k, rz=25 * k)
    p.both("Foot", rx=60 * k)
    return p

@anim("lie_forward", 120)
def a_lie_forward(t):
    p = stand(0, breath=0.0)
    lie_front_pose(p)
    p.both("Arm", ry=22, rx=-20)
    p.both("ForeArm", rz=8)
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

# ---------------------------------------------------------------- кисти по клипам
# Накладываются поверх позы тела (там уже стоит расслабленная кисть "relax").
def h_drink(p, t):
    hand(p, "R", "bottle")                               # бутылка в руке весь клип
    hand(p, "L", "spread", keys(t, [(0, 0), (0.2, 0.7), (0.8, 0.7), (1, 0)]))   # ладонь на животе

def h_work(p, t):
    hand(p, "R", "handle")                               # шпатель
    hand(p, "L", "handle", 0.9)                          # ведро / мастерок

def h_bulb(p, t):
    hand(p, "R", "bulb", 1 + 0.15 * S(t * 3))
    hand(p, "L", "flat")

def h_phone(p, t):
    hand(p, "B", "phone")
    tap = S(t * 8)
    thumb_curl(p, "R", 18 * max(0.0, tap))     # большие пальцы по очереди тыкают в экран
    thumb_curl(p, "L", 18 * max(0.0, -tap))

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

def h_sleep(p, t):
    hand(p, "B", "relax", 0.5, base="flat")              # расслабленно, пальцы чуть сильнее согнуты

HAND_LAYER = {"drink": h_drink, "work": h_work, "bulb": h_bulb, "phone": h_phone, "kick": h_kick,
              "angry": h_angry, "suspicious": h_suspicious, "catch": h_catch, "oath": h_oath,
              "dance": h_dance, "walk_drunk": h_walk_drunk, "fall_back": h_fall_back,
              "get_up": h_get_up, "sleep": h_sleep, "lie_back": h_sleep, "lie_forward": h_sleep}

# ---------------------------------------------------------------- запись в действия
rig.animation_data_create()
pbones = rig.pose.bones
for pb in pbones:
    pb.rotation_mode = "QUATERNION"

def to_local(name, rdeg):
    if any(name.endswith(a) for a in ARMS) and ("Left" in name or "Right" in name):
        order = "YXZ"
    elif name.endswith("HandThumb1"):
        order = "ZYX"      # сначала развернуть к пальцам, потом наклонить под ладонь
    else:
        order = "XYZ"
    q = Euler([math.radians(a) for a in rdeg], order).to_quaternion()
    B = REST[name]
    return B.inverted() @ q @ B

hips_rest = REST["Hips"]
_prev_q = {}

def apply_pose(p):
    for n in BONES:
        q = to_local(n, p.r[n])
        if n in _prev_q and _prev_q[n].dot(q) < 0:
            q.negate()
        _prev_q[n] = q
        pbones[n].rotation_quaternion = q
    pbones["Hips"].location = hips_rest.inverted() @ Vector(p.loc)
    b = p.belly * 0.06
    pbones["Belly"].scale = (1 + b * 0.6, 1 + b, 1 + b * 0.6)

# ---------------------------------------------------------------- решатель: рука к цели
# Подбирает углы (покоординатный спуск), чтобы предмет в руке оказался где нужно.
# Сетку на это время отключаем — считается только скелет.
def posed_point(n, rest_pt):
    return pbones[n].matrix @ arm_data.bones[n].matrix_local.inverted() @ Vector(rest_pt)

def posed_dir(n, rest_vec):
    d = pbones[n].matrix.to_3x3() @ arm_data.bones[n].matrix_local.to_3x3().inverted()
    return (d @ Vector(rest_vec)).normalized()

def bone_rest(n):
    b = arm_data.bones[n]
    return b.head_local.copy(), (b.tail_local - b.head_local).normalized()

# Пределы суставов (поверх стойки), (мин, макс) по rx, ry, rz. Локоть — шарнир: только сгиб (rz)
# и небольшой проворот предплечья (rx); вбок не гнётся.
LIMITS = {
    "Arm":     [(-150, 40), (-140, 60), (-80, 40)],
    "ForeArm": [(-85, 85), (0, 0), (-145, 0)],
    "Hand":    [(-60, 60), (-60, 60), (-50, 50)],
}

def solve(label, table, make_pose, cost, step=8.0):
    for m in body.modifiers:
        m.show_viewport = False
    def ev():
        apply_pose(make_pose())
        bpy.context.view_layer.update()
        return cost()
    best = ev()
    c0 = best
    keys_ = [(b, i) for b in table for i in range(3) if LIMITS[b][i][0] < LIMITS[b][i][1]]
    while step > 0.4:
        improved = False
        for b, i in keys_:
            for d in (step, -step):
                lo, hi = LIMITS[b][i]
                if not lo <= table[b][i] + d <= hi:
                    continue
                table[b][i] += d
                c = ev()
                if c < best - 1e-6:
                    best = c; improved = True
                    break
                table[b][i] -= d
        if not improved:
            step /= 2
    for m in body.modifiers:
        m.show_viewport = True
    print("SOLVE %-6s cost %.2f -> %.2f  %s" % (label, c0, best,
          {b: [round(v, 1) for v in table[b]] for b in table}))
    return best

def solve_starts(label, table, make_pose, cost, starts):
    """Несколько стартовых положений — берём лучший результат (спуск легко застревает)."""
    results = []
    for st in starts:
        for b in table:
            table[b][:] = st[b]
        results.append((solve(label, table, make_pose, cost), {b: list(table[b]) for b in table}))
    best, vals = min(results, key=lambda r: r[0])
    for b in table:
        table[b][:] = vals[b]
    print("SOLVE %s best %.2f" % (label, best))

MOUTH = (0.0, -0.145, 1.53)     # губы в позе покоя (по срезам головы)
EYES = (0.0, -0.10, 1.62)

def drink_cost():
    g_head, g_axis = bone_rest("RightHandGrip")
    c = posed_point("RightHandGrip", g_head)
    axis = posed_dir("RightHandGrip", g_axis)                 # к горлышку
    neck_tip = c + axis * 0.12
    mouth = posed_point("Head", MOUTH)
    want = Vector((0.15, 0.55, -0.82)).normalized()           # горлышко к лицу и вниз, дно вверх
    head_c = posed_point("Head", (0, 0.02, 1.58))
    clear = max(0.0, 0.15 - (c - head_c).length) * 100        # кулак не залезает в голову
    return ((neck_tip - mouth).length * 100) ** 2 + 300 * (1 - axis.dot(want)) + clear ** 2 * 4

def phone_cost():
    ph_head, ph_axis = bone_rest("RightHandPhone")
    c = posed_point("RightHandPhone", ph_head)
    up = posed_dir("RightHandPhone", ph_axis)                 # длинная сторона телефона
    normal = posed_dir("RightHandPhone", (0, 0, -1))          # куда смотрит экран
    eyes = posed_point("Head", EYES)
    target = Vector((0.0, -0.34, 1.24))                       # у груди, над животом
    to_eyes = (eyes - c).normalized()
    return ((c - target).length * 100) ** 2 + 400 * (1 - normal.dot(to_eyes)) + 150 * max(0.0, 0.7 - up.z) \
        + 200 * max(0.0, abs(c.x) - 0.01) * 100

def lift_cost():
    """Фаза подъёма (рука поднята, ещё не запрокинул): бутылка стоймя перед грудью."""
    g_head, g_axis = bone_rest("RightHandGrip")
    c = posed_point("RightHandGrip", g_head)
    axis = posed_dir("RightHandGrip", g_axis)
    target = Vector((-0.12, -0.36, 1.22))
    return ((c - target).length * 100) ** 2 + 300 * (1 - axis.dot(Vector((0.1, -0.15, 1)).normalized()))

# --- большой палец: для каждой позы кисти — куда должен лечь кончик (левая кисть в T-позе)
LIMITS["T"] = [(-40, 100), (-40, 100), (0, 95)]

def finger_pt(n, f=0.5):
    b = arm_data.bones["Left" + n]
    return posed_point("Left" + n, b.head_local.lerp(b.tail_local, f))

def thumb_tip():
    return finger_pt("HandThumb3", 1.0)

def thumb_pts():
    return [finger_pt("HandThumb2", 0.0), finger_pt("HandThumb3", 0.0), thumb_tip()]

DOWN = Vector((0, 0, -1))     # тыльная сторона согнутых пальцев (под ладонью)
BOTTLE_C, BOTTLE_R = Vector((0.805, 0.035, 1.15)), 0.035

def fist_cost():
    # кончик — поверх средней фаланги среднего пальца, сустав — поверх указательного
    a = finger_pt("HandMiddle2") + DOWN * 0.017
    b = finger_pt("HandIndex2") + DOWN * 0.017
    return ((thumb_tip() - a).length * 100) ** 2 + ((finger_pt("HandThumb3", 0.0) - b).length * 100) ** 2

def bottle_cost():
    target = Vector((0.778, -0.005, 1.114))                 # с другой стороны бутылки, у указательного
    pen = 0.0
    for q in thumb_pts():
        dxz = math.hypot(q.x - BOTTLE_C.x, q.z - BOTTLE_C.z)
        pen += max(0.0, BOTTLE_R + 0.009 - dxz) * 100
    return ((thumb_tip() - target).length * 100) ** 2 + 20 * pen ** 2

def phone_thumb_cost():
    return ((thumb_tip() - Vector((0.80, -0.012, 1.156))).length * 100) ** 2   # подушечка на экране

def bulb_cost():
    return ((thumb_tip() - (finger_pt("HandIndex3", 1.0) + DOWN * 0.012)).length * 100) ** 2

def thumb_pose(name):
    def mk():
        p = Pose()
        hand(p, "L", name, base="flat")
        return p
    return mk

for nm, cf in (("fist", fist_cost), ("handle", fist_cost), ("bottle", bottle_cost),
               ("phone", phone_thumb_cost), ("bulb", bulb_cost)):
    solve("T-" + nm, {"T": HANDS[nm][1]}, thumb_pose(nm), cf, step=10.0)

solve("drink", DRINK,lambda: (lambda p: (h_drink(p, 0.5), p)[1])(a_drink(0.5)), drink_cost)
solve("lift", DRINK_LIFT, lambda: (lambda p: (h_drink(p, 0.23), p)[1])(a_drink(0.23)), lift_cost)
solve_starts("phone", PHONE, lambda: (lambda p: (h_phone(p, 0.0), p)[1])(a_phone(0.0)), phone_cost, [
    {b: list(v) for b, v in PHONE.items()},
    {"Arm": [-40, 20, -30], "ForeArm": [60, 0, -110], "Hand": [0, 0, 0]},
    {"Arm": [-40, 20, -30], "ForeArm": [-60, 0, -110], "Hand": [0, 0, 0]},
    {"Arm": [-55, 15, -20], "ForeArm": [80, 0, -90], "Hand": [0, 30, 20]},
    {"Arm": [-55, 15, -20], "ForeArm": [-80, 0, -90], "Hand": [0, -30, 20]},
])

clips = {}
for name, (fn, frames, loop) in ANIMS.items():
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    _prev_q.clear()
    last = frames if loop else frames - 1
    for f in range(0, last + 1):
        t = (f / frames) if loop else (f / (frames - 1))
        if loop and f == frames:
            t = 0.0                       # последний кадр = первому, чтобы цикл был бесшовным
        p = fn(t)
        if name in HAND_LAYER:
            HAND_LAYER[name](p, t)
        apply_pose(p)
        for n in BONES:
            pbones[n].keyframe_insert("rotation_quaternion", frame=f + 1)
        pbones["Hips"].keyframe_insert("location", frame=f + 1)
        pbones["Belly"].keyframe_insert("scale", frame=f + 1)
    clips[name] = act
    print("ANIM %-13s %3d кадров %s" % (name, frames, "цикл" if loop else "разово"))

# каждое действие — своя NLA-дорожка: glTF экспортирует их как отдельные анимации
rig.animation_data.action = None
for pb in pbones:
    pb.rotation_quaternion = Quaternion(); pb.location = Vector(); pb.scale = Vector((1, 1, 1))
for name, act in clips.items():
    tr = rig.animation_data.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, 1, act)
    tr.mute = True

# понятные имена текстур (Godot вынимает их в файлы рядом с моделью)
for mat in body.data.materials:
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image and n.outputs[0].links:
            to = n.outputs[0].links[0].to_node
            kind = "normal" if to.type == "NORMAL_MAP" else "albedo" if to.type == "BSDF_PRINCIPLED" else to.type.lower()
            n.image.name = "texture_" + kind

if BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_animations=True,
    export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_range=False)
print("RIG_OK clips=%d %s" % (len(clips), sorted(clips)))
