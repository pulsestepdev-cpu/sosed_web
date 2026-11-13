"""Готовая модель машины (GLB со стороны) → лёгкая модель для игры.

  blender.exe -b -P tools/blender/import_car.py -- <вход.glb> <выход.glb> [--length 4.0] [--tris 15000] [--metal 0.15]

Что делает: склеивает части в один объект, упрощает сетку до --tris треугольников (для веба), убирает карту
нормалей (на упрощённой сетке она даёт пятна, а с игровой камеры деталей всё равно не видно), задаёт металличность
константой (без отражений окружения металл в игре темнеет), масштабирует по длине (ось X — вдоль машины,
передом к +X), ставит на пол (z = 0) и по центру. Текстуры пишет в JPEG.
"""
import sys

import bpy
import mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
opts = {"--length": 4.0, "--tris": 15000, "--metal": 0.15}
for i, a in enumerate(argv):
    if a in opts:
        opts[a] = float(argv[i + 1])

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
car = bpy.context.view_layer.objects.active
car.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
car.name = car.data.name = "car_w124"

tris = sum(len(p.vertices) - 2 for p in car.data.polygons)
if tris > opts["--tris"]:
    m = car.modifiers.new("decimate", 'DECIMATE')
    m.ratio = opts["--tris"] / tris
    m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=m.name)
print("TRIS", tris, "->", sum(len(p.vertices) - 2 for p in car.data.polygons))

for mat in car.data.materials:
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    for l in list(nt.links):
        if l.to_node == bsdf and l.to_socket.name in ("Normal", "Metallic"):
            nt.links.remove(l)
    drop = []
    for n in nt.nodes:
        if n.type == 'NORMAL_MAP':
            drop.append(n.name)
            if n.inputs["Color"].links:
                drop.append(n.inputs["Color"].links[0].from_node.name)
    for name in drop:          # удалять после обхода: удалённый узел нельзя трогать
        nt.nodes.remove(nt.nodes[name])
    bsdf.inputs["Metallic"].default_value = opts["--metal"]
    for l in nt.links:      # короткие имена текстур (Godot вынесет их в файлы car_w124_<имя>.jpg)
        if l.from_node.type == 'TEX_IMAGE' and l.from_node.image:
            l.from_node.image.name = "color" if l.to_socket.name == "Base Color" else "rough"

# масштаб по длине, на пол, по центру
lo = mathutils.Vector((1e9,) * 3)
hi = mathutils.Vector((-1e9,) * 3)
for v in car.data.vertices:
    lo = mathutils.Vector(map(min, lo, v.co))
    hi = mathutils.Vector(map(max, hi, v.co))
k = opts["--length"] / (hi.x - lo.x)
shift = mathutils.Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
for v in car.data.vertices:
    v.co = (v.co - shift) * k
size = (hi - lo) * k
print("SIZE", tuple(round(c, 3) for c in size))

bpy.ops.object.select_all(action='DESELECT')
car.select_set(True)
bpy.ops.object.shade_smooth()
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', use_selection=True, export_apply=True,
                          export_image_format='JPEG', export_jpeg_quality=85, export_animations=False)
print("EXPORTED", dst)
