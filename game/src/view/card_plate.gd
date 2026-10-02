class_name CardPlate
extends Control
## Карта на экране. Рисуется кодом, в полном разрешении, без пиксельных эффектов.
##   mode "you"    — твой вкладыш на поле: глянцевая плашка с пёстрой рамкой;
##   mode "hand"   — вкладыш в руке: то же плюс цена в искрах в кружке;
##   mode "tape"   — тварь: чёрный кадр плёнки с перфорацией;
##   mode "sketch" — набросок: серый карандашный контур (hidden — только «?»).
## Размеры шрифтов — для 1080p: имя 28, цифры 48, значки 22 (см. дизайн-документ, §9).

const PAPER := Color("f3ead2")
const INK := Color("1c1712")
const MAGENTA := Color("d1287a")
const YELLOW := Color("f2c230")
const CYAN := Color("2bb3d9")
const FILM := Color("0b0a0a")
const FILM_INNER := Color("1d1b1a")
const FILM_INK := Color("ddd6c2")
const PENCIL := Color("a19e96")
const ATK := Color("ff6a4d")
const HP := Color("74e083")
const HP_HURT := Color("ffd166")
const DISC := Color("181210")
const ACCENT := Color("d8322a")

var card: Dictionary = {}
var mode := "you"
var selected := false
var hovered := false
var dim := false
## Прогноз: погибнет на следующем PLAY.
var doomed := false


func setup(c: Dictionary, m: String) -> CardPlate:
	card = c
	mode = m
	mouse_filter = Control.MOUSE_FILTER_PASS
	queue_redraw()
	return self


func _ready() -> void:
	mouse_entered.connect(func(): hovered = true; queue_redraw())
	mouse_exited.connect(func(): hovered = false; queue_redraw())


func _draw() -> void:
	match mode:
		"tape":
			_draw_film()
		"sketch":
			_draw_sketch()
		_:
			_draw_insert()
	if doomed:
		_draw_doom()


# ---------------------------------------------------------------- вкладыш

func _draw_insert() -> void:
	# горизонтальный вкладыш: слева имя, рисунок и значки, справа столбиком атака и здоровье
	var r := Rect2(Vector2.ZERO, size)
	_wavy_rect(r.grow(-2), MAGENTA)
	_wavy_rect(r.grow(-7), YELLOW)
	_wavy_rect(r.grow(-12), CYAN)
	var inner := r.grow(-16)
	draw_rect(inner, PAPER.darkened(0.25) if dim else PAPER)
	if card.get("pirate", false):
		draw_rect(inner, Color(1, 1, 1, 0.35))
	var f_bold := UiKit.FONT_BOLD
	var stat_w := 64.0
	var left := Rect2(inner.position, Vector2(inner.size.x - stat_w, inner.size.y))
	var name_x := left.position.x + (34.0 if mode == "hand" else 0.0)
	var name_w := left.end.x - name_x
	var title := String(card.get("name", ""))
	var name_size := _fit(title, name_w, 28, 22)
	if name_size < 23:
		title = CardDB.short_name(card)
		name_size = _fit(title, name_w, 28, 22)
	draw_string(f_bold, Vector2(name_x, inner.position.y + 26), title, HORIZONTAL_ALIGNMENT_CENTER, name_w, name_size, INK)
	var badges: Array = card.get("badges", [])
	var s := 4 if badges.size() <= 1 else 3
	var art_id: String = CardDB.CARDS.get(card.get("id", ""), {}).get("art", "")
	var tex := Art.tinted(art_id, s, Art.INK, ACCENT)
	var ap := Vector2(left.position.x + (left.size.x - tex.get_width()) * 0.5, inner.position.y + 34)
	draw_texture(tex, ap.floor())
	var by := ap.y + tex.get_height() + 2
	_draw_badges(left, by, INK)
	# цифры справа
	var cx := inner.end.x - stat_w * 0.5 + 2
	var rad := 27.0
	_stat_disc(Vector2(cx, inner.position.y + rad + 4), rad, str(int(card.get("atk", 0))), ATK, 48)
	var hp: int = int(card.get("hp", 0))
	var base_hp: int = int(card.get("src", {}).get("hp", hp)) if card.has("src") else hp
	_stat_disc(Vector2(cx, inner.end.y - rad - 4), rad, str(hp), HP_HURT if hp < base_hp else HP, 48)
	if mode == "hand":
		_draw_cost()
	if card.get("reviewed", false):
		_draw_eye_sticker(left)
	if selected or hovered:
		draw_rect(r.grow(2), Color.WHITE if selected else Color(1, 1, 1, 0.55), false, 4.0 if selected else 2.0)


## Самый крупный размер шрифта от big до small, при котором текст влезает в ширину.
func _fit(text: String, w: float, big: int, small: int) -> int:
	var f := UiKit.FONT_BOLD
	var sz := big
	while sz > small and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > w:
		sz -= 1
	return sz


func _wavy_rect(r: Rect2, color: Color) -> void:
	# прямоугольник с зубчатым краем — как вырубка вкладыша
	draw_rect(r.grow(-3), color)
	var step := 12.0
	var x := r.position.x
	while x < r.end.x - 1:
		draw_circle(Vector2(x + step * 0.5, r.position.y + 3), step * 0.5, color)
		draw_circle(Vector2(x + step * 0.5, r.end.y - 3), step * 0.5, color)
		x += step
	var y := r.position.y
	while y < r.end.y - 1:
		draw_circle(Vector2(r.position.x + 3, y + step * 0.5), step * 0.5, color)
		draw_circle(Vector2(r.end.x - 3, y + step * 0.5), step * 0.5, color)
		y += step


func _draw_stats(inner: Rect2) -> void:
	var rad := 30.0 if size.x >= 200 else 26.0
	var num := 48 if size.x >= 200 else 40
	var y := inner.end.y - rad - 4
	var pa := Vector2(inner.position.x + rad + 4, y)
	var ph := Vector2(inner.end.x - rad - 4, y)
	_stat_disc(pa, rad, str(int(card.get("atk", 0))), ATK, num)
	var hp: int = int(card.get("hp", 0))
	var base_hp: int = int(card.get("src", {}).get("hp", hp)) if card.has("src") else hp
	_stat_disc(ph, rad, str(hp), HP_HURT if hp < base_hp else HP, num)


func _stat_disc(c: Vector2, rad: float, text: String, col: Color, num: int) -> void:
	draw_circle(c, rad + 3, Color(0, 0, 0, 0.85))
	draw_circle(c, rad, DISC)
	var f := UiKit.FONT_NUM
	num = int(num * 0.8)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, num).x
	var p := Vector2(c.x - w * 0.5, c.y + num * 0.36)
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, num, 6, Color.BLACK)
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, num, col)


func _draw_cost() -> void:
	var c := Vector2(30, 30)
	draw_circle(c, 29, Color.BLACK)
	draw_circle(c, 26, YELLOW)
	var f := UiKit.FONT_NUM
	var t := str(int(card.get("cost", 0)))
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
	draw_string(f, Vector2(c.x - w * 0.5, c.y + 13), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, INK)


func _draw_badges(area: Rect2, y: float, col: Color) -> void:
	var f := UiKit.FONT_BOLD
	for b in card.get("badges", []):
		var info: Dictionary = CardDB.BADGES.get(b, {})
		var word: String = info.get("name", b)
		var px := 2.0
		var sz := _fit(word, area.size.x - 9 * px - 10, 22, 17)
		var tw := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var total := 9 * px + 6 + tw
		var x := area.position.x + (area.size.x - total) * 0.5
		BadgeIcons.draw(self, b, Vector2(x, y + 2), px, col)
		draw_string(f, Vector2(x + 9 * px + 6, y + 18), word, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		y += 23


func _draw_eye_sticker(inner: Rect2) -> void:
	var c := Vector2(inner.end.x - 16, inner.position.y + 16)
	draw_circle(c, 12, Color.WHITE)
	draw_circle(c, 6, CYAN.darkened(0.3))
	draw_circle(c, 3, Color.BLACK)


# ---------------------------------------------------------------- кадр плёнки

func _draw_film() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, FILM)
	# перфорация по бокам
	var hole := Vector2(10, 14)
	var y := 8.0
	while y + hole.y < size.y - 4:
		draw_rect(Rect2(Vector2(5, y), hole), Color("3a3733"))
		draw_rect(Rect2(Vector2(size.x - 15, y), hole), Color("3a3733"))
		y += 24
	var inner := Rect2(Vector2(22, 8), Vector2(size.x - 44, size.y - 16))
	draw_rect(inner, FILM_INNER)
	var f := UiKit.FONT_BOLD
	var title := CardDB.short_name(card)
	var name_size := _fit(title, inner.size.x - 8, 28, 22)
	draw_string(f, inner.position + Vector2(0, 28), title, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, name_size, FILM_INK)
	var badges: Array = card.get("badges", [])
	_draw_badges(inner, inner.position.y + 32, FILM_INK)
	var art_id: String = CardDB.CREATURES.get(card.get("id", ""), {}).get("art", "")
	var top := inner.position.y + 36 + badges.size() * 23
	if art_id != "":
		var tex := Art.tinted(art_id, 3, FILM_INK, ACCENT)
		draw_texture(tex, Vector2(inner.position.x + (inner.size.x - tex.get_width()) * 0.5, top).floor())
	else:
		_draw_snow(Rect2(Vector2(inner.position.x + 56, top), Vector2(inner.size.x - 112, 70)))
	var rad := 27.0
	var cy := inner.end.y - rad - 4
	_stat_disc(Vector2(inner.position.x + rad + 4, cy), rad, str(int(card.get("atk", 0))), ATK, 48)
	_stat_disc(Vector2(inner.end.x - rad - 4, cy), rad, str(int(card.get("hp", 0))), HP, 48)
	if card.has("glitch_dir"):
		var d: int = card.glitch_dir
		var ax := inner.end.x - 6 if d > 0 else inner.position.x + 6
		var ay := inner.position.y + inner.size.y * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(ax + d * 14, ay), Vector2(ax - d * 8, ay - 16),
			Vector2(ax - d * 8, ay + 16)]), YELLOW)
	if selected or hovered:
		draw_rect(r.grow(2), Color.WHITE if selected else Color(1, 1, 1, 0.55), false, 4.0 if selected else 2.0)


func _draw_snow(inner: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(card.get("uid", 1))
	for i in 140:
		var p := inner.position + Vector2(rng.randf() * inner.size.x, rng.randf() * inner.size.y)
		draw_rect(Rect2(p.floor(), Vector2(4, 4)), Color(1, 1, 1, rng.randf_range(0.15, 0.7)))


# ---------------------------------------------------------------- набросок

func _draw_sketch() -> void:
	var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
	_dashed_rect(r, PENCIL, 3.0, 14.0)
	var f := UiKit.FONT_BOLD
	if card.get("hidden", false):
		draw_string(f, Vector2(0, size.y * 0.5 + 40), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, 110, PENCIL)
		draw_string(f, Vector2(0, size.y - 22), "НАБРОСОК", HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, PENCIL)
		return
	var c: Dictionary = CardDB.CREATURES.get(card.get("id", ""), {})
	draw_string(f, Vector2(0, 38), "НАБРОСОК", HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, PENCIL)
	draw_string(f, Vector2(0, 68), c.get("short", c.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, PENCIL)
	var art_id: String = c.get("art", "")
	if art_id != "":
		var s := clampi(int(minf(size.x * 0.5 / Art.W, size.y * 0.32 / Art.H)), 2, 5)
		var tex := Art.tinted(art_id, s, PENCIL, PENCIL)
		draw_texture(tex, Vector2((size.x - tex.get_width()) * 0.5, 78).floor(), Color(1, 1, 1, 0.8))
	var atk := int(card.get("atk", c.get("atk", 0)))
	var hp := int(card.get("hp", c.get("hp", 0)))
	draw_string(UiKit.FONT_NUM, Vector2(0, size.y - 22), "%d / %d" % [atk, hp], HORIZONTAL_ALIGNMENT_CENTER, size.x, 34,
		PENCIL)


func _dashed_rect(r: Rect2, col: Color, w: float, dash: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], col, w, dash)


func _draw_doom() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.6, 0.05, 0.05, 0.28))
	var f := UiKit.FONT_BOLD
	var t := "ПОГИБНЕТ"
	var y := size.y * 0.5 + 10
	draw_rect(Rect2(Vector2(0, y - 30), Vector2(size.x, 40)), Color(0, 0, 0, 0.75))
	draw_string(f, Vector2(0, y), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color("ff8a75"))
