extends Control
## Главный экран: обложка игры на весь экран, кнопки «Играть», «Настройки», «Выход».

const GAME := "res://scenes/game.tscn"

var _buttons: VBoxContainer
var _loading: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("2a1408")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/menu_bg.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(art)
	# лёгкое затемнение снизу — под кнопки
	var grad := TextureRect.new()
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color(0, 0, 0, 0))
	g.gradient.set_color(1, Color(0.08, 0.03, 0.0, 0.55))
	g.fill_from = Vector2(0, 0.45)
	g.fill_to = Vector2(0, 1)
	grad.texture = g
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grad)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 22)
	_buttons.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_buttons.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_buttons.offset_bottom = -70
	add_child(_buttons)
	var play := UiStyle.button("Играть", 56, 460)
	play.pressed.connect(_play)
	_buttons.add_child(play)
	var opts := UiStyle.button("Настройки", 44, 460)
	opts.pressed.connect(func(): add_child(SettingsPanel.new()))
	_buttons.add_child(opts)
	var quit := UiStyle.button("Выход", 44, 460)
	quit.pressed.connect(func(): get_tree().quit())
	quit.visible = not OS.has_feature("web")     # в браузере закрыть игру нельзя — вкладку закрывают сами
	_buttons.add_child(quit)

	var ver := UiStyle.label("Уровень 1 · «Понедельник. Больше не пью»", 24, Color("ffe6b0"), 8)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(24, -50)
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(ver)

	_loading = UiStyle.label("Загрузка…", 48, UiStyle.C_TITLE, 12)
	_loading.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_loading.offset_bottom = -200
	_loading.visible = false
	add_child(_loading)

	Settings.music("main_musik")
	# появление кнопок
	_buttons.modulate.a = 0.0
	create_tween().tween_property(_buttons, "modulate:a", 1.0, 0.6).set_delay(0.2)
	if "--play" in OS.get_cmdline_user_args():
		_play.call_deferred()

func _play() -> void:
	_buttons.visible = false
	_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(GAME)
