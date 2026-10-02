class_name SettingsMenu
extends Control
## Окно настроек: камера, эффекты, текст, звук, экран. Всё применяется сразу и сохраняется.

signal closed


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(0.97))
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UiKit.label("Настройки", 44, UiKit.BONE, UiKit.FONT_BOLD))

	_toggle(box, "Спокойный режим: камера на месте, без ряби", "calm_camera")
	_slider(box, "Плёночные эффекты: зерно и дизеринг", "effects", 0.0, 1.0)
	_options(box, "Размер текста", "text_scale", [["100%", 1.0], ["125%", 1.25], ["150%", 1.5]])
	_toggle(box, "Простой шрифт для описаний", "plain_font")
	_toggle(box, "Быстрые анимации боя", "fast_animations")
	_slider(box, "Громкость", "master_volume", 0.0, 1.0)
	_slider(box, "Гул и музыка", "music_volume", 0.0, 1.0)
	_slider(box, "Звуки", "sfx_volume", 0.0, 1.0)
	_toggle(box, "Полный экран", "fullscreen")

	var close := UiKit.button("Готово", true)
	close.pressed.connect(func(): closed.emit(); queue_free())
	box.add_child(close)
	close.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()


func _row(box: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := UiKit.label(text, 28)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	box.add_child(row)
	return row


func _toggle(box: VBoxContainer, text: String, key: String) -> void:
	var row := _row(box, text)
	var c := CheckButton.new()
	c.button_pressed = Settings.get(key)
	c.toggled.connect(func(v): Settings.set_and_save(key, v))
	row.add_child(c)


func _slider(box: VBoxContainer, text: String, key: String, lo: float, hi: float) -> void:
	var row := _row(box, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = Settings.get(key)
	s.custom_minimum_size = Vector2(260, 32)
	s.value_changed.connect(func(v): Settings.set_and_save(key, v))
	row.add_child(s)


func _options(box: VBoxContainer, text: String, key: String, opts: Array) -> void:
	var row := _row(box, text)
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", UiKit.fs(26))
	var cur: float = Settings.get(key)
	for i in opts.size():
		o.add_item(opts[i][0], i)
		if absf(opts[i][1] - cur) < 0.01:
			o.select(i)
	o.item_selected.connect(func(i): Settings.set_and_save(key, opts[i][1]))
	row.add_child(o)
