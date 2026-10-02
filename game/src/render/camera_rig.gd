class_name CameraRig
extends Camera3D
## Камера с именованными ракурсами и плавными переходами.
## В режиме «спокойной камеры» (по умолчанию) нет покачивания, следования за курсором
## и почти нет тряски — только мягкие переходы между ракурсами.

## Ракурсы: имя → [позиция, точка, куда смотреть]
var views := {}
var view_name := ""
## Сила тряски (затухает сама).
var shake := 0.0
## Курсор в координатах -1..1 (для лёгкого параллакса в «живом» режиме).
var pointer := Vector2.ZERO

var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _tpos := Vector3.ZERO
var _tlook := Vector3.ZERO
var _time := 0.0


func add_view(view: String, pos: Vector3, look: Vector3) -> void:
	views[view] = [pos, look]


func set_view(view: String, instant := false) -> void:
	if not views.has(view):
		push_warning("Нет ракурса " + view)
		return
	view_name = view
	_tpos = views[view][0]
	_tlook = views[view][1]
	if instant:
		_pos = _tpos
		_look = _tlook
		_apply(0.0)


func _process(delta: float) -> void:
	_time += delta
	var calm := Settings.calm_camera
	# спокойный режим: переход медленнее и без «пружины»
	var speed := (2.2 if calm else 3.2) * minf(Settings.anim_speed(), 10.0)
	var k := 1.0 - exp(-delta * speed)
	_pos = _pos.lerp(_tpos, k)
	_look = _look.lerp(_tlook, k)
	_apply(delta)


func _apply(delta: float) -> void:
	var p := _pos
	if not Settings.calm_camera:
		p.x += sin(_time * 0.5) * 0.03 + pointer.x * 0.06
		p.y += sin(_time * 0.7) * 0.02 + pointer.y * 0.035
	if shake > 0.0:
		var s := shake * (0.25 if Settings.calm_camera else 1.0)
		p += Vector3(randf_range(-s, s), randf_range(-s, s), 0.0)
		shake = maxf(0.0, shake - delta * 0.6)
	position = p
	if not p.is_equal_approx(_look):
		look_at(_look)
