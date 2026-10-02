extends Node
## Точка входа: обычный запуск — игра (Game). Режимы для проверок — ниже.
## Отладочные параметры после «--»:
##   --shot=путь.png  сохранить кадр и выйти
##   --frames=N       сколько кадров подождать перед снимком (по умолчанию 90)
##   --mode=battle    серый макет боя; --mode=tv — бой на телевизоре; --mode=room — пустая комната
##   --auto           (в игре) ночь играет сама до конца — проверка, что всё проходится
##   --ep=id          какая серия (по умолчанию первая серия 1-го уровня); --seed=N
##   --auto           бой играет сам (простой автоход); --speed=N — ускорение анимаций
##   --place=a:0,b:2  перед снимком выложить вкладыши из руки (номер в руке : полоса)

var _shot_path := ""
var _frames_left := 90


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			_frames_left = int(a.substr(9))
		elif a.begins_with("--speed="):
			Settings.test_speed = float(a.substr(8))
	var mode := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
	if mode == "battle" or mode == "tv":
		_build_battle(mode == "tv")
	elif mode == "" or mode == "game":
		add_child(Game.new())
	elif mode == "paper":
		var stage := TvStage.new()
		add_child(stage)
		stage.cut_to.call_deferred("paper")
	elif mode == "room":
		_build_sandbox()


func _process(_delta: float) -> void:
	if _shot_path.is_empty():
		return
	_frames_left -= 1
	if _frames_left == 0:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		if OS.get_cmdline_user_args().has("--debug-view"):
			var v: LowResView = get_child(0)
			print("view ", v.size, " vp ", v.viewport.size, " rect ", v.rect.size, " cam ", v.viewport.get_camera_3d())
			var vi := v.viewport.get_texture().get_image()
			print("vp image ", vi.get_size(), " center ", vi.get_pixel(vi.get_width() / 2, vi.get_height() / 2))
			vi.save_png(_shot_path.replace(".png", "-vp.png"))
		print("Снимок сохранён: ", _shot_path)
		get_tree().quit()


func _build_sandbox() -> void:
	var view := LowResView.new()
	add_child(view)
	var room := Room.new()
	view.viewport.add_child(room)
	room.screen_material.albedo_texture = Art.make_texture("volk", 8, Color("1b3a5a"))
	var cam := CameraRig.new()
	cam.fov = 52
	view.viewport.add_child(cam)
	cam.add_view("tv", Vector3(0, 1.05, 1.0), Vector3(0, 0.95, -1.6))
	cam.add_view("room", Vector3(0.4, 1.45, 2.6), Vector3(0, 0.7, -1.4))
	var which := "room"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="):
			which = a.substr(7)
	cam.set_view(which, true)
	var label := Label.new()
	label.text = "Многоглазый. После эфира — проверка комнаты"
	label.position = Vector2(40, 30)
	add_child(label)


func _build_battle(on_tv: bool) -> void:
	var ep: Dictionary = Episodes.POOLS[1][0]
	var seed_value := 1
	var place := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ep="):
			var want := a.substr(5)
			if want == Episodes.BOSS.id:
				ep = Episodes.BOSS
			elif want == Episodes.TUTORIAL.id:
				ep = Episodes.TUTORIAL
			for lv in Episodes.POOLS:
				for e in Episodes.POOLS[lv]:
					if e.id == want:
						ep = e
		elif a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--place="):
			place = a.substr(8)
	var deck := CardDB.starter_deck()
	for id in ["soroka", "motylek", "krot"]:
		deck.append(CardDB.make(id))
	var b := Battle.create(ep, deck, ["tape", "knock", "slipper"], {"winks": 1}, seed_value)
	var screen := BattleScreen.new()
	if on_tv:
		var stage := TvStage.new()
		add_child(stage)
		screen.tv = stage
		stage.room.screen_material.albedo_texture = null
		stage.room.screen_material.albedo_color = Color("101418")
	add_child(screen)
	screen.start(b)
	screen.auto = OS.get_cmdline_user_args().has("--auto")
	if place != "":
		for pair in place.split(","):
			var hl := pair.split(":")
			b.apply({"type": "place", "hand": int(hl[0]), "lane": int(hl[1])})
		screen._sync()
