class_name Overlay3D
extends Control
## Рисует поверх 3D: кружки над местами (жёлтые — заначки/подмены, голубые — укрытия, красные — ловушки;
## под курсором кружок крупнее, с белым ободком), облачка реплик, мысль соседа «куда пойдёт» с меткой
## на полу и значки «?» / «!» над соседом.

var game: Node    # Game3D
var _t := 0.0
var _font: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

var _bubbles: Array[Rect2] = []

func _draw() -> void:
	var cam: Camera3D = game.cam
	var k: float = clampf(29.0 / cam.fov, 1.0, 2.2) * 0.75     # крупнее при приближении
	for s in game.spots.values():
		if game.rules.over:
			break
		var sp := s as Spot3D
		if not sp.active and not sp.done:
			continue
		var top := cam.unproject_position(sp.marker_pos())
		var col := Color("9fe3ff") if sp.kind == "hide" else (Color("ff9a7a") if sp.kind == "trap" else Color("ffe08a"))
		if sp.hovered and sp.active and not sp.done:
			var hr := 12.0 * k
			draw_circle(top, hr + 5.0 * k, Color(0, 0, 0, 0.45))
			draw_circle(top, hr + 3.0 * k, Color.WHITE)
			draw_circle(top, hr, col)
		elif sp.done:
			draw_circle(top, 13.0 * k, Color(0.15, 0.55, 0.2, 0.92))
			draw_polyline(PackedVector2Array([top + Vector2(-6, 0) * k, top + Vector2(-1, 5) * k, top + Vector2(7, -5) * k]), Color.WHITE, 3.5 * k)
		else:
			var rr := (7.0 + sin(_t * 4.0 + top.x * 0.01) * 1.8) * k
			draw_circle(top, rr + 3.0 * k, Color(0, 0, 0, 0.35))
			draw_circle(top, rr, Color(col, 0.95))
		if sp.active and not sp.done and game.wants_item(sp):
			# сюда можно применить вещь из сумки: расходящееся зелёное кольцо
			var ph := fmod(_t * 1.2, 1.0)
			draw_arc(top, (12.0 + 16.0 * ph) * k, 0.0, TAU, 32, Color(0.55, 1.0, 0.45, 0.9 * (1.0 - ph)), 3.0 * k)
			draw_arc(top, 11.0 * k, 0.0, TAU, 32, Color(0.55, 1.0, 0.45, 0.95), 2.5 * k)
	# двери-переходы: пульсирующая рамка вокруг проёма и табличка «куда» со стрелкой вверх/вниз
	if not game.rules.over:
		var mp := get_viewport().get_mouse_position()
		for pd in game.portals:
			for side in ["a", "b"]:
				var dp: Vector3 = pd["door_" + side]
				var r: Rect2 = game.screen_rect(AABB(Vector3(dp.x - 0.5, dp.y, dp.z), Vector3(1.0, 2.15, 0.1)))
				var hot := r.grow(6).has_point(mp) and not Settings.is_touch()
				var pulse := 0.55 + 0.45 * sin(_t * 3.0 + dp.x)
				var col := Color("9fe3ff")
				draw_rect(r.grow(3), Color(0.1, 0.06, 0.03, 0.5), false, 5.0 * k)
				draw_rect(r, Color(col, 1.0 if hot else 0.35 + 0.45 * pulse), false, (4.0 if hot else 2.5) * k)
				var up: bool = (pd["b"] if side == "a" else pd["a"]) > (pd["a"] if side == "a" else pd["b"])
				_door_sign(cam.unproject_position(dp + Vector3(0, 2.32, 0.15)), pd["title_" + side], k, up)
	# герой в укрытии — выглядывают глаза
	var h := game.hero as Hero3D
	if h.in_hiding and not h.visible and h.hide_spot:
		var c := cam.unproject_position(h.hide_eyes())
		var blink := fmod(_t, 3.0) > 2.85
		for sx in [-1.0, 1.0]:
			var e: Vector2 = c + Vector2(sx * 9.0 * k, 0)
			if blink:
				draw_line(e + Vector2(-6, 0) * k, e + Vector2(6, 0) * k, Color("2b1208"), 3.0 * k)
			else:
				draw_set_transform(e, 0.0, Vector2(1.0, 1.35))
				draw_circle(Vector2.ZERO, 7.0 * k, Color("2b1208"))
				draw_circle(Vector2.ZERO, 5.5 * k, Color.WHITE)
				draw_circle(Vector2(sin(_t * 0.8) * 2.0 * k, 0.5 * k), 2.6 * k, Color("1a0d05"))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# куда пойдёт сосед: метка на полу и облачко-мысль
	var nb := game.neighbor as Neighbor3D
	if nb.goal != Vector3.INF and not game.rules.over:
		_goal_mark(cam.unproject_position(nb.goal), k)
	if nb.thought != "" and not game.rules.over:
		var hp := cam.unproject_position(nb.head_pos())
		if nb.bubble != "":
			hp.y -= 78.0 * clampf(k, 0.9, 1.4)
		_thought(hp, nb.thought, k)
	# сосед за кадром (крупная камера) — стрелка у края экрана в его сторону
	if not game.rules.over and size.x > 400.0:
		var np := cam.unproject_position(nb.head_pos() + Vector3(0, -0.8, 0))
		var vr := Rect2(Vector2.ZERO, size)
		if not vr.grow(-10).has_point(np) or cam.is_position_behind(nb.head_pos()):
			_offscreen_arrow(np, vr, nb.thought)
	# реплики (облачка не налезают друг на друга и на панель «Задания»)
	_bubbles.clear()
	for a in [game.neighbor, game.hero]:
		var ac := a as Actor
		if ac == null or not ac.visible and ac.bubble == "":
			continue
		if ac.bubble != "":
			_bubble(cam.unproject_position(ac.head_pos()), ac.bubble, ac is Neighbor3D, k)
	# «?» и «!» над соседом
	var n := game.neighbor as Neighbor3D
	var mark := ""
	if n.mode == "chase":
		mark = "!"
	elif n.suspicion > 0.02:
		mark = "?"
	if mark != "":
		var p := cam.unproject_position(n.head_pos() + Vector3(0, 0.25, 0))
		if n.bubble != "":
			p.y -= 70.0 * k
		var fs := int(64 * k)
		var c := Color("ff3b2f") if mark == "!" or n.suspicion > 0.6 else Color("ffd23a")
		draw_string_outline(_font, p + Vector2(-fs * 0.18, 0), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color("2b1208"))
		draw_string(_font, p + Vector2(-fs * 0.18, 0), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)

func _bubble(at: Vector2, text: String, is_neighbor: bool, k: float) -> void:
	var fs := int(26 * clampf(k, 0.9, 1.4))
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := Vector2(18, 10)
	var bs := Vector2(w, fs * 1.15) + pad * 2     # не «size» — это размер экрана (Control.size)
	var r := Rect2(at - Vector2(bs.x * 0.5, bs.y + 22), bs)
	r.position.x = clampf(r.position.x, 8, maxf(8, size.x - 8 - r.size.x))
	r.position.y = maxf(r.position.y, 150)
	var panel: Control = game.hud.tasks
	if panel and panel.is_visible_in_tree():
		var tr := panel.get_global_rect().grow(6)
		if r.intersects(tr):           # персонаж у края экрана — облачко левее панели (или под ней)
			if tr.position.x - r.size.x >= 8:
				r.position.x = tr.position.x - r.size.x
			else:
				r.position.y = tr.end.y
	for o in _bubbles:                 # второе облачко — под первым
		if r.intersects(o.grow(4)):
			r.position.y = o.end.y + 8
	_bubbles.append(r)
	var bg := Color("fffaf0") if is_neighbor else Color("e9f6ff")
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color("3a1b0c")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	draw_style_box(sb, r)
	var tip := Vector2(clampf(at.x, r.position.x + 20, r.end.x - 20), r.end.y)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-10, -2), tip + Vector2(10, -2), tip + Vector2(0, 16)]), bg)
	draw_polyline(PackedVector2Array([tip + Vector2(-10, 0), tip + Vector2(0, 16), tip + Vector2(10, 0)]), Color("3a1b0c"), 3)
	draw_string(_font, r.position + Vector2(pad.x, pad.y + fs * 0.92), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("2b1208"))

## Табличка над дверью-переходом: тёмная плашка с подписью и треугольником-стрелкой вниз.
func _door_sign(at: Vector2, text: String, k: float, up: bool) -> void:
	var fs := int(20 * clampf(k, 0.9, 1.5))
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + fs * 0.9   # место под стрелку
	var r := Rect2(at - Vector2(w * 0.5 + 12, fs + 10), Vector2(w + 24, fs + 12))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.09, 0.05, 0.9)
	sb.border_color = Color("9fe3ff")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, r)
	draw_colored_polygon(PackedVector2Array([Vector2(at.x - 7, r.end.y), Vector2(at.x + 7, r.end.y), Vector2(at.x, r.end.y + 8)]), Color("9fe3ff"))
	# стрелка: куда ведёт дверь (вверх / вниз) — фигурой, в вебе нет шрифта со стрелками
	var a := Vector2(r.position.x + 10 + fs * 0.35, r.get_center().y)
	var h := fs * 0.32
	var tri := PackedVector2Array([a + Vector2(-h, h * 0.6), a + Vector2(h, h * 0.6), a + Vector2(0, -h * 0.9)]) if up 		else PackedVector2Array([a + Vector2(-h, -h * 0.6), a + Vector2(h, -h * 0.6), a + Vector2(0, h * 0.9)])
	draw_colored_polygon(tri, Color("ffd27a"))
	draw_string(_font, Vector2(r.position.x + 12 + fs * 0.9, r.end.y - 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("e9f6ff"))

## Метка цели соседа на полу: пульсирующее кольцо и стрелка вниз.
func _goal_mark(at: Vector2, k: float) -> void:
	var col := Color("ff8a3d")
	var ph := fmod(_t * 1.4, 1.0)
	draw_set_transform(at, 0.0, Vector2(1.0, 0.35))
	draw_arc(Vector2.ZERO, (26.0 + ph * 30.0) * k, 0.0, TAU, 48, Color(col, 0.9 * (1.0 - ph)), 5.0 * k)
	draw_arc(Vector2.ZERO, 26.0 * k, 0.0, TAU, 48, Color("3a1b0c"), 9.0 * k)
	draw_arc(Vector2.ZERO, 26.0 * k, 0.0, TAU, 48, col, 5.0 * k)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var y := at.y - (46.0 + sin(_t * 5.0) * 6.0) * k
	var tri := PackedVector2Array([Vector2(at.x - 16 * k, y - 18 * k), Vector2(at.x + 16 * k, y - 18 * k), Vector2(at.x, y + 6 * k)])
	draw_colored_polygon(tri, col)
	tri.append(tri[0])
	draw_polyline(tri, Color("3a1b0c"), 2.5)

## Облачко-мысль: овальное «облако» из кружков и цепочка пузырьков к голове.
func _thought(head: Vector2, text: String, k: float) -> void:
	var fs := int(24 * clampf(k, 0.9, 1.4))
	var parts := text.split(": ", true, 1)
	var room := parts[0] + ": " if parts.size() > 1 else ""
	var rest := parts[1] if parts.size() > 1 else text
	var w1 := _font.get_string_size(room, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w2 := _font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var bs := Vector2(w1 + w2 + 44, fs * 1.15 + 26)
	var r := Rect2(head - Vector2(bs.x * 0.5, bs.y + 64), bs)
	r.position.x = clampf(r.position.x, 12, maxf(12, size.x - 12 - r.size.x))
	r.position.y = maxf(r.position.y, 150)
	var bg := Color("f4f7ff")
	var line := Color("3a1b0c")
	# облако: контур из кружков по краю, потом заливка поверх
	var bumps: Array[Vector2] = []
	var br := r.size.y * 0.3
	var n := maxi(3, int(r.size.x / 44.0))
	for i in n + 1:
		var x := lerpf(r.position.x + r.size.y * 0.45, r.end.x - r.size.y * 0.45, float(i) / n)
		bumps.append(Vector2(x, r.position.y + 2))
		bumps.append(Vector2(x + 14.0 * (1 if i % 2 else -1), r.end.y - 2))
	for b in bumps:
		draw_circle(b, br + 3.0, line)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = line
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	draw_style_box(sb, r.grow_individual(10, 0, 10, 0))
	for b in bumps:
		draw_circle(b, br, bg)
	draw_rect(r.grow_individual(4, -6, 4, -6), bg)
	# пузырьки к голове
	var from := Vector2(clampf(head.x, r.position.x + 20, r.end.x - 20), r.end.y + br * 0.6)
	for i in 3:
		var t := float(i + 1) / 4.0
		var c := from.lerp(head + Vector2(0, -14), t)
		var rad := (9.0 - i * 2.5) * clampf(k, 0.9, 1.3)
		draw_circle(c, rad + 2.5, line)
		draw_circle(c, rad, bg)
	var base := Vector2(r.position.x + 22, r.position.y + 13 + fs * 0.92)
	draw_string(_font, base, room, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("c2410c"))
	draw_string(_font, base + Vector2(w1, 0), rest, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("2b1208"))

## Стрелка у края экрана к соседу, который сейчас не в кадре, с подписью (и его мыслью, если есть).
func _offscreen_arrow(target: Vector2, vr: Rect2, thought: String) -> void:
	var c := vr.get_center()
	var inner := vr.grow_individual(-70, -180, -70, -190)   # не залезать на верхние и нижнюю панели
	var d := target - c
	if d.length() < 1.0:
		return
	var t := INF
	if absf(d.x) > 0.001:
		t = minf(t, ((inner.end.x if d.x > 0 else inner.position.x) - c.x) / d.x)
	if absf(d.y) > 0.001:
		t = minf(t, ((inner.end.y if d.y > 0 else inner.position.y) - c.y) / d.y)
	var p := c + d * t
	var dir := d.normalized()
	var col := Color("ff8a3d")
	var pulse := 1.0 + sin(_t * 6.0) * 0.08
	draw_circle(p, 30.0 * pulse, Color("3a1b0c"))
	draw_circle(p, 26.0 * pulse, col)
	var tip := p + dir * 44.0
	var side := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([tip, p + dir * 24.0 + side * 14.0, p + dir * 24.0 - side * 14.0])
	draw_colored_polygon(tri, col)
	tri.append(tri[0])
	draw_polyline(tri, Color("3a1b0c"), 3.0)
	var label := "Сосед" + ("  ·  " + thought if thought != "" else "")
	var fs := 22
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lp := p + Vector2(-w * 0.5, 54.0)
	lp.x = clampf(lp.x, 12.0, size.x - w - 12.0)
	if dir.y > 0.5:
		lp.y = p.y - 44.0
	draw_string_outline(_font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color("2b1208"))
	draw_string(_font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ffe9b8"))
	draw_string(_font, p + Vector2(-7, 8), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("2b1208"))
