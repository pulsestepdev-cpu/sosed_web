class_name CutoutRig
extends Node2D
## Персонаж из отдельных частей (cut-out). Собирает иерархию суставов по описанию и анимирует её кодом.
## Смотрит вправо. Начало координат — точка между ступнями на полу.

@export var parts_dir := "res://assets/characters/neighbor/parts"
@export var anim := "idle"  # idle | walk
@export var walk_speed := 1.0

## Описание частей. pivot — точка сустава внутри картинки (доли ширины/высоты).
## joints — точки крепления детей внутри картинки (доли). scale — масштаб детали. z — порядок отрисовки.
var spec := {
	"torso":           {"pivot": Vector2(0.42, 0.88), "scale": 1.0,  "z": 0,
						"joints": {"neck": Vector2(0.43, 0.08), "shoulder": Vector2(0.32, 0.30), "hip": Vector2(0.42, 0.88)}},
	"head":            {"parent": "torso", "at": "neck", "pivot": Vector2(0.50, 0.90), "scale": 0.92, "z": 2},
	"arm_upper_back":  {"parent": "torso", "at": "shoulder", "pivot": Vector2(0.45, 0.17), "scale": 0.55, "z": -2,
						"joints": {"elbow": Vector2(0.55, 0.84)}},
	"arm_lower_back":  {"parent": "arm_upper_back", "at": "elbow", "pivot": Vector2(0.40, 0.14), "scale": 1.0, "z": -1},
	"arm_upper_front": {"parent": "torso", "at": "shoulder", "pivot": Vector2(0.45, 0.17), "scale": 0.55, "z": 3,
						"joints": {"elbow": Vector2(0.55, 0.84)}},
	"arm_lower_front": {"parent": "arm_upper_front", "at": "elbow", "pivot": Vector2(0.40, 0.14), "scale": 1.0, "z": 4},
	"leg_upper_back":  {"parent": "torso", "at": "hip", "pivot": Vector2(0.48, 0.17), "scale": 0.68, "z": -4,
						"joints": {"knee": Vector2(0.50, 0.85)}},
	"leg_lower_back":  {"parent": "leg_upper_back", "at": "knee", "pivot": Vector2(0.33, 0.13), "scale": 1.0, "z": -3},
	"leg_upper_front": {"parent": "torso", "at": "hip", "pivot": Vector2(0.48, 0.17), "scale": 0.68, "z": -1,
						"joints": {"knee": Vector2(0.50, 0.85)}},
	"leg_lower_front": {"parent": "leg_upper_front", "at": "knee", "pivot": Vector2(0.33, 0.13), "scale": 1.0, "z": 0},
}

var bones := {}   # имя -> Node2D сустава
var _t := 0.0

func _init() -> void:
	z_index = 20  # детали рисуются относительно этого уровня, чтобы не прятаться за фоном
var _root: Node2D

func _ready() -> void:
	_root = Node2D.new()
	add_child(_root)
	for name in spec:
		_build(name)
	# ставим так, чтобы ступни стояли на y = 0
	_root.position.y = -_foot_offset()

func _build(name: String) -> Node2D:
	if bones.has(name):
		return bones[name]
	var s: Dictionary = spec[name]
	var tex: Texture2D = load(parts_dir.path_join("part_%s.png" % name))
	var bone := Node2D.new()
	bone.name = name
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.offset = -Vector2(tex.get_size()) * (s["pivot"] as Vector2)
	sprite.z_index = z_index + int(s["z"])
	sprite.z_as_relative = false
	bone.add_child(sprite)
	bone.scale = Vector2.ONE * float(s["scale"])
	if s.has("parent"):
		var parent := _build(s["parent"])
		parent.add_child(bone)
		bone.position = _joint_pos(s["parent"], s["at"])
	else:
		_root.add_child(bone)
	bones[name] = bone
	return bone

## Позиция сустава в координатах кости-родителя.
func _joint_pos(parent: String, joint: String) -> Vector2:
	var ps: Dictionary = spec[parent]
	var tex_size := Vector2((bones[parent].get_child(0) as Sprite2D).texture.get_size())
	return tex_size * ((ps["joints"][joint] as Vector2) - (ps["pivot"] as Vector2))

func _foot_offset() -> float:
	# низ голени в координатах _root при нейтральной позе
	var shin: Node2D = bones["leg_lower_front"]
	var sp := shin.get_child(0) as Sprite2D
	var bottom_local := sp.offset + Vector2(0, sp.texture.get_size().y)
	return (_root.get_global_transform().affine_inverse() * shin.get_global_transform() * bottom_local).y - 4.0

func _process(delta: float) -> void:
	_t += delta
	match anim:
		"walk": _pose_walk(_t * TAU * 0.9 * walk_speed)
		_: _pose_idle(_t)

func _pose_idle(t: float) -> void:
	var breath := sin(t * 2.2)
	bones["torso"].scale = Vector2(1.0 + breath * 0.012, 1.0 - breath * 0.008)
	bones["torso"].rotation = 0.0
	bones["head"].rotation = sin(t * 1.1) * 0.03
	for side in ["back", "front"]:
		bones["arm_upper_" + side].rotation = 0.05 + breath * 0.02
		bones["arm_lower_" + side].rotation = -0.1
		bones["leg_upper_" + side].rotation = 0.0
		bones["leg_lower_" + side].rotation = 0.0
	_root.position.x = 0.0

func _pose_walk(p: float) -> void:
	var swing := sin(p)
	# ноги: бедро качается, колено сгибается на маховой фазе
	bones["leg_upper_front"].rotation = swing * 0.45
	bones["leg_upper_back"].rotation = -swing * 0.45

	bones["leg_lower_back"].rotation = maxf(0.0, sin(p + 1.2 + PI)) * 0.55
	bones["leg_lower_front"].rotation = maxf(0.0, sin(p + 1.2)) * 0.55
	# руки в противофазе ногам
	bones["arm_upper_front"].rotation = -swing * 0.35
	bones["arm_upper_back"].rotation = swing * 0.35
	bones["arm_lower_front"].rotation = -0.25 - maxf(0.0, -swing) * 0.3
	bones["arm_lower_back"].rotation = -0.25 - maxf(0.0, swing) * 0.3
	# корпус: покачивание вверх-вниз и вперёд-назад, пузо колышется
	var bob := absf(cos(p))
	bones["torso"].rotation = 0.05 + sin(p * 2.0) * 0.02
	bones["torso"].scale = Vector2(1.0 + bob * 0.015, 1.0 - bob * 0.015)
	bones["head"].rotation = -0.03 + sin(p * 2.0 + 0.6) * 0.03
	_root.position.y = -_base_y() - bob * 10.0

var _base := INF
func _base_y() -> float:
	if _base == INF:
		_base = -_root.position.y
	return _base
