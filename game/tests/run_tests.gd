extends SceneTree
## Запуск всех тестов без окна:
##   godot --headless --path game -s res://tests/run_tests.gd
## Код выхода 0 — всё зелёное, 1 — есть провалы.


## Ловит ошибки скриптов: тест, упавший с ошибкой посреди, иначе выглядел бы зелёным.
class ErrorCounter:
	extends Logger
	var count := 0
	var last := ""

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT or error_type == ERROR_TYPE_ERROR:
			count += 1
			last = "%s (%s:%d)" % [rationale if rationale != "" else code, file, line]

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var total := 0
	var failed := 0
	var dir := DirAccess.open("res://tests/unit")
	var files := dir.get_files() if dir else PackedStringArray()
	files.sort()
	for f in files:
		if not f.ends_with(".gd"):
			continue
		var script: GDScript = load("res://tests/unit/" + f)
		if script == null or not script.can_instantiate():
			total += 1
			failed += 1
			print("FAIL  %s :: файл не загрузился (ошибка в коде)" % f)
			continue
		var inst = script.new()
		for m in inst.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			total += 1
			inst.failures = PackedStringArray()
			var t0 := Time.get_ticks_msec()
			var errs_before := errors.count
			inst.call(name)
			var ms := Time.get_ticks_msec() - t0
			if errors.count > errs_before:
				inst.failures.append("ошибка в коде: " + errors.last)
			if inst.failures.is_empty():
				print("ok    %s :: %s (%d мс)" % [f, name, ms])
			else:
				failed += 1
				print("FAIL  %s :: %s" % [f, name])
				for msg in inst.failures:
					print("        ", msg)
	print("\nТестов: %d, провалено: %d" % [total, failed])
	quit(1 if failed > 0 or total == 0 else 0)
