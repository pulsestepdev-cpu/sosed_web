class_name Neighbor
extends Character
## Сосед: живёт по расписанию, пользуется предметами (через правила уровня), отвлекается
## на «срочные дела» (сходить к холодильнику), смотрит по сторонам и ловит героя.

## Расписание: [час, комната, x в комнате, что делает, поза, использует (id предмета или "")]
const SCHEDULE := [
	[7.5,  "bedroom",  540,  "спит",                  "idle",  ""],
	[8.0,  "bedroom",  760,  "проснулся",             "idle",  "wake"],
	[8.17, "bathroom", 700,  "чистит зубы",           "work",  "mouthwash"],
	[8.5,  "kitchen",  1290, "пьёт кофе",             "drink", "coffee"],
	[9.0,  "living",   1380, "шпаклюет стену",        "work",  ""],
	[11.0, "kitchen",  175,  "пьёт минералку",        "drink", "fridge"],
	[11.25,"living",   1000, "играет в приставку",    "phone", "gamepad"],
	[11.6, "living",   1000, "играет в приставку",    "phone", "soda"],
	[13.0, "bathroom", 700,  "умывается",             "work",  "mouthwash"],
	[13.5, "living",   1390, "меняет лампочку",       "work",  "ladder"],
	[14.0, "balcony",  900,  "дышит воздухом",        "idle",  "balcony"],
	[14.5, "living",   1380, "шпаклюет стену",        "work",  ""],
	[15.5, "kitchen",  1290, "пьёт кофе",             "drink", "coffee"],
	[16.5, "kitchen",  175,  "пьёт минералку",        "drink", "fridge"],
	[17.0, "living",   420,  "сидит в чат-рулетке",   "phone", "phone"],
	[18.0, "hallway",  540,  "собирается за хлебом",  "idle",  "jacket"],
	[18.3, "hallway",  1330, "ищет ключи",            "idle",  "keys"],
	[19.0, "kitchen",  175,  "ужинает",               "drink", "fridge"],
]

const USE_DELAY := 1.6       # через сколько секунд после прихода он берёт предмет
const SOBER_RANGE := 950.0

var level: Level
var rules: Node              # Level1Rules
var current := -1
var activity := ""
var mode := "schedule"       # schedule | detour | react | asleep
var suspicion := 0.0         # 0..1, при 1 — поймал
var suspicious_until := 0.0  # игровой час, до которого он настороже
var _use_timer := -1.0
var _use_id := ""
var _react_time := 0.0
var _after_react := Callable()
var _look_timer := 5.0
var _look_back := 0.0
var _detour: Dictionary = {}
var _kick_timer := 6.0

func _init() -> void:
	who = "neighbor"
	walk_px_per_sec = 390.0

func _ready() -> void:
	super._ready()
	arrived.connect(_on_arrived)

# --- Расписание ----------------------------------------------------------------

func update_schedule(hour: float, delta: float) -> void:
	if mode == "asleep":
		return
	if mode == "react":
		_react_time -= delta
		if _react_time <= 0.0:
			mode = "schedule"
			var cb := _after_react
			_after_react = Callable()
			if cb.is_valid():
				cb.call()
			else:
				_resume()
		return

	if _use_timer > 0.0:
		_use_timer -= delta
		if _use_timer <= 0.0:
			var id := _use_id
			_use_id = ""
			if mode == "detour":
				_finish_detour()
			else:
				rules.neighbor_use(id)

	_update_drunk_behaviour(delta)
	if mode == "detour":
		return

	# не бросаем дело с предметом на полпути: сначала дойти и воспользоваться
	if current >= 0 and SCHEDULE[current][5] != "" and (is_walking() or _use_timer > 0.0):
		return
	var idx := -1
	for i in SCHEDULE.size():
		if hour >= SCHEDULE[i][0]:
			idx = i
	if idx == current or idx < 0:
		return
	current = idx
	_go_to_current()

func _go_to_current() -> void:
	var e: Array = SCHEDULE[current]
	activity = "идёт: " + e[3]
	idle_anim = "idle"
	if lying and e[3] != "спит":
		get_up()
		set_face(rules.default_face())
	var target := level.spot(e[1], float(e[2]))
	if position.distance_to(target) < 2.0:
		_on_arrived()
	else:
		walk_path(level.plan_path(position, target))

func _resume() -> void:
	if current >= 0:
		_go_to_current()

func _on_arrived() -> void:
	if mode == "detour":
		idle_anim = _detour.get("anim", "drink")
		activity = _detour.get("title", "")
		_use_id = "detour"
		_use_timer = USE_DELAY
		return
	if current < 0:
		return
	var e: Array = SCHEDULE[current]
	activity = e[3]
	idle_anim = e[4]
	face(true)
	if e[3] == "спит":
		set_face("sleeping")
		fall(false)
		return
	set_face(rules.default_face())
	if e[5] != "":
		_use_id = e[5]
		_use_timer = USE_DELAY

# --- Отлучки и реакции ------------------------------------------------------------

## Сходить куда-то вне расписания (обычно «к холодильнику»), потом вернуться к делам.
func detour(room: String, x: float, title: String, anim: String, use_id: String) -> void:
	mode = "detour"
	_use_timer = -1.0
	_detour = {"title": title, "anim": anim, "use": use_id}
	activity = "идёт: " + title
	idle_anim = "idle"
	var target := level.spot(room, x)
	if position.distance_to(target) < 2.0:
		_on_arrived()
	else:
		walk_path(level.plan_path(position, target))

func _finish_detour() -> void:
	var id: String = _detour.get("use", "")
	mode = "schedule"
	_detour = {}
	rules.neighbor_use(id)
	if mode == "schedule":
		_resume()

## Застыть на секунды с лицом и репликой, потом сделать next (или вернуться к расписанию).
func react(face_name: String, line: String, seconds: float, next := Callable()) -> void:
	mode = "react"
	stop()
	_use_timer = -1.0
	set_face(face_name)
	if line != "":
		say(line, seconds + 0.5)
	_react_time = seconds
	_after_react = next

func fall_asleep() -> void:
	mode = "asleep"
	activity = "спит пьяный"
	stop()
	_use_timer = -1.0
	set_face("sleeping")

# --- Пьянство ------------------------------------------------------------------

func _update_drunk_behaviour(delta: float) -> void:
	var stage: int = rules.stage()
	rig.sway = [0.0, 0.25, 0.55, 0.75, 1.0, 1.0][stage]
	speed_mul = [1.0, 0.95, 0.85, 0.8, 0.6, 0.6][stage]
	# «Тренер»: время от времени отрабатывает лоу-кики прямо посреди дела
	if stage == 3 and not is_walking() and mode == "schedule" and not lying:
		_kick_timer -= delta
		if _kick_timer <= 0.0:
			_kick_timer = randf_range(7.0, 11.0)
			var lines := ["Так, смотри сюда! Лоу-кик!", "Руки держим, руки!", "Работаем, работаем!", "Кийя!"]
			var prev_anim := idle_anim
			idle_anim = "kick"
			say(lines.pick_random(), 2.5)
			get_tree().create_timer(2.6).timeout.connect(func():
				if idle_anim == "kick":
					idle_anim = prev_anim)

func is_kicking() -> bool:
	return idle_anim == "kick" and not is_walking()

# --- Обзор -----------------------------------------------------------------------

func view_range(hour: float) -> float:
	if mode == "asleep" or lying or activity == "спит":
		return 0.0
	var r: float = SOBER_RANGE * [1.0, 0.9, 0.7, 0.55, 0.32, 0.0][rules.stage()]
	if activity == "сидит в чат-рулетке":
		r *= 0.3
	elif activity == "играет в приставку":
		r *= 0.45
	if hour < suspicious_until:
		r *= 1.3
	return r

## Видит ли героя прямо сейчас.
func sees(hero: Hero, hour: float) -> bool:
	if hero.in_hiding:
		return false
	if level.floor_of(hero.position.y) != level.floor_of(position.y) or level.on_stairs(hero.position):
		return false
	if level.room_at(hero.position) != level.room_at(position):
		return false
	var dx := hero.position.x - position.x
	if (dx > 0.0) != facing_right() and absf(dx) > 90.0:
		return false
	return absf(dx) <= view_range(hour)

## Иногда оглядывается: поворачивается в другую сторону на пару секунд.
func look_around(delta: float) -> void:
	if is_walking() or mode != "schedule" or lying:
		return
	if _look_back > 0.0:
		_look_back -= delta
		if _look_back <= 0.0:
			face(true)
		return
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = randf_range(5.0, 9.0)
		_look_back = randf_range(1.5, 2.5)
		face(not facing_right())
