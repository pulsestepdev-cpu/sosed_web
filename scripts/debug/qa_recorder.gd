class_name QaRecorder
extends Node
## Регистратор для автотестов: события уровня, поимки, наложения реплик, производительность — и отчёт в JSON.
## Включается аргументом --report=путь.json. --quit-on-end — закрыть игру после итогов (или по --max-real=сек).
## Производительность честная только в окне (в --headless рендера нет: FPS там не смотреть).

var game: Node            # Game3D
var path := ""
var quit_on_end := false
var max_real := 0.0
var _start_us := 0
var _last_us := 0
var _frames := 0
var _frame_ms: Array[float] = []
var _spikes := 0           # кадры дольше 50 мс
var _worst_ms := 0.0
var _events: Array = []
var _overlap_t := 0.0      # секунд, когда сосед и герой звучат одновременно
var _overlaps := 0
var _was_overlap := false
var _activity := ""
var _thoughts := 0
var _result := {}
var _written := false

func setup(g: Node, report_path: String, quit: bool, max_real_s: float) -> void:
	game = g
	path = report_path
	quit_on_end = quit
	max_real = max_real_s
	_start_us = Time.get_ticks_usec()
	_last_us = _start_us
	game.rules.toast.connect(func(t, good): _ev("toast", {"text": t, "good": good}))
	game.rules.finished.connect(_on_finished)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ev(kind: String, data := {}) -> void:
	var e := {"hour": snappedf(game.hour, 0.01), "kind": kind}
	e.merge(data)
	_events.append(e)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	_frames += 1
	if _frames > 30:            # первые кадры — загрузка, не считаем
		_frame_ms.append(ms)
		_worst_ms = maxf(_worst_ms, ms)
		if ms > 50.0:
			_spikes += 1
	# наложение озвучки: оба голоса играют одновременно
	var vp: Dictionary = Settings._voice_players
	var both: bool = vp.has("n") and vp.has("h") and (vp["n"] as AudioStreamPlayer).playing and (vp["h"] as AudioStreamPlayer).playing
	if both:
		_overlap_t += ms / 1000.0
		if not _was_overlap:
			_overlaps += 1
			_ev("voice_overlap", {"neighbor": game.neighbor.bubble, "hero": game.hero.bubble})
	_was_overlap = both
	if game.neighbor.activity != _activity:
		_activity = game.neighbor.activity
		_ev("neighbor", {"activity": _activity, "room": game.room_at(game.neighbor.position)})
	if game.neighbor.thought != "" and (_events.is_empty() or _events[-1].get("thought", "") != game.neighbor.thought):
		_thoughts += 1
		_ev("thought", {"thought": game.neighbor.thought})
	if max_real > 0.0 and (now - _start_us) / 1e6 > max_real and not _written:
		_result = {"win": false, "reason": "timeout (реальное время %.0f с)" % max_real, "timeout": true}
		_write()

func note_catch() -> void:
	_ev("caught", {"room": game.room_at(game.hero.position), "neighbor": game.neighbor.activity})

func _on_finished(win: bool, reason: String) -> void:
	_result = {"win": win, "reason": reason}
	get_tree().create_timer(0.5, true, false, true).timeout.connect(_write)

func _write() -> void:
	if _written:
		return
	_written = true
	var r: Rules3D = game.rules
	var sorted_ms := _frame_ms.duplicate()
	sorted_ms.sort()
	var avg := 0.0
	for m in _frame_ms:
		avg += m
	avg = avg / maxf(1.0, _frame_ms.size())
	var tasks := {}
	for t in Hud3D.TASKS:
		if t[1] != "":
			tasks[t[0]] = r._scored.has(t[1])
	var rep := {
		"result": _result,
		"hour_end": snappedf(game.hour, 0.01),
		"score": r.score, "shame_percent": r.shame_percent(), "drunk": r.drunk, "catches": r.catches,
		"tasks_done": tasks.values().count(true), "tasks_total": tasks.size(), "tasks": tasks,
		"scored": r._scored.keys(),
		"voice_overlaps": _overlaps, "voice_overlap_sec": snappedf(_overlap_t, 0.01),
		"thoughts_shown": _thoughts,
		"perf": {
			"headless": DisplayServer.get_name() == "headless",
			"frames": _frame_ms.size(),
			"avg_ms": snappedf(avg, 0.01),
			"avg_fps": snappedf(1000.0 / maxf(0.001, avg), 0.1),
			"p95_ms": snappedf(sorted_ms[int(sorted_ms.size() * 0.95)] if not sorted_ms.is_empty() else 0.0, 0.01),
			"worst_ms": snappedf(_worst_ms, 0.01),
			"spikes_over_50ms": _spikes,
			"time_scale": Engine.time_scale,
		},
		"real_seconds": snappedf((Time.get_ticks_usec() - _start_us) / 1e6, 0.1),
		"events": _events,
	}
	if OS.has_feature("web"):      # в браузере файла нет — отчёт в window.__qa.report (забирает web_check.py)
		rep.erase("events")
		Settings.qa_mark("report", rep)
		return
	var abs_path := path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rep, "  "))
		f.close()
	print("[QA] report -> ", abs_path, "  win=", _result.get("win"), " score=", r.score, " tasks=", rep["tasks_done"], "/", rep["tasks_total"])
	if quit_on_end:
		get_tree().quit()
