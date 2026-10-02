class_name TvStage
extends Node
## 3D-часть кадра: комната в низком разрешении с плёночной обработкой и неподвижная камера.
## Ракурсы: «tv» — телевизор почти во весь кадр (бой и передачи), «paper» — газета на ковре,
## «room» — вся комната (заставки). Смена ракурса — склейка: мгновенно, с короткой рябью
## (в «Спокойном режиме» — без ряби).
##
## screen_rect() — где на экране монитора сейчас кинескоп: туда интерфейс кладёт поле боя
## чётким слоем в полном разрешении.

signal cut_done

var view: LowResView
var room: Room
var cam: CameraRig
var _static: ColorRect
var _static_t := 0.0


func _ready() -> void:
	view = LowResView.new()
	add_child(view)
	room = Room.new()
	view.viewport.add_child(room)
	cam = CameraRig.new()
	cam.fov = 52
	view.viewport.add_child(cam)
	# экран телевизора: центр (-0.04, 1.11, -1.569), 0.84 × 0.63 м. С 0.85 м он занимает ~1100×825 из 1920×1080.
	var sc := screen_center()
	cam.add_view("tv", Vector3(sc.x, sc.y - 0.08, sc.z + 0.86), Vector3(sc.x, sc.y - 0.08, sc.z - 1.0))
	# газета: почти сверху, чтобы разворот был прямоугольником на экране
	cam.add_view("paper", Vector3(0.0, 0.86, 1.0), Vector3(0.0, 0.0, 0.94))
	cam.add_view("room", Vector3(0.4, 1.45, 2.6), Vector3(0, 0.7, -1.4))
	cam.set_view("tv", true)
	_static = ColorRect.new()
	_static.color = Color(0.8, 0.85, 0.9, 0.0)
	_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.add_child(_static)


func screen_center() -> Vector3:
	return room.screen.global_position if room.screen.is_inside_tree() else Vector3(-0.04, 1.11, -1.569)


## Склейка на другой ракурс.
func cut_to(view_name: String) -> void:
	cam.set_view(view_name, true)
	if not Settings.calm_camera and Settings.effects > 0.0:
		_static_t = 0.2
		Sfx.play("whoosh", 0.4)
	cut_done.emit()


func _process(delta: float) -> void:
	if _static_t > 0.0:
		_static_t -= delta
		_static.color.a = clampf(_static_t / 0.2, 0.0, 1.0) * 0.55 * (0.6 + randf() * 0.4)
	elif _static.color.a > 0.0:
		_static.color.a = 0.0


## Прямоугольник кинескопа в координатах интерфейса (1920×1080).
func screen_rect() -> Rect2:
	return _project_quad(room.screen, room.screen_size)


## Прямоугольник газеты на ковре в координатах интерфейса.
func paper_rect() -> Rect2:
	return _project_quad(room.paper, room.paper_size)


func _project_quad(s: MeshInstance3D, quad_size: Vector2) -> Rect2:
	var half := quad_size * 0.5
	var pts := []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var wp := s.global_transform * Vector3(c.x * half.x, c.y * half.y, 0.0)
		pts.append(view.to_screen(cam.unproject_position(wp)))
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r
