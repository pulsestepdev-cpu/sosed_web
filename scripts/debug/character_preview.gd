extends Node2D
## Просмотр вырезанных персонажей на светлом фоне (проверка краёв).

const VIEWS := [
	"res://assets/characters/neighbor/neighbor_front.png",
	"res://assets/characters/neighbor/neighbor_side.png",
	"res://assets/characters/neighbor/neighbor_three_quarter.png",
]

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("e9d8b4")
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var x := 360.0
	for path in VIEWS:
		var s := Sprite2D.new()
		s.texture = load(path)
		s.position = Vector2(x, 560)
		add_child(s)
		x += 600.0
