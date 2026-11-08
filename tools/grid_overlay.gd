extends SceneTree
## Рисует сетку с подписями координат поверх картинки (для ручных замеров). Аргументы: <вход> <выход> <шаг>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://" + a[0]))
	img.convert(Image.FORMAT_RGBA8)
	var step := int(a[2])
	for x in range(0, img.get_width(), step):
		var c := Color(1, 0, 0) if x % (step * 5) == 0 else Color(0, 0, 1, 0.6)
		for y in img.get_height():
			img.set_pixel(x, y, c)
	for y in range(0, img.get_height(), step):
		var c := Color(1, 0, 0) if y % (step * 5) == 0 else Color(0, 0, 1, 0.6)
		for x in img.get_width():
			img.set_pixel(x, y, c)
	img.save_png(ProjectSettings.globalize_path("res://" + a[1]))
	quit()
