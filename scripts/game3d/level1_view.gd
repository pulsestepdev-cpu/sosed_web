extends Node3D
## Просмотрщик сцены дня (сцены собирает tools/build_level_3d.gd): камера, двери и тайники, персонажи.
## Управление: колесо — зум, правая кнопка (или WASD/стрелки) — двигать камеру, R — общий вид,
## O — открыть/закрыть все двери и тайники, P — рубильник, N / H — следующий клип соседа / героя,
## клик левой кнопкой по предмету — открыть/закрыть только его.

const FACE_DIR := "res://assets/models/characters/"
const FACE_FOR_CLIP := {
	"neighbor": {"drink": "tipsy", "walk_drunk": "drunk", "dance": "drunk", "fall_back": "drunk",
		"lie_back": "drunk", "get_up": "drunk", "kick": "angry", "angry": "angry", "catch": "angry",
		"sleep": "sleep", "fall_forward": "sleep", "lie_forward": "sleep", "oath": "happy"},
	"hero": {"caught": "scared", "success": "happy", "laugh": "happy", "sneak": "sneaky",
		"hide_table": "sneaky", "hide_wardrobe": "sneaky", "hide_curtain": "sneaky", "hide_bed": "sneaky",
		"hide_sofa": "sneaky", "hide_skis": "sneaky", "swap": "sneaky"},
}

var _cam: Camera3D
var _home: Transform3D
var _home_fov := 29.0
var _players: Array = []        # плееры предметов (open/switch)
var _state := {}
var _chars := {}                # имя -> {player, clips, index, mat, kind}
var _label: Label

func _ready() -> void:
	_cam = $Camera
	_home = _cam.transform
	_home_fov = _cam.fov
	for ap in $Furniture.find_children("*", "AnimationPlayer", true, false):
		_players.append(ap)
	_setup_char($Characters/Neighbor, "neighbor", "drink")
	_setup_char($Characters/Hero, "hero", "sneak")
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color("fff3dc"))
	_label.add_theme_color_override("font_outline_color", Color("2b1a10"))
	_label.add_theme_constant_override("outline_size", 6)
	_label.position = Vector2(14, 10)
	var ui := CanvasLayer.new()
	add_child(ui)
	ui.add_child(_label)
	_update_label()
	if "--open" in OS.get_cmdline_user_args():
		_toggle("open")

func _setup_char(node: Node3D, kind: String, clip: String) -> void:
	var ap := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var clips := Array(ap.get_animation_list())
	clips.erase("RESET")
	var mat: StandardMaterial3D = null
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh.surface_get_material(0)
		if m is StandardMaterial3D and mi.get_parent() is Skeleton3D:
			mat = (m as StandardMaterial3D).duplicate()
			(mi as MeshInstance3D).set_surface_override_material(0, mat)
			break
	_chars[kind] = {"player": ap, "clips": clips, "index": maxi(0, clips.find(clip)), "mat": mat}
	_play_char(kind)

func _play_char(kind: String) -> void:
	var c: Dictionary = _chars[kind]
	var clip: String = c["clips"][c["index"]]
	var ap: AnimationPlayer = c["player"]
	ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	ap.play(clip)
	var face: String = FACE_FOR_CLIP[kind].get(clip, "normal")
	if c["mat"]:
		var tex := load(FACE_DIR + "%s_face_%s.jpg" % [kind, face]) as Texture2D
		if tex:
			(c["mat"] as StandardMaterial3D).albedo_texture = tex
	_update_label()
	if "--open" in OS.get_cmdline_user_args():
		_toggle("open")

func _update_label() -> void:
	if _label == null or _chars.size() < 2:
		return
	_label.text = "Дом — 3D.  Сосед: %s   Герой: %s\nколесо — зум   ПКМ/WASD — двигать   R — общий вид   O — открыть всё   клик — открыть предмет   P — рубильник   N/H — клип соседа/героя" % [
		_chars["neighbor"]["clips"][_chars["neighbor"]["index"]], _chars["hero"]["clips"][_chars["hero"]["index"]]]

## Открыть/закрыть: все предметы с клипом или один плеер.
func _toggle(clip: String, only: AnimationPlayer = null) -> void:
	var list: Array = [only] if only else _players
	var key := clip + (str(only.get_instance_id()) if only else "")
	var opened: bool = not _state.get(key, false)
	_state[key] = opened
	for ap in list:
		var p := ap as AnimationPlayer
		if p.has_animation(clip):
			if opened:
				p.play(clip)
			else:
				p.play_backwards(clip)

func _process(delta: float) -> void:
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): mv.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): mv.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): mv.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): mv.y -= 1
	if mv != Vector2.ZERO:
		_cam.position += Vector3(mv.x, mv.y, 0) * delta * 0.25 * _cam.fov / 34.0 * 20.0

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam.fov = maxf(8.0, _cam.fov * 0.9)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam.fov = minf(60.0, _cam.fov / 0.9)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			_click(ev.position)
	elif ev is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var k := 0.0025 * _cam.fov / 34.0 * 19.0
		_cam.position += Vector3(-ev.relative.x * k, ev.relative.y * k, 0)
	elif ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_R:
				_cam.transform = _home
				_cam.fov = _home_fov
			KEY_O:
				_toggle("open")
			KEY_P:
				_toggle("switch")
			KEY_N:
				_next("neighbor")
			KEY_H:
				_next("hero")

func _next(kind: String) -> void:
	var c: Dictionary = _chars[kind]
	c["index"] = (c["index"] + 1) % c["clips"].size()
	_play_char(kind)

## Клик по предмету: ближайший к лучу предмет с клипом open (по центрам), открыть/закрыть только его.
func _click(pos: Vector2) -> void:
	var from := _cam.project_ray_origin(pos)
	var dir := _cam.project_ray_normal(pos)
	var best: AnimationPlayer = null
	var best_d := 0.6
	for ap in _players:
		var p := ap as AnimationPlayer
		if not p.has_animation("open"):
			continue
		var owner3d := p.get_parent() as Node3D
		var c := owner3d.global_position + Vector3(0, 0.8, 0)
		var t := (c - from).dot(dir)
		var d := (from + dir * t).distance_to(c)
		if d < best_d:
			best_d = d
			best = p
	if best:
		_toggle("open", best)
