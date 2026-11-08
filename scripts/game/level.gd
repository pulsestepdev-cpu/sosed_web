class_name Level
extends Node2D
## Уровень 1: квартира из комнат в ряд, камера за героем, игровые часы, сосед по расписанию.
## Мир в пикселях исходных картинок (высота комнаты 1024), камера приближает до 1080.
##
## Отладочные аргументы:
##   --timescale=N   ускорить время в N раз
##   --start=H       начать с часа H (например 11.2)
##   --hero-x=X      поставить героя в мировую точку X
##   --cam=hero|neighbor  за кем следит камера
##   --hero-go=X     герой сразу идёт в точку X (проверка ходьбы)
##   --sneak         герой сразу крадётся

const ROOMS := ["bathroom", "hallway", "kitchen", "living", "balcony"]
const ROOM_NAMES := {"bathroom": "Ванная", "hallway": "Коридор", "kitchen": "Кухня", "living": "Зал", "balcony": "Балкон"}
const ROOM_W := 1536.0
const ROOM_H := 1024.0
const WALL := 48.0
const FLOOR_Y := 948.0
const START_HOUR := 7.5
const END_HOUR := 20.0
const SEC_PER_HOUR := 50.0

var hour := START_HOUR
var time_scale := 1.0
var hero: Hero
var neighbor: Neighbor
var camera: Camera2D
var cam_target: Node2D
var _clock_label: Label
var _status_label: Label
var _left := {}

func _ready() -> void:
	var args := _args()
	time_scale = float(args.get("timescale", "1"))
	hour = float(args.get("start", str(START_HOUR)))

	_build_rooms()

	neighbor = Neighbor.new()
	neighbor.level = self
	neighbor.position = Vector2(room_left("living") + 380, FLOOR_Y)
	add_child(neighbor)

	hero = Hero.new()
	hero.position = Vector2(float(args.get("hero-x", str(room_left("hallway") + 220))), FLOOR_Y)
	hero.min_x = 60.0
	hero.max_x = total_width() - 60.0
	add_child(hero)

	camera = Camera2D.new()
	camera.zoom = Vector2.ONE * (1080.0 / ROOM_H)
	camera.limit_left = 0
	camera.limit_right = int(total_width())
	camera.limit_top = 0
	camera.limit_bottom = int(ROOM_H)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	cam_target = neighbor if args.get("cam", "hero") == "neighbor" else hero
	camera.position = Vector2(cam_target.position.x, ROOM_H / 2.0)
	camera.reset_smoothing()

	_build_hud()
	if args.has("hero-go"):
		hero.go_to(float(args["hero-go"]))
	if args.has("sneak"):
		hero.toggle_sneak()

func _build_rooms() -> void:
	var bg := ColorRect.new()
	bg.color = Color("3b2a1e")
	bg.position = Vector2(-2000, -200)
	bg.size = Vector2(total_width() + 4000, ROOM_H + 400)
	bg.z_index = -100
	add_child(bg)
	var x := 0.0
	for r in ROOMS:
		_left[r] = x
		var s := Sprite2D.new()
		s.texture = load("res://assets/rooms/room_%s.png" % r)
		s.centered = false
		s.position = Vector2(x, 0)
		s.z_index = -50
		add_child(s)
		x += ROOM_W
		if r != ROOMS[-1]:
			# перегородка с проёмом: тёмная стена сверху, проход у пола
			var wall := ColorRect.new()
			wall.color = Color("5a3d28")
			wall.position = Vector2(x, 0)
			wall.size = Vector2(WALL, ROOM_H * 0.22)
			wall.z_index = -40
			add_child(wall)
			var jamb := ColorRect.new()
			jamb.color = Color("2e1f15")
			jamb.position = Vector2(x, ROOM_H * 0.22)
			jamb.size = Vector2(WALL, ROOM_H * 0.78)
			jamb.z_index = -40
			add_child(jamb)
			x += WALL

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.11, 0.07, 0.85)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	hud.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 44)
	_clock_label.add_theme_color_override("font_color", Color("ffe9b8"))
	vb.add_child(_clock_label)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 26)
	_status_label.add_theme_color_override("font_color", Color("e8cfa0"))
	vb.add_child(_status_label)

func _process(delta: float) -> void:
	hour = minf(hour + delta * time_scale / SEC_PER_HOUR, END_HOUR)
	neighbor.update_schedule(hour)
	camera.position = Vector2(cam_target.position.x, ROOM_H / 2.0)

	var h := int(hour)
	var m := int((hour - h) * 60.0)
	_clock_label.text = "%02d:%02d" % [h, m]
	_status_label.text = "Сосед: %s (%s)\nГерой: %s%s" % [
		neighbor.activity, ROOM_NAMES[room_at(neighbor.position.x)],
		ROOM_NAMES[room_at(hero.position.x)], "  · крадётся" if hero.sneaking else ""]

func room_left(room: String) -> float:
	return _left[room]

func room_at(x: float) -> String:
	var found: String = ROOMS[0]
	for r in ROOMS:
		if x >= _left[r]:
			found = r
	return found

func total_width() -> float:
	return ROOM_W * ROOMS.size() + WALL * (ROOMS.size() - 1)

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out
