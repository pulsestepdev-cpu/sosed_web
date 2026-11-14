class_name Rules3D
extends Node
## Правила дня (3D): тайники, подмены, пакости, ловушки, опьянение, цепочки, очки, реакции соседа
## и подколки героя. Что открыто в какой день и какие задания — scripts/levels/days.gd; дизайн — docs/WEEK_PLAN.md.
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
	"samogon":    ["Самогон",      "res://assets/props/drinks/drink_samogon.png"],
	"rods":       ["Удочки",       "res://assets/props/misc/misc_rods.png"],
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
	["dresser",   "stash", "dresser",         6.98, 1, "Комод",                  ""],
	["still",     "stash", "moonshine_still", 4.3, -1, "Самогонный аппарат",     ""],
	["kvass",     "swap",  "kvass_barrel",    6.2, -1, "Бочка с квасом",         "samogon"],
	["basement_jars", "stash", "cellar_shelf", 8.0, -1, "Закатки",               ""],
	["sacks",     "hide",  "potato_sacks",    9.6, -1, "За мешками",             ""],
	["workbench", "stash", "workbench",       11.1, -1, "Верстак",               ""],
	["car",       "hide",  "car",             14.9, -1, "За машиной",            ""],
	["rods",      "take",  "fishing_rods",    16.4, -1, "Удочки",                "rods"],
	["chest",     "stash", "old_chest",       4.3,  2, "Дедов сундук",           ""],
	["boxes",     "hide",  "attic_boxes",     5.9,  2, "За коробками",           ""],
	["brine",     "swap",  "pickle_jar",      9.0,  2, "Банка с рассолом",       "vodka"],
]

## Подмены: [опьянение, реплика, лицо после глотка]
const SWAPS := {
	"mouthwash": [20, "Ух… бодрит!", "tipsy"],
	"coffee":    [10, "Чё-то кофе сегодня крепкий…", "tipsy"],
	"fridge":    [25, "Да как так нахуй?!", "shock"],
	"soda":      [15, "Хм. А газировка-то с пеной…", "tipsy"],
	"jacket":    [20, "…Это знак.", "happy"],
	"kvass":     [20, "Ядрёный квасок… Ещё кружечку!", "tipsy"],
	"brine":     [20, "…Хотя от нервов — самое то.", "happy"],
}

const RAGE := ["Да ну нахуй!", "Да как так нахуй?!", "Да ну нахер, серьёзно?!", "Это чё за херня, нахуй?!",
	"Да вы издеваетесь, нахуй?!", "Ну ёпт твою налево!", "Ёб твою мать, опять?!", "Кто, блядь, тут шарится?!",
	"Да чтоб тебя через колено!", "Ну всё, пиздец котёнку!", "Я же завязал, ёпта!", "Кто подменил, тому пиздец!",
	"Сука, ну что за день такой?!", "Мать твою за ногу!"]
const TAUNTS := ["Пивная открывашка!", "Ветродуйка!", "Турбина перегарная!", "Пей до дна, открывашка!",
	"Давай-давай, ветродуйка!", "Закусывать будешь, бочка с перегаром?", "Твоё здоровье, ветродуйка!",
	"Трезвость — норма жизни. Но не сегодня!", "Пей, пока горячее, проспиртованный!", "Ещё по одной, гроза минералки!"]
## Подколки героя после того, как сосед отбушевал (герой ждёт, пока тот замолчит).
const GLOATS := ["Хе-хе, понеслась!", "Сорвался, ветродуйка!", "Ну и рожа, хе-хе!", "Опять на бутылке, открывашка!",
	"Красавчик, ёпта!", "Вот это я понимаю — завязал!", "Держись, турбина, держись!", "Ой, не могу! Ха-ха!",
	"Ну ты и синеглазка!", "Бросать — так красиво!", "Готовься к новой жизни с понедельника!", "Минус трезвость, плюс веселье!"]

## Герой говорит, пока подстраивает пакость (а не когда сосед попался — тогда говорит сосед):
## id места -> варианты реплики.
const SETUP_LINES := {
	"mouthwash": ["Пусть прополощет, ветродуйка!", "Освежись, турбина перегарная!", "Полощи горло, алкобаза!"],
	"coffee": ["Кофеёк с сюрпризом!", "Бодрящий, сука, кофеёк!", "Капучино по-нашему!"],
	"fridge": ["Минералочка, ага. Хе-хе.", "Пей минералку, бочка с перегаром!", "Водичка «Сорокаградусная»!"],
	"soda": ["Газировочка с пенкой!", "Пузырики подъехали, открывашка!"],
	"jacket": ["Сходит он за хлебом, как же!", "Хлебушка купишь, синеглазка? Хе-хе."],
	"ladder": ["Электрик, ты где? Хе-хе.", "Да будет свет! Ага, щас."],
	"peeltrap": ["Смотри под ноги, турбина перегарная!", "Банановый привет, ветродуйка!"],
	"soaptrap": ["Скользкого утречка, ветродуйка!", "Мыльная дорожка — прямо в люлю!"],
	"keys": ["Ключики теперь мои!", "Сиди дома, бродяга!"],
	"gamepad": ["Поиграл — и хватит!", "Геймер хренов, хе-хе."],
	"phone": ["Позвонишь потом, открывашка!", "Чат-рулетка закрыта, красавчик!"],
	"salad": ["Подушечка готова!", "Мордой в оливье — как положено!"],
	"kvass": ["Квасок с градусом, хе-хе!", "Это тебе не кефир, бродяга!", "Квас «Дедушкин рецепт»!"],
	"brine": ["Рассольчик тебе, синеглазка!", "Опохмелочка подъехала!", "Лечись, лечись, ветродуйка!"],
	"rods": ["Рыбалка отменяется, рыбак хренов!", "Ловить будешь белочку, а не карася!"],
}

## Утренняя клятва соседа по дням (две реплики: проснулся и чуть позже).
const OATHS := [
	["Всё, сегодня больше не пью!", "Не, вообще к пиву не тянет."],
	["Вторник. Разгрузочный день. Только кефир!", "Кефир — это тоже напиток. Почти."],
	["Среда. Гости не придут — и пить не с кем!", "Одному пить — это алкоголизм. А я не алкоголик!"],
	["Четверг. Ревизия погреба. Только огурцы считаю!", "Самогонный аппарат — память о деде. Не трогаю!"],
	["Пятница. Держусь. Я держусь, блядь!", "На рыбалку — только с чаем. Только с чаем, сука."],
	["Суббота. Генеральная уборка — и никакой синьки!", "Дедов хлам разберу — и спать. Трезвым!"],
	["Воскресенье. Завтра новая жизнь. А сегодня — репетиция!", "Последний день. Продержусь — и я человек!"],
]
## Победная реплика героя в конце дня (воскресенье — финал недели, см. _finale).
const DAY_WIN := ["Понедельник — день тяжёлый, ветродуйка!", "Разгрузился, ага. На пол-литра!",
	"Гости не придут? А мы и не звали!", "Погреб проверен. Самогон — тоже!",
	"Рыбалка удалась! Улов — сорок градусов!", "Генеральная уборка: мозги промыты рассолом!", ""]
const WEEK_FINALE := ["Ну что, ветродуйка, опять всю неделю пил не просыхал?",
	"В понедельник — «больше не пью», в воскресенье — лицом в салат. Стабильность!",
	"Семь дней, семь срывов. Рекорд подъезда, турбина перегарная!",
	"Завтра понедельник. Начнёшь новую жизнь, ага. Хе-хе."]
const FOUND := ["Опа, заначка!", "Ну-ка, ну-ка, что тут у нас?", "Конфискация, хе-хе!"]
## Герой у места подмены, а нужной вещи в сумке нет: предмет -> реплика (озвучены; прочие — «Сюда бы… …»).
const NEED_LINES := {
	"antifreeze": "Сюда бы незамерзайки…",
	"tincture": "Сюда бы настоечки…",
	"vodka": "Сюда бы водочки…",
	"beer": "Сюда бы пивка…",
	"chekushka": "Сюда бы чекушечку…",
	"bulb": "Сюда бы лампочку перегоревшую…",
	"samogon": "Сюда бы самогончику…",
}
## Герой заходит в гараж и видит красный мерин соседа: шок и зависть (game.gd: _car_envy).
const CAR_WOW := [
	"Нихуя себе! Пивная открывашка бухает, а тачка — огонь!",
	"Ветродуйка пьёт как не в себя, а мерин — люкс! Откуда, блять?!",
	"Откуда у пивной головы такая машина?! Я на маршрутке езжу!",
	"Сто двадцать четвёртый… Красный… Сука, завидую.",
	"Охренеть! Сам синий в хлам, а тачка блестит. Где справедливость?",
	"Печень в труху, а мерседес — как из салона. Бутылки оптом сдаёт, что ли?",
	"Я пашу как проклятый — у меня самокат. Он бухает — у него мерин. Ёб твою мать…",
	"Ох ты ж ёпт… Тачка — мечта. Хозяин — алкаш. Жизнь — несправедливая сука.",
]
## Герой прячется за машиной.
const CAR_HIDE := [
	"За мерином прятаться — как за бронёй!",
	"Хоть посижу рядом с нормальной тачкой…",
	"Пропил бы ты её — и прятаться было бы негде.",
]
## Поймал (1-й и 2-й раз): держит за шею и трясёт (Neighbor3D._shake_hero).
const GRAB_LINES := [
	"Ну что, тля, допрыгался, бля?!",
	"Попался, тля! Щас шею-то сверну!",
	"Чё ты тут лазишь, а?! Чё лазишь, бля?!",
	"Тля подъездная! Ещё раз увижу — урою!",
	"Ну что, сучёныш, весело тебе, а?!",
	"Я тебя, тля, научу по чужим квартирам шастать!",
]
## Герой, пока его душат.
const CHOKE_LINES := ["Кх-х… пусти, дядя…", "Хр-р… я за солью зашёл…", "Кхе… шея… шея!", "А-а… задушишь, ветродуйка!"]
## Третий раз — вертушка (Neighbor3D._kick_hero).
const KICK_BOAST := "Я пол жизни занимался спортом! Кикбоксинг, фул-контакт!"
const KICK_PLEAD := "Дядь… может, договоримся?"
const KO_LINES := ["Нокаут. Чисто.", "Фул-контакт, сынок!", "Вот так, тля. Вертушечка!"]
## Герой, когда его заметили (сосед бежит): оправдывается — если успеет до того, как схватят.
const CAUGHT_LINES := ["Ой-ой-ой!", "Ой, я за солью!", "Ошибся дверью, бывает!"]
## Герой, когда его отшвырнули (1-я и 2-я поимка).
const THROWN_LINES := ["Ай! Да за что?!", "Ай-ай, больно же, ветродуйка!"]
const GLOAT_HEH := "Хе-хе-хе…"          # злорадный смешок вместо молчаливого смеха
const WIN_NO_SALAD := "Готов, голубчик!"   # сосед уснул где стоял, без салата

const STAGES := ["Трезвый", "Чуть-чуть", "Весёлый", "Тренер", "В стельку", "Уснул"]
const STAGE_FROM := [0, 15, 35, 60, 85, 100]

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
var _last_drop := false
var _wait_salad := false        # все задания сделаны, ждём салат на столе

func setup(g: Node) -> void:
	game = g
	neighbor = g.neighbor
	hero = g.hero

## Задания дня для списка справа: [заголовок группы, ""] и [текст, ключ очков, условие].
func task_rows() -> Array:
	var out := []
	var day_tasks: Array = game.day["tasks"]
	for group in ["Подмены", "Пакости", "Финал"]:
		var rows := []
		for id in day_tasks:
			var t: Array = Days.TASKS[id]
			if t[4] == group:
				rows.append([t[0], t[1], t[2]])
		if not rows.is_empty():
			out.append([group, ""])
			out.append_array(rows)
	return out

## Максимум очков дня (все задания дня; цепочки — сверху, процент не больше 100).
func max_score() -> int:
	var m := 0
	for id in game.day["tasks"]:
		m += int(Days.TASKS[id][3])
	return maxi(1, m)

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

## raw — без поправки дня (отладка: --finale).
func add_drunk(v: float, raw := false) -> void:
	var before := stage()
	# всё сделано, салата ещё нет — сосед держится на ногах, пока салат не на столе (иначе одна рюмка
	# по дороге — и он уснёт где стоял, а салат так и не поставить)
	var top := 99.0 if _wait_salad and not salad_on_table else 100.0
	drunk = minf(drunk + v * (1.0 if raw else float(game.day["drink_k"])), top)
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
	_check_all_done.call_deferred()
	return true

## Все задания дня, кроме салата, засчитаны (сосед попался на каждую подставу).
func tasks_done() -> bool:
	for id in game.day["tasks"]:
		if id != "salad" and not _scored.has(Days.TASKS[id][1]):
			return false
	return true

## «Последняя капля»: выполнил всё — финал не ждёт, пока сосед ещё раз дойдёт до холодильника.
## Салат на столе — сосед дотрепывает реакцию, добирает до 100 % и идёт к салату. Салата ещё нет —
## сосед «в стельку» и ждёт: как только салат на столе, финал.
func _check_all_done() -> void:
	if over or _last_drop or not tasks_done():
		return
	if not salad_on_table:
		_wait_salad = true
		if drunk < STAGE_FROM[4]:
			add_drunk(STAGE_FROM[4] - drunk, true)
			toast.emit("Сосед готовенький — ставь салат на стол!", true)
			get_tree().create_timer(1.5, false).timeout.connect(func():
				if not over and not salad_on_table:
					hero.say("Готовенький! Теперь салатик ему на стол.", 2.4))
		return
	_last_drop = true
	var wait := 0.0
	while wait < 14.0 and neighbor.mode == "react":     # дать доругаться / допить
		await get_tree().create_timer(0.25, false).timeout
		wait += 0.25
	if over:
		return
	toast.emit("Последняя капля! Сосед готов", true)
	add_drunk(100.0, true)

## Герой злорадствует, пока сосед бушует: смеётся молча (говорит в это время сосед).
func gloat(delay := 1.2) -> void:
	get_tree().create_timer(delay, false).timeout.connect(func():
		if over and not salad_on_table and drunk < 100.0:
			return
		var r := randf()
		hero.gloat(GLOATS.pick_random() if r < 0.55 else (GLOAT_HEH if r < 0.75 else "")))

## Реплика героя, когда он подстраивает пакость.
func setup_line(id: String, delay := 0.5) -> void:
	var line: String = (SETUP_LINES[id] as Array).pick_random() if SETUP_LINES.has(id) else TAUNTS[_taunt_i % TAUNTS.size()]
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
			if s.id == "table" and inventory.has("salad"):
				return "Стол — поставить салат"
			return "%s — спрятаться" % s.title
		"swap":
			if swapped.has(s.id):
				return "%s — уже подменено" % s.title
			if inventory.has(s.item):
				return "%s — подложить: %s" % [s.title, item_title(s.item)]
			return "%s — нужно: %s" % [s.title, item_title(s.item)]
		"trap":
			if traps.has(s.id):
				return "%s — ловушка готова" % s.title
			if inventory.has(s.item):
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
			if s.id == "table" and inventory.has("salad"):
				selected = "salad"
				hero.busy_act("swap", 1.0)
				_use_selected()
				salad_on_table = true
				game.place_salad()
				toast.emit("Салат на столе. Ждём финала…", true)
				setup_line("salad")
				_check_all_done()
				return
			hero.hide_in(s)
		"swap":
			if swapped.has(s.id):
				return
			if selected != s.item and inventory.has(s.item):
				selected = s.item
			if selected != s.item:
				toast.emit("Нужно: %s" % item_title(s.item), false)
				hero.say(NEED_LINES.get(s.item, "Сюда бы… %s." % item_title(s.item).to_lower()), 2.0)
				return
			hero.busy_act("swap", 1.4)
			game.open_prop(s, 1.5)
			Settings.sfx("swap", 0.6)
			_use_selected()
			swapped[s.id] = true
			s.done = true
			var what := {"mouthwash": "Незамерзайка вместо ополаскивателя", "coffee": "Настойка в кофе",
				"fridge": "Водка вместо минералки", "soda": "Пиво вместо газировки", "jacket": "Чекушка в куртке",
				"ladder": "Лампочка подменена", "kvass": "Самогон в бочке с квасом", "brine": "Водка вместо рассола"}
			toast.emit(what.get(s.id, "Готово"), true)
			setup_line(s.id, 0.6)
		"trap":
			if traps.has(s.id):
				return
			if selected != s.item and inventory.has(s.item):
				selected = s.item
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
		"mouthwash", "coffee", "soda", "jacket", "kvass", "brine":
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
		"rods":
			if taken.has("rods"):
				_scored["rage"] = true
				_award("prank_rods", 75, "Пакость: спрятаны удочки")
				neighbor.react_seq([
					{"face": "suspicious", "clip": "suspicious", "t": 1.8, "line": "Где удочки?!"},
					{"face": "suspicious", "clip": "suspicious", "t": 1.8, "line": "Я их тут ставил, сука!"},
					{"face": "yell", "clip": "angry", "t": 2.4, "line": rage_line(), "shake": 0.3},
					{"face": "angry", "clip": "kick", "t": 2.2, "line": "Рыбалка накрылась… Ну и хрен с ней!", "sfx": "thud", "shake": 0.2},
				], _go_fridge)
				gloat(2.0)
			else:
				neighbor.say(["Удочки на месте. Червей бы ещё…", "Карась, жди меня!"].pick_random(), 2.4)
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
			# сначала шагами на стремянку лицом к ней (шаг climb), потом — лампочка
			var climb := {"face": default_face(), "clip": "walk", "t": 0.6, "climb": true}
			if swapped.has("ladder"):
				swapped.erase("ladder")
				game.spots["ladder"].done = false
				_award("prank_bulb", 75, "Пакость: перегоревшая лампочка")
				if stage() >= 2:
					_award("chain_electric", 150, "Цепочка «Электрик»")
					neighbor.react_seq([climb,
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
					neighbor.react_seq([climb,
						{"face": "normal", "clip": "bulb", "t": 1.6, "item": "light_bulb_burnt"},
						{"face": "shock", "clip": "bulb", "t": 1.2, "sfx": "alert"},
						{"face": "yell", "clip": "angry", "t": 2.2, "line": "Опять перегорела?", "down": true, "item": "", "shake": 0.2},
						{"face": "angry", "clip": "angry", "t": 2.0, "line": "Да что ж такое-то, а?!"},
					])
					gloat(2.0)
			else:
				neighbor.react_seq([climb, {"face": default_face(), "clip": "bulb", "t": 1.6, "item": "light_bulb"},
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
			if game.spots.has("jars") and (inventory.has("vodka") or swapped.has("fridge") or not game.spots["jars"].active):
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
		"kvass":
			seq.append({"face": "shock", "clip": "suspicious", "t": 1.4, "sfx": "hiccup", "line": "Кхе! Это чё за квас такой?!", "shake": 0.15})
		"brine":
			seq.append({"face": "shock", "clip": "suspicious", "t": 1.4, "sfx": "hiccup", "line": "Тьфу! Рассол водкой пахнет!", "shake": 0.15})
		"soda":
			seq.append({"face": "tipsy", "clip": "idle", "t": 1.0, "sfx": "burp"})
	if id == "jacket" and taken.has("keys"):
		_award("chain_bread", 150, "Цепочка «За хлебом»")
	seq.append({"face": sw[2], "clip": "idle" if id != "jacket" else "oath", "t": 2.2, "line": sw[1], "item": ""})
	seq.append({"face": "happy", "clip": "dance" if id != "coffee" else "idle", "t": 2.2,
		"line": {"mouthwash": "А ничё так, освежает!", "coffee": "Ну и ладно, допью.",
			"soda": "Пивасик?! …Ну, раз налито.", "jacket": "За знакомство!", "kvass": "Ну и хрен с ним, раз уж налито…",
			"brine": "Эх, понеслась душа в рай!"}[id]})
	neighbor.react_seq(seq)
	add_drunk(sw[0])
	gloat(2.4)
	if id in ["coffee", "soda", "jacket", "kvass"]:
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
		{"face": "yell", "clip": "lie_back", "t": 2.2, "line": ("Твою ж… Кто мыло бросил?!" if soap else "Кто кожуру бросил?!") if randf() < 0.6 else "Мать твою за ногу, пол скользкий!"},
		{"face": "angry", "clip": "lie_back", "t": 1.8, "line": ["Ой-ё-ёй… Спина моя…", "А-а-а, моя спина, блядь!"].pick_random()},
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
	var lines: Array = ["Так тебе, ветродуйка!", "И вот опять ты на бутылке!"]
	var n: int = game.day_n
	if n == 7:
		lines = WEEK_FINALE.duplicate()
	elif DAY_WIN[n - 1] != "":
		lines = [DAY_WIN[n - 1], "И вот опять ты на бутылке!"]
	if n != 7 and not salad_on_table:
		lines.push_front(WIN_NO_SALAD)
	for i in lines.size():
		var d := hero.say(lines[i], 2.6)
		await get_tree().create_timer(maxf(2.6, d + 0.6), false).timeout
	if n == 7:   # сосед сквозь сон
		var d2 := neighbor.say("Всё… с понедельника… завязываю…", 3.0)
		await get_tree().create_timer(maxf(3.0, d2 + 0.8), false).timeout
	await get_tree().create_timer(0.6, false).timeout
	finished.emit(true, "Сосед уснул" + (" лицом в салате!" if salad_on_table else ""))

func caught() -> void:
	catches += 1
	score = maxi(0, score - 100)
	if catches >= 3:          # итоги — после вертушки (Game3D._catch); страховка — если сцена не доиграла
		over = true
		get_tree().create_timer(16.0, false).timeout.connect(fail_caught)

var _fail_sent := false
func fail_caught() -> void:
	if _fail_sent:
		return
	_fail_sent = true
	finished.emit(false, "Сосед поймал тебя три раза")

func time_up() -> void:
	if over:
		return
	if _wait_salad:          # всё сделал, салат не поставил — сосед засыпает к вечеру (победа без салата)
		_finale()
		return
	over = true
	finished.emit(false, "Наступил вечер, а сосед всё ещё на ногах")

func shame_percent() -> int:
	return clampi(roundi(100.0 * score / max_score()), 0, 100)

func shame_title() -> String:
	var p := shame_percent()
	if p >= 90: return "Легенда подъезда"
	if p >= 60: return "В синьку"
	if p >= 30: return "Сорвался"
	return "Держится, зараза"
