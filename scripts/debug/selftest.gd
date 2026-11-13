class_name QaSelfTest
extends Node
## Самопроверка правил и кликов (без бота: бот выбирает места напрямую и не «кликает» мышью).
##   Godot.exe --path . res://scenes/game.tscn -- --day=N --autostart --selftest
## Печатает «SELFTEST ok/FAIL …», в конце «SELFTEST PASS» или «SELFTEST FAILED n» и закрывает игру (код 0/1).
##
## 1) Клики у кухонного стола: на столе кружка кофе и ваза, их кружки-метки рядом с меткой стола. С салатом
##    в сумке (даже если выбрана другая вещь) клик по столу, по кружке, по вазе, между метками — «стол»;
##    точно в кружок-метку кофе — всё же кофе. Без салата метки работают как раньше.
## 2) Салат ставится, даже если в сумке выбран не он (раньше герой лез под стол).
## 3) «Последняя капля»: все задания дня засчитаны, салата нет — сосед «в стельку» и ждёт; салат на стол —
##    финал (лицом в салат), не дожидаясь, пока сосед ещё раз выпьет.

var game: Node
var fails := 0

func setup(g: Node) -> void:
	game = g
	_run.call_deferred()

func _ok(cond: bool, what: String) -> void:
	print("SELFTEST %s  %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, false).timeout

func _id(s: Spot3D) -> String:
	return s.id if s else "-"

func _marker(id: String) -> Vector2:
	return game.cam.unproject_position(game.spots[id].marker_pos())

func _center(id: String) -> Vector2:
	return game.screen_rect(game.spots[id].aabb).get_center()

func _run() -> void:
	await _wait(1.0)
	var r: Rules3D = game.rules
	game.neighbor.set_process(false)          # сосед спит и не мешает (распорядок не идёт)
	game.time_scale = 0.0
	for zoom in [false, true]:
		game.zoomed = zoom
		if zoom:
			game.hero.position = game.lane_point(8.7, 0)
			game.center_on_hero()
		await _wait(1.6)                      # камера доехала
		var tag := "крупно" if zoom else "общий план"
		# без салата: метки как раньше
		r.inventory.clear()
		r.selected = ""
		# что стоит на столе в этот день (кружка кофе и ваза есть не во все дни)
		var near: Array = ["coffee", "fruit"].filter(func(id): return game.spots.has(id))
		_ok(_id(game._spot_at(_marker("table"))) == "table", "%s, без салата: метка стола → стол" % tag)
		for id in near:
			_ok(_id(game._spot_at(_marker(id))) == id, "%s, без салата: метка %s → %s" % [tag, id, id])
		# салат в сумке, выбрана другая вещь
		r.inventory.assign(["salad", "banana"])
		r.selected = "banana"
		var mt := _marker("table")
		var pts := [["метка стола", mt], ["середина стола", _center("table")], ["чуть ниже метки стола", mt + Vector2(0, 22)]]
		for id in near:
			pts.append_array([[id + " (сам предмет)", _center(id)], ["между метками стола и " + id, (mt + _marker(id)) * 0.5]])
		for p in pts:
			var got := _id(game._spot_at(p[1]))
			_ok(got == "table", "%s, салат в сумке: %s → %s" % [tag, p[0], got])
		if not Settings.is_touch():    # пальцем в кружок 10 пикселей не попасть — на телефоне с салатом всё ведёт к столу
			for id in near:
				_ok(_id(game._spot_at(_marker(id) + Vector2(3, 2))) == id, "%s, салат в сумке: точно в метку %s → %s" % [tag, id, id])
		_ok(r.describe(game.spots["table"]) == "Стол — поставить салат", "%s: подсказка «поставить салат»" % tag)
	game.zoomed = false
	# салат ставится, хотя выбрана кожура
	r.inventory.assign(["salad", "banana"])
	r.selected = "banana"
	game.hero.position = game.spots["table"].walk
	r.hero_use(game.spots["table"])
	await _wait(0.3)
	_ok(r.salad_on_table, "салат на столе, хотя в руке была кожура")
	_ok(not game.hero.in_hiding, "герой не полез под стол")
	_ok(not r.inventory.has("salad") and r.inventory.has("banana"), "в сумке осталась только кожура")
	# «последняя капля»
	r.salad_on_table = false
	game.neighbor.set_process(true)
	var tasks: Array = game.day["tasks"]
	for id in tasks:
		if id != "salad":
			r._award(Days.TASKS[id][1], 0, "тест: " + id)
	await _wait(0.5)
	_ok(not r.over, "все задания без салата: финала ещё нет (ждёт салат)")
	_ok(r.drunk >= Rules3D.STAGE_FROM[4], "все задания без салата: сосед «в стельку» (%d %%)" % int(r.drunk))
	r.add_drunk(60.0)        # ещё рюмка по дороге — не уснул, держится до салата
	await _wait(0.2)
	_ok(not r.over and r.drunk <= 99.0, "все задания без салата, ещё рюмка: не уснул без салата (%d %%)" % int(r.drunk))
	r.inventory.assign(["salad"])
	r.selected = "salad"
	r.hero_use(game.spots["table"])
	var t := 0.0
	while not r.over and t < 16.0:
		await _wait(0.25)
		t += 0.25
	_ok(r.over and r.drunk >= 100.0, "салат на стол после всех заданий → финал через %.1f с" % t)
	print("SELFTEST %s" % ("PASS" if fails == 0 else "FAILED %d" % fails))
	get_tree().quit(0 if fails == 0 else 1)
