class_name Overlay3D
extends Control
## Рисует поверх 3D: кружки над местами (жёлтые — заначки/подмены, голубые — укрытия, красные — ловушки),
## подсветку места под курсором, облачка реплик и значки «?» / «!» над соседом.

var game: Node    # Game3D
var _t := 0.0
var _font: Font

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

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
		if sp.hovered and sp.active:
			var r: Rect2 = game.screen_rect(sp.aabb)
			draw_rect(r, Color(col, 0.16), true)
			draw_rect(r, col, false, 4.0)
		if sp.done:
			draw_circle(top, 13.0 * k, Color(0.15, 0.55, 0.2, 0.92))
			draw_polyline(PackedVector2Array([top + Vector2(-6, 0) * k, top + Vector2(-1, 5) * k, top + Vector2(7, -5) * k]), Color.WHITE, 3.5 * k)
		elif not sp.hovered:
			var rr := (7.0 + sin(_t * 4.0 + top.x * 0.01) * 1.8) * k
			draw_circle(top, rr + 3.0 * k, Color(0, 0, 0, 0.35))
			draw_circle(top, rr, Color(col, 0.95))
	# герой в укрытии — выглядывают глаза
	var h := game.hero as Hero3D
	if h.in_hiding and not h.visible and h.hide_spot:
		var c := cam.unproject_position(h.hide_spot.aabb.get_center() + Vector3(0, h.hide_spot.aabb.size.y * 0.15, h.hide_spot.aabb.size.z * 0.5))
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
	# реплики
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
	var size := Vector2(w, fs * 1.15) + pad * 2
	var r := Rect2(at - Vector2(size.x * 0.5, size.y + 22), size)
	r.position.x = clampf(r.position.x, 8, 1912 - r.size.x)
	r.position.y = maxf(r.position.y, 150)
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
