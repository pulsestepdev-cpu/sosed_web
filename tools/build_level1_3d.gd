extends SceneTree
## Сборка 3D-сцены уровня 1: квартира в разрезе (вид сбоку, срезы стен и перекрытий — кирпич).
## Godot.exe --headless --path . --script res://tools/build_level1_3d.gd
## Результат: res://scenes/level1_3d.tscn — обычная сцена, её можно открыть и править в редакторе.
##
## Оси: X — вдоль квартиры (вправо), Y — вверх, Z — к зрителю. Срез (ближняя к камере сторона) — z = 0,
## задняя стена — z = -D. Ходят персонажи по «дорожке» z ≈ LANE.
##   2-й этаж: [лестница][ванная  ][спальня ][балкон ][лестница]
##   1-й этаж: [лестница][прихожая][кухня   ][зал    ][лестница]

const H := 2.7          # высота комнаты
const SLAB := 0.35      # перекрытие
const D := 4.0          # глубина комнат
const OUTER := 0.3      # наружная стена
const PART := 0.2       # перегородка
const W := 17.0         # длина квартиры внутри
const F1 := 0.0
const F2 := H + SLAB    # пол 2-го этажа
const TOP := F2 + H     # потолок 2-го этажа
const LANE := -1.0      # дорожка, по которой ходят
const TEX := "res://assets/textures/level1/"
const PROPS := "res://assets/models/props/"
const CHARS := "res://assets/models/characters/"

# секции этажей: [x0, x1, обои, пол, имя]
const FLOOR1 := [[0.0, 3.0, "wall_stairs", "floor_parquet", "stairs_l"], [3.0, 7.0, "wall_hall", "floor_carpet", "hallway"],
	[7.0, 10.4, "wall_kitchen", "floor_kitchen", "kitchen"], [10.4, 14.0, "wall_living", "floor_parquet", "living"],
	[14.0, 17.0, "wall_stairs", "floor_parquet", "stairs_r"]]
const FLOOR2 := [[3.0, 6.4, "wall_bath", "floor_bath", "bathroom"], [6.4, 10.4, "wall_bedroom", "floor_parquet", "bedroom"],
	[10.4, 14.0, "brick", "floor_balcony", "balcony"]]

var lvl: Node3D
var mats := {}

func _init() -> void:
	lvl = Node3D.new()
	lvl.name = "Level1"
	lvl.set_script(load("res://scripts/game3d/level1_view.gd"))
	build_shell()
	build_stairs(0.0, 1.0)
	build_stairs(W, -1.0)
	build_doors_windows()
	build_furniture()
	build_characters()
	build_lights_camera()
	var ps := PackedScene.new()
	var err := ps.pack(lvl)
	if err != OK:
		push_error("pack: %d" % err)
	ResourceSaver.save(ps, "res://scenes/level1_3d.tscn")
	print("LEVEL_OK nodes=%d" % _count(lvl))
	quit()

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

func _own(n: Node, parent: Node = null) -> Node:
	(parent if parent else lvl).add_child(n)
	n.owner = lvl
	return n

# ---------------------------------------------------------------- материалы и коробки
func tex_mat(name: String, scale := 1.05) -> StandardMaterial3D:
	var key := name + str(scale)
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + name + ".png")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats[key] = m
	return m

func color_mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var key := c.to_html() + str(rough)
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	mats[key] = m
	return m

func box(name: String, a: Vector3, b: Vector3, m: Material, parent: Node = null) -> MeshInstance3D:
	## коробка от угла a до угла b
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = (b - a).abs()
	mi.mesh = bm
	mi.position = (a + b) * 0.5
	mi.material_override = m
	_own(mi, parent)
	return mi

## Стена вдоль X (задняя) с проёмами: holes = [[x0, x1, y0, y1], ...]
func wall_x(name: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, m: Material, holes: Array, parent: Node) -> void:
	var hs := holes.filter(func(h): return h[1] > x0 and h[0] < x1)
	hs.sort_custom(func(a, b): return a[0] < b[0])
	var x := x0
	var i := 0
	for h in hs:
		if h[0] > x:
			box("%s_%d" % [name, i], Vector3(x, y0, z0), Vector3(h[0], y1, z1), m, parent); i += 1
		if h[2] > y0:
			box("%s_%d" % [name, i], Vector3(h[0], y0, z0), Vector3(h[1], h[2], z1), m, parent); i += 1
		if h[3] < y1:
			box("%s_%d" % [name, i], Vector3(h[0], h[3], z0), Vector3(h[1], y1, z1), m, parent); i += 1
		x = h[1]
	if x < x1:
		box("%s_%d" % [name, i], Vector3(x, y0, z0), Vector3(x1, y1, z1), m, parent)

## Перегородка поперёк X с проёмом по глубине [oz0, oz1] высотой oh. Сердцевина кирпич (виден на срезе),
## с боков — обои комнат слева/справа.
func partition(x: float, y0: float, y1: float, oz0: float, oz1: float, oh: float, left_wall: String, right_wall: String, parent: Node) -> void:
	var t := PART * 0.5
	var segs := [[-D, oz0, y0, y1], [oz1, 0.0, y0, y1], [oz0, oz1, y0 + oh, y1]]
	var n := 0
	for s in segs:
		if s[1] - s[0] < 0.01 or s[3] - s[2] < 0.01:
			continue
		box("part_%d" % n, Vector3(x - t, s[2], s[0]), Vector3(x + t, s[3], s[1]), tex_mat("brick"), parent)
		var zf := minf(s[1], -0.03)
		if left_wall != "":
			box("part_%d_l" % n, Vector3(x - t - 0.012, s[2], s[0]), Vector3(x - t, s[3], zf), tex_mat(left_wall), parent)
		if right_wall != "":
			box("part_%d_r" % n, Vector3(x + t, s[2], s[0]), Vector3(x + t + 0.012, s[3], zf), tex_mat(right_wall), parent)
		n += 1

# ---------------------------------------------------------------- коробка дома
var HOLES := []    # проёмы в задней стене: [x0, x1, y0, y1]

func build_shell() -> void:
	var shell := _own(Node3D.new()) as Node3D
	shell.name = "Shell"
	# окна и входная дверь — проёмы в задней стене
	HOLES = [[5.95, 6.85, F1, F1 + 2.08],                      # входная дверь (прихожая)
		[11.05, 12.15, F1 + 1.1, F1 + 2.42],                     # окно зала
		[7.85, 8.95, F2 + 1.25, F2 + 2.57],                      # окно спальни
		[11.35, 12.45, F2 + 0.9, F2 + 2.22], [12.65, 13.75, F2 + 0.9, F2 + 2.22],   # окна балкона
		[0.95, 2.05, F2 + 0.6, F2 + 1.92], [14.95, 16.05, F2 + 0.6, F2 + 1.92]]   # окна на лестницах
	var brick := tex_mat("brick")
	# фундамент, перекрытие, крыша, наружные стены — кирпич
	box("foundation", Vector3(-OUTER, -0.7, -D - OUTER), Vector3(W + OUTER, F1 - 0.02, 0), brick, shell)
	box("slab_2", Vector3(3.0 - PART * 0.5, H, -D - OUTER), Vector3(14.0 + PART * 0.5, F2 - 0.02, 0), brick, shell)
	box("roof", Vector3(-OUTER, TOP, -D - OUTER), Vector3(W + OUTER, TOP + SLAB, 0), brick, shell)
	box("roof_edge", Vector3(-OUTER - 0.15, TOP + SLAB, -D - OUTER - 0.1), Vector3(W + OUTER + 0.15, TOP + SLAB + 0.12, 0.1),
		color_mat(Color("5a3b2a")), shell)
	box("outer_l", Vector3(-OUTER, -0.7, -D - OUTER), Vector3(0, TOP, 0), brick, shell)
	box("outer_r", Vector3(W, -0.7, -D - OUTER), Vector3(W + OUTER, TOP, 0), brick, shell)
	# задняя стена: кирпич снаружи + обои внутри, по секциям
	wall_x("back_brick", 0, W, F1, TOP, -D - OUTER, -D, brick, HOLES, shell)
	for sec in FLOOR1:
		var y1: float = TOP if String(sec[4]).begins_with("stairs") else H
		wall_x("back_" + sec[4], sec[0], sec[1], F1, y1, -D, -D + 0.012, tex_mat(sec[2]), HOLES, shell)
		box("floor_" + sec[4], Vector3(sec[0], F1 - 0.02, -D), Vector3(sec[1], F1, -0.02), tex_mat(sec[3], 0.9), shell)
		box("baseboard_" + sec[4], Vector3(sec[0], F1, -D + 0.012), Vector3(sec[1], F1 + 0.09, -D + 0.035), color_mat(Color("6e4428")), shell)
		if not String(sec[4]).begins_with("stairs"):
			box("ceiling_" + sec[4], Vector3(sec[0], H - 0.012, -D), Vector3(sec[1], H, -0.02), color_mat(Color("efe6d2")), shell)
	for sec in FLOOR2:
		wall_x("back_" + sec[4], sec[0], sec[1], F2, TOP, -D, -D + 0.012, tex_mat(sec[2]), HOLES, shell)
		box("floor_" + sec[4], Vector3(sec[0], F2 - 0.02, -D), Vector3(sec[1], F2, -0.02), tex_mat(sec[3], 0.9), shell)
		box("baseboard_" + sec[4], Vector3(sec[0], F2, -D + 0.012), Vector3(sec[1], F2 + 0.09, -D + 0.035), color_mat(Color("6e4428")), shell)
	for x0 in [0.0, 3.0, 6.4, 10.4, 14.0]:
		var x1: float = {0.0: W, 3.0: 6.4, 6.4: 10.4, 10.4: 14.0, 14.0: W}[x0]
		if x0 == 0.0:
			box("ceiling_stairs_l", Vector3(0, TOP - 0.012, -D), Vector3(3.0, TOP, -0.02), color_mat(Color("efe6d2")), shell)
			box("ceiling_stairs_r", Vector3(14.0, TOP - 0.012, -D), Vector3(W, TOP, -0.02), color_mat(Color("efe6d2")), shell)
		elif x0 != 14.0:
			box("ceiling2_%d" % int(x0 * 10), Vector3(x0, TOP - 0.012, -D), Vector3(x1, TOP, -0.02), color_mat(Color("efe6d2")), shell)
	# перегородки: на лестницы — широкие арки без дверей, между комнатами — дверные проёмы
	partition(3.0, F1, H, -1.65, -0.35, 2.3, "wall_stairs", "wall_hall", shell)
	partition(7.0, F1, H, LANE - 0.5, LANE + 0.5, 2.1, "wall_hall", "wall_kitchen", shell)
	partition(10.4, F1, H, LANE - 0.5, LANE + 0.5, 2.1, "wall_kitchen", "wall_living", shell)
	partition(14.0, F1, H, -1.65, -0.35, 2.3, "wall_living", "wall_stairs", shell)
	partition(3.0, F2, TOP, -2.75, -0.35, 2.3, "wall_stairs", "wall_bath", shell)
	partition(6.4, F2, TOP, LANE - 0.5, LANE + 0.5, 2.1, "wall_bath", "wall_bedroom", shell)
	partition(10.4, F2, TOP, LANE - 0.5, LANE + 0.5, 2.1, "wall_bedroom", "brick", shell)
	partition(14.0, F2, TOP, -2.75, -0.35, 2.3, "brick", "wall_stairs", shell)
	# небо и дома напротив — за окнами
	var sky := StandardMaterial3D.new()
	sky.albedo_texture = load(TEX + "sky.png")
	sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box("sky", Vector3(-0.2, 0.2, -D - 2.5), Vector3(W + 0.2, TOP - 0.2, -D - 2.45), sky, shell)
	box("entrance_dark", Vector3(5.8, F1, -D - OUTER - 0.4), Vector3(7.0, F1 + 2.2, -D - OUTER - 0.35), color_mat(Color("3d4a44")), shell)

## Лестница с площадкой: нижний марш спереди (от комнаты 1-го этажа к площадке у наружной стены),
## верхний — сзади (с площадки к комнате 2-го этажа). side = +1 — левая лестница, -1 — правая (зеркально).
func build_stairs(x_outer: float, side: float) -> void:
	var st := _own(Node3D.new()) as Node3D
	st.name = "Stairs_" + ("L" if side > 0 else "R")
	var wood := color_mat(Color("8a5a32"))
	var dark := color_mat(Color("5b3a22"))
	var n := 7
	var half := F2 * 0.5
	var x_room := x_outer + side * 2.9          # край у комнаты
	var x_land := x_outer + side * 0.7          # край площадки
	var run := absf(x_room - x_land) / n
	for i in n:
		# нижний марш: от комнаты (низ) к площадке (верх), спереди
		var xa := x_room - side * run * i
		var xb := x_room - side * run * (i + 1)
		var top := half * (i + 1) / n
		box("lower_%d" % i, Vector3(minf(xa, xb), F1, -1.55), Vector3(maxf(xa, xb), top, -0.45), wood, st)
		box("lower_nose_%d" % i, Vector3(minf(xa, xb), top - 0.03, -1.56), Vector3(maxf(xa, xb), top + 0.01, -0.44), dark, st)
		# верхний марш: от площадки к комнате 2-го этажа, сзади
		var xc := x_land + side * run * i
		var xd := x_land + side * run * (i + 1)
		var top2 := half + half * (i + 1) / n
		box("upper_%d" % i, Vector3(minf(xc, xd), top2 - 0.25, -2.7), Vector3(maxf(xc, xd), top2, -1.6), wood, st)
		box("upper_nose_%d" % i, Vector3(minf(xc, xd), top2 - 0.03, -2.71), Vector3(maxf(xc, xd), top2 + 0.01, -1.59), dark, st)
	box("landing", Vector3(minf(x_outer, x_land), half - 0.25, -2.7), Vector3(maxf(x_outer, x_land), half, -0.45), wood, st)
	box("landing_post", Vector3(minf(x_outer, x_land) + 0.05, F1, -0.6), Vector3(minf(x_outer, x_land) + 0.15, half, -0.5), dark, st)
	box("top_step", Vector3(minf(x_room, x_room + side * 0.12), F2 - 0.25, -2.7), Vector3(maxf(x_room, x_room + side * 0.12), F2, -1.6), wood, st)
	# перила вдоль нижнего марша (спереди)
	for i in range(0, n + 1, 2):
		var x := x_room - side * run * i
		box("baluster_%d" % i, Vector3(x - 0.025, half * i / n, -0.5), Vector3(x + 0.025, half * i / n + 0.9, -0.45), dark, st)
	var rail := MeshInstance3D.new()
	rail.name = "handrail"
	var bm := BoxMesh.new()
	var length := sqrt(pow(absf(x_room - x_land), 2) + half * half)
	bm.size = Vector3(length, 0.05, 0.06)
	rail.mesh = bm
	rail.material_override = dark
	rail.position = Vector3((x_room + x_land) * 0.5, half * 0.5 + 0.9, -0.475)
	rail.rotation.z = atan2(half, x_land - x_room) if side > 0 else atan2(-half, x_room - x_land)
	_own(rail, st)

# ---------------------------------------------------------------- предметы
func _aabb(n: Node, xf: Transform3D, out: Array) -> void:
	if n is MeshInstance3D:
		var b: AABB = (n as MeshInstance3D).get_aabb()
		out.append(xf * b)
	for c in n.get_children():
		if c is Node3D:
			_aabb(c, xf * (c as Node3D).transform, out)

func bounds(n: Node3D) -> AABB:
	var list: Array = []
	_aabb(n, n.transform, list)
	var b: AABB = list[0]
	for x in list.slice(1):
		b = b.merge(x)
	return b

## Поставить предмет. z: число — точная глубина; "back" — вплотную к задней стене (+ gap); "wall" — на стену.
func put(name: String, x: float, y: float, z: Variant = "back", yaw := 0.0, gap := 0.02, parent: Node = null, label := "") -> Node3D:
	var inst := (load(PROPS + name + ".glb") as PackedScene).instantiate() as Node3D
	inst.name = label if label != "" else name
	_own(inst, parent if parent else _furn)
	inst.rotation_degrees.y = yaw
	inst.position = Vector3(x, y, 0.0)
	if z is String and z == "back":
		var b := bounds(inst)
		inst.position.z = (-D + 0.012 + gap) - b.position.z
	elif z is String and z == "wall":
		inst.position.z = -D + 0.012
	else:
		inst.position.z = float(z)
	return inst

var _furn: Node3D

func build_doors_windows() -> void:
	_furn = _own(Node3D.new()) as Node3D
	_furn.name = "Furniture"
	var doors := _own(Node3D.new(), _furn) as Node3D
	doors.name = "Doors"
	put("door", 7.0, F1, LANE, 90, 0, doors, "door_hall_kitchen")
	put("door", 10.4, F1, LANE, 90, 0, doors, "door_kitchen_living")
	put("door", 6.4, F2, LANE, 90, 0, doors, "door_bath_bedroom")
	put("door", 10.4, F2, LANE, -90, 0, doors, "door_bedroom_balcony")
	put("door", 6.4, F1, "wall", 0, 0, doors, "door_entrance")
	var wins := _own(Node3D.new(), _furn) as Node3D
	wins.name = "Windows"
	for w in [[11.6, F1 + 1.1], [8.4, F2 + 1.25], [11.9, F2 + 0.9], [13.2, F2 + 0.9], [1.5, F2 + 0.6], [15.5, F2 + 0.6]]:
		put("window", w[0], w[1], "wall", 0, 0, wins, "window_%d" % int(w[0] * 10))

func build_furniture() -> void:
	var f := _furn
	# прихожая (1 этаж, x 3..7): шкаф-купе (прятки), столик с ключами, щиток, вешалка с курткой, обувь
	put("wardrobe", 3.72, F1)
	put("console_table", 4.75, F1)
	put("key_bowl", 4.62, F1 + 0.8, -D + 0.22)
	put("electric_panel", 4.75, F1 + 1.4, "wall")
	put("coat_rack", 5.5, F1 + 1.75, "wall")
	put("shoe_shelf", 5.5, F1)
	put("chandelier", 6.4, H, -2.3)
	put("stepladder", 6.4, F1, -2.35)    # лампочку меняет в прихожей
	put("rug", 5.0, F1, -1.3)
	put("wall_lamp", 6.4, F1 + 2.25, "wall")
	# кухня (x 7..10.4): гарнитур, холодильник (минералка/салат), стол (прятки), стулья, кофе, фрукты
	put("kitchen_counter", 8.05, F1)
	put("fridge", 9.9, F1)
	put("microwave", 8.62, F1 + 0.92, -D + 0.32)
	put("coffee_maker", 7.42, F1 + 0.92, -D + 0.2)
	put("table", 8.7, F1, -1.95)
	put("chair", 7.95, F1, -1.95, 90)
	put("chair", 9.45, F1, -1.95, -90, 0.02, null, "chair_2")
	put("coffee_mug", 8.45, F1 + 0.775, -1.85)
	put("fruit_bowl", 8.95, F1 + 0.775, -2.05)
	put("chandelier", 8.7, H, -1.9, 0, 0.0, null, "chandelier_kitchen")
	# зал (x 10.4..14): диван (прятки, щель за спинкой), тумба с ТВ и приставкой, газировка
	put("sofa", 11.6, F1, "back", 0, 0.38)
	put("smartphone", 11.1, F1 + 0.48, -D + 0.85)
	put("tv_stand", 13.2, F1)
	put("tv", 13.2, F1 + 0.5, -D + 0.25)
	put("gamepad", 12.8, F1 + 0.5, -D + 0.5)
	put("soda_bottle", 12.95, F1 + 0.5, -D + 0.42)
	put("chandelier", 12.4, H, -2.3, 0, 0.0, null, "chandelier_living")
	put("rug", 12.2, F1, -1.6, 0, 0.0, null, "rug_living")
	put("plant", 13.75, F1, -0.6)
	put("radiator", 13.6, F1 + 0.12, "wall")
	# ванная (2 этаж, x 3..6.4): ванна со шторкой (прятки), раковина (фанфурик), полочка (ополаскиватель), унитаз (пиво)
	# всё сдвинуто влево от перегородки: у x > 5.9 предметы у задней стены закрывает стена спальни
	put("bathtub", 3.85, F2).scale.x = 0.82
	put("shower_curtain", 3.85, F2, -D + 0.8).scale.x = 0.82
	put("sink_vanity", 4.92, F2)
	put("mirror_cabinet", 4.92, F2 + 1.32, "wall")
	put("bath_shelf", 4.92, F2 + 1.16, "wall")
	put("toilet", 5.55, F2)
	put("wall_lamp", 4.0, F2 + 2.25, "wall", 0, 0, null, "wall_lamp_bath")
	# спальня (x 6.4..10.4): кровать (прятки), комод, часы; справа сосед шпаклюет стену
	put("dresser", 6.98, F2)
	put("bed", 8.4, F2)
	put("putty_bucket", 10.12, F2, -3.62)
	put("clock", 10.05, F2 + 1.85, "wall")
	put("chandelier", 8.4, TOP, -2.0, 0, 0.0, null, "chandelier_bedroom")
	put("rug", 8.4, F2, -1.2, 0, 0.0, null, "rug_bedroom")
	# балкон (x 10.4..14): стеллаж с банками (водка), ящик с инструментами (лампочка), лыжи (прятки)
	put("balcony_shelf", 11.0, F2)
	put("toolbox", 11.95, F2)
	put("antifreeze", 12.45, F2)
	put("plant", 12.95, F2, "back", 0, 0.02, null, "plant_balcony")
	put("skis", 13.55, F2)
	# лестницы: лампы
	put("wall_lamp", 1.5, F1 + 2.2, "wall", 0, 0, null, "wall_lamp_stairs_l")
	put("wall_lamp", 15.5, F1 + 2.2, "wall", 0, 0, null, "wall_lamp_stairs_r")

func build_characters() -> void:
	var ch := _own(Node3D.new()) as Node3D
	ch.name = "Characters"
	var n := (load(CHARS + "neighbor.glb") as PackedScene).instantiate() as Node3D
	n.name = "Neighbor"
	_own(n, ch)
	n.position = Vector3(9.05, F1, LANE)
	var h := (load(CHARS + "hero.glb") as PackedScene).instantiate() as Node3D
	h.name = "Hero"
	_own(h, ch)
	h.position = Vector3(4.3, F1, LANE)
	h.rotation_degrees.y = 90

func build_lights_camera() -> void:
	var env := WorldEnvironment.new()
	env.name = "Environment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2a1d16")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("ffe2bd")
	e.ambient_light_energy = 0.28
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.85
	e.ssao_enabled = true
	e.ssao_radius = 0.6
	e.glow_enabled = false
	e.glow_intensity = 0.3
	env.environment = e
	_own(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 0.45
	sun.light_color = Color("fff0d8")
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.shadow_enabled = true
	_own(sun)
	var lights := _own(Node3D.new()) as Node3D
	lights.name = "RoomLights"
	for l in [[1.5, 2.2], [5.0, 1.9], [8.7, 1.9], [12.2, 1.9], [15.5, 2.2], [4.6, F2 + 1.9], [8.4, F2 + 1.9], [12.2, F2 + 1.9], [1.5, F2 + 1.9], [15.5, F2 + 1.9]]:
		var o := OmniLight3D.new()
		o.name = "lamp_%d_%d" % [int(l[0] * 10), int(l[1] * 10)]
		o.light_color = Color("ffd59a")
		o.light_energy = 0.55
		o.omni_range = 4.2
		o.position = Vector3(l[0], l[1], -1.6)
		_own(o, lights)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = 29
	cam.position = Vector3(W * 0.5, TOP * 0.5, 19.0)
	_own(cam)
	cam.transform = Transform3D(Basis.looking_at(Vector3(W * 0.5, TOP * 0.5 - 0.1, -1.5) - cam.position), cam.position)
	cam.current = true
