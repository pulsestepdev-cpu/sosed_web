class_name SettingsPanel
extends Control
## Окно настроек: громкость музыки, звуков, голоса; полный экран; камера; список заданий.
## Закрывается кнопкой «Назад» или Esc.

signal closed

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := UiStyle.panel()
	center.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	p.add_child(vb)
	var t := UiStyle.label("Настройки", 64, UiStyle.C_TITLE, 14)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	_slider(vb, "Музыка", Settings.music_volume, func(v): Settings.music_volume = v)
	_slider(vb, "Звуки", Settings.sfx_volume, func(v):
		Settings.sfx_volume = v
		Settings.sfx("pickup", 0.6))
	_slider(vb, "Голоса", Settings.voice_volume, func(v): Settings.voice_volume = v)
	_check(vb, "Полный экран", Settings.fullscreen, func(on):
		Settings.fullscreen = on
		Settings.apply())
	_check(vb, "Крупная камера (обзор — мышь к краю экрана)", Settings.camera_close, func(on):
		Settings.camera_close = on
		var g := get_tree().current_scene
		if g is Game3D:
			g.zoomed = on
			g.center_on_hero())
	_check(vb, "Список заданий (Tab)", Settings.show_tasks, func(on):
		Settings.show_tasks = on
		var g := get_tree().current_scene
		if g is Game3D:
			g.hud.set_tasks_visible(on))
	var back := UiStyle.button("Назад", 40, 360)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close)
	vb.add_child(back)

func _check(parent: Control, title: String, value: bool, on_toggle: Callable) -> void:
	var cb := CheckButton.new()
	cb.text = title
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = value
	cb.add_theme_font_size_override("font_size", 32)
	cb.add_theme_color_override("font_color", UiStyle.C_TEXT)
	cb.add_theme_color_override("font_hover_color", Color.WHITE)
	cb.add_theme_color_override("font_pressed_color", UiStyle.C_TEXT)
	cb.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	cb.toggled.connect(on_toggle)
	parent.add_child(cb)

func _slider(parent: Control, title: String, value: float, on_change: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)
	parent.add_child(hb)
	var l := UiStyle.label(title, 36)
	l.custom_minimum_size = Vector2(200, 0)
	hb.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(460, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var grab := Image.create(30, 30, false, Image.FORMAT_RGBA8)
	grab.fill(Color(0, 0, 0, 0))
	for y in 30:
		for x in 30:
			var d := Vector2(x - 14.5, y - 14.5).length()
			if d < 14.5:
				grab.set_pixel(x, y, Color("ffd27a") if d < 11.5 else Color("3a1b0c"))
	var gt := ImageTexture.create_from_image(grab)
	s.add_theme_icon_override("grabber", gt)
	s.add_theme_icon_override("grabber_highlight", gt)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.5)
	track.set_corner_radius_all(8)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("e07a2a")
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var pct := UiStyle.label("%d%%" % roundi(value * 100), 30)
	pct.custom_minimum_size = Vector2(90, 0)
	s.value_changed.connect(func(v):
		pct.text = "%d%%" % roundi(v * 100)
		on_change.call(v)
		Settings.apply())
	hb.add_child(s)
	hb.add_child(pct)

func _close() -> void:
	Settings.save()
	closed.emit()
	queue_free()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
