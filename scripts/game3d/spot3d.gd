class_name Spot3D
extends RefCounted
## Интерактивное место в 3D-квартире: тайник, подмена, укрытие, ловушка. Логику решают правила уровня.

var id := ""
var kind := ""            # stash | swap | take | hide | trap
var title := ""
var item := ""
var node: Node3D          # предмет в сцене (может не быть — у ловушек на полу)
var aabb := AABB()        # мировые границы — для клика и подсветки
var floor := 0
var walk := Vector3.ZERO  # где встаёт герой
var active := true
var done := false
var hovered := false

func marker_pos() -> Vector3:
	return Vector3(aabb.get_center().x, aabb.end.y + 0.18, aabb.end.z)
