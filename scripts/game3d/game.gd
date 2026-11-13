class_name Game3D
extends Node
## День недели в 3D: дом в разрезе (scenes/levels/day_N.tscn), герой, сосед, правила, интерфейс.
## Что открыто в какой день — scripts/levels/days.gd (Days).
##
##   этаж  2: [         чердак                       ]   (дверь с площадки правой лестницы)
##   этаж  1: [лестница][ванная  ][спальня ][балкон ][лестница]
##   этаж  0: [лестница][прихожая][кухня   ][зал    ][лестница]
##   этаж -1: [   подвал                  ][ гараж          ]   (дверь под левой лестницей)
## Оси: X — вдоль дома, Y — вверх, Z — к зрителю. Ходят по «дорожке» z = LANE.
## Между этажами — лестницы и двери-переходы (зашёл в дверь на одном этаже — вышел на другом).
##
## Отладочные аргументы (после --):
##   --day=N           день недели 1..7 (без него — выбранный на экране недели)
##   --autostart       без вступления        --start=H        начать с часа H (например 11.2)
##   --timescale=N     игровое время в N раз  --speed=N        Engine.time_scale
##   --drunk=N         начальное опьянение    --give=a,b       предметы в сумку
##   --swap=a,b        считать подменёнными   --take=a,b       считать унесёнными
##   --trap=a,b        ловушки на полу        --salad          салат на столе
##   --hero-at=X,F     герой в точке X на этаже F (-1..2)   --goto=X,F  герой идёт туда (лестницы, двери)
##   --zoom            начать с приближения   --use=a,sel:item,b  герой по очереди использует точки
## Автотесты (scripts/debug/, обёртки в tools/qa/):
##   --bot=careful|normal|reckless   бот сам проходит уровень
##   --report=путь.json  отчёт (события, задания, поимки, наложения голосов, FPS)
##   --quit-on-end       закрыть после итогов   --max-real=сек   страховка по реальному времени
##   --perf              печатать FPS раз в 5 с      --quality=low|high|auto  графика

const PROPS := "res://assets/models/props/"
const FH := Days.FH
const F1 := 0.0
const F2 := 3.05
const LANE := -1.0
const START_HOUR := 7.5
const END_HOUR := 20.0
const SEC_PER_HOUR := 50.0
const HERO_START := Vector3(5.1, 0.0, -1.0)
const RESPAWN := Vector3(0.38, F2 * 0.5, -1.0)   # после «люлей» — на площадку лестницы (там сосед не видит)
const MATTRESS_H := 0.5       # высота матраса над полом
const SALAD_SPOT := Vector3(8.7, 0.0, -2.72)   # где сосед встаёт за столом в финале
const ROOM_NAMES := {"bathroom": "Ванная", "bedroom": "Спальня", "balcony": "Балкон",
	"hallway": "Прихожая", "kitchen": "Кухня", "living": "Зал", "stairs": "Лестница",
	"basement": "Подвал", "garage": "Гараж", "attic": "Чердак"}

var day: Dictionary              # данные дня (Days.day)
var day_n := 1
var house_w := 17.0              # длина дома в этот день
var has_r := true                # есть правая лестница
var portals: Array = []          # открытые двери-переходы: {id, a, b, path, door_a, door_b, title_a, title_b}
var _floors: Array[int] = []     # этажи, где есть комнаты
var _connectors: Array = []      # лестницы и двери: {a, b, pts, cost}
var _door_nodes := {}            # двери-переходы: "cellar_a" -> узел двери
var _ref_dist := 20.5            # расстояние камеры, под которое подобраны приближения (дом среды)
var level: Node3D
var furn: Node3D
var cam: Camera3D
var hero: Hero3D
var neighbor: Neighbor3D
var rules: Rules3D
var hud: Hud3D
var overlay: Control
var spots := {}                 # id -> Spot3D
var hour := START_HOUR
var time_scale := 1.0
var started := false
var paused := false
var zoomed := false
var _home: Transform3D
var _home_fov := 29.0
var _shake := 0.0
var _cam_x := 8.5
var _cam_y := 3.0
var _pending: Spot3D
var _hovered: Spot3D
var _noise_cd := 0.0
var _caught_cd := 0.0
var _warned := false
var _props := {}               # доп. предметы: keys, salad, salad_table, peeltrap, soaptrap
var _last_nx := 0.0
var _debug_uses: Array = []
var _ghost := false
var _pan := Vector2(8.5, 3.0)  # крупная камера: куда смотрит (x, высота)
var _manual_cam := false       # игрок сам сдвинул обзор к краю
var finale_hero := false
var _week_shown := false
var _tv: MeshInstance3D
var _tv_mat: ShaderMaterial
var _tv_power := 0.0       # финал: камера крупно на танцующем герое
var _focus_n := false
var _touches := {}             # палец -> позиция (телефон)
var _tap_from := Vector2.ZERO
var _tap_t := 0
var _dragged := false
var _pinch0 := 0.0
var _touch_on_ui := false
var low_quality := false      # сейчас включена низкая графика
var _q_samples: Array[float] = []   # авто-качество: FPS в первые секунды игры
var _q_decided := false
var _env_ambient := 0.28
var qa_bot: QaBot
var qa_rec: QaRecorder
var _perf_t := 0.0          # отладка: камера крупно на соседе            # отладка: сосед не замечает героя

func _ready() -> void:
	var args := _args()
	time_scale = float(args.get("timescale", "1"))
	if args.has("quality"):        # --quality=low|high|auto (не сохраняется в настройках)
		Settings.quality = args["quality"]
	hour = float(args.get("start", str(START_HOUR)))
	zoomed = args.has("zoom") or Settings.camera_close or Settings.is_touch()
	day_n = int(args.get("day", str(Progress.day)))
	day = Days.day(day_n)
	Progress.day = day_n
	house_w = day["w"]
	has_r = house_w >= 16.9
	for id in day["rooms"]:
		var f: int = Days.ROOMS[id][2]
		if not f in _floors:
			_floors.append(f)
	_floors.sort()
	_build_connectors()

	level = (load(day["scene"]) as PackedScene).instantiate() as Node3D
	level.set_script(null)                 # в сцене — скрипт просмотрщика, в игре он не нужен
	add_child(level)
	furn = level.get_node("Furniture") as Node3D
	cam = level.get_node("Camera") as Camera3D
	_home = cam.transform
	_home_fov = cam.fov
	for id in ["cellar_a", "cellar_b", "attic_a", "attic_b"]:
		var dn := furn.get_node_or_null("Doors/door_" + id)
		if dn:
			_door_nodes[id] = dn
	# ненужное в игре: персонажи просмотрщика
	level.get_node("Characters").queue_free()
	_add_props()

	neighbor = Neighbor3D.new()
	neighbor.name = "Neighbor"
	neighbor.game = self
	level.add_child(neighbor)
	neighbor.setup("res://assets/models/characters/neighbor.glb", "neighbor")
	neighbor.PLAN = day["plan"]
	neighbor.LOOP_FROM = day["loop"]
	hero = Hero3D.new()
	hero.name = "Hero"
	hero.game = self
	level.add_child(hero)
	hero.setup("res://assets/models/characters/hero.glb", "hero")
	hero.borrow_clip("res://assets/models/characters/neighbor.glb", "dance", "dance")
	hero.position = HERO_START
	hero.rotation.y = PI / 2
	hero.target_yaw = PI / 2
	hero.arrived.connect(_on_hero_arrived)
	hero.portal_used.connect(_on_portal_used)
	neighbor.portal_used.connect(_on_portal_used)
	neighbor.partner = hero        # говорят по очереди: сосед в приоритете, герой ждёт
	hero.partner = neighbor
	hero.yields = true

	rules = Rules3D.new()
	add_child(rules)
	neighbor.rules = rules
	rules.setup(self)
	rules.finished.connect(_on_finished)
	_build_spots()
	_put_neighbor_in_bed()

	overlay = Overlay3D.new()
	overlay.game = self
	var ol := CanvasLayer.new()
	ol.layer = 5
	add_child(ol)
	ol.add_child(overlay)

	hud = Hud3D.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	hud.bind(rules)
	hud.start_pressed.connect(func():
		started = true
		Settings.sfx("creak", 0.5))
	hud.restart_pressed.connect(func():
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().reload_current_scene())
	hud.menu_pressed.connect(func():
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	hud.resume_pressed.connect(func(): _set_paused(false))
	hud.next_pressed.connect(func():
		get_tree().paused = false
		Engine.time_scale = 1.0
		Progress.day = mini(7, day_n + 1)
		get_tree().reload_current_scene())
	hud.week_pressed.connect(func():
		if rules.over and rules.drunk >= 100.0 and day_n == 7 and not hud.has_overlay() and not _week_shown:
			_week_shown = true
			hud.show_week_results()
			return
		get_tree().paused = false
		Engine.time_scale = 1.0
		Progress.open_week = true
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	hud.touch_action.connect(_on_touch_action)
	process_mode = Node.PROCESS_MODE_ALWAYS
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	rules.process_mode = Node.PROCESS_MODE_PAUSABLE
	Settings.music("main_musik")

	_apply_debug(args)
	if hour > Neighbor3D.WAKE_HOUR and neighbor.mode == "bed":   # старт с середины дня
		neighbor.skip_to(hour)
	_update_camera(true)
	var env := (level.get_node("Environment") as WorldEnvironment).environment
	_env_ambient = env.ambient_light_energy
	apply_quality()
	Settings.qa_mark("game_ready")

func _apply_debug(args: Dictionary) -> void:
	if args.has("drunk"):
		rules.drunk = float(args["drunk"])
	if args.has("give"):
		for it in args["give"].split(","):
			rules.inventory.append(it)
		rules.selected = rules.inventory[-1]
		rules.inventory_changed.emit()
	if args.has("swap"):
		for it in args["swap"].split(","):
			rules.swapped[it] = true
			spots[it].done = true
	if args.has("take"):
		for it in args["take"].split(","):
			rules.taken[it] = true
			for s in spots.values():
				if s.item == it and s.kind == "take":
					s.active = false
					if s.node:
						s.node.visible = false
	if args.has("trap"):
		for it in args["trap"].split(","):
			rules.traps[it] = true
			show_trap(it, true)
	if args.has("salad"):
		rules.salad_on_table = true
		place_salad()
	if args.has("hero-at"):
		var q: PackedStringArray = args["hero-at"].split(",")
		hero.position = lane_point(float(q[0]), int(q[1]))
	if args.has("goto"):    # герой идёт в точку: --goto=X,этаж (проверка лестниц и дверей-переходов)
		var g: PackedStringArray = args["goto"].split(",")
		get_tree().create_timer(0.3).timeout.connect(func(): hero.go(plan_path(hero.position, lane_point(float(g[0]), int(g[1])))))
	if args.has("use"):
		_debug_uses = Array(args["use"].split(","))
		get_tree().create_timer(0.5).timeout.connect(_debug_next_use)
	if args.has("log"):   # печать событий в консоль — для автопрогонов
		rules.toast.connect(func(t, _g): print("[%05.2f] TOAST %s" % [hour, t]))
		rules.finished.connect(func(w, r): print("[%05.2f] FINISHED %s %s score=%d shame=%d" % [hour, w, r, rules.score, rules.shame_percent()]))
		var last := ["", "", "", ""]
		get_tree().process_frame.connect(func():
			if hero.bubble != last[3]:
				last[3] = hero.bubble
				if hero.bubble != "":
					print("[%05.2f] HERO %s" % [hour, hero.bubble])
			if neighbor.thought != last[2]:
				last[2] = neighbor.thought
				if neighbor.thought != "":
					print("[%05.2f] THINK %s" % [hour, neighbor.thought])
			if neighbor.activity != last[0]:
				last[0] = neighbor.activity
				print("[%05.2f] N %s  drunk=%d  pos=%.1f,%.1f" % [hour, neighbor.activity, rules.drunk, neighbor.position.x, neighbor.position.y])
			if neighbor.bubble != last[1]:
				last[1] = neighbor.bubble
				if neighbor.bubble != "":
					print("[%05.2f] SAY %s" % [hour, neighbor.bubble]))
	if args.has("hide"):    # сразу спрятать героя: --hide=table
		var hs: Spot3D = spots[args["hide"]]
		hero.position = hs.walk
		hero.hide_in(hs)
	if args.has("finale"):  # сразу довести до 100
		get_tree().create_timer(0.5).timeout.connect(func(): rules.add_drunk(100.0, true))
	if args.has("catch"):   # сосед ловит героя
		get_tree().create_timer(0.8).timeout.connect(func(): _catch("А ну пошёл отсюда!"))
	_ghost = args.has("ghost")
	_focus_n = args.has("focus")
	if args.has("sneak"):
		hero.toggle_sneak()
	if args.has("click"):   # эмуляция кликов мышью: --click=x:y:сек;x:y:сек
		for c in args["click"].split(";"):
			var q: PackedStringArray = c.split(":")
			get_tree().create_timer(float(q[2])).timeout.connect(func():
				var e := InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_LEFT
				e.pressed = true
				e.position = Vector2(float(q[0]), float(q[1]))
				Input.warp_mouse(e.position)
				Input.parse_input_event(e))
	if args.has("dump-spots"):   # экранные зоны кликов: --dump-spots
		get_tree().create_timer(1.0).timeout.connect(func():
			for sp in spots.values():
				print("SPOT %-10s rect=%s hit=%s" % [sp.id, screen_rect(sp.aabb), hit_rect(sp)]))
	if args.has("report"):
		qa_rec = QaRecorder.new()
		add_child(qa_rec)
		qa_rec.setup(self, args["report"], args.has("quit-on-end"), float(args.get("max-real", "0")))
	if args.has("bot"):
		qa_bot = QaBot.new()
		add_child(qa_bot)
		qa_bot.setup(self, args["bot"])
	if args.has("perf"):
		get_tree().process_frame.connect(func():
			_perf_t += get_process_delta_time() / maxf(0.001, Engine.time_scale)
			if _perf_t >= 5.0:
				_perf_t = 0.0
				print("[%05.2f] PERF fps=%d  frame=%.1fms  objects=%d  draw_calls=%d" % [hour, Engine.get_frames_per_second(),
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_COUNT),
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
				if OS.has_feature("web"):
					JavaScriptBridge.eval("(window.__qaFps=window.__qaFps||[]).push(%d);" % Engine.get_frames_per_second(), true))
	if args.has("qa") and OS.has_feature("web"):   # для web_check: последнее событие и где герой
		rules.toast.connect(func(t, _g): Settings.qa_mark("last_toast", t))
		get_tree().create_timer(1.0).timeout.connect(_qa_hero_tick)
	if args.has("speed"):
		Engine.time_scale = float(args["speed"])
	if args.has("autostart"):
		started = true
	else:
		hud.show_intro()

# ---------------------------------------------------------------- геометрия
func floor_y(f: int) -> float:
	return f * FH

func floor_of(p: Vector3) -> int:
	return Days.floor_of_y(p.y)

func lane_point(x: float, f: int) -> Vector3:
	return Vector3(x, floor_y(f), LANE)

## На лестнице (в лестничной клетке между 1-м и 2-м этажом, в том числе у дверей-переходов там).
func on_stairs(p: Vector3) -> bool:
	if p.y < -0.3 or p.y > F2 + 0.3:
		return false
	return p.x < 3.05 or (has_r and p.x > 13.95)

func room_open(id: String) -> bool:
	return id in day["rooms"]

func room_at(p: Vector3) -> String:
	if on_stairs(p):
		return "stairs"
	var f := floor_of(p)
	var best := "stairs"
	var bd := INF
	for id in day["rooms"]:
		var r: Array = Days.ROOMS[id]
		if r[2] != f:
			continue
		if p.x >= r[0] and p.x < r[1]:
			return id
		var d := minf(absf(p.x - r[0]), absf(p.x - r[1]))
		if d < bd:
			bd = d
			best = id
	return best

## Границы дорожки на этаже f (по открытым комнатам), с отступом от стен.
func floor_range(f: int) -> Vector2:
	var lo := INF
	var hi := -INF
	for id in day["rooms"]:
		var r: Array = Days.ROOMS[id]
		if r[2] == f:
			lo = minf(lo, r[0])
			hi = maxf(hi, r[1])
	if lo == INF:
		return Vector2(3.25, 3.25)
	return Vector2(lo + 0.25, hi - 0.25)

## Путь по лестнице s (0 — левая, 1 — правая) снизу вверх: нижний марш спереди, площадка у наружной
## стены, верхний марш сзади, выход в комнату 2-го этажа.
func stair_poly(s: int) -> Array[Vector3]:
	var half := F2 * 0.5
	var pts: Array[Vector3] = [Vector3(3.2, F1, LANE), Vector3(2.92, F1, LANE), Vector3(0.72, half, LANE),
		Vector3(0.38, half, LANE), Vector3(0.38, half, -2.15), Vector3(0.72, half, -2.15),
		Vector3(2.92, F2, -2.15), Vector3(3.35, F2, -2.15), Vector3(3.7, F2, LANE)]
	if s == 1:
		for i in pts.size():
			pts[i].x = 17.0 - pts[i].x
	return pts

static func is_tp(p: Vector3) -> bool:
	return p.x > Days.TP * 0.5

## Длина пути (точка-телепорт — как пара метров).
static func path_len(from: Vector3, pts: Array) -> float:
	var d := 0.0
	var p := from
	var jumped := false
	for q in pts:
		if is_tp(q):
			jumped = true
			continue
		d += 2.0 if jumped else p.distance_to(q)
		jumped = false
		p = q
	return d

## Связи между этажами: лестницы (0 ↔ 1) и открытые двери-переходы.
func _build_connectors() -> void:
	_connectors.clear()
	portals.clear()
	var stairs := [0, 1] if has_r else [0]
	for s in stairs:
		var pts := stair_poly(s)
		_connectors.append({"a": 0, "b": 1, "pts": pts, "cost": path_len(pts[0], pts)})
	for id in Days.PORTALS:
		var p: Dictionary = Days.PORTALS[id]
		if not room_open(p["needs"]):
			continue
		var pts: Array[Vector3] = []
		pts.assign(p["path"])
		var c := {"a": p["a"], "b": p["b"], "pts": pts, "cost": path_len(pts[0], pts) + 1.5, "portal": id}
		_connectors.append(c)
		var pd := p.duplicate()
		pd["id"] = id
		portals.append(pd)

## Если стоит на подходе к двери-переходу (сошёл с дорожки) — вернуться по подходу на дорожку.
func _leave_portal_approach(from: Vector3, out: Array[Vector3]) -> Vector3:
	if absf(from.z - LANE) < 0.05:
		return from
	for c in _connectors:
		if not c.has("portal"):
			continue
		var pts: Array = c["pts"]
		var tp := 0
		while tp < pts.size() and not is_tp(pts[tp]):
			tp += 1
		var side_b: Array = pts.slice(tp + 1)
		side_b.reverse()
		for seq in [pts.slice(0, tp), side_b]:    # от дорожки к двери
			for i in seq.size() - 1:
				var cp := Geometry3D.get_closest_point_to_segment(from, seq[i], seq[i + 1])
				if cp.distance_to(from) < 0.12:
					for k in range(i, -1, -1):
						out.append(seq[k])
					return seq[0]
	return from

## Маршрут: по этажу — по дорожке; на другой этаж — через лучшую цепочку лестниц и дверей-переходов
## (Дейкстра по точкам входа/выхода). Сходит с дорожки и возвращается на неё сам.
func plan_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	from = _leave_portal_approach(from, out)
	var tf := floor_of(to)
	if on_stairs(from):
		var s := 0 if from.x < 8.5 else 1
		var poly := stair_poly(s)
		var best := 0
		var bd := INF
		for i in poly.size() - 1:
			var d := Geometry3D.get_closest_point_to_segment(from, poly[i], poly[i + 1]).distance_to(from)
			if d < bd:
				bd = d
				best = i
		if tf >= 1:
			for k in range(best + 1, poly.size()):
				out.append(poly[k])
		else:
			for k in range(best, -1, -1):
				out.append(poly[k])
		from = out[-1] if not out.is_empty() else from
	elif absf(from.z - LANE) > 0.05:
		from = Vector3(from.x, from.y, LANE)
		out.append(from)
	var ff := floor_of(from)
	if ff != tf:
		out.append_array(_route_floors(from, ff, to, tf))
	if absf(to.z - LANE) > 0.05:
		out.append(Vector3(to.x, to.y, LANE))
	out.append(to)
	return out

func _route_floors(from: Vector3, ff: int, to: Vector3, tf: int) -> Array[Vector3]:
	# узлы: 0 — старт, 1 — цель, дальше по два на связь (конец a, конец b)
	var nodes: Array = [[ff, from.x], [tf, to.x]]
	for c in _connectors:
		var pts: Array = c["pts"]
		nodes.append([c["a"], pts[0].x])
		nodes.append([c["b"], pts[-1].x])
	var n := nodes.size()
	var dist: Array[float] = []
	var prev: Array[int] = []
	var done: Array[bool] = []
	for i in n:
		dist.append(INF)
		prev.append(-1)
		done.append(false)
	dist[0] = 0.0
	while true:
		var u := -1
		for i in n:
			if not done[i] and dist[i] < INF and (u < 0 or dist[i] < dist[u]):
				u = i
		if u < 0 or u == 1:
			break
		done[u] = true
		for v in n:
			if done[v] or v == u:
				continue
			var w := INF
			if nodes[u][0] == nodes[v][0]:
				w = absf(nodes[u][1] - nodes[v][1])
			if u >= 2 and v >= 2 and (u - 2) / 2 == (v - 2) / 2:
				w = _connectors[(u - 2) / 2]["cost"]
			if dist[u] + w < dist[v]:
				dist[v] = dist[u] + w
				prev[v] = u
	var out: Array[Vector3] = []
	if prev[1] < 0:
		return out
	var chain: Array[int] = []
	var k := 1
	while k >= 0:
		chain.push_front(k)
		k = prev[k]
	for i in chain.size() - 1:
		var u := chain[i]
		var v := chain[i + 1]
		if u >= 2 and v >= 2 and (u - 2) / 2 == (v - 2) / 2:
			var pts: Array = (_connectors[(u - 2) / 2]["pts"] as Array).duplicate()
			if u > v:
				pts.reverse()
			out.append_array(pts)
	return out

## Дверь-переход, ближайшая к точке (для анимации двери): "cellar_a" и т.п.
func _door_near(p: Vector3) -> String:
	for pd in portals:
		for side in ["a", "b"]:
			var dp: Vector3 = pd["door_" + side]
			if absf(dp.x - p.x) < 0.8 and absf(dp.y - p.y) < 1.0:
				return "%s_%s" % [pd["id"], side]
	return ""

## Персонаж входит в дверь-переход или выходит из неё — дверь открывается и закрывается.
func _on_portal_used(at: Vector3) -> void:
	var id := _door_near(at)
	if id == "" or not _door_nodes.has(id):
		return
	for ap in (_door_nodes[id] as Node).find_children("*", "AnimationPlayer", true, false):
		var p := ap as AnimationPlayer
		if p.has_animation("open"):
			p.play("open")
			Settings.sfx("creak", 0.45, randf_range(0.85, 1.1))
			get_tree().create_timer(0.9, false).timeout.connect(func():
				p.play_backwards("open")
				Settings.sfx("thud", 0.18, 1.4))
			return

## Дверь-переход под точкой экрана: куда она ведёт (точка на дорожке другого этажа) или null.
func portal_at(mp: Vector2) -> Variant:
	for pd in portals:
		for side in ["a", "b"]:
			var dp: Vector3 = pd["door_" + side]
			var r := screen_rect(AABB(Vector3(dp.x - 0.45, dp.y, dp.z), Vector3(0.9, 2.1, 0.3)))
			if r.grow(6).has_point(mp):
				var pts: Array = pd["path"]
				var dest: Vector3 = pts[-1] if side == "a" else pts[0]
				return {"to": dest, "title": pd["title_" + side]}
	return null

# ---------------------------------------------------------------- предметы и места
func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree() and n.visible:
			continue
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	if n is MeshInstance3D:
		var b2: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
		out = b2 if first else out.merge(b2)
	return out

func _put(name: String, file: String, pos: Vector3, yaw := 0.0, scale := 1.0) -> Node3D:
	var inst := (load(PROPS + file + ".glb") as PackedScene).instantiate() as Node3D
	inst.name = name
	furn.add_child(inst)
	inst.position = pos
	inst.rotation_degrees.y = yaw
	inst.scale = Vector3.ONE * scale
	return inst

func _add_props() -> void:
	var counter := _bounds(furn.get_node("kitchen_counter") as Node3D)
	var table := _bounds(furn.get_node("table") as Node3D)
	var tub := _bounds(furn.get_node("bathtub") as Node3D)
	var bowl := _bounds(furn.get_node("key_bowl") as Node3D)
	_props["keys"] = _put("keys", "keys", Vector3(bowl.get_center().x, bowl.end.y - 0.02, bowl.get_center().z))
	_props["salad"] = _put("salad", "salad", Vector3(7.85, counter.end.y, counter.get_center().z + 0.1))
	_props["salad_table"] = _put("salad_table", "salad", Vector3(8.7, table.end.y, table.get_center().z - 0.15))
	_props["salad_table"].visible = false
	_props["soap_dish"] = _put("soap_dish", "soap_dish", Vector3(4.3, tub.end.y, tub.end.z - 0.12))
	_props["peeltrap"] = _put("peel", "banana_peel", Vector3(9.45, F1 + 0.01, LANE + 0.18), 30, 1.3)
	_props["peeltrap"].visible = false
	_props["soaptrap"] = _put("soap_floor", "soap_dish", Vector3(4.92, F2 + 0.01, LANE + 0.18), 20)
	_props["soaptrap"].visible = false
	# телефон на диване: крупнее и прислонён к спинке экраном к игроку, иначе с общего плана не видно
	var phone := furn.get_node_or_null("smartphone") as Node3D
	if phone:
		phone.scale = Vector3.ONE * 2.6
		phone.position = Vector3(11.15, 0.5, -3.05)
		phone.rotation_degrees = Vector3(-65, 180, 0)
	# свежая шпаклёвка на стене спальни, где сосед «работает»
	var patch := MeshInstance3D.new()
	patch.name = "putty_patch"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.85, 0.01)
	patch.mesh = bm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("d9d4c7")
	pm.roughness = 1.0
	patch.material_override = pm
	furn.add_child(patch)
	patch.position = Vector3(9.9, F2 + 1.15, -3.982)
	# экран телевизора: включается, пока сосед играет в приставку (если в этот день зал открыт)
	if furn.get_node_or_null("tv") == null:
		return
	var tvb := _bounds(furn.get_node("tv") as Node3D)
	_tv = MeshInstance3D.new()
	_tv.name = "tv_screen"
	var qm := QuadMesh.new()
	qm.size = Vector2(tvb.size.x * 0.88, tvb.size.y * 0.8)
	_tv.mesh = qm
	_tv_mat = ShaderMaterial.new()
	_tv_mat.shader = load("res://assets/tv_game.gdshader")
	_tv.material_override = _tv_mat
	furn.add_child(_tv)
	_tv.position = Vector3(tvb.get_center().x, tvb.get_center().y + tvb.size.y * 0.04, tvb.end.z + 0.006)
	_tv.visible = false
## Места дня: укрытия — во всех открытых комнатах; тайники — те, что есть в items дня (там же — что в них);
## подмены, «утащить» и ловушки — только для заданий дня.
func _build_spots() -> void:
	var items: Dictionary = day["items"]
	var tasks: Array = day["tasks"]
	for d in Rules3D.SPOTS:
		var id: String = d[0]
		var kind: String = d[1]
		var walk := lane_point(d[3], d[4])
		if not room_open(room_at(walk)):
			continue
		match kind:
			"stash":
				if not items.has(id):
					continue
			"swap", "take", "trap":
				if not id in tasks:
					continue
		var s := Spot3D.new()
		s.id = id
		s.kind = kind
		s.title = d[5]
		s.item = items[id] if kind == "stash" else d[6]
		s.floor = d[4]
		s.walk = walk
		var nname: String = d[2]
		if nname == "salad" or nname == "keys" or nname == "soap_dish":
			s.node = _props[nname]
		elif nname != "":
			s.node = furn.get_node_or_null(nname) as Node3D
		if s.node:
			s.aabb = _bounds(s.node)
		else:   # ловушка на полу — низкая область у пола перед предметом
			s.aabb = AABB(Vector3(d[3] - 0.3, floor_y(s.floor), LANE - 0.2), Vector3(0.6, 0.12, 0.6))
		spots[s.id] = s

func _put_neighbor_in_bed() -> void:
	var bed := _bounds(furn.get_node("bed") as Node3D)
	neighbor.lie_on_bed(Vector3(bed.get_center().x, F2, bed.get_center().z), 0.0)
	# подогнать по костям позы сна: голова к изголовью (+X), середина тела — по центру матраса, спина на матрасе
	neighbor.ap.seek(0.5, true)
	var sk := neighbor.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := func(n: String) -> Vector3: return sk.to_global(sk.get_bone_global_pose(sk.find_bone(n)).origin)
	var head: Vector3 = bone.call("Head")
	var feet: Vector3 = (bone.call("LeftFoot") + bone.call("RightFoot")) * 0.5
	var yaw := PI / 2 - atan2(head.x - feet.x, head.z - feet.z)
	neighbor.lie_on_bed(neighbor.position, yaw)
	neighbor.ap.seek(0.5, true)
	head = bone.call("Head")
	feet = (bone.call("LeftFoot") + bone.call("RightFoot")) * 0.5
	var hips: Vector3 = bone.call("Hips")
	var mid := (head + feet) * 0.5
	neighbor.position += Vector3(bed.get_center().x + 0.05 - mid.x, F2 + MATTRESS_H + 0.13 - hips.y, bed.get_center().z + 0.05 - mid.z)

## Границы предмета в его собственных координатах (без его трансформа) и с ним (в координатах родителя).
func local_bounds(n: Node3D) -> AABB:
	return n.transform.affine_inverse() * local_bounds_xf(n)

func local_bounds_xf(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := n.transform
		var p: Node = m
		var chain: Array[Transform3D] = []
		while p != n:
			chain.push_front((p as Node3D).transform)
			p = p.get_parent()
		for t in chain:
			xf = xf * t
		var b: AABB = xf * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

## Открыть дверцу/крышку предмета (если у него есть клип open) и закрыть через seconds.
func open_prop(s: Spot3D, seconds: float) -> void:
	if s == null or s.node == null:
		return
	for ap in s.node.find_children("*", "AnimationPlayer", true, false):
		var p := ap as AnimationPlayer
		if p.has_animation("open"):
			p.play("open")
			Settings.sfx("creak", 0.35, randf_range(0.9, 1.2))
			get_tree().create_timer(seconds, false).timeout.connect(func(): p.play_backwards("open"))
			return

## Финал: за сколько секунд клипа fall_forward голова опускается к салату и на сколько сдвинуть соседа,
## чтобы она попала точно в миску. Возвращает [время, сдвиг].
func fit_fall_to_salad(n: Actor) -> Array:
	var salad: Vector3 = _bounds(_props["salad_table"]).get_center()
	var sk := n.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hb := sk.find_bone("Head")
	n.ap.play("fall_forward", 0.0)
	var length := n.ap.current_animation_length
	var t := length * 0.6
	var head := Vector3.ZERO
	var step := 0.02
	var x := 0.0
	while x < length:
		n.ap.seek(x, true)
		head = sk.to_global(sk.get_bone_global_pose(hb).origin)
		if head.y <= salad.y + 0.16:
			t = x
			break
		x += step
	n.ap.seek(0.0, true)
	return [t, Vector3(salad.x - head.x, 0.0, salad.z - head.z)]

func show_prop(name: String, vis: bool) -> void:
	if _props.has(name):
		_props[name].visible = vis

func place_salad() -> void:
	_props["salad_table"].visible = true
	Settings.sfx("clink", 0.5)

func show_trap(id: String, vis: bool) -> void:
	show_prop(id, vis)

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

# ---------------------------------------------------------------- цикл
func _process(delta: float) -> void:
	_update_camera(false, delta)
	_update_hover()
	var running := started and not paused and not rules.over
	if running:
		hour = minf(hour + delta * time_scale / SEC_PER_HOUR, END_HOUR)
		neighbor.update_schedule(hour, delta)
		neighbor.look_around(delta)
		_check_traps()
		_update_detection(delta)
		if hour >= END_HOUR:
			rules.time_up()
	var hero_text: String = ROOM_NAMES[room_at(hero.position)]
	if hero.sneaking:
		hero_text += "  ·  крадётся"
	if hero.in_hiding:
		hero_text += "  ·  спрятался"
	hud.update_view(hour, "%s  ·  %s" % [neighbor.activity, ROOM_NAMES[room_at(neighbor.position)]],
		hero_text, neighbor.suspicion, paused, Engine.time_scale > 1.0, delta)
	_last_nx = neighbor.position.x
	_update_tv(delta)
	_auto_quality(delta)

## Качество графики: high — тени, лампы в комнатах, полное разрешение; low — без теней и ламп (светлее общий свет),
## 3D в 70% разрешения (интерфейс остаётся чётким). auto: стартует с high и в первые секунды игры меряет FPS.
func apply_quality() -> void:
	var low := Settings.quality == "low" or (Settings.quality == "auto" and low_quality)
	low_quality = low
	(level.get_node("Sun") as DirectionalLight3D).shadow_enabled = not low
	for l in level.get_node("RoomLights").get_children():
		(l as Light3D).visible = not low
	var env := (level.get_node("Environment") as WorldEnvironment).environment
	env.ambient_light_energy = _env_ambient * (2.4 if low else 1.0)
	get_viewport().scaling_3d_scale = 0.7 if low else 1.0

func _auto_quality(delta: float) -> void:
	if _q_decided or Settings.quality != "auto" or not started or paused:
		return
	var real := delta / maxf(0.01, Engine.time_scale)
	if real <= 0.0:
		return
	_q_samples.append(1.0 / real)
	if _q_samples.size() < 150:          # ~3–5 секунд игры
		return
	_q_decided = true
	var s := _q_samples.slice(30)        # первые кадры — разгон, не считаем
	s.sort()
	var median: float = s[s.size() / 2]
	Settings.qa_mark("auto_quality", {"median_fps": snappedf(median, 0.1), "low": median < 40.0})
	if median < 40.0 and not low_quality:
		low_quality = true
		apply_quality()
		hud.show_toast("Графика упрощена для плавности (Настройки → Графика)", true)

## Телевизор включён, пока сосед на месте «играет в приставку»: экран «раскрывается» полоской и гаснет.
func _update_tv(delta: float) -> void:
	if _tv == null:
		return
	var on := neighbor.activity == "играет в приставку" and not neighbor.is_walking()
	_tv_power = move_toward(_tv_power, 1.0 if on else 0.0, delta * (2.5 if on else 4.0))
	_tv.visible = _tv_power > 0.001
	_tv_mat.set_shader_parameter("power", _tv_power)

func _check_traps() -> void:
	if neighbor.mode not in ["schedule", "detour"] or neighbor.on_ladder or on_stairs(neighbor.position):
		return
	for id in rules.traps.keys():
		var s: Spot3D = spots[id]
		if floor_of(neighbor.position) == s.floor and absf(neighbor.position.x - s.walk.x) < 0.28:
			rules.trap_hit(id)
			return

func _update_detection(delta: float) -> void:
	_noise_cd -= delta
	_caught_cd -= delta
	if _caught_cd > 0.0 or neighbor.mode in ["asleep", "bed", "chase"] or hero.frozen:
		return
	# лоу-кик «тренера» по герою рядом
	if neighbor.is_kicking() and not _ghost and not hero.in_hiding and room_at(hero.position) == room_at(neighbor.position) \
			and floor_of(hero.position) == floor_of(neighbor.position) and absf(hero.position.x - neighbor.position.x) < 0.9:
		_catch("Лоу-кик! Работаем!")
		return
	if neighbor.sees(hero, hour) and not _ghost:
		var rate := 1.0 / (1.7 if hero.sneaking else 1.0)
		if hero.is_noisy():
			rate *= 2.0
		if hero.busy > 0.0:
			rate *= 1.5
		neighbor.suspicion = minf(1.0, neighbor.suspicion + delta * rate)
		if neighbor.suspicion > 0.3 and not _warned and neighbor.mode == "schedule":
			_warned = true
			neighbor.face_x(hero.position.x)
			neighbor.set_face("suspicious")
			neighbor.say(["Э… Кто здесь?", "Чё за шорох?", "Кто тут, блядь?"].pick_random(), 1.5)
			Settings.sfx("alert", 0.5)
		if neighbor.suspicion >= 1.0:
			_catch(["А ну пошёл отсюда!", "Иди сюда, засранец!", "Попался, сучонок!", "Ах ты ж гнида подъездная!",
				"Я тебе щас покажу, вредитель!"].pick_random())
	else:
		neighbor.suspicion = maxf(0.0, neighbor.suspicion - delta * 0.5)
		if neighbor.suspicion <= 0.0 and _warned:
			_warned = false
			if neighbor.mode == "schedule":
				neighbor.set_face(rules.default_face())
				if randf() < 0.5:
					neighbor.say(["Мне показалось?", "Белочка, что ли, пришла?", "Почудилось. Надо меньше пить… А я и не пью!"].pick_random(), 1.6)
		# шаги слышно на том же этаже
		if hero.is_noisy() and _noise_cd <= 0.0 and not _ghost and neighbor.mode == "schedule" and not neighbor.on_ladder \
				and floor_of(hero.position) == floor_of(neighbor.position) and not on_stairs(hero.position) \
				and absf(hero.position.x - neighbor.position.x) < 3.6 and neighbor.view_range(hour) > 0.0:
			_noise_cd = 5.0
			neighbor.face_x(hero.position.x)
			neighbor.set_face("suspicious")
			neighbor.say(["Кто здесь топает?", "Э, кто там шаркает?!"].pick_random(), 1.6)
			neighbor.suspicion = minf(1.0, neighbor.suspicion + 0.25)

func _catch(line: String) -> void:
	_caught_cd = 6.0
	_warned = false
	neighbor.suspicion = 0.0
	neighbor.suspicious_until = hour + 1.0
	_pending = null
	if not _debug_uses.is_empty():
		get_tree().create_timer(5.0).timeout.connect(_debug_next_use)
	hero.get_caught()
	rules.caught()
	if qa_rec:
		qa_rec.note_catch()
	hud.show_toast("Поймал! (%d / 3)" % rules.catches, false)
	neighbor.catch_hero(hero.position, line, func():
		hero.say(["Ай! Да за что?!", "Ой, я за солью!", "Ошибся дверью, бывает!", "Ай-ай, больно же, ветродуйка!"].pick_random(), 1.4)
		var tw := create_tween()
		tw.tween_interval(0.5)
		tw.tween_callback(func():
			Settings.sfx("whoosh", 0.7)
			hero.visible = false)
		tw.tween_interval(0.6)
		tw.tween_callback(func():
			hero.respawn(RESPAWN)
			hero.visible = true
			_caught_cd = 3.0
			if rules.catches >= 3:
				hero.set_face("scared")))

func _on_hero_arrived() -> void:
	if _pending:
		var s := _pending
		_pending = null
		hero.face_x(s.aabb.get_center().x)
		if absf(s.aabb.get_center().x - hero.position.x) < 0.2:
			hero.target_yaw = PI
		rules.hero_use(s)
		if not _debug_uses.is_empty():
			get_tree().create_timer(2.0).timeout.connect(_debug_next_use)

func _debug_next_use() -> void:
	if _debug_uses.is_empty():
		return
	var id: String = _debug_uses.pop_front()
	if id.begins_with("sel:"):
		rules.selected = id.substr(4)
		rules.inventory_changed.emit()
		_debug_next_use()
		return
	_go_spot(spots[id])

func _go_spot(s: Spot3D) -> void:
	if hero.in_portal:
		return
	_pending = s
	if hero.position.distance_to(s.walk) < 0.05 and not hero.in_hiding:
		_on_hero_arrived()
	else:
		hero.go(plan_path(hero.position, s.walk))

func _on_finished(win: bool, reason: String) -> void:
	Engine.time_scale = 1.0
	if win and qa_bot == null:
		Progress.complete(day_n, rules.shame_percent(), rules.score, rules.catches)
	await get_tree().create_timer(0.8).timeout
	Settings.sfx("win" if win else "fail", 0.8)
	hud.show_results(win, reason)

# ---------------------------------------------------------------- ввод
## Экранный прямоугольник места (по 8 углам границ).
func screen_rect(b: AABB) -> Rect2:
	var r := Rect2()
	var first := true
	for i in 8:
		var c := b.get_endpoint(i)
		if cam.is_position_behind(c):
			continue
		var p := cam.unproject_position(c)
		r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
		first = false
	return r

## Зона клика места: сам предмет на экране, но не меньше HIT_MIN пикселей, плюс кружок-метка над ним —
## мелочь (телефон, кружка, геймпад) берётся, если ткнуть рядом, без точного прицеливания.
const HIT_MIN := 86.0
const TOUCH_HIT := 1.5          # на телефоне зоны касания крупнее (палец толще курсора)

func hit_rect(s: Spot3D) -> Rect2:
	var r := screen_rect(s.aabb)
	var m := HIT_MIN * clampf(_home_fov / cam.fov, 1.0, 2.2) * (TOUCH_HIT if Settings.is_touch() else 1.0)
	var sz := Vector2(maxf(r.size.x + 12.0, m), maxf(r.size.y + 12.0, m))
	r = Rect2(r.get_center() - sz * 0.5, sz)
	var mk := cam.unproject_position(s.marker_pos())
	return r.merge(Rect2(mk - Vector2(m, m) * 0.4, Vector2(m, m) * 0.8))

## Нужен ли этому месту предмет, который сейчас в руке (салат — на стол, водка — в холодильник...).
func _wants_selected(s: Spot3D) -> bool:
	if rules.selected == "":
		return false
	if s.id == "table":
		return rules.selected == "salad"
	return s.kind in ["swap", "trap"] and s.item == rules.selected and not s.done

func _spot_at(mp: Vector2) -> Spot3D:
	var k := clampf(_home_fov / cam.fov, 1.0, 2.2)
	# 1) ткнул прямо в кружок-метку — это место, что бы ни стояло рядом
	var best: Spot3D = null
	var best_d := 26.0 * k * (TOUCH_HIT if Settings.is_touch() else 1.0)
	for s in spots.values():
		if s.active:
			var d := mp.distance_to(cam.unproject_position(s.marker_pos()))
			if d < best_d:
				best_d = d
				best = s
	if best:
		return best
	# 2) иначе — по зонам предметов
	var best_score := INF
	for s in spots.values():
		if not s.active:
			continue
		if not hit_rect(s).has_point(mp):
			continue
		# порядок: попал точно в предмет → в расширенную зону мелочи → точно в мебель-укрытие → рядом с ним.
		# Так тумбочка под раковиной берётся кликом по ней (а не соседняя ловушка на полу), а телефон
		# на диване — кликом рядом (а не сам диван). Внутри уровня: меньший / ближайший.
		var r := screen_rect(s.aabb).grow(6)
		var mk := cam.unproject_position(s.marker_pos())
		var exact := r.has_point(mp)
		var tier := (0 if exact else 1) + (2 if s.kind == "hide" else 0)
		var score := tier * 1e7 + (r.get_area() if exact else minf(mp.distance_to(r.get_center()), mp.distance_to(mk)))
		if _wants_selected(s):
			score -= 1e8       # с нужной вещью в руке — сначала туда, куда её можно применить
		if score < best_score:
			best_score = score
			best = s
	return best

func _update_hover() -> void:
	if Settings.is_touch():           # на телефоне наведения нет — подсказка показывается после тапа
		if _hovered:
			_hovered.hovered = false
			_hovered = null
		return
	var mp := get_viewport().get_mouse_position()
	var s: Spot3D = null if hud.has_overlay() else _spot_at(mp)
	if _hovered and _hovered != s:
		_hovered.hovered = false
	_hovered = s
	if s:
		s.hovered = true
		hud.set_tooltip(rules.describe(s), mp)
	elif not hud.has_overlay() and portal_at(mp) != null:
		hud.set_tooltip("Дверь: " + (portal_at(mp)["title"] as String).to_lower(), mp)
	elif rules.selected != "" and not hud.has_overlay():
		hud.set_tooltip("В руке: %s" % rules.item_title(rules.selected), mp)
	else:
		hud.set_tooltip("", Vector2.ZERO)

## Точка на дорожке под курсором: этаж — по высоте попадания в плоскость z = LANE.
func _floor_point(mp: Vector2) -> Variant:
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	if absf(dir.z) < 0.0001:
		return null
	var t := (LANE - from.z) / dir.z
	var p := from + dir * t
	var f := floori((p.y + 0.2) / FH)
	if not f in _floors:
		return null
	var r := floor_range(f)
	return lane_point(clampf(p.x, r.x, r.y), f)

## Касания ловим раньше интерфейса (иначе часть событий забирают его элементы); если палец на кнопке, сумке
## или окне — касание оставляем интерфейсу.
func _input(ev: InputEvent) -> void:
	if not (ev is InputEventScreenTouch or ev is InputEventScreenDrag):
		return
	if ev is InputEventScreenTouch and OS.has_feature("web") and Settings.debug_args().has("qa"):
		Settings.qa_mark("input_touch", {"pressed": ev.pressed, "x": ev.position.x, "y": ev.position.y, "ui": hud.ui_at(ev.position),
			"vs": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]})
	if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed and hud.ui_at(ev.position):
		_touch_on_ui = true
		return
	if _touch_on_ui:
		if ev is InputEventScreenTouch and not (ev as InputEventScreenTouch).pressed:
			_touch_on_ui = false
		return
	_touch_input(ev)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:     # физические клавиши — работают и в русской раскладке
			KEY_ESCAPE:
				if started and not rules.over:
					_set_paused(not paused)
			KEY_SPACE:
				if started and not rules.over and not hud.has_overlay():
					paused = not paused
					get_tree().paused = paused
			KEY_SHIFT:
				hero.toggle_sneak()
			KEY_F:
				Engine.time_scale = 1.0 if Engine.time_scale > 1.0 else 3.0
			KEY_C:
				zoomed = true
				center_on_hero()
			KEY_Z:
				zoomed = not zoomed
				_manual_cam = false
			KEY_TAB:
				hud.toggle_tasks()
		return
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	if ev.device == InputEvent.DEVICE_ID_EMULATION:   # клик, «эмулированный» из касания, — касания обрабатываем сами
		return
	match ev.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if not zoomed:
				_manual_cam = false
			zoomed = true
		MOUSE_BUTTON_WHEEL_DOWN:
			zoomed = false
		MOUSE_BUTTON_MIDDLE:
			zoomed = true
			center_on_hero()
		MOUSE_BUTTON_RIGHT:
			if started and not paused:
				hero.toggle_sneak()
		MOUSE_BUTTON_LEFT:
			if not started or rules.over or paused or hero.frozen:
				return
			_click(ev.position)

## Клик или тап: место под точкой — идти и сделать, иначе — идти по полу.
func _click(pos: Vector2) -> void:
	var s := _spot_at(pos)
	if s:
		_manual_cam = false
		if Settings.is_touch():
			hud.flash_tooltip(rules.describe(s), pos)
		_go_spot(s)
		return
	if hero.in_portal:
		return
	var door: Variant = portal_at(pos)      # дверь-переход — пройти на другой этаж
	if door != null:
		_manual_cam = false
		_pending = null
		if Settings.is_touch():
			hud.flash_tooltip("Дверь: " + door["title"].to_lower(), pos)
		hero.go(plan_path(hero.position, door["to"]))
		return
	var p: Variant = _floor_point(pos)
	if p != null:
		_manual_cam = false
		_pending = null
		hero.go(plan_path(hero.position, p))

## Касания: тап (отпустил, почти не сдвинув) — как клик; один палец тащит — обзор камерой; два пальца — щипок.
func _touch_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if OS.has_feature("web") and Settings.debug_args().has("qa"):
			Settings.qa_mark("touch_ev", {"pressed": t.pressed, "index": t.index, "n": _touches.size(), "dragged": _dragged,
				"dt": Time.get_ticks_msec() - _tap_t, "canceled": t.canceled})
		if t.pressed:
			if t.index == 0:          # первый палец — значит, других на экране нет (сброс «зависших» касаний)
				_touches.clear()
			_touches[t.index] = t.position
			if _touches.size() == 1:
				_tap_from = t.position
				_tap_t = Time.get_ticks_msec()
				_dragged = false
			elif _touches.size() == 2:
				var v: Array = _touches.values()
				_pinch0 = (v[0] as Vector2).distance_to(v[1])
				_dragged = true
		else:
			_touches.erase(t.index)
			if _touches.is_empty() and not _dragged and Time.get_ticks_msec() - _tap_t < 1000:
				if started and not rules.over and not paused and not hero.frozen:
					if OS.has_feature("web"):
						Settings.qa_mark("tap", {"x": t.position.x, "y": t.position.y})
					_click(t.position)
		return
	var d := ev as InputEventScreenDrag
	_touches[d.index] = d.position
	if _touches.size() >= 2:
		var v: Array = _touches.values()
		var dist := (v[0] as Vector2).distance_to(v[1])
		if _pinch0 > 0.0 and dist > _pinch0 * 1.2:
			zoomed = true
			_pinch0 = dist
		elif _pinch0 > 0.0 and dist < _pinch0 * 0.83:
			zoomed = false
			_manual_cam = false
			_pinch0 = dist
		return
	if d.position.distance_to(_tap_from) > 18.0:
		_dragged = true
	if _dragged and zoomed:
		# сдвиг обзора: пиксели экрана → метры на уровне квартиры
		var vs := get_viewport().get_visible_rect().size
		var m_per_px := 2.0 * (cam.position.z - LANE) * tan(deg_to_rad(cam.fov * 0.5)) / vs.y
		if not _manual_cam:
			_pan = Vector2(_cam_x, _cam_y)
		_manual_cam = true
		_pan += Vector2(-d.relative.x, d.relative.y) * m_per_px

func _qa_hero_tick() -> void:
	Settings.qa_mark("hero", {"x": snappedf(hero.position.x, 0.01), "floor": floor_of(hero.position), "zoomed": zoomed,
		"manual_cam": _manual_cam, "cam_x": snappedf(_cam_x, 0.01)})
	get_tree().create_timer(0.5).timeout.connect(_qa_hero_tick)

func _on_touch_action(what: String) -> void:
	match what:
		"sneak":
			hero.toggle_sneak()
			hud.set_sneak_button(hero.sneaking)
		"tasks":
			hud.toggle_tasks()
		"camera":
			zoomed = not zoomed
			_manual_cam = false
		"center":
			zoomed = true
			center_on_hero()
		"pause":
			if started and not rules.over:
				_set_paused(not paused)
		"fullscreen":
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _set_paused(on: bool) -> void:
	paused = on
	get_tree().paused = on
	if on:
		hud.show_pause()
	else:
		hud.close_overlay()

# ---------------------------------------------------------------- камера
func _update_camera(instant: bool, delta := 0.016) -> void:
	var fov := _home_fov
	var target := _home.origin
	var who: Actor = (neighbor as Actor) if (rules and rules.over and rules.drunk >= 100.0 and not finale_hero) or _focus_n else (hero as Actor)
	var close_up := who == neighbor or finale_hero
	if zoomed and not close_up:
		_close_cam(instant, delta)
		target = Vector3(_cam_x, _cam_y, _home.origin.z)
		fov = _fov_at(CLOSE_FOV)
	elif close_up:
		fov = _fov_at(9.5 if not _focus_n else 5.0)
		var f := floor_of(who.position) if not on_stairs(who.position) else (1 if who.position.y > F2 * 0.5 else 0)
		var y := floor_y(f) + (1.05 if who == hero else (1.0 if not _focus_n else 1.35))
		var x := clampf(who.position.x, 2.4, house_w - 2.4)
		_cam_x = x if instant else lerpf(_cam_x, x, minf(1.0, delta * 4.0))
		_cam_y = y if instant else lerpf(_cam_y, y, minf(1.0, delta * 4.0))
		target = Vector3(_cam_x, _cam_y, _home.origin.z)
	else:
		_cam_x = lerpf(_cam_x, _home.origin.x, minf(1.0, delta * 4.0))
		_cam_y = lerpf(_cam_y, _home.origin.y, minf(1.0, delta * 4.0))
	var k := 1.0 if instant else minf(1.0, delta * 5.0)
	cam.fov = lerpf(cam.fov, fov, k)
	var pos := cam.position.lerp(target, k)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.5)
		pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.12
	cam.transform = Transform3D(_home.basis, pos)

## Крупная камера: следует за героем; мышь у края экрана (или стрелки / WASD) сдвигает обзор —
## посмотреть, где сосед. Как только герой пошёл или нажата C / средняя кнопка — снова за героем.
const CLOSE_FOV := 13.0
const EDGE := 36.0             # ширина «горячей» полосы у края экрана, px
const PAN_SPEED := 7.0         # м/с

func _close_cam(instant: bool, delta: float) -> void:
	var f := floor_of(hero.position) if not on_stairs(hero.position) else (1 if hero.position.y > F2 * 0.5 else 0)
	var hero_pt := Vector2(clampf(hero.position.x, 2.6, house_w - 2.6), floor_y(f) + 1.3)
	var dir := Vector2.ZERO
	if started and not paused and not hud.has_overlay():
		var vs := get_viewport().get_visible_rect().size
		var mp := get_viewport().get_mouse_position()
		if not Settings.is_touch() and Rect2(Vector2.ZERO, vs).has_point(mp) and DisplayServer.window_is_focused():
			dir.x = -1.0 if mp.x < EDGE else (1.0 if mp.x > vs.x - EDGE else 0.0)
			dir.y = 1.0 if mp.y < EDGE else (-1.0 if mp.y > vs.y - EDGE else 0.0)
		if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
			dir.x = -1.0
		if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
			dir.x = 1.0
		if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
			dir.y = 1.0
		if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
			dir.y = -1.0
	if dir != Vector2.ZERO:
		if not _manual_cam:
			_pan = Vector2(_cam_x, _cam_y)
		_manual_cam = true
		_pan += dir * PAN_SPEED * delta
	if not _manual_cam:
		_pan = hero_pt
	_pan.x = clampf(_pan.x, 2.6, house_w - 2.6)
	_pan.y = clampf(_pan.y, floor_y(_floors[0]) + 1.3, floor_y(_floors[-1]) + 1.3)
	var kf := 1.0 if instant else minf(1.0, delta * (9.0 if _manual_cam else 4.0))
	_cam_x = lerpf(_cam_x, _pan.x, kf)
	_cam_y = lerpf(_cam_y, _pan.y, kf)

## Угол обзора для приближения: подобраны под дом среды (камера в 20.5 м); в доме больше камера дальше —
## угол уже, чтобы крупный план оставался таким же крупным.
func _fov_at(base: float) -> float:
	var d := _home.origin.z + 1.5
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base * 0.5)) * _ref_dist / maxf(1.0, d)))

func center_on_hero() -> void:
	_manual_cam = false

func _args() -> Dictionary:
	var out := Settings.debug_args()
	if out.has("qa"):              # автотест в браузере: без вступления
		out["autostart"] = "true"
	return out
