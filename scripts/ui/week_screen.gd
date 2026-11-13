class_name WeekScreen
extends Control
## Экран недели: 7 маленьких карточек Пн…Вс. Пройденный день — зелёная галочка и лучший процент,
## следующий — открыт (подсвечен), остальные — под замком. Дни проходятся по порядку, пройденные можно
## переиграть. Галочку и замок рисуем фигурами (в вебе нет шрифтов с такими символами).

signal day_chosen(n: int)
signal closed

const CARD := Vector2(236, 356)

var _grid: HFlowContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.02, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 26)
	sc.add_child(vb)
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 30)
	vb.add_child(top)
	var title := UiStyle.label("Неделя соседа", 66, UiStyle.C_TITLE, 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := UiStyle.label(_subtitle(), 28, UiStyle.C_TEXT, 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)
	_grid = HFlowContainer.new()
	_grid.alignment = FlowContainer.ALIGNMENT_CENTER
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_grid)
	for n in range(1, 8):
		_grid.add_child(_card(n))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	vb.add_child(row)
	var back := UiStyle.button("Назад", 38, 300)
	back.pressed.connect(func():
		closed.emit()
		queue_free())
	row.add_child(back)
	var play := UiStyle.button("Играть: " + Days.NAMES[Progress.next_day() - 1], 38, 460)
	play.pressed.connect(func(): _choose(Progress.next_day()))
	row.add_child(play)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 30)
	vb.add_child(pad)
	Settings.qa_mark("week_ready")

func _subtitle() -> String:
	if Progress.week_done():
		return "Неделя пройдена! Звание: «%s» (в среднем %d%%). Любой день можно переиграть." % [Progress.week_title(), Progress.average_percent()]
	return "Каждый день сосед клянётся «больше не пью». Дни открываются по порядку."

func _choose(n: int) -> void:
	if not Progress.unlocked(n):
		return
	Progress.day = n
	day_chosen.emit(n)

func _card(n: int) -> Control:
	var d := Days.day(n)
	var unlocked := Progress.unlocked(n)
	var done := Progress.is_done(n)
	var current := unlocked and not done and n == Progress.next_day()
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = CARD
	b.disabled = not unlocked
	var border := Color("7fd36b") if done else (Color("ffe08a") if current else Color("8a6a4a"))
	var bg := Color(0.24, 0.12, 0.05, 0.96) if unlocked else Color(0.14, 0.09, 0.06, 0.96)
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, UiStyle.box(bg, border, 18, 5 if current else 4))
	b.add_theme_stylebox_override("hover", UiStyle.box(bg.lightened(0.12), Color("fff0b0"), 18, 5))
	b.add_theme_stylebox_override("pressed", UiStyle.box(bg.darkened(0.2), border, 18, 4))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		Settings.sfx("click", 0.8)
		_choose(n))
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 14
	vb.offset_right = -14
	vb.offset_top = 12
	vb.offset_bottom = -12
	vb.add_theme_constant_override("separation", 6)
	b.add_child(vb)
	var dn := UiStyle.label(d["day_name"], 30, UiStyle.C_TITLE if unlocked else Color("a08a70"), 8)
	dn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dn)
	# картинка дома этого дня (рендер сцены); если нет — просто тёмная плашка
	var pic := TextureRect.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.custom_minimum_size = Vector2(0, 118)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var img_path := "res://assets/ui/days/day_%d.jpg" % n
	if ResourceLoader.exists(img_path):
		pic.texture = load(img_path)
	pic.modulate = Color.WHITE if unlocked else Color(0.35, 0.3, 0.28)
	vb.add_child(pic)
	var t := UiStyle.label("«%s»" % d["title"], 22, UiStyle.C_TEXT if unlocked else Color("8a7a66"), 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(CARD.x - 28, 0)
	vb.add_child(t)
	var rooms := UiStyle.label("Комнат: %d · заданий: %d" % [(d["rooms"] as Array).size(), (d["tasks"] as Array).size()], 18,
		Color("e2c697") if unlocked else Color("7a6a58"), 5)
	rooms.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(rooms)
	var badge := _Badge.new()
	badge.state = 2 if done else (1 if current else (0 if unlocked else -1))
	badge.percent = int(Progress.best.get(n, {}).get("percent", 0))
	badge.custom_minimum_size = Vector2(0, 46)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(badge)
	return b

## Значок внизу карточки: галочка с процентом / «Играть» / замок.
class _Badge extends Control:
	var state := 0       # -1 закрыт, 0 открыт, 1 следующий, 2 пройден
	var percent := 0

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var f := get_theme_default_font()
		match state:
			2:
				draw_circle(c + Vector2(-46, 0), 19, Color("2f8f3a"))
				draw_circle(c + Vector2(-46, 0), 19, Color("bff0a8"), false, 2.5)
				draw_polyline(PackedVector2Array([c + Vector2(-56, 0), c + Vector2(-49, 8), c + Vector2(-35, -8)]), Color.WHITE, 4.5)
				draw_string_outline(f, c + Vector2(-20, 10), "%d%%" % percent, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 7, Color("3a1b0c"))
				draw_string(f, c + Vector2(-20, 10), "%d%%" % percent, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("bff0a8"))
			1:
				var txt := "Играть"
				var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
				draw_string_outline(f, c + Vector2(-w * 0.5, 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 8, Color("3a1b0c"))
				draw_string(f, c + Vector2(-w * 0.5, 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("ffe08a"))
			-1:
				# замок: дужка и корпус с замочной скважиной
				var body := Rect2(c + Vector2(-15, -4), Vector2(30, 22))
				draw_arc(c + Vector2(0, -5), 10, PI, TAU, 16, Color("b9a68c"), 4.5)
				draw_rect(body, Color("b9a68c"))
				draw_circle(c + Vector2(0, 5), 3.5, Color("3a2a1c"))
				draw_rect(Rect2(c + Vector2(-1.5, 6), Vector2(3, 7)), Color("3a2a1c"))
			0:
				pass
