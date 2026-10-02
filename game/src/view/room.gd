class_name Room
extends Node3D
## Комната в панельке, середина 90-х. Всё строится кодом из простых фигур и рисованных текстур.
## Свет: холодный кинескоп, тёплый фонарь за окном, зелёные цифры видика. Верхнего света нет.
##
## Система координат: игрок сидит на полу (ковре) примерно в (0, 0.9, 2.2) и смотрит на телевизор,
## телевизор стоит на тумбе у дальней стены (z ≈ -1.6).

## Материал экрана телевизора: сюда подставляется картинка «эфира» (ViewportTexture).
var screen_material: StandardMaterial3D
## Узел экрана — для выбора мышью и расчёта координат.
var screen: MeshInstance3D
## Размер экрана в метрах (ширина, высота).
var screen_size := Vector2(0.84, 0.63)
var vcr_label: Label3D
var tv_light: OmniLight3D
## Газета с программой передач на ковре (карта ночи). Размер в метрах.
var paper: MeshInstance3D
var paper_size := Vector2(0.96, 0.62)

var _vcr_blink := 0.0


func _ready() -> void:
	_build_shell()
	_build_tv_corner()
	_build_wall_carpet()
	_build_sideboard()
	_build_window()
	_build_floor_things()
	_build_lights()


func _process(delta: float) -> void:
	_vcr_blink += delta
	if vcr_label:
		vcr_label.visible = fmod(_vcr_blink, 1.0) < 0.6
	if tv_light:
		# кинескоп чуть «дышит»; в спокойном режиме почти незаметно
		var amp := 0.03 if Settings.calm_camera else 0.08
		tv_light.light_energy = 2.2 + sin(_vcr_blink * 7.0) * amp + sin(_vcr_blink * 23.0) * amp * 0.5


# ---------------------------------------------------------------- стены, пол, потолок

func _build_shell() -> void:
	var floor_mat := _mat(Color("4a3a2c"), _tex_parquet())
	_box(Vector3(8, 0.1, 8), Vector3(0, -0.05, 0), floor_mat)
	var wall_mat := _mat(Color("8a7f6a"), _tex_wallpaper())
	_box(Vector3(8, 3.2, 0.1), Vector3(0, 1.6, -2.4), wall_mat)          # дальняя
	_box(Vector3(0.1, 3.2, 8), Vector3(-2.9, 1.6, 0), wall_mat)          # левая
	_box(Vector3(0.1, 3.2, 8), Vector3(2.9, 1.6, 0), wall_mat)           # правая
	_box(Vector3(8, 0.1, 8), Vector3(0, 3.2, 0), _mat(Color("2a2622")))  # потолок
	# плинтус
	var skirting := _mat(Color("3a2b1d"))
	_box(Vector3(5.8, 0.08, 0.04), Vector3(0, 0.04, -2.33), skirting)
	# ковёр на полу — поле игры лежит на нём
	var rug := _flat_mat(_tex_carpet(Color("6e1d18"), Color("c9a25a"), 7, 128, 96))
	var r := _quad(Vector2(3.2, 2.4), Vector3(0, 0.012, 0.5), rug)
	r.rotation_degrees = Vector3(-90, 0, 0)


func _build_tv_corner() -> void:
	# тумба
	var wood := _mat(Color("5a3c25"), _tex_veneer())
	_box(Vector3(1.5, 0.55, 0.6), Vector3(0, 0.275, -1.95), wood)
	_box(Vector3(1.46, 0.02, 0.02), Vector3(0, 0.3, -1.64), _mat(Color("2a1d12")))
	# видик
	var vcr := _box(Vector3(0.9, 0.11, 0.42), Vector3(0, 0.61, -1.9), _mat(Color("1b1a1a")))
	vcr.name = "VCR"
	_box(Vector3(0.36, 0.04, 0.01), Vector3(-0.15, 0.615, -1.685), _mat(Color("050505")))  # щель кассеты
	var display := _box(Vector3(0.2, 0.05, 0.01), Vector3(0.24, 0.615, -1.684), _mat(Color("071a0c")))
	display.name = "VcrDisplay"
	vcr_label = Label3D.new()
	vcr_label.text = "00:00"
	vcr_label.font = UiKit.FONT_BOLD
	vcr_label.font_size = 32
	vcr_label.pixel_size = 0.0012
	vcr_label.modulate = Color("5dff7a")
	vcr_label.outline_size = 0
	vcr_label.shaded = false
	vcr_label.position = Vector3(0.24, 0.615, -1.678)
	add_child(vcr_label)
	# телевизор: корпус под дерево, серый кант, выпуклый экран
	var tv := Node3D.new()
	tv.name = "TV"
	tv.position = Vector3(0, 0.67, -1.95)
	add_child(tv)
	var shell := _mat(Color("6b4a2e"), _tex_veneer())
	_box(Vector3(1.12, 0.86, 0.72), Vector3(0, 0.43, 0), shell, tv)
	_box(Vector3(0.98, 0.76, 0.04), Vector3(-0.04, 0.44, 0.36), _mat(Color("2c2c2a")), tv)  # рамка
	_box(Vector3(0.12, 0.6, 0.02), Vector3(0.48, 0.42, 0.365), _mat(Color("8f8a7c")), tv)   # панель кнопок
	for i in 3:
		var knob := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.025
		cyl.bottom_radius = 0.03
		cyl.height = 0.03
		cyl.radial_segments = 8
		knob.mesh = cyl
		knob.rotation_degrees = Vector3(90, 0, 0)
		knob.position = Vector3(0.48, 0.62 - i * 0.12, 0.385)
		knob.material_override = _mat(Color("1a1a1a"))
		tv.add_child(knob)
	var brand := Label3D.new()
	brand.text = "РАССВЕТ"
	brand.font = UiKit.FONT_BOLD
	brand.font_size = 24
	brand.pixel_size = 0.0011
	brand.modulate = Color("c8b88a")
	brand.position = Vector3(-0.04, 0.08, 0.385)
	tv.add_child(brand)
	# экран: слегка выпуклая плоскость, светится картинкой эфира
	screen = MeshInstance3D.new()
	screen.name = "Screen"
	var q := QuadMesh.new()
	q.size = screen_size
	screen.mesh = q
	screen.position = Vector3(-0.04, 0.44, 0.381)
	screen_material = StandardMaterial3D.new()
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.albedo_color = Color(0.85, 0.9, 1.0)
	screen_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen.material_override = screen_material
	tv.add_child(screen)
	# антенна-«рога»
	for s in [-1, 1]:
		var rod := _box(Vector3(0.012, 0.55, 0.012), Vector3(s * 0.12, 1.1, -0.05), _mat(Color("9a9a90")), tv)
		rod.rotation_degrees = Vector3(0, 0, -s * 28)
	_box(Vector3(0.18, 0.05, 0.12), Vector3(0, 0.885, -0.05), _mat(Color("1a1a1a")), tv)


func _build_wall_carpet() -> void:
	# ковёр на левой стене — бордовый с орнаментом
	var carpet := _flat_mat(_tex_carpet(Color("7a1c1a"), Color("d4b06a"), 11, 128, 84))
	var c := _quad(Vector2(2.6, 1.7), Vector3(-2.84, 1.55, -0.6), carpet)
	c.rotation_degrees = Vector3(0, 90, 0)
	c.name = "WallCarpet"


func _build_sideboard() -> void:
	# сервант справа: шкаф со стеклом и хрусталём
	var wood := _mat(Color("4a2e1a"), _tex_veneer())
	var x := 2.35
	_box(Vector3(0.9, 1.9, 0.5), Vector3(x, 0.95, -1.2), wood)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.7, 0.75, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.metallic_specular = 0.9
	_box(Vector3(0.02, 0.8, 0.44), Vector3(x - 0.46, 1.4, -1.2), glass)
	var crystal := _mat(Color("c6d2d8"))
	crystal.roughness = 0.15
	for i in 4:
		var g := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.045
		cm.bottom_radius = 0.025
		cm.height = 0.14
		cm.radial_segments = 6
		g.mesh = cm
		g.material_override = crystal
		g.position = Vector3(x - 0.1, 1.15 + (i / 2) * 0.32, -1.32 + (i % 2) * 0.22)
		add_child(g)


func _build_window() -> void:
	# окно на правой стене, за ним ночь и фонарь
	var frame := _mat(Color("cfc7b4"))
	_box(Vector3(0.06, 1.3, 1.2), Vector3(2.86, 1.75, 1.0), _mat(Color("0b1420")))
	_box(Vector3(0.08, 1.36, 0.06), Vector3(2.84, 1.75, 0.4), frame)
	_box(Vector3(0.08, 1.36, 0.06), Vector3(2.84, 1.75, 1.6), frame)
	_box(Vector3(0.08, 0.06, 1.26), Vector3(2.84, 1.1, 1.0), frame)
	_box(Vector3(0.08, 0.06, 1.26), Vector3(2.84, 2.4, 1.0), frame)
	_box(Vector3(0.08, 1.3, 0.04), Vector3(2.84, 1.75, 1.0), frame)
	var tulle := StandardMaterial3D.new()
	tulle.albedo_color = Color(0.85, 0.85, 0.8, 0.35)
	tulle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tulle.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box(Vector3(0.01, 1.6, 1.5), Vector3(2.78, 1.7, 1.0), tulle)


func _build_floor_things() -> void:
	# газета-разворот с программой передач: печать рисует интерфейс поверх, здесь — бумага
	paper = MeshInstance3D.new()
	paper.name = "Paper"
	var pq := QuadMesh.new()
	pq.size = paper_size
	paper.mesh = pq
	paper.rotation_degrees = Vector3(-90, 0, 0)
	paper.position = Vector3(0.0, 0.016, 0.95)
	paper.material_override = _flat_mat(_tex_newsprint())
	add_child(paper)
	# пульт и тапок рядом с местом игрока
	var remote := _box(Vector3(0.08, 0.025, 0.22), Vector3(1.05, 0.035, 1.35), _mat(Color("222222")))
	remote.rotation_degrees = Vector3(0, 20, 0)
	remote.name = "Remote"
	var slipper := _box(Vector3(0.12, 0.05, 0.3), Vector3(-1.2, 0.04, 1.5), _mat(Color("6a2a2a")))
	slipper.rotation_degrees = Vector3(0, -35, 0)


func _build_lights() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("1b2433")
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	# кинескоп — главный холодный свет
	tv_light = OmniLight3D.new()
	tv_light.light_color = Color("9ec3ff")
	tv_light.light_energy = 2.2
	tv_light.omni_range = 5.5
	tv_light.omni_attenuation = 1.2
	tv_light.position = Vector3(-0.04, 1.1, -1.2)
	tv_light.shadow_enabled = true
	tv_light.shadow_opacity = 0.55
	add_child(tv_light)
	# фонарь за окном — тёплый косой луч
	var lamp := SpotLight3D.new()
	lamp.light_color = Color("ffb36b")
	lamp.light_energy = 3.0
	lamp.spot_range = 8.0
	lamp.spot_angle = 22.0
	lamp.position = Vector3(4.0, 3.2, 1.0)
	add_child(lamp)
	lamp.look_at(Vector3(0.5, 0.0, 0.6))
	# зелёный отсвет видика
	var vcr_glow := OmniLight3D.new()
	vcr_glow.light_color = Color("5dff7a")
	vcr_glow.light_energy = 0.25
	vcr_glow.omni_range = 0.6
	vcr_glow.position = Vector3(0.24, 0.62, -1.6)
	add_child(vcr_glow)


# ---------------------------------------------------------------- помощники

func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	(parent if parent else self).add_child(m)
	return m


func _mat(color: Color, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	m.metallic_specular = 0.2
	if tex:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(1, 1, 1)
	return m


func _quad(size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	m.mesh = q
	m.position = pos
	m.material_override = mat
	add_child(m)
	return m


## Материал для вещей, на которые текстура ложится один раз целиком (ковры).
func _flat_mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 1.0
	m.metallic_specular = 0.1
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m


static func _tex_carpet(base: Color, gold: Color, seed_value: int, w: int, h: int) -> ImageTexture:
	# орнамент: ромбы-медальоны, кайма, «глазки» в розетках
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var dark := base.darkened(0.45)
	for y in h:
		for x in w:
			var c := base
			var dx := absf(x - w / 2.0) / (w / 2.0)
			var dy := absf(y - h / 2.0) / (h / 2.0)
			var d := dx + dy
			if fmod(d * 6.0, 1.0) < 0.18:
				c = gold.darkened(0.25)
			elif fmod(d * 6.0, 1.0) < 0.32:
				c = dark
			if x < 5 or y < 5 or x > w - 6 or y > h - 6:
				c = dark
			if (x % 24 == 12 and y % 24 == 12):
				c = gold
			c = c.darkened(r.randf() * 0.12)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func _tex_newsprint() -> ImageTexture:
	# серая газетная бумага с колонками «текста» и сгибом посередине
	var w := 192
	var h := 124
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = 13
	for y in h:
		for x in w:
			var c := Color("cfc8b4").darkened(r.randf() * 0.06)
			if absi(x - w / 2) <= 0:
				c = c.darkened(0.25)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func _tex_wallpaper() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = 4
	for y in 64:
		for x in 64:
			var c := Color("8c8470")
			if x % 16 < 2:
				c = Color("6e6656")
			if (x % 16 == 8) and (y % 16 > 4 and y % 16 < 12):
				c = Color("a0977f")
			img.set_pixel(x, y, c.darkened(r.randf() * 0.08))
	return ImageTexture.create_from_image(img)


static func _tex_veneer() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = 2
	for y in 64:
		var band := sin(y * 0.4 + sin(y * 0.07) * 3.0) * 0.08
		for x in 64:
			img.set_pixel(x, y, Color("8a5a35").darkened(0.1 + band + r.randf() * 0.05))
	return ImageTexture.create_from_image(img)


static func _tex_parquet() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = 6
	for y in 64:
		for x in 64:
			var block := (int(x / 16.0) + int(y / 16.0)) % 2
			var c := Color("6b4c33") if block == 0 else Color("5c3f29")
			if x % 16 == 0 or y % 16 == 0:
				c = Color("2e2015")
			img.set_pixel(x, y, c.darkened(r.randf() * 0.1))
	return ImageTexture.create_from_image(img)
