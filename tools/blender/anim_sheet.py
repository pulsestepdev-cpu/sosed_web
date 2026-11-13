# Раскадровка анимаций: для каждого клипа (NLA-дорожки) N кадров в ряд, все клипы — одна картинка.
# blender -b <файл.blend> -P tools/blender/anim_sheet.py -- <выход.png> [кадров=6] [клипы,через,запятую] [вид=q34|front|side] [размер_кадра=220]
import bpy, sys, math, os
import numpy as np
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
# необязательные ключи (в любом месте): --ortho 3.5 (ширина кадра, м), --target x,y,z (центр кадра),
# --box x0,y0,z0,x1,y1,z1 (серый ящик — мебель у укрытия; можно несколько), --t0 0.2 --t1 0.9 (доля клипа)
opt = {"ortho": 2.3, "target": "0,0,0.8", "box": [], "t0": 0.0, "t1": 1.0}
pos = []
i = 0
while i < len(a):
    if a[i].startswith("--") and a[i][2:] in opt:
        k = a[i][2:]
        if k == "box":
            opt["box"].append([float(v) for v in a[i + 1].split(",")])
        else:
            opt[k] = a[i + 1] if k == "target" else float(a[i + 1])
        i += 2
    else:
        pos.append(a[i])
        i += 1
a = pos
out = a[0]
n = int(a[1]) if len(a) > 1 else 6
only = a[2].split(",") if len(a) > 2 and a[2] else None
view = a[3] if len(a) > 3 else "q34"
CELL = int(a[4]) if len(a) > 4 else 220

sc = bpy.context.scene
rig = next(o for o in sc.objects if o.type == "ARMATURE")
tracks = [t for t in rig.animation_data.nla_tracks if not only or t.name in only]

sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = CELL
sc.render.film_transparent = False
w = bpy.data.worlds.new("W"); sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.5, 0.45, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 1.2
bpy.ops.object.light_add(type="SUN", rotation=(0.8, 0.2, 0.6)); bpy.context.active_object.data.energy = 3
bpy.ops.mesh.primitive_plane_add(size=8)          # пол — видно, где стопы и где лежит
for b in opt["box"]:                               # мебель-заглушка (полупрозрачная серая)
    lo, hi = Vector(b[:3]), Vector(b[3:])
    bpy.ops.mesh.primitive_cube_add(location=(lo + hi) / 2)
    o = bpy.context.active_object
    o.scale = (hi - lo) / 2
    m = bpy.data.materials.new("box"); m.use_nodes = True
    bs = m.node_tree.nodes["Principled BSDF"]
    bs.inputs["Base Color"].default_value = (0.25, 0.3, 0.45, 1); bs.inputs["Alpha"].default_value = 0.55
    m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
    o.data.materials.append(m)
cd = bpy.data.cameras.new("C"); cd.type = "ORTHO"; cd.ortho_scale = opt["ortho"]
cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam
yaw = {"front": 0, "side": math.pi / 2, "q34": math.pi / 4, "back": math.pi}[view]
target = Vector([float(v) for v in opt["target"].split(",")])
d = Vector((math.sin(yaw) * 5, -math.cos(yaw) * 5, 1.2))
cam.location = target + d
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()

tmp = os.path.join(os.path.dirname(out), "_cell.png")
sheet = np.zeros((len(tracks) * CELL, n * CELL, 4), dtype=np.float32)
rig.animation_data.action = None
for row, tr in enumerate(tracks):
    for t2 in rig.animation_data.nla_tracks:
        t2.mute = t2 != tr
    st = tr.strips[0]
    f0, f1 = st.frame_start, st.frame_end
    f0, f1 = f0 + (f1 - f0) * opt["t0"], f0 + (f1 - f0) * opt["t1"]
    for i in range(n):
        sc.frame_set(int(round(f0 + (f1 - f0) * i / max(1, n - 1))))
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp, check_existing=False)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(CELL, CELL, 4)
        bpy.data.images.remove(img)
        y0 = (len(tracks) - 1 - row) * CELL
        sheet[y0:y0 + CELL, i * CELL:(i + 1) * CELL] = px
    print("SHEET", tr.name)
res = bpy.data.images.new("sheet", n * CELL, len(tracks) * CELL, alpha=True)
res.pixels = sheet.ravel()
res.filepath_raw = out
res.file_format = "PNG"
res.save()
os.remove(tmp)
print("SHEET_OK", out)
