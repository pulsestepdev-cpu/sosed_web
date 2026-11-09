extends SceneTree
## Проверка озвучки: каждая реплика из assets/audio/voice/index.json грузится и не пустая.
## Godot.exe --headless --path . --script res://tools/check_voice.gd
func _init() -> void:
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/voice/index.json"))
	var bad := 0
	for text in idx:
		var p := "res://assets/audio/voice/%s.mp3" % idx[text]
		var s := load(p) as AudioStream if ResourceLoader.exists(p) else null
		if s == null or s.get_length() < 0.3:
			bad += 1
			print("BAD ", p, "  ", text)
	print("VOICE_OK %d / %d" % [idx.size() - bad, idx.size()])
	quit()
