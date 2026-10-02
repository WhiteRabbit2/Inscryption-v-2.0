extends Node
## Проверка газеты без главного меню: комната, ракурс «газета», ночь с парой обведённых передач.
## godot --path game res://src/dev/preview_paper.tscn -- --shot=путь.png [--steps=N] [--seed=N]

var stage: TvStage
var paper: PaperScreen
var _shot := ""
var _frames := 40


func _ready() -> void:
	var steps := 2
	var seed_value := 5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--steps="):
			steps = int(a.substr(8))
		elif a.begins_with("--seed="):
			seed_value = int(a.substr(7))
	stage = TvStage.new()
	add_child(stage)
	stage.cut_to.call_deferred("paper")
	var run := Run.new_night(Meta.new_meta(), seed_value, false)
	for i in steps:
		var mv: Array = run.available_moves()
		if mv.is_empty():
			break
		run.choose(mv[mv.size() / 2])
		# на превью рубрики и серии не играем — просто двигаемся по газете
		run.state = "grid"
	var layer := CanvasLayer.new()
	add_child(layer)
	paper = PaperScreen.new()
	layer.add_child(paper)
	paper.show_run(run)


func _process(_delta: float) -> void:
	paper.fit(stage.paper_rect().grow(-4))
	if _shot == "":
		return
	_frames -= 1
	if _frames == 0:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
