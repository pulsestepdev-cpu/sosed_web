extends Node2D
## Проверка сборки персонажа из частей: эталонный вид сбоку, поза покоя и ходьба.

const FLOOR_Y := 940.0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("e9d8b4")
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var fl := ColorRect.new()
	fl.color = Color("a0784f")
	fl.position = Vector2(0, FLOOR_Y)
	fl.size = Vector2(1920, 140)
	add_child(fl)

	var ref := Sprite2D.new()
	ref.texture = load("res://assets/characters/neighbor/neighbor_side.png")
	ref.centered = false
	ref.position = Vector2(140, FLOOR_Y - ref.texture.get_size().y + 8)
	add_child(ref)

	for i in 2:
		var rig := CutoutRig.new()
		rig.anim = ["idle", "walk"][i]
		rig.position = Vector2(860 + i * 620, FLOOR_Y)
		add_child(rig)
