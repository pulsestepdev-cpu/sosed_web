extends Node2D
## Все предметы из папки на светлом и тёмном фоне (проверка краёв после вырезки).

var dir := "res://assets/props/drinks"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--props="):
			dir = "res://assets/props/" + a.substr(8)
	for half in 2:
		var bg := ColorRect.new()
		bg.color = Color("e9d8b4") if half == 0 else Color("3b2a1e")
		bg.position = Vector2(0, half * 540)
		bg.size = Vector2(1920, 540)
		add_child(bg)
	var files: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png") and not f.ends_with("_sheet.png"):
			files.append(f)
	files.sort()
	var step := 1920.0 / maxf(files.size(), 1)
	for half in 2:
		for i in files.size():
			var s := Sprite2D.new()
			s.texture = load(dir.path_join(files[i]))
			var k := minf(170.0 / s.texture.get_width(), 380.0 / s.texture.get_height())
			s.scale = Vector2.ONE * k
			s.position = Vector2(step * (i + 0.5), half * 540 + 270)
			add_child(s)
