extends SceneTree
## Список костей модели: Godot.exe --headless --path . --script res://tools/list_bones.gd -- res://x.glb
func _init() -> void:
	var p: String = OS.get_cmdline_user_args()[0]
	var n := (load(p) as PackedScene).instantiate()
	var sk := n.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var names := []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
	print("BONES ", names)
	quit()
