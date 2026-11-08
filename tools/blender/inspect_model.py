# Осмотр модели: статистика + рендер спереди, сбоку, 3/4 и крупно лицо.
# blender -b -P tools/blender/inspect_model.py -- <модель.glb> <папка_выхода> <префикс>
import bpy, sys, math, mathutils
args = sys.argv[sys.argv.index("--") + 1:]
src, out_dir, prefix = args[:3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
mn = mathutils.Vector((1e9,) * 3); mx = mathutils.Vector((-1e9,) * 3)
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ mathutils.Vector(c)
        mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
size = mx - mn
imgs = [(i.name, i.size[0], i.size[1]) for i in bpy.data.images]
arm = [o.name for o in bpy.context.scene.objects if o.type == "ARMATURE"]
print("INFO meshes=%d tris=%d size=%.2fx%.2fx%.2f textures=%s armature=%s anims=%d" % (
    len(meshes), tris, size.x, size.y, size.z, imgs, arm, len(bpy.data.actions)))
center = (mn + mx) / 2
h = max(size.x, size.y, size.z)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = 768
sc.render.film_transparent = False
world = bpy.data.worlds.new("W"); sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.5, 0.45, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.2
bpy.ops.object.light_add(type="SUN", rotation=(0.8, 0.2, 0.6)); bpy.context.active_object.data.energy = 3
cam_data = bpy.data.cameras.new("C"); cam_data.type = "ORTHO"
cam = bpy.data.objects.new("C", cam_data); sc.collection.objects.link(cam); sc.camera = cam
def shot(name, yaw, target, scale):
    cam_data.ortho_scale = scale
    d = mathutils.Vector((math.sin(yaw), -math.cos(yaw), 0)) * h * 3
    cam.location = target + d
    cam.rotation_euler = (d * -1).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = "%s/%s_%s.png" % (out_dir, prefix, name)
    bpy.ops.render.render(write_still=True)
shot("front", 0, center, h * 1.1)
shot("side", math.pi / 2, center, h * 1.1)
shot("q34", math.pi / 4, center, h * 1.1)
head = mathutils.Vector((center.x, center.y, mx.z - h * 0.15)) if size.z >= size.y else mathutils.Vector((center.x, mx.y - h * 0.15, center.z))
shot("face", 0, head, h * 0.35)
print("RENDER_OK")
