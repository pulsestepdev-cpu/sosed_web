class_name Hud
extends CanvasLayer
## Интерфейс уровня: часы и статус, шкала опьянения, поимки и очки, инвентарь,
## подсказка у курсора, всплывающие сообщения, экраны вступления и итогов.

signal start_pressed
signal restart_pressed

const C_PANEL := Color(0.16, 0.10, 0.06, 0.92)
const C_TEXT := Color("ffe9b8")
const C_DIM := Color("d9bd8c")

var rules: Level1Rules
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

func _ready() -> void:
	layer = 10
	# левая панель — время и статус
	var left := _panel(Vector2(20, 14))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 26)
	left.add_child(hb)
	clock = _label(62, C_TEXT)
	hb.add_child(clock)
	status = _label(26, C_DIM)
	hb.add_child(status)

	# правая панель — опьянение, поимки, очки
	var right := _panel(Vector2(1300, 14))
	right.custom_minimum_size = Vector2(600, 0)
	var vb := VBoxContainer.new()
	right.add_child(vb)
	drunk_label = _label(28, C_TEXT)
	vb.add_child(drunk_label)
	drunk_bar = _bar(Color("e0662f"))
	vb.add_child(drunk_bar)
	stats = _label(24, C_DIM)
	vb.add_child(stats)

	# индикатор «заметил»
	suspicion_bar = _bar(Color("ff3b2f"))
	suspicion_bar.position = Vector2(760, 140)
	suspicion_bar.size = Vector2(400, 18)
	suspicion_bar.visible = false
	add_child(suspicion_bar)

	# инвентарь
	var inv_panel := _panel(Vector2(560, 922))
	inv_panel.custom_minimum_size = Vector2(800, 112)
	inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	inv_box = HBoxContainer.new()
	inv_box.add_theme_constant_override("separation", 10)
	inv_box.alignment = BoxContainer.ALIGNMENT_CENTER
	inv_panel.add_child(inv_box)

	var hint := _label(19, Color("b8976a"))
	hint.text = "ЛКМ — идти / взять / спрятаться  ·  предмет в сумке → цель — подложить  ·  ПКМ/Shift — крадучись  ·  колесо — приблизить  ·  Пробел — пауза  ·  F — x3"
	hint.position = Vector2(24, 1046)
	add_child(hint)

	toasts = VBoxContainer.new()
	toasts.position = Vector2(560, 150)
	toasts.custom_minimum_size = Vector2(800, 0)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)

	tooltip = _label(26, Color.WHITE)
	tooltip.add_theme_color_override("font_outline_color", Color.BLACK)
	tooltip.add_theme_constant_override("outline_size", 10)
	tooltip.visible = false
	add_child(tooltip)

func bind(r: Level1Rules) -> void:
	rules = r
	rules.toast.connect(show_toast)
	rules.inventory_changed.connect(_rebuild_inventory)
	_rebuild_inventory()

func update_view(hour: float, neighbor_text: String, hero_text: String, suspicion: float, paused: bool, fast: bool) -> void:
	var h := int(hour)
	clock.text = "%02d:%02d" % [h, int((hour - h) * 60.0)]
	status.text = "Сосед: %s\nГерой: %s%s%s" % [neighbor_text, hero_text,
		"   ⏸ ПАУЗА" if paused else "", "   ⏩ x3" if fast else ""]
	drunk_label.text = "Опьянение соседа: %d%%  —  «%s»" % [int(rules.drunk), rules.stage_name()]
	drunk_bar.value = rules.drunk
	stats.text = "Поимки: %d / 3      Очки: %d" % [rules.catches, rules.score]
	suspicion_bar.visible = suspicion > 0.01
	suspicion_bar.value = suspicion * 100.0

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
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

func _rebuild_inventory() -> void:
	for c in inv_box.get_children():
		c.queue_free()
	if rules.inventory.is_empty():
		var l := _label(24, Color("9c7d55"))
		l.text = "Сумка пуста — ищи заначки (жёлтые кружки)"
		inv_box.add_child(l)
		return
	for item in rules.inventory:
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 96)
		b.tooltip_text = rules.item_title(item)
		var path: String = Level1Rules.ITEMS[item][1]
		if path != "":
			b.icon = load(path)
			b.expand_icon = true
		else:
			b.text = rules.item_title(item)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("ffd36a", 0.55) if rules.selected == item else Color(1, 1, 1, 0.08)
		sb.set_corner_radius_all(12)
		sb.border_color = Color("ffd36a") if rules.selected == item else Color(1, 1, 1, 0.2)
		sb.set_border_width_all(3)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func(): rules.select(item))
		inv_box.add_child(b)

# --- Экраны ------------------------------------------------------------------------

func show_intro() -> void:
	_overlay("Сосед на бутылке",
		"Уровень 1. Понедельник. «Больше не пью».\n\n" +
		"Сосед в очередной раз завязал. До 20:00 доведи его до финала —\nчтобы уснул (а лучше — лицом в салате).\n\n" +
		"• Ищи заначки (жёлтые кружки) и подменяй напитки, пока он не видит.\n" +
		"• Прячься (голубые кружки) и крадись (ПКМ/Shift) — шаги слышно.\n" +
		"• Поймает 3 раза — провал.",
		"Начать", start_pressed)

func show_results(win: bool, reason: String) -> void:
	var lines := "\n".join(rules.log_done.map(func(s): return "• " + s)) if not rules.log_done.is_empty() else "Ничего не вышло."
	_overlay("ПОБЕДА!" if win else "Провал",
		"%s\n\nОчки: %d   ·   Позор: %d%% — «%s»\n\n%s" % [reason, rules.score, rules.shame_percent(), rules.shame_title(), lines],
		"Ещё раз", restart_pressed)

func _overlay(title: String, body: String, button: String, sig: Signal) -> void:
	if overlay:
		overlay.queue_free()
	overlay = ColorRect.new()
	(overlay as ColorRect).color = Color(0.08, 0.05, 0.03, 0.82)
	overlay.size = Vector2(1920, 1080)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var p := _panel(Vector2.ZERO)
	p.get_parent().remove_child(p)
	overlay.add_child(p)
	p.custom_minimum_size = Vector2(1100, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	p.add_child(vb)
	var t := _label(72, Color("ffcf6a"))
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var b := _label(30, C_TEXT)
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(1040, 0)
	vb.add_child(b)
	var btn := Button.new()
	btn.text = button
	btn.add_theme_font_size_override("font_size", 40)
	btn.custom_minimum_size = Vector2(360, 84)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func():
		overlay.queue_free()
		overlay = null
		sig.emit())
	vb.add_child(btn)
	p.position = (Vector2(1920, 1080) - p.get_combined_minimum_size()) * 0.5
	p.resized.connect(func(): p.position = (Vector2(1920, 1080) - p.size) * 0.5)

func has_overlay() -> bool:
	return overlay != null

# --- Помощники -----------------------------------------------------------------------

func _panel(pos: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = pos
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
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
