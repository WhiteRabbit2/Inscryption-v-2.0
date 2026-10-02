class_name PaperScreen
extends Control
## Газета «Программа передач» на ковре — карта ночи. Рисуется чётко поверх газеты в 3D-комнате.
## 3 канала (столбцы) × 9 получасов (строки). Уже просмотренное обведено красным фломастером,
## куда можно пойти сейчас — подсвечено маркером. Клик по доступной передаче — сигнал chosen(channel).
## Базовый размер 1290×830; fit(rect) масштабирует под прямоугольник газеты на экране.

signal chosen(channel: int)
signal hovered(cell: Dictionary, at: Vector2)

const BASE := Vector2(1290, 830)
const HEAD_H := 92.0
const TIME_W := 96.0
const ROW_H := 82.0
const INK := Color("1d1a16")
const GREY := Color("6f675a")
const PAPER := Color("d8d0bb")
const MARKER := Color("d4231b")
const HIGHLIGHT := Color(1.0, 0.92, 0.25, 0.55)

## Значки типов передач: 9×9 «штампиков» из BadgeIcons там, где подходят, остальное — свои.
const KIND_ICONS := {
	"episode": [
		"#########",
		"#.#.#.#.#",
		"#########",
		"#.......#",
		"#.......#",
		"#.......#",
		"#########",
		"#.#.#.#.#",
		"#########",
	],
	"raffle": [
		".........",
		"#.......#",
		"##.###.##",
		"#########",
		"####.####",
		"#########",
		"##.###.##",
		"#.......#",
		".........",
	],
	"shop": [
		".#######.",
		"##.....##",
		"#.......#",
		".........",
		"...###...",
		"..#####..",
		".##.#.##.",
		".#######.",
		".........",
	],
	"review": [
		"..####...",
		".#....#..",
		"#......#.",
		"#......#.",
		"#......#.",
		".#....#..",
		"..#####..",
		"......##.",
		".......##",
	],
	"pirate": [
		"..#####..",
		".#######.",
		"#########",
		"##.###.##",
		"#########",
		".#######.",
		"..#.#.#..",
		".........",
		"#.......#",
	],
	"sponsor": [
		"..#...#..",
		"...#.#...",
		"#########",
		"#...#...#",
		"#########",
		".#..#..#.",
		".#..#..#.",
		".#..#..#.",
		".#######.",
	],
}

var run: Run
var _hover := Vector2i(-1, -1)
## Дорисовка обводки последней выбранной передачи (0..1).
var _ink_t := 1.0


func _ready() -> void:
	size = BASE
	mouse_filter = Control.MOUSE_FILTER_STOP


func fit(r: Rect2) -> void:
	var k := minf(r.size.x / BASE.x, r.size.y / BASE.y)
	scale = Vector2(k, k)
	position = r.position + (r.size - BASE * k) * 0.5


func show_run(r: Run) -> void:
	run = r
	queue_redraw()


## Обвести только что выбранную передачу «фломастером» (анимация).
func ink_last() -> void:
	_ink_t = 0.0
	var tw := create_tween()
	tw.tween_property(self, "_ink_t", 1.0, 0.35 / Settings.anim_speed())
	tw.tween_callback(queue_redraw)


func _process(_delta: float) -> void:
	if _ink_t < 1.0:
		queue_redraw()


func col_w() -> float:
	return (BASE.x - TIME_W) / ProgramGrid.CHANNELS


func cell_rect(r: int, ch: int) -> Rect2:
	return Rect2(Vector2(TIME_W + ch * col_w(), HEAD_H + r * ROW_H), Vector2(col_w(), ROW_H))


# ---------------------------------------------------------------- рисование

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, BASE), PAPER)
	if run == null:
		return
	var f := UiKit.FONT_BOLD
	var fb := UiKit.FONT_BODY
	# шапка
	draw_string(UiKit.FONT_TITLE, Vector2(18, 46), "НОЧНАЯ ВОЛНА", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, INK)
	var mast := UiKit.FONT_TITLE.get_string_size("НОЧНАЯ ВОЛНА", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(f, Vector2(18 + mast + 24, 40), "ТЕЛЕПРОГРАММА · НОЧЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, INK)
	draw_string(fb, Vector2(BASE.x - 520, 40), "13-й канал в программе не значится", HORIZONTAL_ALIGNMENT_RIGHT, 500, 22,
		GREY)
	draw_line(Vector2(12, 56), Vector2(BASE.x - 12, 56), INK, 3.0)
	for ch in ProgramGrid.CHANNELS:
		var x := TIME_W + ch * col_w()
		var name: String = run.grid.get("channels", ProgramGrid.CHANNEL_NAMES)[ch]
		draw_string(f, Vector2(x + 12, 84), name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, col_w() - 24, 26, INK)
		if ch > 0:
			draw_line(Vector2(x, 62), Vector2(x, BASE.y - 8), Color(INK, 0.35), 1.5)
	draw_line(Vector2(12, HEAD_H), Vector2(BASE.x - 12, HEAD_H), INK, 2.0)
	var moves: Array = run.available_moves()
	for r in ProgramGrid.ROWS:
		var y := HEAD_H + r * ROW_H
		var past := r < run.row
		var tcol := GREY if past else INK
		draw_string(UiKit.FONT_NUM, Vector2(14, y + 34), ProgramGrid.TIMES[r], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, tcol)
		draw_line(Vector2(12, y + ROW_H), Vector2(BASE.x - 12, y + ROW_H), Color(INK, 0.18), 1.0)
		for ch in ProgramGrid.CHANNELS:
			var c: Dictionary = run.grid.rows[r][ch]
			var cr := cell_rect(r, ch)
			var avail := r == run.row + 1 and moves.has(ch)
			if avail:
				draw_rect(cr.grow(-4), HIGHLIGHT if _hover == Vector2i(r, ch) else Color(HIGHLIGHT, 0.25))
			_draw_cell(c, cr, past and not (r < run.path.size() and run.path[r] == ch))
			if avail:
				_dashed(cr.grow(-6), INK, 2.0, 8.0)
	# обводки фломастером: весь пройденный путь
	for r in run.path.size():
		var t := 1.0 if r < run.path.size() - 1 else _ink_t
		_marker_oval(cell_rect(r, int(run.path[r])), t, r)


func _draw_cell(c: Dictionary, cr: Rect2, faded: bool) -> void:
	var f := UiKit.FONT_BOLD
	var fb := UiKit.FONT_BODY
	var col := Color(INK, 0.35) if faded else INK
	var x := cr.position.x + 46
	var w := cr.size.x - 56
	_kind_icon(String(c.get("icon", "")), cr.position + Vector2(10, 14), col)
	var title := String(c.get("title", ""))
	var stamp_w := 104.0 if String(c.get("theory", "")) != "" else (70.0 if c.get("night", false) else 0.0)
	var ts := _fit(f, title, w - stamp_w, 26, 18)
	draw_string(f, Vector2(x, cr.position.y + 32), _ellipsize(f, title, w - stamp_w, ts), HORIZONTAL_ALIGNMENT_LEFT, -1,
		ts, col)
	var sub := String(c.get("sub", ""))
	if sub != "":
		draw_string(fb, Vector2(x, cr.position.y + 62), _ellipsize(fb, sub, w, 21), HORIZONTAL_ALIGNMENT_LEFT, -1, 21,
			Color(col, col.a * 0.8))
	if String(c.get("theory", "")) != "":
		_stamp(cr.position + Vector2(cr.size.x - 104, 6), "ТЕОРИЯ", faded)
	elif c.get("night", false):
		_stamp(cr.position + Vector2(cr.size.x - 66, 6), "16+", faded)


## Обрезать строку по ширине с многоточием на границе слова.
func _ellipsize(f: Font, text: String, w: float, sz: int) -> String:
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x <= w:
		return text
	var words := text.split(" ")
	var out := ""
	for wd in words:
		var nxt := (out + " " + wd).strip_edges()
		if f.get_string_size(nxt + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > w:
			break
		out = nxt
	return out.rstrip(",.—- ") + "…"


func _fit(f: Font, text: String, w: float, big: int, small: int) -> int:
	var s := big
	while s > small and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > w:
		s -= 1
	return s


func _stamp(p: Vector2, text: String, faded: bool) -> void:
	var f := UiKit.FONT_BOLD
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 14
	var col := Color(MARKER, 0.35 if faded else 0.9)
	draw_set_transform(p + Vector2(w * 0.5, 14), -0.08)
	draw_rect(Rect2(Vector2(-w * 0.5, -14), Vector2(w, 28)), col, false, 2.5)
	draw_string(f, Vector2(-w * 0.5 + 7, 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
	draw_set_transform(Vector2.ZERO)


func _kind_icon(icon: String, p: Vector2, col: Color) -> void:
	var px := 3.0
	match icon:
		"night":
			BadgeIcons.draw(self, "star", p, px, MARKER if col.a > 0.5 else col)
		"tutorial":
			draw_string(UiKit.FONT_BOLD, p + Vector2(4, 26), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, col)
		"boss":
			BadgeIcons.draw(self, "boss", p, px, MARKER if col.a > 0.5 else col)
		"glitch":
			BadgeIcons.draw(self, "static", p, px, col)
		_:
			var rows: Array = KIND_ICONS.get(icon, KIND_ICONS.episode)
			for y in rows.size():
				for x in String(rows[y]).length():
					if String(rows[y])[x] == "#":
						draw_rect(Rect2(p + Vector2(x, y) * px, Vector2(px, px)), col)


func _dashed(r: Rect2, col: Color, w: float, dash: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], Color(col, 0.6), w, dash)


## Красная обводка фломастером, от руки. t — какая часть уже нарисована.
func _marker_oval(cr: Rect2, t: float, seed_value: int) -> void:
	if t <= 0.0:
		return
	var c := cr.get_center()
	var rx := cr.size.x * 0.5 - 6
	var ry := cr.size.y * 0.5 - 5
	var pts := PackedVector2Array()
	var n := int(56 * t) + 2
	for k in n:
		var a := -2.4 + (TAU + 0.5) * k / 55.0
		var wob := 1.0 + 0.035 * sin(a * 2.0 + seed_value) + 0.02 * sin(a * 5.0 + seed_value * 1.7)
		pts.append(c + Vector2(cos(a) * rx * wob, sin(a) * ry * wob))
	draw_polyline(pts, Color(MARKER, 0.85), 5.0, true)


# ---------------------------------------------------------------- ввод

func _gui_input(e: InputEvent) -> void:
	if run == null:
		return
	var hit := _cell_at(e.position) if (e is InputEventMouse) else Vector2i(-1, -1)
	if e is InputEventMouseMotion:
		if hit != _hover:
			_hover = hit
			queue_redraw()
			if hit.x >= 0:
				hovered.emit(run.grid.rows[hit.x][hit.y], get_global_transform() * cell_rect(hit.x, hit.y).end)
			else:
				hovered.emit({}, Vector2.ZERO)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and hit.x >= 0:
		if hit.x == run.row + 1 and run.available_moves().has(hit.y):
			chosen.emit(hit.y)
			accept_event()
		else:
			Sfx.play("deny", 0.4)


func _cell_at(p: Vector2) -> Vector2i:
	if p.y < HEAD_H or p.x < TIME_W:
		return Vector2i(-1, -1)
	var r := int((p.y - HEAD_H) / ROW_H)
	var ch := int((p.x - TIME_W) / col_w())
	if r < 0 or r >= ProgramGrid.ROWS or ch < 0 or ch >= ProgramGrid.CHANNELS:
		return Vector2i(-1, -1)
	return Vector2i(r, ch)
