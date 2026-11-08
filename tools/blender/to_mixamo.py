# Варианты файла для Mixamo:
#  1) <имя>_mixamo.zip  — OBJ + MTL + текстура (Mixamo принимает ZIP, самый надёжный вариант)
#  2) <имя>_mixamo_v2.fbx — FBX без вшитых текстур, сантиметры, лицом вперёд
# blender -b -P tools/blender/to_mixamo.py -- <вход.glb> <папка> <имя>
import bpy, sys, os, zipfile, shutil
src, out, name = sys.argv[sys.argv.index("--") + 1:][:3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
tmp = os.path.join(out, name + "_obj")
os.makedirs(tmp, exist_ok=True)
# текстура цвета — отдельным файлом рядом с OBJ
for img in bpy.data.images:
    if "basecolor" in img.name.lower() or "base" in img.name.lower():
        img.filepath_raw = os.path.join(tmp, "texture.png")
        img.file_format = "PNG"
        img.save()
for mat in bpy.data.materials:
    if mat.node_tree:
        for n in list(mat.node_tree.nodes):
            if n.type == "NORMAL_MAP":
                mat.node_tree.nodes.remove(n)
bpy.ops.wm.obj_export(filepath=os.path.join(tmp, name + ".obj"), export_materials=True,
    path_mode="RELATIVE", forward_axis="NEGATIVE_Z", up_axis="Y")
zpath = os.path.join(out, name + "_mixamo.zip")
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
    for f in os.listdir(tmp):
        z.write(os.path.join(tmp, f), f)
shutil.rmtree(tmp)
bpy.ops.export_scene.fbx(filepath=os.path.join(out, name + "_mixamo_v2.fbx"), path_mode="AUTO",
    embed_textures=False, global_scale=1.0, apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS",
    axis_forward="-Z", axis_up="Y", object_types={"MESH"}, mesh_smooth_type="FACE")
print("MIXAMO_OK", zpath)
