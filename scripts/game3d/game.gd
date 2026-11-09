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
const HERO_START := Vector3(6.4, 0.0, -1.0)
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

func _ready() -> void:
	var args := _args()
	time_scale = float(args.get("timescale", "1"))
	hour = float(args.get("start", str(START_HOUR)))
	zoomed = args.has("zoom")

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
	hero.position = HERO_START
	hero.rotation.y = PI / 2
	hero.target_yaw = PI / 2
	hero.arrived.connect(_on_hero_arrived)

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
	Settings.music("level_loop")

	_apply_debug(args)
	if hour > 8.0 and neighbor.mode == "bed":   # старт с середины дня — сосед там, где был по расписанию
		neighbor.mode = "schedule"
		var prev: Array = Neighbor3D.SCHEDULE[1]
		for e in Neighbor3D.SCHEDULE:
			if e[0] < hour - 0.01:
				prev = e
		neighbor.position = lane_point(prev[1], prev[2])
		neighbor.release()
	_update_camera(true)

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
		var last := ["", ""]
		get_tree().process_frame.connect(func():
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
	_props["soap_dish"] = _put("soap_dish", "soap_dish", Vector3(4.55, tub.end.y, tub.end.z - 0.12))
	_props["peeltrap"] = _put("peel", "banana_peel", Vector3(6.55, F1 + 0.01, LANE + 0.1), 30, 1.3)
	_props["peeltrap"].visible = false
	_props["soaptrap"] = _put("soap_floor", "soap_dish", Vector3(4.6, F2 + 0.01, LANE + 0.1), 20)
	_props["soaptrap"].visible = false

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
		else:   # ловушка на полу — область у пола
			s.aabb = AABB(Vector3(d[3] - 0.35, floor_y(s.floor), LANE - 0.4), Vector3(0.7, 0.25, 0.8))
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

func _check_traps() -> void:
	if not neighbor.is_walking() or neighbor.mode in ["react", "chase", "asleep"]:
		return
	for id in rules.traps.keys():
		var s: Spot3D = spots[id]
		var x := s.walk.x
		if floor_of(neighbor.position) == s.floor and not on_stairs(neighbor.position) \
				and (_last_nx - x) * (neighbor.position.x - x) <= 0.0 and absf(neighbor.position.x - x) < 0.3:
			rules.trap_hit(id)
			return

func _update_detection(delta: float) -> void:
	_noise_cd -= delta
	_caught_cd -= delta
	if _caught_cd > 0.0 or neighbor.mode in ["asleep", "bed", "chase"] or hero.frozen:
		return
	# лоу-кик «тренера» по герою рядом
	if neighbor.is_kicking() and not hero.in_hiding and room_at(hero.position) == room_at(neighbor.position) \
			and floor_of(hero.position) == floor_of(neighbor.position) and absf(hero.position.x - neighbor.position.x) < 0.9:
		_catch("Лоу-кик! Работаем!")
		return
	if neighbor.sees(hero, hour):
		var rate := 1.0 / 1.1
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
		if hero.is_noisy() and _noise_cd <= 0.0 and neighbor.mode == "schedule" and not neighbor.on_ladder \
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
	hero.get_caught()
	rules.caught()
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
			hero.respawn(HERO_START)
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

func _spot_at(mp: Vector2) -> Spot3D:
	var best: Spot3D = null
	var best_area := INF
	for s in spots.values():
		if not s.active:
			continue
		var r := screen_rect(s.aabb).grow(6)
		if r.has_point(mp) and r.get_area() < best_area:
			best_area = r.get_area()
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
		match ev.keycode:
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
		return
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	match ev.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			zoomed = true
		MOUSE_BUTTON_WHEEL_DOWN:
			zoomed = false
		MOUSE_BUTTON_RIGHT:
			if started and not paused:
				hero.toggle_sneak()
		MOUSE_BUTTON_LEFT:
			if not started or rules.over or paused or hero.frozen:
				return
			var s := _spot_at(ev.position)
			if s:
				_go_spot(s)
				return
			var p: Variant = _floor_point(ev.position)
			if p != null:
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
	var who: Actor = neighbor if rules and rules.over and rules.drunk >= 100.0 else hero
	if zoomed or who == neighbor:
		fov = 12.5 if who == hero else 9.5
		var f := floor_of(who.position) if not on_stairs(who.position) else (1 if who.position.y > F2 * 0.5 else 0)
		var y := floor_y(f) + (1.3 if who == hero else 1.0)
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

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out
