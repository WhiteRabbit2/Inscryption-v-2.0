class_name UiKit
extends RefCounted
## Общие цвета, шрифты и рамки интерфейса. Всё в одном месте, чтобы стиль был единым.

const NIGHT := Color("070608")
const SOOT := Color("16130f")
const WOOD := Color("5a4b35")
const BONE := Color("e3dbbd")
const ASH := Color("a89a74")
const BLOOD := Color("c8402c")

const FONT_BODY := preload("res://assets/fonts/Handjet-600.ttf")
const FONT_BOLD := preload("res://assets/fonts/Handjet-700.ttf")
const FONT_TITLE := preload("res://assets/fonts/RuslanDisplay-400.ttf")
## Крупные числа (атака, здоровье, цена, шкалы): у Handjet ноль с точкой и издалека похож на 8,
## у Pixelify «2» и «5» похожи на «S». Russo One читается однозначно.
const FONT_NUM := preload("res://assets/fonts/RussoOne-Regular.ttf")


## Размер шрифта с учётом настройки «размер текста».
static func fs(base: int) -> int:
	return int(round(base * Settings.text_scale))


static func panel_style(alpha := 0.94, border := WOOD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(SOOT.r * 0.6, SOOT.g * 0.6, SOOT.b * 0.6, alpha)
	s.border_color = border
	s.set_border_width_all(3)
	s.set_content_margin_all(18)
	s.shadow_color = Color(0, 0, 0, 0.6)
	s.shadow_size = 0
	s.shadow_offset = Vector2(4, 4)
	return s


static func label(text: String, size := 30, color := BONE, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func rich(size := 30) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", fs(size))
	r.add_theme_font_size_override("bold_font_size", fs(size))
	r.add_theme_font_override("bold_font", FONT_BOLD)
	r.add_theme_color_override("default_color", BONE)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", fs(30))
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", ASH.darkened(0.3))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := panel_style(0.95, BLOOD if accent else WOOD)
		s.set_content_margin_all(10)
		s.content_margin_left = 20
		s.content_margin_right = 20
		if state == "hover" or state == "focus":
			s.border_color = BONE
		if state == "pressed":
			s.bg_color = SOOT.lightened(0.1)
		b.add_theme_stylebox_override(state, s)
	b.focus_mode = Control.FOCUS_ALL
	return b
