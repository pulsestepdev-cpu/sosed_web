class_name Neighbor
extends Character
## Сосед: живёт по расписанию. В нужное время идёт в нужную точку и делает дело.

## Расписание: [час (дробный), комната, x внутри комнаты, действие, лицо, реплика]
const SCHEDULE := [
	[7.5,  "living",   380,  "спит",                    "sleeping", ""],
	[8.0,  "living",   380,  "просыпается",             "proud",    "Всё, сегодня больше не пью!"],
	[8.17, "bathroom", 670,  "чистит зубы",             "normal",   ""],
	[8.5,  "kitchen",  1270, "пьёт кофе",               "normal",   "Не, вообще к пиву не тянет."],
	[9.0,  "living",   1300, "шпаклюет стену",          "normal",   ""],
	[11.0, "kitchen",  200,  "пьёт минералку",          "normal",   ""],
	[11.25,"living",   980,  "играет в приставку",      "normal",   ""],
	[13.0, "bathroom", 670,  "умывается",               "normal",   ""],
	[13.5, "living",   770,  "меняет лампочку",         "normal",   ""],
	[14.0, "balcony",  800,  "дышит воздухом",          "normal",   ""],
	[14.5, "living",   1300, "шпаклюет стену",          "normal",   ""],
	[16.5, "kitchen",  200,  "пьёт минералку",          "normal",   ""],
	[17.0, "living",   380,  "сидит в чат-рулетке",     "normal",   "Привет, откуда?"],
	[18.0, "hallway",  1300, "собирается за хлебом",    "normal",   ""],
	[19.0, "kitchen",  1270, "ужинает",                 "normal",   ""],
]

signal activity_started(entry: Array)

var level: Node            # Level: даёт координаты комнат
var current := -1
var activity := ""
var _pending := false

func _init() -> void:
	who = "neighbor"
	walk_px_per_sec = 300.0

func _ready() -> void:
	super._ready()
	arrived.connect(_on_arrived)

## Вызывается уровнем каждый кадр с текущим игровым временем (в часах).
func update_schedule(hour: float) -> void:
	var idx := -1
	for i in SCHEDULE.size():
		if hour >= SCHEDULE[i][0]:
			idx = i
	if idx == current or idx < 0:
		return
	current = idx
	var e: Array = SCHEDULE[idx]
	activity = "идёт: " + e[3]
	set_face("normal" if e[4] == "sleeping" else e[4])
	var x: float = level.room_left(e[1]) + float(e[2])
	if absf(x - position.x) < 2.0:
		_on_arrived()
	else:
		_pending = true
		walk_to(x)

func _on_arrived() -> void:
	if current < 0:
		return
	_pending = false
	var e: Array = SCHEDULE[current]
	activity = e[3]
	set_face(e[4])
	face(true)
	if e[5] != "":
		say(e[5], 4.0)
	activity_started.emit(e)
