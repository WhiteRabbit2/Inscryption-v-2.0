class_name CardPrinter
extends Node
## «Печатный станок» для лиц карт: вёрстка из обычных элементов интерфейса (с настоящим шрифтом)
## рисуется в отдельном невидимом кадре и превращается в текстуру. Так цифры и надписи
## на картах получаются чёткими, а не из мелкого самодельного шрифта.
##
## request(key, size, build) сразу возвращает текстуру (сначала пустую), а когда кадр
## отрисуется — заполняет её. build(root: Control) должен построить вёрстку внутри root.

var _vp: SubViewport
var _queue: Array = []
var _cache := {}
var _busy := false


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(64, 64)
	add_child(_vp)


func request(key: String, size: Vector2i, build: Callable) -> ImageTexture:
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.74, 0.57, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	_queue.append({"tex": tex, "size": size, "build": build})
	return tex


## Сколько карт ещё ждёт печати.
func pending() -> int:
	return _queue.size() + (1 if _busy else 0)


func _process(_delta: float) -> void:
	if _busy or _queue.is_empty():
		return
	_print_next()


func _print_next() -> void:
	_busy = true
	var job: Dictionary = _queue.pop_front()
	for c in _vp.get_children():
		c.queue_free()
	_vp.size = job.size
	var root := Control.new()
	root.size = Vector2(job.size)
	_vp.add_child(root)
	job.build.call(root)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img and not img.is_empty() and img.get_size() == Vector2i(job.size):
		img.convert(Image.FORMAT_RGBA8)
		job.tex.update(img)
	root.queue_free()
	_busy = false
