class_name Character
extends Node2D
## Общая основа героя и соседа: ходьба по полу к точке, разворот, анимация, облачко реплики.

signal arrived

const BUBBLE_Y := -720.0

@export var who := "neighbor"
@export var char_scale := 0.834
@export var walk_px_per_sec := 360.0

var rig: CutoutRig
var body: Node2D          # разворачивается влево/вправо
var target_x := NAN
var speed_mul := 1.0
var _bubble: Label
var _bubble_time := 0.0

func _ready() -> void:
	body = Node2D.new()
	add_child(body)
	rig = CutoutRig.new()
	rig.character = who
	rig.scale = Vector2.ONE * char_scale
	body.add_child(rig)

	_bubble = Label.new()
	_bubble.add_theme_font_size_override("font_size", 38)
	_bubble.add_theme_color_override("font_color", Color("2b1a10"))
	_bubble.add_theme_color_override("font_outline_color", Color("fff6e0"))
	_bubble.add_theme_constant_override("outline_size", 14)
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.size = Vector2(900, 60)
	_bubble.position = Vector2(-450, BUBBLE_Y)
	_bubble.z_index = 100
	_bubble.visible = false
	add_child(_bubble)

func walk_to(x: float) -> void:
	target_x = x

func stop() -> void:
	target_x = NAN

func is_walking() -> bool:
	return not is_nan(target_x)

func face(right: bool) -> void:
	body.scale.x = 1.0 if right else -1.0

func set_face(face_name: String) -> void:
	rig.set_face(face_name)

func say(text: String, seconds := 3.0) -> void:
	_bubble.text = text
	_bubble.visible = text != ""
	_bubble_time = seconds

func _process(delta: float) -> void:
	if _bubble_time > 0.0:
		_bubble_time -= delta
		if _bubble_time <= 0.0:
			_bubble.visible = false

	if is_nan(target_x):
		rig.anim = "idle"
		return
	var dx := target_x - position.x
	var step := walk_px_per_sec * speed_mul * delta
	if absf(dx) <= step:
		position.x = target_x
		target_x = NAN
		rig.anim = "idle"
		arrived.emit()
		return
	face(dx > 0.0)
	position.x += signf(dx) * step
	rig.anim = "walk"
	rig.walk_speed = speed_mul * walk_px_per_sec / 360.0
