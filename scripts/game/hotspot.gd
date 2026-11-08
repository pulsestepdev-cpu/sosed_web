class_name Hotspot
extends Node2D
## Интерактивное место в квартире: тайник, предмет для подмены, укрытие.
## Рисует маркер и подсветку при наведении; логику решают правила уровня.

var id := ""
var title := ""
var kind := ""              # stash | swap | hide | take | place
var rect := Rect2()         # в мировых координатах
var walk := Vector2.ZERO    # куда встаёт герой
var hovered := false
var done := false           # подмена/пакость уже сделана — маркер-галочка
var active := true          # можно взаимодействовать (тайник не пуст и т.п.)
var _t := 0.0
var ui := 1.0               # масштаб маркера (больше при виде всей квартиры)

func _init() -> void:
	z_index = 150

func contains(p: Vector2) -> bool:
	return active and rect.has_point(p)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	if not active and not done:
		return
	var top := Vector2(rect.get_center().x, rect.position.y - 26.0 * ui)
	var col := Color("ffe08a") if kind != "hide" else Color("9fe3ff")
	if done:
		draw_circle(top, 22.0 * ui, Color(0.15, 0.55, 0.2, 0.9))
		draw_polyline(PackedVector2Array([top + Vector2(-10, 0) * ui, top + Vector2(-2, 9) * ui, top + Vector2(12, -9) * ui]), Color.WHITE, 6.0 * ui)
		if not active:
			return
	if hovered:
		draw_rect(rect, Color(col, 0.18), true)
		draw_rect(rect, col, false, 6.0 * ui)
	elif not done:
		var r := (13.0 + sin(_t * 4.0) * 3.0) * ui
		draw_circle(top, r + 5.0 * ui, Color(0, 0, 0, 0.35))
		draw_circle(top, r, Color(col, 0.95))
