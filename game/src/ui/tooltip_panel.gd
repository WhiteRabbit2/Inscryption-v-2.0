class_name TooltipPanel
extends PanelContainer
## Всплывающее описание: заголовок, подзаголовок, строки с текстом и (необязательно) картинка.
## show_at(data, screen_pos) — data: {title, subtitle, lines: [String], image: Texture2D}

var _image: TextureRect
var _title: Label
var _subtitle: Label
var _body: VBoxContainer
var _key := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style(0.96))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(420, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	_image = TextureRect.new()
	_image.custom_minimum_size = Vector2(128, 180)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(_image)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	_title = UiKit.label("", 36, UiKit.BONE, UiKit.FONT_BOLD)
	col.add_child(_title)
	_subtitle = UiKit.label("", 24, UiKit.ASH)
	col.add_child(_subtitle)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	col.add_child(_body)
	visible = false


func show_at(data: Dictionary, screen_pos: Vector2) -> void:
	var key := str(data.hash())
	if key != _key:
		_key = key
		_title.text = data.get("title", "")
		_subtitle.text = data.get("subtitle", "")
		_subtitle.visible = _subtitle.text != ""
		_image.texture = data.get("image", null)
		_image.visible = _image.texture != null
		for c in _body.get_children():
			c.queue_free()
		for line in data.get("lines", []):
			var r := UiKit.rich(26)
			r.custom_minimum_size = Vector2(420 if _image.visible else 520, 0)
			r.text = line
			_body.add_child(r)
		reset_size()
	visible = true
	_place.call_deferred(screen_pos)


func _place(screen_pos: Vector2) -> void:
	var vp := get_viewport_rect().size
	var s := size
	var p := screen_pos + Vector2(28, -s.y * 0.5)
	if p.x + s.x > vp.x - 12:
		p.x = screen_pos.x - s.x - 28
	p.y = clampf(p.y, 12, vp.y - s.y - 12)
	p.x = clampf(p.x, 12, vp.x - s.x - 12)
	position = p


func hide_tip() -> void:
	visible = false
	_key = ""
