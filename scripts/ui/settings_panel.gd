class_name SettingsPanel
extends Control
## Окно настроек: громкость музыки, звуков, голоса; полный экран; камера; список заданий.
## Закрывается кнопкой «Назад» или Esc.

signal closed

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	_choice(vb, "Графика", [["auto", "Авто"], ["high", "Высокая"], ["low", "Низкая"]], Settings.quality, func(v):
		Settings.quality = v
		var g := get_tree().current_scene
		if g is Game3D:
			g.low_quality = false
			g.apply_quality())
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

## Выбор из нескольких вариантов: подпись и ряд кнопок, выбранная — оранжевая.
func _choice(parent: Control, title: String, options: Array, value: String, on_pick: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	parent.add_child(hb)
	var l := UiStyle.label(title, 32)
	l.custom_minimum_size = Vector2(200, 0)
	hb.add_child(l)
	var btns: Array[Button] = []
	for o in options:
		var b := Button.new()
		b.text = o[1]
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(170, 52)
		b.add_theme_font_size_override("font_size", 28)
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("e07a2a") if st.contains("pressed") else Color(0.3, 0.17, 0.08, 0.9)
			sb.border_color = Color("3a1b0c")
			sb.set_border_width_all(3)
			sb.set_corner_radius_all(12)
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_color", UiStyle.C_TEXT)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.button_pressed = o[0] == value
		btns.append(b)
		hb.add_child(b)
	for i in btns.size():
		var key: String = options[i][0]
		btns[i].pressed.connect(func():
			for j in btns.size():
				btns[j].set_pressed_no_signal(j == i)
			on_pick.call(key))

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
	cb.add_theme_constant_override("h_separation", 22)
	# крупный тумблер вместо стандартного (в браузере игра уменьшается под окно — стандартный не разглядеть)
	var on_icon := _toggle_icon(true)
	var off_icon := _toggle_icon(false)
	for n in ["checked", "checked_mirrored", "checked_disabled", "checked_disabled_mirrored"]:
		cb.add_theme_icon_override(n, on_icon)
	for n in ["unchecked", "unchecked_mirrored", "unchecked_disabled", "unchecked_disabled_mirrored"]:
		cb.add_theme_icon_override(n, off_icon)
	cb.toggled.connect(on_toggle)
	parent.add_child(cb)

## Тумблер 84×44: дорожка (оранжевая — вкл, тёмная — выкл) с белым кружком справа/слева.
func _toggle_icon(on: bool) -> ImageTexture:
	var w := 84
	var h := 44
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := h * 0.5
	var track := Color("e07a2a") if on else Color("4a2c18")
	var knob_x := w - r if on else r
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, r, w - r)
			var d := p.distance_to(Vector2(cx, r))
			if d < r:
				img.set_pixel(x, y, Color("3a1b0c") if d > r - 3.0 else track)
			var dk := p.distance_to(Vector2(knob_x, r))
			if dk < r - 6.0:
				img.set_pixel(x, y, Color("fff3d6") if dk < r - 8.0 else Color("3a1b0c"))
	return ImageTexture.create_from_image(img)

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
