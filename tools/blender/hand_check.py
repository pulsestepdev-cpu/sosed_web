# Крупные планы кисти: клип@доля_времени, камера следит за кистью; в руку временно кладётся предмет
# (бутылка для drink, телефон для phone) на кость хвата — так видно, правильно ли сомкнуты пальцы.
# blender -b <файл.blend> -P tools/blender/hand_check.py -- <выход.png> <клип@t,клип@t,...> [Right|Left] [размер=300] [ширина_кадра_м=0.32]
import bpy, sys, math, os
import numpy as np
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
out = a[0]
shots = [(s.split("@")[0], float(s.split("@")[1]) if "@" in s else 0.5) for s in a[1].split(",")]
side = a[2] if len(a) > 2 else "Right"
CELL = int(a[3]) if len(a) > 3 else 300
ZOOM = float(a[4]) if len(a) > 4 else 0.32
VIEWS = [("front", Vector((0, -1, 0.3))), ("side", Vector((-1 if side == "Right" else 1, -0.2, 0.2))),
         ("above", Vector((0.35, -0.6, 1)))]

sc = bpy.context.scene
rig = next(o for o in sc.objects if o.type == "ARMATURE")
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = CELL
w = bpy.data.worlds.new("W"); sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.55, 0.6, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 1.3
cd = bpy.data.cameras.new("C"); cd.type = "ORTHO"; cd.ortho_scale = ZOOM
cam = bpy.data.objects.new("C", cd); sc.collection.objects.link(cam); sc.camera = cam

def prop(kind):
    if kind == "bottle":       # бутылка Ø 7 см, 26 см, ось — вдоль кости хвата
        bpy.ops.mesh.primitive_cylinder_add(radius=0.035, depth=0.26, rotation=(math.pi / 2, 0, 0))
        col = (0.15, 0.45, 0.2, 1)
    else:                      # телефон 7.5 x 15 x 0.9 см
        bpy.ops.mesh.primitive_cube_add(size=1)
        bpy.context.active_object.scale = (0.075, 0.15, 0.009)
        col = (0.05, 0.05, 0.07, 1)
    o = bpy.context.active_object
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    m = bpy.data.materials.new(kind); m.diffuse_color = col
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = col
    o.data.materials.append(m)
    bone = side + ("HandGrip" if kind == "bottle" else "HandPhone")
    o.parent = rig; o.parent_type = "BONE"; o.parent_bone = bone
    o.location = (0, -rig.data.bones[bone].length, 0)    # центр предмета = голова кости
    return o

props = {"drink": "bottle", "phone": "phone"}
tmp = os.path.join(os.path.dirname(out), "_cell.png")
sheet = np.zeros((len(shots) * CELL, len(VIEWS) * CELL, 4), dtype=np.float32)
rig.animation_data.action = None
for row, (clip, t) in enumerate(shots):
    tr = rig.animation_data.nla_tracks[clip]
    for t2 in rig.animation_data.nla_tracks:
        t2.mute = t2 != tr
    st = tr.strips[0]
    sc.frame_set(int(round(st.frame_start + (st.frame_end - st.frame_start) * t)))
    pr = prop(props[clip]) if clip in props else None
    bpy.context.view_layer.update()
    pb = rig.pose.bones[side + "Hand"]
    target = rig.matrix_world @ ((pb.head + pb.tail) / 2 + (pb.tail - pb.head) * 0.6)
    for i, (vn, d) in enumerate(VIEWS):
        cam.location = target + d.normalized() * 2
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp, check_existing=False)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(CELL, CELL, 4)
        bpy.data.images.remove(img)
        y0 = (len(shots) - 1 - row) * CELL
        sheet[y0:y0 + CELL, i * CELL:(i + 1) * CELL] = px
    if pr:
        bpy.data.objects.remove(pr, do_unlink=True)
    print("HAND", clip, t)
res = bpy.data.images.new("sheet", len(VIEWS) * CELL, len(shots) * CELL, alpha=True)
res.pixels = sheet.ravel()
res.filepath_raw = out; res.file_format = "PNG"; res.save()
os.remove(tmp)
print("HAND_OK", out)
