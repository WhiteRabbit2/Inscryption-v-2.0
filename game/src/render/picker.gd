class_name Picker
extends RefCounted
## Выбор 3D-объектов мышью без физики: у каждого объекта — невидимая коробка-«хитбокс».
## Луч из камеры пересекается с коробками, побеждает ближайшая видимая.

## Список хитбоксов: {node: Node3D, size: Vector3, offset: Vector3, data: Dictionary}
var boxes: Array = []


func add(node: Node3D, size: Vector3, data: Dictionary, offset := Vector3.ZERO) -> void:
	boxes.append({"node": node, "size": size, "offset": offset, "data": data})


func remove_node(node: Node3D) -> void:
	boxes = boxes.filter(func(b): return b.node != node and is_instance_valid(b.node))


func clear() -> void:
	boxes.clear()


## Возвращает {data, point, distance} или пустой словарь.
func pick(camera: Camera3D, vp_pos: Vector2, filter := Callable()) -> Dictionary:
	var origin := camera.project_ray_origin(vp_pos)
	var dir := camera.project_ray_normal(vp_pos)
	var best := {}
	var best_t := INF
	var alive: Array = []
	for b in boxes:
		var node: Node3D = b.node
		if not is_instance_valid(node):
			continue
		alive.append(b)
		if not node.is_visible_in_tree():
			continue
		if filter.is_valid() and not filter.call(b.data):
			continue
		var inv := node.global_transform.affine_inverse()
		var o: Vector3 = inv * origin - b.offset
		var d: Vector3 = inv.basis * dir
		var t := _ray_box(o, d, b.size * 0.5)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"data": b.data, "point": origin + dir * t, "distance": t, "node": node}
	boxes = alive
	return best


## Пересечение луча с коробкой [-h, h]; возвращает параметр t или -1.
static func _ray_box(o: Vector3, d: Vector3, h: Vector3) -> float:
	var tmin := -INF
	var tmax := INF
	for axis in 3:
		var oa := o[axis]
		var da := d[axis]
		if absf(da) < 1e-8:
			if oa < -h[axis] or oa > h[axis]:
				return -1.0
			continue
		var t1 := (-h[axis] - oa) / da
		var t2 := (h[axis] - oa) / da
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	if tmax < 0.0:
		return -1.0
	return tmin if tmin >= 0.0 else tmax
