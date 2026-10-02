class_name Game
extends Node
## Вся игра от меню до конца ночи: комната с телевизором, газета, серии, рубрики, итог и письма зрителей.
## Логика — в Run / Battle / Meta; здесь только переключение экранов и сохранения.
##
## Сохранения: мета (глаза, письма, открытия) — после каждой ночи; ночь — после каждого шага по газете,
## рубрики и серии. «Продолжить» в меню поднимает ночь с последнего шага.

var stage: TvStage
var layer: CanvasLayer
var meta: Dictionary
var run: Run
var screen: Control
var subtitle: Label
## Автоигра для проверок без человека (--auto): сама выбирает в газете и рубриках, бой — простым автоходом.
var auto := false


func _ready() -> void:
	auto = OS.get_cmdline_user_args().has("--auto")
	stage = TvStage.new()
	add_child(stage)
	# пока нет передачи — на кинескопе тёмно-синий «нет сигнала»
	stage.room.screen_material.albedo_color = Color("16304a")
	layer = CanvasLayer.new()
	add_child(layer)
	subtitle = UiKit.label("", 30, UiKit.BONE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(160, 1000)
	subtitle.size = Vector2(1600, 60)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(subtitle)
	meta = Meta.normalize(Saves.read(Saves.META, Meta.new_meta()))
	Sfx.start_drone()
	if auto:
		_new_night()
	else:
		_show_menu()


func _process(_delta: float) -> void:
	if screen is PaperScreen:
		(screen as PaperScreen).fit(stage.paper_rect().grow(-4))
	elif screen is SegmentPanel:
		(screen as SegmentPanel).fit(stage.screen_rect().grow(-6))


func say(text: String) -> void:
	subtitle.text = text


func _clear() -> void:
	if screen:
		screen.queue_free()
		screen = null
	say("")


func _save() -> void:
	if run and not run.is_over():
		Saves.write(Saves.RUN, run.to_dict())


# ---------------------------------------------------------------- меню

func _show_menu() -> void:
	_clear()
	stage.cut_to("room")
	var box := VBoxContainer.new()
	box.position = Vector2(110, 300)
	box.size = Vector2(640, 600)
	box.add_theme_constant_override("separation", 18)
	var title := UiKit.label("МНОГОГЛАЗЫЙ", 72, Color.WHITE, UiKit.FONT_BOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(title)
	box.add_child(UiKit.label("После эфира", 44, Color("e8261c"), UiKit.FONT_BOLD))
	var info := "Ночей: %d · Побед: %d · Писем: %d" % [int(meta.nights), int(meta.wins), meta.letters.size()]
	box.add_child(UiKit.label(info, 26, UiKit.ASH))
	if Saves.has_run():
		var cont := UiKit.button("Продолжить ночь", true)
		cont.pressed.connect(_continue)
		box.add_child(cont)
	var new_btn := UiKit.button("Новая ночь", not Saves.has_run())
	new_btn.pressed.connect(_new_night)
	box.add_child(new_btn)
	var set_btn := UiKit.button("Настройки")
	set_btn.pressed.connect(func(): layer.add_child(SettingsMenu.new()))
	box.add_child(set_btn)
	var quit_btn := UiKit.button("Выйти")
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)
	layer.add_child(box)
	screen = box
	say(Lines.pick("night_start"))


func _new_night() -> void:
	run = Run.new_night(meta, randi(), int(meta.nights) == 0)
	_save()
	_go()


func _continue() -> void:
	var d = Saves.read(Saves.RUN)
	run = Run.from_dict(d) if d is Dictionary else null
	if run == null:
		_new_night()
		return
	_go()


## Какой экран показать по состоянию ночи.
func _go() -> void:
	_clear()
	if auto:
		print("шаг: ", ProgramGrid.TIMES[maxi(run.row, 0)], " ", run.state)
	match run.state:
		"grid":
			_show_paper()
		"theory", "segment":
			_show_panel("")
		"battle":
			_show_battle()
		_:
			_show_end()


# ---------------------------------------------------------------- газета

func _show_paper() -> void:
	stage.cut_to("paper")
	var p := PaperScreen.new()
	layer.add_child(p)
	p.show_run(run)
	p.chosen.connect(_on_chosen)
	screen = p
	say(Lines.pick("paper"))
	if auto:
		var mv: Array = run.available_moves()
		_on_chosen.call_deferred(mv[randi() % mv.size()])


func _on_chosen(ch: int) -> void:
	if not (screen is PaperScreen):
		return
	run.choose(ch)
	Sfx.play("paper", 0.6)
	(screen as PaperScreen).queue_redraw()
	(screen as PaperScreen).ink_last()
	await get_tree().create_timer(0.6 / Settings.anim_speed()).timeout
	_save()
	_go()


# ---------------------------------------------------------------- рубрики и теории

func _show_panel(note: String) -> void:
	stage.cut_to("tv")
	var p := SegmentPanel.new()
	layer.add_child(p)
	p.fit(stage.screen_rect().grow(-6))
	p.show_offer(run, note)
	p.picked.connect(_on_picked)
	screen = p
	if auto:
		var ch: Array = run.choices()
		_on_picked.call_deferred(ch[0])


func _on_picked(c: Dictionary) -> void:
	var before := run.state
	var ev := run.resolve(c)
	var note := ""
	for e in ev:
		if e.t == "line" or e.t == "deny":
			note = String(e.get("text", "Так нельзя: " + String(e.get("why", ""))))
	Sfx.play("coin" if not ev.any(func(e): return e.t == "deny") else "deny", 0.6)
	_save()
	if run.state == before and run.state == "segment" and not run.current_offer().is_empty():
		(screen as SegmentPanel).show_offer(run, note)
		if auto:
			_on_picked.call_deferred(run.choices().back())
		return
	_go()
	if note != "":
		say(note)


# ---------------------------------------------------------------- серия

func _show_battle() -> void:
	stage.cut_to("tv")
	var b: Battle = run.battle if run.battle != null else run.start_battle()
	var bs := BattleScreen.new()
	bs.tv = stage
	bs.run = run
	bs.auto = auto
	layer.add_child(bs)
	bs.start(b, run.rewinds)
	bs.finished.connect(_on_battle_done.bind(bs))
	screen = bs
	Sfx.play("crt_on", 0.5)


func _on_battle_done(_res: String, bs: BattleScreen) -> void:
	var ev := run.finish_battle(bs.b)
	for e in ev:
		if e.t == "line":
			say(String(e.text))
	_save()
	_go()


# ---------------------------------------------------------------- конец ночи

func _show_end() -> void:
	stage.cut_to("room")
	var out := Meta.after_night(meta, run.report())
	meta = out.meta
	Saves.write(Saves.META, meta)
	Saves.erase(Saves.RUN)
	var won := run.result == "win"
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(0.95))
	panel.position = Vector2(260, 80)
	panel.custom_minimum_size = Vector2(1400, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UiKit.label("КОНЕЦ ЭФИРА" if won else "ПЛЁНКУ ЗАЖЕВАЛО", 64, Color.WHITE, UiKit.FONT_BOLD))
	box.add_child(UiKit.label(Lines.pick("night_won" if won else "night_lost"), 30, Color("bfe0ff")))
	var rep := run.report()
	box.add_child(UiKit.label("Дошли до %s · фантиков: %d · серий выиграно: %d" % [rep.time, int(rep.fantiki),
		int(run.stats.wins)], 26, UiKit.ASH))
	for e in out.events:
		if e.has("text"):
			box.add_child(UiKit.label(String(e.text), 26, Color("ffd166")))
	if not out.letters.is_empty():
		box.add_child(UiKit.label("ПИСЬМА ЗРИТЕЛЕЙ", 34, Color.WHITE, UiKit.FONT_BOLD))
		for l in out.letters:
			var who := String(l.get("from", l.get("author", "")))
			var txt := String(l.get("text", ""))
			box.add_child(UiKit.label("«%s»%s" % [txt, (" — " + who) if who != "" else ""], 24, UiKit.BONE))
			box.add_child(UiKit.label("Открыто: " + String(l.get("note", "")), 22, Color("8cff9e")))
	var again := UiKit.button("Новая ночь", true)
	again.pressed.connect(_new_night)
	box.add_child(again)
	var menu_btn := UiKit.button("В меню")
	menu_btn.pressed.connect(_show_menu)
	box.add_child(menu_btn)
	layer.add_child(panel)
	screen = panel
	if auto:
		print("НОЧЬ ОКОНЧЕНА: ", run.result, " ", rep.time)
		get_tree().quit.call_deferred()
