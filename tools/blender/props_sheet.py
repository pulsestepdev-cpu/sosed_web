# Лист-превью предметов: каждый объект — в своей клетке, камера подогнана под его размер, подпись снизу.
# blender -b <props.blend> -P tools/blender/props_sheet.py -- <выход.png> [колонок=6] [размер_клетки=320]
import bpy, sys, os, math
import numpy as np
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
out = a[0]
COLS = int(a[1]) if len(a) > 1 else 6
CELL = int(a[2]) if len(a) > 2 else 320

sc = bpy.context.scene
objs = sorted([o for o in sc.objects if o.type == "MESH"], key=lambda o: o.name)
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = CELL
sc.view_settings.view_transform = "Standard"     # без «выцветания» AgX
w = bpy.data.worlds.new("W"); sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.93, 0.90, 0.84, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.8
bpy.ops.object.light_add(type="SUN", rotation=(0.9, 0.15, 0.7)); bpy.context.active_object.data.energy = 3.5
cd = bpy.data.cameras.new("C"); cd.type = "ORTHO"
cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
txt_mat = bpy.data.materials.new("txt"); txt_mat.use_nodes = True
txt_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.15, 0.08, 0.04, 1)

rows = math.ceil(len(objs) / COLS)
sheet = np.ones((rows * CELL, COLS * CELL, 4), dtype=np.float32) * np.array([0.86, 0.83, 0.77, 1.0], dtype=np.float32)
tmp = os.path.join(os.path.dirname(out), "_cell.png")
view = Vector((0.55, -1.0, 0.45)).normalized()          # три четверти спереди-сверху
for i, o in enumerate(objs):
    for p in objs:
        p.hide_render = p != o
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = Vector(map(min, *pts)); mx = Vector(map(max, *pts))
    c = (mn + mx) / 2
    size = max((mx - mn).length, 0.05)
    cd.ortho_scale = size * 1.25
    cam.location = c + view * size * 3
    cam.rotation_euler = (-view).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.text_add()
    t = bpy.context.active_object
    t.data.body = o.name
    t.data.align_x = "CENTER"
    t.data.size = size * 0.085
    t.rotation_euler = cam.rotation_euler
    t.location = c + view * size * 1.0 - cam.matrix_world.to_3x3() @ Vector((0, size * 0.52, 0))
    t.data.materials.append(txt_mat)
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(t, do_unlink=True)
    img = bpy.data.images.load(tmp, check_existing=False)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(CELL, CELL, 4)
    bpy.data.images.remove(img)
    r, col = divmod(i, COLS)
    y0 = (rows - 1 - r) * CELL
    sheet[y0:y0 + CELL, col * CELL:(col + 1) * CELL] = px
res = bpy.data.images.new("sheet", COLS * CELL, rows * CELL, alpha=True)
res.pixels = sheet.ravel()
res.filepath_raw = out; res.file_format = "PNG"; res.save()
os.remove(tmp)
print("PROPS_SHEET_OK %d" % len(objs))
