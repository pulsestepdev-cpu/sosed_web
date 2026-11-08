# Проверка управления Blender из скрипта: сцена → GLB для Godot → рендер PNG.
# Запуск: blender -b -P tools/blender/smoke_test.py -- <выход.glb> <выход.png>
import bpy, sys
out_glb, out_png = sys.argv[sys.argv.index("--") + 1:][:2]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.5))
cube = bpy.context.active_object
mat = bpy.data.materials.new("Warm")
mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.85, 0.45, 0.15, 1)
cube.data.materials.append(mat)
bpy.ops.mesh.primitive_plane_add(size=4)

bpy.ops.object.light_add(type="AREA", location=(2, -2, 3))
bpy.context.active_object.data.energy = 300
bpy.ops.object.camera_add(location=(3, -3, 2.2), rotation=(1.15, 0, 0.785))
bpy.context.scene.camera = bpy.context.active_object

bpy.ops.export_scene.gltf(filepath=out_glb, export_format="GLB")
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 640, 360
sc.render.filepath = out_png
bpy.ops.render.render(write_still=True)
print("SMOKE_OK", out_glb, out_png)
