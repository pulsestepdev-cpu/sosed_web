class_name QaAnimCheck
extends Node
## Проверка анимации «без глаз» (как selftest; агент anim-review запускает её первой).
##
## --animcheck — прятки дня: герой по очереди залезает в каждое укрытие этого дня (как по клику). Проверяется:
##   1) в начале клипа смотрит на укрытие — не лезет спиной (лыжи — исключение: подходит лицом, потом прижимается
##      к стене спиной);
##   2) за клип таз сдвигается к укрытию, а не от него;
##   3) таз, грудь, шея и голова не проходят сквозь мебель (у своей мебели укрытия — только сквозь «твёрдые» части:
##      столешницу, сиденье и спинку дивана, капот и крышу машины…), заднюю стену, перегородки комнат и пол.
##   Печатает «ANIMCHECK ok/FAIL …», в конце «ANIMCHECK PASS» или «ANIMCHECK FAILED n», код выхода 0/1.
##     Godot.exe --headless --path . res://scenes/game.tscn -- --day=N --autostart --animcheck
##
## --animwatch — следит за обоими персонажами всю игру (удобно с ботом): «едет» без шагов (узел движется,
##   а клип не шаговый) и «пятится» (идёт спиной вперёд) дольше 0.35 с. Итог — в отчёт QaRecorder (поле anim)
##   и строкой «ANIMWATCH …» в лог.

const POINTS := ["Hips", "Spine2", "Neck", "Head"]
const BACK_OK := ["skis"]
const STEP_CLIPS := ["walk", "sneak", "walk_drunk", "run"]
## Клипы, в которых узел двигают нарочно (встаёт с кровати, падает со стремянки) — не «едет».
const MOVE_OK := ["get_up", "fall_back", "fall_forward"]
## Мебель, которую не проверяем: группы на весь дом, ковры, лампы.
const SKIP_PREFIX := ["Doors", "Windows", "rug", "bulb", "chandelier"]

var game: Node
var active := false
var fails := 0
var _watch := {}            # Actor -> {prev, glide, back}
var _events: Array = []
var _counts := {"glide": 0, "backward": 0}

func setup(g: Node, run_hides: bool) -> void:
	game = g
	active = run_hides
	if active:
		_run.call_deferred()

func _ok(cond: bool, what: String) -> void:
	print("ANIMCHECK %s  %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		fails += 1

# ---------------------------------------------------------------- прятки
func _run() -> void:
	await get_tree().create_timer(0.8, false).timeout
	game.neighbor.set_process(false)       # сосед не ходит и не ловит
	game.time_scale = 0.0
	Engine.time_scale = 3.0
	var hides: Array = game.spots.values().filter(func(s): return s.kind == "hide")
	print("ANIMCHECK день %d: укрытий %d" % [game.day_n, hides.size()])
	for s in hides:
		await _check_hide(s)
	Engine.time_scale = 1.0
	print("ANIMCHECK %s" % ("PASS" if fails == 0 else "FAILED %d" % fails))
	get_tree().quit(0 if fails == 0 else 1)

func _bone_points(a: Actor) -> Dictionary:
	var sk := a.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var out := {}
	for n in POINTS:
		var i := sk.find_bone(n)
		if i < 0:
			continue
		var gp := sk.get_bone_global_pose(i)
		var p := gp.origin + (gp.basis.y.normalized() * 0.16 if n == "Head" else Vector3.ZERO)   # середина головы
		out[n] = sk.global_transform * p
	return out

## «Твёрдые» части мебели: своя мебель укрытия — по её форме, остальная — целиком (чуть уменьшенная).
func _solids(s: Spot3D) -> Array:
	var out := []
	var own: Array = [s.node]
	if s.id == "curtain":
		own.append(game.furn.get_node_or_null("bathtub"))
	for n in game.furn.get_children():
		if not (n is Node3D) or n in own or SKIP_PREFIX.any(func(p): return String(n.name).begins_with(p)):
			continue
		var b: AABB = game._bounds(n)
		if b.size.length() < 0.05 or b.size.x > 6.0:
			continue
		out.append([String(n.name), _shrink(b)])
	if s.node == null:
		return out
	var b: AABB = s.aabb
	var p := b.position
	var z := b.size
	match s.id:
		"table":      # столешница
			out.append(["столешница", AABB(Vector3(p.x, b.end.y - 0.07, p.z), Vector3(z.x, 0.07, z.z))])
		"bed":        # матрас и каркас (под кроватью пусто до ~0.5 м — сетка матраса с 0.55)
			out.append(["кровать", _shrink(AABB(p + Vector3(0, 0.5, 0), z - Vector3(0, 0.5, 0)))])
		"sofa":       # сиденье спереди, спинка сзади
			out.append(["сиденье дивана", _shrink(AABB(Vector3(p.x, p.y, b.end.z - z.z * 0.62), Vector3(z.x, 0.42, z.z * 0.62)))])
			out.append(["спинка дивана", _shrink(AABB(p, Vector3(z.x, z.y, z.z * 0.33)))])
		"car":        # капот спереди (справа), салон с крышей
			var hx := p.x + z.x * 0.63
			out.append(["капот", _shrink(AABB(Vector3(hx, p.y, p.z), Vector3(b.end.x - hx, 0.84, z.z)))])
			out.append(["салон", _shrink(AABB(p, Vector3(hx - p.x, 1.36, z.z)))])
		"wardrobe", "curtain":
			pass      # внутрь
		_:
			out.append([s.title, _shrink(b)])
	return out

## Чуть меньше рамки (касание — не «сквозь»); у тонких предметов — не больше четверти толщины.
static func _shrink(b: AABB) -> AABB:
	var m := Vector3(minf(0.03, b.size.x * 0.25), minf(0.03, b.size.y * 0.25), minf(0.03, b.size.z * 0.25))
	return AABB(b.position + m, b.size - m * 2.0)

func _check_hide(s: Spot3D) -> void:
	var h: Hero3D = game.hero
	h.leave_hiding()
	h.stop()
	h.frozen = false
	h.release()
	h.position = s.walk
	h.rotation.y = PI / 2
	h.target_yaw = PI / 2
	await get_tree().process_frame
	var clip_name: String = Hero3D.hide_data(s.id)[0]
	var solids := _solids(s)
	var room: Array = Days.ROOMS.get(game.room_strict(s.walk), [-99.0, 99.0])
	var fy: float = game.floor_y(s.floor)
	var obj := s.aabb.get_center()
	h.hide_in(s)
	var t := 0.0
	var started := false
	var face_dot := 1.0
	var hips0 := Vector3.ZERO
	var hits := {}
	while h.hide_stage != 3 and t < 9.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if not started and h.clip() == clip_name:
			started = true
			var fwd := Vector3(sin(h.rotation.y), 0, cos(h.rotation.y))
			var to := obj - h.position
			to.y = 0
			face_dot = fwd.dot(to.normalized())
			hips0 = _bone_points(h).get("Hips", h.position)
		var pts := _bone_points(h)
		for n in pts.keys():
			var q: Vector3 = pts[n]
			var what := ""
			for so in solids:
				if (so[1] as AABB).has_point(q):
					what = so[0]
					break
			if what == "":
				if q.z < -3.98:
					what = "задняя стена"
				elif q.x < room[0] - 0.02 or q.x > room[1] + 0.02:
					what = "стена комнаты"
				elif q.y < fy - 0.03:
					what = "пол"
			if what != "":
				var key := "%s сквозь «%s»" % [n, what]
				hits[key] = hits.get(key, 0) + 1
	var hips1: Vector3 = _bone_points(h).get("Hips", h.position)
	var to2 := obj - hips0
	to2.y = 0
	var d := hips1 - hips0
	d.y = 0
	var tag := "%s (%s)" % [s.title, clip_name]
	_ok(started and h.hide_stage == 3, "%s: залез и скрылся за %.1f с" % [tag, t])
	if not s.id in BACK_OK:
		_ok(face_dot > 0.5, "%s: лицом к укрытию (%.2f)" % [tag, face_dot])
	_ok(d.dot(to2.normalized()) > 0.08, "%s: двигается к укрытию на %.2f м" % [tag, d.dot(to2.normalized())])
	var bad := hits.keys().filter(func(k): return hits[k] >= 2)
	_ok(bad.is_empty(), "%s: не проходит сквозь мебель и стены%s" % [tag, "" if bad.is_empty() else " — " + ", ".join(bad.map(func(k): return "%s ×%d" % [k, hits[k]]))])
	h.leave_hiding()
	await get_tree().process_frame

# ---------------------------------------------------------------- наблюдение во время игры
func _process(delta: float) -> void:
	if active or game == null or game.hero == null or delta <= 0.0:
		return
	for a in [game.hero, game.neighbor]:
		var st: Dictionary = _watch.get(a, {"prev": a.position, "glide": 0.0, "back": 0.0})
		var v: Vector3 = (a.position - st["prev"]) / delta
		v.y = 0
		st["prev"] = a.position
		var moving: bool = v.length() > 0.25 and not a.in_portal and a.visible and a.model.visible
		var c: String = a.clip()
		var stepping: bool = c in STEP_CLIPS or c in MOVE_OK or c.begins_with("hide_")
		st["glide"] = st["glide"] + delta if moving and not stepping else 0.0
		var fwd := Vector3(sin(a.rotation.y), 0, cos(a.rotation.y))
		st["back"] = st["back"] + delta if moving and fwd.dot(v.normalized()) < -0.5 else 0.0
		for kind in ["glide", "back"]:
			if st[kind] >= 0.35 and st[kind] - delta < 0.35:
				var k := "glide" if kind == "glide" else "backward"
				_counts[k] += 1
				var e := {"kind": k, "who": a.kind, "clip": c, "hour": snappedf(game.hour, 0.01),
					"x": snappedf(a.position.x, 0.1), "floor": game.floor_of(a.position), "activity": game.neighbor.activity if a == game.neighbor else ""}
				if _events.size() < 40:
					_events.append(e)
				print("ANIMWATCH %s %s clip=%s час=%.2f x=%.1f %s" % [k, a.kind, c, game.hour, a.position.x, e["activity"]])
		_watch[a] = st

func summary() -> Dictionary:
	return {"glide": _counts["glide"], "backward": _counts["backward"], "events": _events}
