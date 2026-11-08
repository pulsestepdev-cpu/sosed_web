extends Node2D
## Вся квартира целиком: комнаты в ряд с перегородками. Черновой порядок комнат.

const ROOMS := ["bathroom", "hallway", "kitchen", "living", "balcony"]
const ROOM_H := 1024.0          # высота исходных картинок
const WALL := 36.0              # толщина перегородки, px исходника
const CHAR_SCALE := 0.88 * 1080.0 / 1024.0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("3b2a1e")
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var strip := Node2D.new()
	add_child(strip)
	var x := 0.0
	for r in ROOMS:
		var tex: Texture2D = load("res://assets/rooms/room_%s.png" % r)
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position.x = x
		strip.add_child(s)
		x += tex.get_size().x + WALL
	var total := x - WALL
	var k := 1880.0 / total
	strip.scale = Vector2.ONE * k
	strip.position = Vector2(20, (1080 - ROOM_H * k) / 2.0)

	var floor_y := strip.position.y + 975.0 * k
	var spots := [["hero", 1536 + WALL + 1000, "walk", ""], ["neighbor", (1536 + WALL) * 3 + 520, "idle", "proud"]]
	for sp in spots:
		var rig := CutoutRig.new()
		rig.character = sp[0]
		rig.anim = sp[2]
		rig.face = sp[3]
		rig.scale = Vector2.ONE * 0.88 * k
		rig.position = Vector2(strip.position.x + float(sp[1]) * k, floor_y)
		add_child(rig)
