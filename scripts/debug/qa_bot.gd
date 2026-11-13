class_name QaBot
extends Node
## Бот-игрок для автотестов: сам проходит уровень. Включается аргументом --bot=careful|normal|reckless.
##   careful  — крадётся рядом с соседом, обходит комнату, где он есть и куда он идёт, прячется заранее;
##   normal   — обходит комнату соседа, прячется, если тот заметил;
##   reckless — ходит напрямую, на соседа почти не смотрит (проверка «наказывает ли игра за наглость»).
## Решения — раз в 0.25 с игрового времени. Пишет свои решения в лог (print "[BOT] ...").

var game: Node            # Game3D
var strategy := "normal"
var _t := 0.0
var _target: Spot3D
var _target_since := 0.0
var _last_say := ""

func setup(g: Node, s: String) -> void:
	game = g
	strategy = s if s in ["careful", "normal", "reckless"] else "normal"
	if strategy == "careful" and not game.hero.sneaking:
		game.hero.toggle_sneak()
	_log("стратегия: " + strategy)

func _process(delta: float) -> void:
	if game == null or not game.started or game.rules.over:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	_think()

func _log(s: String) -> void:
	if s != _last_say:
		_last_say = s
		print("[%05.2f] BOT %s" % [game.hour, s])

# ---------------------------------------------------------------- оценка обстановки
func _room(p: Vector3) -> String:
	return "%s/%d" % [game.room_at(p), game.floor_of(p)]

func _neighbor_active() -> bool:
	return game.neighbor.mode not in ["bed", "asleep"]

## Комнаты, куда сейчас лучше не соваться.
func _danger_rooms() -> Array:
	var out := []
	if not _neighbor_active():
		return out
	var n: Neighbor3D = game.neighbor
	out.append(_room(n.position))
	if strategy == "careful" and n.goal != Vector3.INF:
		out.append(_room(n.goal))
	return out

func _in_danger() -> bool:
	var n: Neighbor3D = game.neighbor
	var h: Hero3D = game.hero
	if not _neighbor_active() or game.on_stairs(h.position):
		return false
	if n.suspicion > (0.1 if strategy != "reckless" else 0.6):
		return true
	if strategy == "reckless":
		return false
	var same := _room(h.position) == _room(n.position)
	if strategy == "careful" and n.goal != Vector3.INF and _room(n.goal) == _room(h.position) and n.is_walking():
		return true
	return same and n.view_range(game.hour) > 0.0

# ---------------------------------------------------------------- решение
func _think() -> void:
	var h: Hero3D = game.hero
	if h.frozen or h.busy > 0.0:
		return
	# 1) опасно — спрятаться (или сидеть, если уже спрятался)
	if _in_danger():
		if h.in_hiding:
			return
		var hide := _best_hide(true)
		if hide and (_target != hide):
			_go(hide, "прячусь: %s" % hide.title)
		elif hide == null and not h.is_walking():
			# прятаться негде — уйти на лестницу
			_target = null
			h.go(game.plan_path(h.position, game.lane_point(3.2, game.floor_of(h.position))))
			_log("ухожу на лестницу")
		return
	# 2) идём к цели — не дёргаться, пока не дошли (но и не залипать)
	if _target and (h.is_walking() or game._pending == _target):
		if game.hour - _target_since < 1.0:
			return
	# 3) выбрать дело
	var best := _best_task()
	if best:
		if best != _target or not h.is_walking():
			_go(best, "иду: %s" % game.rules.describe(best))
		return
	# 4) дел нет — переждать в укрытии подальше от соседа
	if not h.in_hiding and not h.is_walking():
		var hide := _best_hide(false)
		if hide:
			_go(hide, "жду в укрытии: %s" % hide.title)

func _go(s: Spot3D, why: String) -> void:
	_target = s
	_target_since = game.hour
	if s.kind in ["swap", "trap"]:
		game.rules.selected = s.item
		game.rules.inventory_changed.emit()
	elif s.id == "table" and game.rules.inventory.has("salad"):
		game.rules.selected = "salad"
		game.rules.inventory_changed.emit()
	_log(why)
	game._go_spot(s)

func _dist(s: Spot3D) -> float:
	var path: Array[Vector3] = game.plan_path(game.hero.position, s.walk)
	var d := 0.0
	var p: Vector3 = game.hero.position
	for q in path:
		d += p.distance_to(q)
		p = q
	return d

func _value(s: Spot3D) -> float:
	var r: Rules3D = game.rules
	if not s.active:
		return 0.0
	match s.kind:
		"stash":
			return 2.0
		"take":
			return 3.0
		"swap":
			return 4.0 if r.inventory.has(s.item) and not r.swapped.has(s.id) else 0.0
		"trap":
			return 4.0 if r.inventory.has(s.item) and not r.traps.has(s.id) else 0.0
		"hide":
			if s.id == "table" and r.inventory.has("salad") and not r.salad_on_table:
				return 6.0 if (r.drunk >= 45.0 or game.hour > 15.5) else 0.0
	return 0.0

func _best_task() -> Spot3D:
	var danger := _danger_rooms()
	var best: Spot3D = null
	var best_score := -INF
	for s in game.spots.values():
		var v := _value(s)
		if v <= 0.0:
			continue
		if strategy != "reckless" and _room(s.walk) in danger:
			continue
		var score := v * 10.0 - _dist(s)
		if score > best_score:
			best_score = score
			best = s
	return best

## Укрытие: в своей комнате (near=true) — ближайшее, иначе — подальше от соседа.
func _best_hide(near: bool) -> Spot3D:
	var best: Spot3D = null
	var best_score := INF
	var danger := _danger_rooms()
	for s in game.spots.values():
		if s.kind != "hide" or not s.active:
			continue
		var d := _dist(s)
		if near:
			if d > 4.5:
				continue
			if d < best_score:
				best_score = d
				best = s
		else:
			if _room(s.walk) in danger:
				continue
			var away: float = -s.walk.distance_to(game.neighbor.position)
			if away + d * 0.2 < best_score:
				best_score = away + d * 0.2
				best = s
	return best
