# Сборка персонажа Mixamo: модель со скелетом из файла With Skin + анимации из остальных FBX.
# Все анимации становятся отдельными клипами (NLA) и уходят в один GLB для Godot.
# blender -b -P tools/blender/merge_mixamo.py -- <папка_с_fbx> <файл_со_скином.fbx> <выход.glb> [рост_м=1.75]
import bpy, sys, os
d, skin_name, dst = sys.argv[sys.argv.index("--") + 1:][:3]
bpy.ops.wm.read_factory_settings(use_empty=True)

def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=False, ignore_leaf_bones=True)
    return [o for o in bpy.data.objects if o not in before]

new = import_fbx(os.path.join(d, skin_name))
arm = next(o for o in new if o.type == "ARMATURE")
arm.name = "Rig"
# Mixamo считает входную модель в сантиметрах и ставит скелету масштаб 0.01.
# Подгоняем общий масштаб так, чтобы персонаж был нужного роста (по умолчанию 1.75 м).
target_h = float(sys.argv[sys.argv.index("--") + 4]) if len(sys.argv) > sys.argv.index("--") + 4 else 1.75
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
zs = []
for o in new:
    if o.type == "MESH":
        e = o.evaluated_get(dg)
        zs += [(o.matrix_world @ v.co).z for v in e.data.vertices]
k = target_h / (max(zs) - min(zs))
arm.scale = arm.scale * k
print("SCALE_FIX x%.2f" % k)
clips = {}
def take_action(obj, clip):
    act = obj.animation_data.action if obj.animation_data else None
    if act:
        act.name = clip
        act.use_fake_user = True
        clips[clip] = act
take_action(arm, os.path.splitext(skin_name)[0].lower())

for f in sorted(os.listdir(d)):
    if not f.lower().endswith(".fbx") or f == skin_name:
        continue
    clip = os.path.splitext(f)[0].lower()
    objs = import_fbx(os.path.join(d, f))
    a2 = next((o for o in objs if o.type == "ARMATURE"), None)
    if a2:
        take_action(a2, clip)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)

# «На месте»: убираем у корневой кости (Hips) равномерный дрейф — если в Mixamo забыли In Place.
# Покачивание вверх-вниз и в стороны остаётся, уходит только сквозное смещение от начала к концу.
for name, act in clips.items():
    fcs = [fc for fc in act.fcurves if 'Hips' in fc.data_path and fc.data_path.endswith('location')] if hasattr(act, "fcurves") else []
    if not fcs:
        # Blender 5: каналы лежат в слоях/слотах действия
        for layer in getattr(act, "layers", []):
            for strip in layer.strips:
                for bag in strip.channelbags:
                    fcs += [fc for fc in bag.fcurves if 'Hips' in fc.data_path and fc.data_path.endswith('location')]
    for fc in fcs:
        if fc.array_index == 1:   # ось Y у Hips в Mixamo — вверх: приседания не трогаем
            continue
        kps = fc.keyframe_points
        if len(kps) < 2:
            continue
        t0, t1 = kps[0].co.x, kps[-1].co.x
        v0, v1 = kps[0].co.y, kps[-1].co.y
        drift = v1 - v0
        if abs(drift) < 1e-4:
            continue
        for kp in kps:
            d = drift * (kp.co.x - t0) / (t1 - t0)
            kp.co.y -= d
            kp.handle_left.y -= d
            kp.handle_right.y -= d
        print("INPLACE %s %s[%d] drift=%.2f" % (name, fc.data_path, fc.array_index, drift))

# матовый материал (Mixamo возвращает свой блестящий)
for mat in bpy.data.materials:
    if mat.node_tree:
        for n in mat.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                for inp in ("Roughness", "Metallic"):
                    for l in list(n.inputs[inp].links):
                        mat.node_tree.links.remove(l)
                n.inputs["Roughness"].default_value = 0.85
                n.inputs["Metallic"].default_value = 0.0
                if "Specular IOR Level" in n.inputs:
                    n.inputs["Specular IOR Level"].default_value = 0.25

# каждое действие — отдельная NLA-дорожка, тогда glTF экспортирует их как отдельные анимации
arm.animation_data_create()
arm.animation_data.action = None
for name, act in clips.items():
    tr = arm.animation_data.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, int(act.frame_range[0]), act)
    tr.mute = True
for o in bpy.data.objects:
    if o.type == "MESH":
        o.name = "Body"
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_animations=True,
    export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_range=False)
print("MERGE_OK clips=%s" % sorted(clips))
