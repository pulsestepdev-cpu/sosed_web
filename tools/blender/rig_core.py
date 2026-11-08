# Общий механизм для персонажей из Tripo (T-поза): чистка, скелет по точкам, веса, пальцы,
# позы, решатель «рука к цели», запись клипов и экспорт в GLB. Сами персонажи и их анимации —
# в rig_neighbor.py / rig_hero.py (они делают `from rig_core import *`).
#
# Анимации — функции позы от времени t (0..1). Углы — в градусах, в осях ПОКОЯ
# (T-поза, персонаж смотрит в -Y, его левая рука — в +X, вверх — +Z):
#   ноги/спина/голова (порядок XYZ):  rx+ — корпус/голова вперёд, бедро назад, голень сгибается,
#                                     стопа носком вниз; ry — наклон вбок; rz — поворот.
#   руки (порядок YXZ):  ry+ — опустить руку из T-позы, rx- — махнуть вперёд, rx+ — назад,
#                        rz- — завести внутрь, перед собой. Предплечье/кисть: rz- — согнуть.
#   пальцы: ry+ — сгиб к ладони, rz — развести; большой палец — см. hand().
# Правая сторона задаётся теми же числами, что левая (зеркалится автоматически).
import bpy, sys, math, mathutils
from mathutils import Vector, Euler, Quaternion

FPS = 30
body = rig = arm_data = pbones = None
BONES, REST = [], {}
FINGER_NAMES = ("Index", "Middle", "Ring", "Pinky")
FINGER_BONES = ["Hand%s%d" % (f, i) for f in FINGER_NAMES for i in (1, 2, 3)] + ["HandThumb%d" % i for i in (1, 2, 3)]
ARMS = ("Shoulder", "Arm", "ForeArm", "Hand")

def args():
    a = sys.argv[sys.argv.index("--") + 1:]
    return a[0], a[1], (a[2] if len(a) > 2 else None)

def _sm(f):
    f = max(0.0, min(1.0, f))
    return f * f * (3 - 2 * f)

# ---------------------------------------------------------------- модель
def load_model(src, height=1.75, max_tris=40000):
    """Импорт, сшивка швов Tripo, упрощение без порчи UV, рост/центр, матовый материал."""
    global body
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=src)
    body = max((o for o in bpy.context.scene.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
    for o in list(bpy.context.scene.objects):
        if o != body:
            bpy.data.objects.remove(o, do_unlink=True)
    body.name = "Body"
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.object.mode_set(mode="OBJECT")
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    if tris > max_tris:
        m = body.modifiers.new("dec", "DECIMATE")
        m.ratio = max_tris / tris
        m.delimit = {"UV", "SEAM"}
        bpy.ops.object.modifier_apply(modifier="dec")
    vs = [v.co for v in body.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    k = height / (mx.z - mn.z)
    off = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    for v in body.data.vertices:
        v.co = (v.co - off) * k
    body.data.update()
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
    return body

# ---------------------------------------------------------------- скелет
def build_skeleton(center, side, fingers, thumb, grip, phone):
    """center/side — [(имя, голова, хвост, родитель)], side — для левой стороны (+X).
    fingers — {палец: (костяшка, кончик)}, thumb — 4 точки, grip/phone — (голова, хвост) точек-предметов:
      HandGrip  — центр кулака; ось кости = ось бутылки, смотрит к горлышку (к большому пальцу).
      HandPhone — центр телефона на ладони экраном от неё; ось кости = длинная сторона телефона."""
    global rig, arm_data, BONES, REST, pbones
    side = list(side)
    for f, (a, b) in fingers.items():
        a, b = Vector(a), Vector(b)
        pts = [a, a.lerp(b, 0.45), a.lerp(b, 0.75), b]
        for i in range(3):
            side.append(("Hand%s%d" % (f, i + 1), tuple(pts[i]), tuple(pts[i + 1]),
                         "Hand" if i == 0 else "Hand%s%d" % (f, i)))
    for i in range(3):
        side.append(("HandThumb%d" % (i + 1), thumb[i], thumb[i + 1], "Hand" if i == 0 else "HandThumb%d" % i))
    side.append(("HandGrip", grip[0], grip[1], "Hand"))
    side.append(("HandPhone", phone[0], phone[1], "Hand"))
    arm_data = bpy.data.armatures.new("Rig")
    rig = bpy.data.objects.new("Rig", arm_data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    centers = {c[0] for c in center}
    def add_bone(name, h, t, parent):
        b = eb.new(name)
        b.head, b.tail = Vector(h), Vector(t)
        b.roll = 0
        if parent:
            b.parent = eb[parent]
            b.use_connect = (b.parent.tail - b.head).length < 1e-4 and name != "Belly"
        b.use_deform = not name.endswith(("Grip", "Phone"))
    for n, h, t, p in center:
        add_bone(n, h, t, p)
    for s, sx in (("Left", 1), ("Right", -1)):
        for n, h, t, p in side:
            add_bone(s + n, (h[0] * sx, h[1], h[2]), (t[0] * sx, t[1], t[2]),
                     None if p is None else (p if p in centers else s + p))
    bpy.ops.object.mode_set(mode="OBJECT")
    BONES[:] = [b.name for b in arm_data.bones]
    REST.clear(); REST.update({b.name: b.matrix_local.to_quaternion() for b in arm_data.bones})
    pbones = rig.pose.bones
    rig.animation_data_create()
    for pb in pbones:
        pb.rotation_mode = "QUATERNION"

# ---------------------------------------------------------------- веса
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length

def make_weights(voxel=0.009):
    """Сетка Tripo не замкнутая — тепловая карта на ней не сходится. Поэтому: замкнутая копия
    через voxel-remesh -> веса на ней -> перенос на настоящую сетку. Пальцы делятся отдельно."""
    proxy = body.copy()
    proxy.data = body.data.copy()
    proxy.name = "WeightProxy"
    bpy.context.scene.collection.objects.link(proxy)
    proxy.data.materials.clear()
    rm = proxy.modifiers.new("vox", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = proxy
    proxy.select_set(True)
    bpy.ops.object.modifier_apply(modifier="vox")
    dm = proxy.modifiers.new("dec", "DECIMATE")
    dm.ratio = min(1.0, 30000 / max(1, len(proxy.data.polygons)))
    bpy.ops.object.modifier_apply(modifier="dec")
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
    while body.modifiers[0].name != "wt":           # перенос — перед арматурой
        bpy.ops.object.modifier_move_up(modifier="wt")
    bpy.ops.object.modifier_apply(modifier="wt")
    bpy.data.objects.remove(proxy, do_unlink=True)

    # Пальцы: на замкнутой копии они слиплись — долю кисти (Hand + пальцы) делим заново по
    # расстоянию до оси каждой кости. Ладонь — «веер» отрезков от запястья к костяшкам.
    bones = arm_data.bones
    for s in ("Left", "Right"):
        chain = [s + "Hand"] + [s + n for n in FINGER_BONES]
        segs = {n: [(bones[n].head_local, bones[n].tail_local)] for n in chain[1:]}
        wrist = bones[s + "Hand"].head_local
        segs[chain[0]] = [(wrist, bones[s + "Hand%s1" % f].head_local) for f in FINGER_NAMES] + \
                         [(wrist, bones[s + "HandThumb1"].head_local)]
        gi = {body.vertex_groups[n].index: n for n in chain}
        groups = {n: body.vertex_groups[n] for n in chain}
        for v in body.data.vertices:
            total = sum(g.weight for g in v.groups if g.group in gi)
            if total < 1e-4:
                continue
            ws = {n: 1.0 / (min(seg_dist(v.co, a, b) for a, b in segs[n]) + 0.002) ** 8 for n in chain}
            sm = sum(ws.values())
            for n in chain:
                w = total * ws[n] / sm
                if w > 1e-3:
                    groups[n].add([v.index], w, "REPLACE")
                else:
                    groups[n].remove([v.index])

def boost_group(name, weight_fn):
    """Отдать кости name долю веса вершин: weight_fn(co) -> 0..1 (остальные группы ужимаются)."""
    g0 = body.vertex_groups[name]
    for v in body.data.vertices:
        k = weight_fn(v.co)
        if k < 0.02:
            continue
        for g in v.groups:
            if g.group != g0.index:
                g.weight *= (1 - k)
        old = next((g.weight for g in v.groups if g.group == g0.index), 0.0)
        g0.add([v.index], old * (1 - k) + k, "REPLACE")

def report_weights():
    un = sum(1 for v in body.data.vertices if not v.groups or max(g.weight for g in v.groups) < 1e-3)
    print("WEIGHTS groups=%d unweighted_verts=%d of %d" % (len(body.vertex_groups), un, len(body.data.vertices)))

# ---------------------------------------------------------------- помощники для поз
def lerp(a, b, f):
    return a + (b - a) * f

def smooth(f):
    return _sm(f)

def keys(t, pts, ease=smooth):
    """Плавная кривая по точкам [(время, значение), ...]."""
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
        self.belly = 0.0               # «вдох» живота (если есть кость Belly)
        self.squash = 0.0              # живот сплющен о пол (0..1)
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
# Позы кисти: (основные, средние, ногтевые фаланги), [большой: к пальцам, к ладони, согнуть], развести.
# Большой палец: «к пальцам» — разворот от «вперёд» к кончикам пальцев, «к ладони» — наклон под
# ладонь; фаланги гнутся вокруг собственной оси пальца. Для хватов большой палец подбирает solve_thumbs().
HANDS = {
    "relax":  ((12, 18, 10), [5, 5, 10], 2),
    "flat":   ((0, 0, 0), [0, 0, 0], 0),
    "spread": ((-4, 0, 0), [-12, -5, 0], 10),
    "fist":   ((88, 100, 70), [45, 35, 35], -2),
    "bottle": ((52, 58, 40), [22, 45, 15], -1),    # обхват бутылки Ø ~7 см
    "handle": ((75, 85, 55), [40, 35, 30], -2),    # ручка, перекладина
    "phone":  ((6, 10, 30), [10, 25, 10], 0),      # пальцы за телефоном, большой — на экране
    "bulb":   ((38, 42, 28), [30, 30, 15], 6),     # щепоть
    "claw":   ((30, 45, 35), [10, 20, 20], 6),     # «крадущиеся» пальцы
}

def hand(p, s, name, k=1.0, base="relax"):
    """Добавить позу кисти name поверх base с силой k (0..1). s = 'L' / 'R' / 'B' (обе)."""
    if s == "B":
        hand(p, "L", name, k, base); hand(p, "R", name, k, base)
        return p
    (c, th, sp), (c0, th0, sp0) = HANDS[name], HANDS[base]
    for i, f in enumerate(FINGER_NAMES):
        m = 1 + 0.08 * i            # к мизинцу пальцы сгибаются чуть сильнее
        p.side(s, "Hand%s1" % f, ry=(c[0] - c0[0]) * m * k, rz=(sp - sp0) * (i - 1.2) * k)
        p.side(s, "Hand%s2" % f, ry=(c[1] - c0[1]) * m * k)
        p.side(s, "Hand%s3" % f, ry=(c[2] - c0[2]) * m * k)
    p.side(s, "HandThumb1", rz=(th[0] - th0[0]) * k, ry=(th[1] - th0[1]) * k)   # порядок ZYX
    thumb_curl(p, s, (th[2] - th0[2]) * k)
    return p

def thumb_curl(p, s, c):
    """Согнуть фаланги большого пальца на c градусов: ось сгиба ⟂ пальцу в плоскости ладони."""
    for n, m in (("HandThumb2", 0.7), ("HandThumb3", 1.0)):
        p.side(s, n, rx=0.83 * c * m, ry=0.55 * c * m)

# ---------------------------------------------------------------- анимации
ANIMS = {}
def anim(name, frames, loop=True):
    def deco(fn):
        ANIMS[name] = (fn, frames, loop)
        return fn
    return deco

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

_prev_q = {}

def apply_pose(p):
    for n in BONES:
        q = to_local(n, p.r[n])
        if n in _prev_q and _prev_q[n].dot(q) < 0:
            q.negate()
        _prev_q[n] = q
        pbones[n].rotation_quaternion = q
    pbones["Hips"].location = REST["Hips"].inverted() @ Vector(p.loc)
    if "Belly" in pbones:
        b = p.belly * 0.06
        sq = p.squash
        pbones["Belly"].scale = ((1 + b * 0.6) * (1 + 0.4 * sq), (1 + b) * (1 - 0.75 * sq),
                                 (1 + b * 0.6) * (1 + 0.4 * sq))

# ---------------------------------------------------------------- решатель: рука к цели
# Покоординатный спуск по углам, чтобы предмет в руке оказался где нужно. Сетка на это время
# отключена — считается только скелет.
def posed_point(n, rest_pt):
    return pbones[n].matrix @ arm_data.bones[n].matrix_local.inverted() @ Vector(rest_pt)

def posed_dir(n, rest_vec):
    d = pbones[n].matrix.to_3x3() @ arm_data.bones[n].matrix_local.to_3x3().inverted()
    return (d @ Vector(rest_vec)).normalized()

def bone_rest(n):
    b = arm_data.bones[n]
    return b.head_local.copy(), (b.tail_local - b.head_local).normalized()

# Пределы суставов (поверх стойки), (мин, макс) по rx, ry, rz. Локоть — шарнир: только сгиб (rz)
# и проворот предплечья (rx); вбок не гнётся.
LIMITS = {
    "Arm":     [(-150, 40), (-165, 60), (-80, 40)],
    "ForeArm": [(-85, 85), (0, 0), (-145, 0)],
    "Hand":    [(-60, 60), (-60, 60), (-50, 50)],
    "T":       [(-40, 100), (-40, 100), (0, 95)],
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
    ks = [(b, i) for b in table for i in range(3) if LIMITS[b][i][0] < LIMITS[b][i][1]]
    while step > 0.4:
        improved = False
        for b, i in ks:
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
    print("SOLVE %-8s cost %.2f -> %.2f  %s" % (label, c0, best,
          {b: [round(v, 1) for v in table[b]] for b in table}))
    return best

def solve_starts(label, table, make_pose, cost, starts):
    """Несколько стартовых положений — берём лучший результат (спуск легко застревает)."""
    results = []
    for st in [{b: list(v) for b, v in table.items()}] + starts:
        for b in table:
            table[b][:] = st[b]
        results.append((solve(label, table, make_pose, cost), {b: list(table[b]) for b in table}))
    best, vals = min(results, key=lambda r: r[0])
    for b in table:
        table[b][:] = vals[b]
    print("SOLVE %s best %.2f" % (label, best))

def at(fn, layer, t):
    """make_pose для решателя: поза клипа fn (+ слой кистей) в момент t."""
    def mk():
        p = fn(t)
        if layer:
            layer(p, t)
        return p
    return mk

# --- большой палец: для каждой позы кисти — куда должен лечь кончик (левая кисть в T-позе)
def finger_pt(n, f=0.5):
    b = arm_data.bones["Left" + n]
    return posed_point("Left" + n, b.head_local.lerp(b.tail_local, f))

def solve_thumbs(names=("fist", "handle", "bottle", "phone", "bulb", "claw")):
    DOWN = Vector((0, 0, -1))          # тыльная сторона согнутых пальцев (под ладонью)
    grip = arm_data.bones["LeftHandGrip"].head_local
    phone = arm_data.bones["LeftHandPhone"].head_local
    tip = lambda: finger_pt("HandThumb3", 1.0)
    def fist_cost():   # кончик — поверх средней фаланги среднего, сустав — поверх указательного
        a = finger_pt("HandMiddle2") + DOWN * 0.017
        b = finger_pt("HandIndex2") + DOWN * 0.017
        return ((tip() - a).length * 100) ** 2 + ((finger_pt("HandThumb3", 0.0) - b).length * 100) ** 2
    def bottle_cost():  # с другой стороны бутылки, у указательного; сквозь бутылку не проходит
        target = grip + Vector((-0.027, -0.04, -0.036))
        pen = 0.0
        for q in (finger_pt("HandThumb2", 0.0), finger_pt("HandThumb3", 0.0), tip()):
            pen += max(0.0, 0.044 - math.hypot(q.x - grip.x, q.z - grip.z)) * 100
        return ((tip() - target).length * 100) ** 2 + 20 * pen ** 2
    def phone_cost():   # подушечка на экране
        return ((tip() - (phone + Vector((0.022, -0.015, -0.0105)))).length * 100) ** 2
    def pinch_cost():   # щепоть: к кончику указательного
        return ((tip() - (finger_pt("HandIndex3", 1.0) + DOWN * 0.012)).length * 100) ** 2
    costs = {"fist": fist_cost, "handle": fist_cost, "bottle": bottle_cost, "phone": phone_cost,
             "bulb": pinch_cost, "claw": pinch_cost}
    for nm in names:
        def mk(nm=nm):
            p = Pose()
            hand(p, "L", nm, base="flat")
            return p
        solve("T-" + nm, {"T": HANDS[nm][1]}, mk, costs[nm], step=10.0)

# ---------------------------------------------------------------- запись и экспорт
def record(hand_layer=None):
    hand_layer = hand_layer or {}
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
                t = 0.0                       # последний кадр = первому: цикл бесшовный
            p = fn(t)
            if name in hand_layer:
                hand_layer[name](p, t)
            apply_pose(p)
            for n in BONES:
                pbones[n].keyframe_insert("rotation_quaternion", frame=f + 1)
            pbones["Hips"].keyframe_insert("location", frame=f + 1)
            if "Belly" in pbones:
                pbones["Belly"].keyframe_insert("scale", frame=f + 1)
        clips[name] = act
        print("ANIM %-14s %3d кадров %s" % (name, frames, "цикл" if loop else "разово"))
    # каждое действие — своя NLA-дорожка: glTF экспортирует их как отдельные анимации
    rig.animation_data.action = None
    for pb in pbones:
        pb.rotation_quaternion = Quaternion(); pb.location = Vector(); pb.scale = Vector((1, 1, 1))
    for name, act in clips.items():
        tr = rig.animation_data.nla_tracks.new()
        tr.name = name
        tr.strips.new(name, 1, act)
        tr.mute = True
    return clips

def export(dst, blend=None):
    # понятные имена текстур (Godot вынимает их в файлы рядом с моделью)
    for mat in body.data.materials:
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image and n.outputs[0].links:
                to = n.outputs[0].links[0].to_node
                kind = "normal" if to.type == "NORMAL_MAP" else "albedo" if to.type == "BSDF_PRINCIPLED" else to.type.lower()
                n.image.name = "texture_" + kind
    if blend:
        bpy.ops.wm.save_as_mainfile(filepath=blend)
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_animations=True,
        export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_range=False)
    print("RIG_OK clips=%d %s" % (len(ANIMS), sorted(ANIMS)))
