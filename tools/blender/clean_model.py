# Чистка модели из Tripo: матовый материал без блеска, упрощение сетки, центр/масштаб, экспорт GLB.
# blender -b -P tools/blender/clean_model.py -- <вход.glb> <выход.glb> [треугольников=40000] [рост_м=1.75]
import bpy, sys, mathutils
a = sys.argv[sys.argv.index("--") + 1:]
src, dst = a[0], a[1]
target = int(a[2]) if len(a) > 2 else 40000
height = float(a[3]) if len(a) > 3 else 1.75
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in meshes:
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if tris > target:
        # Tripo режет вершины по швам развёртки — сшиваем их, иначе упрощение рвёт текстуру
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=0.0001)
        bpy.ops.object.mode_set(mode="OBJECT")
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = target / tris
        m.delimit = {"UV", "SEAM"}
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="dec")
    for mat in o.data.materials:
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        # убираем карту шероховатости/металла из Tripo — она и даёт «мокрый пластик»
        for inp in ("Roughness", "Metallic"):
            for l in list(bsdf.inputs[inp].links):
                nt.links.remove(l)
        bsdf.inputs["Roughness"].default_value = 0.85
        bsdf.inputs["Metallic"].default_value = 0.0
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.25
# ставим на пол, по центру, нужного роста
mn = mathutils.Vector((1e9,) * 3); mx = mathutils.Vector((-1e9,) * 3)
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ mathutils.Vector(c)
        mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
k = height / (mx.z - mn.z)
for o in meshes:
    o.location = (o.location - mathutils.Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))) * k
    o.scale = o.scale * k
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB")
print("CLEAN_OK tris=%d" % tris)
