class_name Theories
extends RefCounted
## Теории Многоглазого (§13). С 00:00 на некоторых сериях в газете стоит метка «ТЕОРИЯ».
## Перед такой серией лежат две карточки: «Обычный просмотр» или теория — особое правило и награда получше.
##
## Теория меняет серию двумя путями: через cfg боя (overrides для Battle.create) и через сам сценарий
## (например, привычки взглядов). Награда — множитель фантиков и/или рубрика после победы (очередь Run.queue).
## Решение, где документ молчит: теории не ставятся на «Ночной показ» и на босса — там своих сложностей хватает.

const PLAIN := {
	"id": "plain", "name": "Обычный просмотр", "rule": "Серия как есть, без фокусов.", "reward": "Обычная награда.",
	"line": "Без теорий? Скучно, зато честно.",
}

## rule у «Цензоров» — формат с номером вырезанной полосы (1–4).
const THEORIES := {
	"censors": {
		"name": "Эту серию резали цензоры", "rule": "В %d-ю полосу выкладывать нельзя: её вырезали.",
		"reward": "Фантики ×2.",
		"line": "Тут явно что-то вырезали. Я знаю что. А вы — нет.",
	},
	"night_ink": {
		"name": "Мультик рисовали ночью", "rule": "Наброски показывают, где выйдет тварь, но не какая.",
		"reward": "Предмет на выбор.",
		"line": "Художники рисовали без света. Видно, что кто-то есть. Не видно, кто.",
	},
	"one_wolf": {
		"name": "Все звери тут — один волк", "rule": "У тварей +1 здоровья.",
		"reward": "Редкий вкладыш на выбор.",
		"line": "Присмотритесь: это один и тот же волк в разных шапках. Живучий, зараза.",
	},
	"sleepy": {
		"name": "Оператор уснул", "rule": "Взгляды стоят на месте 3 хода, потом прыгают на 2 полосы.",
		"reward": "Бесплатный Разбор.",
		"line": "Оператор уснул на штативе. Камера смотрит в одну точку. Как и он.",
	},
}

## Множитель фантиков за победу.
const FANTIKI_MULT := {"censors": 2}

## Рубрики-награды после победы (в формате очереди Run.queue).
const REWARDS := {
	"night_ink": [{"kind": "sponsor", "opts": {"reason": "theory"}}],
	"one_wolf": [{"kind": "raffle", "opts": {"rarities": ["rare"], "reason": "theory"}}],
	"sleepy": [{"kind": "review", "opts": {"free": true, "reason": "theory"}}],
}


static func ids() -> Array:
	return THEORIES.keys()


## Правило теории с подставленными подробностями клетки газеты (вырезанная полоса и т. п.).
static func rule_text(id: String, cell := {}) -> String:
	var t: Dictionary = THEORIES.get(id, PLAIN)
	if id == "censors":
		return t.rule % (blocked_lane(cell) + 1)
	return t.rule


static func blocked_lane(cell: Dictionary) -> int:
	return int(cell.get("theory_cfg", {}).get("blocked_lane", 0))


## Две карточки перед серией: options[0] — обычный просмотр, options[1] — теория. Выбор: {"pick": 0 | 1}.
static func offer(cell: Dictionary) -> Dictionary:
	var id: String = cell.get("theory", "")
	var t: Dictionary = THEORIES[id]
	var plain := PLAIN.duplicate()
	var card := {
		"id": id, "name": t.name, "rule": rule_text(id, cell), "reward": t.reward, "line": t.line,
	}
	if id == "censors":
		card.blocked_lane = blocked_lane(cell)
	return {"kind": "theory", "theory": id, "options": [plain, card], "done": false}


## Готовит серию под теорию: {"ep": изменённая копия серии, "cfg": overrides для Battle.create}.
static func prepare(id: String, ep: Dictionary, cell := {}) -> Dictionary:
	var e: Dictionary = ep.duplicate(true)
	var cfg := {}
	match id:
		"censors":
			cfg.blocked_lane = blocked_lane(cell)
		"night_ink":
			cfg.hidden_sketches = true
		"one_wolf":
			# складывается с «Ночным показом» 3-го уровня, если он уже дал тварям здоровье
			cfg.tape_hp = int(e.get("cfg", {}).get("tape_hp", 0)) + 1
		"sleepy":
			e.gazes = sleepy_gazes(e)
	return {"ep": e, "cfg": cfg}


## Взгляды серии с привычкой «Оператор уснул» (стоят 3 хода, прыгают на 2), с теми же полосами и сторонами.
static func sleepy_gazes(ep: Dictionary) -> Array:
	var src: Array = ep.get("gazes", [])
	if src.is_empty():
		if int(ep.get("gaze_count", 2)) <= 1:
			src = [{"lane": 0, "dir": 1}]
		else:
			src = [{"lane": 0, "dir": 1}, {"lane": Battle.LANES - 1, "dir": -1}]
	var out := []
	for g in src:
		out.append({"lane": int(g.get("lane", 0)), "habit": "sleepy", "dir": int(g.get("dir", 1))})
	return out


static func fantiki_mult(id: String) -> int:
	return int(FANTIKI_MULT.get(id, 1))


static func reward_queue(id: String) -> Array:
	return (REWARDS.get(id, []) as Array).duplicate(true)
