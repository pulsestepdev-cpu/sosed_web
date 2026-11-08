class_name Level
extends Node2D
## Уровень 1: двухэтажная квартира в разрезе, видна целиком. Две лестницы (слева и справа).
## Мир в пикселях исходных картинок комнат (1536×1024 каждая).
##
##   [ лестница ] [ Ванная  ] [ Спальня ] [ Балкон ] [ лестница ]   ← 2-й этаж (floor 0)
##   [ лестница ] [ Коридор ] [ Кухня   ] [ Зал    ] [ лестница ]   ← 1-й этаж (floor 1)
##
## Отладочные аргументы:
##   --autostart      без экрана вступления
##   --speed=N        ускорить всё (Engine.time_scale) — для тестов
##   --timescale=N    ускорить игровое время в N раз
##   --start=H        начать с часа H (например 11.2)
##   --hero-at=X,Y    поставить героя в мировую точку
##   --hero-go=X,Y    герой сразу идёт в мировую точку
##   --hero-go2=X,Y,T второй клик через T секунд
##   --sneak          герой сразу крадётся
##   --zoom           начать в приближенном виде
##   --give=a,b       положить предметы в сумку
##   --drunk=N        начальное опьянение
##   --use=a,sel:item,b  герой по очереди идёт и использует точки (sel: — выбрать предмет)
##   --swap=a,b       считать подменёнными (mouthwash, fridge, ...)
##   --take=a,b       считать унесёнными (gamepad, phone, keys)
##   --debug-stairs   нарисовать линию пути по лестнице

const FLOORS := [["bathroom", "bedroom", "balcony"], ["hallway", "kitchen", "living"]]
const ROOM_NAMES := {"bathroom": "Ванная", "bedroom": "Спальня", "balcony": "Балкон",
	"hallway": "Коридор", "kitchen": "Кухня", "living": "Зал", "stairs": "Лестница"}
const ROOM_W := 1536.0
const ROOM_H := 1024.0
const SLAB := 40.0             # толщина перекрытия между этажами
const WALL := 36.0             # толщина перегородки между комнатами
const FLOOR_LINE := 948.0      # где стоят ноги, от верха комнаты

## Картинка лестницы 887×1774. Замерено по сетке: ноги на площадке 2-го этажа — y=705,
## на полу 1-го — y=1660. Масштаб и сдвиг подобраны, чтобы эти линии совпали с полами этажей.
const STAIR_SCALE := 1.114
const STAIR_OFFSET_Y := 162.6            # = FLOOR_LINE - 705 * STAIR_SCALE
const STAIR_W := 887.0 * STAIR_SCALE
## Путь ног по лестнице в координатах картинки: пол → нижняя ступень → проступи → площадка.
const STAIR_PATH := [Vector2(22, 1660), Vector2(86, 1528), Vector2(116, 1466), Vector2(136, 1397),
	Vector2(662, 792), Vector2(736, 705)]
const STAIR_CROP_TOP := 125.0  # срезаем потолок и светильник картинки, рисуем общий потолок
const CEILING_H := 40.0
const CEILING_COLOR := Color("a8673b")

const START_HOUR := 7.5
const END_HOUR := 20.0
const SEC_PER_HOUR := 50.0
const HUD_TOP := 150.0

var hour := START_HOUR
var time_scale := 1.0
var hero: Hero
var neighbor: Neighbor
var rules: Level1Rules
var hud: Hud
var camera: Camera2D
var zoomed := false
var started := false
var paused := false
var _full_zoom := 1.0
var _rect := {}
var _pending: Hotspot
var _hovered: Hotspot
var _noise_cd := 0.0
var _caught_cd := 0.0
var _warned := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := _args()
	time_scale = float(args.get("timescale", "1"))
	hour = float(args.get("start", str(START_HOUR)))
	zoomed = args.has("zoom")

	_build_house()

	neighbor = Neighbor.new()
	neighbor.level = self
	neighbor.position = spot("bedroom", 540)
	add_child(neighbor)

	hero = Hero.new()
	hero.level = self
	hero.position = spot("hallway", 230)
	add_child(hero)
	hero.arrived.connect(_on_hero_arrived)

	rules = Level1Rules.new()
	add_child(rules)
	neighbor.rules = rules
	rules.setup(self)
	rules.finished.connect(_on_finished)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	add_child(camera)
	_full_zoom = minf(1900.0 / world_size().x, (1080.0 - HUD_TOP - 150.0) / world_size().y)
	_update_camera(true)

	hud = Hud.new()
	add_child(hud)
	hud.bind(rules)
	hud.start_pressed.connect(func(): started = true)
	hud.restart_pressed.connect(func():
		Engine.time_scale = 1.0
		get_tree().reload_current_scene())

	if args.has("debug-stairs"):
		_draw_stair_debug()
	if args.has("drunk"):
		rules.drunk = float(args["drunk"])
	if args.has("give"):
		for it in args["give"].split(","):
			rules.inventory.append(it)
		rules.inventory_changed.emit()
	if args.has("swap"):
		for it in args["swap"].split(","):
			rules.swapped[it] = true
			rules.spots[it].done = true
	if args.has("take"):
		for it in args["take"].split(","):
			rules.taken[it] = true
	if args.has("hero-at"):
		var q: PackedStringArray = args["hero-at"].split(",")
		hero.position = snap_to_floor(Vector2(float(q[0]), float(q[1])))
	if args.has("hero-go"):
		var p: PackedStringArray = args["hero-go"].split(",")
		hero.go_to_point(Vector2(float(p[0]), float(p[1])))
	if args.has("hero-go2"):
		var g: PackedStringArray = args["hero-go2"].split(",")
		get_tree().create_timer(float(g[2])).timeout.connect(
			func(): hero.go_to_point(Vector2(float(g[0]), float(g[1]))))
	if args.has("sneak"):
		hero.toggle_sneak()
	if args.has("use"):
		# цепочка действий героя: --use=canisters,mouthwash — по очереди
		_debug_uses = Array(args["use"].split(","))
		_debug_next_use()
	if args.has("speed"):
		Engine.time_scale = float(args["speed"])
	if args.has("autostart"):
		started = true
	else:
		hud.show_intro()

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

## Путь по лестнице s (0 — левая, 1 — правая) в мировых точках, снизу вверх.
func stair_poly(s: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in STAIR_PATH:
		var x: float = p.x * STAIR_SCALE
		if s == 1:
			x = world_size().x - x
		out.append(Vector2(x, STAIR_OFFSET_Y + p.y * STAIR_SCALE))
	out[0].y = floor_y(1)
	out[-1].y = floor_y(0)
	return out

func walk_min_x(f: int) -> float:
	return stair_poly(0)[-1].x if f == 0 else stair_poly(0)[0].x

func walk_max_x(f: int) -> float:
	return world_size().x - walk_min_x(f)

func room_rect(room: String) -> Rect2:
	return _rect[room]

## Точка на полу комнаты: x отсчитывается от левого края комнаты.
func spot(room: String, x: float) -> Vector2:
	var r: Rect2 = _rect[room]
	return Vector2(r.position.x + x, r.position.y + FLOOR_LINE)

func room_at(p: Vector2) -> String:
	if on_stairs(p):
		return "stairs"
	for room in _rect:
		var r: Rect2 = _rect[room]
		if p.x >= r.position.x and p.x < r.end.x + WALL and floor_of(p.y) == floor_of(r.position.y + 1):
			return room
	return "stairs"

func on_stairs(p: Vector2) -> bool:
	return absf(p.y - floor_y(0)) > 1.0 and absf(p.y - floor_y(1)) > 1.0

func snap_to_floor(p: Vector2) -> Vector2:
	var f := floor_of(p.y)
	return Vector2(clampf(p.x, walk_min_x(f), walk_max_x(f)), floor_y(f))

## Маршрут: на другом этаже — через ближайшую лестницу, точно по ступеням.
## Если персонаж уже на ступенях — продолжает по ним в нужную сторону.
func plan_path(from: Vector2, to: Vector2) -> Array[Vector2]:
	var tf := floor_of(to.y)
	var out: Array[Vector2] = []
	if on_stairs(from):
		var s := 0 if from.x < world_size().x * 0.5 else 1
		var poly := stair_poly(s)
		var i := 0
		while i < poly.size() - 2 and from.y < poly[i + 1].y:
			i += 1
		if tf == 0:
			for k in range(i + 1, poly.size()):
				out.append(poly[k])
		else:
			for k in range(i, -1, -1):
				out.append(poly[k])
		out.append(to)
		return out
	var ff := floor_of(from.y)
	if ff == tf:
		return [to]
	var best_len := INF
	for s in 2:
		var poly := stair_poly(s)
		if ff == 0:
			poly.reverse()
		var length := absf(from.x - poly[0].x) + absf(poly[-1].x - to.x)
		for k in poly.size() - 1:
			length += poly[k].distance_to(poly[k + 1])
		if length < best_len:
			best_len = length
			out = poly.duplicate()
			out.append(to)
	return out

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
			var s := Sprite2D.new()
			s.texture = load("res://assets/rooms/room_%s.png" % room)
			s.centered = false
			s.position = r.position
			s.z_index = -50
			add_child(s)
			x += ROOM_W
			if c < 2:
				_add_rect(Vector2(x, r.position.y), Vector2(WALL, ROOM_H * 0.2), Color("5a3d28"), -40)
				_add_rect(Vector2(x, r.position.y + ROOM_H * 0.2), Vector2(WALL, ROOM_H * 0.8), Color("1e140d"), -40)
				x += WALL
	_add_rect(Vector2(STAIR_W, ROOM_H), Vector2(right_stairs_x() - STAIR_W, SLAB), Color("4a3020"), -30)
	_build_stairs()

func _build_stairs() -> void:
	var tex: Texture2D = load("res://assets/rooms/room_stairs.png")
	var main_y := STAIR_OFFSET_Y + STAIR_CROP_TOP * STAIR_SCALE
	var visible_h := (world_size().y - main_y) / STAIR_SCALE
	var band_src_y := 135.0
	var band_src_h := 170.0
	for side in 2:
		var x0 := 0.0 if side == 0 else right_stairs_x()
		var y := 0.0
		while y < main_y:
			var band := _stair_sprite(tex, Rect2(0, band_src_y, tex.get_width(), band_src_h), side, Vector2(x0, y))
			band.z_index = -51
			y += band_src_h * STAIR_SCALE
		_stair_sprite(tex, Rect2(0, STAIR_CROP_TOP, tex.get_width(), visible_h), side, Vector2(x0, main_y))
		_add_rect(Vector2(x0, 0), Vector2(STAIR_W, CEILING_H), CEILING_COLOR, -49)
		# перекрытие под площадкой — продолжение перекрытия между комнатами
		var land_x: float = stair_poly(0)[-1].x - 50.0
		var lx := land_x if side == 0 else right_stairs_x()
		_add_rect(Vector2(lx, ROOM_H), Vector2(STAIR_W - land_x, SLAB), Color("4a3020"), -30)

func _stair_sprite(tex: Texture2D, region: Rect2, side: int, pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.region_enabled = true
	s.region_rect = region
	s.scale = Vector2.ONE * STAIR_SCALE
	s.flip_h = side == 1
	s.position = pos
	s.z_index = -50
	add_child(s)
	return s

func _draw_stair_debug() -> void:
	for s in 2:
		var l := Line2D.new()
		l.points = PackedVector2Array(stair_poly(s))
		l.width = 8
		l.default_color = Color(1, 0, 1)
		l.z_index = 300
		add_child(l)

func _add_rect(pos: Vector2, size: Vector2, color: Color, z: int) -> ColorRect:
	var cr := ColorRect.new()
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE   # иначе прямоугольник съедает клики
	cr.position = pos
	cr.size = size
	cr.color = color
	cr.z_index = z
	add_child(cr)
	return cr

# --- Цикл --------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_camera(false)
	_update_hover()
	var running := started and not paused and not rules.over
	hero.process_mode = Node.PROCESS_MODE_INHERIT if running or rules.over else Node.PROCESS_MODE_DISABLED
	neighbor.process_mode = hero.process_mode
	if running:
		hour = minf(hour + delta * time_scale / SEC_PER_HOUR, END_HOUR)
		neighbor.update_schedule(hour, delta)
		neighbor.look_around(delta)
		_update_detection(delta)
		if hour >= END_HOUR:
			rules.time_up()
	hud.update_view(hour,
		"%s  ·  %s" % [neighbor.activity, ROOM_NAMES[room_at(neighbor.position)]],
		"%s%s%s" % [ROOM_NAMES[room_at(hero.position)], "  ·  крадётся" if hero.sneaking else "",
			"  ·  спрятался" if hero.in_hiding else ""],
		neighbor.suspicion, paused, Engine.time_scale > 1.0)

func _update_detection(delta: float) -> void:
	_noise_cd -= delta
	_caught_cd -= delta
	if _caught_cd > 0.0 or neighbor.mode == "asleep":
		return
	# лоу-кик «тренера» по герою рядом
	if neighbor.is_kicking() and not hero.in_hiding and room_at(hero.position) == room_at(neighbor.position) \
			and absf(hero.position.x - neighbor.position.x) < 260.0:
		_catch("Лоу-кик! Работаем!")
		return
	if neighbor.sees(hero, hour):
		var rate := 1.0 / 1.1
		if hero.is_noisy():
			rate *= 2.0
		if hero.busy > 0.0:
			rate *= 1.5
		neighbor.suspicion = minf(1.0, neighbor.suspicion + delta * rate)
		if neighbor.suspicion > 0.35 and not _warned and neighbor.mode == "schedule":
			_warned = true
			neighbor.face_towards(hero.position.x)
			neighbor.set_face("suspicious")
			neighbor.say("Э… Кто здесь?", 1.5)
		if neighbor.suspicion >= 1.0:
			_catch("А ну пошёл отсюда!")
	else:
		neighbor.suspicion = maxf(0.0, neighbor.suspicion - delta * 0.5)
		if neighbor.suspicion <= 0.0 and _warned:
			_warned = false
			if neighbor.mode == "schedule":
				neighbor.set_face(rules.default_face())
		# шаги слышно на том же этаже
		if hero.is_noisy() and _noise_cd <= 0.0 and neighbor.mode == "schedule" and not neighbor.lying \
				and floor_of(hero.position.y) == floor_of(neighbor.position.y) \
				and absf(hero.position.x - neighbor.position.x) < 650.0:
			_noise_cd = 5.0
			neighbor.face_towards(hero.position.x)
			neighbor.say("Кто здесь топает?", 1.5)
			neighbor.suspicion = minf(1.0, neighbor.suspicion + 0.2)

func _catch(line: String) -> void:
	_caught_cd = 3.0
	_warned = false
	neighbor.suspicion = 0.0
	neighbor.suspicious_until = hour + 1.0
	hero.stop()
	hero.set_hidden(false)
	_pending = null
	neighbor.face_towards(hero.position.x)
	neighbor.react("angry", line, 1.8)
	rules.caught()
	hud.show_toast("Поймал! (%d / 3)" % rules.catches, false)
	var tw := create_tween()
	tw.tween_property(hero, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): hero.position = spot("hallway", 230))
	tw.tween_property(hero, "modulate:a", 1.0, 0.4)

func _on_hero_arrived() -> void:
	if _pending:
		var h := _pending
		_pending = null
		hero.face_towards(h.rect.get_center().x)
		rules.hero_use(h)
		if not _debug_uses.is_empty():
			get_tree().create_timer(1.2).timeout.connect(_debug_next_use)

var _debug_uses: Array = []

func _debug_next_use() -> void:
	if _debug_uses.is_empty():
		return
	var id: String = _debug_uses.pop_front()
	if id.begins_with("sel:"):
		rules.select(id.substr(4))
		_debug_next_use()
		return
	var h: Hotspot = rules.spots[id]
	_pending = h
	hero.set_hidden(false)
	hero.walk_path(plan_path(hero.position, h.walk))

func _on_finished(win: bool, reason: String) -> void:
	Engine.time_scale = 1.0
	await get_tree().create_timer(0.8).timeout
	hud.show_results(win, reason)

# --- Ввод и камера ------------------------------------------------------------

func _hotspot_at(p: Vector2) -> Hotspot:
	for h in rules.spots.values():
		if h.contains(p):
			return h
	return null

func _update_hover() -> void:
	var p := get_global_mouse_position()
	var h: Hotspot = null if hud.has_overlay() else _hotspot_at(p)
	if _hovered and _hovered != h:
		_hovered.hovered = false
	_hovered = h
	if h:
		h.hovered = true
		hud.set_tooltip(rules.describe(h), get_viewport().get_mouse_position())
	elif rules.selected != "":
		hud.set_tooltip("В руке: %s" % rules.item_title(rules.selected), get_viewport().get_mouse_position())
	else:
		hud.set_tooltip("", Vector2.ZERO)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoomed = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoomed = false
		elif not started or rules.over or paused:
			return
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var p := get_global_mouse_position()
			var h := _hotspot_at(p)
			if h:
				_pending = h
				hero.set_hidden(false)
				if hero.position.distance_to(h.walk) < 3.0:
					_on_hero_arrived()
				else:
					hero.walk_path(plan_path(hero.position, h.walk))
			else:
				_pending = null
				hero.go_to_point(p)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			hero.toggle_sneak()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SHIFT:
				hero.toggle_sneak()
			KEY_SPACE:
				if started and not rules.over:
					paused = not paused
			KEY_F:
				Engine.time_scale = 1.0 if Engine.time_scale > 1.0 else 3.0

func _update_camera(instant: bool) -> void:
	var z: float
	camera.limit_enabled = zoomed
	camera.limit_left = 0
	camera.limit_right = int(world_size().x)
	camera.limit_top = 0
	camera.limit_bottom = int(world_size().y)
	if zoomed:
		z = 1080.0 / ROOM_H
		camera.position = Vector2(hero.position.x, floor_top(floor_of(hero.position.y)) + ROOM_H * 0.5)
	else:
		z = _full_zoom
		camera.position = world_size() * 0.5 + Vector2(0, -8.0 / z)
	camera.zoom = Vector2.ONE * z
	for c in [hero, neighbor]:
		if c:
			c.ui_scale = 0.6 / z if not zoomed else 1.0
	if rules:
		for h in rules.spots.values():
			h.ui = 0.55 / z if not zoomed else 1.0
	if instant:
		camera.reset_smoothing()

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out
