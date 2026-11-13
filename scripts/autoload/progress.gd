extends Node
## Прогресс недели: выбранный день, пройденные дни и лучшие результаты. Хранится в user://progress.cfg
## (в браузере Godot кладёт его в IndexedDB). Дни открываются строго по порядку: следующий — после победы
## в предыдущем; пройденные можно переиграть.
## Отладка: --unlock-all (все дни открыты), --reset-progress (начать неделю заново).

const PATH := "user://progress.cfg"

var day := 1                 # какой день сейчас играем / выбран на экране недели
var best := {}               # номер дня -> {"percent": int, "score": int, "catches": int}
var open_week := false       # вернуться из игры сразу на экран недели
var show_week_results := false   # после воскресенья — показать итоги недели
var _unlock_all := false

func _ready() -> void:
	var args := Settings.debug_args()
	_unlock_all = args.has("unlock-all")
	if args.has("reset-progress"):
		best.clear()
		save()
	else:
		_load()
	day = next_day()

func is_done(n: int) -> bool:
	return best.has(n)

func unlocked(n: int) -> bool:
	return n == 1 or _unlock_all or best.has(n - 1)

## Первый непройденный день (или воскресенье, если неделя пройдена).
func next_day() -> int:
	for n in range(1, 8):
		if not best.has(n):
			return n
	return 7

func week_done() -> bool:
	for n in range(1, 8):
		if not best.has(n):
			return false
	return true

## День пройден: запомнить лучший результат.
func complete(n: int, percent: int, score: int, catches: int) -> void:
	var old: Dictionary = best.get(n, {})
	if old.is_empty() or percent > int(old.get("percent", 0)) or (percent == int(old.get("percent", 0)) and score > int(old.get("score", 0))):
		best[n] = {"percent": percent, "score": score, "catches": catches}
	save()

func average_percent() -> int:
	if best.is_empty():
		return 0
	var s := 0
	for n in best:
		s += int(best[n]["percent"])
	return roundi(float(s) / 7.0)

func week_title() -> String:
	var p := average_percent()
	if p >= 85: return "Легенда подъезда"
	if p >= 60: return "Синяя неделя"
	if p >= 35: return "Сорвался по полной"
	return "Держится, зараза"

func save() -> void:
	var c := ConfigFile.new()
	for n in best:
		var b: Dictionary = best[n]
		c.set_value("day_%d" % n, "percent", b["percent"])
		c.set_value("day_%d" % n, "score", b["score"])
		c.set_value("day_%d" % n, "catches", b["catches"])
	c.save(PATH)

func _load() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	for n in range(1, 8):
		var sec := "day_%d" % n
		if c.has_section(sec):
			best[n] = {"percent": int(c.get_value(sec, "percent", 0)), "score": int(c.get_value(sec, "score", 0)),
				"catches": int(c.get_value(sec, "catches", 0))}
