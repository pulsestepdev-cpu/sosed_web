class_name Actor
extends Node3D
## Общая основа 3D-героя и соседа: модель с клипами, ходьба по маршруту из точек (в том числе по лестнице),
## плавный разворот, лицо (подмена текстуры), реплика над головой с озвучкой, звук шагов.

signal arrived
signal portal_used(at: Vector3)    # вошёл в дверь-переход или вышел из неё (точка у двери)

const FACE_DIR := "res://assets/models/characters/"
const LOOPED := ["idle", "walk", "sneak", "walk_drunk", "drink", "work", "phone", "game", "kick", "sleep", "dance",
	"lie_back", "lie_forward", "bulb", "search_low", "search_mid",
	"brush", "wash", "inspect", "repair", "rummage", "gaze", "stretch"]     # бытовые дела соседа по распорядку

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
var partner: Actor              # второй персонаж: говорят по очереди, не перебивая
var yields := false             # true — ждёт, пока партнёр договорит (герой); false — перебивает его (сосед)
var speech_t := 0.0             # сколько ещё звучит своя реплика
var _queued := ""
var _queued_secs := 0.0
var _queued_wait := 0.0
var _faces := {}
var _clip := ""
var in_portal := false          # прямо сейчас «за дверью» (переход между этажами)
var _portal_t := 0.0
var _portal_stage := 0
const PORTAL_TIME := 0.9        # сколько секунд персонажа не видно в двери
const PORTAL_OPEN := 0.4       # дверь успевает открыться, прежде чем он войдёт / выйдет

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
## Говорят по очереди: герой ждёт, пока сосед договорит (до 14 с, потом реплика пропадает),
## сосед своей репликой обрывает героя.
func say(text: String, seconds := 2.5) -> float:
	if text != "" and partner:
		if yields and partner.is_speaking():
			_queued = text
			_queued_secs = seconds
			_queued_wait = 14.0
			return 0.0
		if not yields and partner.is_speaking():
			partner.shut_up()
	bubble = text
	var dur := Settings.voice(text, "n" if kind == "neighbor" else "h") if text != "" else 0.0
	bubble_time = maxf(seconds, dur + 0.4)
	speech_t = maxf(dur + 0.25, minf(bubble_time, 1.6)) if text != "" else 0.0
	return dur

## Звучит ли реплика: по таймеру и по самому звуку (он идёт в реальном времени — при ускорении игры
## таймер в игровом времени кончается раньше, чем звук).
func is_speaking() -> bool:
	return speech_t > 0.0 or Settings.voice_playing("n" if kind == "neighbor" else "h")

func shut_up() -> void:
	bubble = ""
	bubble_time = 0.0
	speech_t = 0.0
	_queued = ""
	Settings.stop_voice("n" if kind == "neighbor" else "h")

# ---------------------------------------------------------------- ходьба
func walk_path(points: Array[Vector3]) -> void:
	path = points.duplicate()

func stop() -> void:
	if in_portal:
		_finish_portal()
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

## Мировая точка кости модели (голова лежащего героя — для звёздочек).
func bone_pos(bone: String) -> Vector3:
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var i := sk.find_bone(bone)
	return sk.to_global(sk.get_bone_global_pose(i).origin) if i >= 0 else head_pos()

func _process(delta: float) -> void:
	if bubble_time > 0.0:
		bubble_time -= delta
		if bubble_time <= 0.0:
			bubble = ""
	if speech_t > 0.0:
		speech_t -= delta / maxf(0.01, Engine.time_scale)     # реальные секунды, как у звука
	if _queued != "":
		_queued_wait -= delta
		if partner == null or not partner.is_speaking():
			var q := _queued
			_queued = ""
			say(q, _queued_secs)
		elif _queued_wait <= 0.0:
			_queued = ""
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * 9.0))
	if in_portal:
		_portal_t -= delta
		if _portal_t <= 0.0:
			_portal_step()
		return
	if path.is_empty():
		if not hold:
			play(idle_clip)
		return
	var step := speed * speed_mul * delta
	while step > 0.0 and not path.is_empty():
		if path[0].x > Days.TP * 0.5:     # дверь-переход: скрыться в двери, через PORTAL_TIME выйти из парной
			_start_portal()
			return
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

## Дверь-переход по шагам: 1 — дверь открывается, персонаж шагает в проём и пропадает; 2 — «за дверью»
## (PORTAL_TIME); 3 — на другом этаже открывается парная дверь, и он выходит из проёма.
func _start_portal() -> void:
	in_portal = true
	_portal_stage = 1
	_portal_t = PORTAL_OPEN
	portal_used.emit(position)          # дверь открывается

func _portal_step() -> void:
	match _portal_stage:
		1:
			_portal_stage = 2
			_portal_t = PORTAL_TIME
			if hold:
				release()
			play(walk_clip, 0.15)
			var into := Vector3(position.x, position.y, position.z - 0.3)
			var tw := create_tween()
			tw.tween_property(self, "position", into, 0.3)
			tw.tween_callback(func():
				if in_portal:
					model.visible = false)
		2:
			_portal_stage = 3
			_portal_t = PORTAL_OPEN
			if not path.is_empty() and path[0].x > Days.TP * 0.5:
				path.remove_at(0)
			if not path.is_empty():       # встать в проёме парной двери (дальше — шаг из неё)
				position = Vector3(path[0].x, path[0].y, path[0].z - 0.3)
			portal_used.emit(position)    # парная дверь открывается
		_:
			_finish_portal()

## Выйти из парной двери (или сразу закончить переход, если путь прервали).
func _finish_portal() -> void:
	if _portal_stage <= 2:
		if not path.is_empty() and path[0].x > Days.TP * 0.5:
			path.remove_at(0)
		if not path.is_empty():
			position = Vector3(path[0].x, path[0].y, path[0].z - 0.3)
	in_portal = false
	_portal_stage = 0
	model.visible = true
	model.scale = Vector3.ONE

func _walk_anim_k() -> float:
	return 1.0

func _step_period() -> float:
	return 0.42
