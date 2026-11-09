class_name Neighbor3D
extends Actor
## Сосед: спит на кровати, потом живёт по расписанию, пользуется вещами (через правила уровня),
## бурно реагирует на пакости, пьянеет (лицо, походка, обзор), оглядывается и ловит героя.

signal finale_done

## Распорядок дня — цепочка дел, как в классике жанра: пришёл, сколько-то секунд занят делом, пошёл дальше.
## Дела чередуют комнаты и этажи (зал — только короткими заходами), каждый предмет он трогает за день
## несколько раз — есть окна, чтобы набрать заначки, и подставы успевают сработать. Когда список кончился —
## по кругу с LOOP_FROM. Куда пойдёт дальше, видно заранее: облачко-мысль над головой и метка на полу.
## [x, этаж, что делает, клип, использует, куда смотрит: back | front | left | right | tv, секунд на месте, z (необяз.)]
const PLAN := [
	[8.4,   1, "спит",                  "sleep",      "",          "front", 0],
	[9.35,  1, "проснулся",             "idle",       "wake",      "front", 6],
	[4.92,  1, "чистит зубы",           "work",       "mouthwash", "back",  10],
	[8.3,   0, "пьёт кофе",             "idle",       "coffee",    "back",  10],
	[9.85,  1, "шпаклюет стену",        "work",       "",          "back",  14, -3.25],
	[9.45,  0, "пьёт минералку",        "idle",       "fridge",    "back",  8],
	[12.75, 0, "играет в приставку",    "phone",      "gamepad",   "tv",    14],
	[12.0,  1, "дышит воздухом",        "idle",       "balcony",   "back",  10],
	[12.0,  0, "меняет лампочку",       "bulb",       "ladder",    "front", 3],
	[4.92,  1, "умывается",             "work",       "mouthwash", "back",  10],
	[13.05, 0, "пьёт газировку",        "idle",       "soda",      "back",  7],
	[9.85,  1, "шпаклюет стену",        "work",       "",          "back",  12, -3.25],
	[8.3,   0, "пьёт кофе",             "idle",       "coffee",    "back",  9],
	[11.1,  0, "сидит в чат-рулетке",   "phone",      "phone",     "front", 14],
	[5.45,  0, "собирается за хлебом",  "idle",       "jacket",    "back",  8],
	[4.62,  0, "ищет ключи",            "suspicious", "keys",      "back",  8],
	[12.0,  1, "проверяет заначку",     "idle",       "balcony",   "back",  9],
	[9.45,  0, "пьёт минералку",        "idle",       "fridge",    "back",  8],
	[4.92,  1, "умывается",             "work",       "mouthwash", "back",  9],
	[12.75, 0, "играет в приставку",    "phone",      "gamepad",   "tv",    12],
	[9.85,  1, "шпаклюет стену",        "work",       "",          "back",  12, -3.25],
	[13.05, 0, "пьёт газировку",        "idle",       "soda",      "back",  7],
	[9.45,  0, "ужинает",               "idle",       "fridge",    "back",  10],
]
## Мысль перед делом: activity -> что он думает (в облачке, вместе с комнатой).
const THOUGHTS := {"чистит зубы": "почистить зубы", "умывается": "умыться", "пьёт кофе": "кофейку",
	"шпаклюет стену": "пошпаклевать стену", "пьёт минералку": "минералочки", "играет в приставку": "в приставку",
	"дышит воздухом": "подышать воздухом", "меняет лампочку": "лампочку поменять", "пьёт газировку": "газировочки",
	"сидит в чат-рулетке": "в чат-рулетку", "собирается за хлебом": "за хлебом сходить", "ищет ключи": "где ключи?",
	"проверяет заначку": "проверить заначку", "ужинает": "поужинать"}
const LOOP_FROM := 3
const WAKE_HOUR := 8.0
## Что у него в руке, когда пользуется вещью: id -> [модель обычная, модель после подмены]
const HAND := {
	"mouthwash": ["mouthwash", "antifreeze"], "coffee": ["coffee_mug", "coffee_mug"],
	"fridge": ["mineral_water", "vodka"], "detour": ["mineral_water", "vodka"], "soda": ["soda_bottle", "beer_can"],
	"jacket": ["chekushka", "chekushka"], "gamepad": ["gamepad", "gamepad"], "phone": ["smartphone", "smartphone"],
	"ladder": ["light_bulb", "light_bulb_burnt"],
}
const USE_DELAY := 1.2
const SOBER_RANGE := 3.0
const GRUMBLE := ["Бу-бу-бу… никто не ценит…", "Эх, жизнь…", "Хм-м… Ну и ладно."]

var game: Node                 # Game3D
var rules: Rules3D
var current := -1
var activity := ""
var mode := "bed"              # bed | schedule | detour | react | chase | asleep
var suspicion := 0.0
var suspicious_until := 0.0
var on_ladder := false
var thought := ""             # облачко-мысль: куда и зачем пойдёт (рисует Overlay3D)
var goal := Vector3.INF        # куда идёт — метка на полу
var _use_timer := -1.0
var _use_id := ""
var _seq: Array = []
var _seq_t := 0.0
var _seq_next := Callable()
var _detour := {}
var _look_t := 6.0
var _look_back := 0.0
var _kick_t := 6.0
var _hic_t := 12.0
var _grumble_t := 25.0
var _snore_t := 0.5
var _activity_yaw := 0.0
var _busy_wake := false
var _used_entry := -1          # пункт распорядка, где предмет уже использован (не повторять после реакции)
var _stay_entry := -1          # пункт, для которого идёт отсчёт времени на месте
var _stay_left := 0.0
var _here := false             # дошёл до места текущего дела
var _hand: Node3D              # предмет в руке
var _hand_name := ""
var _hand_cache := {}

func _init() -> void:
	speed = 1.05
	head_h = 2.0
	step_sfx = "step"
	step_vol = 0.35

# ---------------------------------------------------------------- сон на кровати (начало дня)
func lie_on_bed(pos: Vector3, yaw: float) -> void:
	mode = "bed"
	activity = "спит"
	position = pos
	rotation.y = yaw
	target_yaw = yaw
	act("sleep", -1.0, 0.0)
	set_face("sleep")

func _bed_tick(delta: float) -> void:
	_snore_t -= delta
	if _snore_t <= 0.0:
		_snore_t = 3.2
		Settings.sfx("snore", 0.55)
		bubble = "Хр-р-р…  z Z z"
		bubble_time = 2.4

## Встать с кровати и сойти на пол рядом.
func _get_off_bed(then: Callable) -> void:
	_busy_wake = true
	act("get_up", -1.0, 0.3)
	set_face("tipsy" if rules.drunk > 0 else "normal")
	bubble = ""
	var tw := create_tween()
	tw.tween_interval(1.0)
	var floor_p: Vector3 = game.lane_point(9.35, 1)
	tw.tween_property(self, "position", floor_p, 0.6).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		_busy_wake = false
		release()
		then.call())

func wake_up() -> void:
	act("oath", 3.4)
	set_face("happy")
	say("Всё, сегодня больше не пью!", 3.0)
	get_tree().create_timer(3.6, false).timeout.connect(func():
		if mode == "schedule" and current == 1:
			set_face("normal")
			say("Не, вообще к пиву не тянет.", 2.6))

# ---------------------------------------------------------------- расписание
func update_schedule(hour: float, delta: float) -> void:
	if mode == "asleep" or mode == "chase" or _busy_wake:
		return
	if mode == "bed":
		_bed_tick(delta)
		if hour >= WAKE_HOUR:
			current = 1
			mode = "schedule"
			_get_off_bed(_go_to_current)
		return
	if mode == "react":
		_seq_t -= delta
		if _seq_t <= 0.0:
			_next_step()
		return
	if _use_timer > 0.0:
		_use_timer -= delta
		if _use_timer <= 0.0:
			var id := _use_id
			_use_id = ""
			if mode == "detour":
				_finish_detour()
			else:
				_used_entry = current
				rules.neighbor_use(id)
	_drunk_behaviour(delta)
	if mode == "detour" or is_walking() or not _here:
		return
	_stay_left -= delta
	if _stay_left < 5.0 and thought == "" and _use_timer <= 0.0 and bubble == "":
		_think(_next_index())
	if _stay_left <= 0.0 and _use_timer <= 0.0:
		next_task()

## Следующее дело по распорядку (после последнего — по кругу).
func next_task() -> void:
	current = _next_index()
	_used_entry = -1
	_go_to_current()

## Старт с середины дня (отладка): пропустить дела, которые к этому часу уже прошли бы.
func skip_to(hour: float) -> void:
	var t: float = (hour - WAKE_HOUR) * game.SEC_PER_HOUR
	current = 1
	while t > 0.0:
		t -= float(PLAN[current][6]) + 7.0
		if t > 0.0:
			current = current + 1 if current + 1 < PLAN.size() else LOOP_FROM
	mode = "schedule"
	position = game.lane_point(PLAN[current][0], PLAN[current][1])
	release()
	_go_to_current()

func _next_index() -> int:
	return current + 1 if current + 1 < PLAN.size() else LOOP_FROM

func _plan_point(i: int) -> Vector3:
	var e: Array = PLAN[i]
	var p: Vector3 = game.lane_point(e[0], e[1])
	if e.size() > 7:
		p.z = e[7]
	return p

## Подумать о деле i: облачко «Комната: зачем» и метка на полу там, куда пойдёт.
func _think(i: int) -> void:
	var e: Array = PLAN[i]
	if not THOUGHTS.has(e[2]):
		_clear_thought()
		return
	var p := _plan_point(i)
	thought = "%s: %s" % [game.ROOM_NAMES[game.room_at(p)], THOUGHTS.get(e[2], e[2])]
	goal = Vector3(p.x, p.y, game.LANE)

func _clear_thought() -> void:
	thought = ""
	goal = Vector3.INF

func _go_to_current() -> void:
	var e: Array = PLAN[current]
	activity = "идёт: " + e[2]
	_here = false
	release()
	hold_item("")
	_to_floor()
	_think(current)
	var target: Vector3 = _plan_point(current)
	if position.distance_to(target) < 0.05:
		_on_arrived()
	else:
		walk_path(game.plan_path(position, target))

func _resume() -> void:
	if current >= 0:
		_go_to_current()

func _ready() -> void:
	arrived.connect(_on_arrived)

func _on_arrived() -> void:
	if mode == "chase":
		return
	if mode == "detour":
		activity = _detour.get("title", "")
		_clear_thought()
		face_dir(Vector3(0, 0, -1))
		_use_id = "detour"
		_use_timer = USE_DELAY
		return
	if current < 0 or mode != "schedule":
		return
	var e: Array = PLAN[current]
	_here = true
	_clear_thought()
	if _stay_entry != current:
		_stay_entry = current
		_stay_left = float(e[6])
	activity = e[2]
	_face_activity(e[5])
	set_face(rules.default_face())
	if e[3] != "idle":
		act(e[3])
	if e[2] == "шпаклюет стену" and randf() < 0.6:
		say("Так-с… шпаклёвочка…", 2.2)
	if e[4] in ["gamepad", "phone"] and not rules.taken.has(e[4]):
		hold_item(HAND[e[4]][0])
	if e[4] != "" and _used_entry != current:
		_use_id = e[4]
		_use_timer = USE_DELAY

## Предмет в правой руке (модель из assets/models/props), "" — убрать. Держит за кость RightHandGrip
## (бутылки, кружка, лампочка — ось кости к горлышку) или RightHandPhone (телефон, геймпад).
func hold_item(n: String) -> void:
	if n == _hand_name:
		return
	_hand_name = n
	if _hand:
		_hand.visible = false
	_hand = null
	if n == "":
		return
	if not _hand_cache.has(n):
		var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var phone := n in ["smartphone", "gamepad"]
		var att := BoneAttachment3D.new()
		att.bone_name = "RightHandPhone" if phone else "RightHandGrip"
		sk.add_child(att)
		var inst := (load(game.PROPS + n + ".glb") as PackedScene).instantiate() as Node3D
		att.add_child(inst)
		inst.scale = Vector3.ONE * (1.6 if phone else 1.25)   # по-мультяшному крупнее, чтобы читалось издалека
		var b: AABB = game.local_bounds(inst)
		if phone:
			# экраном к лицу: длинная сторона — вдоль кости (Y), толщина — по Z
			var sz := b.size
			if sz.y < sz.x and sz.y < sz.z:      # лежит плашмя (тонкий по Y) — поставить «на ребро»
				inst.rotation_degrees.x = 90.0
				if sz.x > sz.z:
					inst.rotation_degrees.z = 90.0
			b = game.local_bounds_xf(inst)
		inst.position -= b.get_center()        # центр предмета — в точке хвата
		_hand_cache[n] = att
	_hand = _hand_cache[n]
	_hand.visible = true

## Модель предмета для «использует» с учётом подмены.
func hand_for(use_id: String) -> String:
	if not HAND.has(use_id):
		return ""
	var swapped: bool = rules.swapped.has("fridge" if use_id == "detour" else use_id)
	return HAND[use_id][1 if swapped else 0]

func _face_activity(where: String) -> void:
	_activity_yaw = {"back": PI, "tv": PI * 0.72, "front": 0.0, "left": -PI / 2, "right": PI / 2}[where]
	target_yaw = _activity_yaw

# ---------------------------------------------------------------- отлучки и реакции
func detour(x: float, fl: int, title: String, use_id: String) -> void:
	mode = "detour"
	_use_timer = -1.0
	_detour = {"title": title, "use": use_id}
	activity = "идёт: " + title
	release()
	_to_floor()
	var target: Vector3 = game.lane_point(x, fl)
	thought = "%s: %s" % [game.ROOM_NAMES[game.room_at(target)], _detour["title"].trim_prefix("идёт ")]
	goal = target
	if position.distance_to(target) < 0.05:
		_on_arrived()
	else:
		walk_path(game.plan_path(position, target))

func _finish_detour() -> void:
	var id: String = _detour.get("use", "")
	mode = "schedule"
	_detour = {}
	rules.neighbor_use(id)
	if mode == "schedule":
		_resume()

## Цепочка реакции: шаги {face, clip, t, line, sfx, shake, fall, down}. Потом next или возврат к делам.
func react_seq(steps: Array, next := Callable()) -> void:
	mode = "react"
	stop()
	_clear_thought()
	_use_timer = -1.0
	_seq = steps.duplicate()
	_seq_next = next
	_next_step()

func _next_step() -> void:
	if _seq.is_empty():
		mode = "schedule"
		hold_item("")
		release()
		_to_floor()
		set_face(rules.default_face())
		var cb := _seq_next
		_seq_next = Callable()
		if cb.is_valid():
			cb.call()
		else:
			_resume()
		return
	var s: Dictionary = _seq.pop_front()
	_seq_t = s.get("t", 1.5)
	if not on_ladder:   # эмоции — лицом к игроку (чуть вполоборота)
		target_yaw = 0.35 if sin(rotation.y) >= 0.0 else -0.35
	set_face(s.get("face", rules.default_face()))
	act(s.get("clip", "idle"), -1.0, 0.15)
	if s.has("item"):
		hold_item(s["item"])
	if s.has("line"):
		var dur := say(s["line"], _seq_t + 0.4)
		_seq_t = maxf(_seq_t, dur + 0.2)
	if s.has("sfx"):
		Settings.sfx(s["sfx"], 0.8)
	if s.has("shake"):
		game.shake(s["shake"])
	if s.get("fall", false) or s.get("down", false):
		_to_floor(0.45)

func climb_ladder() -> void:
	if on_ladder:
		return
	on_ladder = true
	var tw := create_tween()
	tw.tween_property(self, "position", Vector3(12.25, 0.62, -2.05), 0.5).set_trans(Tween.TRANS_QUAD)

func _to_floor(t := 0.3) -> void:
	if not on_ladder:
		return
	on_ladder = false
	var tw := create_tween()
	tw.tween_property(self, "position", game.lane_point(12.0, 0), t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# ---------------------------------------------------------------- поимка
## Подбежать к герою и выдать «люлей». on_hit — когда ударил.
func catch_hero(hero_pos: Vector3, line: String, on_hit: Callable) -> void:
	mode = "chase"
	_clear_thought()
	_use_timer = -1.0
	_seq.clear()
	_to_floor()
	set_face("yell")
	say(line, 2.2)
	Settings.sfx("alert", 0.8)
	var target := Vector3(hero_pos.x - signf(hero_pos.x - position.x) * 0.55, hero_pos.y, game.LANE)
	if absf(hero_pos.x - position.x) > 0.7 and absf(hero_pos.y - position.y) < 0.5:
		speed_mul = 1.9
		walk_path(game.plan_path(position, target))
		await arrived
	face_x(hero_pos.x)
	act("catch", -1.0, 0.1)
	await get_tree().create_timer(0.55, false).timeout
	Settings.sfx("punch", 1.0)
	game.shake(0.4)
	on_hit.call()
	await get_tree().create_timer(1.3, false).timeout
	set_face("angry")
	act("angry", -1.0)
	await get_tree().create_timer(1.2, false).timeout
	if mode == "chase":
		mode = "schedule"
		release()
		set_face(rules.default_face())
		_resume()

# ---------------------------------------------------------------- финал
func finale(salad: bool) -> void:
	mode = "asleep"
	stop()
	_clear_thought()
	_use_timer = -1.0
	_seq.clear()
	_to_floor()
	if salad:
		activity = "идёт к салату…"
		set_face("wasted")
		say("Салатик… моя подушечка…", 2.5)
		speed_mul = 0.6
		var behind: float = game.SALAD_SPOT.z
		var pts: Array[Vector3] = []
		pts.assign(game.plan_path(position, game.lane_point(7.42, 0)))
		pts.append(Vector3(7.42, 0.0, behind))
		pts.append(Vector3(game.SALAD_SPOT.x, 0.0, behind))
		walk_path(pts)
		await arrived
		target_yaw = 0.0
		await get_tree().create_timer(0.5, false).timeout
		rotation.y = 0.0
		say("Я… ик… не пью…", 2.5)
		await get_tree().create_timer(1.8, false).timeout
		# когда голова опустится до стола и где она окажется — по кости головы в клипе падения
		var fit: Array = game.fit_fall_to_salad(self)
		var t: float = fit[0]
		hold = true
		ap.play("fall_forward", 0.15)
		_clip = "fall_forward"
		create_tween().tween_property(self, "position", position + fit[1], t * 0.8)
		await get_tree().create_timer(t, false).timeout
		ap.pause()
		Settings.sfx("splash", 0.9)
		game.shake(0.3)
		set_face("sleep")
		activity = "спит лицом в салате"
		finale_done.emit()
	else:
		activity = "уснул где стоял"
		set_face("wasted")
		say("Я… ик… не пью…", 2.5)
		await get_tree().create_timer(2.0, false).timeout
		act("fall_back", -1.0, 0.1)
		Settings.sfx("thud", 0.9)
		game.shake(0.4)
		await get_tree().create_timer(1.3, false).timeout
		act("sleep", -1.0, 0.4)
		set_face("sleep")
		activity = "спит на полу"
		finale_done.emit()
	while is_inside_tree():
		Settings.sfx("snore", 0.5)
		bubble = "Хр-р-р…  z Z z"
		bubble_time = 2.4
		await get_tree().create_timer(3.2, false).timeout

# ---------------------------------------------------------------- пьянство
func _drunk_behaviour(delta: float) -> void:
	var st: int = rules.stage()
	walk_clip = "walk_drunk" if st >= 2 else "walk"
	speed_mul = [1.0, 0.97, 0.9, 0.85, 0.7, 0.7][st] if mode != "chase" else speed_mul
	if is_walking() or mode != "schedule":
		return
	# «Тренер»: время от времени отрабатывает лоу-кики прямо посреди дела
	if st == 3 and not on_ladder:
		_kick_t -= delta
		if _kick_t <= 0.0:
			_kick_t = randf_range(9.0, 14.0)
			var prev := clip()
			var was_hold := hold
			act("kick", -1.0)
			set_face("angry")
			say(["Так, смотри сюда! Лоу-кик!", "Руки держим, руки!", "Работаем, работаем!", "Кийя!"].pick_random(), 2.5)
			get_tree().create_timer(2.6, false).timeout.connect(func():
				if clip() == "kick" and mode == "schedule":
					set_face(rules.default_face())
					if was_hold and prev != "kick":
						act(prev)
					else:
						release())
	if st >= 1:
		_hic_t -= delta
		if _hic_t <= 0.0:
			_hic_t = randf_range(9.0, 16.0)
			Settings.sfx("hiccup", 0.6, randf_range(0.85, 1.05))
			if st >= 2 and randf() < 0.5 and bubble == "":
				say(["Ну одну-то можно…", "Это не считается.", "А чё, нормально сидим!", "Завтра точно брошу."][mini(3, (st - 1) * 2 + randi() % 2)], 2.5)
	elif bubble == "":
		_grumble_t -= delta
		if _grumble_t <= 0.0:
			_grumble_t = randf_range(25.0, 40.0)
			say(GRUMBLE.pick_random(), 2.5)

## Пока бушует (вся цепочка реакции) — «говорит»: герой ждёт своей очереди.
func is_speaking() -> bool:
	return super.is_speaking() or mode == "react"

func is_kicking() -> bool:
	return clip() == "kick" and not is_walking()

# ---------------------------------------------------------------- обзор
func view_range(hour: float) -> float:
	if mode in ["asleep", "bed"] or clip() in ["lie_back", "sleep", "fall_back", "get_up"]:
		return 0.0
	var r: float = SOBER_RANGE * [1.0, 0.9, 0.75, 0.6, 0.38, 0.0][rules.stage()]
	if activity == "сидит в чат-рулетке":
		r *= 0.35
	elif activity == "играет в приставку":
		r *= 0.45
	if hour < suspicious_until:
		r *= 1.3
	return r

## Видит ли героя прямо сейчас.
func sees(h: Hero3D, hour: float) -> bool:
	if h.in_hiding or mode == "chase":
		return false
	if game.on_stairs(h.position) or game.floor_of(h.position) != game.floor_of(position):
		return false
	if game.room_at(h.position) != game.room_at(position):
		return false
	var dx := h.position.x - position.x
	var s := sin(rotation.y)
	var c := cos(rotation.y)
	var r := view_range(hour)
	if absf(dx) < 0.45:
		return r > 0.0
	if c < -0.6:            # стоит лицом к стене — видит только краем глаза рядом
		return absf(dx) <= r * 0.35
	if c > 0.6:             # лицом к игроку — по бокам видит, но хуже
		return absf(dx) <= r * 0.7
	if absf(s) > 0.3 and (dx > 0.0) != (s > 0.0):
		return false
	return absf(dx) <= r

## Иногда оглядывается по сторонам, потом возвращается к делу.
func look_around(delta: float) -> void:
	if is_walking() or mode != "schedule" or on_ladder or clip() == "kick":
		return
	if _look_back > 0.0:
		_look_back -= delta
		if _look_back <= 0.0:
			target_yaw = _activity_yaw
		return
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = randf_range(5.0, 9.0)
		_look_back = randf_range(1.4, 2.4)
		target_yaw = PI / 2 if randf() < 0.5 else -PI / 2
