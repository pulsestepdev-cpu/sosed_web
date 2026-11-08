extends Node3D
## Проверка 3D-персонажа: тёплая комната-коробка, свет, анимация.
## По умолчанию — сосед; Tab переключает персонажа (см. MODELS).
## --model=res://...glb  --anim=walk
##  --strip  — 6 копий персонажа в ряд, каждая в своей фазе анимации (раскадровка)

## Персонажи, между которыми переключает Tab. Первый открывается по умолчанию (F6 в редакторе).
const MODELS := ["res://assets/models/characters/neighbor.glb", "res://assets/models/characters/hero.glb"]
var model_path: String = MODELS[0]
var anim := "idle"
var strip := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="): model_path = a.substr(8)
		elif a.begins_with("--anim="): anim = a.substr(7)
		elif a == "--strip": strip = true

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2a1d14")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("ffd9a8")
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	add_child(env)

	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color("9a6a3e")
	var wall_m := StandardMaterial3D.new()
	wall_m.albedo_color = Color("e2b46a")
	_box(Vector3(14, 0.1, 4), Vector3(0, -0.05, 0), floor_m)
	_box(Vector3(14, 4, 0.1), Vector3(0, 2, -1.5), wall_m)

	var lamp := OmniLight3D.new()
	lamp.light_color = Color("ffcf8a")
	lamp.light_energy = 0.9
	lamp.omni_range = 12
	lamp.shadow_enabled = true
	lamp.position = Vector3(0, 3.2, 1.2)
	add_child(lamp)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.35
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()   # мягкий заполняющий свет со стороны камеры
	fill.light_energy = 0.5
	fill.light_color = Color("ffe6c8")
	fill.rotation_degrees = Vector3(-15, 0, 0)
	add_child(fill)
	var count := 6 if strip else 0     # без --strip модель грузит _load_model()
	var scene: PackedScene = load(model_path)
	for i in count:
		var m := scene.instantiate() as Node3D
		add_child(m)
		m.position = Vector3((i - (count - 1) * 0.5) * 1.15, 0, 0)
		m.rotation_degrees.y = 90   # смотрит вправо, как в игре
		var ap := m.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var a := ap.get_animation(anim)
		a.loop_mode = Animation.LOOP_LINEAR
		ap.play(anim)
		ap.seek(a.length * i / count, true)
		if strip:
			ap.speed_scale = 0.0

	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.0, 4.6 if not strip else 9.0), Vector3(0, 0.9, 0))
	_cam = cam
	if not strip:
		_label = Label.new()
		_label.add_theme_font_size_override("font_size", 26)
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 8)
		_label.position = Vector2(20, 14)
		var ui := CanvasLayer.new()
		add_child(ui)
		ui.add_child(_label)
		_load_model(model_path)

## Загрузить персонажа (или заменить текущего — по Tab).
func _load_model(path: String) -> void:
	var keep_rot := 90.0
	if _model:
		keep_rot = _model.rotation_degrees.y
		_model.queue_free()
	_bottle = null
	_phone = null
	model_path = path
	_model = (load(path) as PackedScene).instantiate() as Node3D
	add_child(_model)
	_model.rotation_degrees.y = keep_rot     # 90 — смотрит вправо, как в игре
	_player = _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var prev: String = _names[_index] if _index < _names.size() else anim
	_names = Array(_player.get_animation_list())
	_names.erase("RESET")
	_index = maxi(0, _names.find(prev))
	_add_props()
	_play_current()

## Временные предметы в руке (бутылка, телефон) на костях-точках RightHandGrip / RightHandPhone.
var _bottle: Node3D
var _phone: Node3D

func _add_props() -> void:
	var sk := _model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty() or (sk[0] as Skeleton3D).find_bone("RightHandGrip") < 0:
		return
	_bottle = _prop(sk[0], "RightHandGrip", Color("2f7a3c"), true)
	_phone = _prop(sk[0], "RightHandPhone", Color("1c1c24"), false)

func _prop(sk: Skeleton3D, bone: String, col: Color, bottle: bool) -> Node3D:
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	sk.add_child(att)
	var mi := MeshInstance3D.new()
	if bottle:              # бутылка Ø 7 см, 26 см; ось кости — к горлышку
		var cy := CylinderMesh.new()
		cy.top_radius = 0.035; cy.bottom_radius = 0.035; cy.height = 0.26
		mi.mesh = cy
	else:                   # телефон 7.5 x 15 x 0.9 см; ось кости — длинная сторона
		var bx := BoxMesh.new()
		bx.size = Vector3(0.075, 0.15, 0.009)
		mi.mesh = bx
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.4
	mi.material_override = m
	att.add_child(mi)
	return att

# --- просмотр: переключение клипов с клавиатуры ---------------------------------------
var _cam: Camera3D
var _model: Node3D
var _player: AnimationPlayer
var _names: Array = []
var _index := 0
var _label: Label
var _zoom := 4.6

func _play_current() -> void:
	var n: String = _names[_index]
	var a := _player.get_animation(n)
	a.loop_mode = Animation.LOOP_LINEAR
	_player.play(n)
	_player.speed_scale = 1.0
	if _bottle:
		_bottle.visible = n == "drink"
		_phone.visible = n == "phone"

func _process(_delta: float) -> void:
	if _player == null:
		return
	var n: String = _names[_index]
	var a := _player.get_animation(n)
	_label.text = "[%s]  %d/%d  %s   %.2f / %.2f с   скорость x%.2f%s\nTab — персонаж   ←/→ клип   пробел пауза   ,/. кадр   ↑/↓ скорость   A/D повернуть   колесо — зум   R — сброс" % [
		model_path.get_file().get_basename(), _index + 1, _names.size(), n, _player.current_animation_position, a.length,
		absf(_player.speed_scale) if _player.speed_scale != 0.0 else _paused_speed,
		"  (пауза)" if _player.speed_scale == 0.0 else ""]
	if Input.is_key_pressed(KEY_A):
		_model.rotation_degrees.y -= 120.0 * _delta
	if Input.is_key_pressed(KEY_D):
		_model.rotation_degrees.y += 120.0 * _delta

var _paused_speed := 1.0

func _unhandled_input(e: InputEvent) -> void:
	if _player == null:
		return
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP: _zoom = maxf(1.2, _zoom - 0.3)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN: _zoom = minf(9.0, _zoom + 0.3)
		_cam.look_at_from_position(Vector3(0, 1.0, _zoom), Vector3(0, 0.9 if _zoom > 2.5 else 1.15, 0))
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_TAB:
			_load_model(MODELS[(MODELS.find(model_path) + 1) % MODELS.size()])
		KEY_RIGHT:
			_index = (_index + 1) % _names.size(); _play_current()
		KEY_LEFT:
			_index = (_index - 1 + _names.size()) % _names.size(); _play_current()
		KEY_SPACE:
			if _player.speed_scale == 0.0:
				_player.speed_scale = _paused_speed
			else:
				_paused_speed = _player.speed_scale; _player.speed_scale = 0.0
		KEY_UP:
			_player.speed_scale = minf(2.0, (_player.speed_scale if _player.speed_scale != 0.0 else _paused_speed) * 1.5)
		KEY_DOWN:
			_player.speed_scale = maxf(0.1, (_player.speed_scale if _player.speed_scale != 0.0 else _paused_speed) / 1.5)
		KEY_PERIOD, KEY_COMMA:
			if _player.speed_scale != 0.0:
				_paused_speed = _player.speed_scale; _player.speed_scale = 0.0
			_player.seek(clampf(_player.current_animation_position + (1.0 if e.keycode == KEY_PERIOD else -1.0) / 30.0,
				0.0, _player.get_animation(_names[_index]).length), true)
		KEY_R:
			_model.rotation_degrees.y = 90; _zoom = 4.6
			_cam.look_at_from_position(Vector3(0, 1.0, _zoom), Vector3(0, 0.9, 0))

func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
