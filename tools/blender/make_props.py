# Предметы квартиры: процедурные мультяшные модели (скруглённые края, тёплая палитра стиль-гайда).
# blender -b -P tools/blender/make_props.py -- <папка_для_glb> [сохранить.blend] [только,эти,имена]
#
# Каждый предмет — отдельный объект и отдельный GLB. Размеры в метрах. Перед — к зрителю (-Y в Blender,
# +Z в Godot). Напольные предметы: начало координат — центр низа. Настенные (окно, бра, часы, зеркало,
# батарея): начало — у стены (y=0), низ предмета; люстра — точка крепления к потолку.
# Длинные предметы (ванна, диван, кровать) стоят длинной стороной вдоль X — как их видно в разрезе.
import bpy, sys, os, math, random
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
OUT = a[0]
BLEND = a[1] if len(a) > 1 and a[1] else None
ONLY = set(a[2].split(",")) if len(a) > 2 and a[2] else None
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
rnd = random.Random(7)

# ---------------------------------------------------------------- материалы
_mats = {}
def M(name, rgb, rough=0.6, metal=0.0, alpha=1.0, emit=0.0):
    rgb = tuple(c ** 2.2 for c in rgb)       # цвета заданы как на экране (sRGB), Blender ждёт линейные
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*rgb, alpha)
    _mats[name] = m
    return m

WOOD = M("wood", (0.55, 0.32, 0.16), 0.7)
WOOD_D = M("wood_dark", (0.34, 0.19, 0.09), 0.7)
WOOD_L = M("wood_light", (0.70, 0.47, 0.25), 0.7)
CREAM = M("cream", (0.93, 0.87, 0.74), 0.6)
CREAM_D = M("cream_dark", (0.84, 0.77, 0.62), 0.6)
CERAMIC = M("ceramic", (0.95, 0.95, 0.92), 0.22)
CHROME = M("chrome", (0.85, 0.85, 0.87), 0.2, 1.0)
BRASS = M("brass", (0.88, 0.66, 0.26), 0.3, 1.0)
STEEL = M("steel", (0.78, 0.79, 0.80), 0.35, 0.5)
MUSTARD = M("mustard", (0.85, 0.60, 0.14), 0.75)
OLIVE = M("olive", (0.43, 0.46, 0.18), 0.85)
OLIVE_D = M("olive_dark", (0.32, 0.35, 0.13), 0.85)
BRICK = M("brick", (0.62, 0.21, 0.13), 0.8)
TEAL = M("teal", (0.14, 0.50, 0.48), 0.75)
TEAL_L = M("teal_light", (0.30, 0.64, 0.60), 0.75)
OCHRE = M("ochre", (0.80, 0.52, 0.20), 0.75)
DARK = M("dark", (0.07, 0.07, 0.08), 0.45)
GRAPHITE = M("graphite", (0.18, 0.18, 0.20), 0.5)
SCREEN = M("screen", (0.03, 0.04, 0.06), 0.15)
GLASS = M("glass", (0.70, 0.86, 0.92), 0.05, 0.0, 0.35)
MIRROR = M("mirror", (0.85, 0.90, 0.92), 0.03, 1.0)
LEAF = M("leaf", (0.20, 0.45, 0.14), 0.6)
LEAF_L = M("leaf_light", (0.33, 0.58, 0.18), 0.6)
CLAY = M("terracotta", (0.66, 0.32, 0.17), 0.8)
SOIL = M("soil", (0.20, 0.12, 0.07), 0.95)
RED = M("red", (0.78, 0.14, 0.10), 0.5)
BLUE = M("blue", (0.18, 0.35, 0.72), 0.5)
PURPLE = M("purple", (0.46, 0.26, 0.62), 0.5)
COFFEE = M("coffee", (0.20, 0.09, 0.04), 0.2)
WATER = M("water", (0.25, 0.62, 0.70), 0.1, 0.0, 0.7)
LAMP = M("lamp_shade", (1.0, 0.93, 0.75), 0.5, 0.0, 1.0, 1.5)
LED_G = M("led_green", (0.2, 1.0, 0.5), 0.3, 0, 1, 4)
LED_T = M("led_teal", (0.2, 0.9, 1.0), 0.3, 0, 1, 4)
MOP = M("mop_strands", (0.90, 0.88, 0.80), 0.9)

# ---------------------------------------------------------------- примитивы
PARTS = []
def _add(o, m, bev):
    o.data.materials.append(m)
    if bev:
        b = o.modifiers.new("bev", "BEVEL")
        b.width = bev
        b.segments = 3
        b.limit_method = "ANGLE"
    PARTS.append(o)
    return o

def box(sx, sy, sz, x=0, y=0, z=0, m=CREAM, bev=0.008, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z), rotation=rot)
    o = bpy.context.active_object
    o.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    return _add(o, m, min(bev, 0.45 * min(sx, sy, sz)) if bev else 0)

def cyl(r, h, x=0, y=0, z=0, m=CREAM, rot=(0, 0, 0), r2=None, v=32, bev=0.004, sc=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, vertices=v, location=(x, y, z), rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, vertices=v, location=(x, y, z), rotation=rot)
    o = bpy.context.active_object
    if sc:
        o.scale = sc
        bpy.ops.object.transform_apply(scale=True)
    return _add(o, m, min(bev, 0.3 * min(r, h)) if bev else 0)

def sph(r, x=0, y=0, z=0, m=CREAM, sc=(1, 1, 1), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=24, ring_count=12, location=(x, y, z), rotation=rot)
    o = bpy.context.active_object
    o.scale = sc
    bpy.ops.object.transform_apply(scale=True)
    return _add(o, m, 0)

def tor(R, r, x=0, y=0, z=0, m=CHROME, rot=(0, 0, 0), sc=None, arc=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=32, minor_segments=10,
                                     location=(x, y, z), rotation=rot)
    o = bpy.context.active_object
    if arc is not None:            # оставить дугу: срезать вершины ниже плоскости
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.object.mode_set(mode="OBJECT")
        import bmesh
        bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < arc], context="VERTS")
        bm.to_mesh(o.data); bm.free()
    if sc:
        o.scale = sc
        bpy.ops.object.transform_apply(scale=True)
    return _add(o, m, 0)

def cut(target, cutter):
    """Вырезать cutter из target (например, полость ванны)."""
    PARTS.remove(cutter)
    md = target.modifiers.new("cut", "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.object = cutter
    md.solver = "EXACT"
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(cutter, do_unlink=True)

def rad(d):
    return math.radians(d)

# ---------------------------------------------------------------- сборка и экспорт
PROPS = {}
def prop(name):
    def deco(fn):
        PROPS[name] = fn
        return fn
    return deco

def finish(name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in PARTS:
        o.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.convert(target="MESH")          # применить скругления
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=rad(40))
    except Exception:
        bpy.ops.object.shade_smooth()
    PARTS.clear()
    return o

# ================================================================ мебель (типы со скринов)
@prop("door")
def p_door():
    W, H, T = 0.9, 2.05, 0.045
    box(W, T, H, z=H / 2, m=CREAM, bev=0.006)
    for x in (-0.2, 0.2):                      # филёнки: две высокие сверху, две пониже снизу
        box(0.30, 0.014, 0.70, x=x, y=-T / 2 - 0.005, z=1.47, m=CREAM_D, bev=0.012)
        box(0.30, 0.014, 0.62, x=x, y=-T / 2 - 0.005, z=0.52, m=CREAM_D, bev=0.012)
    for sx in (-1, 1):                         # наличник
        box(0.08, 0.06, H + 0.08, x=sx * (W / 2 + 0.04), z=(H + 0.08) / 2, m=CREAM, bev=0.01)
    box(W + 0.24, 0.06, 0.09, z=H + 0.08, m=CREAM, bev=0.01)
    cyl(0.03, 0.02, x=0.36, y=-T / 2 - 0.01, z=1.0, m=BRASS, rot=(rad(90), 0, 0))
    sph(0.035, x=0.36, y=-T / 2 - 0.05, z=1.0, m=BRASS)
    cyl(0.008, 0.04, x=0.36, y=-T / 2 - 0.03, z=1.0, m=BRASS, rot=(rad(90), 0, 0))

@prop("window")
def p_window():
    W, H = 1.1, 1.3
    box(1.3, 0.2, 0.05, y=-0.06, z=-0.025, m=CREAM, bev=0.01)              # подоконник
    for sx in (-1, 1):
        box(0.07, 0.09, H, x=sx * (W / 2 - 0.035), y=-0.02, z=H / 2, m=CREAM)
    box(W, 0.09, 0.07, y=-0.02, z=H - 0.035, m=CREAM)
    box(W, 0.09, 0.07, y=-0.02, z=0.035, m=CREAM)
    box(0.05, 0.08, H - 0.1, y=-0.02, z=H / 2, m=CREAM)                     # переплёт
    box(W - 0.1, 0.08, 0.05, y=-0.02, z=H * 0.62, m=CREAM)
    box(W - 0.08, 0.01, H - 0.08, y=0.0, z=H / 2, m=GLASS, bev=0)
    cyl(0.018, 1.75, y=-0.14, z=H + 0.2, m=WOOD_D, rot=(0, rad(90), 0))      # карниз
    for sx in (-1, 1):
        sph(0.035, x=sx * 0.9, y=-0.14, z=H + 0.2, m=WOOD_D)
        for i in range(6):                                                  # шторы складками
            x = sx * (W / 2 + 0.02 - i * 0.055)
            cyl(0.04, H + 0.42, x=x, y=-0.14 - 0.012 * (i % 2), z=(H + 0.42) / 2 - 0.22,
                m=MUSTARD if i % 2 else OCHRE, v=12, bev=0)
        tor(0.09, 0.012, x=sx * 0.47, y=-0.15, z=H * 0.45, m=BRICK, rot=(rad(90), 0, 0), sc=(1.6, 1, 1))

@prop("armchair")
def p_armchair():
    box(0.86, 0.80, 0.28, z=0.26, m=OLIVE, bev=0.06)
    box(0.62, 0.64, 0.15, y=-0.04, z=0.47, m=OLIVE, bev=0.06)               # подушка сиденья
    box(0.86, 0.24, 0.66, y=0.30, z=0.70, m=OLIVE, bev=0.09, rot=(rad(-8), 0, 0))
    for sx in (-1, 1):
        box(0.17, 0.80, 0.30, x=sx * 0.36, z=0.52, m=OLIVE_D, bev=0.06)
        cyl(0.10, 0.80, x=sx * 0.36, z=0.66, m=OLIVE_D, rot=(rad(90), 0, 0), bev=0.03)
        for sy in (-1, 1):
            cyl(0.03, 0.12, x=sx * 0.36, y=sy * 0.33, z=0.06, m=WOOD_D, r2=0.022)

@prop("wardrobe")
def p_wardrobe():
    box(1.05, 0.58, 1.86, z=1.03, m=WOOD, bev=0.01)
    box(1.10, 0.62, 0.10, z=0.05, m=WOOD_D, bev=0.015)
    box(1.16, 0.66, 0.10, z=2.0, m=WOOD_D, bev=0.02)
    box(0.9, 0.5, 0.12, z=2.1, m=WOOD_D, bev=0.04)
    for sx in (-1, 1):
        x = sx * 0.262
        box(0.50, 0.025, 1.74, x=x, y=-0.3, z=1.03, m=WOOD_L, bev=0.008)
        box(0.36, 0.012, 0.78, x=x, y=-0.315, z=1.43, m=WOOD, bev=0.01)
        box(0.36, 0.012, 0.66, x=x, y=-0.315, z=0.56, m=WOOD, bev=0.01)
        sph(0.025, x=sx * 0.04, y=-0.33, z=1.05, m=BRASS)

@prop("toilet")
def p_toilet():
    cyl(0.14, 0.32, y=0.0, z=0.16, m=CERAMIC, r2=0.11, sc=(1, 1.25, 1), bev=0.02)
    cyl(0.20, 0.15, y=-0.06, z=0.36, m=CERAMIC, r2=0.22, sc=(1, 1.28, 1), bev=0.03)
    tor(0.17, 0.035, y=-0.06, z=0.445, m=CERAMIC, sc=(1, 1.28, 0.8))         # сиденье
    cyl(0.205, 0.025, y=-0.06, z=0.475, m=CERAMIC, sc=(1, 1.28, 1), bev=0.01)  # крышка
    box(0.42, 0.20, 0.38, y=0.22, z=0.64, m=CERAMIC, bev=0.035)              # бачок
    box(0.45, 0.23, 0.045, y=0.22, z=0.85, m=CERAMIC, bev=0.02)
    cyl(0.03, 0.02, y=0.22, z=0.88, m=CHROME)

@prop("bathtub")
def p_bathtub():
    outer = box(1.70, 0.76, 0.56, z=0.28, m=CERAMIC, bev=0.06)
    inner = box(1.54, 0.60, 0.56, z=0.39, m=CERAMIC, bev=0.12)
    cut(outer, inner)
    box(1.64, 0.02, 0.44, y=-0.385, z=0.24, m=CERAMIC, bev=0.01)            # фронтальная панель
    cyl(0.025, 0.2, x=0.76, y=0.30, z=0.66, m=CHROME)                        # смеситель
    cyl(0.02, 0.16, x=0.70, y=0.30, z=0.75, m=CHROME, rot=(0, rad(90), 0))
    for dx in (0.08, -0.08):
        sph(0.03, x=0.76 + dx * 0.0, y=0.30 + dx, z=0.62, m=CHROME)

@prop("shower_curtain")
def p_shower_curtain():
    L = 1.7
    cyl(0.015, L, z=2.0, m=CHROME, rot=(0, rad(90), 0))
    n = 18
    for i in range(n):
        x = -L / 2 + 0.05 + i * (L - 0.1) / (n - 1)
        cyl(0.045, 1.5, x=x, y=0.018 * (i % 2), z=1.22, m=TEAL if i % 2 else TEAL_L, v=12, bev=0)
        tor(0.02, 0.005, x=x, z=1.99, m=CHROME, rot=(0, rad(90), 0))

@prop("sink")
def p_sink():
    cyl(0.09, 0.72, y=0.05, z=0.36, m=CERAMIC, r2=0.12, bev=0.02)
    basin = box(0.56, 0.44, 0.17, y=-0.02, z=0.80, m=CERAMIC, bev=0.05)
    inner = box(0.44, 0.32, 0.17, y=-0.04, z=0.88, m=CERAMIC, bev=0.07)
    cut(basin, inner)
    cyl(0.02, 0.14, y=0.15, z=0.95, m=CHROME)
    cyl(0.015, 0.1, y=0.10, z=1.01, m=CHROME, rot=(rad(90), 0, 0))
    sph(0.025, x=0.07, y=0.15, z=0.93, m=CHROME)

@prop("mirror_cabinet")
def p_mirror():
    box(0.52, 0.13, 0.62, y=-0.065, z=0.31, m=CREAM, bev=0.015)
    box(0.44, 0.01, 0.54, y=-0.135, z=0.31, m=MIRROR, bev=0)
    box(0.56, 0.16, 0.04, y=-0.08, z=0.64, m=CREAM_D, bev=0.01)
    cyl(0.03, 0.06, y=-0.11, z=0.70, m=LAMP)                                  # лампочка сверху

@prop("dresser")
def p_dresser():
    box(0.84, 0.45, 0.80, z=0.46, m=WOOD, bev=0.012)
    box(0.90, 0.49, 0.04, z=0.88, m=WOOD_D, bev=0.012)
    for i, z in enumerate((0.22, 0.47, 0.72)):
        box(0.76, 0.025, 0.21, y=-0.235, z=z, m=WOOD_L, bev=0.01)
        for sx in (-1, 1):
            sph(0.02, x=sx * 0.2, y=-0.258, z=z, m=BRASS)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl(0.03, 0.06, x=sx * 0.38, y=sy * 0.18, z=0.03, m=WOOD_D, r2=0.022)

@prop("console_table")
def p_console():
    box(0.80, 0.38, 0.04, z=0.78, m=WOOD, bev=0.012)
    box(0.72, 0.32, 0.08, z=0.72, m=WOOD_D, bev=0.008)
    box(0.30, 0.012, 0.05, y=-0.165, z=0.72, m=WOOD_L, bev=0.005)
    sph(0.012, y=-0.175, z=0.72, m=BRASS)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl(0.022, 0.70, x=sx * 0.34, y=sy * 0.14, z=0.35, m=WOOD_D, r2=0.014)

@prop("chandelier")
def p_chandelier():
    cyl(0.06, 0.03, z=-0.015, m=BRASS)
    cyl(0.008, 0.38, z=-0.2, m=BRASS)
    sph(0.05, z=-0.42, m=BRASS)
    for i in range(3):
        ang = rad(90 + 120 * i)
        x, y = math.cos(ang) * 0.24, math.sin(ang) * 0.24
        cyl(0.01, 0.27, x=x / 2, y=y / 2, z=-0.42, m=BRASS, rot=(0, rad(90), ang))
        cyl(0.012, 0.08, x=x, y=y, z=-0.38, m=BRASS)
        cyl(0.05, 0.12, x=x, y=y, z=-0.3, m=LAMP, r2=0.095, v=16)            # тюльпан
    sph(0.025, z=-0.5, m=BRASS)

@prop("radiator")
def p_radiator():
    for i in range(10):
        box(0.06, 0.08, 0.58, x=-0.34 + i * 0.075, y=-0.07, z=0.39, m=CREAM, bev=0.02)
    for z in (0.14, 0.64):
        cyl(0.02, 0.8, y=-0.07, z=z, m=CREAM, rot=(0, rad(90), 0))
    for sx in (-1, 1):
        cyl(0.015, 0.1, x=sx * 0.3, y=-0.04, z=0.05, m=STEEL)

@prop("plant")
def p_plant():
    cyl(0.12, 0.26, z=0.13, m=CLAY, r2=0.16, bev=0.01)
    tor(0.16, 0.022, z=0.26, m=CLAY)
    cyl(0.15, 0.02, z=0.245, m=SOIL, bev=0)
    for i in range(16):
        ang = rnd.uniform(0, 2 * math.pi)
        h = rnd.uniform(0.35, 0.75)
        r = rnd.uniform(0.04, 0.18)
        x, y = math.cos(ang) * r, math.sin(ang) * r
        cyl(0.006, h - 0.2, x=x * 0.5, y=y * 0.5, z=0.25 + (h - 0.2) / 2, m=LEAF, v=6, bev=0,
            rot=(math.sin(ang) * 0.3, -math.cos(ang) * 0.3, 0))
        sph(0.05, x=x, y=y, z=0.25 + h - 0.15, m=LEAF if i % 2 else LEAF_L, sc=(0.6, 1.5, 0.25),
            rot=(rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6), ang))

# ================================================================ предметы с листа Gemini
@prop("coffee_maker")
def p_coffee():
    box(0.22, 0.26, 0.04, z=0.02, m=CREAM_D, bev=0.01)
    box(0.22, 0.12, 0.36, y=0.07, z=0.22, m=CREAM, bev=0.02)
    box(0.22, 0.25, 0.09, y=0.005, z=0.42, m=CREAM, bev=0.025)
    cyl(0.065, 0.13, y=-0.05, z=0.11, m=GLASS, bev=0.01)
    cyl(0.06, 0.07, y=-0.05, z=0.08, m=COFFEE, bev=0.01)
    cyl(0.067, 0.02, y=-0.05, z=0.18, m=DARK)
    tor(0.04, 0.009, x=0.075, y=-0.05, z=0.11, m=DARK, rot=(rad(90), 0, 0), sc=(0.7, 1, 1))
    box(0.025, 0.012, 0.02, x=0.07, y=-0.13, z=0.025, m=RED, bev=0.003)

@prop("gamepad")
def p_gamepad():
    box(0.10, 0.05, 0.035, z=0.02, m=GRAPHITE, bev=0.015)
    for sx in (-1, 1):
        sph(0.032, x=sx * 0.055, y=0.012, z=0.017, m=GRAPHITE, sc=(1, 1.4, 0.65), rot=(0, 0, sx * 0.4))
        cyl(0.011, 0.015, x=sx * 0.028, y=-0.008, z=0.042, m=DARK)
    for dx, dy, m in ((0.05, -0.012, LED_G), (0.05, 0.008, RED), (0.04, -0.002, BLUE), (0.06, -0.002, MUSTARD)):
        sph(0.0055, x=dx, y=dy, z=0.039, m=m)
    box(0.02, 0.006, 0.004, x=-0.05, y=-0.003, z=0.039, m=DARK, bev=0.001)
    box(0.006, 0.02, 0.004, x=-0.05, y=-0.003, z=0.039, m=DARK, bev=0.001)

@prop("books")
def p_books():
    cols = (BRICK, OLIVE, TEAL, MUSTARD, BLUE, PURPLE)
    x = -0.18
    for i, (w, h) in enumerate(((0.04, 0.24), (0.035, 0.26), (0.045, 0.23))):     # стоят
        box(w, 0.17, h, x=x + w / 2, z=h / 2, m=cols[i], bev=0.004)
        box(w - 0.008, 0.172, h - 0.012, x=x + w / 2 + 0.002, z=h / 2, m=CREAM, bev=0.002)
        x += w + 0.004
    z = 0
    for i, (d, l) in enumerate(((0.045, 0.24), (0.04, 0.22), (0.05, 0.23))):      # лежат стопкой
        box(l, 0.17, d, x=0.1, z=z + d / 2, m=cols[3 + i], bev=0.004, rot=(0, 0, rad(4 * (i - 1))))
        box(l - 0.012, 0.165, d - 0.008, x=0.104, y=-0.004, z=z + d / 2, m=CREAM, bev=0.002,
            rot=(0, 0, rad(4 * (i - 1))))
        z += d

@prop("pc_tower")
def p_pc():
    box(0.20, 0.44, 0.44, z=0.22, m=GRAPHITE, bev=0.012)
    box(0.18, 0.01, 0.42, y=-0.222, z=0.22, m=DARK, bev=0.004)
    for i in range(6):
        box(0.12, 0.004, 0.008, y=-0.228, z=0.06 + i * 0.025, m=GRAPHITE, bev=0)
    cyl(0.008, 0.006, x=0.0, y=-0.228, z=0.38, m=LED_T, rot=(rad(90), 0, 0))
    box(0.1, 0.004, 0.012, y=-0.228, z=0.34, m=GRAPHITE, bev=0)

@prop("tv")
def p_tv():
    box(1.10, 0.05, 0.64, z=0.47, m=DARK, bev=0.01)
    box(1.05, 0.01, 0.59, y=-0.026, z=0.47, m=SCREEN, bev=0)
    box(0.08, 0.04, 0.14, y=0.01, z=0.11, m=GRAPHITE, bev=0.008)
    box(0.42, 0.22, 0.025, z=0.0125, m=GRAPHITE, bev=0.01)

@prop("stick_vacuum")
def p_stick_vac():
    box(0.26, 0.10, 0.05, y=-0.02, z=0.025, m=GRAPHITE, bev=0.02)           # щётка
    cyl(0.022, 0.24, y=-0.06, z=0.025, m=PURPLE, rot=(0, rad(90), 0))
    cyl(0.015, 0.75, z=0.42, m=BRASS, rot=(rad(-6), 0, 0))                     # труба
    cyl(0.045, 0.2, y=0.04, z=0.88, m=GLASS, rot=(rad(-6), 0, 0))              # колба
    cyl(0.05, 0.14, y=0.06, z=1.02, m=PURPLE, rot=(rad(-6), 0, 0))
    cyl(0.02, 0.16, y=0.10, z=1.12, m=GRAPHITE, rot=(rad(40), 0, 0))           # ручка
    box(0.04, 0.03, 0.05, y=0.13, z=1.05, m=GRAPHITE, bev=0.01)

@prop("robot_vacuum")
def p_robot():
    cyl(0.17, 0.07, z=0.04, m=GRAPHITE, bev=0.02)
    cyl(0.15, 0.012, z=0.08, m=STEEL, bev=0.004)
    cyl(0.03, 0.02, y=0.05, z=0.09, m=DARK)
    sph(0.008, y=-0.06, z=0.088, m=LED_G)
    tor(0.17, 0.012, z=0.035, m=DARK)                                          # бампер

@prop("fridge")
def p_fridge():
    box(0.68, 0.64, 1.78, z=0.89, m=STEEL, bev=0.03)
    box(0.66, 0.03, 0.56, y=-0.33, z=1.48, m=STEEL, bev=0.015)
    box(0.66, 0.03, 1.12, y=-0.33, z=0.62, m=STEEL, bev=0.015)
    for z, h in ((1.38, 0.3), (0.95, 0.5)):
        cyl(0.012, h, x=-0.27, y=-0.37, z=z, m=CHROME)
    for (x, z, w, hh, m) in ((0.08, 1.55, 0.12, 0.12, OCHRE), (0.15, 1.36, 0.1, 0.14, TEAL_L),
                             (-0.05, 0.95, 0.14, 0.12, BRICK), (0.12, 0.8, 0.1, 0.1, PURPLE)):
        box(w, 0.006, hh, x=x, y=-0.348, z=z, m=m, bev=0.002, rot=(0, rad(rnd.uniform(-6, 6)), 0))

@prop("spice_rack")
def p_spices():
    for sx in (-1, 1):
        box(0.02, 0.10, 0.42, x=sx * 0.21, z=0.21, m=WOOD, bev=0.004)
    box(0.42, 0.012, 0.42, y=0.045, z=0.21, m=WOOD_D, bev=0.002)
    cols = (BRICK, OCHRE, OLIVE, MUSTARD, RED, CREAM_D)
    for j, z in enumerate((0.0, 0.14, 0.28)):
        box(0.42, 0.10, 0.018, z=z + 0.009, m=WOOD, bev=0.003)
        box(0.42, 0.01, 0.025, y=-0.048, z=z + 0.04, m=WOOD, bev=0.002)          # бортик
        for i in range(6):
            x = -0.17 + i * 0.068
            cyl(0.025, 0.09, x=x, z=z + 0.063, m=GLASS, v=14, bev=0)
            cyl(0.022, 0.06, x=x, z=z + 0.05, m=cols[(i + j) % 6], v=14, bev=0)
            cyl(0.026, 0.02, x=x, z=z + 0.115, m=DARK, v=14, bev=0.003)

@prop("microwave")
def p_microwave():
    box(0.52, 0.38, 0.30, z=0.15, m=STEEL, bev=0.02)
    box(0.34, 0.01, 0.22, x=-0.06, y=-0.192, z=0.15, m=SCREEN, bev=0.005)
    box(0.012, 0.03, 0.2, x=0.125, y=-0.205, z=0.15, m=CHROME, bev=0.004)
    box(0.09, 0.006, 0.04, x=0.19, y=-0.193, z=0.24, m=LED_G, bev=0.002)
    for i in range(3):
        for j in range(2):
            cyl(0.008, 0.006, x=0.17 + j * 0.035, y=-0.193, z=0.18 - i * 0.03, m=GRAPHITE, rot=(rad(90), 0, 0))
    cyl(0.018, 0.012, x=0.19, y=-0.195, z=0.06, m=GRAPHITE, rot=(rad(90), 0, 0))

@prop("rug")
def p_rug():
    box(1.6, 1.0, 0.012, z=0.006, m=BRICK, bev=0.004)
    for sy in (-1, 1):
        box(1.5, 0.03, 0.004, y=sy * 0.43, z=0.013, m=MUSTARD, bev=0)
    for sx in (-1, 1):
        box(0.03, 0.9, 0.004, x=sx * 0.73, z=0.013, m=MUSTARD, bev=0)
        box(0.3, 0.3, 0.004, x=sx * 0.3, z=0.014, m=OCHRE, bev=0, rot=(0, 0, rad(45)))
        box(0.15, 0.15, 0.005, x=sx * 0.3, z=0.015, m=CREAM, bev=0, rot=(0, 0, rad(45)))
        for i in range(14):                                                    # бахрома
            box(0.008, 0.05, 0.004, x=sx * 0.82, y=-0.45 + i * 0.07, z=0.004, m=CREAM, bev=0,
                rot=(0, 0, rad(90)))

@prop("toolbox")
def p_toolbox():
    b = box(0.46, 0.22, 0.18, z=0.09, m=BRICK, bev=0.012)
    inner = box(0.43, 0.19, 0.18, z=0.15, m=BRICK, bev=0.005)
    cut(b, inner)
    box(0.462, 0.222, 0.035, z=0.06, m=MUSTARD, bev=0.004)                    # полоса
    box(0.2, 0.02, 0.06, x=-0.22, y=-0.06, z=0.21, m=BRICK, bev=0.006, rot=(rad(-30), 0, 0))  # открытая крышка
    cyl(0.014, 0.28, x=-0.08, y=0.02, z=0.24, m=WOOD_L, rot=(rad(-20), rad(40), 0))         # молоток
    box(0.1, 0.035, 0.035, x=0.0, y=0.06, z=0.32, m=STEEL, bev=0.006, rot=(rad(-20), rad(40), 0))
    box(0.025, 0.012, 0.24, x=0.1, y=-0.03, z=0.22, m=STEEL, bev=0.004, rot=(0, rad(-25), 0))  # ключ
    tor(0.026, 0.008, x=0.155, y=-0.03, z=0.33, m=STEEL, rot=(rad(90), 0, 0), arc=-0.01)
    cyl(0.016, 0.1, x=0.16, y=0.05, z=0.2, m=RED, rot=(0, rad(-15), 0))       # отвёртка
    cyl(0.004, 0.14, x=0.18, y=0.05, z=0.31, m=STEEL, rot=(0, rad(-15), 0))

@prop("washing_machine")
def p_washer():
    box(0.60, 0.58, 0.85, z=0.425, m=CERAMIC, bev=0.025)
    box(0.58, 0.01, 0.12, y=-0.29, z=0.77, m=CREAM, bev=0.005)
    box(0.16, 0.012, 0.06, x=-0.18, y=-0.296, z=0.77, m=CREAM_D, bev=0.005)
    cyl(0.03, 0.02, x=0.18, y=-0.3, z=0.77, m=STEEL, rot=(rad(90), 0, 0))
    box(0.1, 0.006, 0.035, x=0.04, y=-0.297, z=0.77, m=LED_T, bev=0.002)
    tor(0.16, 0.025, y=-0.3, z=0.40, m=STEEL, rot=(rad(90), 0, 0))
    cyl(0.145, 0.02, y=-0.295, z=0.40, m=SCREEN, rot=(rad(90), 0, 0))

@prop("wall_lamp")
def p_sconce():
    box(0.07, 0.02, 0.12, y=-0.01, z=0.06, m=STEEL, bev=0.006)
    box(0.02, 0.1, 0.02, y=-0.06, z=0.05, m=STEEL, bev=0.005)
    cyl(0.07, 0.12, y=-0.13, z=0.1, m=LAMP, bev=0.008)

@prop("clock")
def p_clock():
    cyl(0.16, 0.04, y=-0.02, z=0.16, m=CREAM, rot=(rad(90), 0, 0))
    tor(0.16, 0.018, y=-0.03, z=0.16, m=GRAPHITE, rot=(rad(90), 0, 0))
    for i in range(12):
        ang = rad(i * 30)
        box(0.006, 0.006, 0.025 if i % 3 else 0.04, x=math.sin(ang) * 0.125, y=-0.042,
            z=0.16 + math.cos(ang) * 0.125, m=DARK, bev=0, rot=(0, -ang, 0))
    box(0.008, 0.006, 0.08, x=0.025, y=-0.046, z=0.19, m=DARK, bev=0, rot=(0, rad(-40), 0))
    box(0.006, 0.006, 0.11, x=-0.035, y=-0.048, z=0.17, m=DARK, bev=0, rot=(0, rad(60), 0))
    cyl(0.01, 0.01, y=-0.05, z=0.16, m=DARK, rot=(rad(90), 0, 0))

@prop("mop_bucket")
def p_mop():
    b = cyl(0.13, 0.26, z=0.13, m=STEEL, r2=0.16, bev=0.006)
    inner = cyl(0.12, 0.26, z=0.15, m=STEEL, r2=0.15, bev=0)
    cut(b, inner)
    cyl(0.135, 0.01, z=0.17, m=WATER, bev=0)
    tor(0.16, 0.006, z=0.26, m=GRAPHITE, rot=(rad(90), 0, 0), arc=0.0)         # дужка
    cyl(0.013, 1.25, x=-0.05, z=0.68, m=STEEL, rot=(0, rad(10), 0))            # черенок
    cyl(0.016, 0.12, x=-0.15, z=1.25, m=BLUE, rot=(0, rad(10), 0))
    cyl(0.03, 0.05, x=0.04, z=0.1, m=BLUE)
    for i in range(14):                                                        # тряпка из жгутиков
        ang = rad(i * 360 / 14)
        cyl(0.01, 0.13, x=0.04 + math.cos(ang) * 0.03, y=math.sin(ang) * 0.03, z=0.05, m=MOP, v=6, bev=0,
            rot=(math.sin(ang) * 0.3, -math.cos(ang) * 0.3, 0))

@prop("keys")
def p_keys():
    tor(0.016, 0.0025, z=0.003, m=STEEL)
    for i, ang in enumerate((rad(-20), rad(25))):
        dx, dy = math.cos(ang), math.sin(ang)
        cyl(0.012, 0.003, x=0.02 * dx, y=0.02 * dy, z=0.002, m=BRASS if i else STEEL, bev=0.001)
        box(0.045, 0.008, 0.003, x=0.05 * dx, y=0.05 * dy, z=0.002, m=BRASS if i else STEEL, bev=0.0008,
            rot=(0, 0, ang))
        for k in range(3):
            box(0.004, 0.005, 0.003, x=(0.04 + k * 0.01) * dx + 0.005 * dy, y=(0.04 + k * 0.01) * dy - 0.005 * dx,
                z=0.002, m=BRASS if i else STEEL, bev=0, rot=(0, 0, ang))
    box(0.025, 0.04, 0.003, x=-0.03, y=-0.012, z=0.002, m=CREAM, bev=0.003, rot=(0, 0, rad(30)))

@prop("router")
def p_router():
    box(0.26, 0.17, 0.04, z=0.02, m=DARK, bev=0.01)
    for i in range(4):
        x = -0.1 + i * 0.066
        cyl(0.007, 0.17, x=x, y=0.08, z=0.12, m=DARK, rot=(rad(-8), rad((i - 1.5) * 10), 0))
        sph(0.004, x=x, y=-0.086, z=0.022, m=LED_G)

# ================================================================ для пряток и пакостей
@prop("table")
def p_table():
    box(1.2, 0.75, 0.05, z=0.75, m=WOOD, bev=0.015)
    box(1.08, 0.63, 0.08, z=0.69, m=WOOD_D, bev=0.006)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(0.06, 0.06, 0.70, x=sx * 0.52, y=sy * 0.3, z=0.35, m=WOOD_D, bev=0.01)

@prop("sofa")
def p_sofa():
    box(1.9, 0.86, 0.26, z=0.24, m=TEAL, bev=0.05)
    for i in range(3):
        box(0.54, 0.66, 0.15, x=-0.56 + i * 0.56, y=-0.06, z=0.44, m=TEAL_L, bev=0.06)
    box(1.9, 0.24, 0.56, y=0.31, z=0.62, m=TEAL, bev=0.08, rot=(rad(-6), 0, 0))
    for sx in (-1, 1):
        box(0.18, 0.86, 0.34, x=sx * 0.86, z=0.47, m=TEAL, bev=0.07)
        for sy in (-1, 1):
            cyl(0.03, 0.1, x=sx * 0.85, y=sy * 0.36, z=0.05, m=WOOD_D, r2=0.022)

@prop("bed")
def p_bed():
    box(2.0, 1.5, 0.28, z=0.26, m=WOOD, bev=0.02)                              # вдоль X, изголовье +X
    box(1.92, 1.42, 0.2, z=0.5, m=CREAM, bev=0.06)
    box(1.35, 1.46, 0.07, x=-0.3, z=0.6, m=MUSTARD, bev=0.03)                  # одеяло
    for sy in (-1, 1):
        box(0.36, 0.55, 0.13, x=0.72, y=sy * 0.33, z=0.66, m=CREAM, bev=0.06)
    box(0.08, 1.56, 0.95, x=1.0, z=0.6, m=WOOD_D, bev=0.03)
    box(0.07, 1.56, 0.5, x=-1.0, z=0.4, m=WOOD_D, bev=0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(0.07, 0.07, 0.14, x=sx * 0.94, y=sy * 0.7, z=0.07, m=WOOD_D, bev=0.01)

@prop("stepladder")
def p_ladder():
    H = 1.3
    for sy, ang in ((-1, -14), (1, 14)):                                       # две опоры буквой А
        for sx in (-1, 1):
            box(0.04, 0.05, H, x=sx * 0.22, y=sy * 0.17, z=H / 2, m=STEEL, bev=0.006, rot=(rad(ang), 0, 0))
    for i in range(4):
        z = 0.28 + i * 0.28
        y = -0.17 * (1 - z / H) - 0.0
        box(0.44, 0.12, 0.03, y=y - 0.0, z=z, m=STEEL, bev=0.006)
    box(0.46, 0.22, 0.04, z=H + 0.01, m=ORANGE, bev=0.01)

ORANGE = M("orange", (0.92, 0.45, 0.12), 0.5)

@prop("skis")
def p_skis():
    for i, (x, m) in enumerate(((-0.07, RED), (0.07, MUSTARD))):
        box(0.08, 0.02, 1.6, x=x, y=0.0, z=0.8, m=m, bev=0.008, rot=(rad(-6), 0, 0))
        box(0.08, 0.02, 0.14, x=x, y=-0.06, z=1.64, m=m, bev=0.008, rot=(rad(-40), 0, 0))   # загнутый нос
        box(0.085, 0.04, 0.08, x=x, y=-0.07, z=0.65, m=DARK, bev=0.01, rot=(rad(-6), 0, 0))  # крепление
    for sx in (-1, 1):
        cyl(0.01, 1.25, x=sx * 0.2, y=0.02, z=0.63, m=STEEL, rot=(rad(-5), 0, 0))
        tor(0.035, 0.006, x=sx * 0.2, y=-0.02, z=0.1, m=DARK)
        cyl(0.016, 0.14, x=sx * 0.2, y=0.07, z=1.2, m=DARK)

# ---------------------------------------------------------------- запуск
done = []
for name, fn in PROPS.items():
    if ONLY and name not in ONLY:
        continue
    fn()
    o = finish(name)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True)
    o.hide_render = False
    done.append(name)
    print("PROP %-16s tris=%d" % (name, sum(len(p.vertices) - 2 for p in o.data.polygons)))
if BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
print("PROPS_OK %d" % len(done))
