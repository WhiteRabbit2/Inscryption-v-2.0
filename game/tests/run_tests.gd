extends SceneTree
## Запуск всех тестов без окна:
##   godot --headless --path game -s res://tests/run_tests.gd
## Код выхода 0 — всё зелёное, 1 — есть провалы.


func _initialize() -> void:
	var total := 0
	var failed := 0
	var dir := DirAccess.open("res://tests/unit")
	var files := dir.get_files() if dir else PackedStringArray()
	files.sort()
	for f in files:
		if not f.ends_with(".gd"):
			continue
		var script: GDScript = load("res://tests/unit/" + f)
		var inst = script.new()
		for m in inst.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			total += 1
			inst.failures = PackedStringArray()
			var t0 := Time.get_ticks_msec()
			inst.call(name)
			var ms := Time.get_ticks_msec() - t0
			if inst.failures.is_empty():
				print("ok    %s :: %s (%d мс)" % [f, name, ms])
			else:
				failed += 1
				print("FAIL  %s :: %s" % [f, name])
				for msg in inst.failures:
					print("        ", msg)
	print("\nТестов: %d, провалено: %d" % [total, failed])
	quit(1 if failed > 0 or total == 0 else 0)
