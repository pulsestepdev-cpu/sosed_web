class_name Hero
extends Character
## Герой. Клики обрабатывает уровень (там решается: пол, предмет, укрытие).
## Здесь — скорость, «крадучись», укрытие и короткое действие руками.

const WALK_SPEED := 430.0
const SNEAK_SPEED := 200.0

var sneaking := false
var in_hiding := false
var busy := 0.0            # сколько секунд ещё занят действием (стоит, его видно)
var level: Level

func _init() -> void:
	who = "hero"

func _ready() -> void:
	super._ready()
	_apply_speed()

func toggle_sneak() -> void:
	sneaking = not sneaking
	_apply_speed()

func _apply_speed() -> void:
	walk_px_per_sec = SNEAK_SPEED if sneaking else WALK_SPEED

## Идти к точке мира (этаж определяется по высоте клика).
func go_to_point(p: Vector2) -> void:
	set_hidden(false)
	walk_path(level.plan_path(position, level.snap_to_floor(p)))

func set_hidden(h: bool) -> void:
	in_hiding = h
	modulate = Color(1, 1, 1, 0.35) if h else Color.WHITE
	z_index = -45 if h else 0

func act(seconds: float) -> void:
	busy = seconds
	idle_anim = "work"

## Шумит ли: идёт обычным шагом.
func is_noisy() -> bool:
	return is_walking() and not sneaking

func _process(delta: float) -> void:
	if busy > 0.0:
		busy -= delta
		if busy <= 0.0:
			idle_anim = "idle"
	super._process(delta)
