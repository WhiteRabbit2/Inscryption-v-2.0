extends Node
## Точка входа. Пока — пробная сцена для проверки картинки и шрифтов.
## Отладочные параметры после «--»:
##   --shot=путь.png  сохранить кадр и выйти
##   --frames=N       сколько кадров подождать перед снимком (по умолчанию 90)

var _shot_path := ""
var _frames_left := 90


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			_frames_left = int(a.substr(9))
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
	label.text = "Стол Многоглазого — проверка комнаты"
	label.position = Vector2(40, 30)
	add_child(label)
