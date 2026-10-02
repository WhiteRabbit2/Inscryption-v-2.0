class_name ProgramGrid
extends RefCounted
## «Программа передач» (§13): газета на ковре, 3 канала (столбцы) × 9 получасов (строки), 23:00…03:00.
## Каждую строку игрок обводит одну передачу: можно остаться на своём канале или перейти на соседний.
##
## generate() возвращает обычный словарь (переживает JSON):
##   {"seed": "…", "channels": [названия], "rows": [[клетка × 3] × 9]}
## Клетка:
##   row, channel, time ("00:30"), kind ("episode" / "segment" / "boss"), icon (значок типа),
##   title, sub — строка газеты и мелкая подпись под ней,
##   level (0–3 серия, 4 босс, -1 рубрика), night («Ночной показ (16+)»),
##   segment (id рубрики для kind == "segment"),
##   theory (id теории или ""), theory_cfg (подробности теории: blocked_lane у «Цензоров»),
##   episode (готовый сценарий серии из Episodes, уже с поправками Ночного показа), episode_id.
##
## Расписание:
##   23:00 серия-пилот (в первую ночь — обучение на всех каналах); 23:30 Розыгрыш на всех каналах;
##   00:00 серия ур. 1, на одном канале Ночной показ; 00:30 рубрика; 01:00 серия ур. 2, может быть Ночной показ;
##   01:30 рубрика, на одном канале всегда Телемагазин; 02:00 серия ур. 3; 02:30 рубрика, всегда есть Разбор;
##   03:00 «Конец эфира» — босс на всех каналах.
## Решения, где документ молчит: в одной строке рубрики не повторяются (кроме 23:30); теория — не больше
## одной на строку, с вероятностью THEORY_CHANCE, только на обычной серии; серии в ночь по возможности
## не повторяются (сначала избегаем всех уже стоящих в газете, потом — хотя бы стоящих в этой строке).

const CHANNELS := 3
const TIMES := ["23:00", "23:30", "00:00", "00:30", "01:00", "01:30", "02:00", "02:30", "03:00"]
const ROWS := 9
## Кнопки на телевизоре «Рассвет». 13-го канала, где идёт «После эфира», в программе нет.
const CHANNEL_NAMES := ["Вторая кнопка", "Пятая кнопка", "Девятая кнопка"]

const SCHEDULE := [
	{"kind": "episode", "level": 0},
	{"kind": "segment", "all": "raffle"},
	{"kind": "episode", "level": 1, "night": "one", "theories": true},
	{"kind": "segment"},
	{"kind": "episode", "level": 2, "night": "maybe", "theories": true},
	{"kind": "segment", "must": "shop"},
	{"kind": "episode", "level": 3, "theories": true},
	{"kind": "segment", "must": "review"},
	{"kind": "boss", "level": 4},
]

const NIGHT_MAYBE_CHANCE := 0.5
const THEORY_CHANCE := 0.67
## Из каких рубрик набираются строки 00:30, 01:30, 02:30.
const SEGMENT_POOL := ["raffle", "shop", "review", "pirate", "sponsor", "glitch"]

const TEXT := {
	"episode": "«Кривая опушка». Серия %d",
	"episode_unnumbered": "«Кривая опушка». Внеочередная серия",
	"tutorial": "«Кривая опушка». Пилотная серия",
	"tutorial_sub": "В эфир так и не пустили. Сейчас поймёте почему",
	"night": "НОЧНОЙ ПОКАЗ (16+)",
	"night_subs": ["Серия %d. %s. Детей уложить, нервы убрать", "Серия %d. %s. Слабонервным переключить",
		"Серия %d. %s. Показ без цензуры и без совести"],
	"boss": "КОНЕЦ ЭФИРА",
	"boss_sub": "«Кривая опушка». Серия 13. В эфир не выходила",
}


## Газета на одну ночь. theories — открытые теории (null — все); пустой массив — без теорий.
static func generate(seed_value: int, first_night: bool, theories = null) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var open: Array = Theories.ids() if theories == null else (theories as Array)
	var rows := []
	var used_eps := []
	var used_theories := []
	for r in ROWS:
		var spec: Dictionary = SCHEDULE[r]
		var row: Array
		match String(spec.kind):
			"episode":
				row = _episode_row(r, spec, rng, first_night, used_eps)
			"segment":
				row = _segment_row(r, spec, rng)
			_:
				row = _boss_row(r)
		if spec.get("theories", false) and not open.is_empty() and rng.randf() < THEORY_CHANCE:
			_place_theory(row, rng, open, used_theories)
		rows.append(row)
	return {"seed": str(seed_value), "channels": CHANNEL_NAMES.duplicate(), "rows": rows}


## Куда можно пойти в следующей строке из клетки (row, channel). row = -1 — ещё ничего не выбрано: любой канал.
static func moves(row: int, channel: int) -> Array:
	if row >= ROWS - 1:
		return []
	if row < 0:
		return range(CHANNELS)
	var out := []
	for c in [channel - 1, channel, channel + 1]:
		if c >= 0 and c < CHANNELS:
			out.append(c)
	return out


static func cell(grid: Dictionary, row: int, channel: int) -> Dictionary:
	if row < 0 or row >= grid.rows.size() or channel < 0 or channel >= CHANNELS:
		return {}
	return grid.rows[row][channel]


## Номер серии «Кривой опушки» по порядку в Episodes.POOLS (пилот — 0, «Конец эфира» — 13).
static func episode_number(id: String) -> int:
	if id == Episodes.BOSS.id:
		return 13
	if id == Episodes.TUTORIAL.id:
		return 0
	var n := 0
	var levels: Array = Episodes.POOLS.keys()
	levels.sort()
	for lv in levels:
		for e in Episodes.POOLS[lv]:
			n += 1
			if e.id == id:
				return n
	return -1


# ================================================================ строки

static func _blank(row: int, ch: int) -> Dictionary:
	return {
		"row": row, "channel": ch, "time": TIMES[row], "kind": "", "icon": "", "title": "", "sub": "",
		"level": -1, "night": false, "segment": "", "theory": "", "theory_cfg": {}, "episode": {}, "episode_id": "",
	}


static func _episode_row(r: int, spec: Dictionary, rng: RandomNumberGenerator, first_night: bool, used: Array) -> Array:
	var level: int = spec.level
	var night_ch := -1
	match String(spec.get("night", "")):
		"one":
			night_ch = rng.randi_range(0, CHANNELS - 1)
		"maybe":
			if rng.randf() < NIGHT_MAYBE_CHANCE:
				night_ch = rng.randi_range(0, CHANNELS - 1)
	var row := []
	var row_ids := []
	for ch in CHANNELS:
		var c := _blank(r, ch)
		var ep: Dictionary
		if level == 0 and first_night:
			ep = Episodes.TUTORIAL.duplicate(true)
		else:
			ep = _pick_episode(level, ch == night_ch, rng, used, row_ids)
		used.append(ep.id)
		row_ids.append(ep.id)
		c.kind = "episode"
		c.level = level
		c.night = ch == night_ch
		c.episode = ep
		c.episode_id = ep.id
		_episode_texts(c, ep, rng)
		row.append(c)
	return row


## Серия через Episodes.pick, по возможности без повторов за ночь.
## Уровень пула для Ночного показа повторяет логику Episodes.pick (уровень + 1, не выше 3).
static func _pick_episode(level: int, night: bool, rng: RandomNumberGenerator, used: Array, row_ids: Array) -> Dictionary:
	var lv := clampi(level + (1 if night else 0), 0, 3)
	var ids: Array = Episodes.POOLS[lv].map(func(e): return e.id)
	var avoid: Array = []
	for attempt in [used, row_ids]:  # used уже включает row_ids
		if ids.any(func(id): return not attempt.has(id)):
			avoid = attempt
			break
	return Episodes.pick(level, rng, night, avoid)


static func _episode_texts(c: Dictionary, ep: Dictionary, rng: RandomNumberGenerator) -> void:
	var n := episode_number(ep.id)
	var base_name := String(ep.name).trim_suffix(" (16+)")
	if ep.get("tutorial", false):
		c.icon = "tutorial"
		c.title = TEXT.tutorial
		c.sub = TEXT.tutorial_sub
	elif c.night:
		c.icon = "night"
		c.title = TEXT.night
		c.sub = String(LogicUtil.pick(rng, TEXT.night_subs)) % [n, base_name]
	else:
		c.icon = "episode"
		c.title = TEXT.episode % n if n > 0 else TEXT.episode_unnumbered
		c.sub = base_name


static func _segment_row(r: int, spec: Dictionary, rng: RandomNumberGenerator) -> Array:
	var kinds := []
	if spec.has("all"):
		for ch in CHANNELS:
			kinds.append(spec.all)
	else:
		var must := String(spec.get("must", ""))
		var pool: Array = SEGMENT_POOL.duplicate()
		pool.erase(must)
		LogicUtil.shuffle(rng, pool)
		kinds = pool.slice(0, CHANNELS - (1 if must != "" else 0))
		if must != "":
			kinds.insert(rng.randi_range(0, kinds.size()), must)
	var subs_used := []
	var row := []
	for ch in CHANNELS:
		var c := _blank(r, ch)
		var kind: String = kinds[ch]
		var info: Dictionary = Segments.KINDS[kind]
		c.kind = "segment"
		c.segment = kind
		c.icon = kind
		c.title = info.title
		var subs: Array = (info.subs as Array).filter(func(s): return not subs_used.has(s))
		if subs.is_empty():
			subs = info.subs
		c.sub = LogicUtil.pick(rng, subs)
		subs_used.append(c.sub)
		row.append(c)
	return row


static func _boss_row(r: int) -> Array:
	var row := []
	for ch in CHANNELS:
		var c := _blank(r, ch)
		c.kind = "boss"
		c.icon = "boss"
		c.level = 4
		c.episode = Episodes.BOSS.duplicate(true)
		c.episode_id = Episodes.BOSS.id
		c.title = TEXT.boss
		c.sub = TEXT.boss_sub
		row.append(c)
	return row


## Метка ТЕОРИЯ на одной обычной серии строки; теории за ночь по возможности не повторяются.
static func _place_theory(row: Array, rng: RandomNumberGenerator, open: Array, used: Array) -> void:
	var cands := row.filter(func(c): return c.kind == "episode" and not c.night and int(c.level) >= 1)
	if cands.is_empty():
		return
	var c: Dictionary = LogicUtil.pick(rng, cands)
	var pool := open.filter(func(t): return not used.has(t))
	if pool.is_empty():
		pool = open.duplicate()
	var t: String = LogicUtil.pick(rng, pool)
	used.append(t)
	c.theory = t
	if t == "censors":
		c.theory_cfg = {"blocked_lane": rng.randi_range(0, Battle.LANES - 1)}
