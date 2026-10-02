class_name TestCase
extends RefCounted
## Минимальная основа для тестов: методы test_* в наследниках, проверки копят ошибки.

var failures: PackedStringArray = []


func check(cond: bool, msg := "условие не выполнено") -> void:
	if not cond:
		failures.append(msg)


func check_eq(a, b, msg := "") -> void:
	if a != b:
		failures.append("%s ожидалось %s, получено %s" % [msg, str(b), str(a)])
