extends Node
## Обновления версии для ПК: при запуске подхватывает файл-патч patch_N.pck (только изменённые файлы игры).
## Ищет рядом с exe и в user://patches/ (место для будущего автообновления), берёт патч с самым большим N:
## каждый патч собирается от базовой версии и содержит все изменения сразу, старые можно удалять.
## Должна стоять ПЕРВОЙ в автозагрузке: остальные скрипты и сцены грузятся уже с учётом патча.
## Сам этот файл и project.godot (автозагрузки, настройки проекта) патчем не меняются — для них нужна новая полная версия.
## Сборка: python tools/build_windows.py (полная версия или --patch).

var patch := 0                  ## номер загруженного патча (0 — без патча)
var version := ""               ## строка версии из res://version.cfg (её пишет сборка), «» — сборка без версии


func _init() -> void:
	if OS.has_feature("pc") and not OS.has_feature("editor"):
		var best := ""
		for dir in [OS.get_executable_path().get_base_dir(), ProjectSettings.globalize_path("user://patches")]:
			if not DirAccess.dir_exists_absolute(dir):
				continue
			for f in DirAccess.get_files_at(dir):
				var n := _patch_number(f)
				if n > patch:
					patch = n
					best = dir.path_join(f)
		if best != "" and not ProjectSettings.load_resource_pack(best, true):
			push_warning("Патч не загрузился: " + best)
			patch = 0
	var c := ConfigFile.new()
	if c.load("res://version.cfg") == OK:
		version = str(c.get_value("build", "version", ""))


## «patch_12.pck» → 12, всё остальное → 0.
static func _patch_number(file: String) -> int:
	if not (file.begins_with("patch_") and file.ends_with(".pck")):
		return 0
	var s := file.trim_prefix("patch_").trim_suffix(".pck")
	return int(s) if s.is_valid_int() else 0


## Для меню: «версия 3» / «версия 3 · патч 2» / «» (веб и редактор).
func label() -> String:
	if version == "":
		return ""
	return "версия " + version + (" · патч %d" % patch if patch > 0 else "")
