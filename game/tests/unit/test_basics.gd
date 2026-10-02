extends TestCase
## Проверки служебных частей: выбор мышью и рисунки зверей.


func test_ray_hits_box_from_front() -> void:
	var t := Picker._ray_box(Vector3(0, 0, 5), Vector3(0, 0, -1), Vector3(1, 1, 1))
	check(absf(t - 4.0) < 0.001, "луч должен попасть в коробку на расстоянии 4, а не %s" % t)


func test_ray_misses_box_to_the_side() -> void:
	check(Picker._ray_box(Vector3(3, 0, 5), Vector3(0, 0, -1), Vector3(1, 1, 1)) < 0.0, "луч сбоку не должен попадать")


func test_ray_from_inside_box() -> void:
	check(Picker._ray_box(Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 1, 1)) >= 0.0, "луч изнутри коробки — попадание")


func test_every_art_has_ink() -> void:
	for id in Art.ARTS:
		var g := Art.raster(id)
		var ink := 0
		for v in g:
			if v != 0:
				ink += 1
		check(ink > 25, "рисунок %s почти пустой (%d пикселей)" % [id, ink])
