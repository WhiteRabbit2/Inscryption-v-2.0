extends Node
## Настройки игрока. Хранятся в user://settings.cfg и применяются сразу.

signal changed

const PATH := "user://settings.cfg"

## Камера не качается и не плавает. По умолчанию включено: живая камера утомляет.
var calm_camera := true
## Сила плёночных эффектов: зерно, аберрация, дизеринг. 0 — чистая картинка.
var effects := 0.5
## Масштаб текста интерфейса.
var text_scale := 1.0
## Быстрые анимации боя.
var fast_animations := false
var master_volume := 0.8
var music_volume := 0.6
var sfx_volume := 0.9
var fullscreen := false

## Ускорение для автотестов (не сохраняется).
var test_speed := 1.0


func _ready() -> void:
	_ensure_buses()
	load_settings()
	apply()


func anim_speed() -> float:
	return test_speed * (1.6 if fast_animations else 1.0)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	calm_camera = cfg.get_value("view", "calm_camera", calm_camera)
	effects = clampf(cfg.get_value("view", "effects", effects), 0.0, 1.0)
	text_scale = clampf(cfg.get_value("view", "text_scale", text_scale), 0.8, 1.6)
	fast_animations = cfg.get_value("game", "fast_animations", fast_animations)
	master_volume = clampf(cfg.get_value("audio", "master", master_volume), 0.0, 1.0)
	music_volume = clampf(cfg.get_value("audio", "music", music_volume), 0.0, 1.0)
	sfx_volume = clampf(cfg.get_value("audio", "sfx", sfx_volume), 0.0, 1.0)
	fullscreen = cfg.get_value("view", "fullscreen", fullscreen)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("view", "calm_camera", calm_camera)
	cfg.set_value("view", "effects", effects)
	cfg.set_value("view", "text_scale", text_scale)
	cfg.set_value("view", "fullscreen", fullscreen)
	cfg.set_value("game", "fast_animations", fast_animations)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(PATH)


func apply() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("Sfx", sfx_volume)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	changed.emit()


func set_and_save(key: String, value) -> void:
	set(key, value)
	apply()
	save_settings()


func _ensure_buses() -> void:
	for bus_name in ["Music", "Sfx"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _set_bus_volume(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))
