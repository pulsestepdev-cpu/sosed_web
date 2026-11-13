class_name Days
extends RefCounted
## Неделя соседа: 7 дней (Пн–Вс). Сложность растёт за счёт дома и заданий — больше комнат, этажей, тайников,
## предметы лежат дальше от мест, где их подкладывать. Скорость, обзор и реакция соседа одинаковые во всех днях.
## План — docs/WEEK_PLAN.md. Сцена дня собирается tools/build_level_3d.gd → scenes/levels/day_N.tscn.
##
## Дом (вид в разрезе, X — вдоль дома, этажи по 3.05 м):
##   этаж  2: [         чердак (3..17)                    ]
##   этаж  1: [лестн.][ванная][спальня][балкон ][лестн.]
##   этаж  0: [лестн.][прихожая][кухня][зал    ][лестн.]
##   этаж -1: [  подвал (0..10.4)       ][гараж (10.4..17)]
## Подвал — через дверь под левой лестницей, чердак — через дверь с площадки правой лестницы.

const FH := 3.05                 # шаг этажей
const LANE := -1.0

## Комнаты: id -> [x0, x1, этаж, обои, пол, название]
const ROOMS := {
	"hallway":  [3.0, 7.0, 0, "wall_hall", "floor_carpet", "Прихожая"],
	"kitchen":  [7.0, 10.4, 0, "wall_kitchen", "floor_kitchen", "Кухня"],
	"living":   [10.4, 14.0, 0, "wall_living", "floor_parquet", "Зал"],
	"bathroom": [3.0, 6.4, 1, "wall_bath", "floor_bath", "Ванная"],
	"bedroom":  [6.4, 10.4, 1, "wall_bedroom", "floor_parquet", "Спальня"],
	"balcony":  [10.4, 14.0, 1, "brick", "floor_balcony", "Балкон"],
	"basement": [0.0, 10.4, -1, "wall_basement", "floor_concrete", "Подвал"],
	"garage":   [10.4, 17.0, -1, "wall_garage", "floor_garage", "Гараж"],
	"attic":    [3.0, 17.0, 2, "wall_attic", "floor_attic", "Чердак"],
}

## Двери-переходы: зашёл в дверь на одном этаже — вышел из парной на другом. Путь — от дорожки этажа A до
## дорожки этажа B; точка с x = TP — «телепорт» (персонаж скрылся в двери A и появился в двери B).
const TP := 1.0e9
const PORTALS := {
	"cellar": {"needs": "basement", "a": 0, "b": -1, "title_a": "Подвал", "title_b": "Наверх",
		"door_a": Vector3(1.75, 0.0, -4.0), "door_b": Vector3(1.75, -FH, -4.0),
		"path": [Vector3(3.25, 0.0, -1.0), Vector3(2.98, 0.0, -1.62), Vector3(2.2, 0.0, -2.2), Vector3(1.75, 0.0, -2.6),
			Vector3(1.75, 0.0, -3.72), Vector3(TP, 0, 0), Vector3(1.75, -FH, -3.72), Vector3(1.75, -FH, -1.0)]},
	"attic": {"needs": "attic", "a": 1, "b": 2, "title_a": "Чердак", "title_b": "Вниз",
		"door_a": Vector3(15.5, FH, -4.0), "door_b": Vector3(15.5, FH * 2.0, -4.0),
		"path": [Vector3(13.3, FH, -1.0), Vector3(13.65, FH, -2.15), Vector3(14.1, FH, -2.2), Vector3(14.75, FH, -3.0),
			Vector3(15.5, FH, -3.72), Vector3(TP, 1, 0), Vector3(15.5, FH * 2.0, -3.72), Vector3(15.5, FH * 2.0, -1.0)]},
}

## Задания: id -> [текст в списке, ключ очков, условие «подложено», очки, группа]
const TASKS := {
	"mouthwash": ["Незамерзайка в ополаск.", "swap_mouthwash", "sw:mouthwash", 100, "Подмены"],
	"coffee":    ["Настойка в кофе", "swap_coffee", "sw:coffee", 100, "Подмены"],
	"fridge":    ["Водка вместо минералки", "swap_fridge", "sw:fridge", 100, "Подмены"],
	"soda":      ["Пиво вместо газировки", "swap_soda", "sw:soda", 100, "Подмены"],
	"jacket":    ["Чекушка в куртку", "swap_jacket", "sw:jacket", 100, "Подмены"],
	"kvass":     ["Самогон в квас", "swap_kvass", "sw:kvass", 100, "Подмены"],
	"brine":     ["Водка вместо рассола", "swap_brine", "sw:brine", 100, "Подмены"],
	"gamepad":   ["Спрятать геймпад", "prank_gamepad", "tk:gamepad", 75, "Пакости"],
	"phone":     ["Спрятать телефон", "prank_phone", "tk:phone", 75, "Пакости"],
	"keys":      ["Спрятать ключи", "prank_keys", "tk:keys", 75, "Пакости"],
	"rods":      ["Спрятать удочки", "prank_rods", "tk:rods", 75, "Пакости"],
	"ladder":    ["Перегоревшая лампочка", "prank_bulb", "sw:ladder", 75, "Пакости"],
	"peeltrap":  ["Кожура у холодильника", "prank_peeltrap", "tr:peeltrap", 75, "Пакости"],
	"soaptrap":  ["Мыло у раковины", "prank_soaptrap", "tr:soaptrap", 75, "Пакости"],
	"salad":     ["Салат на стол", "final_salad", "salad", 300, "Финал"],
}

## Сколько пьянит одна порция в этот день: в поздние дни соседа «берёт» хуже — нужно больше подстав
## (сложность — через количество заданий, а не через скорость или зоркость соседа).
const DRINK_K := [1.0, 1.0, 0.95, 0.85, 0.8, 0.75, 0.7]

const NAMES := ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
const SHORT := ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

## Распорядок: [x, этаж, что делает, клип, использует, куда смотрит, секунд на месте, z (необяз.)]
const SLEEP := [8.4, 1, "спит", "sleep", "", "front", 0]
const WAKE := [9.35, 1, "проснулся", "idle", "wake", "front", 6]
const P_TEETH := [4.92, 1, "чистит зубы", "work", "mouthwash", "back", 10]
const P_WASH := [4.92, 1, "умывается", "work", "mouthwash", "back", 9]
const P_COFFEE := [8.3, 0, "пьёт кофе", "idle", "coffee", "back", 10]
const P_PUTTY := [9.85, 1, "шпаклюет стену", "work", "", "back", 13, -3.25]
const P_FRIDGE := [9.45, 0, "пьёт минералку", "idle", "fridge", "back", 8]
const P_DINNER := [9.45, 0, "ужинает", "idle", "fridge", "back", 10]
const P_GAME := [12.75, 0, "играет в приставку", "game", "gamepad", "tv", 13]
const P_AIR := [12.0, 1, "дышит воздухом", "idle", "balcony", "back", 10]
const P_STASH := [12.0, 1, "проверяет заначку", "idle", "balcony", "back", 9]
const P_BULB := [6.0, 0, "меняет лампочку", "bulb", "ladder", "front", 3]
const P_SODA := [13.05, 0, "пьёт газировку", "idle", "soda", "back", 7]
const P_ROULETTE := [11.1, 0, "сидит в чат-рулетке", "phone", "phone", "front", 14]
const P_BREAD := [5.45, 0, "собирается за хлебом", "idle", "jacket", "back", 8]
const P_KEYS := [4.62, 0, "ищет ключи", "suspicious", "keys", "back", 8]
const P_JARS := [8.0, -1, "проверяет закатки", "work", "", "back", 10]
const P_KVASS := [6.2, -1, "пьёт квас", "idle", "kvass", "back", 8]
const P_CAR := [12.3, -1, "чинит машину", "work", "", "back", 14]
const P_RODS := [16.4, -1, "собирает удочки", "suspicious", "rods", "back", 8]
const P_JUNK := [6.6, 2, "разбирает хлам", "work", "", "back", 12]
const P_BRINE := [9.0, 2, "пьёт рассол", "idle", "brine", "back", 8]
const P_PIGEONS := [12.6, 2, "смотрит на голубей", "idle", "", "back", 9]

## Дни. rooms — открытые комнаты; w — длина дома (10.4 — без зала, 14 — без правой лестницы, 17 — весь);
## items — какие тайники открыты и что в них лежит; tasks — задания дня; plan/loop — распорядок соседа.
static func day(n: int) -> Dictionary:
	n = clampi(n, 1, 7)
	var d: Dictionary = _DAYS[n - 1].duplicate(true)
	d["n"] = n
	d["day_name"] = NAMES[n - 1]
	d["short"] = SHORT[n - 1]
	d["scene"] = "res://scenes/levels/day_%d.tscn" % n
	d["drink_k"] = DRINK_K[n - 1]
	return d

const _DAYS := [
	{   # Пн — 4 комнаты, одна лестница, 6 заданий
		"title": "Больше не пью",
		"rooms": ["hallway", "kitchen", "bathroom", "bedroom"], "w": 10.4,
		"items": {"toilet": "tincture", "sink": "antifreeze", "dresser": "vodka", "boots": "chekushka",
			"fruit": "banana", "salad": "salad"},
		"tasks": ["mouthwash", "coffee", "fridge", "jacket", "peeltrap", "salad"],
		"plan": [SLEEP, WAKE, P_TEETH, P_COFFEE, P_PUTTY, P_FRIDGE, P_BREAD, P_BULB, P_WASH, P_COFFEE, P_PUTTY,
			P_FRIDGE, P_BREAD, P_WASH, P_DINNER],
		"loop": 3,
		"intro": "Сосед в очередной раз завязал и пока спит. До 20:00 доведи его до финала — чтобы уснул (а лучше — лицом в салате).",
		"hint": "• Шарь по заначкам (жёлтые кружки) и подменяй напитки, пока он не видит.\n• Кожура у холодильника — пусть звереет.\n• Прячься (голубые кружки) и крадись (ПКМ/Shift) — шаги слышно.\n• Поймает 3 раза — провал.",
	},
	{   # Вт — +зал, 7 заданий
		"title": "Разгрузочный день",
		"rooms": ["hallway", "kitchen", "living", "bathroom", "bedroom"], "w": 14.0,
		"items": {"toilet": "beer", "sink": "antifreeze", "dresser": "vodka", "boots": "tincture",
			"fruit": "banana", "salad": "salad"},
		"tasks": ["mouthwash", "coffee", "fridge", "soda", "gamepad", "peeltrap", "salad"],
		"plan": [SLEEP, WAKE, P_TEETH, P_COFFEE, P_PUTTY, P_FRIDGE, P_GAME, P_BULB, P_WASH, P_SODA, P_PUTTY,
			P_COFFEE, P_FRIDGE, P_GAME, P_SODA, P_WASH, P_DINNER],
		"loop": 3,
		"intro": "Вторник. У соседа «разгрузочный день» — только кефир и приставка. Разгрузим его как следует.",
		"hint": "• Новая комната — зал: приставка и газировка.\n• Спрячешь геймпад — сосед озвереет и пойдёт «успокаиваться» к холодильнику.",
	},
	{   # Ср — вся квартира (+балкон, вторая лестница), 8 заданий
		"title": "Гости не придут",
		"rooms": ["hallway", "kitchen", "living", "bathroom", "bedroom", "balcony"], "w": 17.0,
		"items": {"toilet": "beer", "sink": "tincture", "soapdish": "soap", "jars": "vodka", "canisters": "antifreeze",
			"toolbox": "bulb", "boots": "chekushka", "fruit": "banana", "salad": "salad"},
		"tasks": ["mouthwash", "fridge", "soda", "phone", "keys", "ladder", "soaptrap", "salad"],
		"plan": [SLEEP, WAKE, P_TEETH, P_COFFEE, P_PUTTY, P_FRIDGE, P_GAME, P_AIR, P_BULB, P_WASH, P_SODA, P_PUTTY,
			P_COFFEE, P_ROULETTE, P_BREAD, P_KEYS, P_BULB, P_STASH, P_FRIDGE, P_WASH, P_GAME, P_PUTTY, P_SODA, P_DINNER],
		"loop": 3,
		"intro": "Среда. Гости не придут — значит, и пить не с кем, решил сосед. Открыт балкон с его заначками.",
		"hint": "• На балконе — банки, канистра и ящик с инструментами.\n• Перегоревшая лампочка на стремянке: пьяный электрик падает эффектнее.",
	},
	{   # Чт — +подвал (дверь под левой лестницей), 9 заданий
		"title": "Ревизия погреба",
		"rooms": ["hallway", "kitchen", "living", "bathroom", "bedroom", "balcony", "basement"], "w": 17.0,
		"items": {"still": "samogon", "jars": "vodka", "boots": "chekushka", "sink": "tincture", "toolbox": "bulb",
			"soapdish": "soap", "toilet": "beer", "salad": "salad"},
		"tasks": ["coffee", "fridge", "jacket", "keys", "gamepad", "ladder", "soaptrap", "kvass", "salad"],
		"plan": [SLEEP, WAKE, P_TEETH, P_COFFEE, P_JARS, P_FRIDGE, P_GAME, P_KVASS, P_BULB, P_WASH, P_PUTTY,
			P_BREAD, P_KEYS, P_JARS, P_COFFEE, P_KVASS, P_GAME, P_BULB, P_FRIDGE, P_WASH, P_KVASS, P_DINNER],
		"loop": 3,
		"intro": "Четверг. Сосед полез в погреб «проверить закатки». В подвал ведёт дверь под лестницей — зашёл тут, вышел там.",
		"hint": "• Дверь под левой лестницей — в подвал (и обратно).\n• В подвале самогонный аппарат и бочка с квасом. Сосед любит квасок…",
	},
	{   # Пт — +гараж (из подвала), 10 заданий
		"title": "Рыбалка отменяется",
		"rooms": ["hallway", "kitchen", "living", "bathroom", "bedroom", "balcony", "basement", "garage"], "w": 17.0,
		"items": {"workbench": "antifreeze", "toilet": "beer", "sink": "tincture", "basement_jars": "vodka",
			"boots": "chekushka", "fruit": "banana", "still": "samogon", "salad": "salad"},
		"tasks": ["mouthwash", "coffee", "fridge", "soda", "jacket", "keys", "phone", "peeltrap", "rods", "salad"],
		"plan": [SLEEP, WAKE, P_TEETH, P_COFFEE, P_CAR, P_FRIDGE, P_RODS, P_GAME, P_SODA, P_KVASS, P_ROULETTE,
			P_WASH, P_BREAD, P_KEYS, P_CAR, P_COFFEE, P_RODS, P_FRIDGE, P_SODA, P_WASH, P_DINNER],
		"loop": 3,
		"intro": "Пятница. Сосед собрался на рыбалку — «только чай в термосе». Гараж — за подвалом.",
		"hint": "• Гараж открыт: верстак, машина, удочки.\n• Нет удочек — нет рыбалки. А с горя сосед идёт к холодильнику…",
	},
	{   # Сб — +чердак (дверь с площадки правой лестницы), 11 заданий
		"title": "Генеральная уборка",
		"rooms": ["hallway", "kitchen", "living", "bathroom", "bedroom", "balcony", "basement", "garage", "attic"], "w": 17.0,
		"items": {"canisters": "antifreeze", "jars": "vodka", "toilet": "beer", "workbench": "chekushka",
			"toolbox": "bulb", "soapdish": "soap", "still": "samogon", "chest": "vodka", "salad": "salad"},
		"tasks": ["mouthwash", "fridge", "soda", "jacket", "gamepad", "ladder", "soaptrap", "kvass", "rods", "brine", "salad"],
		"plan": [SLEEP, WAKE, P_TEETH, P_JUNK, P_COFFEE, P_FRIDGE, P_KVASS, P_GAME, P_BRINE, P_SODA, P_BREAD,
			P_CAR, P_RODS, P_BULB, P_PIGEONS, P_WASH, P_JUNK, P_FRIDGE, P_KVASS, P_BRINE, P_SODA, P_DINNER],
		"loop": 3,
		"intro": "Суббота. Генеральная уборка: сосед полез на чердак разбирать дедов хлам. Дверь на чердак — с площадки правой лестницы.",
		"hint": "• Чердак: дедов сундук и банка рассола — сосед лечится им «от нервов».\n• Двери-переходы — ещё и способ уйти от соседа.",
	},
	{   # Вс — весь дом, 12 заданий, финал недели
		"title": "Последний шанс",
		"rooms": ["hallway", "kitchen", "living", "bathroom", "bedroom", "balcony", "basement", "garage", "attic"], "w": 17.0,
		"items": {"canisters": "antifreeze", "sink": "tincture", "jars": "vodka", "workbench": "chekushka",
			"toolbox": "bulb", "fruit": "banana", "still": "samogon", "chest": "vodka", "boots": "beer", "salad": "salad"},
		"tasks": ["mouthwash", "coffee", "fridge", "jacket", "phone", "keys", "ladder", "peeltrap", "kvass", "rods", "brine", "salad"],
		"plan": [SLEEP, WAKE, P_TEETH, P_COFFEE, P_JUNK, P_FRIDGE, P_KVASS, P_ROULETTE, P_BRINE, P_BREAD, P_KEYS,
			P_CAR, P_RODS, P_BULB, P_WASH, P_COFFEE, P_JARS, P_FRIDGE, P_BRINE, P_KVASS, P_BULB, P_DINNER],
		"loop": 3,
		"intro": "Воскресенье. Последний шанс соседа начать новую жизнь с понедельника. Не дадим ему этого шанса.",
		"hint": "• Весь дом открыт: подвал, гараж, чердак.\n• Предметы лежат далеко от мест, где они нужны, — планируй маршрут.",
	},
]

## Номер этажа по высоте точки (этаж -1 — подвал, 2 — чердак).
static func floor_of_y(y: float) -> int:
	return floori((y + 1.45) / FH)
