extends Node3D
## Проверка 3D-персонажа: тёплая комната-коробка, свет, анимация.
## --model=res://...glb  --anim=walk  --t=0.5 (секунда анимации на момент снимка)
##  --strip  — 6 копий персонажа в ряд, каждая в своей фазе анимации (раскадровка)

var model_path := "res://assets/models/characters/hero.glb"
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
	var count := 6 if strip else 1
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

func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
