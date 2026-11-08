extends Node3D
## Просмотр 3D-предметов: все .glb из assets/models/props рядами, с подписями.
## Мышь: правая кнопка — вращать камеру, колесо — зум. WASD/стрелки — двигаться, Q/E — вниз/вверх.
## F — следующий предмет крупно, R — общий вид. O — открыть/закрыть все подвижные части (клип open),
## P — рубильник щитка (switch). --open в аргументах — сразу открыть (для снимка).

const DIR := "res://assets/models/props/"
const GAP := 0.6          # промежуток между предметами
const ROW_W := 9.0        # ширина ряда, м

var _cam: Camera3D
var _target := Vector3(4.5, 0.6, 3.0)
var _yaw := 0.0
var _pitch := -0.75
var _dist := 15.0
var _items: Array = []    # [центр, размер, имя]
var _focus := -1
var _label: Label
var _home := Vector3.ZERO

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("b9ab95")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("fff1d8")
	e.ambient_light_energy = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.75
	e.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("8a6a4a")
	floor_mi.material_override = fm
	add_child(floor_mi)

	var files: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".glb"):
			files.append(f)
	files.sort()
	var x := 0.0
	var z := 0.0
	var row_depth := 0.0
	for f in files:
		var node := (load(DIR + f) as PackedScene).instantiate() as Node3D
		add_child(node)
		var box := _bounds(node)
		if x + box.size.x > ROW_W and x > 0.0:
			x = 0.0
			z += row_depth + GAP * 2.0
			row_depth = 0.0
		node.position = Vector3(x - box.position.x, -box.position.y, z - box.position.z)
		var center := node.position + box.get_center()
		_items.append([center, box.size, f.get_basename()])
		var lbl := Label3D.new()
		lbl.text = f.get_basename()
		lbl.font_size = 64
		lbl.pixel_size = 0.0025
		lbl.modulate = Color("3a2412")
		lbl.outline_size = 0
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(center.x, 0.04, z + box.size.z + 0.15)
		add_child(lbl)
		x += box.size.x + GAP
		row_depth = maxf(row_depth, box.size.z)
	_target = Vector3(ROW_W * 0.5, 0.5, (z + row_depth) * 0.5)
	_home = _target

	_cam = Camera3D.new()
	_cam.fov = 40
	add_child(_cam)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color("3a2412"))
	_label.position = Vector2(16, 12)
	_label.text = "%d предметов   O — открыть/закрыть   P — рубильник   ПКМ — вращать   колесо — зум   WASD — двигаться   Q/E — вниз/вверх   F — следующий крупно   R — общий вид" % _items.size()
	var ui := CanvasLayer.new()
	add_child(ui)
	ui.add_child(_label)
	_update_cam()
	for ap in find_children("*", "AnimationPlayer", true, false):
		_players.append(ap)
	if "--open" in OS.get_cmdline_user_args():
		_toggle("open")

func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b: AABB = m.transform * m.get_aabb()
		var p := m.get_parent()
		while p != n and p is Node3D:
			b = (p as Node3D).transform * b
			p = p.get_parent()
		out = b if first else out.merge(b)
		first = false
	return out

func _update_cam() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	_cam.look_at_from_position(_target + dir * _dist, _target)

func _process(delta: float) -> void:
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): mv.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): mv.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): mv.x += 1
	if Input.is_key_pressed(KEY_Q): mv.y -= 1
	if Input.is_key_pressed(KEY_E): mv.y += 1
	if mv != Vector3.ZERO:
		_target += Basis(Vector3.UP, _yaw) * mv * delta * maxf(1.5, _dist * 0.5)
		_update_cam()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= ev.relative.x * 0.006
		_pitch = clampf(_pitch - ev.relative.y * 0.006, -1.4, 0.3)
		_update_cam()
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: _dist = maxf(0.4, _dist * 0.88)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: _dist = minf(40.0, _dist / 0.88)
		_update_cam()
	elif ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_F and not _items.is_empty():
			_focus = (_focus + 1) % _items.size()
			var it: Array = _items[_focus]
			_target = it[0]
			_dist = maxf(0.5, (it[1] as Vector3).length() * 1.8)
			_label.text = "%d/%d  %s   (F — следующий, R — общий вид)" % [_focus + 1, _items.size(), it[2]]
			_update_cam()
		elif ev.keycode == KEY_O:
			_toggle("open")
		elif ev.keycode == KEY_P:
			_toggle("switch")
		elif ev.keycode == KEY_R:
			_ready_view()

func _ready_view() -> void:
	_focus = -1
	_yaw = 0.0; _pitch = -0.75; _dist = 15.0
	_target = _home
	_label.text = "%d предметов   O — открыть/закрыть   P — рубильник   ПКМ — вращать   колесо — зум   WASD — двигаться   Q/E — вниз/вверх   F — следующий крупно   R — общий вид" % _items.size()
	_update_cam()

var _players: Array = []
var _state := {}

## Проиграть клип у всех предметов, где он есть: туда, а при повторном нажатии — обратно.
func _toggle(clip: String) -> void:
	var opened: bool = not _state.get(clip, false)
	_state[clip] = opened
	for ap in _players:
		var p := ap as AnimationPlayer
		if not p.has_animation(clip):
			continue
		if opened:
			p.play(clip)
		else:
			p.play_backwards(clip)
