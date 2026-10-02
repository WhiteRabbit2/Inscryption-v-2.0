class_name BattleScreen
extends Control
## Экран боя (пока серый 2D-макет): поле на «экране», рука вкладышей, видик с PLAY и искрами,
## карманы с предметами, кружок ведущего, субтитры, перемотка.
## Логику не трогает напрямую: всё через Battle.apply(), потом проигрывает события и сверяет экран (sync).
##
## Управление: клик по вкладышу в руке → клик по своей пустой клетке. Предмет: первый клик — описание,
## второй — применить (или клик по цели). PLAY — кнопка или пробел. Esc / правая кнопка — отмена.

signal finished(result: String)

const HAND_Y := 856.0
const HAND_CARD := Vector2(256, 180)

var b: Battle
var rewinds := 2
## Если задан — поле кладётся на кинескоп телевизора в 3D-комнате (иначе серый макет).
var tv: TvStage
## Автоход для проверок без человека.
var auto := false

var board: BattleBoard
var hand_box: Control
var play_btn: Button
var vcr: Control
var pocket_btns: Array = []
var wink_btn: Button
var subtitle: Label
var tooltip: TooltipPanel
var overlay: Control
var host: HostCircle
var _bg: ColorRect

var _sel_hand := -1
var _sel_item := -1
var _wink_armed := false
var _busy := false
var _hand_plates: Array = []
var _auto_t := 0.0
var _dead_names := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = ColorRect.new()
	_bg.color = Color("232327")
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.visible = tv == null
	add_child(_bg)
	board = BattleBoard.new()
	board.position = Vector2(410, 22)
	add_child(board)
	board.cell_clicked.connect(_on_cell)
	board.cell_hovered.connect(_on_cell_hover)
	hand_box = Control.new()
	hand_box.position = Vector2(0, HAND_Y)
	hand_box.size = Vector2(1920, 1080 - HAND_Y)
	hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hand_box)
	_build_host()
	_build_vcr()
	_build_pockets()
	subtitle = UiKit.label("", 30, UiKit.BONE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(410, 784)
	subtitle.size = Vector2(1100, 60)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.78)
	sb.set_content_margin_all(8)
	subtitle.add_theme_stylebox_override("normal", sb)
	add_child(subtitle)
	tooltip = TooltipPanel.new()
	add_child(tooltip)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)


## Положить поле на прямоугольник экрана (в TV-режиме — каждый кадр по кинескопу).
func fit_board(r: Rect2) -> void:
	var k := r.size.x / BattleBoard.BASE.x
	board.scale = Vector2(k, k)
	board.position = r.position + Vector2(0, (r.size.y - BattleBoard.BASE.y * k) * 0.5)
	host.size = Vector2(100, 100) * k
	host.position = board.position + Vector2(10, 6) * k
	subtitle.position = board.position + Vector2(0, 760) * k
	subtitle.size = Vector2(BattleBoard.BASE.x, 60)
	subtitle.scale = Vector2(k, k)


## Точка поля → координаты экрана (с учётом масштаба поля).
func board_point(local: Vector2) -> Vector2:
	return board.get_global_transform() * local


func start(battle: Battle, rewinds_left := 2) -> void:
	b = battle
	rewinds = rewinds_left
	_sync()
	var line: String = b.episode.get("line", "")
	say(line if line != "" else "Серия %s. Поехали." % b.episode.get("name", ""))


func say(text: String) -> void:
	subtitle.text = text
	subtitle.visible = text != ""


# ---------------------------------------------------------------- постройка

func _build_host() -> void:
	host = HostCircle.new()
	host.position = Vector2(135, 18)
	host.size = Vector2(150, 150)
	add_child(host)
	wink_btn = UiKit.button("Подмигнуть")
	wink_btn.position = Vector2(40, 190)
	wink_btn.size = Vector2(340, 60)
	wink_btn.pressed.connect(_on_wink)
	add_child(wink_btn)


func _build_vcr() -> void:
	vcr = VcrPanel.new()
	vcr.position = Vector2(1540, 22)
	vcr.size = Vector2(350, 560)
	add_child(vcr)
	play_btn = UiKit.button("▶  PLAY", true)
	play_btn.add_theme_font_size_override("font_size", UiKit.fs(52))
	play_btn.position = Vector2(1560, 600)
	play_btn.size = Vector2(310, 110)
	play_btn.pressed.connect(_on_play)
	play_btn.mouse_entered.connect(func(): board.show_forecast = true; board.refresh_forecast())
	add_child(play_btn)


func _build_pockets() -> void:
	var title := UiKit.label("КАРМАНЫ", 26, UiKit.ASH)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.position = Vector2(40, 300)
	add_child(title)
	for i in 3:
		var btn := UiKit.button("")
		btn.position = Vector2(40, 340 + i * 84)
		btn.size = Vector2(340, 72)
		btn.pressed.connect(_on_pocket.bind(i))
		btn.mouse_entered.connect(_on_pocket_hover.bind(i, btn))
		btn.mouse_exited.connect(func(): tooltip.hide_tip())
		add_child(btn)
		pocket_btns.append(btn)


# ---------------------------------------------------------------- сверка с состоянием

func _sync() -> void:
	board.targets = _targets()
	board.sync(b)
	(vcr as VcrPanel).show_state(b, rewinds)
	for i in pocket_btns.size():
		var id = b.items[i] if i < b.items.size() else null
		var btn: Button = pocket_btns[i]
		btn.text = "—" if id == null else CardDB.ITEMS[id].get("short", CardDB.ITEMS[id].name)
		btn.disabled = id == null or b.over
		if i == _sel_item:
			btn.text = "▶ " + btn.text
	wink_btn.visible = b.winks > 0
	wink_btn.text = ("▶ " if _wink_armed else "") + "Подмигнуть ×%d" % b.winks
	play_btn.disabled = b.over or _busy
	_layout_hand()


func _layout_hand() -> void:
	for p in _hand_plates:
		p.queue_free()
	_hand_plates.clear()
	var n := b.hand.size()
	var gap := 10.0
	var w := n * HAND_CARD.x + maxf(n - 1, 0) * gap
	var x0 := (1920.0 - w) * 0.5
	for i in n:
		var c: Dictionary = b.hand[i]
		var p := CardPlate.new()
		p.setup(c, "hand")
		p.size = HAND_CARD
		p.position = Vector2(x0 + i * (HAND_CARD.x + gap), 4 if i == _sel_hand else 24)
		p.selected = i == _sel_hand
		p.dim = int(c.cost) > b.sparks
		p.gui_input.connect(_on_hand_input.bind(i))
		p.mouse_entered.connect(_on_hand_hover.bind(i, p))
		p.mouse_exited.connect(func(): tooltip.hide_tip())
		hand_box.add_child(p)
		_hand_plates.append(p)


func _targets() -> Dictionary:
	var t := {}
	if b == null or b.over:
		return t
	if _sel_hand >= 0:
		var lanes := []
		for l in Battle.LANES:
			if b.can_place(_sel_hand, l):
				lanes.append(l)
		t["you"] = lanes
	elif _sel_item >= 0:
		for a in b.legal_actions():
			if a.type == "item" and int(a.slot) == _sel_item and a.has("lane"):
				var row := "tape" if CardDB.ITEMS[b.items[_sel_item]].target == "tape" else "you"
				if not t.has(row):
					t[row] = []
				t[row].append(int(a.lane))
	return t


# ---------------------------------------------------------------- ввод

func _unhandled_input(e: InputEvent) -> void:
	if _busy or b == null:
		return
	if e.is_action_pressed("advance") and not b.over:
		_on_play()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("cancel"):
		_clear_selection()
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and e.keycode >= KEY_1 and e.keycode <= KEY_7:
		var i: int = e.keycode - KEY_1
		if i < b.hand.size():
			_sel_hand = -1 if _sel_hand == i else i
			_sel_item = -1
			_sync()


func _clear_selection() -> void:
	_sel_hand = -1
	_sel_item = -1
	_wink_armed = false
	_sync()


func _on_hand_input(e: InputEvent, i: int) -> void:
	if _busy or b.over:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_sel_hand = -1 if _sel_hand == i else i
		_sel_item = -1
		_wink_armed = false
		if _sel_hand >= 0 and int(b.hand[i].cost) > b.sparks:
			say("Не хватает искр: нужно %d, есть %d." % [int(b.hand[i].cost), b.sparks])
		_sync()


func _on_hand_hover(i: int, p: CardPlate) -> void:
	if i < b.hand.size():
		tooltip.show_at(_card_tip(b.hand[i]), p.global_position + Vector2(p.size.x * 0.5, -10))


func _on_cell_hover(row: String, l: int) -> void:
	if row == "" or b == null:
		tooltip.hide_tip()
		return
	var c = null
	if row == "you":
		c = b.you[l]
	elif row == "tape":
		c = b.tape[l]
		if c == null and b.sketches[l] != null:
			c = CardDB.make_creature(b.sketches[l].id, int(b.cfg.tape_hp), int(b.cfg.tape_atk))
			if b.sketches[l].hidden:
				tooltip.show_at({"title": "Набросок", "lines": ["Мультик рисовали ночью: кто тут выйдет — не видно."]},
					board_point(board.cell_rect("tape", l).end))
				return
			c.sketch = true
	if c == null:
		tooltip.hide_tip()
		return
	tooltip.show_at(_card_tip(c), board_point(board.cell_rect(row, l).end - Vector2(0, 100)))


func _card_tip(c: Dictionary) -> Dictionary:
	var lines := []
	var is_tape: bool = CardDB.CREATURES.has(c.id) and not CardDB.CARDS.has(c.id)
	var head := "Атака %d · Здоровье %d" % [int(c.atk), int(c.hp)]
	if not is_tape:
		head = "Цена %d искр · " % int(c.cost) + head
	lines.append(head)
	for bd in c.get("badges", []):
		var info: Dictionary = CardDB.BADGES.get(bd, {})
		lines.append("[b]%s[/b] — %s" % [info.get("name", bd), info.get("text", "")])
	if c.get("flat", false):
		lines.append("Расплющен в блин. Второй раз не повезёт.")
	if c.get("pirate", false):
		lines.append("Пиратская копия.")
	if c.get("reviewed", false):
		lines.append("Уже был на Разборе.")
	var src: Dictionary = CardDB.CREATURES.get(c.id, {}) if is_tape else CardDB.CARDS.get(c.id, {})
	if src.has("flavor"):
		lines.append("[i]«%s»[/i]" % src.flavor)
	var sub := "набросок твари" if c.get("sketch", false) else ("тварь с плёнки" if is_tape else "вкладыш «Опушка»")
	return {"title": String(c.name), "subtitle": sub, "lines": lines}


func _on_pocket_hover(i: int, btn: Button) -> void:
	var id = b.items[i] if b and i < b.items.size() else null
	if id == null:
		return
	var it: Dictionary = CardDB.ITEMS[id]
	tooltip.show_at({"title": it.name, "lines": [it.text, "Клик — выбрать, ещё клик — применить."]},
		btn.global_position + Vector2(btn.size.x, 0))


func _on_pocket(i: int) -> void:
	if _busy or b.over or b.items[i] == null:
		return
	var id: String = b.items[i]
	var it: Dictionary = CardDB.ITEMS[id]
	_sel_hand = -1
	_wink_armed = false
	if _sel_item != i:
		_sel_item = i
		match String(it.target):
			"tape":
				say("%s: выбери тварь." % it.name)
			"you":
				say("%s: выбери своего зверя." % it.name)
			"gaze":
				say("%s: кликни полосу рядом с пунктиром — он туда переедет." % it.name)
			_:
				say("%s — %s Нажми ещё раз, чтобы применить." % [it.name, it.text])
		_sync()
		return
	if String(it.target) == "":
		_act({"type": "item", "slot": i})


func _on_wink() -> void:
	if _busy or b.over or b.winks <= 0:
		return
	_wink_armed = not _wink_armed
	_sel_hand = -1
	_sel_item = -1
	if _wink_armed:
		say("Подмигивание: кликни полосу рядом с пунктиром — он туда переедет.")
	_sync()


func _on_cell(row: String, l: int) -> void:
	if _busy or b.over:
		return
	if _sel_hand >= 0 and row == "you":
		if b.can_place(_sel_hand, l):
			var hi := _sel_hand
			_sel_hand = -1
			_act({"type": "place", "hand": hi, "lane": l})
		else:
			say("Сюда нельзя." if b.you[l] != null else "Не хватает искр.")
		return
	if _sel_item >= 0:
		var it: Dictionary = CardDB.ITEMS[b.items[_sel_item]]
		if it.target == "gaze":
			var a := _shift_action(l)
			if a.is_empty():
				say("Пунктир сдвигается только на соседнюю полосу.")
				return
			a.type = "item"
			a.slot = _sel_item
			_sel_item = -1
			_act(a)
			return
		var want := "tape" if it.target == "tape" else "you"
		if row == want:
			var a := {"type": "item", "slot": _sel_item, "lane": l}
			_sel_item = -1
			_act(a)
		return
	if _wink_armed:
		var a := _shift_action(l)
		if a.is_empty():
			say("Пунктир сдвигается только на соседнюю полосу.")
			return
		a.type = "wink"
		_wink_armed = false
		_act(a)


## Какой пунктир сдвинуть, чтобы он лёг на полосу l.
func _shift_action(l: int) -> Dictionary:
	for gi in b.gazes.size():
		var d: int = l - int(b.gazes[gi].plan)
		if absi(d) == 1:
			return {"gaze": gi, "dir": d}
	return {}


func _on_play() -> void:
	if _busy or b.over:
		return
	_clear_selection()
	await _act({"type": "play"})


# ---------------------------------------------------------------- проигрывание событий

func _act(a: Dictionary) -> void:
	_busy = true
	_dead_names.clear()
	for c in b.you:
		if c != null:
			_dead_names[c.uid] = CardDB.short_name(c)
	var ev := b.apply(a)
	await _playback(ev)
	_busy = false
	_sync()
	if b.over:
		_show_result()
	else:
		_comment(a, ev)


## Одна реплика ведущего на действие — самое заметное из случившегося. Не на каждый чих.
func _comment(a: Dictionary, ev: Array) -> void:
	var film := 0
	var sig := 0
	var off := 0
	var died_you := ""
	var died_tape := 0
	var flat := false
	var moved_by := ""
	var squint := false
	for e in ev:
		match e.t:
			"film":
				film += -int(e.delta)
			"signal":
				sig += -int(e.delta)
			"strike":
				if e.side == "you" and e.target == "offscreen":
					off += 1
			"die":
				if e.side == "tape":
					died_tape += 1
			"flatten":
				flat = true
			"gaze_add":
				squint = true
			"gaze_plan":
				if String(e.by).begins_with("card:"):
					moved_by = String(e.by)
	if a.type == "play":
		for e in ev:
			if e.t == "die" and e.side == "you":
				died_you = _name_of_dead(e.uid)
		var key := ""
		if film >= 3:
			key = "film_big"
		elif b.sig <= 2 and sig > 0:
			key = "signal_low"
		elif flat:
			key = "flatten"
		elif died_you != "":
			say(Lines.fmt("you_die", null, {"name": died_you}))
			return
		elif sig > 0:
			key = "signal_hit"
		elif off > 0 and film == 0:
			key = "offscreen"
		elif film > 0:
			key = "film_hit"
		elif died_tape > 0:
			key = "tape_die"
		elif squint:
			key = "squint"
		if key != "":
			say(Lines.pick(key))
		return
	if a.type == "place" and moved_by != "":
		var uid := int(moved_by.substr(5))
		for c in b.you:
			if c != null and c.uid == uid:
				say(Lines.fmt("gaze_moved_by_card", null, {"name": CardDB.short_name(c)}))
				return
	if a.type == "place" and randf() < 0.35:
		var c = b.you[int(a.lane)]
		if c != null:
			say(Lines.fmt("place_lit" if b.lit(int(a.lane)) else "place_off", null, {"name": CardDB.short_name(c)}))


func _name_of_dead(uid: int) -> String:
	return _dead_names.get(uid, "")


func _speed() -> float:
	return Settings.anim_speed()


func _wait(t: float) -> void:
	await get_tree().create_timer(t / _speed()).timeout


func _playback(ev: Array) -> void:
	var scene_shown := false
	for e in ev:
		match e.t:
			"deny":
				Sfx.play("deny", 0.6)
			"place":
				Sfx.play("place")
			"item":
				Sfx.play("item")
				say(CardDB.ITEMS[e.item].name + "!")
			"play":
				Sfx.play("vcr_play", 0.8)
				say("")
			"sketch":
				Sfx.play("pencil", 0.5)
			"ink":
				board.sync(b)
				Sfx.play("paper", 0.6)
			"strike":
				if not scene_shown:
					scene_shown = true
					await _show_scene(ev)
			"die":
				Sfx.play("die", 0.7)
			"phase":
				board.sync(b)
				say(b.episode.phase2.get("line", "Стоп-кадр."))
				await _wait(1.2)
			"titles":
				say("Титры! Обе шкалы теряют по 1.")
			"gaze_move", "gaze_add", "gaze_plan":
				Sfx.play("eye", 0.35)
			"montage":
				board.sync(b)
				await _wait(0.15)
	board.sync(b)


## Сцена: все бьют одновременно — показываем одним тактом.
func _show_scene(ev: Array) -> void:
	board.show_forecast = false
	board.refresh_forecast()
	var lw := board.size.x / Battle.LANES
	var tw := create_tween().set_parallel(true)
	for e in ev:
		if e.t != "strike":
			continue
		var row: String = e.side
		var c = b.you[e.lane] if row == "you" else b.tape[e.lane]
		if c == null:
			continue
		var p: CardPlate = board.plate_for(c.uid)
		if p == null:
			continue
		var d := -28.0 if row == "you" else 28.0
		var base := p.position
		tw.tween_property(p, "position", base + Vector2(0, d), 0.09 / _speed())
		tw.chain().tween_property(p, "position", base, 0.12 / _speed())
		tw.set_parallel(true)
		var txt := ""
		var col := Color.WHITE
		match String(e.target):
			"film":
				txt = "−%d ПЛЁНКИ" % e.dmg
				col = BattleBoard.GOOD
			"signal":
				txt = "−%d СИГНАЛА" % e.dmg
				col = BattleBoard.BAD
			"offscreen":
				txt = "за кадром"
				col = BattleBoard.MUTED
		if txt != "":
			_popup(board_point(Vector2(lw * (e.lane + 0.5), BattleBoard.MID_Y + 40)), txt, col)
	Sfx.play("hit", 0.8)
	await _wait(0.32)
	for e in ev:
		if e.t == "damage":
			var p: CardPlate = board.plate_for(e.uid)
			if p:
				_popup(board_point(p.position + Vector2(p.size.x * 0.5, 60)), "−%d" % e.dmg, BattleBoard.BAD)
	await _wait(0.3)
	board.show_forecast = true


func _popup(at: Vector2, text: String, col: Color) -> void:
	var l := UiKit.label(text, 40, col, UiKit.FONT_BOLD)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(260, 50)
	l.position = at - Vector2(130, 25)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 40, 0.8 / _speed())
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8 / _speed()).set_delay(0.3 / _speed())
	tw.tween_callback(l.queue_free)


# ---------------------------------------------------------------- итог

func _show_result() -> void:
	for c in overlay.get_children():
		c.queue_free()
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0.55, 0.92) if b.result == "lose" else Color(0, 0, 0, 0.85)
	panel.position = board.position
	panel.size = board.size * board.scale
	overlay.add_child(panel)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	box.position = board_point(Vector2(150, 200))
	box.size = Vector2(800, 420) * board.scale
	overlay.add_child(box)
	if b.result == "win":
		box.add_child(_center(UiKit.label("ОБРЫВ ПЛЁНКИ", 84, Color.WHITE, UiKit.FONT_BOLD)))
		box.add_child(_center(UiKit.label("Серия окончена. Титры.", 36, UiKit.BONE)))
		var ok := UiKit.button("Дальше", true)
		ok.pressed.connect(func(): finished.emit("win"))
		box.add_child(_center(ok))
		Sfx.play("win")
		return
	box.add_child(_center(UiKit.label("НЕТ СИГНАЛА", 84, Color.WHITE, UiKit.FONT_BOLD)))
	Sfx.play("static", 0.7)
	Sfx.play("lose", 0.6)
	if rewinds > 0:
		box.add_child(_center(UiKit.label("Перемоток осталось: %d" % rewinds, 34, UiKit.BONE)))
		var back := UiKit.button("Перемотать на ход назад", true)
		back.pressed.connect(_rewind.bind(false))
		box.add_child(_center(back))
		var start_btn := UiKit.button("К началу серии")
		start_btn.pressed.connect(_rewind.bind(true))
		box.add_child(_center(start_btn))
	else:
		box.add_child(_center(UiKit.label("ПЛЁНКУ ЗАЖЕВАЛО", 48, UiKit.BLOOD, UiKit.FONT_BOLD)))
		var end_btn := UiKit.button("Конец ночи")
		end_btn.pressed.connect(func(): finished.emit("lose"))
		box.add_child(_center(end_btn))


func _center(c: Control) -> Control:
	if c is Label:
		(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		c.custom_minimum_size = Vector2(460, 72)
	return c


func _rewind(to_start: bool) -> void:
	rewinds -= 1
	b.rewind(to_start)
	for c in overlay.get_children():
		c.queue_free()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Sfx.play("vcr_rewind", 0.8)
	say("Перемотаем. Я тоже с первого раза не понял, что там произошло.")
	_sync()


# ---------------------------------------------------------------- автоход (проверки)

func _process(delta: float) -> void:
	if tv:
		fit_board(tv.screen_rect().grow(-6))
	if not auto or b == null or _busy:
		return
	_auto_t += delta * _speed()
	if _auto_t < 0.4:
		return
	_auto_t = 0.0
	if b.over:
		if b.result == "lose" and rewinds > 0:
			_rewind(true)
		else:
			auto = false
			finished.emit(b.result)
		return
	for i in b.hand.size():
		for l in Battle.LANES:
			if b.can_place(i, l) and (b.tape[l] != null or b.sketches[l] != null or b.lit(l)):
				_act({"type": "place", "hand": i, "lane": l})
				return
	_on_play()
