class_name VcrPanel
extends Control
## Видик справа от экрана: табло с ходом, искры лампочками, кассета с отметками перемоток.

const GREEN := Color("5dff7a")
const LAMP_ON := Color("ffd23f")
const LAMP_OFF := Color("3a3424")

var _turn := 1
var _sparks := 0
var _cap := 5
var _carry := 2
var _rewinds := 2
var _phase := 1
var _over := false


func show_state(b: Battle, rewinds: int) -> void:
	_turn = b.turn
	_sparks = b.sparks
	_cap = int(b.cfg.spark_cap)
	_carry = int(b.cfg.carry)
	_rewinds = rewinds
	_phase = b.phase
	_over = b.over
	queue_redraw()


func _draw() -> void:
	var f := UiKit.FONT_BOLD
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("1b1a1a"))
	draw_rect(r, Color("3b3936"), false, 3.0)
	# табло
	var disp := Rect2(Vector2(20, 20), Vector2(size.x - 40, 110))
	draw_rect(disp, Color("071a0c"))
	var state := "■ СТОП" if _over else "II ПАУЗА"
	draw_string(f, disp.position + Vector2(16, 40), state, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, GREEN)
	draw_string(f, disp.position + Vector2(16, 90), "ХОД", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, GREEN)
	draw_string(UiKit.FONT_NUM, disp.position + Vector2(86, 90), str(_turn), HORIZONTAL_ALIGNMENT_LEFT, -1, 42, GREEN)
	if _phase == 2:
		draw_string(f, disp.position + Vector2(150, 90), "НЕГАТИВ", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, GREEN)
	# искры
	draw_string(f, Vector2(20, 180), "ИСКРЫ", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiKit.BONE)
	var big := str(_sparks)
	var fn := UiKit.FONT_NUM
	draw_string_outline(fn, Vector2(size.x - 80, 194), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, 8, Color.BLACK)
	draw_string(fn, Vector2(size.x - 80, 194), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, LAMP_ON)
	var n := maxi(_cap, _sparks)
	for i in n:
		var c := Vector2(40 + i * 56, 236)
		draw_circle(c, 22, Color.BLACK)
		draw_circle(c, 18, LAMP_ON if i < _sparks else LAMP_OFF)
		if i < _sparks:
			draw_circle(c + Vector2(-6, -6), 5, Color(1, 1, 1, 0.6))
	draw_string(f, Vector2(20, 296), "+3 каждый ход, до %d в запас" % _carry, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiKit.ASH)
	# кассета
	var cas := Rect2(Vector2(20, 330), Vector2(size.x - 40, 200))
	draw_rect(cas, Color("2b2724"))
	draw_rect(Rect2(cas.position + Vector2(20, 18), Vector2(cas.size.x - 40, 50)), Color("e8dfc6"))
	draw_string(f, cas.position + Vector2(20, 54), "КРИВАЯ ОПУШКА 1–13", HORIZONTAL_ALIGNMENT_CENTER, cas.size.x - 40, 26,
		Color("2a1d12"))
	for k in 2:
		var c := cas.position + Vector2(cas.size.x * (0.3 + 0.4 * k), 112)
		draw_circle(c, 30, Color("111"))
		draw_circle(c, 12, Color("5a554e"))
	draw_string(f, cas.position + Vector2(0, 180), "ПЕРЕМОТКИ", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UiKit.BONE)
	for k in maxi(_rewinds, 2):
		var mr := Rect2(cas.position + Vector2(160 + k * 46, 154), Vector2(34, 34))
		draw_rect(mr, Color("111"))
		if k < _rewinds:
			draw_rect(mr.grow(-5), Color("ff5a3c"))
