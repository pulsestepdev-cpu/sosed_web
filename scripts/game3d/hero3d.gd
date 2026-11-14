class_name Hero3D
extends Actor
## Герой: ходит по клику (обычно или крадучись), шарит в тайниках, подменяет, прячется,
## злорадствует, когда сосед попался на пакость, и пугается, когда попался сам.

const WALK_SPEED := 1.55
const SNEAK_SPEED := 0.8

## Укрытия: id -> [клип, точка подхода (x, z), разворот перед клипом, открыть дверцу/шторку через … с
##   (-1 — нечего открывать), на сколько секунд, через сколько секунд клипа герой скрыт, глаза (x, над полом, z)].
## Герой всегда подходит к укрытию лицом (идёт к точке подхода), а внутрь / под / за укрытие его ведёт сам клип
## (корневое смещение, tools/blender/rig_hero.py). Разворот к зрителю — уже внутри клипа (шкаф, ванна, диван, машина).
## Размеры мебели и зазоры — tools/build_level_3d.gd; что ничего не проходит сквозь мебель, проверяет --animcheck.
const HIDES := {
	"wardrobe": ["hide_wardrobe", Vector2(3.72, -2.5), PI, 0.2, 1.45, 1.85, Vector3(3.72, 1.4, -3.26)],
	"curtain":  ["hide_curtain", Vector2(3.85, -2.85), PI, 0.25, 1.3, 2.15, Vector3(3.85, 1.48, -3.14)],
	"bed":      ["hide_bed", Vector2(8.4, -1.45), PI, -1.0, 0.0, 1.35, Vector3(8.4, 0.18, -2.42)],
	"table":    ["hide_table", Vector2(8.7, -1.15), PI, -1.0, 0.0, 1.75, Vector3(8.7, 0.42, -1.62)],
	"sofa":     ["hide_over", Vector2(11.6, -2.3), PI, -1.0, 0.0, 1.75, Vector3(11.6, 0.97, -3.6)],
	"skis":     ["hide_skis", Vector2(13.55, -3.3), 0.0, -1.0, 0.0, 1.25, Vector3(13.55, 1.62, -3.55)],
	"sacks":    ["hide_climb", Vector2(9.6, -2.42), PI, -1.0, 0.0, 1.5, Vector3(9.6, 1.34, -3.44)],
	"car":      ["hide_hood", Vector2(14.9, -1.0), PI, -1.0, 0.0, 1.5, Vector3(14.9, 0.96, -3.26)],
	"boxes":    ["hide_climb", Vector2(5.9, -2.38), PI, -1.0, 0.0, 1.5, Vector3(5.9, 1.16, -3.39)],
}
const HIDE_RUN := 1.5       # к укрытию — бегом

var game: Node
var sneaking := false
var in_hiding := false
var hide_spot: Spot3D
var busy := 0.0
var frozen := false          # пойман — стоит в ужасе
var dizzy := false           # нокаут: звёздочки над головой (Overlay3D)
var hide_stage := 0          # 1 — бежит к укрытию, 2 — залезает (клип), 3 — сидит (скрыт)
var _hide_token := 0         # отменяет отложенные шаги пряток, если вылез раньше
var _gloat_cd := 0.0

func _init() -> void:
	speed = WALK_SPEED
	head_h = 1.8
	step_sfx = "step"
	step_vol = 0.45

## Финал: вылезти, встать лицом к игроку и сплясать (свой танец героя — клип dance, rig_hero.py).
func victory_dance() -> void:
	stop()
	leave_hiding()
	frozen = true
	busy = 0.0
	target_yaw = 0.0
	set_face("laugh")
	act("dance", -1.0, 0.3)

func toggle_sneak() -> void:
	sneaking = not sneaking
	speed = SNEAK_SPEED if sneaking else WALK_SPEED
	walk_clip = "sneak" if sneaking else "walk"
	step_sfx = "sneak" if sneaking else "step"
	step_vol = 0.25 if sneaking else 0.6
	if not in_hiding and not frozen:
		set_face("sneaky" if sneaking else "normal")

func _step_period() -> float:
	return 0.55 if sneaking else 0.36

## Идти к точке (маршрут строит уровень). Если сидит в укрытии — сначала вылезти.
func go(points: Array[Vector3]) -> void:
	if frozen or in_portal:
		return
	busy = 0.0
	release()
	if in_hiding:
		leave_hiding()
		var p := points.duplicate()
		p.push_front(game.lane_point(position.x, game.floor_of(position)))
		walk_path(p)
	else:
		walk_path(points)

func busy_act(c: String, seconds: float) -> void:
	busy = seconds
	act(c, seconds)

func is_noisy() -> bool:
	return is_walking() and not sneaking and not in_hiding

static func hide_data(id: String) -> Array:
	return HIDES.get(id, ["hide_sofa", Vector2.ZERO, 0.0, -1.0, 0.0, 0.8, Vector3.INF])

## Точка подхода к укрытию (на полу этажа укрытия).
func hide_entry(s: Spot3D) -> Vector3:
	var a: Vector2 = hide_data(s.id)[1]
	if a == Vector2.ZERO:
		a = Vector2(s.walk.x, s.walk.z)
	return Vector3(a.x, game.floor_y(s.floor), a.y)

## Спрятаться: подбежать к укрытию лицом к нему, залезть (клип), пропасть — над укрытием только «глаза»
## (рисует Overlay3D). Спрятанным считается сразу — сосед не видит его уже на подходе (как и раньше).
func hide_in(s: Spot3D) -> void:
	in_hiding = true
	hide_spot = s
	_hide_token += 1
	set_face("sneaky")
	var a := hide_entry(s)
	if Vector2(a.x - position.x, a.z - position.z).length() > 0.03:
		hide_stage = 1
		speed_mul = HIDE_RUN
		walk_path([a])
	else:
		_hide_enter()

func _hide_enter() -> void:
	var s := hide_spot
	var h := hide_data(s.id)
	hide_stage = 2
	speed_mul = 1.0
	target_yaw = h[2]
	var tok := _hide_token
	var turn := absf(angle_difference(rotation.y, target_yaw))
	if turn > 0.3:                       # сначала развернуться (лыжи: к стене спиной)
		await get_tree().create_timer(minf(0.45, turn * 0.12), false).timeout
		if tok != _hide_token:
			return
	rotation.y = target_yaw
	Settings.sfx("hide", 0.6)
	act(h[0])
	if s.id == "car" and randf() < 0.5:
		say(Rules3D.CAR_HIDE.pick_random(), 2.2)
	if h[3] >= 0.0:                      # дверца шкафа / шторка — когда до неё дотянулся
		get_tree().create_timer(h[3], false).timeout.connect(func():
			if tok == _hide_token:
				game.open_prop(s, h[4]))
	get_tree().create_timer(h[5], false).timeout.connect(func():
		if tok == _hide_token and in_hiding:
			hide_stage = 3
			visible = false)

## Где над укрытием выглядывают глаза (мировые координаты).
func hide_eyes() -> Vector3:
	var e: Vector3 = hide_data(hide_spot.id)[6]
	if e == Vector3.INF:
		var b := hide_spot.aabb
		return b.get_center() + Vector3(0, b.size.y * 0.15, b.size.z * 0.5)
	return Vector3(e.x, game.floor_y(hide_spot.floor) + e.y, e.z)

func leave_hiding() -> void:
	if not in_hiding:
		return
	in_hiding = false
	_hide_token += 1
	if hide_stage >= 2 and hide_data(hide_spot.id)[3] >= 0.0:
		game.open_prop(hide_spot, 1.0)
	hide_stage = 0
	speed_mul = 1.0
	visible = true
	hide_spot = null
	release()
	set_face("sneaky" if sneaking else "normal")

## Нашёл вещь в тайнике.
func found() -> void:
	set_face("happy")
	act("success", 1.2)
	if randf() < 0.45:
		say(Rules3D.FOUND.pick_random(), 1.6)
	get_tree().create_timer(1.3, false).timeout.connect(func():
		if not frozen:
			set_face("sneaky" if sneaking or in_hiding else "normal"))

## Злорадство: смех (и обзывательство, если line не пустая).
func gloat(line: String) -> void:
	if frozen or _gloat_cd > 0.0:
		return
	_gloat_cd = 4.0
	set_face("laugh")
	if line != "":
		say(line, 2.4)
	if not is_walking() and not in_hiding and busy <= 0.0:
		act("laugh", 2.4)
	get_tree().create_timer(2.6, false).timeout.connect(func():
		if not frozen:
			set_face("sneaky" if sneaking or in_hiding else "normal"))

## Попался: застыть в ужасе (сосед бежит бить).
func get_caught() -> void:
	stop()
	leave_hiding()
	frozen = true
	busy = 0.0
	set_face("scared")
	act("caught")
	if randf() < 0.6:          # ждёт, пока сосед доорёт; схватит раньше — реплику оборвёт его крик
		say(Rules3D.CAUGHT_LINES.pick_random(), 1.6)

## Держат за шею и трясут (клип choked идёт в такт с grab_shake соседа).
func choke() -> void:
	act("choked", -1.0, 0.12)
	set_face("scared")

func thrown_away() -> void:
	act("thrown", -1.0, 0.08)

func knock_out() -> void:
	act("knocked_out", -1.0, 0.04)
	set_face("scared")
	dizzy = true

func respawn(at: Vector3) -> void:
	frozen = false
	dizzy = false
	release()
	position = at
	target_yaw = PI / 2
	rotation.y = target_yaw
	set_face("sneaky" if sneaking else "normal")

func _process(delta: float) -> void:
	_gloat_cd -= delta
	if busy > 0.0:
		busy -= delta
	super._process(delta)
	if hide_stage == 1 and in_hiding and path.is_empty():
		_hide_enter()
