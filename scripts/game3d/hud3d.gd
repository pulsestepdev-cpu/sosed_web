class_name Hud3D
extends CanvasLayer
## Интерфейс 3D-уровня: часы и что делает сосед, шкала опьянения, поимки и очки, сумка,
## список заданий, подсказка у курсора, всплывающие сообщения, вступление, пауза, итоги.

signal start_pressed
signal restart_pressed
signal menu_pressed
signal resume_pressed

const C_TEXT := Color("ffe9b8")
const C_DIM := Color("e2c697")

var rules: Rules3D
var clock: Label
var status: Label
var drunk_bar: ProgressBar
var drunk_label: Label
var stats: Label
var inv_box: HBoxContainer
var tooltip: Label
var toasts: VBoxContainer
var overlay: Control
var suspicion_bar: ProgressBar
var tasks: Control
var _task_t := 0.0
var _drunk_shown := 0.0

func _ready() -> void:
	layer = 10
	var left := _panel(Vector2(20, 14))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 26)
	left.add_child(hb)
	clock = _label(60, C_TEXT)
	hb.add_child(clock)
	status = _label(25, C_DIM)
	hb.add_child(status)

	var right := _panel(Vector2(1290, 14))
	right.custom_minimum_size = Vector2(610, 0)
	var vb := VBoxContainer.new()
	right.add_child(vb)
	drunk_label = _label(27, C_TEXT)
	vb.add_child(drunk_label)
	drunk_bar = _bar(Color("e0662f"))
	vb.add_child(drunk_bar)
	stats = _label(23, C_DIM)
	vb.add_child(stats)

	suspicion_bar = _bar(Color("ff3b2f"))
	suspicion_bar.position = Vector2(760, 150)
	suspicion_bar.size = Vector2(400, 18)
	suspicion_bar.visible = false
	add_child(suspicion_bar)

	var inv_panel := _panel(Vector2(510, 940))
	inv_panel.custom_minimum_size = Vector2(900, 104)
	inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	inv_box = HBoxContainer.new()
	inv_box.add_theme_constant_override("separation", 10)
	inv_box.alignment = BoxContainer.ALIGNMENT_CENTER
	inv_panel.add_child(inv_box)
	inv_panel.resized.connect(func(): inv_panel.position.x = (1920 - inv_panel.size.x) * 0.5)

	var hint := _label(18, Color("c9a777"))
	hint.text = "ЛКМ — идти / взять / подложить  ·  ПКМ/Shift — крадучись  ·  колесо или Z — крупно (мышь к краю — обзор, C — к герою)  ·  Tab — задания  ·  Пробел — пауза  ·  F — ускорить  ·  Esc — меню"
	hint.position = Vector2(24, 1050)
	hint.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	hint.add_theme_constant_override("outline_size", 6)
	add_child(hint)

	toasts = VBoxContainer.new()
	toasts.position = Vector2(560, 700)
	toasts.custom_minimum_size = Vector2(800, 0)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)

	_build_tasks()

	tooltip = _label(26, Color.WHITE)
	tooltip.add_theme_color_override("font_outline_color", Color.BLACK)
	tooltip.add_theme_constant_override("outline_size", 10)
	tooltip.visible = false
	add_child(tooltip)

func bind(r: Rules3D) -> void:
	rules = r
	rules.toast.connect(show_toast)
	rules.inventory_changed.connect(_rebuild_inventory)
	_rebuild_inventory()

func update_view(hour: float, neighbor_text: String, hero_text: String, suspicion: float, paused: bool, fast: bool, delta: float) -> void:
	var h := int(hour)
	clock.text = "%02d:%02d" % [h, int((hour - h) * 60.0)]
	status.text = "Сосед: %s\nГерой: %s%s%s" % [neighbor_text, hero_text,
		"   ⏸ ПАУЗА" if paused else "", "   ⏩ x3" if fast else ""]
	_drunk_shown = move_toward(_drunk_shown, rules.drunk, delta * 25.0)
	drunk_label.text = "Опьянение соседа: %d%%  —  «%s»" % [int(_drunk_shown), rules.stage_name()]
	drunk_bar.value = _drunk_shown
	stats.text = "Поимки: %d / 3      Очки: %d" % [rules.catches, rules.score]
	suspicion_bar.visible = suspicion > 0.01
	suspicion_bar.value = suspicion * 100.0
	_update_tasks_fade(delta)

func set_tooltip(text: String, at: Vector2) -> void:
	tooltip.visible = text != ""
	tooltip.text = text
	tooltip.position = at + Vector2(24, 18)
	tooltip.position.x = minf(tooltip.position.x, 1920 - tooltip.size.x - 10)

func show_toast(text: String, good: bool) -> void:
	var l := _label(32, Color("c8ff9e") if good else Color("ffb0a0"))
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 12)
	toasts.add_child(l)
	while toasts.get_child_count() > 4:
		toasts.get_child(0).free()
	var tw := create_tween()
	tw.tween_interval(2.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

func _rebuild_inventory() -> void:
	for c in inv_box.get_children():
		c.queue_free()
	if rules.inventory.is_empty():
		var l := _label(24, Color("b8966a"))
		l.text = "Сумка пуста — шарь по заначкам (жёлтые кружки)"
		inv_box.add_child(l)
		return
	for item in rules.inventory:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(88, 88)
		b.tooltip_text = rules.item_title(item)
		var path: String = Rules3D.ITEMS[item][1]
		if path != "":
			b.icon = load(path)
			b.expand_icon = true
		else:
			b.text = rules.item_title(item)
			b.add_theme_font_size_override("font_size", 20)
		var sel: bool = rules.selected == item
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("ffd36a", 0.55) if sel else Color(1, 1, 1, 0.08)
		sb.set_corner_radius_all(12)
		sb.border_color = Color("ffd36a") if sel else Color(1, 1, 1, 0.2)
		sb.set_border_width_all(3)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func():
			Settings.sfx("click", 0.6)
			rules.select(item))
		inv_box.add_child(b)

# ---------------------------------------------------------------- задания
## Список заданий справа: что подменить, какие пакости устроить, финал. Квадратик: пустой — не сделано,
## оранжевый — подложено, ждём соседа; зелёная галочка — сработало. Tab — свернуть/развернуть.
const TASKS := [
	["Подмены", ""],
	["Незамерзайка в ополаск.", "swap_mouthwash", "sw:mouthwash"],
	["Настойка в кофе", "swap_coffee", "sw:coffee"],
	["Минералка → водка", "swap_fridge", "sw:fridge"],
	["Газировка → пиво", "swap_soda", "sw:soda"],
	["Чекушка в куртку", "swap_jacket", "sw:jacket"],
	["Пакости", ""],
	["Спрятать геймпад", "prank_gamepad", "tk:gamepad"],
	["Спрятать телефон", "prank_phone", "tk:phone"],
	["Спрятать ключи", "prank_keys", "tk:keys"],
	["Перегоревшая лампочка", "prank_bulb", "sw:ladder"],
	["Кожура у холодильника", "prank_peeltrap", "tr:peeltrap"],
	["Мыло у раковины", "prank_soaptrap", "tr:soaptrap"],
	["Финал", ""],
	["Салат на стол", "final_salad", "salad"],
]
const TASK_RECT := Rect2(1584, 146, 326, 0)

func _build_tasks() -> void:
	tasks = Control.new()
	tasks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tasks.position = TASK_RECT.position
	tasks.size = Vector2(TASK_RECT.size.x, 40)
	tasks.draw.connect(_draw_tasks)
	add_child(tasks)
	move_child(tasks, 0)

func toggle_tasks() -> void:
	set_tasks_visible(not Settings.show_tasks)
	Settings.save()

func set_tasks_visible(on: bool) -> void:
	Settings.show_tasks = on
	if tasks:
		tasks.queue_redraw()

func _task_state(t: Array) -> int:   # 0 — нет, 1 — подложено, 2 — готово
	if rules._scored.has(t[1]):
		return 2
	var c: String = t[2]
	if c == "salad":
		return 1 if rules.salad_on_table else 0
	var id := c.substr(3)
	match c.substr(0, 3):
		"sw:":
			return 1 if rules.swapped.has(id) else 0
		"tk:":
			return 1 if rules.taken.has(id) else 0
		"tr:":
			return 1 if rules.traps.has(id) else 0
	return 0

func _draw_tasks() -> void:
	if rules == null:
		return
	var f := tasks.get_theme_default_font()
	var w := TASK_RECT.size.x
	var open := Settings.show_tasks
	var row := 27.0
	var h := 44.0 if not open else 50.0 + TASKS.size() * row
	tasks.size = Vector2(w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.09, 0.04, 0.82)
	sb.border_color = Color("c98a3c")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	tasks.draw_style_box(sb, Rect2(Vector2.ZERO, tasks.size))
	var done := 0
	var total := 0
	for t in TASKS:
		if t[1] != "":
			total += 1
			if _task_state(t) == 2:
				done += 1
	tasks.draw_string(f, Vector2(16, 30), "Задания  %d / %d" % [done, total], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, C_TEXT)
	tasks.draw_string(f, Vector2(w - 60, 30), "Tab", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("b8966a"))
	if not open:
		return
	var y := 50.0
	for t in TASKS:
		if t[1] == "":
			tasks.draw_string(f, Vector2(16, y + 20), t[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("d99a4e"))
			y += row
			continue
		var st := _task_state(t)
		var box := Rect2(20, y + 5, 18, 18)
		if st == 2:
			tasks.draw_rect(box, Color("4caf50"))
			tasks.draw_polyline(PackedVector2Array([box.position + Vector2(3, 9), box.position + Vector2(8, 14), box.position + Vector2(16, 3)]), Color.WHITE, 3.0)
		elif st == 1:
			tasks.draw_rect(box, Color("ff9a3d"))
			tasks.draw_circle(box.get_center(), 3.5, Color("3a1b0c"))
		else:
			tasks.draw_rect(box, Color(1, 1, 1, 0.12))
		tasks.draw_rect(box, Color("e2c697"), false, 2.0)
		var col := Color("9fcf8a") if st == 2 else (Color("ffcf8a") if st == 1 else C_DIM)
		var txt: String = t[0] + ("  — ждём" if st == 1 else "")
		tasks.draw_string(f, Vector2(48, y + 21), txt, HORIZONTAL_ALIGNMENT_LEFT, w - 56, 18, col)
		y += row

func _update_tasks_fade(delta: float) -> void:
	if tasks == null or rules == null or rules.game == null:
		return
	# кто-то из персонажей за панелью — сделать её прозрачнее
	var behind := false
	var r := Rect2(tasks.position, tasks.size).grow(20)
	for a in [rules.game.hero, rules.game.neighbor]:
		var ac := a as Node3D
		var cam: Camera3D = rules.game.cam
		for hgt in [0.3, 1.0, 1.7]:
			var p := ac.global_position + Vector3(0, hgt, 0)
			if not cam.is_position_behind(p) and r.has_point(cam.unproject_position(p)):
				behind = true
	tasks.modulate.a = move_toward(tasks.modulate.a, 0.3 if behind else 1.0, delta * 4.0)
	_task_t -= delta
	if _task_t <= 0.0:
		_task_t = 0.25
		tasks.queue_redraw()

# ---------------------------------------------------------------- экраны
func show_intro() -> void:
	_overlay("Понедельник. «Больше не пью»",
		"Сосед в очередной раз завязал и пока спит. До 20:00 доведи его до финала — чтобы уснул (а лучше — лицом в салате).\n\n" +
		"• Шарь по заначкам (жёлтые кружки) и подменяй напитки, пока он не видит.\n" +
		"• Подкладывай кожуру и мыло, прячь геймпад, телефон и ключи — пусть звереет.\n" +
		"• Прячься (голубые кружки) и крадись (ПКМ/Shift) — шаги слышно.\n" +
		"• Поймает 3 раза — провал.",
		[["Начать", start_pressed]])

func show_results(win: bool, reason: String) -> void:
	var lines := "\n".join(rules.log_done.map(func(s): return "• " + s)) if not rules.log_done.is_empty() else "Ничего не вышло."
	_overlay("ПОБЕДА!" if win else "Провал",
		"%s\n\nОчки: %d   ·   Позор: %d%% — «%s»\n\n%s" % [reason, rules.score, rules.shame_percent(), rules.shame_title(), lines],
		[["Ещё раз", restart_pressed], ["В меню", menu_pressed]])

func show_pause() -> void:
	_overlay("Пауза", "", [["Продолжить", resume_pressed], ["Настройки", Signal()], ["Начать заново", restart_pressed], ["В главное меню", menu_pressed]])

func close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null

func _overlay(title: String, body: String, buttons: Array) -> void:
	close_overlay()
	overlay = ColorRect.new()
	(overlay as ColorRect).color = Color(0.08, 0.04, 0.02, 0.78)
	overlay.size = Vector2(1920, 1080)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay)
	var center := CenterContainer.new()
	center.size = Vector2(1920, 1080)
	overlay.add_child(center)
	var p := UiStyle.panel()
	center.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	p.add_child(vb)
	var t := UiStyle.label(title, 68, UiStyle.C_TITLE, 14)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	if body != "":
		var b := UiStyle.label(body, 29, C_TEXT, 6)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(1060, 0)
		vb.add_child(b)
	var row: BoxContainer = VBoxContainer.new() if buttons.size() > 2 else HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	for bd in buttons:
		var btn := UiStyle.button(bd[0], 38, 400)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var sig: Signal = bd[1]
		if sig.is_null():
			btn.pressed.connect(func(): add_child(SettingsPanel.new()))
		else:
			btn.pressed.connect(func():
				close_overlay()
				sig.emit())
		row.add_child(btn)

func has_overlay() -> bool:
	return overlay != null

# ---------------------------------------------------------------- помощники
func _panel(pos: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = pos
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.09, 0.04, 0.9)
	sb.border_color = Color("c98a3c")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 22)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(8)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(8)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b
