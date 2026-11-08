# GLB → FBX с вшитыми текстурами (для загрузки в Mixamo).
# blender -b -P tools/blender/to_fbx.py -- <вход.glb> <выход.fbx>
import bpy, sys
src, dst = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
bpy.ops.export_scene.fbx(filepath=dst, path_mode="COPY", embed_textures=True, apply_unit_scale=True, use_selection=False)
print("FBX_OK", dst)
