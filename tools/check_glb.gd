extends SceneTree
## Проверка: Godot открывает GLB и видит в нём узлы/анимации. Аргумент: res://путь.glb
func _init() -> void:
	var path := OS.get_cmdline_user_args()[0]
	var scene: PackedScene = load(path)
	if scene == null:
		print("GLB_FAIL ", path)
		quit(1)
		return
	var root := scene.instantiate()
	var meshes := root.find_children("*", "MeshInstance3D", true, false).size()
	var players := root.find_children("*", "AnimationPlayer", true, false)
	var anims := []
	for p in players:
		anims.append_array((p as AnimationPlayer).get_animation_list())
	print("GLB_OK ", path, " meshes=", meshes, " anims=", anims)
	root.free()
	quit(0)
