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
		print("Снимок сохранён: ", _shot_path)
		get_tree().quit()


func _build_sandbox() -> void:
	var view := LowResView.new()
	add_child(view)
	var world := Node3D.new()
	view.viewport.add_child(world)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.3, 3.5)
	cam.fov = 50
	world.add_child(cam)
	cam.look_at(Vector3(0, 0, -0.5))
	var table := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(7.4, 5.8)
	table.mesh = pm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color("5b4632")
	tm.roughness = 1.0
	table.material_override = tm
	world.add_child(table)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 5, -0.1)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.spot_range = 14
	spot.spot_angle = 40
	spot.light_energy = 6
	spot.shadow_enabled = true
	world.add_child(spot)
	for i in 4:
		var card := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.8, 1.125)
		card.mesh = q
		card.rotation_degrees = Vector3(-90, 0, 0)
		card.position = Vector3(-1.56 + i * 1.04, 0.01, 1.2)
		var cm := StandardMaterial3D.new()
		cm.albedo_texture = Art.make_texture(["volk", "sova", "gadyuka", "polevka"][i], 4, Color("cbbd92"))
		cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		card.material_override = cm
		world.add_child(card)
	var label := Label.new()
	label.text = "Стол Многоглазого — проверка шрифта: Весы. Перевесишь на пять — победа."
	label.position = Vector2(40, 30)
	add_child(label)
