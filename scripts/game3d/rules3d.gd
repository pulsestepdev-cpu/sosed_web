class_name Rules3D
extends Node
## Правила уровня 1 «Понедельник. Больше не пью» (3D): тайники, подмены, пакости, ловушки, опьянение,
## цепочки, очки, реакции соседа и подколки героя. Описание — docs/LEVEL1_DESIGN.md.
##
## Как в классике жанра: герой находит вещи в тайниках, подкладывает/подменяет их, пока сосед не видит;
## сосед по расписанию натыкается на подставу и бурно реагирует, а герой в этот момент злорадствует.

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
	"keys":       ["Ключи",        "res://assets/props/misc/misc_keys.png"],
	"banana":     ["Банановая кожура", "res://assets/props/misc/misc_banana_peel.png"],
	"soap":       ["Мыло",         "res://assets/props/misc/misc_soap.png"],
}

## [id, вид, узел в сцене, x где встать, этаж (0 — 1-й, 1 — 2-й), название, предмет]
## stash — взять предмет; swap — подменить (нужен предмет); take — утащить; hide — укрытие;
## trap — положить ловушку на пол (нужен предмет).
const SPOTS := [
	["toilet",    "stash", "toilet",          5.55, 1, "Бачок унитаза",          "beer"],
	["sink",      "stash", "sink_vanity",     4.92, 1, "Шкафчик под раковиной", "tincture"],
	["mouthwash", "swap",  "bath_shelf",      4.92, 1, "Ополаскиватель",         "antifreeze"],
	["soapdish",  "stash", "soap_dish",       4.3,  1, "Мыльница",               "soap"],
	["curtain",   "hide",  "shower_curtain",  3.75, 1, "Шторка ванной",          ""],
	["soaptrap",  "trap",  "",                4.92, 1, "Пол у раковины",         "soap"],
	["bed",       "hide",  "bed",             8.0,  1, "Под кроватью",           ""],
	["jars",      "stash", "balcony_shelf",   11.0, 1, "Банки с соленьями",      "vodka"],
	["canisters", "stash", "antifreeze",      12.4, 1, "Канистра",               "antifreeze"],
	["toolbox",   "stash", "toolbox",         11.95, 1, "Ящик с инструментами",  "bulb"],
	["skis",      "hide",  "skis",            13.35, 1, "За лыжами",             ""],
	["wardrobe",  "hide",  "wardrobe",        3.75, 0, "Шкаф",                   ""],
	["keys",      "take",  "keys",            4.62, 0, "Ключи в миске",          "keys"],
	["jacket",    "swap",  "coat_rack",       5.45, 0, "Куртка на вешалке",      "chekushka"],
	["boots",     "stash", "shoe_shelf",      5.55, 0, "Ботинки на полке",       "chekushka"],
	["peeltrap",  "trap",  "",                9.45, 0, "Пол у холодильника",     "banana"],
	["fruit",     "stash", "fruit_bowl",      9.05, 0, "Ваза с фруктами",        "banana"],
	["fridge",    "swap",  "fridge",          9.45, 0, "Холодильник",            "vodka"],
	["coffee",    "swap",  "coffee_mug",      8.3,  0, "Кружка кофе",            "tincture"],
	["salad",     "stash", "salad",           7.8,  0, "Миска салата",           "salad"],
	["table",     "hide",  "table",           8.7,  0, "Под столом",             ""],
	["sofa",      "hide",  "sofa",            11.95, 0, "За диваном",            ""],
	["phone",     "take",  "smartphone",      11.1, 0, "Телефон на диване",      "phone"],
	["gamepad",   "take",  "gamepad",         12.75, 0, "Геймпад",               "gamepad"],
	["soda",      "swap",  "soda_bottle",     13.05, 0, "Газировка",             "beer"],
	["ladder",    "swap",  "stepladder",      6.0,  0, "Стремянка и лампочка",   "bulb"],
]

## Подмены: [опьянение, реплика, лицо после глотка]
const SWAPS := {
	"mouthwash": [20, "Ух… бодрит!", "tipsy"],
	"coffee":    [10, "Чё-то кофе сегодня крепкий…", "tipsy"],
	"fridge":    [25, "Да как так нахуй?!", "shock"],
	"soda":      [15, "Хм. А газировка-то с пеной…", "tipsy"],
	"jacket":    [20, "…Это знак.", "happy"],
}

const RAGE := ["Да ну нахуй!", "Да как так нахуй?!", "Да ну нахер, серьёзно?!", "Это чё за херня, нахуй?!",
	"Да вы издеваетесь, нахуй?!", "Ну ёпт твою налево!"]
const TAUNTS := ["Пивная открывашка!", "Ветродуйка!", "Турбина перегарная!", "Пей до дна, открывашка!",
	"Давай-давай, ветродуйка!"]

## Герой говорит, пока подстраивает пакость (а не когда сосед попался — тогда говорит сосед):
## id места -> реплика.
const SETUP_LINES := {
	"mouthwash": "Пусть прополощет, ветродуйка!", "coffee": "Кофеёк с сюрпризом!",
	"fridge": "Минералочка, ага. Хе-хе.", "soda": "Газировочка с пенкой!",
	"jacket": "Сходит он за хлебом, как же!", "ladder": "Электрик, ты где? Хе-хе.",
	"peeltrap": "Смотри под ноги, турбина перегарная!", "soaptrap": "Скользкого утречка, ветродуйка!",
	"keys": "Ключики теперь мои!", "gamepad": "Поиграл — и хватит!", "phone": "Позвонишь потом, открывашка!",
	"salad": "Подушечка готова!",
}

const STAGES := ["Трезвый", "Чуть-чуть", "Весёлый", "Тренер", "В стельку", "Уснул"]
const STAGE_FROM := [0, 15, 35, 60, 85, 100]
const MAX_SCORE := 5 * 100 + 6 * 75 + 4 * 150 + 300

var game: Node                     # Game3D
var neighbor: Neighbor3D
var hero: Hero3D
var drunk := 0.0
var score := 0
var catches := 0
var inventory: Array[String] = []
var selected := ""
var log_done: Array[String] = []
var swapped := {}
var taken := {}
var traps := {}                    # id ловушки -> true (лежит на полу)
var salad_on_table := false
var over := false
var _scored := {}
var _taunt_i := 0

func setup(g: Node) -> void:
	game = g
	neighbor = g.neighbor
	hero = g.hero

# ---------------------------------------------------------------- опьянение
func stage() -> int:
	var st := 0
	for i in STAGE_FROM.size():
		if drunk >= STAGE_FROM[i]:
			st = i
	return st

func stage_name() -> String:
	return STAGES[stage()]

func default_face() -> String:
	return ["normal", "tipsy", "drunk", "drunk", "wasted", "sleep"][stage()]

func add_drunk(v: float) -> void:
	var before := stage()
	drunk = minf(drunk + v, 100.0)
	if stage() != before:
		toast.emit("Сосед теперь: «%s»" % stage_name(), true)
		Settings.sfx("stage", 0.6)
	if drunk >= 100.0:
		_finale()

func _award(key: String, points: int, text: String) -> bool:
	if _scored.has(key):
		return false
	_scored[key] = true
	score += points
	log_done.append(text)
	toast.emit("%s  +%d" % [text, points], true)
	Settings.sfx("prank", 0.7)
	return true

## Герой злорадствует, пока сосед бушует: смеётся молча (говорит в это время сосед).
func gloat(delay := 1.2) -> void:
	get_tree().create_timer(delay, false).timeout.connect(func():
		if over and not salad_on_table and drunk < 100.0:
			return
		hero.gloat(""))

## Реплика героя, когда он подстраивает пакость.
func setup_line(id: String, delay := 0.5) -> void:
	var line: String = SETUP_LINES.get(id, TAUNTS[_taunt_i % TAUNTS.size()])
	_taunt_i += 1
	get_tree().create_timer(delay, false).timeout.connect(func():
		if not over:
			hero.say(line, 2.2))

func rage_line() -> String:
	return RAGE[randi() % RAGE.size()]

# ---------------------------------------------------------------- подсказки
func item_title(id: String) -> String:
	return ITEMS[id][0]

func describe(s: Spot3D) -> String:
	match s.kind:
		"stash":
			return "%s — пошарить" % s.title
		"take":
			return "%s — утащить" % s.title
		"hide":
			if s.id == "table" and selected == "salad":
				return "Стол — поставить салат"
			return "%s — спрятаться" % s.title
		"swap":
			if swapped.has(s.id):
				return "%s — уже подменено" % s.title
			if selected == s.item:
				return "%s — подложить: %s" % [s.title, item_title(s.item)]
			return "%s — нужно: %s" % [s.title, item_title(s.item)]
		"trap":
			if traps.has(s.id):
				return "%s — ловушка готова" % s.title
			if selected == s.item:
				return "%s — подложить: %s" % [s.title, item_title(s.item)]
			return "%s — сюда бы %s" % [s.title, item_title(s.item).to_lower()]
	return s.title

# ---------------------------------------------------------------- действия героя
func hero_use(s: Spot3D) -> void:
	if over:
		return
	match s.kind:
		"stash":
			if not s.active:     # уже обшарил (или шарит прямо сейчас — повторный клик)
				return
			s.active = false
			var low: bool = s.aabb.get_center().y - game.floor_y(s.floor) < 0.7
			hero.busy_act("search_low" if low else "search_mid", 1.4)
			game.open_prop(s, 1.6)
			Settings.sfx("rustle", 0.7)
			get_tree().create_timer(1.3, false).timeout.connect(func():
				if over:
					return
				_give(s.item)
				hero.found()
				if s.id == "salad":
					game.show_prop("salad", false))
		"take":
			if not s.active:
				return
			s.active = false
			hero.busy_act("take", 1.0)
			get_tree().create_timer(0.6, false).timeout.connect(func():
				_give(s.item)
				setup_line(s.item, 0.2)
				taken[s.item] = true
				s.active = false
				s.done = true
				if s.node:
					s.node.visible = false)
		"hide":
			if s.id == "table" and selected == "salad":
				hero.busy_act("swap", 1.0)
				_use_selected()
				salad_on_table = true
				game.place_salad()
				toast.emit("Салат на столе. Ждём финала…", true)
				setup_line("salad")
				return
			hero.hide_in(s)
		"swap":
			if swapped.has(s.id):
				return
			if selected != s.item:
				toast.emit("Нужно: %s" % item_title(s.item), false)
				hero.say("Сюда бы… %s." % item_title(s.item).to_lower(), 2.0)
				return
			hero.busy_act("swap", 1.4)
			game.open_prop(s, 1.5)
			Settings.sfx("swap", 0.6)
			_use_selected()
			swapped[s.id] = true
			s.done = true
			var what := {"mouthwash": "Незамерзайка вместо ополаскивателя", "coffee": "Настойка в кофе",
				"fridge": "Водка вместо минералки", "soda": "Пиво вместо газировки", "jacket": "Чекушка в куртке",
				"ladder": "Лампочка подменена"}
			toast.emit(what.get(s.id, "Готово"), true)
			setup_line(s.id, 0.6)
		"trap":
			if traps.has(s.id):
				return
			if selected != s.item:
				toast.emit("Нужно: %s" % item_title(s.item), false)
				return
			hero.busy_act("swap", 1.0)
			_use_selected()
			traps[s.id] = true
			s.done = true
			game.show_trap(s.id, true)
			toast.emit("%s на полу. Смотри под ноги, сосед!" % item_title(s.item), true)
			setup_line(s.id, 0.5)

func _give(item: String) -> void:
	inventory.append(item)
	toast.emit("Взял: %s" % item_title(item), true)
	Settings.sfx("pickup", 0.6)
	Settings.sfx("grab", 0.8)
	if selected == "":
		selected = item
	inventory_changed.emit()

func _use_selected() -> void:
	inventory.erase(selected)
	selected = inventory[-1] if not inventory.is_empty() else ""
	inventory_changed.emit()

func select(item: String) -> void:
	selected = "" if selected == item else item
	inventory_changed.emit()

# ---------------------------------------------------------------- сосед пользуется вещами
func neighbor_use(id: String) -> void:
	if over:
		return
	match id:
		"wake":
			neighbor.wake_up()
		"mouthwash", "coffee", "soda", "jacket":
			_use_drink(id)
		"fridge", "detour":
			game.open_prop(game.spots["fridge"], 2.2)
			if swapped.has("fridge"):
				var first := not _scored.has("swap_fridge")
				_award("swap_fridge", 100, "Подмена: водка вместо минералки")
				Settings.sfx("drink", 0.6)
				if first:
					neighbor.react_seq([
						{"face": "tipsy", "clip": "drink", "t": 1.8, "item": "vodka"},
						{"face": "shock", "clip": "suspicious", "t": 1.6, "line": "Да как так нахуй?!", "sfx": "alert", "shake": 0.2},
						{"face": "suspicious", "clip": "suspicious", "t": 1.6, "line": "Это ж не минералка…"},
						{"face": "happy", "clip": "idle", "t": 2.0, "line": "Ну раз уж открыл…"},
						{"face": "happy", "clip": "dance", "t": 2.6, "line": "Эх, понеслась!", "item": ""},
					])
					gloat(3.0)
				else:
					neighbor.react_seq([
						{"face": "tipsy", "clip": "drink", "t": 2.2, "item": "vodka",
							"line": ["Ну ещё по одной…", "За ремонт!", "Последняя. Точно."].pick_random()},
					])
				if id == "detour" and _scored.has("rage"):
					_award("chain_grief", 150, "Цепочка «Сорвался с горя»")
				add_drunk(25)
			elif id == "detour":
				neighbor.react_seq([{"face": "normal", "clip": "drink", "t": 2.0, "item": "mineral_water", "line": "Минералочка… Успокоился."}])
			else:
				neighbor.react_seq([{"face": default_face(), "clip": "drink", "t": 2.0, "item": "mineral_water"}])
		"gamepad", "phone":
			if taken.has(id):
				_scored["rage"] = true
				_award("prank_" + id, 75, "Пакость: спрятан " + ("геймпад" if id == "gamepad" else "телефон"))
				neighbor.react_seq([
					{"face": "suspicious", "clip": "suspicious", "t": 1.8, "line": "Где геймпад?!" if id == "gamepad" else "Где телефон?!"},
					{"face": "suspicious", "clip": "suspicious", "t": 1.8, "line": "Я же его тут оставлял!"},
					{"face": "yell", "clip": "angry", "t": 2.4, "line": rage_line(), "shake": 0.3},
					{"face": "angry", "clip": "kick", "t": 2.2, "line": "Ну всё, я злой!", "sfx": "thud", "shake": 0.2},
				], _go_fridge)
				gloat(2.0)
			elif id == "phone" and stage() >= 2:
				neighbor.react_seq([
					{"face": "happy", "clip": "phone", "t": 1.6, "line": "Привет, откуда?"},
					{"face": "drunk", "clip": "kick", "t": 2.6, "line": "Смотри, как я могу! Кийя!"},
					{"face": "yell", "clip": "angry", "t": 2.4, "line": "Э, куда скипаешь?!", "shake": 0.2},
				], func():
					_scored["rage"] = true
					_award("chain_roulette", 150, "Цепочка «Звезда чат-рулетки»")
					gloat(0.2)
					_go_fridge())
			elif id == "phone":
				neighbor.say("Привет, откуда?", 2.0)
		"ladder":
			neighbor.climb_ladder()
			if swapped.has("ladder"):
				swapped.erase("ladder")
				game.spots["ladder"].done = false
				_award("prank_bulb", 75, "Пакость: перегоревшая лампочка")
				if stage() >= 2:
					_award("chain_electric", 150, "Цепочка «Электрик»")
					neighbor.react_seq([
						{"face": "drunk", "clip": "bulb", "t": 1.8, "item": "light_bulb_burnt"},
						{"face": "shock", "item": "", "clip": "fall_back", "t": 1.5, "fall": true, "sfx": "thud", "shake": 0.6, "line": "Уа-а-а!"},
						{"face": "yell", "clip": "lie_back", "t": 2.2, "line": "Да как так нахуй?!"},
						{"face": "drunk", "clip": "lie_back", "t": 1.8, "line": "Ой-ё-ёй… Спина моя…"},
						{"face": "drunk", "clip": "get_up", "t": 1.6},
						{"face": "yell", "clip": "angry", "t": 2.2, "line": "Кто лампочку подсунул?!", "shake": 0.25},
					], func():
						_scored["rage"] = true
						_go_fridge())
					gloat(3.0)
				else:
					neighbor.react_seq([
						{"face": "normal", "clip": "bulb", "t": 1.6, "item": "light_bulb_burnt"},
						{"face": "shock", "clip": "bulb", "t": 1.2, "sfx": "alert"},
						{"face": "yell", "clip": "angry", "t": 2.2, "line": "Опять перегорела?", "down": true, "item": "", "shake": 0.2},
						{"face": "angry", "clip": "angry", "t": 2.0, "line": "Да что ж такое-то, а?!"},
					])
					gloat(2.0)
			else:
				neighbor.react_seq([{"face": default_face(), "clip": "bulb", "t": 1.6, "item": "light_bulb"},
					{"face": default_face(), "clip": "idle", "t": 0.4, "item": "", "down": true}])
		"keys":
			if taken.has("keys"):
				_scored["rage"] = true
				_award("prank_keys", 75, "Пакость: спрятаны ключи")
				neighbor.react_seq([
					{"face": "suspicious", "clip": "suspicious", "t": 1.8, "line": "Где ключи?!"},
					{"face": "suspicious", "clip": "suspicious", "t": 1.6, "line": "Я же их в миску клал!"},
					{"face": "yell", "clip": "angry", "t": 2.2, "line": rage_line(), "shake": 0.3},
					{"face": "happy", "clip": "idle", "t": 2.4, "line": "…Ну раз дома — можно."},
				], _go_fridge)
				gloat(2.0)
		"balcony":
			if inventory.has("vodka") or swapped.has("fridge") or not game.spots["jars"].active:
				neighbor.react_seq([
					{"face": "suspicious", "clip": "suspicious", "t": 2.4, "line": "Э… А где моя заначка за банками?"},
					{"face": "angry", "clip": "angry", "t": 2.0, "line": "Домовой, что ли, завёлся?"},
				])

func _use_drink(id: String) -> void:
	if not swapped.has(id):
		if id == "jacket":
			return
		neighbor.react_seq([{"face": default_face(), "clip": "drink", "t": 2.0, "item": neighbor.hand_for(id)}])
		return
	var sw: Array = SWAPS[id]
	_award("swap_" + id, 100, "Подмена: " + game.spots[id].title)
	Settings.sfx("drink", 0.6)
	var seq: Array = []
	if id == "jacket":
		seq.append({"face": "suspicious", "clip": "suspicious", "t": 1.6, "line": "Опа… А это чё в кармане?"})
	seq.append({"face": default_face(), "clip": "drink", "t": 1.8, "item": neighbor.hand_for(id)})
	match id:
		"mouthwash":
			seq.append({"face": "shock", "clip": "suspicious", "t": 1.4, "sfx": "hiccup", "line": "Кхе-кхе! Это чё такое?!", "shake": 0.2})
		"coffee":
			seq.append({"face": "shock", "clip": "suspicious", "t": 1.4, "sfx": "hiccup", "line": "Кхм! Это кофе?!"})
		"soda":
			seq.append({"face": "tipsy", "clip": "idle", "t": 1.0, "sfx": "burp"})
	if id == "jacket" and taken.has("keys"):
		_award("chain_bread", 150, "Цепочка «За хлебом»")
	seq.append({"face": sw[2], "clip": "idle" if id != "jacket" else "oath", "t": 2.2, "line": sw[1], "item": ""})
	seq.append({"face": "happy", "clip": "dance" if id != "coffee" else "idle", "t": 2.2,
		"line": {"mouthwash": "А ничё так, освежает!", "coffee": "Ну и ладно, допью.",
			"soda": "Пивасик?! …Ну, раз налито.", "jacket": "За знакомство!"}[id]})
	neighbor.react_seq(seq)
	add_drunk(sw[0])
	gloat(2.4)
	if id in ["coffee", "soda", "jacket"]:
		swapped.erase(id)    # выпил — больше не сработает
		game.spots[id].done = false
		game.spots[id].active = id != "jacket"

## Сосед наступил на ловушку: поскользнулся, грохнулся, лежит и ругается, встаёт и ищет виноватого.
func trap_hit(id: String) -> void:
	if over or not traps.has(id):
		return
	traps.erase(id)
	game.show_trap(id, false)
	game.spots[id].done = false
	game.spots[id].active = false
	var soap := id == "soaptrap"
	_award("prank_" + id, 75, "Пакость: " + ("мыло на полу" if soap else "банановая кожура"))
	_scored["rage"] = true
	neighbor.react_seq([
		{"face": "shock", "clip": "fall_back", "t": 1.5, "fall": true, "sfx": "thud", "shake": 0.6, "line": "Оп-оп-оп… А-а-а!"},
		{"face": "yell", "clip": "lie_back", "t": 2.2, "line": "Твою ж… Кто мыло бросил?!" if soap else "Кто кожуру бросил?!"},
		{"face": "angry", "clip": "lie_back", "t": 1.8, "line": "Ой-ё-ёй… Спина моя…"},
		{"face": "angry", "clip": "get_up", "t": 1.6},
		{"face": "yell", "clip": "angry", "t": 2.2, "line": rage_line(), "shake": 0.3},
		{"face": "suspicious", "clip": "suspicious", "t": 2.0, "line": "Узнаю, кто это сделал — урою!"},
	])
	gloat(1.6)

func _go_fridge() -> void:
	if over:
		return
	neighbor.detour(9.45, 0, "идёт к холодильнику «успокоиться»", "detour")

# ---------------------------------------------------------------- финал
func _finale() -> void:
	if over:
		return
	over = true
	neighbor.finale(salad_on_table)
	await neighbor.finale_done
	if salad_on_table:
		_award("final_salad", 300, "Финал: лицом в салат!")
	# полюбоваться на соседа, потом камера — на героя: пляшет и подкалывает
	await get_tree().create_timer(2.2, false).timeout
	game.finale_hero = true
	hero.victory_dance()
	await get_tree().create_timer(1.0, false).timeout
	var d := hero.say("Так тебе, ветродуйка!", 2.4)
	await get_tree().create_timer(maxf(2.4, d + 0.5), false).timeout
	d = hero.say("И вот опять ты на бутылке!", 2.8)
	await get_tree().create_timer(maxf(3.2, d + 1.2), false).timeout
	finished.emit(true, "Сосед уснул" + (" лицом в салате!" if salad_on_table else ""))

func caught() -> void:
	catches += 1
	score = maxi(0, score - 100)
	if catches >= 3:
		over = true
		get_tree().create_timer(2.5, false).timeout.connect(func():
			finished.emit(false, "Сосед поймал тебя три раза"))

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
