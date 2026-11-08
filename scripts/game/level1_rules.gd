class_name Level1Rules
extends Node
## Правила уровня 1 «Понедельник. Больше не пью»: тайники, подмены, пакости, опьянение,
## цепочки, очки. Описание — docs/LEVEL1_DESIGN.md.

signal toast(text: String, good: bool)
signal inventory_changed
signal finished(win: bool, reason: String)

const ITEMS := {
	"antifreeze": ["Незамерзайка", "res://assets/props/drinks/drink_antifreeze.png"],
	"tincture":   ["Настойка",     "res://assets/props/drinks/drink_tincture.png"],
	"beer":       ["Банка пива",   "res://assets/props/drinks/drink_beer_can.png"],
	"chekushka":  ["Чекушка",      "res://assets/props/drinks/drink_vodka_small.png"],
	"vodka":      ["Водка",        "res://assets/props/drinks/drink_vodka.png"],
	"bulb":       ["Перегоревшая лампочка", "res://assets/props/repair/repair_bulb_burnt.png"],
	"salad":      ["Салат",        "res://assets/props/misc/misc_salad.png"],
	"gamepad":    ["Геймпад",      "res://assets/props/misc/misc_gamepad.png"],
	"phone":      ["Телефон",      "res://assets/props/misc/misc_phone.png"],
	"keys":       ["Ключи",        ""],
}

## [id, комната, вид, x, y, ширина, высота, где встать (x в комнате), название, предмет]
## stash — взять предмет; swap — подменить (нужен предмет); take — унести; hide — укрытие; place — положить.
const SPOTS := [
	["toilet",     "bathroom", "stash", 830, 520, 190, 150, 900,  "Бачок унитаза",        "beer"],
	["sink",       "bathroom", "stash", 560, 610, 230, 230, 680,  "Шкафчик под раковиной","tincture"],
	["mouthwash",  "bathroom", "swap",  640, 420, 190, 110, 700,  "Ополаскиватель",       "antifreeze"],
	["curtain",    "bathroom", "hide",  20,  300, 420, 600, 230,  "Шторка ванной",        ""],
	["bed",        "bedroom",  "hide",  200, 700, 640, 250, 520,  "Под кроватью",         ""],
	["jars",       "balcony",  "stash", 280, 400, 410, 160, 480,  "Банки с соленьями",    "vodka"],
	["canisters",  "balcony",  "stash", 290, 600, 230, 220, 400,  "Канистры",             "antifreeze"],
	["toolbox",    "balcony",  "stash", 525, 660, 160, 150, 600,  "Ящик с инструментами", "bulb"],
	["skis",       "balcony",  "hide",  0,   200, 220, 750, 120,  "За лыжами",            ""],
	["jacket",     "hallway",  "swap",  420, 320, 230, 290, 530,  "Куртка на вешалке",    "chekushka"],
	["boots",      "hallway",  "stash", 420, 650, 280, 250, 560,  "Ботинки на полке",     "chekushka"],
	["wardrobe",   "hallway",  "hide",  720, 230, 470, 700, 950,  "Шкаф-купе",            ""],
	["keys",       "hallway",  "take",  1230, 500, 200, 140, 1330, "Ключи в миске",        "keys"],
	["fridge",     "kitchen",  "swap",  30,  260, 250, 650, 175,  "Холодильник",          "vodka"],
	["coffee",     "kitchen",  "swap",  1300, 540, 140, 110, 1290, "Кружка кофе",          "tincture"],
	["table",      "kitchen",  "hide",  1060, 660, 440, 260, 1270, "Под столом",           ""],
	["sofa",       "living",   "hide",  20,  520, 700, 330, 300,  "За диваном",           ""],
	["phone",      "living",   "take",  520, 600, 120, 100, 560,  "Телефон на диване",    "phone"],
	["gamepad",    "living",   "take",  1110, 575, 150, 100, 1080, "Геймпад",              "gamepad"],
	["soda",       "living",   "swap",  745, 480, 110, 140, 860,  "Газировка",            "beer"],
	["ladder",     "living",   "swap",  1250, 440, 280, 400, 1300, "Стремянка и лампочка", "bulb"],
]

## Подмены: сколько опьянения даёт и реплика при первом срабатывании.
const SWAPS := {
	"mouthwash": [20, "Ух… бодрит!", "tipsy"],
	"coffee":    [10, "Чё-то кофе сегодня крепкий…", "tipsy"],
	"fridge":    [25, "…Да как так нахуй?!", "angry"],
	"soda":      [15, "Хм. А газировка-то с пеной…", "tipsy"],
	"jacket":    [20, "…Это знак.", "suspicious"],
}

const STAGES := ["Трезвый", "Чуть-чуть", "Весёлый", "Тренер", "В стельку", "Уснул"]
const STAGE_FROM := [0, 15, 35, 60, 85, 100]
const MAX_SCORE := 5 * 100 + 4 * 75 + 4 * 150 + 300

var level: Level
var neighbor: Neighbor
var hero: Hero
var drunk := 0.0
var score := 0
var catches := 0
var inventory: Array[String] = []
var selected := ""
var log_done: Array[String] = []   # что удалось — для экрана итогов
var spots := {}                    # id -> Hotspot
var swapped := {}                  # id -> true
var taken := {}                    # id -> true (унесено из квартиры героем)
var salad_on_table := false
var over := false
var _scored := {}
var _props := {}                   # id -> Sprite2D (нарисованные поверх фона предметы)

func setup(lv: Level) -> void:
	level = lv
	neighbor = lv.neighbor
	hero = lv.hero
	for s in SPOTS:
		var h := Hotspot.new()
		h.id = s[0]
		h.kind = s[2]
		var r := level.room_rect(s[1])
		h.rect = Rect2(r.position + Vector2(s[3], s[4]), Vector2(s[5], s[6]))
		h.walk = level.spot(s[1], float(s[7]))
		h.title = s[8]
		h.set_meta("item", s[9])
		level.add_child(h)
		spots[h.id] = h
	# предметов нет на картинках — дорисовываем
	_add_prop("phone", "living", "res://assets/props/misc/misc_phone.png", Vector2(580, 660), 0.28, -0.3)
	_add_prop("soda", "living", "res://assets/props/drinks/drink_soda.png", Vector2(800, 612), 0.34, 0.0, true)
	_add_prop("salad", "kitchen", "res://assets/props/misc/misc_salad.png", Vector2(1200, 640), 0.32, 0.0, true)
	_props["salad"].visible = false

func _add_prop(id: String, room: String, path: String, pos: Vector2, k: float, rot := 0.0, bottom := false) -> void:
	var s := Sprite2D.new()
	s.texture = load(path)
	s.scale = Vector2.ONE * k
	s.rotation = rot
	s.position = level.room_rect(room).position + pos
	if bottom:
		s.offset = Vector2(0, -s.texture.get_height() * 0.5)
	s.z_index = -20
	level.add_child(s)
	_props[id] = s

# --- Опьянение --------------------------------------------------------------------

func stage() -> int:
	var st := 0
	for i in STAGE_FROM.size():
		if drunk >= STAGE_FROM[i]:
			st = i
	return st

func stage_name() -> String:
	return STAGES[stage()]

func default_face() -> String:
	return ["proud", "tipsy", "drunk", "singing", "drunk", "sleeping"][stage()]

func add_drunk(v: float) -> void:
	var before := stage()
	drunk = minf(drunk + v, 100.0)
	if stage() != before:
		toast.emit("Сосед: «%s»" % stage_name(), true)
	if drunk >= 100.0:
		_finale()

func _award(key: String, points: int, text: String) -> void:
	if _scored.has(key):
		return
	_scored[key] = true
	score += points
	log_done.append(text)
	toast.emit("%s  +%d" % [text, points], true)

# --- Подсказки --------------------------------------------------------------------

func item_title(id: String) -> String:
	return ITEMS[id][0]

func describe(h: Hotspot) -> String:
	var item: String = h.get_meta("item")
	match h.kind:
		"stash":
			return "%s — взять: %s" % [h.title, item_title(item)]
		"take":
			return "%s — утащить" % h.title
		"hide":
			if h.id == "table" and selected == "salad":
				return "Стол — поставить салат"
			return "%s — спрятаться" % h.title
		"swap":
			if swapped.has(h.id):
				return "%s — уже подменено" % h.title
			if selected == item:
				return "%s — подложить: %s" % [h.title, item_title(item)]
			return "%s — нужно: %s" % [h.title, item_title(item)]
	return h.title

# --- Действия героя ---------------------------------------------------------------

func hero_use(h: Hotspot) -> void:
	if over:
		return
	var item: String = h.get_meta("item")
	match h.kind:
		"stash", "take":
			hero.act(0.8)
			_give(item)
			h.active = false
			if h.kind == "take":
				taken[item] = true
				h.done = true
				if _props.has(h.id):
					_props[h.id].visible = false
		"hide":
			if h.id == "table" and selected == "salad":
				hero.act(0.8)
				_use_selected()
				salad_on_table = true
				_props["salad"].visible = true
				toast.emit("Салат на столе. Ждём финала…", true)
				return
			hero.set_hidden(true)
		"swap":
			if swapped.has(h.id):
				return
			if selected != item:
				toast.emit("Нужно: %s" % item_title(item), false)
				return
			hero.act(1.0)
			_use_selected()
			swapped[h.id] = true
			h.done = true
			var what := {"mouthwash": "Ополаскиватель → незамерзайка", "coffee": "Настойка в кофе",
				"fridge": "Минералка → водка", "soda": "Газировка → пиво", "jacket": "Чекушка в куртке",
				"ladder": "Лампочка подменена"}
			toast.emit(what.get(h.id, "Готово"), true)

func _give(item: String) -> void:
	inventory.append(item)
	toast.emit("Взял: %s" % item_title(item), true)
	inventory_changed.emit()

func _use_selected() -> void:
	inventory.erase(selected)
	selected = ""
	inventory_changed.emit()

func select(item: String) -> void:
	selected = "" if selected == item else item
	inventory_changed.emit()

# --- Сосед пользуется вещами -----------------------------------------------------

func neighbor_use(id: String) -> void:
	if over:
		return
	match id:
		"wake":
			neighbor.set_face("proud")
			neighbor.say("Всё, сегодня больше не пью!", 3.5)
			get_tree().create_timer(4.0).timeout.connect(func():
				if neighbor.mode == "schedule":
					neighbor.say("Не, вообще к пиву не тянет.", 3.0))
		"mouthwash", "coffee", "soda", "jacket":
			if swapped.has(id) and not _scored.has("used_" + id + str(neighbor.current)):
				_scored["used_" + id + str(neighbor.current)] = true
				var sw: Array = SWAPS[id]
				_award("swap_" + id, 100, "Подмена: " + spots[id].title)
				neighbor.react(sw[2], sw[1], 2.5)
				add_drunk(sw[0])
				if id in ["coffee", "soda", "jacket"]:
					swapped.erase(id)    # выпил — больше не сработает
					spots[id].done = false
					spots[id].active = id != "jacket"
				if id == "jacket" and taken.has("keys"):
					_award("chain_bread", 150, "Цепочка «За хлебом»")
		"fridge", "detour":
			if swapped.has("fridge"):
				var first := not _scored.has("swap_fridge")
				_award("swap_fridge", 100, "Подмена: минералка → водка")
				if first:
					neighbor.react("angry", "…Да как так нахуй?!", 2.0, func():
						neighbor.react("tipsy", "Ну раз уж открыл…", 2.0))
				else:
					neighbor.react(default_face(), ["Ну ещё по одной…", "За ремонт!", "Последняя. Точно."].pick_random(), 2.2)
				if id == "detour" and _scored.has("rage"):
					_award("chain_grief", 150, "Цепочка «Сорвался с горя»")
				add_drunk(25)
			elif id == "detour":
				neighbor.react("normal", "Минералочка… Успокоился.", 1.8)
		"gamepad":
			if taken.has("gamepad"):
				_scored["rage"] = true
				_award("prank_gamepad", 75, "Пакость: спрятан геймпад")
				neighbor.react("angry", "Да ну нахуй! Где геймпад?!", 2.5, _go_fridge)
		"phone":
			if taken.has("phone"):
				_scored["rage"] = true
				_award("prank_phone", 75, "Пакость: спрятан телефон")
				neighbor.react("angry", "Да как так нахуй?! Где телефон?!", 2.5, _go_fridge)
			elif stage() >= 2:
				neighbor.idle_anim = "kick"
				neighbor.say("Смотри, как я могу! Кийя!", 2.5)
				get_tree().create_timer(3.0).timeout.connect(func():
					if over:
						return
					_award("chain_roulette", 150, "Цепочка «Звезда чат-рулетки»")
					_scored["rage"] = true
					neighbor.react("angry", "Э, куда скипаешь?! Да как так нахуй?!", 2.5, _go_fridge))
		"ladder":
			if swapped.has("ladder"):
				swapped.erase("ladder")
				if stage() >= 2:
					_award("prank_bulb", 75, "Пакость: перегоревшая лампочка")
					_award("chain_electric", 150, "Цепочка «Электрик»")
					neighbor.fall(false)
					neighbor.react("angry", "Да как так нахуй?!", 3.0, func():
						neighbor.get_up()
						_scored["rage"] = true
						_go_fridge())
				else:
					_award("prank_bulb", 75, "Пакость: перегоревшая лампочка")
					neighbor.react("angry", "Опять перегорела? Да ну нахуй.", 2.5)
		"keys":
			if taken.has("keys"):
				_award("prank_keys", 75, "Пакость: спрятаны ключи")
				_scored["rage"] = true
				neighbor.react("angry", "Да ну нахуй, где ключи?! …Ну раз дома — можно.", 3.0, _go_fridge)
		"balcony":
			if inventory.has("vodka") or swapped.has("fridge"):
				neighbor.react("suspicious", "Э… А где моя заначка за банками?", 2.5)

func _go_fridge() -> void:
	if over:
		return
	neighbor.detour("kitchen", 175, "идёт к холодильнику «успокоиться»", "drink", "detour")

# --- Финал ------------------------------------------------------------------------

func _finale() -> void:
	if over:
		return
	over = true
	neighbor.stop()
	if salad_on_table:
		neighbor.mode = "asleep"
		neighbor.activity = "идёт к салату…"
		neighbor.say("Я… ик… не пью…", 3.0)
		neighbor.walk_path(level.plan_path(neighbor.position, level.spot("kitchen", 1250)))
		await neighbor.arrived
		neighbor.face(true)
		neighbor.set_face("sleeping")
		neighbor.fall(true)
		_award("final_salad", 300, "Финал: лицом в салат!")
		neighbor.activity = "спит лицом в салате"
	else:
		neighbor.fall_asleep()
		neighbor.say("Я… ик… не пью…", 3.0)
		neighbor.fall(false)
	await get_tree().create_timer(3.5).timeout
	finished.emit(true, "Сосед уснул")

func caught() -> void:
	catches += 1
	score = maxi(0, score - 100)
	if catches >= 3:
		over = true
		finished.emit(false, "Сосед поймал тебя три раза")

func time_up() -> void:
	if over:
		return
	over = true
	finished.emit(false, "Наступил вечер, а сосед всё ещё на ногах")

func shame_percent() -> int:
	return clampi(roundi(100.0 * score / MAX_SCORE), 0, 100)

func shame_title() -> String:
	var p := shame_percent()
	if p >= 90: return "Легенда подъезда"
	if p >= 60: return "В синьку"
	if p >= 30: return "Сорвался"
	return "Держится, зараза"
