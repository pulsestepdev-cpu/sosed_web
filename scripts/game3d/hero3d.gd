class_name Hero3D
extends Actor
## Герой: ходит по клику (обычно или крадучись), шарит в тайниках, подменяет, прячется,
## злорадствует, когда сосед попался на пакость, и пугается, когда попался сам.

const WALK_SPEED := 1.55
const SNEAK_SPEED := 0.8

## Укрытия: id -> [клип, точка (x, y от пола, z), исчезает ли целиком, разворот]
const HIDES := {
	"wardrobe": ["hide_wardrobe", Vector3(3.72, 0.0, -1.55), true, PI],
	"curtain":  ["hide_curtain", Vector3(3.85, 0.0, -3.35), false, 0.0],
	"bed":      ["hide_bed", Vector3(8.4, 0.0, -1.7), false, PI],
	"table":    ["hide_table", Vector3(8.7, 0.0, -1.95), false, 0.0],
	"sofa":     ["hide_sofa", Vector3(11.6, 0.0, -3.82), false, 0.0],
	"skis":     ["hide_skis", Vector3(13.25, 0.0, -3.55), false, 0.0],
}

var game: Node
var sneaking := false
var in_hiding := false
var hide_spot: Spot3D
var busy := 0.0
var frozen := false          # пойман — стоит в ужасе
var _gloat_cd := 0.0

func _init() -> void:
	speed = WALK_SPEED
	head_h = 1.8
	step_sfx = "step"
	step_vol = 0.45

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
	if frozen:
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
	return is_walking() and not sneaking

func hide_in(s: Spot3D) -> void:
	var h: Array = HIDES.get(s.id, ["hide_table", s.walk, false, 0.0])
	in_hiding = true
	hide_spot = s
	set_face("sneaky")
	Settings.sfx("hide", 0.6)
	var p: Vector3 = h[1]
	p.y = game.floor_y(s.floor)
	if h[2]:
		game.open_prop(s, 1.3)
	target_yaw = h[3]
	act(h[0])
	# нырнул в укрытие и пропал — над укрытием только «глаза» (рисует Overlay3D)
	var tw := create_tween()
	tw.tween_property(self, "position", p, 0.4)
	tw.tween_interval(1.15 if s.id == "bed" else 0.35)     # под кровать — видно, как ныряет «рыбкой»
	tw.tween_callback(func():
		if in_hiding:
			visible = false)

func leave_hiding() -> void:
	if not in_hiding:
		return
	in_hiding = false
	if HIDES.get(hide_spot.id, ["", 0, false])[2]:
		game.open_prop(hide_spot, 1.0)
	visible = true
	hide_spot = null
	release()
	set_face("sneaky" if sneaking else "normal")

## Нашёл вещь в тайнике.
func found() -> void:
	set_face("happy")
	act("success", 1.2)
	if randf() < 0.45:
		say("Опа, заначка!", 1.6)
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

func respawn(at: Vector3) -> void:
	frozen = false
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
