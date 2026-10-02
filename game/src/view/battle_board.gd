class_name BattleBoard
extends Control
## Поле боя на экране телевизора: 4 полосы × 2 ряда, шкалы Плёнки (сверху) и Сигнала (снизу),
## подсветка «В КАДРЕ», пунктир следующего взгляда, прогноз по каждой полосе.
## Рисуется в полном разрешении; карты — дочерние CardPlate. Базовый размер 1100×825 (4:3).
##
## Сам ничего не решает: BattleScreen говорит sync(b) — и поле перерисовывается по состоянию боя.

signal cell_clicked(row: String, lane: int)
signal cell_hovered(row: String, lane: int)

const BASE := Vector2(1100, 825)
const FILM_Y := 18.0
const TAPE_Y := 118.0
const ROW_H := 222.0
const MID_Y := 344.0
const YOU_Y := 430.0
const SIG_Y := 668.0
const PLATE := Vector2(236, 214)
## Твой вкладыш — горизонтальный: другая форма, чем у кадров плёнки.
const INSERT := Vector2(256, 180)

const LIT := Color(0.55, 0.78, 1.0, 0.17)
const WARM := Color(1.0, 0.78, 0.45, 0.05)
const FRAME := Color("bfe0ff")
const PLAN := Color("e8f2ff")
const GOOD := Color("8fe3ff")
const BAD := Color("ff7a66")
const MUTED := Color("9a958a")

var b: Battle
## Отображаемые полосы взглядов (дробные — для плавного переезда).
var gaze_disp: Array = []
## Подсветка клеток, куда можно положить выбранное (row → [lanes]).
var targets := {}
var forecast := {}
var show_forecast := true
var plates := {}           # uid → CardPlate
var sketch_plates: Array = [null, null, null, null]


func _ready() -> void:
	custom_minimum_size = BASE
	size = BASE
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false


func lane_x(l: int) -> float:
	return (size.x / Battle.LANES) * (l + 0.5)


func cell_rect(row: String, l: int) -> Rect2:
	if row == "you":
		return Rect2(Vector2(lane_x(l) - INSERT.x * 0.5, YOU_Y + (ROW_H - INSERT.y) * 0.5 - 6), INSERT)
	return Rect2(Vector2(lane_x(l) - PLATE.x * 0.5, TAPE_Y), PLATE)


## Перестроить всё по состоянию боя.
func sync(battle: Battle) -> void:
	b = battle
	var alive := {}
	for row in ["you", "tape"]:
		var arr: Array = b.you if row == "you" else b.tape
		for l in Battle.LANES:
			var c = arr[l]
			if c == null:
				continue
			alive[c.uid] = true
			var p: CardPlate = plates.get(c.uid)
			if p == null:
				p = CardPlate.new()
				p.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(p)
				plates[c.uid] = p
			p.setup(c, row)
			var cr := cell_rect(row, l)
			p.size = cr.size
			p.position = cr.position
			p.modulate = Color.WHITE
			p.scale = Vector2.ONE
	for uid in plates.keys():
		if not alive.has(uid):
			plates[uid].queue_free()
			plates.erase(uid)
	for l in Battle.LANES:
		var s = b.sketches[l]
		if s == null:
			if sketch_plates[l]:
				sketch_plates[l].queue_free()
				sketch_plates[l] = null
			continue
		if sketch_plates[l] == null:
			var sp := CardPlate.new()
			sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(sp)
			sketch_plates[l] = sp
		var sk: Dictionary = CardDB.make_creature(s.id, int(b.cfg.tape_hp), int(b.cfg.tape_atk))
		sk.hidden = s.hidden
		sketch_plates[l].setup(sk, "sketch")
		sketch_plates[l].size = PLATE
		sketch_plates[l].position = cell_rect("tape", l).position
	if gaze_disp.size() != b.gazes.size():
		gaze_disp = []
		for g in b.gazes:
			gaze_disp.append(float(g.lane))
	else:
		for i in b.gazes.size():
			gaze_disp[i] = float(b.gazes[i].lane)
	refresh_forecast()


func refresh_forecast() -> void:
	if b == null or b.over:
		forecast = {}
	else:
		forecast = b.compute_scene()
	for uid in plates:
		plates[uid].doomed = false
	for sp in sketch_plates:
		if sp:
			sp.doomed = false
	if show_forecast and not forecast.is_empty():
		for l in forecast.die_you:
			if b.you[l] != null and plates.has(b.you[l].uid) and not _survives_toon(b.you[l]):
				plates[b.you[l].uid].doomed = true
		for l in forecast.die_tape:
			if b.tape[l] != null and plates.has(b.tape[l].uid):
				plates[b.tape[l].uid].doomed = not _survives_toon(b.tape[l])
			elif sketch_plates[l]:
				sketch_plates[l].doomed = true
	for uid in plates:
		plates[uid].queue_redraw()
	for sp in sketch_plates:
		if sp:
			sp.queue_redraw()
	queue_redraw()


func _survives_toon(c: Dictionary) -> bool:
	return c.badges.has("toon") and not c.get("flat", false)


func plate_for(uid: int) -> CardPlate:
	return plates.get(uid)


# ---------------------------------------------------------------- рисование

func _draw() -> void:
	if b == null:
		return
	var lw := size.x / Battle.LANES
	# фон экрана: тёмная «опушка»
	draw_rect(Rect2(Vector2.ZERO, size), Color("101418"))
	draw_rect(Rect2(Vector2(0, TAPE_Y - 8), Vector2(size.x, SIG_Y - TAPE_Y + 2)), Color("161b1f"))
	for l in Battle.LANES:
		var lane_r := Rect2(Vector2(lw * l + 6, TAPE_Y - 10), Vector2(lw - 12, YOU_Y + ROW_H - TAPE_Y + 18))
		draw_rect(lane_r, LIT if b.lit(l) else WARM)
		if l > 0:
			draw_line(Vector2(lw * l, TAPE_Y), Vector2(lw * l, YOU_Y + ROW_H), Color(1, 1, 1, 0.06), 2.0)
		var tag := ""
		if int(b.cfg.blocked_lane) == l:
			tag = "ВЫРЕЗАНО ЦЕНЗУРОЙ"
		elif b.lit(l):
			tag = "СЧИТАЕТСЯ" if b.cfg.invert else "В КАДРЕ"
			if b.planned(l) and not b.cfg.invert:
				tag += " И ДАЛЬШЕ"
		elif b.planned(l):
			tag = "ДАЛЬШЕ"
		if tag != "":
			var col := BAD if int(b.cfg.blocked_lane) == l else (FRAME if b.lit(l) else PLAN)
			_tag(Vector2(lane_r.position.x, lane_r.position.y - 2), lw - 12, tag, col, not b.lit(l))
	# видоискатели на текущих взглядах
	for i in gaze_disp.size():
		var x: float = lw * gaze_disp[i] + 6
		_viewfinder(Rect2(Vector2(x, TAPE_Y - 10), Vector2(lw - 12, YOU_Y + ROW_H - TAPE_Y + 18)),
			FRAME if not b.cfg.invert else MUTED)
	# пунктир следующего взгляда
	for i in b.gazes.size():
		var g: Dictionary = b.gazes[i]
		var pr := Rect2(Vector2(lw * g.plan + 16, TAPE_Y), Vector2(lw - 32, YOU_Y + ROW_H - TAPE_Y))
		_dashed(pr, PLAN, 3.0, 12.0)
		_eye(Vector2(pr.end.x - 26, pr.position.y + 22 + i * 30), PLAN)
		if g.by != "":
			_by_label(g, pr)
	# клетки, куда можно положить
	for row in targets:
		for l in targets[row]:
			var cr := cell_rect(row, l).grow(4)
			draw_rect(cr, Color(0.5, 1.0, 0.6, 0.12))
			draw_rect(cr, Color("8cff9e"), false, 3.0)
	_draw_film_gauge()
	_draw_signal_gauge()
	_draw_forecast()


func _tag(p: Vector2, w: float, text: String, col: Color, dotted := false) -> void:
	var f := UiKit.FONT_BOLD
	var r := Rect2(p + Vector2(0, -28), Vector2(w, 28))
	draw_rect(r, Color(0, 0, 0, 0.6))
	if dotted:
		_dashed(r.grow(-2), col, 2.0, 6.0)
	draw_string(f, p + Vector2(0, -5), text, HORIZONTAL_ALIGNMENT_CENTER, w, 24, col)


func _viewfinder(r: Rect2, col: Color) -> void:
	var arm := 34.0
	var w := 5.0
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x <= r.position.x + 1 else -1.0
		var sy := 1.0 if c.y <= r.position.y + 1 else -1.0
		draw_line(c, c + Vector2(arm * sx, 0), col, w)
		draw_line(c, c + Vector2(0, arm * sy), col, w)


func _dashed(r: Rect2, col: Color, w: float, dash: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], col, w, dash)


func _eye(c: Vector2, col: Color) -> void:
	draw_circle(c, 13, Color(0, 0, 0, 0.7))
	var pts := PackedVector2Array()
	for k in 17:
		var a := PI * k / 16.0
		pts.append(c + Vector2(cos(a) * 11, -sin(a) * 6))
	for k in range(16, -1, -1):
		var a := PI * k / 16.0
		pts.append(c + Vector2(cos(a) * 11, sin(a) * 6))
	draw_colored_polygon(pts, col)
	draw_circle(c, 4, Color.BLACK)


func _by_label(g: Dictionary, pr: Rect2) -> void:
	var who := ""
	match String(g.by):
		"knock":
			who = "Стукнули по телевизору"
		"wink":
			who = "Подмигивание"
		"remote":
			who = "Пульт"
		_:
			if String(g.by).begins_with("card:"):
				var uid := int(String(g.by).substr(5))
				for c in b.you:
					if c != null and c.uid == uid:
						who = CardDB.short_name(c)
	if who == "":
		return
	var f := UiKit.FONT_BOLD
	var y := pr.end.y - 8
	draw_rect(Rect2(Vector2(pr.position.x, y - 26), Vector2(pr.size.x, 30)), Color(0.1, 0.2, 0.35, 0.92))
	draw_string(f, Vector2(pr.position.x, y - 4), "↪ сдвинул: " + who, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 22, PLAN)


func _draw_film_gauge() -> void:
	var f := UiKit.FONT_BOLD
	var x0 := 150.0
	draw_string(f, Vector2(x0, FILM_Y + 40), "ПЛЁНКА СЕРИИ", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiKit.BONE)
	var loss: int = forecast.get("film", 0) if show_forecast else 0
	var n := str(maxi(b.film, 0))
	var fn := UiKit.FONT_NUM
	draw_string_outline(fn, Vector2(x0 + 190, FILM_Y + 60), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, 8, Color.BLACK)
	draw_string(fn, Vector2(x0 + 190, FILM_Y + 60), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, Color.WHITE)
	var fx := x0 + 270.0
	for i in b.film_max:
		var r := Rect2(Vector2(fx + i * 46, FILM_Y + 14), Vector2(40, 52))
		var has := i < b.film
		var lose := has and i >= b.film - loss
		draw_rect(r, Color("2a2622"))
		if has:
			draw_rect(r.grow(-5), Color("d9cfb2") if not lose else Color("ffd166"))
			if lose:
				draw_line(r.position + Vector2(6, 6), r.end - Vector2(6, 6), Color.BLACK, 4.0)
		for k in 3:
			draw_rect(Rect2(Vector2(r.position.x + 4 + k * 12, r.position.y - 7), Vector2(6, 5)), Color("2a2622"))
	if loss > 0:
		draw_string(f, Vector2(fx + b.film_max * 46 + 12, FILM_Y + 52), "−%d после PLAY" % loss,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, GOOD)


func _draw_signal_gauge() -> void:
	var f := UiKit.FONT_BOLD
	var x0 := 150.0
	var y := SIG_Y + 10
	draw_string(f, Vector2(x0, y + 44), "ТВОЙ СИГНАЛ", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiKit.BONE)
	var loss: int = forecast.get("signal", 0) if show_forecast else 0
	var n := str(maxi(b.sig, 0))
	var fn := UiKit.FONT_NUM
	draw_string_outline(fn, Vector2(x0 + 190, y + 64), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, 8, Color.BLACK)
	draw_string(fn, Vector2(x0 + 190, y + 64), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, Color.WHITE)
	var fx := x0 + 270.0
	for i in b.sig_max:
		var h := 18.0 + i * 7.0
		var r := Rect2(Vector2(fx + i * 34, y + 62 - h), Vector2(26, h))
		var has := i < b.sig
		var lose := has and i >= b.sig - loss
		draw_rect(r, Color("2a2622"))
		if has:
			draw_rect(r.grow(-3), Color("7fe08a") if not lose else BAD)
	if loss > 0:
		draw_string(f, Vector2(fx + b.sig_max * 34 + 12, y + 52), "−%d после PLAY" % loss, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 30, BAD)


func _draw_forecast() -> void:
	if not show_forecast or forecast.is_empty():
		return
	var f := UiKit.FONT_BOLD
	var lw := size.x / Battle.LANES
	for l in Battle.LANES:
		var lines := []
		if forecast.film_lanes[l] > 0:
			lines.append(["−%d плёнки" % forecast.film_lanes[l], GOOD])
		if forecast.signal_lanes[l] > 0:
			lines.append(["−%d сигнала" % forecast.signal_lanes[l], BAD])
		for s in forecast.strikes:
			if s.lane == l and s.target == "offscreen":
				lines.append(["мимо кадра" if s.side == "you" else "его удар мимо кадра", MUTED])
				break
		var y := MID_Y + 30
		for ln in lines:
			draw_rect(Rect2(Vector2(lw * l + 20, y - 26), Vector2(lw - 40, 32)), Color(0, 0, 0, 0.6))
			draw_string(f, Vector2(lw * l, y - 2), ln[0], HORIZONTAL_ALIGNMENT_CENTER, lw, 28, ln[1])
			y += 36


# ---------------------------------------------------------------- ввод

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var hit := _cell_at(e.position)
		if hit.size() == 2:
			cell_clicked.emit(hit[0], hit[1])
			accept_event()
	elif e is InputEventMouseMotion:
		var hit := _cell_at(e.position)
		if hit.size() == 2:
			cell_hovered.emit(hit[0], hit[1])
		else:
			cell_hovered.emit("", -1)


func _cell_at(p: Vector2) -> Array:
	var l := int(p.x / (size.x / Battle.LANES))
	if l < 0 or l >= Battle.LANES:
		return []
	if p.y >= TAPE_Y and p.y < TAPE_Y + ROW_H:
		return ["tape", l]
	if p.y >= YOU_Y and p.y < YOU_Y + ROW_H:
		return ["you", l]
	if p.y >= MID_Y - 10 and p.y < YOU_Y:
		return ["mid", l]
	return []
