class_name HostCircle
extends Control
## Кружок с Многоглазым в углу экрана, как у сурдопереводчика в новостях.
## Пока заглушка: тёмный капюшон и 13 глаз, моргают по одному, двигаются только зрачки.
## Облик ещё согласуется с автором — потом здесь будет его рисунок.

const EYES := [
	Vector2(-0.30, -0.18), Vector2(0.0, -0.24), Vector2(0.30, -0.18), Vector2(-0.18, -0.02), Vector2(0.18, -0.02),
	Vector2(-0.40, 0.05), Vector2(0.40, 0.05), Vector2(0.0, 0.08), Vector2(-0.24, 0.18), Vector2(0.24, 0.18),
	Vector2(-0.10, -0.40), Vector2(0.12, -0.40), Vector2(0.0, 0.30),
]

var look := Vector2.ZERO
var _blink := -1
var _t := 0.0
var _next := 1.0


func _process(delta: float) -> void:
	_t += delta
	if _t > _next:
		_t = 0.0
		_blink = -1 if _blink >= 0 else randi() % EYES.size()
		_next = 0.12 if _blink >= 0 else randf_range(0.8, 2.2)
	var m := get_local_mouse_position() - size * 0.5
	look = look.lerp(m.limit_length(200.0) / 200.0, minf(delta * 4.0, 1.0))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var rad := minf(size.x, size.y) * 0.5
	draw_circle(c, rad + 4, Color("bfe0ff"))
	draw_circle(c, rad, Color("0d0f14"))
	# капюшон
	var hood := PackedVector2Array()
	for k in 25:
		var a := PI + PI * k / 24.0
		hood.append(c + Vector2(cos(a) * rad * 0.78, sin(a) * rad * 0.86 + rad * 0.25))
	hood.append(c + Vector2(rad * 0.9, rad))
	hood.append(c + Vector2(-rad * 0.9, rad))
	draw_colored_polygon(hood, Color("1c1d26"))
	# ухмылка
	draw_arc(c + Vector2(0, rad * 0.42), rad * 0.26, 0.25, PI - 0.25, 12, Color("e3dbbd"), 3.0)
	for i in EYES.size():
		var p: Vector2 = c + EYES[i] * rad
		var er := rad * 0.075
		if i == _blink:
			draw_line(p - Vector2(er, 0), p + Vector2(er, 0), Color("e3dbbd"), 2.0)
			continue
		draw_circle(p, er, Color("e3dbbd"))
		draw_circle(p + look * er * 0.45, er * 0.5, Color("111111"))
