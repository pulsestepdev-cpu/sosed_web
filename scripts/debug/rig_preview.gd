extends Node2D
## Проверка сборки персонажей из частей: эталон сбоку, поза покоя и ходьба для каждого.

const FLOOR_Y := 940.0
const SCALE := 0.62

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

	var x := 60.0
	for who in ["hero", "neighbor"]:
		var ref := Sprite2D.new()
		ref.texture = load("res://assets/characters/%s/%s_side.png" % [who, who])
		ref.centered = false
		ref.scale = Vector2.ONE * SCALE
		ref.position = Vector2(x, FLOOR_Y - ref.texture.get_size().y * SCALE + 6)
		add_child(ref)
		x += 260.0
		for a in ["idle", "walk"]:
			var rig := CutoutRig.new()
			rig.character = who
			rig.anim = a
			rig.scale = Vector2.ONE * SCALE
			rig.position = Vector2(x + 90, FLOOR_Y)
			add_child(rig)
			x += 280.0
		x += 40.0
