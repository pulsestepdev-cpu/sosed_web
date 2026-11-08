class_name Hero
extends Character
## Герой: ходит туда, куда кликнули (на любой этаж — сам дойдёт до лестницы).
## Правая кнопка или Shift — переключить «крадучись».

const WALK_SPEED := 420.0
const SNEAK_SPEED := 190.0

var sneaking := false
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
	walk_path(level.plan_path(position, level.snap_to_floor(p)))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			go_to_point(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			toggle_sneak()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SHIFT:
		toggle_sneak()
