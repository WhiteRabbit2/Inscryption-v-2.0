# gdlint: disable=max-returns
class_name SegmentPanel
extends Control
## Рубрики и теории на экране телевизора: заголовок, реплика ведущего и список вариантов кнопками.
## Простой общий вид для всех рубрик: варианты берутся из Run.choices(), подписи — из describe().
## Кладётся на кинескоп (fit), как поле боя.

signal picked(choice: Dictionary)

const BASE := Vector2(1100, 825)

var run: Run
var _title: Label
var _line: Label
var _info: Label
var _list: VBoxContainer
var _note: Label


func _ready() -> void:
	size = BASE
	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.size = BASE
	add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(40, 24)
	box.size = BASE - Vector2(80, 48)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = UiKit.label("", 46, Color.WHITE, UiKit.FONT_BOLD)
	box.add_child(_title)
	_line = UiKit.label("", 26, Color("bfe0ff"))
	box.add_child(_line)
	_info = UiKit.label("", 22, UiKit.ASH)
	box.add_child(_info)
	_note = UiKit.label("", 24, Color("ffd166"))
	box.add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)


func fit(r: Rect2) -> void:
	var k := r.size.x / BASE.x
	scale = Vector2(k, k)
	position = r.position + Vector2(0, (r.size.y - BASE.y * k) * 0.5)


func show_offer(r: Run, note := "") -> void:
	run = r
	var o: Dictionary = run.current_offer()
	var kind := String(o.get("kind", ""))
	if kind == "theory":
		_title.text = "ТЕОРИЯ МНОГОГЛАЗОГО"
		_line.text = Lines.pick("theory")
	else:
		_title.text = Segments.KINDS.get(kind, {}).get("title", kind.to_upper())
		_line.text = String(o.get("line", ""))
		if kind == "glitch":
			_line.text = "%s. %s" % [o.get("name", ""), o.get("text", "")]
	var pockets := []
	for p in run.pockets:
		pockets.append("—" if p == null else CardDB.ITEMS[p].get("short", CardDB.ITEMS[p].name))
	_info.text = "Фантики: %d   ·   Карманы: %s   ·   Колода: %d   ·   Перемотки: %d" % [
		run.fantiki, ", ".join(pockets), run.deck.size(), run.rewinds]
	_note.text = note
	_note.visible = note != ""
	for c in _list.get_children():
		c.queue_free()
	for ch in run.choices():
		var b := UiKit.button(describe(o, ch))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", UiKit.fs(24))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(BASE.x - 100, 0)
		b.pressed.connect(func(): picked.emit(ch))
		_list.add_child(b)


## Подпись варианта по-человечески.
func describe(o: Dictionary, c: Dictionary) -> String:
	var kind := String(o.get("kind", ""))
	if c.get("skip", false):
		return "Пропустить"
	if c.get("leave", false):
		return "Повесить трубку" if kind == "shop" else "Уйти"
	match kind:
		"theory":
			var t: Dictionary = o.options[int(c.pick)]
			return "%s — %s Награда: %s" % [t.name, t.rule, t.reward]
		"raffle":
			return "Взять: " + card_text(o.cards[int(c.pick)])
		"shop":
			var lot: Dictionary = o.lots[int(c.buy)]
			var what := ""
			match String(lot.type):
				"card":
					what = card_text(lot.card)
				"item":
					what = "%s — %s" % [CardDB.ITEMS[lot.item].name, CardDB.ITEMS[lot.item].text]
				"bundle":
					what = "«Но это ещё не всё!»: %s + предмет-сюрприз" % card_text(lot.card)
			return "Купить за %d фантиков: %s" % [int(lot.price), what]
		"review":
			var opt := {}
			for x in Segments.REVIEW_OPTIONS:
				if x.id == c.option:
					opt = x
			return "%s: %s (%s)" % [card_text(run.deck[int(c.card)]), opt.get("name", ""), opt.get("text", "")]
		"pirate":
			if c.has("copy"):
				return "Пиратская копия: " + card_text(run.deck[int(c.copy)])
			return "Сдать за %d фантика: %s" % [int(o.get("sell_price", 2)), card_text(run.deck[int(c.sell)])]
		"sponsor":
			var id: String = o.items[int(c.pick)]
			var t := "%s — %s" % [CardDB.ITEMS[id].name, CardDB.ITEMS[id].text]
			if c.has("slot"):
				var old = run.pockets[int(c.slot)]
				t += " (вместо: %s)" % ("пусто" if old == null else CardDB.ITEMS[old].name)
			return t
		"glitch":
			var opt2: Dictionary = o.options[int(c.pick)]
			var t2 := String(opt2.text)
			if c.has("card"):
				t2 += " — " + card_text(run.deck[int(c.card)])
			return t2
	return str(c)


static func card_text(c: Dictionary) -> String:
	var badges := []
	for bd in c.get("badges", []):
		badges.append(CardDB.BADGES.get(bd, {}).get("name", bd))
	var t := "%s (цена %d, %d/%d)" % [c.name, int(c.cost), int(c.atk), int(c.hp)]
	if not badges.is_empty():
		t += " " + ", ".join(badges)
	return t
