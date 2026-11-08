extends Node
## Скриншоты для разработки.
## Авто: Godot.exe --path . -- --shot=screenshots/x.png [--shot-delay=1.5] [--shot-scene=res://...]
##   снимает кадр через задержку и закрывает игру.
## Вручную: F12 в игре — сохраняет screenshots/manual_<время>.png и screenshots/last.png

const DIR := "res://screenshots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var args := _parse_args()
	if args.has("shot-scene"):
		get_tree().change_scene_to_file.call_deferred(args["shot-scene"])
	if args.has("shot"):
		var delay := float(args.get("shot-delay", "1.0"))
		await get_tree().create_timer(delay, true, false, true).timeout
		await RenderingServer.frame_post_draw
		_save(args["shot"])
		get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		await RenderingServer.frame_post_draw
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		_save("screenshots/manual_%s.png" % stamp)
		_save("screenshots/last.png")

func _save(rel_path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := rel_path if rel_path.is_absolute_path() else ProjectSettings.globalize_path("res://" + rel_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	print("[screenshot] ", path, " -> ", error_string(err))

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out
