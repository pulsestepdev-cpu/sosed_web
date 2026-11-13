extends SceneTree
## Сборка 3D-сцен дней недели: дом в разрезе (вид сбоку, срезы стен и перекрытий — кирпич).
## Godot.exe --headless --path . --script res://tools/build_level_3d.gd -- [--day=N|all]
## Результат: res://scenes/levels/day_N.tscn — обычные сцены, их можно открыть в редакторе.
## Какие комнаты открыты в какой день — scripts/levels/days.gd. Закрытые части дома — глухая кладка.
##
## Оси: X — вдоль дома (вправо), Y — вверх, Z — к зрителю. Срез (ближняя к камере сторона) — z = 0,
## задняя стена — z = -D. Ходят персонажи по «дорожке» z ≈ LANE.
##   этаж  2: [         чердак                       ]
##   этаж  1: [лестн.][ванная  ][спальня ][балкон ][лестн.]
##   этаж  0: [лестн.][прихожая][кухня   ][зал    ][лестн.]
##   этаж -1: [   подвал                  ][ гараж          ]

const H := 2.7          # высота комнаты
const SLAB := 0.35      # перекрытие
const D := 4.0          # глубина комнат
const OUTER := 0.3      # наружная стена
const PART := 0.2       # перегородка
const FH := H + SLAB    # шаг этажей
const F1 := 0.0
const F2 := FH          # пол 2-го этажа
const TOP := F2 + H     # потолок 2-го этажа
const FB := -FH         # пол подвала
const FA := 2.0 * FH    # пол чердака
const LANE := -1.0
const TEX := "res://assets/textures/level1/"
const PROPS := "res://assets/models/props/"
const CHARS := "res://assets/models/characters/"

var lvl: Node3D
var mats := {}
var day: Dictionary
var W := 17.0
var has_living := false
var has_balcony := false
var has_r := false
var has_base := false
var has_garage := false
var has_attic := false
var _furn: Node3D
var HOLES := []    # проёмы в задней стене: [x0, x1, y0, y1]

func _init() -> void:
	var which := "all"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--day="):
			which = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/levels"))
	var days := range(1, 8) if which == "all" else [int(which)]
	for n in days:
		build_day(n)
	quit()

func build_day(n: int) -> void:
	day = Days.day(n)
	var rooms: Array = day["rooms"]
	W = day["w"]
	has_living = "living" in rooms
	has_balcony = "balcony" in rooms
	has_r = W >= 16.9
	has_base = "basement" in rooms
	has_garage = "garage" in rooms
	has_attic = "attic" in rooms
	lvl = Node3D.new()
	lvl.name = "Day%d" % n
	lvl.set_script(load("res://scripts/game3d/level1_view.gd"))
	build_shell()
	build_stairs(0.0, 1.0)
	if has_r:
		build_stairs(W, -1.0)
	if has_attic:
		build_gallery()
	build_doors_windows()
	build_furniture()
	build_characters()
	build_lights_camera()
	var ps := PackedScene.new()
	var err := ps.pack(lvl)
	if err != OK:
		push_error("pack: %d" % err)
	var path: String = day["scene"]
	ResourceSaver.save(ps, path)
	print("LEVEL_OK day=%d nodes=%d -> %s" % [n, _count(lvl), path])
	lvl.free()

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
func tex_mat(name: String, scale := 1.05, tint := Color.WHITE) -> StandardMaterial3D:
	var key := name + str(scale) + tint.to_html()
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + name + ".png")
	m.albedo_color = tint
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

## Стена вдоль X (задняя) с проёмами: holes = [[x0, x1, y0, y1], ...]. Стена режется по X на полосы
## по краям проёмов, в каждой полосе — куски между проёмами по высоте (проёмы могут пересекаться по X).
func wall_x(name: String, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, m: Material, holes: Array, parent: Node) -> void:
	var hs := holes.filter(func(h): return h[1] > x0 and h[0] < x1 and h[3] > y0 and h[2] < y1)
	var xs := [x0, x1]
	for h in hs:
		for v in [h[0], h[1]]:
			if v > x0 and v < x1 and not xs.has(v):
				xs.append(v)
	xs.sort()
	var i := 0
	for k in xs.size() - 1:
		var a: float = xs[k]
		var b: float = xs[k + 1]
		var mid := (a + b) * 0.5
		var gaps := hs.filter(func(h): return h[0] < mid and h[1] > mid).map(func(h): return [maxf(h[2], y0), minf(h[3], y1)])
		gaps.sort_custom(func(p, q): return p[0] < q[0])
		var y := y0
		for g in gaps:
			if g[0] > y:
				box("%s_%d" % [name, i], Vector3(a, y, z0), Vector3(b, g[0], z1), m, parent)
				i += 1
			y = maxf(y, g[1])
		if y < y1:
			box("%s_%d" % [name, i], Vector3(a, y, z0), Vector3(b, y1, z1), m, parent)
			i += 1

## Перегородка поперёк X с проёмом по глубине [oz0, oz1] высотой oh (oh = 0 — глухая). Сердцевина кирпич
## (виден на срезе), с боков — обои комнат слева/справа.
func partition(x: float, y0: float, y1: float, oz0: float, oz1: float, oh: float, left_wall: String, right_wall: String, parent: Node) -> void:
	var t := PART * 0.5
	var segs := [[-D, oz0, y0, y1], [oz1, 0.0, y0, y1], [oz0, oz1, y0 + oh, y1]]
	var n := 0
	for s in segs:
		if s[1] - s[0] < 0.01 or s[3] - s[2] < 0.01:
			continue
		box("part_%d_%d" % [int(x * 10), n], Vector3(x - t, s[2], s[0]), Vector3(x + t, s[3], s[1]), tex_mat("brick"), parent)
		var zf := minf(s[1], -0.03)
		if left_wall != "":
			box("part_%d_%d_l" % [int(x * 10), n], Vector3(x - t - 0.012, s[2], s[0]), Vector3(x - t, s[3], zf), tex_mat(left_wall), parent)
		if right_wall != "":
			box("part_%d_%d_r" % [int(x * 10), n], Vector3(x + t, s[2], s[0]), Vector3(x + t + 0.012, s[3], zf), tex_mat(right_wall), parent)
		n += 1

## Закрытая часть дома — глухая кладка (темнее обычной) на всю глубину.
func closed(name: String, x0: float, x1: float, y0: float, y1: float, parent: Node) -> void:
	box(name, Vector3(x0, y0, -D - OUTER), Vector3(x1, y1, 0), tex_mat("brick", 1.05, Color(0.72, 0.66, 0.62)), parent)

# ---------------------------------------------------------------- коробка дома
func _room(id: String) -> Array:
	return Days.ROOMS[id]

func _fy(f: int) -> float:
	return f * FH

func build_shell() -> void:
	var shell := _own(Node3D.new()) as Node3D
	shell.name = "Shell"
	var y_lo := FB if has_base else F1          # пол нижнего этажа
	var y_hi := FA + H if has_attic else TOP    # потолок верхнего
	# окна и двери — проёмы в задней стене
	HOLES = [[5.95, 6.85, F1, F1 + 2.08],                      # входная дверь (прихожая)
		[7.85, 8.95, F2 + 1.25, F2 + 2.57],                      # окно спальни
		[0.95, 2.05, F2 + 0.6, F2 + 1.92]]                       # окно на левой лестнице
	if has_living:
		HOLES.append([11.05, 12.15, F1 + 1.1, F1 + 2.42])        # окно зала
	if has_balcony:
		HOLES.append_array([[11.35, 12.45, F2 + 0.9, F2 + 2.22], [12.65, 13.75, F2 + 0.9, F2 + 2.22]])
	if has_r:
		if has_attic:
			HOLES.append([15.05, 15.95, F2, F2 + 2.08])          # дверь на чердак с площадки
		else:
			HOLES.append([14.95, 16.05, F2 + 0.6, F2 + 1.92])    # окно на правой лестнице
	if has_base:
		HOLES.append_array([[1.3, 2.2, F1, F1 + 2.08], [1.3, 2.2, FB, FB + 2.08]])   # дверь в подвал и из него
	if has_attic:
		HOLES.append_array([[15.05, 15.95, FA, FA + 2.08], [12.05, 13.15, FA + 1.0, FA + 1.9]])
	var brick := tex_mat("brick")
	# фундамент / земля
	if has_base:
		box("foundation", Vector3(-OUTER, FB - 0.7, -D - OUTER), Vector3(W + OUTER, FB - 0.02, 0), brick, shell)
		box("slab_0", Vector3(-OUTER, FB + H, -D - OUTER), Vector3(W + OUTER, F1 - 0.02, 0), brick, shell)
		var soil := color_mat(Color("5a3a24"), 0.95)
		var grass := color_mat(Color("6f8f3a"), 0.9)
		for side in [[-2.6, -OUTER], [W + OUTER, W + 2.6]]:
			box("soil_%d" % int(side[0]), Vector3(side[0], FB - 0.7, -D - OUTER), Vector3(side[1], F1 - 0.06, 0), soil, shell)
			box("grass_%d" % int(side[0]), Vector3(side[0], F1 - 0.06, -D - OUTER), Vector3(side[1], F1, 0), grass, shell)
	else:
		box("foundation", Vector3(-OUTER, -0.7, -D - OUTER), Vector3(W + OUTER, F1 - 0.02, 0), brick, shell)
	# перекрытие 1/2 этажа (над лестницами — проёмы)
	box("slab_2", Vector3(3.0 - PART * 0.5, H, -D - OUTER), Vector3((14.0 + PART * 0.5) if has_r else W, F2 - 0.02, 0), brick, shell)
	# крыша / чердак
	box("roof", Vector3(-OUTER, TOP, -D - OUTER), Vector3(W + OUTER, TOP + SLAB, 0), brick, shell)
	var roof_y := TOP + SLAB
	if has_attic:
		box("attic_roof", Vector3(-OUTER, FA + H, -D - OUTER), Vector3(W + OUTER, FA + H + SLAB, 0), brick, shell)
		roof_y = FA + H + SLAB
		closed("closed_attic_l", -OUTER, 3.0 - PART * 0.5, FA, FA + H, shell)
	box("roof_edge", Vector3(-OUTER - 0.15, roof_y, -D - OUTER - 0.1), Vector3(W + OUTER + 0.15, roof_y + 0.12, 0.1),
		color_mat(Color("5a3b2a")), shell)
	var wall_lo := (FB - 0.7) if has_base else -0.7
	box("outer_l", Vector3(-OUTER, wall_lo, -D - OUTER), Vector3(0, roof_y, 0), brick, shell)
	box("outer_r", Vector3(W, wall_lo, -D - OUTER), Vector3(W + OUTER, roof_y, 0), brick, shell)
	# задняя стена: кирпич снаружи + обои внутри, по комнатам
	wall_x("back_brick", 0, W, y_lo, y_hi, -D - OUTER, -D, brick, HOLES, shell)
	var secs := [[0.0, 3.0, 0, "wall_stairs", "floor_parquet", "stairs_l", TOP]]
	if has_r:
		secs.append([14.0, W, 0, "wall_stairs", "floor_parquet", "stairs_r", TOP])
	for id in day["rooms"]:
		var r := _room(id)
		secs.append([r[0], r[1], r[2], r[3], r[4], id, _fy(r[2]) + H])
	for s in secs:
		var fy := _fy(s[2])
		var y1: float = s[6]
		wall_x("back_" + s[5], s[0], s[1], fy, y1, -D, -D + 0.012, tex_mat(s[3]), HOLES, shell)
		box("floor_" + s[5], Vector3(s[0], fy - 0.02, -D), Vector3(s[1], fy, -0.02), tex_mat(s[4], 0.9), shell)
		box("baseboard_" + s[5], Vector3(s[0], fy, -D + 0.012), Vector3(s[1], fy + 0.09, -D + 0.035), color_mat(Color("6e4428")), shell)
		var ceil_c := Color("efe6d2") if s[2] in [0, 1] else (Color("b8b2a6") if s[2] < 0 else Color("6e4a2c"))
		box("ceiling_" + s[5], Vector3(s[0], y1 - 0.012, -D), Vector3(s[1], y1, -0.02), color_mat(ceil_c), shell)
	# закрытые части
	if not has_balcony and W > 10.5:
		closed("closed_balcony", 10.4 + PART * 0.5, W, F2, TOP, shell)
	if has_base and not has_garage:
		closed("closed_garage", 10.4 + PART * 0.5, W, FB, FB + H, shell)
	# перегородки: на лестницы — широкие арки без дверей, между комнатами — дверные проёмы
	partition(3.0, F1, H, -1.65, -0.35, 2.3, "wall_stairs", "wall_hall", shell)
	partition(7.0, F1, H, LANE - 0.5, LANE + 0.5, 2.1, "wall_hall", "wall_kitchen", shell)
	if has_living:
		partition(10.4, F1, H, LANE - 0.5, LANE + 0.5, 2.1, "wall_kitchen", "wall_living", shell)
	if has_r:
		partition(14.0, F1, H, -1.65, -0.35, 2.3, "wall_living", "wall_stairs", shell)
	partition(3.0, F2, TOP, -2.75, -0.35, 2.3, "wall_stairs", "wall_bath", shell)
	partition(6.4, F2, TOP, LANE - 0.5, LANE + 0.5, 2.1, "wall_bath", "wall_bedroom", shell)
	if has_balcony:
		partition(10.4, F2, TOP, LANE - 0.5, LANE + 0.5, 2.1, "wall_bedroom", "brick", shell)
	elif W > 10.5:
		partition(10.4, F2, TOP, LANE - 0.5, LANE + 0.5, 0.0, "wall_bedroom", "", shell)
	if has_r:
		partition(14.0, F2, TOP, -2.75, -0.35, 2.3, "brick", "wall_stairs", shell)
	if has_garage:
		partition(10.4, FB, FB + H, LANE - 0.5, LANE + 0.5, 2.1, "wall_basement", "wall_garage", shell)
	elif has_base:
		partition(10.4, FB, FB + H, LANE - 0.5, LANE + 0.5, 0.0, "wall_basement", "", shell)
	if has_attic:
		partition(3.0, FA, FA + H, LANE - 0.5, LANE + 0.5, 0.0, "", "wall_attic", shell)
	# небо и дома напротив — за окнами; за дверями — тёмные проёмы
	var sky := StandardMaterial3D.new()
	sky.albedo_texture = load(TEX + "sky.png")
	sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box("sky", Vector3(-0.2, 0.2, -D - 2.5), Vector3(W + 0.2, y_hi - 0.2, -D - 2.45), sky, shell)
	var dark := color_mat(Color("3d4a44"))
	box("entrance_dark", Vector3(5.8, F1, -D - OUTER - 0.4), Vector3(7.0, F1 + 2.2, -D - OUTER - 0.35), dark, shell)
	var deep := color_mat(Color("1e1a17"))
	if has_base:
		box("cellar_dark_a", Vector3(1.15, F1, -D - OUTER - 0.4), Vector3(2.35, F1 + 2.2, -D - OUTER - 0.35), deep, shell)
		box("cellar_dark_b", Vector3(1.15, FB, -D - OUTER - 0.4), Vector3(2.35, FB + 2.2, -D - OUTER - 0.35), deep, shell)
	if has_attic:
		box("attic_dark_a", Vector3(14.9, F2, -D - OUTER - 0.4), Vector3(16.1, F2 + 2.2, -D - OUTER - 0.35), deep, shell)
		box("attic_dark_b", Vector3(14.9, FA, -D - OUTER - 0.4), Vector3(16.1, FA + 2.2, -D - OUTER - 0.35), deep, shell)

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
		var xa := x_room - side * run * i
		var xb := x_room - side * run * (i + 1)
		var top := half * (i + 1) / n
		box("lower_%d" % i, Vector3(minf(xa, xb), F1, -1.55), Vector3(maxf(xa, xb), top, -0.45), wood, st)
		box("lower_nose_%d" % i, Vector3(minf(xa, xb), top - 0.03, -1.56), Vector3(maxf(xa, xb), top + 0.01, -0.44), dark, st)
		var xc := x_land + side * run * i
		var xd := x_land + side * run * (i + 1)
		var top2 := half + half * (i + 1) / n
		box("upper_%d" % i, Vector3(minf(xc, xd), top2 - 0.25, -2.7), Vector3(maxf(xc, xd), top2, -1.6), wood, st)
		box("upper_nose_%d" % i, Vector3(minf(xc, xd), top2 - 0.03, -2.71), Vector3(maxf(xc, xd), top2 + 0.01, -1.59), dark, st)
	box("landing", Vector3(minf(x_outer, x_land), half - 0.25, -2.7), Vector3(maxf(x_outer, x_land), half, -0.45), wood, st)
	box("landing_post", Vector3(minf(x_outer, x_land) + 0.05, F1, -0.6), Vector3(minf(x_outer, x_land) + 0.15, half, -0.5), dark, st)
	box("top_step", Vector3(minf(x_room, x_room + side * 0.12), F2 - 0.25, -2.7), Vector3(maxf(x_room, x_room + side * 0.12), F2, -1.6), wood, st)
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

## Площадка за верхним маршем правой лестницы — к двери на чердак.
func build_gallery() -> void:
	var g := _own(Node3D.new()) as Node3D
	g.name = "Gallery"
	var wood := color_mat(Color("8a5a32"))
	var dark := color_mat(Color("5b3a22"))
	box("gallery_floor", Vector3(14.0, F2 - 0.25, -D), Vector3(W, F2, -2.7), wood, g)
	box("gallery_edge", Vector3(14.0, F2 - 0.03, -2.71), Vector3(W, F2 + 0.01, -2.69), dark, g)
	for x in [15.0, 15.7, 16.4]:
		box("gallery_post_%d" % int(x * 10), Vector3(x - 0.025, F2, -2.75), Vector3(x + 0.025, F2 + 0.9, -2.7), dark, g)
	box("gallery_rail", Vector3(14.95, F2 + 0.88, -2.76), Vector3(W, F2 + 0.93, -2.69), dark, g)

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

func build_doors_windows() -> void:
	_furn = _own(Node3D.new()) as Node3D
	_furn.name = "Furniture"
	var doors := _own(Node3D.new(), _furn) as Node3D
	doors.name = "Doors"
	put("door", 7.0, F1, LANE, 90, 0, doors, "door_hall_kitchen")
	if has_living:
		put("door", 10.4, F1, LANE, 90, 0, doors, "door_kitchen_living")
	put("door", 6.4, F2, LANE, 90, 0, doors, "door_bath_bedroom")
	if has_balcony:
		put("door", 10.4, F2, LANE, -90, 0, doors, "door_bedroom_balcony")
	put("door", 6.4, F1, "wall", 0, 0, doors, "door_entrance")
	if has_garage:
		put("door", 10.4, FB, LANE, 90, 0, doors, "door_basement_garage")
	if has_base:   # двери-переходы: под левой лестницей — в подвал
		put("door", 1.75, F1, "wall", 0, 0, doors, "door_cellar_a")
		put("door", 1.75, FB, "wall", 0, 0, doors, "door_cellar_b")
	if has_attic:  # с площадки правой лестницы — на чердак
		put("door", 15.5, F2, "wall", 0, 0, doors, "door_attic_a")
		put("door", 15.5, FA, "wall", 0, 0, doors, "door_attic_b")
	var wins := _own(Node3D.new(), _furn) as Node3D
	wins.name = "Windows"
	var ws := [[8.4, F2 + 1.25], [1.5, F2 + 0.6]]
	if has_living:
		ws.append([11.6, F1 + 1.1])
	if has_balcony:
		ws.append_array([[11.9, F2 + 0.9], [13.2, F2 + 0.9]])
	if has_r and not has_attic:
		ws.append([15.5, F2 + 0.6])
	if has_attic:
		ws.append([12.6, FA + 1.0])
	for w in ws:
		put("window", w[0], w[1], "wall", 0, 0, wins, "window_%d_%d" % [int(w[0] * 10), int(w[1] * 10)])

func build_furniture() -> void:
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
	if has_living:
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
	# ванная (2 этаж, x 3..6.4): ванна со шторкой (прятки), раковина, полочка (ополаскиватель), унитаз
	put("bathtub", 3.85, F2).scale.x = 0.82
	put("shower_curtain", 3.85, F2, -D + 0.8).scale.x = 0.82
	put("sink_vanity", 4.92, F2)
	put("mirror_cabinet", 4.92, F2 + 1.32, "wall")
	put("bath_shelf", 4.92, F2 + 1.16, "wall")
	put("toilet", 5.55, F2)
	put("wall_lamp", 4.0, F2 + 2.25, "wall", 0, 0, null, "wall_lamp_bath")
	# спальня (x 6.4..10.4): кровать (прятки), комод (тайник), часы; справа сосед шпаклюет стену
	put("dresser", 6.98, F2)
	put("bed", 8.4, F2)
	put("putty_bucket", 10.12, F2, -3.62)
	put("clock", 10.05, F2 + 1.85, "wall")
	put("chandelier", 8.4, TOP, -2.0, 0, 0.0, null, "chandelier_bedroom")
	put("rug", 8.4, F2, -1.2, 0, 0.0, null, "rug_bedroom")
	if has_balcony:
		# балкон (x 10.4..14): стеллаж с банками (водка), ящик с инструментами (лампочка), лыжи (прятки)
		put("balcony_shelf", 11.0, F2)
		put("toolbox", 11.95, F2)
		put("antifreeze", 12.45, F2)
		put("plant", 12.95, F2, "back", 0, 0.02, null, "plant_balcony")
		put("skis", 13.55, F2)
	# лестницы: лампы
	put("wall_lamp", 0.6 if has_base else 1.5, F1 + 2.2, "wall", 0, 0, null, "wall_lamp_stairs_l")
	if has_r:
		put("wall_lamp", 16.3 if has_attic else 15.5, F1 + 2.2, "wall", 0, 0, null, "wall_lamp_stairs_r")
	if has_base:
		# подвал (x 0..10.4): самогонный аппарат (тайник), бочка кваса (подмена), закатки (тайник), мешки (прятки)
		put("moonshine_still", 4.3, FB)
		put("kvass_barrel", 6.2, FB)
		put("cellar_shelf", 8.0, FB)
		put("potato_sacks", 9.6, FB, "back", 0, 0.55)          # зазор у стены — там прячется герой
		put("bare_bulb", 4.6, FB + H, -2.0, 0, 0.0, null, "bulb_basement_1")
		put("bare_bulb", 8.4, FB + H, -2.0, 0, 0.0, null, "bulb_basement_2")
		put("mop_bucket", 0.9, FB, "back", 0, 0.02, null, "basement_bucket")
		var pipe := color_mat(Color("8c8f94"), 0.4)
		box("pipe_1", Vector3(0.0, FB + 2.3, -3.95), Vector3(W if has_garage else 10.3, FB + 2.4, -3.85), pipe, _furn)
		box("pipe_2", Vector3(0.0, FB + 2.48, -3.93), Vector3(W if has_garage else 10.3, FB + 2.55, -3.86), color_mat(Color("a8573a"), 0.5), _furn)
	if has_garage:
		# гараж (x 10.4..17): верстак (тайник), машина (прятки), покрышки, удочки (утащить)
		put("workbench", 11.1, FB)
		put("garage_gate", 13.6, FB, "wall")
		put("car", 13.6, FB, -2.4)
		put("tires", 16.0, FB)
		put("fishing_rods", 16.6, FB).scale = Vector3.ONE * 1.35
		put("antifreeze", 15.4, FB, "back", 0, 0.02, null, "garage_canister")
		put("bare_bulb", 12.2, FB + H, -2.0, 0, 0.0, null, "bulb_garage_1")
		put("bare_bulb", 15.6, FB + H, -2.0, 0, 0.0, null, "bulb_garage_2")
	if has_attic:
		# чердак (x 3..17): сундук (тайник), коробки (прятки), банка рассола (подмена), голуби на окне
		put("old_chest", 4.3, FA)
		put("attic_boxes", 5.9, FA, "back", 0, 0.6)
		put("armchair", 7.7, FA, "back", 15, 0.05, null, "attic_armchair")
		put("pickle_jar", 9.0, FA)
		put("books", 10.4, FA, "back", 0, 0.05, null, "attic_books")
		put("pigeon", 12.35, FA + 1.0, -3.92, 0, 0.0, null, "pigeon_1")
		put("pigeon", 12.85, FA + 1.0, -3.92, 180, 0.0, null, "pigeon_2")
		put("bare_bulb", 6.2, FA + H, -2.0, 0, 0.0, null, "bulb_attic_1")
		put("bare_bulb", 11.2, FA + H, -2.0, 0, 0.0, null, "bulb_attic_2")
		var beam := color_mat(Color("5b3a22"))
		for bx in [4.8, 8.2, 11.6, 14.6]:
			box("rafter_%d" % int(bx * 10), Vector3(bx - 0.09, FA, -3.95), Vector3(bx + 0.09, FA + H, -3.77), beam, _furn)
		box("attic_beam", Vector3(3.0, FA + H - 0.3, -3.95), Vector3(W, FA + H - 0.14, -3.77), beam, _furn)

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
	var ls := [[1.5, 2.2], [5.0, 1.9], [8.7, 1.9], [4.6, F2 + 1.9], [8.4, F2 + 1.9], [1.5, F2 + 1.9]]
	if has_living:
		ls.append([12.2, 1.9])
	if has_balcony:
		ls.append([12.2, F2 + 1.9])
	if has_r:
		ls.append_array([[15.5, 2.2], [15.5, F2 + 1.9]])
	var cool := []
	if has_base:
		cool.append_array([[2.4, FB + 1.9], [5.6, FB + 1.9], [8.6, FB + 1.9]])
	if has_garage:
		cool.append_array([[12.2, FB + 1.9], [15.6, FB + 1.9]])
	if has_attic:
		ls.append_array([[6.2, FA + 1.9], [11.2, FA + 1.9], [15.3, FA + 1.9]])
	for l in ls + cool:
		var o := OmniLight3D.new()
		o.name = "lamp_%d_%d" % [int(l[0] * 10), int(l[1] * 10)]
		o.light_color = Color("ffd59a") if l in ls else Color("ffe6c2")
		o.light_energy = 0.55
		o.omni_range = 4.2
		o.position = Vector3(l[0], l[1], -1.6)
		_own(o, lights)
	# камера: весь дом в кадре (ширина 16:9 или высота с запасом под верхнюю и нижнюю панели интерфейса)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = 29
	var y_lo := (FB - 0.7) if has_base else -0.7
	var y_hi := (FA + H + SLAB) if has_attic else (TOP + SLAB)
	var t := tan(deg_to_rad(cam.fov * 0.5))
	var dist := maxf((W + 1.8) * 0.5 / (t * 16.0 / 9.0), (y_hi - y_lo) / (0.73 * 2.0 * t))
	var cy := (y_lo + y_hi) * 0.5 + 0.075
	cam.position = Vector3(W * 0.5, cy + 0.1, -1.5 + dist)
	_own(cam)
	cam.transform = Transform3D(Basis.looking_at(Vector3(W * 0.5, cy, -1.5) - cam.position), cam.position)
	cam.current = true
