extends Control
## Главный экран: обложка игры на весь экран, кнопки «Играть» (экран недели), «Настройки», «Выход».

const GAME := "res://scenes/game.tscn"

var _buttons: VBoxContainer
var _loading: Label
var _qa_wait := false

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
	play.pressed.connect(_open_week)
	_buttons.add_child(play)
	var opts := UiStyle.button("Настройки", 44, 460)
	opts.pressed.connect(func(): add_child(SettingsPanel.new()))
	_buttons.add_child(opts)
	var quit := UiStyle.button("Выход", 44, 460)
	quit.pressed.connect(func(): get_tree().quit())
	quit.visible = not OS.has_feature("web")     # в браузере закрыть игру нельзя — вкладку закрывают сами
	_buttons.add_child(quit)

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
	Settings.qa_mark("menu_ready")
	var dbg := Settings.debug_args()
	if Progress.open_week:
		Progress.open_week = false
		_open_week.call_deferred()
	if dbg.has("week"):
		_open_week.call_deferred()
	elif dbg.has("play"):
		_play.call_deferred()
	elif dbg.has("qa"):            # автотест в браузере: старт по первому клику/касанию — как у живого игрока
		_qa_wait = true            # (браузер включает звук только после жеста пользователя)
		print("[QA] waiting for gesture")

func _input(ev: InputEvent) -> void:
	if _qa_wait and ((ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed)):
		_qa_wait = false
		_play()

func _open_week() -> void:
	if get_node_or_null("Week"):
		return
	var w := WeekScreen.new()
	w.name = "Week"
	_buttons.visible = false
	w.day_chosen.connect(func(_n):
		w.queue_free()
		_play())
	w.closed.connect(func(): _buttons.visible = true)
	add_child(w)

func _play() -> void:
	_buttons.visible = false
	_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(GAME)
