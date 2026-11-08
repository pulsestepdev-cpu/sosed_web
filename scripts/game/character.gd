class_name Character
extends Node2D
## Общая основа героя и соседа: ходьба по маршруту из точек (в том числе по лестнице),
## разворот, поза на месте, падение, облачко реплики.

signal arrived

const BUBBLE_Y := -760.0

@export var who := "neighbor"
@export var char_scale := 0.834
@export var walk_px_per_sec := 360.0

var rig: CutoutRig
var body: Node2D          # разворачивается влево/вправо
var path: Array[Vector2] = []
var speed_mul := 1.0
var ui_scale := 1.0       # масштаб облачка, чтобы текст был читаемым при любом зуме
var idle_anim := "idle"   # поза, когда стоит на месте: idle | drink | work | kick | phone
var lying := false
var _bubble: Label
var _bubble_time := 0.0
var _fall_tween: Tween

func _ready() -> void:
	body = Node2D.new()
	add_child(body)
	rig = CutoutRig.new()
	rig.character = who
	rig.scale = Vector2.ONE * char_scale
	body.add_child(rig)

	_bubble = Label.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_theme_font_size_override("font_size", 40)
	_bubble.add_theme_color_override("font_color", Color("2b1a10"))
	_bubble.add_theme_color_override("font_outline_color", Color("fff6e0"))
	_bubble.add_theme_constant_override("outline_size", 16)
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.size = Vector2(1000, 60)
	_bubble.z_index = 200
	_bubble.visible = false
	add_child(_bubble)

func walk_path(points: Array[Vector2]) -> void:
	if lying:
		return
	path = points.duplicate()

func stop() -> void:
	path.clear()

func is_walking() -> bool:
	return not path.is_empty()

func facing_right() -> bool:
	return body.scale.x > 0.0

func face(right: bool) -> void:
	body.scale.x = 1.0 if right else -1.0

func face_towards(x: float) -> void:
	if absf(x - position.x) > 1.0:
		face(x > position.x)

func set_face(face_name: String) -> void:
	rig.set_face(face_name)

func say(text: String, seconds := 3.0) -> void:
	_bubble.text = text
	_bubble.visible = text != ""
	_bubble_time = seconds

## Упасть (назад — на спину, вперёд — лицом вниз).
func fall(forward := false) -> void:
	lying = true
	path.clear()
	if _fall_tween:
		_fall_tween.kill()
	_fall_tween = create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var angle := 1.45 if forward else -1.45
	_fall_tween.tween_property(body, "rotation", angle * signf(body.scale.x), 0.7)
	_fall_tween.parallel().tween_property(body, "position:y", -60.0, 0.7)

func get_up() -> void:
	lying = false
	if _fall_tween:
		_fall_tween.kill()
	_fall_tween = create_tween()
	_fall_tween.tween_property(body, "rotation", 0.0, 0.5)
	_fall_tween.parallel().tween_property(body, "position:y", 0.0, 0.5)

func _process(delta: float) -> void:
	_bubble.scale = Vector2.ONE * ui_scale
	_bubble.position = Vector2(-500.0 * ui_scale, BUBBLE_Y * minf(ui_scale, 1.25) - 60.0 * (ui_scale - 1.0))
	if _bubble_time > 0.0:
		_bubble_time -= delta
		if _bubble_time <= 0.0:
			_bubble.visible = false

	if lying:
		rig.anim = "idle"
		return
	if path.is_empty():
		rig.anim = idle_anim
		return
	var step := walk_px_per_sec * speed_mul * delta
	while step > 0.0 and not path.is_empty():
		var to := path[0] - position
		if absf(to.x) > 1.0:
			face(to.x > 0.0)
		var dist := to.length()
		if dist <= step:
			position = path[0]
			path.remove_at(0)
			step -= dist
		else:
			position += to / dist * step
			step = 0.0
	if path.is_empty():
		rig.anim = idle_anim
		arrived.emit()
	else:
		rig.anim = "walk"
		rig.walk_speed = speed_mul * walk_px_per_sec / 360.0
