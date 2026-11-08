# Выражения лица — варианты основной текстуры персонажа (лицо нарисовано на текстуре, костей лица нет).
# blender -b <персонаж_rig.blend> -P tools/blender/face_textures.py -- <neighbor|hero> <папка_вывода> [проверка.png]
#
# Точки лица задаются в 3D (поза покоя, метры): луч спереди попадает в сетку, оттуда берётся UV и местный
# масштаб (сколько пикселей в сантиметре по горизонтали/вертикали лица). Рисование — в «плоскости лица»:
# dx — вбок (+ к левому плечу персонажа), dz — вверх, в метрах; поэтому формы не зависят от раскладки UV.
# Игра меняет выражение подменой текстуры: <персонаж>_face_<выражение>.jpg.
import bpy, sys, os, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

a = sys.argv[sys.argv.index("--") + 1:]
CHAR, OUT = a[0], a[1]
CHECK = a[2] if len(a) > 2 else None

# точки лица (по рендерам головы с метками высоты)
FACES = {
    "neighbor": dict(eyes=[(0.064, 1.55), (-0.064, 1.55)], eye_r=(0.027, 0.012), brow_dz=0.03,
                     cheeks=[(0.075, 1.49), (-0.075, 1.49)], nose=(0.0, 1.49), mouth=(0.0, 1.433),
                     mouth_r=(0.026, 0.012), skin=(0.03, 1.61), lash=(0.25, 0.14, 0.10)),
    "hero":     dict(eyes=[(0.069, 1.453), (-0.069, 1.453)], eye_r=(0.033, 0.016), brow_dz=0.062,
                     cheeks=[(0.088, 1.415), (-0.088, 1.415)], nose=(0.0, 1.405), mouth=(0.0, 1.352),
                     mouth_r=(0.03, 0.015), skin=(0.0, 1.488), lash=(0.35, 0.16, 0.08)),
}
F = FACES[CHAR]

body = bpy.data.objects["Body"]
me = body.data
me.calc_loop_triangles()
verts = [v.co.copy() for v in me.vertices]
tris = [tuple(t.vertices) for t in me.loop_triangles]
bvh = BVHTree.FromPolygons(verts, tris)
uv_layer = me.uv_layers.active.data

mat = body.data.materials[0]
tex_node = next(n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.outputs[0].links
                and n.outputs[0].links[0].to_node.type == "BSDF_PRINCIPLED")
src = tex_node.image
W, H = src.size
BASE = np.array(src.pixels[:], dtype=np.float32).reshape(H, W, 4)

def uv_at(x, z):
    hit, _, idx, _ = bvh.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)))
    if hit is None:
        raise RuntimeError("луч не попал в лицо: %.3f %.3f" % (x, z))
    t = me.loop_triangles[idx]
    w = poly_3d_calc([verts[i] for i in t.vertices], hit)
    uv = sum((uv_layer[l].uv * wi for l, wi in zip(t.loops, w)), Vector((0, 0)))
    return np.array([uv.x * W, uv.y * H])

def frame(x, z):
    """Пиксель точки и матрица «метры лица -> пиксели» (местная, по двум соседним точкам)."""
    p0 = uv_at(x, z)
    e = 0.004
    J = np.stack([(uv_at(x + e, z) - p0) / e, (uv_at(x, z + e) - p0) / e], axis=1)
    return p0, J

# Карта положений: для каждого пикселя текстуры лица — его точка на 3D-сетке. Лицо в атласе Tripo порезано
# на мелкие куски, поэтому рисуем не по соседним пикселям, а по настоящим координатам на голове.
def _position_map():
    zmin = min(z for _, z in F["eyes"]) - 0.25
    px_l, py_l, P_l = [], [], []
    for t in me.loop_triangles:
        vs3 = [verts[i] for i in t.vertices]
        if min(v.z for v in vs3) < zmin or min(v.y for v in vs3) > 0.06:
            continue
        uv = np.array([[uv_layer[l].uv.x * W, uv_layer[l].uv.y * H] for l in t.loops])
        x0, y0 = np.floor(uv.min(0)).astype(int); x1, y1 = np.ceil(uv.max(0)).astype(int)
        if x1 - x0 > 200 or y1 - y0 > 200:
            continue
        ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
        q = np.stack([xs + 0.5, ys + 0.5], -1).reshape(-1, 2)
        a, b, c = uv
        m = np.array([[b[0] - a[0], c[0] - a[0]], [b[1] - a[1], c[1] - a[1]]])
        if abs(np.linalg.det(m)) < 1e-9:
            continue
        l12 = (q - a) @ np.linalg.inv(m).T
        l0 = 1 - l12.sum(1)
        inside = (l0 >= -0.02) & (l12[:, 0] >= -0.02) & (l12[:, 1] >= -0.02)
        if not inside.any():
            continue
        P = np.array([[v.x, v.y, v.z] for v in vs3])
        pts = l0[inside, None] * P[0] + l12[inside, 0:1] * P[1] + l12[inside, 1:2] * P[2]
        qq = q[inside].astype(int)
        px_l.append(qq[:, 0]); py_l.append(qq[:, 1]); P_l.append(pts)
    px = np.clip(np.concatenate(px_l), 0, W - 1); py = np.clip(np.concatenate(py_l), 0, H - 1)
    return px, py, np.concatenate(P_l)

TX, TY, TP = _position_map()
print("POSMAP texels=%d" % len(TX))

def region(img, cx, cz, rx, rz, fn):
    """Вызвать fn(dx, dz) -> (маска 0..1, цвет) для пикселей лица вокруг точки (cx, cz); смешать с картинкой."""
    sel = (np.abs(TP[:, 0] - cx) < rx * 1.25) & (np.abs(TP[:, 2] - cz) < rz * 1.25) & (TP[:, 1] < 0.02)
    if not sel.any():
        return
    dx, dz = TP[sel, 0] - cx, TP[sel, 2] - cz
    m, col = fn(dx, dz)
    m = np.clip(m, 0, 1)[:, None]
    col = np.asarray(col, dtype=np.float32)[..., :3]
    xs, ys = TX[sel], TY[sel]
    img[ys, xs, :3] = img[ys, xs, :3] * (1 - m) + col * m

def soft(v, edge):
    """1 внутри (v<1), плавный край шириной edge."""
    return np.clip((1 + edge - v) / edge, 0, 1)

def sample(x, z, r=0.004):
    p = uv_at(x, z).astype(int)
    k = 3
    return BASE[p[1] - k:p[1] + k, p[0] - k:p[0] + k, :3].reshape(-1, 3).mean(0)

SKIN = sample(*F["skin"])
LID = SKIN * 0.92
LASH = np.array(F["lash"])
RX, RZ = F["eye_r"]

# ---------------------------------------------------------------- приёмы рисования
def blush(img, x, z, r, k, col=(0.86, 0.25, 0.2)):
    region(img, x, z, r, r, lambda dx, dz: (np.clip(1 - np.hypot(dx, dz) / r, 0, 1) ** 1.5 * k, col))

def eyelid(img, frac, slant=0.0):
    """Опустить верхние веки на долю frac высоты глаза (1 — закрыт). slant — злой наклон к переносице."""
    for i, (ex, ez) in enumerate(F["eyes"]):
        side = 1 if ex > 0 else -1
        def fn(dx, dz, side=side):
            inside = soft((dx / (RX * 1.18)) ** 2 + (dz / (RZ * 1.35)) ** 2, 0.25)
            edge = RZ * 1.35 - 2 * RZ * 1.35 * frac + slant * RZ * (-side * dx / RX)   # линия края века
            lid = np.clip((dz - edge) / (RZ * 0.25), 0, 1) * inside
            return lid, LID
        region(img, ex, ez, RX * 1.3, RZ * 1.5, fn)
        def line(dx, dz, side=side):                                               # тёмный край века
            edge = RZ * 1.35 - 2 * RZ * 1.35 * frac + slant * RZ * (-side * dx / RX)
            within = soft((dx / (RX * 1.12)) ** 2, 0.2)
            return soft(np.abs(dz - edge) / (RZ * 0.22), 0.6) * within, LASH
        region(img, ex, ez, RX * 1.3, RZ * 1.5, line)

def eyes_closed(img, happy=False):
    """Глаза закрыты: веко целиком + ресничная дуга (вниз — спит, вверх «^^» — радуется)."""
    for ex, ez in F["eyes"]:
        region(img, ex, ez, RX * 1.3, RZ * 1.6,
               lambda dx, dz: (soft((dx / (RX * 1.2)) ** 2 + (dz / (RZ * 1.45)) ** 2, 0.2), LID))
        def arc(dx, dz):
            u = np.clip(dx / (RX * 1.05), -1, 1)
            cz = (RZ * 0.55 * (u * u) - RZ * 0.35) if not happy else (-RZ * 0.8 * (u * u) + RZ * 0.45)
            within = soft((dx / (RX * 1.05)) ** 2, 0.15)
            return soft(np.abs(dz - cz) / (RZ * 0.28), 0.5) * within, LASH
        region(img, ex, ez, RX * 1.3, RZ * 1.6, arc)

def eyes_wide(img):
    """Глаза навыкате: большой белок, крошечный зрачок, блик."""
    for ex, ez in F["eyes"]:
        region(img, ex, ez, RX * 1.5, RZ * 1.9,
               lambda dx, dz: (soft((dx / (RX * 1.3)) ** 2 + (dz / (RZ * 1.75)) ** 2, 0.12), (0.97, 0.96, 0.93)))
        region(img, ex, ez, RX * 1.5, RZ * 1.9,
               lambda dx, dz: (soft(np.abs(np.sqrt((dx / (RX * 1.3)) ** 2 + (dz / (RZ * 1.75)) ** 2) - 1) / 0.05, 0.6),
                               LASH))
        pr = RZ * 0.42
        region(img, ex, ez, pr * 1.3, pr * 1.3, lambda dx, dz: (soft(np.hypot(dx, dz) / pr, 0.2), (0.08, 0.06, 0.05)))
        region(img, ex + pr * 0.4, ez + pr * 0.45, pr * 0.5, pr * 0.5,
               lambda dx, dz: (soft(np.hypot(dx, dz) / (pr * 0.32), 0.3), (1, 1, 1)))

def brows(img, dz_up, tilt):
    """Нарисовать брови: dz_up — сдвиг вверх от обычного места, tilt>0 — «домиком» (испуг), <0 — злые."""
    bz = F["brow_dz"]
    for ex, ez in F["eyes"]:
        side = 1 if ex > 0 else -1
        def fn(dx, dz, side=side):
            u = np.clip(dx * side / (RX * 1.2), -1, 1)                               # -1 у переносицы, +1 снаружи
            cz = bz + dz_up - tilt * RZ * 0.9 * u + RZ * 0.25 * (1 - u * u)
            within = soft((dx / (RX * 1.2)) ** 2, 0.2)
            return soft(np.abs(dz - cz) / (RZ * 0.4), 0.5) * within, LASH * 0.8
        region(img, ex, ez, RX * 1.5, bz + dz_up + RZ * 2, fn)

def hide_brows(img):
    for ex, ez in F["eyes"]:
        region(img, ex, ez + F["brow_dz"], RX * 1.4, RZ * 1.2,
               lambda dx, dz: (soft((dx / (RX * 1.35)) ** 2 + (dz / (RZ * 1.0)) ** 2, 0.4), SKIN))

def mouth_open(img, rx, rz):
    mx, mz = F["mouth"]
    region(img, mx, mz, rx * 1.3, rz * 1.4,
           lambda dx, dz: (soft((dx / rx) ** 2 + (dz / rz) ** 2, 0.15), (0.28, 0.07, 0.06)))
    region(img, mx, mz + rz * 0.55, rx * 1.1, rz * 0.6,
           lambda dx, dz: (soft((dx / (rx * 0.75)) ** 2 + (dz / (rz * 0.3)) ** 2, 0.2), (0.95, 0.93, 0.88)))
    region(img, mx, mz, rx * 1.3, rz * 1.4,
           lambda dx, dz: (soft(np.abs(np.sqrt((dx / rx) ** 2 + (dz / rz) ** 2) - 1) / 0.12, 0.5), LASH * 0.7))

def sweat(img):
    ex, ez = F["eyes"][0]
    x, z = ex + RX * 1.9, ez + RZ * 2.5
    r = RZ * 0.8
    region(img, x, z, r * 1.5, r * 2.5, lambda dx, dz: (
        soft(np.hypot(dx / r, np.maximum(dz, 0) / (r * 2.2) + np.minimum(dz, 0) / r * 0 + np.minimum(dz, 0) / r), 0.2),
        (0.55, 0.8, 0.98)))

def tint(img, k, col):
    cx, cz = F["nose"]
    R = RX * 4.5
    region(img, cx, cz + RZ, R, R, lambda dx, dz: (np.clip(1 - np.hypot(dx, dz * 0.9) / R, 0, 1) ** 0.8 * k, col))

# ---------------------------------------------------------------- выражения
def red_face(img, k):
    for (x, z) in F["cheeks"]:
        blush(img, x, z, RX * 1.7, 0.6 * k)
    blush(img, F["nose"][0], F["nose"][1], RX * 1.25, 0.8 * k, (0.85, 0.18, 0.15))

EXPR = {
    "neighbor": {
        "normal": [],
        "tipsy":  [lambda i: red_face(i, 0.55), lambda i: eyelid(i, 0.3)],
        "drunk":  [lambda i: red_face(i, 1.0), lambda i: eyelid(i, 0.52)],
        "sleep":  [lambda i: red_face(i, 0.6), lambda i: eyes_closed(i)],
        "angry":  [lambda i: tint(i, 0.35, (0.85, 0.2, 0.15)), lambda i: eyelid(i, 0.25, slant=0.9),
                   lambda i: brows(i, -0.004, -0.9)],
        "happy":  [lambda i: red_face(i, 0.5), lambda i: eyes_closed(i, happy=True)],
    },
    "hero": {
        "normal": [],
        "scared": [lambda i: tint(i, 0.18, (0.75, 0.85, 0.95)), lambda i: hide_brows(i), lambda i: eyes_wide(i),
                   lambda i: brows(i, 0.012, 0.8), lambda i: mouth_open(i, F["mouth_r"][0] * 0.75, F["mouth_r"][1] * 1.4),
                   lambda i: sweat(i)],
        "happy":  [lambda i: red_face(i, 0.4), lambda i: eyes_closed(i, happy=True)],
        "sneaky": [lambda i: eyelid(i, 0.35)],
    },
}

INMAP = np.zeros((H, W), bool)
INMAP[TY, TX] = True

def seal_seams(img, steps=3):
    """Залатать швы: пиксели на краях кусков атласа (их нет в карте положений) берут цвет нарисованных соседей."""
    changed = np.abs(img[..., :3] - BASE[..., :3]).max(-1) > 1e-4
    for _ in range(steps):
        acc = np.zeros((H, W, 3), np.float32); cnt = np.zeros((H, W), np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh_c = np.roll(changed, (dy, dx), (0, 1)); sh_i = np.roll(img[..., :3], (dy, dx), (0, 1))
            acc += sh_i * sh_c[..., None]; cnt += sh_c
        cand = (~changed) & (~INMAP) & (cnt > 0)
        img[cand, :3] = acc[cand] / cnt[cand, None]
        changed |= cand

os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
sc.render.image_settings.file_format = "JPEG"
sc.render.image_settings.quality = 92
made = {}
for name, ops in EXPR[CHAR].items():
    img = BASE.copy()
    for op in ops:
        op(img)
    seal_seams(img)
    im = bpy.data.images.new("%s_face_%s" % (CHAR, name), W, H)
    im.pixels = img.ravel()
    path = os.path.join(OUT, "%s_face_%s.jpg" % (CHAR, name))
    im.save_render(path)
    made[name] = im
    print("FACE", name, path)

# ---------------------------------------------------------------- проверка: головы с каждым выражением
if CHECK:
    rig = next(o for o in sc.objects if o.type == "ARMATURE")
    if rig.animation_data:
        rig.animation_data.action = None
        for t in rig.animation_data.nla_tracks:
            t.mute = True
    for pb in rig.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0); pb.scale = (1, 1, 1)
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 360
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("W"); sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.8, 0.78, 0.72, 1)
    bpy.ops.object.light_add(type="SUN", rotation=(0.6, 0.0, 0.3)); bpy.context.active_object.data.energy = 3
    cd = bpy.data.cameras.new("C"); cd.type = "ORTHO"; cd.ortho_scale = 0.34
    cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
    ex, ez = F["eyes"][0]
    tgt = Vector((0, -0.05, (ez + F["mouth"][1]) / 2 + 0.01))
    cam.location = tgt + Vector((0, -1, 0)); cam.rotation_euler = Vector((0, 1, 0)).to_track_quat("-Z", "Y").to_euler()
    names = list(made)
    sheet = np.zeros((360, 360 * len(names), 4), dtype=np.float32)
    tmp = os.path.join(os.path.dirname(CHECK), "_face.png")
    for i, n in enumerate(names):
        tex_node.image = made[n]
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(tmp, check_existing=False)
        sheet[:, i * 360:(i + 1) * 360] = np.array(im.pixels[:], dtype=np.float32).reshape(360, 360, 4)
        bpy.data.images.remove(im)
    res = bpy.data.images.new("faces", 360 * len(names), 360, alpha=True)
    res.pixels = sheet.ravel(); res.filepath_raw = CHECK; res.file_format = "PNG"; res.save()
    os.remove(tmp)
    tex_node.image = src
    print("FACES_CHECK", CHECK, names)
