# gdlint: disable=max-line-length
class_name LowResView
extends Control
## 3D рисуется в маленьком разрешении (по умолчанию 360 строк) и растягивается без сглаживания,
## поверх — постобработка. Интерфейс рисуется отдельно, в полном разрешении, поэтому текст чёткий.

const POST := preload("res://src/render/post.gdshader")
## Палитра: грязные тона от черноты до кости + отдельная рампа акцентного красного.
const RAMP := ["#050507", "#0c0b0e", "#141217", "#1c191b", "#262220", "#332d26", "#433a2d", "#554834", "#6a5a3f", "#82714f", "#9c8b66", "#b6a781", "#cdc29e", "#e3dbbd"]
const ACCENT := ["#1c0607", "#430c0b", "#781712", "#ad2a1d", "#d9472e"]

@export var base_height := 360

var viewport: SubViewport
var rect: TextureRect
var _mat: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.positional_shadow_atlas_size = 2048
	viewport.audio_listener_enable_3d = true
	add_child(viewport)
	rect = TextureRect.new()
	rect.texture = viewport.get_texture()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = POST
	_mat.set_shader_parameter("palette", _palette_texture())
	_mat.set_shader_parameter("levels", float(RAMP.size()))
	_mat.set_shader_parameter("alevels", float(ACCENT.size()))
	rect.material = _mat
	add_child(rect)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not get_parent() is Control:
		# без родителя-интерфейса якоря не работают — растягиваемся на окно сами
		get_viewport().size_changed.connect(_fill_window)
		_fill_window()
	resized.connect(_fit)
	Settings.changed.connect(_apply_settings)
	_fit()
	_apply_settings()


func _process(_delta: float) -> void:
	_mat.set_shader_parameter("time_s", Time.get_ticks_msec() / 1000.0)


func _fill_window() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


## Перевод координат экрана (интерфейса) в пиксели внутреннего 3D-кадра.
func to_viewport(screen_pos: Vector2) -> Vector2:
	var local := screen_pos - global_position
	return local / size * Vector2(viewport.size)


## Обратно: из пикселей 3D-кадра в координаты интерфейса.
func to_screen(vp_pos: Vector2) -> Vector2:
	return global_position + vp_pos / Vector2(viewport.size) * size


func _fit() -> void:
	if size.y < 1.0:
		return
	var h := base_height
	var w := int(round(h * size.x / size.y))
	viewport.size = Vector2i(maxi(w, 16), h)
	_mat.set_shader_parameter("src_size", Vector2(viewport.size))


func _apply_settings() -> void:
	_mat.set_shader_parameter("effects", Settings.effects)
	_mat.set_shader_parameter("palette_mix", lerpf(0.55, 0.9, Settings.effects))


static func _palette_texture() -> ImageTexture:
	var img := Image.create(16, 2, false, Image.FORMAT_RGB8)
	for i in RAMP.size():
		img.set_pixel(i, 0, Color(RAMP[i]))
	for i in ACCENT.size():
		img.set_pixel(i, 1, Color(ACCENT[i]))
	return ImageTexture.create_from_image(img)
