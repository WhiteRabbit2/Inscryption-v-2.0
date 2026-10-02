class_name Meta
extends RefCounted
## Мета-прогрессия между ночами (§15): глаза-перебежчики, Письма зрителей, открытия.
## Только чистые функции. Словарь meta хранит и сохраняет вызывающий (Saves), здесь его не меняют на месте.
##
## meta (new_meta()):
##   version, nights, wins — сколько ночей сыграно и выиграно;
##   eyes      — глаза-перебежчики 0..EYES_MAX, каждый даёт одно «Подмигивание» на серию;
##   best_row  — самая дальняя строка газеты, до которой доходил игрок (-1 — ещё не играл);
##   letters   — id прочитанных Писем зрителей, по порядку;
##   unlocked  — что открыли письма: {"cards": [], "items": [], "glitches": [], "theories": [], "starters": []}.
##
## Решения, где документ молчит:
##   - глаз забирается за каждую проигранную ночь (не больше 3); любая победа возвращает все глаза,
##     и после неё проигрыши снова дают глаза — это подсказка для тех, у кого не идёт;
##   - письма читаются строго по порядку LETTERS: 1 письмо, если ночь кончилась до 01:00,
##     2 — если дошёл до 01:00, 3 — если дошёл до «Конца эфира» или победил;
##   - всё, чего нет в LOCKED, открыто с первой ночи.

const VERSION := 1
const EYES_MAX := 3

## Сколько писем после ночи: [строка газеты, с которой столько читается]. 4 — 01:00, 8 — 03:00.
const LETTERS_BY_ROW := [[0, 1], [4, 2], [8, 3]]

## Ключи unlocked по виду открытия.
const KIND_KEYS := {"card": "cards", "item": "items", "glitch": "glitches", "theory": "theories", "starter": "starters"}

## Закрыто до писем. Каждое из этого открывает ровно одно письмо.
const LOCKED := {
	"cards": ["lis", "netopyr", "shatun", "kabanchik"],
	"items": ["batteries"],
	"glitches": ["chew", "rerun"],
	"theories": ["sleepy", "one_wolf"],
	"starters": ["flyers"],
}

## Стартовые наборы. items — карманы на старте (не больше 3).
const STARTERS := {
	"basic": {
		"name": "Жвачка с опушки", "cards": ["yozh", "yozh", "belka", "vorobey", "gornostay", "gornostay", "zayats", "volk"],
		"items": ["tape"], "text": "Ежи, белка, горностаи и волк. Проверено пилотом.",
	},
	"flyers": {
		"name": "Летуны", "cards": ["vorobey", "vorobey", "sova", "yozh", "yozh", "belka", "uzh", "gornostay"],
		"items": ["knock"], "text": "Воробьи, сова и все, кто бьёт поверх голов. Только бы в кадр попасть.",
	},
}

## Письма зрителей. Медленно открывают тайну студии «Подлесок» и невышедшей 13-й серии.
const LETTERS := [
	{"id": "fox", "from": "Оля, Череповец",
		"text": "Здравствуйте, Многоглазый! В детстве я больше всех любила Лису из «Кривой опушки»: она всегда знала, "
			+ "куда смотрит камера. А потом её вырезали даже из заставки. Верните Лису, пожалуйста.",
		"unlock": {"kind": "card", "id": "lis"}},
	{"id": "light", "from": "Дима, Тверь",
		"text": "Мой батя был осветителем на студии «Подлесок». Говорит, под конец снимали по ночам, и оператор "
			+ "засыпал прямо на штативе. Камера так и стояла, глядя в одну точку. Батя считает, что лучшие кадры — оттуда.",
		"unlock": {"kind": "theory", "id": "sleepy"}},
	{"id": "granny", "from": "Вера Павловна, пенсионерка",
		"text": "Внук записал мне вашу передачу. Я ничего не поняла, но батарейки в пульте теперь держу на изоленте, "
			+ "как у вас. Пульт работает. Передача — не знаю.",
		"unlock": {"kind": "item", "id": "batteries"}},
	{"id": "birds", "from": "Саша, 9 лет",
		"text": "А можно колоду из одних птиц? Я нарисовал воробья и сову, они летают прямо через экран. "
			+ "Мама говорит, так не по правилам. Многоглазый, скажите маме.",
		"unlock": {"kind": "starter", "id": "flyers"}},
	{"id": "editor", "from": "Бывший монтажёр",
		"text": "Когда «Подлесок» закрыли, плёнку порезали и клеили из обрезков новые серии. Зверей не хватало, "
			+ "так что везде вставляли одного и того же волка. Присмотритесь — это всё он.",
		"unlock": {"kind": "theory", "id": "one_wolf"}},
	{"id": "bat", "from": "Слава, Мурманск",
		"text": "В заставке «Опушки» Нетопырь висел вниз головой. Я пересматривал кассету сто раз и клянусь: "
			+ "в последней серии он висит как надо и смотрит прямо в комнату. Перемотайте, проверьте.",
		"unlock": {"kind": "card", "id": "netopyr"}},
	{"id": "thirteen", "from": "Без обратного адреса",
		"text": "На моей кассете серий не двенадцать, а тринадцать. Последняя без названия, и видик зажевал её "
			+ "на третьей минуте. Я вытащил плёнку карандашом. Мама до сих пор ищет карандаш.",
		"unlock": {"kind": "glitch", "id": "chew"}},
	{"id": "sketch", "from": "Ксения, художница фонов",
		"text": "Шатуна в сериал так и не пустили, он остался на эскизах. Наш режиссёр говорил: тринадцатую серию "
			+ "рисуют не для зрителей, а вместе с ними. Тогда я не поняла, о чём он.",
		"unlock": {"kind": "card", "id": "shatun"}},
	{"id": "live", "from": "Анонимно",
		"text": "Тринадцатая должна была идти в прямом эфире: зрители звонят в студию и подсказывают зверям, "
			+ "что делать. Вести её должен был Улыбака. В ту ночь канал закрыли ровно в три. Зато повторов — сколько угодно.",
		"unlock": {"kind": "glitch", "id": "rerun"}},
	{"id": "caller", "from": "Тот, кто звонил в ту ночь",
		"text": "Здравствуйте. В девяносто первом я полночи крутил диск телефона, чтобы попасть в тринадцатую серию. "
			+ "Не дозвонился. А вы дозвонились. Передайте Кабанчику, что я в него верил.",
		"unlock": {"kind": "card", "id": "kabanchik"}},
]

## Подпись к открытию под письмом.
const UNLOCK_NOTES := {
	"card": "Новый вкладыш в розыгрышах: %s.",
	"item": "Новый предмет в подарках: %s.",
	"glitch": "Новая помеха: «%s».",
	"theory": "Новая теория: «%s».",
	"starter": "Новый стартовый набор: «%s».",
}

const LINES := {
	"eye_taken": "Ну всё, теперь смотришь моими. Этот глаз я оставлю себе. Будет подмигивать.",
	"eye_full": "Глаз у меня и так хватает. Этот можешь оставить себе.",
	"eyes_returned": "Победа! Держи свои глаза обратно. Протри только.",
}


static func new_meta() -> Dictionary:
	return {
		"version": VERSION, "nights": 0, "wins": 0, "eyes": 0, "best_row": -1, "letters": [],
		"unlocked": {"cards": [], "items": [], "glitches": [], "theories": [], "starters": []},
	}


## Копия meta, дополненная недостающими полями (старые сохранения, JSON с дробными числами).
static func normalize(meta: Dictionary) -> Dictionary:
	var m := new_meta()
	var src: Dictionary = LogicUtil.ints(meta.duplicate(true))
	for k in m:
		if not src.has(k):
			continue
		if k == "unlocked":
			for kk in m.unlocked:
				m.unlocked[kk] = (src.unlocked.get(kk, []) as Array).duplicate()
		else:
			m[k] = src[k]
	m.version = VERSION
	return m


## Глаза-перебежчики = подмигивания на каждую серию.
static func eyes(meta: Dictionary) -> int:
	return clampi(int(meta.get("eyes", 0)), 0, EYES_MAX)


## Всё открытое к этой ночи: {"cards", "items", "glitches", "theories", "starters"} — массивы id.
static func unlocks(meta: Dictionary) -> Dictionary:
	var opened: Dictionary = normalize(meta).unlocked
	return {
		"cards": _open(CardDB.CARDS.keys(), LOCKED.cards, opened.cards),
		"items": _open(CardDB.COMMON_ITEMS, LOCKED.items, opened.items),
		"glitches": _open(Segments.GLITCHES.keys(), LOCKED.glitches, opened.glitches),
		"theories": _open(Theories.ids(), LOCKED.theories, opened.theories),
		"starters": _open(STARTERS.keys(), LOCKED.starters, opened.starters),
	}


static func _open(all: Array, locked: Array, opened: Array) -> Array:
	return all.filter(func(id): return not locked.has(id) or opened.has(id))


static func is_unlocked(meta: Dictionary, kind: String, id: String) -> bool:
	return unlocks(meta).get(KIND_KEYS.get(kind, kind), []).has(id)


static func starter_deck(set_id: String) -> Array:
	var out := []
	for id in STARTERS.get(set_id, STARTERS.basic).cards:
		out.append(CardDB.make(id))
	return out


## Карманы на старте: 3 места, пустые — null.
static func starter_pockets(set_id: String) -> Array:
	var out: Array = (STARTERS.get(set_id, STARTERS.basic).items as Array).duplicate()
	while out.size() < 3:
		out.append(null)
	return out.slice(0, 3)


## Сколько писем читается после ночи.
static func letter_count(row: int, won: bool) -> int:
	if won:
		return LETTERS_BY_ROW[-1][1]
	var n := 0
	for step in LETTERS_BY_ROW:
		if row >= int(step[0]):
			n = int(step[1])
	return maxi(n, 1)


static func letter(id: String) -> Dictionary:
	for l in LETTERS:
		if l.id == id:
			return l
	return {}


## Подпись к открытию («Новый вкладыш в розыгрышах: Лиса.»).
static func unlock_note(unlock: Dictionary) -> String:
	var id := String(unlock.id)
	var name := id
	match String(unlock.kind):
		"card":
			name = CardDB.CARDS[id].name
		"item":
			name = CardDB.ITEMS[id].name
		"glitch":
			name = Segments.GLITCHES[id].name
		"theory":
			name = Theories.THEORIES[id].name
		"starter":
			name = STARTERS[id].name
	return UNLOCK_NOTES[unlock.kind] % name


## Итог ночи. report — Run.report(): {"result": "win" | "lose", "row": строка, где кончилась ночь}.
## Возвращает {"meta": новая meta, "letters": [письма + note], "events": [...]}. Исходную meta не меняет.
## События: eye_taken {eyes, text}, eye_kept {text}, eyes_returned {count, text}, letter {id}, unlock {kind, id, note}.
static func after_night(meta: Dictionary, report: Dictionary) -> Dictionary:
	var m := normalize(meta)
	var ev := []
	var won := String(report.get("result", "")) == "win"
	var row := int(report.get("row", -1))
	m.nights += 1
	m.best_row = maxi(int(m.best_row), row)
	if won:
		m.wins += 1
		if int(m.eyes) > 0:
			ev.append({"t": "eyes_returned", "count": m.eyes, "text": LINES.eyes_returned})
		m.eyes = 0
	elif int(m.eyes) < EYES_MAX:
		m.eyes += 1
		ev.append({"t": "eye_taken", "eyes": m.eyes, "text": LINES.eye_taken})
	else:
		ev.append({"t": "eye_kept", "text": LINES.eye_full})
	var letters := []
	for i in letter_count(row, won):
		var l := _next_letter(m)
		if l.is_empty():
			break
		var u: Dictionary = l.unlock
		m.letters.append(l.id)
		var key: String = KIND_KEYS[u.kind]
		if not m.unlocked[key].has(u.id):
			m.unlocked[key].append(u.id)
		var out: Dictionary = l.duplicate(true)
		out.note = unlock_note(u)
		letters.append(out)
		ev.append({"t": "letter", "id": l.id})
		ev.append({"t": "unlock", "kind": u.kind, "id": u.id, "note": out.note})
	return {"meta": m, "letters": letters, "events": ev}


static func _next_letter(m: Dictionary) -> Dictionary:
	for l in LETTERS:
		if not m.letters.has(l.id):
			return l
	return {}
