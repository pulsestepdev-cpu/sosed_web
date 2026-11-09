class_name Actor
extends Node3D
## Общая основа 3D-героя и соседа: модель с клипами, ходьба по маршруту из точек (в том числе по лестнице),
## плавный разворот, лицо (подмена текстуры), реплика над головой с озвучкой, звук шагов.

signal arrived

const FACE_DIR := "res://assets/models/characters/"
const LOOPED := ["idle", "walk", "sneak", "walk_drunk", "drink", "work", "phone", "kick", "sleep", "dance",
	"lie_back", "lie_forward", "bulb", "search_low", "search_mid"]

var kind := "neighbor"          # neighbor | hero (имя файла модели и текстур лица)
var model: Node3D
var ap: AnimationPlayer
var mat: StandardMaterial3D
var path: Array[Vector3] = []
var speed := 1.2                # м/с
var speed_mul := 1.0
var walk_clip := "walk"
var idle_clip := "idle"
var hold := false               # клип задан снаружи (реакция, действие) — не переключать на idle/walk
var head_h := 1.85              # высота макушки — для облачка
var bubble := ""
var bubble_time := 0.0
var face_name := "normal"
var target_yaw := 0.0
var step_sfx := "step"
var step_vol := 0.5
var _step_t := 0.0
var _faces := {}
var _clip := ""

func setup(glb_path: String, who: String) -> void:
	kind = who
	model = (load(glb_path) as PackedScene).instantiate() as Node3D
	add_child(model)
	ap = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for c in ap.get_animation_list():
		ap.get_animation(c).loop_mode = Animation.LOOP_LINEAR if c in LOOPED else Animation.LOOP_NONE
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh.surface_get_material(0)
		if m is StandardMaterial3D and mi.get_parent() is Skeleton3D:
			mat = (m as StandardMaterial3D).duplicate()
			(mi as MeshInstance3D).set_surface_override_material(0, mat)
			break
	play(idle_clip)

# ---------------------------------------------------------------- анимация и лицо
func play(clip: String, blend := 0.25, spd := 1.0) -> void:
	if not ap.has_animation(clip):
		return
	if clip == _clip and ap.is_playing():
		ap.speed_scale = spd
		return
	_clip = clip
	ap.play(clip, blend)
	ap.speed_scale = spd

## Проиграть клип один раз и держать (hold), потом — обратно к обычным позам, если release.
func act(clip: String, seconds := -1.0, blend := 0.2) -> void:
	hold = true
	play(clip, blend)
	if seconds > 0.0:
		var my := _clip
		get_tree().create_timer(seconds, false).timeout.connect(func():
			if _clip == my:
				hold = false)

func release() -> void:
	hold = false

func clip() -> String:
	return _clip

## Застыть на кадре клипа (для позы «лицом в салат» и т.п.).
func freeze_at(c: String, t: float) -> void:
	hold = true
	_clip = c
	ap.play(c, 0.3)
	ap.seek(t, true)
	ap.pause()

func set_face(n: String) -> void:
	if mat == null or n == face_name:
		return
	face_name = n
	if not _faces.has(n):
		var p := FACE_DIR + "%s_face_%s.jpg" % [kind, n]
		_faces[n] = load(p) if ResourceLoader.exists(p) else null
	if _faces[n]:
		mat.albedo_texture = _faces[n]

func set_alpha(a: float) -> void:
	if mat == null:
		return
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS if a < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color.a = a

## Реплика над головой; озвучивается, если есть запись. Возвращает, сколько секунд она звучит.
func say(text: String, seconds := 2.5) -> float:
	bubble = text
	var dur := Settings.voice(text, "n" if kind == "neighbor" else "h") if text != "" else 0.0
	bubble_time = maxf(seconds, dur + 0.4)
	return dur

# ---------------------------------------------------------------- ходьба
func walk_path(points: Array[Vector3]) -> void:
	path = points.duplicate()

func stop() -> void:
	path.clear()

func is_walking() -> bool:
	return not path.is_empty()

func face_dir(d: Vector3) -> void:
	if Vector2(d.x, d.z).length() > 0.001:
		target_yaw = atan2(d.x, d.z)

func face_x(x: float) -> void:
	if absf(x - position.x) > 0.02:
		face_dir(Vector3(x - position.x, 0, 0))

## Смотрит вправо (+X)? Для обзора соседа.
func looks_right() -> bool:
	return sin(model_yaw()) >= 0.0

func model_yaw() -> float:
	return rotation.y

func head_pos() -> Vector3:
	return global_position + Vector3(0, head_h, 0)

func _process(delta: float) -> void:
	if bubble_time > 0.0:
		bubble_time -= delta
		if bubble_time <= 0.0:
			bubble = ""
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * 9.0))
	if path.is_empty():
		if not hold:
			play(idle_clip)
		return
	var step := speed * speed_mul * delta
	while step > 0.0 and not path.is_empty():
		var to := path[0] - position
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() > 0.02:
			face_dir(flat)
		var dist := to.length()
		if dist <= step:
			position = path[0]
			path.remove_at(0)
			step -= dist
		else:
			position += to / dist * step
			step = 0.0
	if path.is_empty():
		if not hold:
			play(idle_clip)
		arrived.emit()
	else:
		if not hold:
			play(walk_clip, 0.2, speed_mul * _walk_anim_k())
		_step_t -= delta * speed_mul
		if _step_t <= 0.0:
			_step_t = _step_period()
			Settings.sfx("%s_%d" % [step_sfx, randi() % 4], step_vol, randf_range(0.9, 1.1))

func _walk_anim_k() -> float:
	return 1.0

func _step_period() -> float:
	return 0.42
