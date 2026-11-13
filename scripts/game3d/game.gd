class_name Game3D
extends Node
## Уровень 1 в 3D: квартира в разрезе (scenes/level1_3d.tscn), герой, сосед, правила, интерфейс.
##
##   2-й этаж: [лестница][ванная  ][спальня ][балкон ][лестница]
##   1-й этаж: [лестница][прихожая][кухня   ][зал    ][лестница]
## Оси: X — вдоль квартиры, Y — вверх, Z — к зрителю. Ходят по «дорожке» z = LANE.
##
## Отладочные аргументы (после --):
##   --autostart       без вступления        --start=H        начать с часа H (например 11.2)
##   --timescale=N     игровое время в N раз  --speed=N        Engine.time_scale
##   --drunk=N         начальное опьянение    --give=a,b       предметы в сумку
##   --swap=a,b        считать подменёнными   --take=a,b       считать унесёнными
##   --trap=a,b        ловушки на полу        --salad          салат на столе
##   --hero-at=X,F     герой в точке X на этаже F (0/1)
##   --zoom            начать с приближения   --use=a,sel:item,b  герой по очереди использует точки
## Автотесты (scripts/debug/, обёртки в tools/qa/):
##   --bot=careful|normal|reckless   бот сам проходит уровень
##   --report=путь.json  отчёт (события, задания, поимки, наложения голосов, FPS)
##   --quit-on-end       закрыть после итогов   --max-real=сек   страховка по реальному времени
##   --perf              печатать FPS раз в 5 с      --quality=low|high|auto  графика

const LEVEL := "res://scenes/level1_3d.tscn"
const PROPS := "res://assets/models/props/"
const F1 := 0.0
const F2 := 3.05
const LANE := -1.0
const ROOM_MIN := 3.25
const ROOM_MAX := 13.75
const START_HOUR := 7.5
const END_HOUR := 20.0
const SEC_PER_HOUR := 50.0
const HERO_START := Vector3(5.1, 0.0, -1.0)
const RESPAWN := Vector3(0.38, F2 * 0.5, -1.0)   # после «люлей» — на площадку лестницы (там сосед не видит)
const MATTRESS_H := 0.5       # высота матраса над полом
const SALAD_SPOT := Vector3(8.7, 0.0, -2.72)   # где сосед встаёт за столом в финале
const ROOM_NAMES := {"bathroom": "Ванная", "bedroom": "Спальня", "balcony": "Балкон",
	"hallway": "Прихожая", "kitchen": "Кухня", "living": "Зал", "stairs": "Лестница"}

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
var _tv: MeshInstance3D
var _tv_mat: ShaderMaterial
var _tv_power := 0.0       # финал: камера крупно на танцующем герое
var _focus_n := false
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
	zoomed = args.has("zoom") or Settings.camera_close

	level = (load(LEVEL) as PackedScene).instantiate() as Node3D
	level.set_script(null)                 # в сцене — скрипт просмотрщика, в игре он не нужен
	add_child(level)
	furn = level.get_node("Furniture") as Node3D
	cam = level.get_node("Camera") as Camera3D
	_home = cam.transform
	_home_fov = cam.fov
	# ненужное в игре: персонажи просмотрщика
	level.get_node("Characters").queue_free()
	_add_props()

	neighbor = Neighbor3D.new()
	neighbor.name = "Neighbor"
	neighbor.game = self
	level.add_child(neighbor)
	neighbor.setup("res://assets/models/characters/neighbor.glb", "neighbor")
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
		get_tree().create_timer(0.5).timeout.connect(func(): rules.add_drunk(100.0))
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
	if args.has("speed"):
		Engine.time_scale = float(args["speed"])
	if args.has("autostart"):
		started = true
	else:
		hud.show_intro()

# ---------------------------------------------------------------- геометрия
func floor_y(f: int) -> float:
	return F2 if f == 1 else F1

func floor_of(p: Vector3) -> int:
	return 1 if p.y > 1.6 else 0

func lane_point(x: float, f: int) -> Vector3:
	return Vector3(x, floor_y(f), LANE)

func on_stairs(p: Vector3) -> bool:
	return p.x < 3.05 or p.x > 13.95

func room_at(p: Vector3) -> String:
	if on_stairs(p):
		return "stairs"
	if floor_of(p) == 0:
		return "hallway" if p.x < 7.0 else ("kitchen" if p.x < 10.4 else "living")
	return "bathroom" if p.x < 6.4 else ("bedroom" if p.x < 10.4 else "balcony")

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

## Маршрут: на другом этаже — через ближайшую лестницу. Сходит с дорожки и возвращается на неё сам.
func plan_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var tf := floor_of(to)
	var to_lane := Vector3(to.x, to.y, LANE)
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
		if tf == 1:
			for k in range(best + 1, poly.size()):
				out.append(poly[k])
		else:
			for k in range(best, -1, -1):
				out.append(poly[k])
	else:
		if absf(from.z - LANE) > 0.05:
			out.append(Vector3(from.x, from.y, LANE))
		var ff := floor_of(from)
		if ff != tf:
			var best_len := INF
			var best_poly: Array[Vector3] = []
			for s in 2:
				var poly := stair_poly(s)
				if ff == 1:
					poly.reverse()
				var length := absf(from.x - poly[0].x) + absf(poly[-1].x - to.x)
				if length < best_len:
					best_len = length
					best_poly = poly
			out.append_array(best_poly)
	if absf(to.z - LANE) > 0.05:
		out.append(to_lane)
	out.append(to)
	return out

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
	# экран телевизора: включается, пока сосед играет в приставку
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

func _build_spots() -> void:
	for d in Rules3D.SPOTS:
		var s := Spot3D.new()
		s.id = d[0]
		s.kind = d[1]
		s.title = d[5]
		s.item = d[6]
		s.floor = d[4]
		s.walk = lane_point(d[3], s.floor)
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
			neighbor.say("Э… Кто здесь?", 1.5)
			Settings.sfx("alert", 0.5)
		if neighbor.suspicion >= 1.0:
			_catch(["А ну пошёл отсюда!", "Иди сюда, засранец!"].pick_random())
	else:
		neighbor.suspicion = maxf(0.0, neighbor.suspicion - delta * 0.5)
		if neighbor.suspicion <= 0.0 and _warned:
			_warned = false
			if neighbor.mode == "schedule":
				neighbor.set_face(rules.default_face())
				if randf() < 0.5:
					neighbor.say("Мне показалось?", 1.6)
		# шаги слышно на том же этаже
		if hero.is_noisy() and _noise_cd <= 0.0 and not _ghost and neighbor.mode == "schedule" and not neighbor.on_ladder \
				and floor_of(hero.position) == floor_of(neighbor.position) and not on_stairs(hero.position) \
				and absf(hero.position.x - neighbor.position.x) < 3.6 and neighbor.view_range(hour) > 0.0:
			_noise_cd = 5.0
			neighbor.face_x(hero.position.x)
			neighbor.set_face("suspicious")
			neighbor.say("Кто здесь топает?", 1.6)
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
		hero.say("Ай! Да за что?!", 1.4)
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
	_pending = s
	if hero.position.distance_to(s.walk) < 0.05 and not hero.in_hiding:
		_on_hero_arrived()
	else:
		hero.go(plan_path(hero.position, s.walk))

func _on_finished(win: bool, reason: String) -> void:
	Engine.time_scale = 1.0
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

func hit_rect(s: Spot3D) -> Rect2:
	var r := screen_rect(s.aabb)
	var m := HIT_MIN * clampf(_home_fov / cam.fov, 1.0, 2.2)
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
	var best_d := 26.0 * k
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
	var mp := get_viewport().get_mouse_position()
	var s: Spot3D = null if hud.has_overlay() else _spot_at(mp)
	if _hovered and _hovered != s:
		_hovered.hovered = false
	_hovered = s
	if s:
		s.hovered = true
		hud.set_tooltip(rules.describe(s), mp)
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
	if p.y < -0.5 or p.y > F2 + 2.9:
		return null
	var f := 1 if p.y > F2 - 0.2 else 0
	return lane_point(clampf(p.x, ROOM_MIN, ROOM_MAX), f)

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
			var s := _spot_at(ev.position)
			if s:
				_manual_cam = false
				_go_spot(s)
				return
			var p: Variant = _floor_point(ev.position)
			if p != null:
				_manual_cam = false
				_pending = null
				hero.go(plan_path(hero.position, p))

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
		fov = CLOSE_FOV
	elif close_up:
		fov = 9.5 if not _focus_n else 5.0
		var f := floor_of(who.position) if not on_stairs(who.position) else (1 if who.position.y > F2 * 0.5 else 0)
		var y := floor_y(f) + (1.05 if who == hero else (1.0 if not _focus_n else 1.35))
		var x := clampf(who.position.x, 2.4, 14.6)
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
	var hero_pt := Vector2(clampf(hero.position.x, 2.6, 14.4), floor_y(f) + 1.3)
	var dir := Vector2.ZERO
	if started and not paused and not hud.has_overlay():
		var vs := get_viewport().get_visible_rect().size
		var mp := get_viewport().get_mouse_position()
		if Rect2(Vector2.ZERO, vs).has_point(mp) and DisplayServer.window_is_focused():
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
	_pan.x = clampf(_pan.x, 2.6, 14.4)
	_pan.y = clampf(_pan.y, F1 + 1.3, F2 + 1.3)
	var kf := 1.0 if instant else minf(1.0, delta * (9.0 if _manual_cam else 4.0))
	_cam_x = lerpf(_cam_x, _pan.x, kf)
	_cam_y = lerpf(_cam_y, _pan.y, kf)

func center_on_hero() -> void:
	_manual_cam = false

func _args() -> Dictionary:
	var out := Settings.debug_args()
	if out.has("qa"):              # автотест в браузере: без вступления
		out["autostart"] = "true"
	return out
