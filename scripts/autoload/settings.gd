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

func _load() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	music_volume = c.get_value("audio", "music", music_volume)
	sfx_volume = c.get_value("audio", "sfx", sfx_volume)
	voice_volume = c.get_value("audio", "voice", voice_volume)
	fullscreen = c.get_value("video", "fullscreen", fullscreen)

func save() -> void:
	var c := ConfigFile.new()
	c.set_value("audio", "music", music_volume)
	c.set_value("audio", "sfx", sfx_volume)
	c.set_value("audio", "voice", voice_volume)
	c.set_value("video", "fullscreen", fullscreen)
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
	var s := _stream(VOICE_DIR + key + ".wav")
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

func has_voice(text: String) -> bool:
	return _voice_index.has(text)

func music(name: String) -> void:
	if name == _music_name:
		return
	_music_name = name
	if name == "":
		_music.stop()
		return
	var s := _stream(MUSIC_DIR + name + ".wav") as AudioStreamWAV
	if s:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
		_music.stream = s
		_music.play()
