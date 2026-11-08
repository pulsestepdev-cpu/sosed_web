extends Node2D
## Просмотр вырезанных персонажей на светлом фоне: проверка краёв и масштаба друг относительно друга.

const VIEWS := [
	"res://assets/characters/hero/hero_front.png",
	"res://assets/characters/hero/hero_side.png",
	"res://assets/characters/hero/hero_sneak.png",
	"res://assets/characters/neighbor/neighbor_side.png",
	"res://assets/characters/neighbor/neighbor_front.png",
]
const FLOOR_Y := 960.0
const SCALE := 0.95

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("e9d8b4")
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var floor_rect := ColorRect.new()
	floor_rect.color = Color("a0784f")
	floor_rect.position = Vector2(0, FLOOR_Y)
	floor_rect.size = Vector2(1920, 1080 - FLOOR_Y)
	add_child(floor_rect)
	var x := 40.0
	for path in VIEWS:
		var tex: Texture2D = load(path)
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.scale = Vector2.ONE * SCALE
		var size := tex.get_size() * SCALE
		s.position = Vector2(x, FLOOR_Y - size.y + 8)
		add_child(s)
		x += size.x + 20.0
