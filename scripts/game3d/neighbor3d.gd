class_name Neighbor3D
extends Actor
## Сосед: спит на кровати, потом живёт по расписанию, пользуется вещами (через правила уровня),
## бурно реагирует на пакости, пьянеет (лицо, походка, обзор), оглядывается и ловит героя.

signal finale_done

## Распорядок дня — цепочка дел, как в классике жанра: пришёл, сколько-то секунд занят делом, пошёл дальше.
## Берётся из данных дня (Days: plan, loop). Когда список кончился — по кругу с loop. Куда пойдёт дальше,
## видно заранее: облачко-мысль над головой и метка на полу.
## [x, этаж, что делает, клип, использует, куда смотрит: back | front | left | right | tv, секунд на месте, z (необяз.)]
var PLAN: Array = []
var LOOP_FROM := 3
## Мысль перед делом: activity -> что он думает (в облачке, вместе с комнатой).
const THOUGHTS := {"чистит зубы": "почистить зубы", "умывается": "умыться", "пьёт кофе": "кофейку",
	"шпаклюет стену": "пошпаклевать стену", "пьёт минералку": "минералочки", "играет в приставку": "в приставку",
	"дышит воздухом": "подышать воздухом", "меняет лампочку": "лампочку поменять", "пьёт газировку": "газировочки",
	"сидит в чат-рулетке": "в чат-рулетку", "собирается за хлебом": "за хлебом сходить", "ищет ключи": "где ключи?",
	"проверяет заначку": "проверить заначку", "ужинает": "поужинать", "проверяет закатки": "проверить закатки",
	"пьёт квас": "кваску", "чинит машину": "покопаться в машине", "собирает удочки": "собрать удочки",
	"разбирает хлам": "разобрать дедов хлам", "пьёт рассол": "рассольчику", "смотрит на голубей": "на голубей глянуть"}
const WAKE_HOUR := 8.0
## Что у него в руке, когда пользуется вещью: id -> [модель обычная, модель после подмены]
const HAND := {
	"mouthwash": ["mouthwash", "antifreeze"], "coffee": ["coffee_mug", "coffee_mug"],
	"fridge": ["mineral_water", "vodka"], "detour": ["mineral_water", "vodka"], "soda": ["soda_bottle", "beer_can"],
	"jacket": ["chekushka", "chekushka"], "gamepad": ["gamepad", "gamepad"], "phone": ["smartphone", "smartphone"],
	"ladder": ["light_bulb", "light_bulb_burnt"], "kvass": ["kvass_mug", "kvass_mug"], "brine": ["brine_jar", "brine_jar"],
}
## Сдвиг предмета в руке (в координатах кости хвата): короткие сосуды держат ближе ко дну.
const HOLD_SHIFT := {"kvass_mug": Vector3(0, -0.07, 0), "brine_jar": Vector3(0, -0.09, 0)}
const USE_DELAY := 1.2
const SOBER_RANGE := 3.0
## Копается в машине — воркует с ней.
const CAR_LOVE := [
	"Ласточка моя… Хоть ты не пьёшь.",
	"Мерин мой… Только ты меня понимаешь.",
	"Тачку пропить — последнее дело. Не, не пропью.",
]
## Говорит за делом (раз за приход, с вероятностью ACT_LINE_P, через ACT_LINE_AFTER с на месте — после того, как
## воспользовался вещью и отреагировал). Шпаклёвка и машина — свои реплики сразу по приходу (_on_arrived).
const ACT_LINES := {
	"чистит зубы": ["Зубы — как у молодого!", "Тридцать два… ну, двадцать восемь. Все мои!"],
	"умывается": ["Ух, свежо! Как заново родился.", "Морда — как у трезвенника!"],
	"проверяет закатки": ["Огурчики, помидорчики… Всё посчитано.", "Под такой огурчик — грех не… Не-не-не, считаю!",
		"Банка к банке. Порядок!"],
	"проверяет заначку": ["Так-с… Порядок должен быть.", "Я просто проверяю. Просто проверяю!"],
	"разбирает хлам": ["Дедов баян… Медаль «За трезвость»? Ха!", "О, дедова фляжка! Пустая. Жаль…",
		"Это выкинуть, это оставить… Всё оставить."],
	"смотрит на голубей": ["Гули-гули-гули…", "Вот кому хорошо — ни работы, ни похмелья.", "Ишь, расселись, пернатые!"],
	"дышит воздухом": ["Ух, воздух-то какой… Трезвый!", "Хорошо… Аж голова прояснилась.", "Вдох… выдох… Не пью. Не пью."],
	"играет в приставку": ["Ну! Ну! Гол!", "Да как он отбил?!", "Ещё один матч — и всё."],
}
const ACT_LINE_AFTER := 3.0
const ACT_LINE_P := 0.6
const GRUMBLE := ["Бу-бу-бу… никто не ценит…", "Эх, жизнь…", "Хм-м… Ну и ладно.", "Трезвым жить — скучно, но надо…",
	"Кефир… Кефир — тоже ничего.", "Держусь. Держусь, сука."]
## Пьяные фразы между делом: по две на стадию (Чуть-чуть, Весёлый, Тренер, В стельку).
const DRUNK_LINES := [["Ну одну-то можно…", "Это не считается."], ["А чё, нормально сидим!", "Я не пьяный, я весёлый!"],
	["Жизнь-то налаживается!", "Кто сказал «хватит»?!"], ["Завтра точно брошу.", "Ик… А закуска где?"]]

var game: Node                 # Game3D
var rules: Rules3D
var current := -1
var activity := ""
var mode := "bed"              # bed | schedule | detour | react | chase | asleep
var suspicion := 0.0
var suspicious_until := 0.0
var on_ladder := false
var thought := ""             # облачко-мысль: куда и зачем пойдёт (рисует Overlay3D)
var goal := Vector3.INF        # куда идёт — метка на полу
var _use_timer := -1.0
var _use_id := ""
var _seq: Array = []
var _seq_t := 0.0
var _seq_next := Callable()
var _detour := {}
var _look_t := 6.0
var _look_back := 0.0
var _kick_t := 6.0
var _hic_t := 12.0
var _grumble_t := 25.0
var _snore_t := 0.5
var _activity_yaw := 0.0
var _busy_wake := false
var _used_entry := -1          # пункт распорядка, где предмет уже использован (не повторять после реакции)
var _stay_entry := -1          # пункт, для которого идёт отсчёт времени на месте
var _stay_left := 0.0
var _here := false             # дошёл до места текущего дела
var _act_line_entry := -1      # для какого пункта распорядка уже была реплика за делом (ACT_LINES)
var _hand: Node3D              # предмет в руке
var _hand_name := ""
var _hand_cache := {}

func _init() -> void:
	speed = 1.05
	head_h = 2.0
	step_sfx = "step"
	step_vol = 0.35

# ---------------------------------------------------------------- сон на кровати (начало дня)
func lie_on_bed(pos: Vector3, yaw: float) -> void:
	mode = "bed"
	activity = "спит"
	position = pos
	rotation.y = yaw
	target_yaw = yaw
	act("sleep", -1.0, 0.0)
	set_face("sleep")

func _bed_tick(delta: float) -> void:
	_snore_t -= delta
	if _snore_t <= 0.0:
		_snore_t = 3.2
		Settings.sfx(["snore", "snore_2"].pick_random(), 0.55)
		bubble = "Хр-р-р…  z Z z"
		bubble_time = 2.4

## Встать с кровати и сойти на пол рядом.
func _get_off_bed(then: Callable) -> void:
	_busy_wake = true
	act("get_up", -1.0, 0.3)
	set_face("tipsy" if rules.drunk > 0 else "normal")
	bubble = ""
	var tw := create_tween()
	tw.tween_interval(1.0)
	var floor_p: Vector3 = game.lane_point(9.35, 1)
	tw.tween_property(self, "position", floor_p, 0.6).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		_busy_wake = false
		release()
		then.call())

func wake_up() -> void:
	act("oath", 3.4)
	set_face("happy")
	var oath: Array = Rules3D.OATHS[clampi(game.day_n - 1, 0, 6)]
	say(oath[0], 3.0)
	get_tree().create_timer(3.6, false).timeout.connect(func():
		if mode == "schedule" and current == 1:
			set_face("normal")
			say(oath[1], 2.6))

# ---------------------------------------------------------------- расписание
func update_schedule(hour: float, delta: float) -> void:
	if mode == "asleep" or mode == "chase" or _busy_wake:
		return
	if mode == "bed":
		_bed_tick(delta)
		if hour >= WAKE_HOUR:
			current = 1
			mode = "schedule"
			_get_off_bed(_go_to_current)
		return
	if mode == "react":
		_seq_t -= delta
		if _seq_t <= 0.0:
			_next_step()
		return
	if _use_timer > 0.0:
		_use_timer -= delta
		if _use_timer <= 0.0:
			var id := _use_id
			_use_id = ""
			if mode == "detour":
				_finish_detour()
			else:
				_used_entry = current
				rules.neighbor_use(id)
	_drunk_behaviour(delta)
	if mode == "detour" or is_walking() or not _here:
		return
	_stay_left -= delta
	_act_line()
	if _stay_left < 5.0 and thought == "" and _use_timer <= 0.0 and bubble == "":
		_think(_next_index())
	if _stay_left <= 0.0 and _use_timer <= 0.0:
		next_task()

## Реплика за делом (ACT_LINES): раз за приход, когда побыл на месте, ничем не занят, облачко свободно
## и герой не говорит (сосед иначе оборвал бы его).
func _act_line() -> void:
	if _act_line_entry == current or current < 0 or not ACT_LINES.has(activity):
		return
	if _use_timer > 0.0 or bubble != "" or _stay_left < 2.5:
		return
	if float(PLAN[current][6]) - _stay_left < ACT_LINE_AFTER:
		return
	if partner and partner.is_speaking():
		return
	_act_line_entry = current
	if activity == "играет в приставку" and rules.taken.has("gamepad"):
		return
	if randf() < ACT_LINE_P:
		say(ACT_LINES[activity].pick_random(), 2.6)

## Следующее дело по распорядку (после последнего — по кругу).
func next_task() -> void:
	current = _next_index()
	_used_entry = -1
	_act_line_entry = -1
	_go_to_current()

## Старт с середины дня (отладка): пропустить дела, которые к этому часу уже прошли бы.
func skip_to(hour: float) -> void:
	var t: float = (hour - WAKE_HOUR) * game.SEC_PER_HOUR
	current = 1
	while t > 0.0:
		t -= float(PLAN[current][6]) + 7.0
		if t > 0.0:
			current = current + 1 if current + 1 < PLAN.size() else LOOP_FROM
	mode = "schedule"
	position = game.lane_point(PLAN[current][0], PLAN[current][1])
	release()
	_go_to_current()

func _next_index() -> int:
	return current + 1 if current + 1 < PLAN.size() else LOOP_FROM

func _plan_point(i: int) -> Vector3:
	var e: Array = PLAN[i]
	var p: Vector3 = game.lane_point(e[0], e[1])
	if e.size() > 7:
		p.z = e[7]
	return p

## Подумать о деле i: облачко «Комната: зачем» и метка на полу там, куда пойдёт.
func _think(i: int) -> void:
	var e: Array = PLAN[i]
	if not THOUGHTS.has(e[2]):
		_clear_thought()
		return
	var p := _plan_point(i)
	thought = "%s: %s" % [game.ROOM_NAMES[game.room_at(p)], THOUGHTS.get(e[2], e[2])]
	goal = Vector3(p.x, p.y, game.LANE)

func _clear_thought() -> void:
	thought = ""
	goal = Vector3.INF

func _go_to_current() -> void:
	var e: Array = PLAN[current]
	activity = "идёт: " + e[2]
	_here = false
	release()
	hold_item("")
	_to_floor()
	_think(current)
	var target: Vector3 = _plan_point(current)
	if position.distance_to(target) < 0.05:
		_on_arrived()
	else:
		walk_path(game.plan_path(position, target))

func _resume() -> void:
	if current >= 0:
		_go_to_current()

func _ready() -> void:
	arrived.connect(_on_arrived)

func setup(glb_path: String, who: String) -> void:
	super.setup(glb_path, who)
	_make_game_clip()

## Поза «играет на геймпаде»: клип phone, где левая рука повторяет правую зеркально — обе кисти
## перед грудью (в модели нет отдельной двуручной позы).
func _make_game_clip() -> void:
	if ap == null or ap.has_animation("game") or not ap.has_animation("phone"):
		return
	var a := ap.get_animation("phone").duplicate(true) as Animation
	var by_bone := {}
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			by_bone[a.track_get_path(i).get_concatenated_subnames()] = i
	for bone in by_bone:
		if not (bone as String).begins_with("Left") or (bone as String).begins_with("LeftUpLeg") or bone in ["LeftLeg", "LeftFoot", "LeftToeBase"]:
			continue
		var src_name: String = "Right" + (bone as String).substr(4)
		if not by_bone.has(src_name):
			continue
		var dst: int = by_bone[bone]
		var src: int = by_bone[src_name]
		while a.track_get_key_count(dst) > 0:
			a.track_remove_key(dst, 0)
		for k in a.track_get_key_count(src):
			var q: Quaternion = a.track_get_key_value(src, k)
			a.rotation_track_insert_key(dst, a.track_get_key_time(src, k), Quaternion(q.x, -q.y, -q.z, q.w))
	a.loop_mode = Animation.LOOP_LINEAR
	ap.get_animation_library("").add_animation("game", a)

func _on_arrived() -> void:
	if mode == "chase":
		return
	if mode == "detour":
		activity = _detour.get("title", "")
		_clear_thought()
		face_dir(Vector3(0, 0, -1))
		_use_id = "detour"
		_use_timer = USE_DELAY
		return
	if current < 0 or mode != "schedule":
		return
	var e: Array = PLAN[current]
	_here = true
	_clear_thought()
	if _stay_entry != current:
		_stay_entry = current
		_stay_left = float(e[6])
	activity = e[2]
	_face_activity(e[5])
	set_face(rules.default_face())
	if e[3] != "idle":
		act(e[3])
	if e[2] == "шпаклюет стену" and randf() < 0.6:
		say("Так-с… шпаклёвочка…", 2.2)
	if e[2] == "чинит машину" and randf() < 0.7:
		say(CAR_LOVE.pick_random(), 2.6)
	if e[4] in ["gamepad", "phone"] and not rules.taken.has(e[4]):
		hold_item(HAND[e[4]][0])
	if e[4] != "" and _used_entry != current:
		_use_id = e[4]
		_use_timer = USE_DELAY

## Предмет в правой руке (модель из assets/models/props), "" — убрать. Держит за кость RightHandGrip
## (бутылки, кружка, лампочка — ось кости к горлышку) или RightHandPhone (телефон, геймпад).
func hold_item(n: String) -> void:
	if n == _hand_name:
		return
	_hand_name = n
	if _hand:
		_hand.visible = false
	_hand = null
	if n == "":
		return
	if n == "gamepad":       # геймпад — двумя руками, горизонтально (см. _update_pad)
		if not _hand_cache.has(n):
			_hand_cache[n] = _make_pad()
		_hand = _hand_cache[n]
		_hand.visible = true
		return
	if not _hand_cache.has(n):
		var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var phone := n in ["smartphone", "gamepad"]
		var att := BoneAttachment3D.new()
		att.bone_name = "RightHandPhone" if phone else "RightHandGrip"
		sk.add_child(att)
		var inst := (load(game.PROPS + n + ".glb") as PackedScene).instantiate() as Node3D
		att.add_child(inst)
		inst.scale = Vector3.ONE * (1.6 if phone else 1.25)   # по-мультяшному крупнее, чтобы читалось издалека
		var b: AABB = game.local_bounds(inst)
		if phone:
			# экраном к лицу: длинная сторона — вдоль кости (Y), толщина — по Z
			var sz := b.size
			if sz.y < sz.x and sz.y < sz.z:      # лежит плашмя (тонкий по Y) — поставить «на ребро»
				inst.rotation_degrees.x = 90.0
				if sz.x > sz.z:
					inst.rotation_degrees.z = 90.0
			b = game.local_bounds_xf(inst)
		inst.position -= b.get_center()        # центр предмета — в точке хвата
		if HOLD_SHIFT.has(n):                  # кружка, банка: хват ближе к донышку
			inst.position += HOLD_SHIFT[n]
		_hand_cache[n] = att
	_hand = _hand_cache[n]
	_hand.visible = true

## Геймпад: отдельный узел у соседа (не на кости одной руки): длинной стороной поперёк тела,
## кнопками вверх; каждый кадр ставится между ладонями и наклоняется к лицу.
func _make_pad() -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	var inst := (load(game.PROPS + "gamepad.glb") as PackedScene).instantiate() as Node3D
	holder.add_child(inst)
	inst.scale = Vector3.ONE * 1.5
	var b: AABB = game.local_bounds(inst)
	if b.size.z > b.size.x:            # длинная сторона — по X (поперёк тела)
		inst.rotation_degrees.y = 90.0
	b = game.local_bounds_xf(inst)
	inst.position -= b.get_center()
	return holder

func _update_pad() -> void:
	if _hand_name != "gamepad" or _hand == null:
		return
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var l := sk.to_global(sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin)
	var r := sk.to_global(sk.get_bone_global_pose(sk.find_bone("RightHand")).origin)
	var fwd := global_transform.basis.z.normalized()
	_hand.global_position = (l + r) * 0.5 + fwd * 0.05 + Vector3(0, 0.06, 0)
	_hand.global_basis = Basis(Vector3.UP, rotation.y) * Basis(Vector3.RIGHT, deg_to_rad(-40.0))

func _process(delta: float) -> void:
	super._process(delta)
	_update_pad()

## Модель предмета для «использует» с учётом подмены.
func hand_for(use_id: String) -> String:
	if not HAND.has(use_id):
		return ""
	var swapped: bool = rules.swapped.has("fridge" if use_id == "detour" else use_id)
	return HAND[use_id][1 if swapped else 0]

func _face_activity(where: String) -> void:
	_activity_yaw = {"back": PI, "tv": PI * 0.72, "front": 0.0, "left": -PI / 2, "right": PI / 2}[where]
	target_yaw = _activity_yaw

# ---------------------------------------------------------------- отлучки и реакции
func detour(x: float, fl: int, title: String, use_id: String) -> void:
	mode = "detour"
	_use_timer = -1.0
	_detour = {"title": title, "use": use_id}
	activity = "идёт: " + title
	release()
	_to_floor()
	var target: Vector3 = game.lane_point(x, fl)
	thought = "%s: %s" % [game.ROOM_NAMES[game.room_at(target)], _detour["title"].trim_prefix("идёт ")]
	goal = target
	if position.distance_to(target) < 0.05:
		_on_arrived()
	else:
		walk_path(game.plan_path(position, target))

func _finish_detour() -> void:
	var id: String = _detour.get("use", "")
	mode = "schedule"
	_detour = {}
	rules.neighbor_use(id)
	if mode == "schedule":
		_resume()

## Цепочка реакции: шаги {face, clip, t, line, sfx, shake, fall, down}. Потом next или возврат к делам.
func react_seq(steps: Array, next := Callable()) -> void:
	mode = "react"
	stop()
	_clear_thought()
	_use_timer = -1.0
	_seq = steps.duplicate()
	_seq_next = next
	_next_step()

func _next_step() -> void:
	if _seq.is_empty():
		mode = "schedule"
		hold_item("")
		release()
		_to_floor()
		set_face(rules.default_face())
		var cb := _seq_next
		_seq_next = Callable()
		if cb.is_valid():
			cb.call()
		else:
			_resume()
		return
	var s: Dictionary = _seq.pop_front()
	_seq_t = s.get("t", 1.5)
	if not on_ladder:   # эмоции — лицом к игроку (чуть вполоборота)
		target_yaw = 0.35 if sin(rotation.y) >= 0.0 else -0.35
	set_face(s.get("face", rules.default_face()))
	act(s.get("clip", "idle"), -1.0, 0.15)
	if s.has("item"):
		hold_item(s["item"])
	if s.has("line"):
		var dur := say(s["line"], _seq_t + 0.4)
		_seq_t = maxf(_seq_t, dur + 0.2)
	if s.has("sfx"):
		Settings.sfx(s["sfx"], 0.8)
	if s.has("shake"):
		game.shake(s["shake"])
	if s.get("climb", false):
		climb_ladder(maxf(0.2, _seq_t - 0.05))
	if s.get("fall", false):
		_to_floor(0.45)
	elif s.get("down", false) and on_ladder:     # слезает со стремянки шагами, потом — клип шага
		var c: String = s.get("clip", "idle")
		act("walk", -1.0, 0.1)
		_to_floor(0.45)
		get_tree().create_timer(0.45, false).timeout.connect(func():
			if mode == "react" and clip() == "walk":
				act(c, -1.0, 0.15))

## Стремянка с лампочкой — в прихожей, под люстрой у входной двери.
const LADDER_STAND := 6.0                       # где стоит перед стремянкой (x на дорожке)
const LADDER_TOP := Vector3(6.25, 0.62, -2.05)  # куда встаёт на стремянке

## Влезть на стремянку: лицом к ней, шагами (клип walk в шаге «climb»), наверху — вполоборота к зрителю.
func climb_ladder(t := 0.55) -> void:
	if on_ladder:
		return
	on_ladder = true
	face_dir(LADDER_TOP - position)
	var tw := create_tween()
	tw.tween_property(self, "position", LADDER_TOP, t).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		if on_ladder:
			target_yaw = 0.35)

func _to_floor(t := 0.3) -> void:
	if not on_ladder:
		return
	on_ladder = false
	var tw := create_tween()
	tw.tween_property(self, "position", game.lane_point(LADDER_STAND, 0), t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# ---------------------------------------------------------------- поимка
## Поймал: подбежать к герою. 1-й и 2-й раз — схватить за шею, потрясти и отшвырнуть; 3-й — «пол жизни
## кикбоксингом занимался» и вертушка в голову. Встаёт ровно на расстоянии контакта (Game3D.catch_distance:
## руки — у шеи героя, стопа — у его головы). on_done(final) — сцена кончилась (герою — исчезнуть / итоги).
const FACEPLANT_HIT := 0.6      # удар лицом в салат — доля клипа faceplant (как в rig_neighbor.py)
const KICK_HIT := 0.55          # удар вертушки — доля клипа spin_kick

func catch_hero(hero_pos: Vector3, line: String, on_done: Callable) -> void:
	mode = "chase"
	_clear_thought()
	_use_timer = -1.0
	_seq.clear()
	_to_floor()
	release()
	hold_item("")
	set_face("yell")
	say(line, 2.2)
	Settings.sfx("alert", 0.8)
	var final: bool = rules.catches >= 3
	var h := partner as Hero3D
	var side := signf(hero_pos.x - position.x)
	if side == 0.0:
		side = 1.0
	var same_floor := absf(hero_pos.y - position.y) < 0.5
	var target := Vector3(hero_pos.x - side * game.catch_distance("kick" if final else "grab"), hero_pos.y, game.LANE)
	if same_floor and position.distance_to(target) > 0.05:
		speed_mul = 1.9
		walk_path(game.plan_path(position, target))
		await arrived
	if same_floor:
		position = target              # точно на расстоянии контакта
	face_x(hero_pos.x)
	rotation.y = target_yaw
	if same_floor and h:
		h.face_x(position.x)
		h.rotation.y = h.target_yaw
		if final:
			await _kick_hero(h)
		else:
			await _shake_hero(h)
	else:                              # с другого этажа (редко) — по-старому, без контакта
		act("catch", -1.0, 0.1)
		await get_tree().create_timer(0.55, false).timeout
		Settings.sfx("punch", 1.0)
		game.shake(0.4)
	on_done.call(final)
	if final:
		return
	game.finale_hero = false
	await get_tree().create_timer(0.8, false).timeout
	set_face("angry")
	act("angry", -1.0)
	await get_tree().create_timer(1.2, false).timeout
	if mode == "chase":
		mode = "schedule"
		release()
		set_face(rules.default_face())
		_resume()

## За шею: схватил, приподнял, трясёт и орёт; герой хрипит и болтает ногами; потом — отшвырнул.
func _shake_hero(h: Hero3D) -> void:
	game.finale_hero = true            # крупно: видно, как держит за шею
	act("grab_shake", -1.0, 0.12)
	h.choke()                          # клипы одной длины, стартуют в один кадр — тряска в такт
	Settings.sfx("grab", 0.9)
	game.shake(0.25)
	set_face("yell")
	say(Rules3D.GRAB_LINES.pick_random(), 2.4)
	await get_tree().create_timer(0.8, false).timeout
	h.say(Rules3D.CHOKE_LINES.pick_random(), 1.6)
	await get_tree().create_timer(1.9, false).timeout
	act("catch", -1.0, 0.1)           # бросок
	await get_tree().create_timer(0.25, false).timeout
	Settings.sfx("whoosh", 0.8)
	h.thrown_away()
	await get_tree().create_timer(0.45, false).timeout
	Settings.sfx("thud", 0.7)
	game.shake(0.3)
	await get_tree().create_timer(0.7, false).timeout

## Вертушка: стойка и «пол жизни спортом…», герой просит пощады — оборот, нога в голову, нокаут.
func _kick_hero(h: Hero3D) -> void:
	game.finale_hero = true            # камера крупно на героя (сосед рядом, тоже в кадре)
	act("fight_stance", -1.0, 0.15)
	set_face("angry")
	var d := say(Rules3D.KICK_BOAST, 3.4)
	await get_tree().create_timer(maxf(2.8, d + 0.2), false).timeout
	h.say(Rules3D.KICK_PLEAD, 1.4)
	await get_tree().create_timer(0.9, false).timeout
	act("spin_kick", -1.0, 0.06)
	Settings.sfx("whoosh", 1.0)
	var hit := ap.current_animation_length * KICK_HIT
	await get_tree().create_timer(hit, false).timeout
	Settings.sfx("punch", 1.0)
	Settings.sfx("thud", 0.6)
	game.shake(0.9)
	game.slowmo(0.35, 0.45)
	h.knock_out()
	await get_tree().create_timer(maxf(0.3, ap.current_animation_length - hit), false).timeout
	act("fight_stance", -1.0, 0.2)
	say(Rules3D.KO_LINES.pick_random(), 2.2)
	await get_tree().create_timer(2.4, false).timeout

# ---------------------------------------------------------------- финал
func finale(salad: bool) -> void:
	mode = "asleep"
	stop()
	_clear_thought()
	_use_timer = -1.0
	_seq.clear()
	_to_floor()
	release()
	hold_item("")
	if salad:
		activity = "идёт к салату…"
		set_face("wasted")
		say("Салатик… моя подушечка…", 2.5)
		speed_mul = 0.6
		var behind: float = game.SALAD_SPOT.z
		var pts: Array[Vector3] = []
		pts.assign(game.plan_path(position, game.lane_point(7.42, 0)))
		pts.append(Vector3(7.42, 0.0, behind))
		pts.append(Vector3(game.SALAD_SPOT.x, 0.0, behind))
		walk_path(pts)
		await arrived
		target_yaw = 0.0
		await get_tree().create_timer(0.5, false).timeout
		rotation.y = 0.0
		say("Я… ик… не пью…", 2.5)
		await get_tree().create_timer(1.8, false).timeout
		# лицом в салат: клип faceplant (ноги на полу, сгибается в поясе); куда сдвинуть, чтобы лицо попало
		# в миску, — по кости головы в момент удара; удар — замедление, брызги салата, «ПЛЮХ!»
		var fit: Array = game.fit_fall_to_salad(self)
		var t: float = fit[0]
		hold = true
		_clip = "faceplant"
		ap.play("faceplant", 0.2)
		create_tween().tween_property(self, "position", position + fit[1], t * 0.85).set_trans(Tween.TRANS_SINE)
		await get_tree().create_timer(maxf(0.0, t - 0.28), false).timeout
		game.slowmo(0.3, 0.6)
		await get_tree().create_timer(0.28, false).timeout
		game.salad_splash(self)
		set_face("sleep")
		activity = "спит лицом в салате"
		await get_tree().create_timer(maxf(0.2, ap.current_animation_length - t), false).timeout
		act("faceplant_sleep", -1.0, 0.4)
		finale_done.emit()
	else:
		activity = "уснул где стоял"
		set_face("wasted")
		say("Я… ик… не пью…", 2.5)
		await get_tree().create_timer(2.0, false).timeout
		act("fall_back", -1.0, 0.1)
		Settings.sfx("thud", 0.9)
		game.shake(0.4)
		await get_tree().create_timer(1.3, false).timeout
		act("sleep", -1.0, 0.4)
		set_face("sleep")
		activity = "спит на полу"
		finale_done.emit()
	while is_inside_tree():
		Settings.sfx(["snore", "snore_2"].pick_random(), 0.5)
		if not (partner and partner.is_speaking()):     # храп — не поверх реплик героя
			bubble = "Хр-р-р…  z Z z"
			bubble_time = 2.4
		await get_tree().create_timer(3.2, false).timeout

# ---------------------------------------------------------------- пьянство
func _drunk_behaviour(delta: float) -> void:
	var st: int = rules.stage()
	walk_clip = "walk_drunk" if st >= 2 else "walk"
	speed_mul = [1.0, 0.97, 0.9, 0.85, 0.7, 0.7][st] if mode != "chase" else speed_mul
	if is_walking() or mode != "schedule":
		return
	# «Тренер»: время от времени отрабатывает лоу-кики прямо посреди дела
	if st == 3 and not on_ladder:
		_kick_t -= delta
		if _kick_t <= 0.0:
			_kick_t = randf_range(9.0, 14.0)
			var prev := clip()
			var was_hold := hold
			act("kick", -1.0)
			set_face("angry")
			say(["Так, смотри сюда! Лоу-кик!", "Руки держим, руки!", "Работаем, работаем!", "Кийя!"].pick_random(), 2.5)
			get_tree().create_timer(2.6, false).timeout.connect(func():
				if clip() == "kick" and mode == "schedule":
					set_face(rules.default_face())
					if was_hold and prev != "kick":
						act(prev)
					else:
						release())
	if st >= 1:
		_hic_t -= delta
		if _hic_t <= 0.0:
			_hic_t = randf_range(9.0, 16.0)
			Settings.sfx("hiccup", 0.6, randf_range(0.85, 1.05))
			if st >= 2 and randf() < 0.5 and bubble == "":
				say(DRUNK_LINES[mini(3, st - 1)].pick_random(), 2.5)
	elif bubble == "":
		_grumble_t -= delta
		if _grumble_t <= 0.0:
			_grumble_t = randf_range(25.0, 40.0)
			say(GRUMBLE.pick_random(), 2.5)

## Пока бушует (вся цепочка реакции) — «говорит»: герой ждёт своей очереди.
func is_speaking() -> bool:
	return super.is_speaking() or mode == "react"

func is_kicking() -> bool:
	return clip() == "kick" and not is_walking()

# ---------------------------------------------------------------- обзор
func view_range(hour: float) -> float:
	if mode in ["asleep", "bed"] or clip() in ["lie_back", "sleep", "fall_back", "get_up"]:
		return 0.0
	var r: float = SOBER_RANGE * [1.0, 0.9, 0.75, 0.6, 0.38, 0.0][rules.stage()]
	if activity == "сидит в чат-рулетке":
		r *= 0.35
	elif activity == "играет в приставку":
		r *= 0.45
	if hour < suspicious_until:
		r *= 1.3
	return r

## Видит ли героя прямо сейчас.
func sees(h: Hero3D, hour: float) -> bool:
	if h.in_hiding or h.in_portal or in_portal or mode == "chase":
		return false
	if game.on_stairs(h.position) or game.floor_of(h.position) != game.floor_of(position):
		return false
	if game.room_at(h.position) != game.room_at(position):
		return false
	var dx := h.position.x - position.x
	var s := sin(rotation.y)
	var c := cos(rotation.y)
	var r := view_range(hour)
	if absf(dx) < 0.45:
		return r > 0.0
	if c < -0.6:            # стоит лицом к стене — видит только краем глаза рядом
		return absf(dx) <= r * 0.35
	if c > 0.6:             # лицом к игроку — по бокам видит, но хуже
		return absf(dx) <= r * 0.7
	if absf(s) > 0.3 and (dx > 0.0) != (s > 0.0):
		return false
	return absf(dx) <= r

## Иногда оглядывается по сторонам, потом возвращается к делу.
func look_around(delta: float) -> void:
	if is_walking() or mode != "schedule" or on_ladder or clip() == "kick":
		return
	if _look_back > 0.0:
		_look_back -= delta
		if _look_back <= 0.0:
			target_yaw = _activity_yaw
		return
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = randf_range(5.0, 9.0)
		_look_back = randf_range(1.4, 2.4)
		target_yaw = PI / 2 if randf() < 0.5 else -PI / 2
