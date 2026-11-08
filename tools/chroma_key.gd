extends SceneTree
## Убирает зелёный или пурпурный фон (хромакей) и режет лист персонажа на отдельные виды.
## Запуск:
##   Godot.exe --headless --path . --script res://tools/chroma_key.gd -- <вход.png> <папка_выхода> <префикс> [имена,через,запятую]
## Пример:
##   ... -- assets/raw/neighbor_final_green.png assets/characters/neighbor neighbor front,side,three_quarter

const KEY_HARD := 0.22   # насколько зелёный пиксель считается фоном полностью
const KEY_SOFT := 0.06   # ниже этого — точно персонаж; между — полупрозрачный край
const PAD := 8           # отступ вокруг вырезанного вида, px

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Нужно: <вход.png> <папка_выхода> <префикс> [имена]")
		quit(1)
		return
	var src := _abs(args[0])
	var out_dir := _abs(args[1])
	var prefix := args[2]
	var names := args[3].split(",") if args.size() > 3 else PackedStringArray()

	var img := Image.load_from_file(src)
	if img == null:
		push_error("Не удалось открыть " + src)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	_key_out(img)
	DirAccess.make_dir_recursive_absolute(out_dir)
	img.save_png(out_dir.path_join(prefix + "_sheet.png"))

	var parts := _split(img)
	print("Найдено видов: ", parts.size())
	for i in parts.size():
		var part: Image = parts[i]
		var name := names[i] if i < names.size() else str(i + 1)
		var path := out_dir.path_join("%s_%s.png" % [prefix, name])
		part.save_png(path)
		print("  ", path, "  ", part.get_size())
	quit(0)

func _abs(p: String) -> String:
	return p if p.is_absolute_path() else ProjectSettings.globalize_path("res://" + p)

## Цвет фона определяется по левому верхнему углу: зелёный (#00FF00) или пурпурный (#FF00FF).
func _key_out(img: Image) -> void:
	var corner := img.get_pixel(2, 2)
	var magenta := corner.r > 0.5 and corner.b > 0.5 and corner.g < 0.4
	print("Фон: ", "пурпурный" if magenta else "зелёный")
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var key: float
			var fixed: Color
			if magenta:
				var rb := minf(c.r, c.b)
				key = rb - c.g
				fixed = Color(minf(c.r, c.g + (c.r - rb)), c.g, minf(c.b, c.g + (c.b - rb)), c.a)
			else:
				var other := maxf(c.r, c.b)
				key = c.g - other
				fixed = Color(c.r, other, c.b, c.a)
			if key >= KEY_HARD:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif key > KEY_SOFT:
				fixed.a = 1.0 - (key - KEY_SOFT) / (KEY_HARD - KEY_SOFT)
				img.set_pixel(x, y, fixed)  # убираем цветной отсвет фона
			elif key > 0.0:
				img.set_pixel(x, y, fixed)

## Ищет отдельные фигуры (связные области непрозрачных пикселей).
## Мелкие оторванные кусочки приклеивает к ближайшей крупной фигуре.
## Каждый вид вырезается своим отдельным изображением, чужие пиксели внутри рамки стираются.
var _labels := PackedInt32Array()

func _split(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	_labels.resize(w * h)
	_labels.fill(-1)
	var boxes: Array[Rect2i] = []
	var areas: Array[int] = []
	for y in h:
		for x in w:
			var i := y * w + x
			if _labels[i] != -1 or img.get_pixel(x, y).a <= 0.1:
				continue
			var id := boxes.size()
			var stack := PackedInt32Array([i])
			_labels[i] = id
			var mn := Vector2i(x, y)
			var mx := Vector2i(x, y)
			var area := 0
			while stack.size() > 0:
				var p := stack[stack.size() - 1]
				stack.remove_at(stack.size() - 1)
				area += 1
				var px := p % w
				var py := p / w
				mn = Vector2i(mini(mn.x, px), mini(mn.y, py))
				mx = Vector2i(maxi(mx.x, px), maxi(mx.y, py))
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = px + d.x
					var ny: int = py + d.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var ni := ny * w + nx
					if _labels[ni] == -1 and img.get_pixel(nx, ny).a > 0.1:
						_labels[ni] = id
						stack.append(ni)
			boxes.append(Rect2i(mn, mx - mn + Vector2i.ONE))
			areas.append(area)

	var big_area := 0
	for a in areas:
		big_area = maxi(big_area, a)
	var main_ids: Array[int] = []
	for id in boxes.size():
		if areas[id] >= big_area * 0.2:
			main_ids.append(id)
	main_ids.sort_custom(func(a, b): return boxes[a].get_center().x < boxes[b].get_center().x)

	# к какой крупной фигуре принадлежит каждая область
	var owner := PackedInt32Array()
	owner.resize(boxes.size())
	for id in boxes.size():
		var best := main_ids[0]
		var best_d := INF
		for m in main_ids:
			var d := Vector2(boxes[id].get_center()).distance_to(Vector2(boxes[m].get_center()))
			if d < best_d:
				best_d = d
				best = m
		owner[id] = best

	var result := []
	for m in main_ids:
		var r := Rect2i()
		var first := true
		for id in boxes.size():
			if owner[id] == m:
				r = boxes[id] if first else r.merge(boxes[id])
				first = false
		r = r.grow(PAD).intersection(Rect2i(0, 0, w, h))
		var part := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
		for y in r.size.y:
			for x in r.size.x:
				var gx := r.position.x + x
				var gy := r.position.y + y
				var l := _labels[gy * w + gx]
				if l != -1 and owner[l] == m:
					part.set_pixel(x, y, img.get_pixel(gx, gy))
		result.append(part)
	return result
