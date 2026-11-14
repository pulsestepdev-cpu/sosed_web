"""Капот машины соседа: отдельная панель hood с шарниром у лобового стекла, клип open, моторный отсек под ней.

  blender.exe -b -P tools/blender/car_hood.py -- <вход.glb> <выход.glb> [--open 62] [--frames 18]

Вход — модель после import_car.py (одна сетка, нос к +X, пол z = 0, центр по X/Y, длина 4.2 м). Если её уже
перезаписали версией с капотом — взять из git: `git show 548dafb:assets/models/props/car_w124.glb > base.glb`.

Что делает:
  1. Режет верхнюю обшивку по контуру капота (плоскости x = X_REAR / X_FRONT, y = ±Y_SIDE — сняты по срезам
     модели: лобовое стекло кончается у x 0.78, крылья скругляются с |y| 0.76, фары и решётка — с x 1.88;
     звезда на решётке остаётся на месте) и отделяет капот в объект hood. Ось — задний край капота.
  2. Капоту — изнанка в 12 мм (тёмная шумоизоляция снизу и тёмный торец — как щель между панелями).
  3. Под капотом — моторный отсек вместо пустоты кузова: стенки точно по краю выреза, полка над колёсами
     (шины доходят до z 0.62), яма с мотором; в отсеке клапанная крышка, воздушный фильтр с патрубком,
     радиатор с вентилятором, аккумулятор, бачок омывателя, расширительный бачок, вакуумник, опоры стоек.
     Всё ниже закрытого капота. Отсек вклеивается в кузов (одна сетка), текстур нет — размер почти не растёт.
  4. Клип open: капот поднимается за --frames кадров (30 к/с) на --open градусов; закрывают его тем же клипом
     задом наперёд (сначала медленно, в конце быстрее — хлопок).
Текстуры кузова пишутся как были (те же JPEG, без пережатия).
"""
import math
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
opts = {"--open": 62.0, "--frames": 18.0}
for i, a in enumerate(argv):
    if a in opts:
        opts[a] = float(argv[i + 1])

X_REAR, X_FRONT, Y_SIDE = 0.82, 1.88, 0.74     # контур капота
Z_SHELF, Z_PIT = 0.635, 0.40                   # полка над колёсами (шины до 0.62) и дно ямы
PIT = (1.02, 1.72, 0.50)                       # яма: x от/до, |y| до
SKIN = 0.012                                   # толщина капота

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
if any(o.name.startswith("hood") for o in bpy.context.scene.objects):
    sys.exit("car_hood: в модели уже есть капот — нужен исходный car_w124.glb (см. шапку скрипта)")
car = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
bpy.context.view_layer.objects.active = car
probe = BVHTree.FromObject(car, bpy.context.evaluated_depsgraph_get())   # обшивка до разреза


def top_z(x, y):
    """Высота верхней обшивки в точке (луч сверху), None — дыра."""
    hit = probe.ray_cast(Vector((x, y, 3.0)), Vector((0, 0, -1)))
    return hit[0].z if hit[0] is not None and hit[0].z > 0.6 else None


def mat(name, rgb, rough=0.7, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.use_backface_culling = True
    return m


BAY = mat("bay", (0.035, 0.035, 0.038), 0.9)              # стенки отсека, изнанка капота
ENGINE = mat("engine", (0.11, 0.11, 0.12), 0.55, 0.3)     # блок, радиатор, вентилятор
ALU = mat("alu", (0.34, 0.35, 0.36), 0.45, 0.5)            # клапанная крышка, крышки
PLASTIC = mat("plastic", (0.015, 0.015, 0.016), 0.6)      # фильтр, аккумулятор, патрубки
WHITE = mat("tank", (0.80, 0.80, 0.74), 0.5)              # бачки
RED = mat("red", (0.75, 0.08, 0.05), 0.5)                 # клемма «+», крышка омывателя

# ---------------------------------------------------------------- 1. разрез по контуру капота
bpy.ops.object.mode_set(mode='EDIT')
bpy.context.tool_settings.mesh_select_mode = (False, False, True)
bm = bmesh.from_edit_mesh(car.data)
lo =Vector((X_REAR - 0.05, -Y_SIDE - 0.05))
hi = Vector((X_FRONT + 0.05, Y_SIDE + 0.05))


def near_region(f):
    vs = [v.co for v in f.verts]
    return (max(v.z for v in vs) > 0.62 and max(v.x for v in vs) > lo.x and min(v.x for v in vs) < hi.x
            and max(v.y for v in vs) > lo.y and min(v.y for v in vs) < hi.y)


for co, no in (((X_REAR, 0, 0), (1, 0, 0)), ((X_FRONT, 0, 0), (1, 0, 0)),
               ((0, Y_SIDE, 0), (0, 1, 0)), ((0, -Y_SIDE, 0), (0, 1, 0))):
    faces = [f for f in bm.faces if near_region(f)]
    edges = list({e for f in faces for e in f.edges})
    verts = list({v for f in faces for v in f.verts})
    bmesh.ops.bisect_plane(bm, geom=faces + edges + verts, dist=1e-5, plane_co=co, plane_no=no)
bm.faces.ensure_lookup_table()
bm.faces.index_update()
cut = BVHTree.FromBMesh(bm)
eps = 1e-4
for g in (bm.verts, bm.edges, bm.faces):
    for e in g:
        e.select = False
hood_faces = []
for f in bm.faces:
    c = f.calc_center_median()
    if not (X_REAR + eps < c.x < X_FRONT - eps and abs(c.y) < Y_SIDE - eps and c.z > 0.6):
        continue
    hit = cut.ray_cast(Vector((c.x, c.y, 3.0)), Vector((0, 0, -1)))
    first = hit[0] is not None and (hit[2] == f.index or abs(hit[0].z - c.z) < 0.01)
    if first or c.z > 0.75:            # верхняя обшивка (дворники — над ней, тоже капот)
        hood_faces.append(f)
for f in hood_faces:
    f.select_set(True)
bmesh.update_edit_mesh(car.data)
bpy.ops.mesh.separate(type='SELECTED')
bpy.ops.object.mode_set(mode='OBJECT')
hood = next(o for o in bpy.context.scene.objects if o.type == 'MESH' and o != car)
hood.name = hood.data.name = "hood"
print("HOOD faces", len(hood_faces))

# ---------------------------------------------------------------- 2. изнанка капота и шарнир
# Верхнюю обшивку не трогаем: её нормали — из исходной модели (пересчёт по упрощённой сетке и solidify дают блики
# и шипы на загибах). Изнанка — копия обшивки на SKIN ниже, лицом вниз; торец — полоски по внешнему краю: ребро
# только у одной грани (по положению — швы UV не в счёт) и на линии разреза (внутри после упрощения сетки полно
# трещин — им торец не нужен, он внутри капота).
hood.data.materials.append(BAY)
bm = bmesh.new()
bm.from_mesh(hood.data)
top = list(bm.faces)


def pkey(co):
    return round(co.x, 5), round(co.y, 5), round(co.z, 5)


def on_contour(co):
    return min(abs(co.x - X_REAR), abs(co.x - X_FRONT), abs(abs(co.y) - Y_SIDE)) < 0.004


uses = {}
for f in top:
    f.normal_update()
    for e in f.edges:
        k = frozenset((pkey(e.verts[0].co), pkey(e.verts[1].co)))
        uses[k] = uses.get(k, 0) + 1
low = {}


def lowv(v):
    if v not in low:
        low[v] = bm.verts.new(v.co - Vector((0, 0, SKIN)))
    return low[v]


rim = 0
for f in top:
    vs = [lowv(v) for v in f.verts]
    if f.normal.z > 0:
        vs.reverse()
    g = bm.faces.new(vs)
    g.material_index = 1
    g.smooth = True
    c = f.calc_center_median()
    for e in f.edges:
        v0, v1 = e.verts
        if uses[frozenset((pkey(v0.co), pkey(v1.co)))] != 1 or not (on_contour(v0.co) and on_contour(v1.co)):
            continue
        g = bm.faces.new([v0, v1, lowv(v1), lowv(v0)])
        g.material_index = 1
        g.smooth = True
        g.normal_update()
        out = (v0.co + v1.co) / 2 - c
        out.z = 0
        if g.normal.dot(out) < 0:
            g.normal_flip()
        rim += 1
bm.to_mesh(hood.data)
bm.free()
print("HOOD rim edges", rim)
hv = [v.co for v in hood.data.vertices]
hlo = Vector((min(v.x for v in hv), min(v.y for v in hv), min(v.z for v in hv)))
hhi = Vector((max(v.x for v in hv), max(v.y for v in hv), max(v.z for v in hv)))
print("HOOD bounds", tuple(round(c, 3) for c in hlo), tuple(round(c, 3) for c in hhi))
if hlo.x < X_REAR - 0.03 or hhi.x > X_FRONT + 0.03 or max(-hlo.y, hhi.y) > Y_SIDE + 0.03 or hlo.z < 0.58:
    sys.exit("car_hood: капот вылез за контур — шипы от толщины или лишние грани")
pivot = Vector((X_REAR, 0.0, top_z(X_REAR + 0.005, 0.0)))
bpy.context.scene.cursor.location = pivot
bpy.ops.object.select_all(action='DESELECT')
hood.select_set(True)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

# ---------------------------------------------------------------- 3. моторный отсек
bay = bpy.data.meshes.new("bay")
bm = bmesh.new()
mats = [BAY, ENGINE, ALU, PLASTIC, WHITE, RED]
inside = Vector(((X_REAR + X_FRONT) / 2, 0.0, 0.5))


def face(pts, m, toward=None):
    f = bm.faces.new([bm.verts.new(p) for p in pts])
    f.material_index = mats.index(m)
    f.normal_update()
    if toward is not None and f.normal.dot(toward - f.calc_center_median()) < 0:
        f.normal_flip()
    return f


def edge_z(x, y, dx, dy):
    """Высота края выреза: медиана по точкам чуть внутри (dx, dy — внутрь)."""
    zs = sorted(z for z in (top_z(x + dx * d, y + dy * d) for d in (0.003, 0.008, 0.015)) if z is not None)
    return (zs[len(zs) // 2] if zs else None)


# стенки — от края выреза вниз до полки; обход по периметру с шагом ~4 см
corners = [(X_REAR, -Y_SIDE), (X_FRONT, -Y_SIDE), (X_FRONT, Y_SIDE), (X_REAR, Y_SIDE)]
ring = []
for k in range(4):
    (x0, y0), (x1, y1) = corners[k], corners[(k + 1) % 4]
    n = max(2, int(math.hypot(x1 - x0, y1 - y0) / 0.04))
    dx, dy = -(y1 - y0), (x1 - x0)             # внутрь (обход против часовой)
    ln = math.hypot(dx, dy)
    dx, dy = dx / ln, dy / ln
    for i in range(n):
        x, y = x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n
        ring.append([x, y, edge_z(x + dx * 1e-4, y + dy * 1e-4, dx, dy)])
for i, p in enumerate(ring):                   # дыры в обшивке — по соседям
    if p[2] is None:
        p[2] = next(q[2] for q in ring[i:] + ring[:i] if q[2] is not None)
tops = [bm.verts.new((x, y, z - 0.004)) for x, y, z in ring]
bots = [bm.verts.new((x, y, Z_SHELF)) for x, y, z in ring]
flip = None
for i in range(len(ring)):
    j = (i + 1) % len(ring)
    f = bm.faces.new([tops[i], tops[j], bots[j], bots[i]])
    f.material_index = mats.index(BAY)
    f.smooth = True                            # тёмные стенки: общие вершины дешевле, углы всё равно не видно
    f.normal_update()
    if flip is None:
        flip = f.normal.dot(inside - f.calc_center_median()) < 0
    if flip:
        f.normal_flip()
# полка (рамка между вырезом и ямой), стенки ямы, дно
px0, px1, py = PIT
outer = [(X_REAR, -Y_SIDE), (X_FRONT, -Y_SIDE), (X_FRONT, Y_SIDE), (X_REAR, Y_SIDE)]
inner = [(px0, -py), (px1, -py), (px1, py), (px0, py)]
up = Vector((0, 0, 1))
for k in range(4):
    o0, o1, i0, i1 = outer[k], outer[(k + 1) % 4], inner[k], inner[(k + 1) % 4]
    f = face([(*o0, Z_SHELF), (*o1, Z_SHELF), (*i1, Z_SHELF), (*i0, Z_SHELF)], BAY)
    if f.normal.z < 0:
        f.normal_flip()
    face([(*i0, Z_SHELF), (*i1, Z_SHELF), (*i1, Z_PIT), (*i0, Z_PIT)], BAY, Vector(((px0 + px1) / 2, 0, 0.5)))
f = face([(*p, Z_PIT) for p in inner], BAY)
if f.normal.z < 0:
    f.normal_flip()


def box(x0, x1, y0, y1, z0, z1, m, bottom=False):
    vs = [bm.verts.new((x, y, z)) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
    quads = [(0, 1, 5, 4), (1, 3, 7, 5), (3, 2, 6, 7), (2, 0, 4, 6), (4, 5, 7, 6)] + ([(0, 2, 3, 1)] if bottom else [])
    c = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    for q in quads:
        f = bm.faces.new([vs[i] for i in q])
        f.material_index = mats.index(m)
        f.normal_update()
        if f.normal.dot(f.calc_center_median() - c) < 0:
            f.normal_flip()


def cyl(c, r, h, m, axis="z", seg=12, ends=(False, True)):
    """Цилиндр: c — центр, h — длина вдоль оси; ends — (низ, верх) с крышками."""
    c = Vector(c)
    ax = {"x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)), "z": Vector((0, 0, 1))}[axis] if isinstance(axis, str) \
        else Vector(axis).normalized()
    u = ax.orthogonal().normalized()
    v = ax.cross(u)
    rings = []
    for s in (-0.5, 0.5):
        rings.append([bm.verts.new(c + ax * h * s + (u * math.cos(t) + v * math.sin(t)) * r)
                      for t in (2 * math.pi * i / seg for i in range(seg))])
    for i in range(seg):
        j = (i + 1) % seg
        f = bm.faces.new([rings[0][i], rings[0][j], rings[1][j], rings[1][i]])
        f.material_index = mats.index(m)
        f.smooth = True                        # бок гладкий (и вершины общие), крышки плоские
        f.normal_update()
        if f.normal.dot(f.calc_center_median() - c) < 0:
            f.normal_flip()
    for k, on in enumerate(ends):
        if on:
            f = bm.faces.new(rings[k])
            f.material_index = mats.index(m)
            f.normal_update()
            if f.normal.dot(ax * (1 if k else -1)) < 0:
                f.normal_flip()


box(1.05, 1.61, -0.18, 0.18, Z_PIT, 0.68, ENGINE)                      # блок цилиндров
box(1.07, 1.59, -0.11, 0.11, 0.68, 0.755, ALU)                         # клапанная крышка
cyl((1.19, 0.05, 0.765), 0.028, 0.03, PLASTIC, seg=8)                         # маслозаливная крышка
box(1.10, 1.56, 0.12, 0.24, 0.60, 0.70, ENGINE)                        # впускной коллектор
for i in range(4):                                                     # свечные провода — колпачки
    cyl((1.15 + i * 0.12, -0.13, 0.69), 0.016, 0.06, PLASTIC, seg=6)
cyl((1.04, 0.30, 0.70), 0.13, 0.08, PLASTIC, seg=16)                           # корпус воздушного фильтра
cyl((1.04, 0.30, 0.745), 0.035, 0.012, ALU, seg=8)                            # гайка-барашек
cyl((1.40, 0.36, 0.69), 0.04, 0.46, PLASTIC, axis=(1, 0.15, -0.05), seg=10)   # патрубок к решётке
box(1.72, 1.80, -0.44, 0.44, 0.58, 0.70, ENGINE)                       # радиатор
cyl((1.76, -0.30, 0.71), 0.025, 0.025, ALU, seg=8)                            # пробка радиатора
cyl((1.665, 0.0, 0.56), 0.14, 0.03, ENGINE, axis="x", seg=16, ends=(True, True))   # вентилятор
cyl((1.665, 0.0, 0.56), 0.035, 0.08, ALU, axis="x", seg=10, ends=(True, True))      # ступица
cyl((1.64, -0.08, 0.64), 0.025, 0.2, PLASTIC, axis=(1, -0.6, 0.2), seg=8)          # шланг к радиатору
box(0.87, 1.11, -0.72, -0.54, Z_SHELF, 0.80, PLASTIC)                  # аккумулятор
cyl((0.92, -0.58, 0.81), 0.014, 0.025, RED, seg=8)                     # клеммы
cyl((1.06, -0.58, 0.81), 0.014, 0.025, PLASTIC, seg=8)
box(1.52, 1.70, 0.53, 0.70, Z_SHELF, 0.735, WHITE)                     # бачок омывателя
cyl((1.60, 0.63, 0.745), 0.022, 0.02, RED, seg=8)
cyl((1.24, -0.62, 0.71), 0.065, 0.10, WHITE)                           # расширительный бачок
cyl((1.24, -0.62, 0.765), 0.03, 0.012, PLASTIC, seg=8)
cyl((0.88, 0.48, 0.74), 0.09, 0.10, PLASTIC, axis="x", seg=16)        # вакуумник тормозов у перегородки
cyl((1.00, 0.48, 0.74), 0.03, 0.14, ALU, axis="x", seg=8)              # главный тормозной цилиндр
for sy in (-1, 1):                                                     # опоры стоек над колёсами
    cyl((1.36, sy * 0.63, 0.685), 0.075, 0.05, ENGINE, seg=12)
bm.to_mesh(bay)
bm.free()
bay_obj = bpy.data.objects.new("bay", bay)
bpy.context.scene.collection.objects.link(bay_obj)
for m in mats:
    bay.materials.append(m)
bpy.ops.object.select_all(action='DESELECT')
bay_obj.select_set(True)
car.select_set(True)
bpy.context.view_layer.objects.active = car
bpy.ops.object.join()                          # отсек — часть кузова

# ---------------------------------------------------------------- 4. клип open
hood.parent = car
hood.rotation_mode = 'XYZ'                     # импорт glTF ставит кватернионы — ключи эйлера не сработали бы
deg, fr = opts["--open"], int(opts["--frames"])
hood.animation_data_create()
act = bpy.data.actions.new("hood_open")
hood.animation_data.action = act
for f, k in ((1, 0.0), (max(2, fr // 3), 0.35), (max(3, fr * 2 // 3), 0.86), (fr, 1.0)):
    hood.rotation_euler[1] = -math.radians(deg) * k     # вокруг +Y минус — передний край вверх
    hood.keyframe_insert("rotation_euler", index=1, frame=f)
hood.animation_data.action = None
tr = hood.animation_data.nla_tracks.new()
tr.name = "open"
tr.strips.new(act.name, 1, act)
hood.rotation_euler[1] = 0.0

tris = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in (car, hood)}
print("TRIS", tris)
bpy.ops.object.select_all(action='DESELECT')
car.select_set(True)
hood.select_set(True)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=True, export_apply=True,
                          export_image_format='AUTO', export_animations=True, export_animation_mode='NLA_TRACKS',
                          export_force_sampling=True)
print("EXPORTED", dst)
