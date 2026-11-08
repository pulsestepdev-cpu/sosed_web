class_name Hero
extends Character
## Герой: ходит туда, куда кликнули. Shift или правая кнопка — переключить «крадучись».

const WALK_SPEED := 420.0
const SNEAK_SPEED := 190.0

var sneaking := false
var min_x := 0.0
var max_x := 1e9

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

func go_to(x: float) -> void:
	walk_to(clampf(x, min_x, max_x))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			go_to(get_global_mouse_position().x)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			toggle_sneak()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SHIFT:
		toggle_sneak()
