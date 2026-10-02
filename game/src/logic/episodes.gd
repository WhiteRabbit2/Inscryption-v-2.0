class_name Episodes
extends RefCounted
## Сценарии серий мультсериала «Кривая опушка» (студия «Подлесок», 1991).
##
## Серия — словарь:
##   name, level (0 — пилот, 1–3 — серии ночи, 4 — босс), film (Плёнка; по умолчанию 5),
##   gaze_count (1 или 2) или gazes: [{lane, habit, dir, ...}] — см. Gaze;
##   start: [{c, lane}] — твари на экране с самого начала;
##   turns: [[{c, lane, if?, else?}, ...], ...] — наброски, которые Многоглазый рисует в каждом Монтаже
##          (turns[0] — перед первым PLAY); loop — что повторять, когда turns кончились;
##   phase2 — у босса: вторая фаза в том же формате (+ invert).
## lane: число (полоса 0–3; занята — ближайшая свободная), "open" (где твоя клетка пуста),
##   "strong" / "weak" (напротив твоего самого сильного / самого хилого), "lit" (засчитывается), "random".
## if: "you_empty:N", "you_full:N", "tape_empty:N", "turn_ge:N" — условие; не выполнено — берётся else
##   (если else нет — набросок пропускается).
## line — реплика Многоглазого перед серией.

const TUTORIAL := {
	"id": "tutorial", "name": "Пилотная серия", "level": 0, "film": 3, "gaze_count": 1, "tutorial": true,
	"gazes": [{"lane": 1, "habit": "pan", "dir": 1}],
	"turns": [[], [{"c": "bity", "lane": 3}], [], [{"c": "pen", "lane": 1}]],
	"loop": [[], [{"c": "bity", "lane": "open"}]],
	"line": "Пилотную серию в эфир так и не пустили. Сейчас поймёшь почему.",
}

const POOLS := {
	0: [
		{"id": "pervy_sneg", "name": "«Первый снег»", "level": 0,
			"turns": [[{"c": "bity", "lane": 1}], [], [{"c": "pen", "lane": 2}], [{"c": "bity", "lane": "open"}], [],
				[{"c": "klyaksa", "lane": "open"}]],
			"loop": [[{"c": "bity", "lane": "random"}], []],
			"line": "Серия первая. Снег тут нарисован прямо по плёнке. Иногда он шевелится."},
		{"id": "pen_i_druzya", "name": "«Пень и его друзья»", "level": 0,
			"start": [{"c": "pen", "lane": 0}],
			"turns": [[], [{"c": "bity", "lane": 2}], [{"c": "bity", "lane": "open"}], [], [{"c": "klyaksa", "lane": 3}]],
			"loop": [[{"c": "bity", "lane": "open"}], []],
			"line": "Главный герой этой серии — пень. Сценаристам платили за метраж."},
	],
	1: [
		{"id": "gribnoy_dozhd", "name": "«Грибной дождь»", "level": 1,
			"start": [{"c": "pen", "lane": 0}],
			"turns": [[{"c": "bity", "lane": 2}], [{"c": "klyaksa", "lane": "open"}], [],
				[{"c": "bity", "lane": "strong"}], [{"c": "skleyka", "lane": 2, "if": "you_empty:2", "else": "open"}]],
			"loop": [[{"c": "bity", "lane": "random"}], [], [{"c": "klyaksa", "lane": "open"}]],
			"line": "Грибной дождь. Грибов в кадре нет. Дождя тоже. Название — загадка."},
		{"id": "klyaksa_uletela", "name": "«Клякса улетела»", "level": 1,
			"turns": [[{"c": "klyaksa", "lane": 1}], [{"c": "klyaksa", "lane": 3}], [], [{"c": "bity", "lane": "open"}],
				[{"c": "klyaksa", "lane": "lit"}]],
			"loop": [[{"c": "bity", "lane": "random"}], []],
			"line": "Художник уронил кисточку. Клякса решила, что она персонаж."},
		{"id": "bitye_kadry", "name": "«Битые кадры»", "level": 1,
			"turns": [[{"c": "bity", "lane": 0}, {"c": "bity", "lane": 3}], [], [{"c": "pen", "lane": "strong"}],
				[{"c": "bity", "lane": "open"}], []],
			"loop": [[{"c": "bity", "lane": "open"}], []],
			"line": "Эту кассету жевал видик в общежитии. Кадры с тех пор бьются."},
	],
	2: [
		{"id": "chuzhoy_hudozhnik", "name": "«Чужой художник»", "level": 2,
			"gazes": [{"lane": 0, "habit": "pan", "dir": 1}, {"lane": 3, "habit": "closeup", "dir": -1}],
			"start": [{"c": "pen", "lane": 3}],
			"turns": [[{"c": "perevolk", "lane": 1}], [], [{"c": "bity", "lane": "open"}],
				[{"c": "skleyka", "lane": "strong"}], [], [{"c": "perevolk", "lane": "open"}]],
			"loop": [[{"c": "bity", "lane": "random"}], [{"c": "skleyka", "lane": "random"}]],
			"line": "В этой серии волка рисовал практикант. Волк до сих пор обижен."},
		{"id": "skleennaya", "name": "«Склеенная серия»", "level": 2,
			"turns": [[{"c": "skleyka", "lane": 2}], [{"c": "bity", "lane": "open"}], [],
				[{"c": "skleyka", "lane": "weak"}], [{"c": "klyaksa", "lane": "lit"}]],
			"loop": [[{"c": "skleyka", "lane": "random"}], [], [{"c": "bity", "lane": "open"}]],
			"line": "Две серии склеили скотчем. Шов видно. Шов кусается."},
		{"id": "vse_naoborot", "name": "«Всё наоборот»", "level": 2,
			"gazes": [{"lane": 1, "habit": "closeup", "dir": 1}, {"lane": 2, "habit": "pan", "dir": -1}],
			"turns": [[{"c": "negayozh", "lane": 1}], [{"c": "dvoynik", "lane": "open"}], [],
				[{"c": "dvoynik", "lane": "lit"}], [{"c": "bity", "lane": "open"}]],
			"loop": [[{"c": "dvoynik", "lane": "random"}], [], [{"c": "bity", "lane": "open"}]],
			"line": "Эту серию проявляли в другую сторону. Все персонажи немного не те."},
	],
	3: [
		{"id": "los_iz_efira", "name": "«Лось из старого эфира»", "level": 3,
			"gazes": [{"lane": 0, "habit": "closeup", "dir": 1}, {"lane": 3, "habit": "pan", "dir": -1}],
			"turns": [[{"c": "zatyorly", "lane": 1}], [{"c": "bity", "lane": "open"}], [{"c": "skleyka", "lane": "strong"}],
				[], [{"c": "perevolk", "lane": "open"}], [{"c": "zatyorly", "lane": "open"}]],
			"loop": [[{"c": "bity", "lane": "random"}], [{"c": "skleyka", "lane": "open"}], []],
			"line": "Лося затёрли до дыр. Буквально: через него видно ковёр."},
		{"id": "ryab", "name": "«Рябь»", "level": 3,
			"start": [{"c": "bity", "lane": 0}, {"c": "bity", "lane": 3}],
			"turns": [[{"c": "ryaboy", "lane": 2}], [], [{"c": "klyaksa", "lane": "lit"}],
				[{"c": "perevolk", "lane": "open"}], [], [{"c": "ryaboy", "lane": "open"}]],
			"loop": [[{"c": "bity", "lane": "open"}], [], [{"c": "skleyka", "lane": "random"}]],
			"line": "Антенну повернули не туда. Шатун пошёл рябью и не вернулся."},
		{"id": "nestiraemaya", "name": "«Нестираемая»", "level": 3,
			"gazes": [{"lane": 1, "habit": "pan", "dir": 1}, {"lane": 2, "habit": "closeup", "dir": -1}],
			"start": [{"c": "negayozh", "lane": 1}],
			"turns": [[{"c": "perevolk", "lane": 3}], [{"c": "skleyka", "lane": "open"}], [],
				[{"c": "ryaboy", "lane": 0, "if": "you_full:0", "else": "strong"}], [{"c": "dvoynik", "lane": "lit"}]],
			"loop": [[{"c": "skleyka", "lane": "random"}], [{"c": "bity", "lane": "open"}], []],
			"line": "На кассете написано «НЕ СТИРАТЬ». Её пытались. Не вышло."},
	],
}

const BOSS := {
	"id": "konets_efira", "name": "«Конец эфира»", "level": 4, "film": 6, "boss": true,
	"start": [{"c": "ulybaka", "lane": 1}],
	"gazes": [{"lane": 1, "habit": "glued", "target": "ulybaka"}, {"lane": 3, "habit": "pan", "dir": -1}],
	"turns": [[{"c": "podtanc", "lane": "open"}]],
	"loop": [[{"c": "podtanc", "lane": "open"}], [{"c": "podtanc", "lane": "lit"}]],
	"line": "Три часа ночи. А вот и наша звезда. Улыбаемся, машем.",
	"phase2": {
		"name": "Негатив", "film": 6, "invert": true,
		"gazes": [{"lane": 0, "habit": "hero"}, {"lane": 3, "habit": "hero"}],
		"start": [{"c": "aplod", "lane": 2}],
		"turns": [[{"c": "podtanc", "lane": "open"}], [{"c": "aplod", "lane": "lit"}], [{"c": "skleyka", "lane": "strong"}]],
		"loop": [[{"c": "podtanc", "lane": "open"}], [{"c": "aplod", "lane": "lit"}], []],
		"line": "Стоп-кадр. Кассета перевернулась. Теперь считается только то, чего я НЕ вижу.",
	},
}


## Серия по уровню. night — «Ночной показ (16+)»: твари из пула на уровень выше, Плёнка 7.
static func pick(level: int, rng: RandomNumberGenerator, night := false, avoid: Array = []) -> Dictionary:
	var lv := clampi(level + (1 if night else 0), 0, 3)
	var pool: Array = []
	for e in POOLS[lv]:
		if not avoid.has(e.id):
			pool.append(e)
	if pool.is_empty():
		pool = POOLS[lv]
	var ep: Dictionary = LogicUtil.pick(rng, pool).duplicate(true)
	if night:
		ep.night = true
		ep.film = 7
		ep.name = ep.name + " (16+)"
		if not ep.has("gazes"):
			ep.gazes = [{"lane": 0, "habit": "pan", "dir": 1}, {"lane": 3, "habit": "closeup", "dir": -1}]
		if level + 1 > 3:
			var c: Dictionary = ep.get("cfg", {})
			c.tape_hp = 1
			ep.cfg = c
	return ep


static func all_ids() -> Array:
	var out := [TUTORIAL.id, BOSS.id]
	for lv in POOLS:
		for e in POOLS[lv]:
			out.append(e.id)
	return out
