extends Node2D
## Все эмоции соседа на собранном персонаже.

const FACES := ["proud", "normal", "suspicious", "tipsy", "drunk", "singing", "angry", "sleeping"]
const FLOOR_Y := 1000.0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("e9d8b4")
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	for i in FACES.size():
		var rig := CutoutRig.new()
		rig.character = "neighbor"
		rig.face = FACES[i]
		rig.scale = Vector2.ONE * 0.52
		rig.position = Vector2(130 + (i % 4) * 470, 520 + (i / 4) * 500)
		add_child(rig)
