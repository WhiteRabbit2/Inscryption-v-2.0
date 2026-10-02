extends Node
## Сохранения в папке пользователя (user://). Всё — обычный JSON,
## любая ошибка чтения означает «сохранения нет», игра от этого не падает.

const RUN := "user://run.json"
const META := "user://meta.json"
const MEMORIES := "user://memories.json"


func read(path: String, fallback = null):
	if not FileAccess.file_exists(path):
		return fallback
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return fallback
	var data = JSON.parse_string(f.get_as_text())
	return fallback if data == null else data


func write(path: String, data) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Не удалось сохранить %s" % path)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	# запись через временный файл: если игра упадёт посреди записи, старое сохранение останется целым
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	return dir.rename(tmp.get_file(), path.get_file()) == OK


func erase(path: String) -> void:
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists(path.get_file()):
		dir.remove(path.get_file())


func has_run() -> bool:
	return FileAccess.file_exists(RUN)
