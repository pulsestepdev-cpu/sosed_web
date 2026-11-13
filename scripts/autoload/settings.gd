extends Node
## Настройки игры (громкость, экран) и звук: эффекты, озвучка реплик, музыка.
## Хранится в user://settings.cfg. Шины: Music, Sfx, Voice.

const PATH := "user://settings.cfg"
const SFX_DIR := "res://assets/audio/sfx/"
const VOICE_DIR := "res://assets/audio/voice/"
const MUSIC_DIR := "res://assets/audio/music/"

var music_volume := 0.6
var sfx_volume := 0.8
var voice_volume := 1.0
var fullscreen := false
var camera_close := false       # true — крупная камера на героя с прокруткой у краёв экрана
var show_tasks := true          # список заданий в игре (Tab)
var quality := "auto"           # графика: auto (по FPS в начале игры) | high | low

var _music: AudioStreamPlayer
var _music_name := ""
var _voice_index := {}
var _voice_players := {}        # кто -> AudioStreamPlayer (у каждого свой голос, не перебивают друг друга)
var _sfx_pool: Array[AudioStreamPlayer] = []
var _cache := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "Sfx", "Voice"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_load()
	apply()
	_apply_ui_scale()
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_sfx_pool.append(p)
	var f := FileAccess.open(VOICE_DIR + "index.json", FileAccess.READ)
	if f:
		_voice_index = JSON.parse_string(f.get_as_text())

var _touch := -1

## Сенсорное устройство (телефон, планшет): основной указатель — палец. Ноутбук с сенсорным экраном и мышью — не считается.
func is_touch() -> bool:
	if _touch < 0:
		_touch = 0
		if OS.has_feature("web"):
			var r = JavaScriptBridge.eval("((window.matchMedia && window.matchMedia('(pointer: coarse)').matches) || " +
				"((navigator.maxTouchPoints || 0) > 0 && /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent)) || " +
				"(navigator.platform === 'MacIntel' && (navigator.maxTouchPoints || 0) > 1)) ? 1 : 0", true)
			_touch = 1 if str(r) in ["1", "true", "1.0"] else 0
		elif OS.has_feature("mobile"):
			_touch = 1
		if Settings.debug_args().has("touch"):     # отладка: --touch (интерфейс телефона на ПК)
			_touch = 1
	return _touch == 1

## Интерфейс крупнее на маленьких экранах: телефон ×1,6, планшет ×1,3 (по короткой стороне экрана в CSS-пикселях).
func _apply_ui_scale() -> void:
	if not is_touch():
		return
	qa_mark("touch", true)
	var short := 400.0
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("Math.min(screen.width, screen.height)", true)
		if v is float or v is int:
			short = float(v)
	var k := 1.6 if short < 520.0 else (1.3 if short < 900.0 else 1.1)
	get_tree().root.content_scale_factor = k

func _load() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	music_volume = c.get_value("audio", "music", music_volume)
	sfx_volume = c.get_value("audio", "sfx", sfx_volume)
	voice_volume = c.get_value("audio", "voice", voice_volume)
	fullscreen = c.get_value("video", "fullscreen", fullscreen)
	camera_close = c.get_value("game", "camera_close", camera_close)
	show_tasks = c.get_value("game", "show_tasks", show_tasks)
	quality = c.get_value("video", "quality", quality)

func save() -> void:
	var c := ConfigFile.new()
	c.set_value("audio", "music", music_volume)
	c.set_value("audio", "sfx", sfx_volume)
	c.set_value("audio", "voice", voice_volume)
	c.set_value("video", "fullscreen", fullscreen)
	c.set_value("game", "camera_close", camera_close)
	c.set_value("game", "show_tasks", show_tasks)
	c.set_value("video", "quality", quality)
	c.save(PATH)

func apply() -> void:
	_set_bus("Music", music_volume)
	_set_bus("Sfx", sfx_volume)
	_set_bus("Voice", voice_volume)
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want and not (not fullscreen and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
			DisplayServer.window_set_mode(want)

func _set_bus(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, v <= 0.001)

func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]

## Звуковой эффект по имени файла без расширения (step_0, pickup, ...). vol — 0..1, pitch — высота.
func sfx(name: String, vol := 1.0, pitch := 1.0) -> void:
	var s := _stream(SFX_DIR + name + ".ogg")        # настоящие записи (Kenney, CC0) — в приоритете
	if s == null:
		s = _stream(SFX_DIR + name + ".wav")         # сгенерированные tools/gen_audio.py
	if s == null:
		return
	var p: AudioStreamPlayer = _sfx_pool[0]
	for q in _sfx_pool:
		if not q.playing:
			p = q
			break
	p.stream = s
	p.volume_db = linear_to_db(maxf(vol, 0.0001))
	p.pitch_scale = pitch
	p.play()

## Озвучить реплику, если для этого текста есть запись. Возвращает длительность (0 — записи нет).
func voice(text: String, who := "n") -> float:
	var key: String = _voice_index.get(text, "")
	if key == "":
		return 0.0
	var s := _stream(VOICE_DIR + key + ".mp3")      # нейроголос (tools/gen_audio.py voice)
	if s == null:
		s = _stream(VOICE_DIR + key + ".wav")
	if s == null:
		return 0.0
	if not _voice_players.has(who):
		var p := AudioStreamPlayer.new()
		p.bus = "Voice"
		add_child(p)
		_voice_players[who] = p
	var pl: AudioStreamPlayer = _voice_players[who]
	pl.stream = s
	pl.play()
	return s.get_length()

func voice_playing(who: String) -> bool:
	return _voice_players.has(who) and (_voice_players[who] as AudioStreamPlayer).playing

func stop_voice(who: String) -> void:
	if _voice_players.has(who):
		(_voice_players[who] as AudioStreamPlayer).stop()

## Отладочные аргументы: из командной строки (после --) и, в браузере, из адреса страницы
## (?qa=1&bot=normal&perf=1 — то же, что --qa --bot=normal --perf). Для автотестов (tools/qa/web_check.py).
func debug_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and q.length() > 1:
			for pair in (q as String).substr(1).split("&", false):
				var kv := (pair as String).split("=", true, 1)
				out[kv[0].uri_decode()] = kv[1].uri_decode() if kv.size() > 1 else "true"
	return out

## Отметка для автотестов: печать в лог и, в браузере, в window.__qa (консоль многопоточной сборки приходит
## с задержкой, а переменную страницы web_check.py читает сразу). value — любое значение для JSON.
func qa_mark(key: String, value: Variant = true) -> void:
	print("[QA] %s %s" % [key, str(value) if not (value is Dictionary or value is Array) else ""])
	if OS.has_feature("web"):
		var js := "window.__qa=window.__qa||{};window.__qa[%s]={t:performance.now(),v:%s};" % [JSON.stringify(key), JSON.stringify(value)]
		JavaScriptBridge.eval(js, true)

func has_voice(text: String) -> bool:
	return _voice_index.has(text)

## Треки: имя -> [с какой секунды играть (вступление пропускаем, туда же возвращается цикл), громкость, дБ].
## main_musik — песня автора игры: в меню и фоном в игре, средняя громкость, не перезапускается между сценами.
const TRACKS := {"main_musik": [15.8, -7.0]}

func music(name: String) -> void:
	if name == _music_name:
		return
	_music_name = name
	if name == "":
		_music.stop()
		return
	var cfg: Array = TRACKS.get(name, [0.0, 0.0])
	var mp := _stream(MUSIC_DIR + name + ".mp3") as AudioStreamMP3
	if mp:
		mp.loop = true
		mp.loop_offset = cfg[0]
		_music.stream = mp
		_music.volume_db = -30.0
		_music.play(cfg[0])
		create_tween().tween_property(_music, "volume_db", cfg[1], 2.5)
		return
	var s := _stream(MUSIC_DIR + name + ".wav") as AudioStreamWAV
	if s:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
		_music.stream = s
		_music.volume_db = cfg[1]
		_music.play()
