# Иконка предмета для сумки: рендер GLB на прозрачном фоне, камера сверху-спереди, мягкий контур.
# blender -b -P tools/blender/render_icon.py -- <модель.glb> <выход.png> [размер=512] [наклон_град=55] [поворот_град=0]
import bpy, sys, math
from mathutils import Vector, Euler

a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = a[0], a[1]
SIZE = int(a[2]) if len(a) > 2 else 512
TILT = math.radians(float(a[3]) if len(a) > 3 else 55)
YAW = math.radians(float(a[4]) if len(a) > 4 else 0)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
meshes = [o for o in sc.objects if o.type == "MESH"]
pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
center = (lo + hi) / 2
radius = (hi - lo).length / 2

sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = SIZE
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Standard"
sc.render.use_freestyle = True
sc.render.line_thickness_mode = "ABSOLUTE"
sc.render.line_thickness = max(1.5, SIZE / 170)
ls = sc.view_layers[0].freestyle_settings.linesets[0] if sc.view_layers[0].freestyle_settings.linesets else \
    sc.view_layers[0].freestyle_settings.linesets.new("L")
if ls.linestyle is None:
    ls.linestyle = bpy.data.linestyles.new("LS")
ls.linestyle.color = (0.16, 0.08, 0.03)
w = bpy.data.worlds.new("W"); sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (1, 0.96, 0.9, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
bpy.ops.object.light_add(type="SUN", rotation=(0.7, 0.2, 0.6)); bpy.context.active_object.data.energy = 3.2

cd = bpy.data.cameras.new("C"); cd.type = "ORTHO"; cd.ortho_scale = radius * 2.25
cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
d = Vector((math.sin(YAW) * math.cos(TILT), -math.cos(YAW) * math.cos(TILT), math.sin(TILT)))
cam.location = center + d * (radius * 4 + 1)
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("ICON", OUT)
