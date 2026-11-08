class_name Level
extends Node2D
## Уровень 1: двухэтажная квартира в разрезе, видна целиком. Лестница слева соединяет этажи.
## Мир в пикселях исходных картинок комнат (1536×1024 каждая).
##
##   [ лестница ] [ Ванная  ] [ Спальня ] [ Балкон ] [ лестница ]   ← 2-й этаж (floor 0)
##   [ лестница ] [ Коридор ] [ Кухня   ] [ Зал    ] [ лестница ]   ← 1-й этаж (floor 1)
## Лестниц две (правая — зеркальная), персонаж идёт к ближайшей.
##
## Колесо мыши — приблизить к герою / вернуться к виду всей квартиры.
##
## Отладочные аргументы:
##   --timescale=N   ускорить время в N раз
##   --start=H       начать с часа H (например 11.2)
##   --hero-go=X,Y   герой сразу идёт в мировую точку (проверка ходьбы и лестницы)
##   --hero-at=X,Y   поставить героя в мировую точку
##   --sneak         герой сразу крадётся
##   --zoom          начать в приближенном виде

const FLOORS := [["bathroom", "bedroom", "balcony"], ["hallway", "kitchen", "living"]]
const ROOM_NAMES := {"bathroom": "Ванная", "bedroom": "Спальня", "balcony": "Балкон",
	"hallway": "Коридор", "kitchen": "Кухня", "living": "Зал", "stairs": "Лестница"}
const ROOM_W := 1536.0
const ROOM_H := 1024.0
## Картинка лестницы 887×1774: пол 1-го этажа на y≈1650, площадка 2-го на y≈700.
## Масштаб подобран так, чтобы эти точки совпали с полом этажей.
const STAIR_SCALE := 1.12
const STAIR_OFFSET_Y := 164.0
const STAIR_W := 887.0 * STAIR_SCALE
const STAIR_BOTTOM_X := 50.0    # где начинается подъём (от внешнего края лестницы)
const STAIR_TOP_X := 735.0      # где кончаются ступени на площадке
const SLAB := 40.0             # толщина перекрытия между этажами
const WALL := 36.0             # толщина перегородки между комнатами
const FLOOR_LINE := 948.0      # где стоят ноги, от верха комнаты
const START_HOUR := 7.5
const END_HOUR := 20.0
const SEC_PER_HOUR := 50.0
const HUD_TOP := 150.0         # место под панель сверху

var hour := START_HOUR
var time_scale := 1.0
var hero: Hero
var neighbor: Neighbor
var camera: Camera2D
var zoomed := false
var _full_zoom := 1.0
var _clock_label: Label
var _status_label: Label
var _rect := {}                # комната -> Rect2 в мире

func _ready() -> void:
	var args := _args()
	time_scale = float(args.get("timescale", "1"))
	hour = float(args.get("start", str(START_HOUR)))
	zoomed = args.has("zoom")

	_build_house()

	neighbor = Neighbor.new()
	neighbor.level = self
	neighbor.position = spot("bedroom", 760)
	add_child(neighbor)

	hero = Hero.new()
	hero.level = self
	hero.position = spot("hallway", 260)
	add_child(hero)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	add_child(camera)
	var view_h := 1080.0 - HUD_TOP - 20.0
	_full_zoom = minf(1900.0 / world_size().x, view_h / world_size().y)
	_update_camera(true)

	_build_hud()
	if args.has("hero-at"):
		var q: PackedStringArray = args["hero-at"].split(",")
		hero.position = snap_to_floor(Vector2(float(q[0]), float(q[1])))
	if args.has("hero-go"):
		var p: PackedStringArray = args["hero-go"].split(",")
		hero.go_to_point(Vector2(float(p[0]), float(p[1])))
	if args.has("sneak"):
		hero.toggle_sneak()

# --- Геометрия ---------------------------------------------------------------

func world_size() -> Vector2:
	return Vector2(2 * STAIR_W + 3 * ROOM_W + 2 * WALL, 2 * ROOM_H + SLAB)

func right_stairs_x() -> float:
	return STAIR_W + 3 * ROOM_W + 2 * WALL

func floor_top(f: int) -> float:
	return f * (ROOM_H + SLAB)

func floor_y(f: int) -> float:
	return floor_top(f) + FLOOR_LINE

func floor_of(y: float) -> int:
	return 0 if y < ROOM_H + SLAB * 0.5 else 1

## Точки входа на лестницу s (0 — левая, 1 — правая) на этаже f.
## Внизу — у внешней стены дома, наверху — там, где ступени выходят на площадку.
func stair_point(s: int, f: int) -> Vector2:
	var x := STAIR_TOP_X if f == 0 else STAIR_BOTTOM_X
	if s == 1:
		x = world_size().x - x
	return Vector2(x, floor_y(f))

func walk_min_x(f: int) -> float:
	return STAIR_TOP_X if f == 0 else STAIR_BOTTOM_X

func walk_max_x(f: int) -> float:
	return world_size().x - walk_min_x(f)

func room_rect(room: String) -> Rect2:
	return _rect[room]

## Точка на полу комнаты: x отсчитывается от левого края комнаты.
func spot(room: String, x: float) -> Vector2:
	var r: Rect2 = _rect[room]
	return Vector2(r.position.x + x, r.position.y + FLOOR_LINE)

func room_at(p: Vector2) -> String:
	for room in _rect:
		var r: Rect2 = _rect[room]
		if p.x >= r.position.x and p.x < r.end.x + WALL and floor_of(p.y) == floor_of(r.position.y + 1):
			return room
	return "stairs"

## Привязать клик к полу ближайшего этажа.
func snap_to_floor(p: Vector2) -> Vector2:
	var f := floor_of(p.y)
	return Vector2(clampf(p.x, walk_min_x(f), walk_max_x(f)), floor_y(f))

## Маршрут: если цель на другом этаже — через ближайшую (по общей длине пути) лестницу.
func plan_path(from: Vector2, to: Vector2) -> Array[Vector2]:
	var ff := floor_of(from.y)
	var tf := floor_of(to.y)
	if ff == tf:
		return [to]
	var best: Array[Vector2] = []
	var best_len := INF
	for s in 2:
		var a := stair_point(s, ff)
		var b := stair_point(s, tf)
		var length := absf(from.x - a.x) + a.distance_to(b) + absf(b.x - to.x)
		if length < best_len:
			best_len = length
			best = [a, b, to]
	return best

# --- Постройка ---------------------------------------------------------------

func _build_house() -> void:
	var ws := world_size()
	_add_rect(Vector2(-4000, -4000), Vector2(ws.x + 8000, ws.y + 8000), Color("2a1d14"), -100)

	for f in 2:
		var x := STAIR_W
		for c in 3:
			var room: String = FLOORS[f][c]
			var r := Rect2(x, floor_top(f), ROOM_W, ROOM_H)
			_rect[room] = r
			var path := "res://assets/rooms/room_%s.png" % room
			if ResourceLoader.exists(path):
				var s := Sprite2D.new()
				s.texture = load(path)
				s.centered = false
				s.position = r.position
				s.z_index = -50
				add_child(s)
			else:
				_placeholder_room(r, ROOM_NAMES[room])
			x += ROOM_W
			if c < 2:
				_add_rect(Vector2(x, r.position.y), Vector2(WALL, ROOM_H * 0.2), Color("5a3d28"), -40)
				_add_rect(Vector2(x, r.position.y + ROOM_H * 0.2), Vector2(WALL, ROOM_H * 0.8), Color("1e140d"), -40)
				x += WALL
	# перекрытие между этажами (над лестницами — проём)
	_add_rect(Vector2(STAIR_W, ROOM_H), Vector2(right_stairs_x() - STAIR_W, SLAB), Color("4a3020"), -30)
	_build_stairs()

func _placeholder_room(r: Rect2, title: String) -> void:
	_add_rect(r.position, r.size, Color("c9a46a"), -50)
	_add_rect(Vector2(r.position.x, r.position.y + FLOOR_LINE - 30), Vector2(r.size.x, r.size.y - FLOOR_LINE + 30), Color("a0784f"), -49)
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = title + "\n(картинка скоро)"
	l.add_theme_font_size_override("font_size", 90)
	l.add_theme_color_override("font_color", Color("6b4a2c"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(r.size.x, 300)
	l.position = r.position + Vector2(0, 300)
	l.z_index = -48
	add_child(l)

## Заглушка лестницы, пока нет картинки: стена, ступени по диагонали, площадка наверху.
func _build_stairs() -> void:
	var path := "res://assets/rooms/room_stairs.png"
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		# низ картинки ниже пола 1-го этажа обрезаем, сверху — полоса потолка
		var visible_h := (world_size().y - STAIR_OFFSET_Y) / STAIR_SCALE
		for side in 2:
			var x0 := 0.0 if side == 0 else right_stairs_x()
			_add_rect(Vector2(x0, 0), Vector2(STAIR_W, STAIR_OFFSET_Y + 10), Color("b06e35"), -51)
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.region_enabled = true
			s.region_rect = Rect2(0, 0, tex.get_width(), visible_h)
			s.scale = Vector2.ONE * STAIR_SCALE
			s.flip_h = side == 1
			s.position = Vector2(x0, STAIR_OFFSET_Y)
			s.z_index = -50
			add_child(s)
		return
	_add_rect(Vector2.ZERO, Vector2(STAIR_W, world_size().y), Color("b88a55"), -50)
	var bottom := stair_point(0, 1)
	var top := stair_point(0, 0)
	var steps := 16
	var poly := PackedVector2Array()
	poly.append(Vector2(bottom.x - 60, bottom.y + 30))
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var a := bottom.lerp(top, t0)
		var b := bottom.lerp(top, t1)
		poly.append(Vector2(a.x - 60 + (b.x - a.x) * 0.0, b.y + 30))
		poly.append(Vector2(b.x - 60, b.y + 30))
	poly.append(Vector2(top.x + 60, top.y + 30))
	poly.append(Vector2(top.x + 60, top.y + 90))
	poly.append(Vector2(bottom.x + 40, bottom.y + 90))
	var p2 := Polygon2D.new()
	p2.polygon = poly
	p2.color = Color("7a4e2d")
	p2.z_index = -45
	add_child(p2)
	# площадка 2-го этажа
	_add_rect(Vector2(top.x - 120, ROOM_H - 46), Vector2(STAIR_W - top.x + 120, SLAB + 46), Color("4a3020"), -44)

func _add_rect(pos: Vector2, size: Vector2, color: Color, z: int) -> ColorRect:
	var cr := ColorRect.new()
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE   # иначе прямоугольник съедает клики
	cr.position = pos
	cr.size = size
	cr.color = color
	cr.z_index = z
	add_child(cr)
	return cr

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(24, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.11, 0.07, 0.9)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	hud.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 30)
	panel.add_child(hb)
	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 64)
	_clock_label.add_theme_color_override("font_color", Color("ffe9b8"))
	hb.add_child(_clock_label)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 28)
	_status_label.add_theme_color_override("font_color", Color("e8cfa0"))
	hb.add_child(_status_label)

	var hint := Label.new()
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.text = "ЛКМ — идти   ·   ПКМ / Shift — крадучись   ·   колесо — приблизить"
	hint.add_theme_font_size_override("font_size", 24)
	hint.add_theme_color_override("font_color", Color("c9a878"))
	hint.position = Vector2(24, 1040)
	hud.add_child(hint)

# --- Цикл --------------------------------------------------------------------

func _process(delta: float) -> void:
	hour = minf(hour + delta * time_scale / SEC_PER_HOUR, END_HOUR)
	neighbor.update_schedule(hour)
	_update_camera(false)

	var h := int(hour)
	var m := int((hour - h) * 60.0)
	_clock_label.text = "%02d:%02d" % [h, m]
	_status_label.text = "Сосед: %s  ·  %s\nГерой: %s%s" % [
		neighbor.activity, ROOM_NAMES[room_at(neighbor.position)],
		ROOM_NAMES[room_at(hero.position)], "  ·  крадётся" if hero.sneaking else ""]

func _update_camera(instant: bool) -> void:
	var z: float
	if zoomed:
		z = 1080.0 / ROOM_H
		camera.position = Vector2(hero.position.x, floor_top(floor_of(hero.position.y)) + ROOM_H * 0.5)
	else:
		z = _full_zoom
		camera.position = world_size() * 0.5 - Vector2(0, HUD_TOP * 0.5 / z)
	camera.zoom = Vector2.ONE * z
	for c in [hero, neighbor]:
		if c:
			c.ui_scale = 0.6 / z if not zoomed else 1.0
	if instant:
		camera.reset_smoothing()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and not zoomed:
			zoomed = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and zoomed:
			zoomed = false

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out
