class_name DialogBox
extends PanelContainer
## Реплики Многоглазого: текст печатается по буквам с бормотанием.
## say(text, wait=true) — ждать клика игрока; wait=false — реплика сама исчезнет.

signal finished

## Автотесты: не ждать клика.
var auto_advance := false

var _label: RichTextLabel
var _who: Label
var _more: Label
var _full := ""
var _shown := 0.0
var _typing := false
var _waiting := false
var _hide_timer := 0.0
var _voice_acc := 0


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style(0.93))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_who = UiKit.label("МНОГОГЛАЗЫЙ", 22, UiKit.BLOOD)
	box.add_child(_who)
	_label = UiKit.rich(34)
	box.add_child(_label)
	_more = UiKit.label("▼ дальше — клик или пробел", 20, UiKit.ASH)
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_more)
	visible = false


func is_waiting() -> bool:
	return _waiting or _typing


func say(text: String, wait := true) -> void:
	_full = text
	_shown = 0.0
	_typing = true
	_waiting = false
	_label.text = ""
	_more.visible = false
	visible = true
	_hide_timer = 0.0
	if Settings.test_speed > 4.0:
		_shown = text.length()
	while _typing:
		await get_tree().process_frame
	if wait and not (auto_advance or Settings.test_speed > 4.0):
		_waiting = true
		_more.visible = true
		await finished
		visible = false
	elif wait:
		visible = false
	else:
		_hide_timer = maxf(2.2, text.length() * 0.055)


## Клик или пробел: допечатать или перейти дальше.
func advance() -> bool:
	if _typing:
		_shown = _full.length()
		return true
	if _waiting:
		_waiting = false
		finished.emit()
		return true
	return false


func _process(delta: float) -> void:
	if _typing:
		var before := int(_shown)
		_shown += delta * 38.0
		var n := mini(int(_shown), _full.length())
		if n != before:
			_label.text = _full.substr(0, n)
			_voice_acc += n - before
			if _voice_acc >= 3:
				_voice_acc = 0
				Sfx.voice()
		if n >= _full.length():
			_label.text = _full
			_typing = false
	elif _hide_timer > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0 and not _waiting:
			visible = false
