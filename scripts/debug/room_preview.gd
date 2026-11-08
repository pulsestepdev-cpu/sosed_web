extends Node2D
## Персонажи в комнате: проверка масштаба и того, как они сочетаются с фоном.

const ROOM := "res://assets/rooms/room_kitchen.png"
const CHAR_SCALE := 0.72

func _ready() -> void:
	var tex: Texture2D = load(ROOM)
	var k := 1080.0 / tex.get_size().y
	var room := Sprite2D.new()
	room.texture = tex
	room.centered = false
	room.scale = Vector2.ONE * k
	room.position.x = (1920.0 - tex.get_size().x * k) / 2.0
	add_child(room)
	var floor_y := 1000.0

	var hero := CutoutRig.new()
	hero.character = "hero"
	hero.anim = "walk"
	hero.walk_speed = 0.7
	hero.scale = Vector2.ONE * CHAR_SCALE
	hero.position = Vector2(room.position.x + 470, floor_y)
	add_child(hero)

	var nb := CutoutRig.new()
	nb.character = "neighbor"
	nb.face = "normal"
	nb.scale = Vector2.ONE * CHAR_SCALE
	nb.position = Vector2(room.position.x + 1030, floor_y)
	add_child(nb)
