class_name Run
extends RefCounted
## Одна ночь эфира (§13, §6): газета-программа, серии, рубрики, Теории, перемотки, фантики.
## Чистая логика без узлов. Всё состояние — to_dict()/from_dict(), переживает JSON (вместе с идущим боем).
##
## Машина состояний (state):
##   "grid"    — газета: available_moves() — каналы следующей строки, choose(channel) — обвести передачу;
##   "theory"  — серия с меткой ТЕОРИЯ: current_offer() — две карточки, resolve({"pick": 0 | 1});
##   "battle"  — серия: start_battle() → Battle; бой ведут интерфейс или бот через Battle.apply;
##               когда b.over — finish_battle(b). Проигрыш при оставшихся перемотках — событие no_signal,
##               нужен use_rewind(b, to_start); перемоток нет — «ПЛЁНКУ ЗАЖЕВАЛО», ночь окончена;
##   "segment" — рубрика или награда после серии: current_offer(), choices(), resolve(choice) до offer.done;
##   "over"    — ночь кончилась: result "win" / "lose", report() — итог для Meta.after_night.
## После серии сначала идут награды из очереди queue (Ночной показ, Теория), потом — обратно в газету.
## Победа над боссом в 03:00 — победа в ночи.
##
## Всё случайное (газета, сиды боёв, предложения рубрик) — из rng забега, он сохраняется.

const SAVE_VERSION := 1
const REWINDS := 2
## Сложность ночи поверх сценариев (подобрано симуляцией ботами): твари бьют на 1 сильнее,
## у каждой серии на 1 Плёнки больше (кроме пилота). Пилот и обучение не трогаем.
const DIFFICULTY := {"tape_atk": 1, "film_bonus": 1}

## Фантики за серию: победа, Ночной показ (вместо обычной победы — двойные), чистая серия, удары сверх нужного.
const FANTIKI := {"win": 2, "night": 4, "clean": 1, "overkill_max": 3}

const TEXT := {
	"no_signal": "НЕТ СИГНАЛА",
	"chewed": "ПЛЁНКУ ЗАЖЕВАЛО",
	"film_break": "ОБРЫВ ПЛЁНКИ",
}

const LINES := {
	"rewind": "Перемотаем. Я тоже с первого раза не понял, что там произошло.",
	"rewind_start": "С самого начала. Делаем вид, что ничего не было.",
	"chewed": "Плёнку зажевало. Ночь окончена. Кассету не выбрасывай — пригодится.",
	"night_won": "Конец эфира. Настроечная таблица. Ты досидел — я впечатлён.",
	"night": "Ночной показ досмотрели. Нервы — ваши, награда — тоже.",
}

## Поля, которые сохраняются как есть (кроме rng и боя).
const _FIELDS := ["first_night", "starter", "unlocks", "eyes", "deck", "pockets", "fantiki", "rewinds",
	"signal_bonus", "signal_penalty", "grid", "row", "channel", "path", "state", "offer", "queue", "theory",
	"result", "flags", "seen_glitches", "stats"]

var rng := RandomNumberGenerator.new()
var seed_value := 0
var first_night := false
var starter := "basic"
var unlocks: Dictionary = {}     # Meta.unlocks() на начало ночи: что может выпасть в наградах
var eyes := 0                    # глаза-перебежчики: подмигиваний на каждую серию
var deck: Array = []             # карты колоды (CardDB.make + правки Разбора, пиратские копии)
var pockets: Array = []          # 3 кармана: id предмета или null
var fantiki := 0
var rewinds := REWINDS
var signal_bonus := 0            # Комнатная антенна
var signal_penalty := 0          # Помеха «Сосед»: −Сигнал в следующей серии
var grid: Dictionary = {}        # ProgramGrid.generate()
var row := -1                    # строка газеты (-1 — ещё ничего не обведено)
var channel := -1
var path: Array = []             # обведённые каналы по строкам
var state := "grid"
var offer: Dictionary = {}       # текущее предложение (рубрика или теория)
var queue: Array = []            # награды после серии: [{"kind": рубрика, "opts": {...}}]
var theory := ""                 # теория, выбранная для текущей серии
var battle: Battle = null        # идущий бой
var result := ""                 # "" / "win" / "lose"
var flags: Dictionary = {}       # мелкие отметки ночи (antenna — антенна уже куплена)
var seen_glitches: Array = []
var stats := {"battles": 0, "wins": 0, "rewinds_used": 0, "fantiki_earned": 0, "theories": 0, "night_shows": 0}


# ================================================================ создание

## Новая ночь. meta — Meta (глаза, открытия), first_night — в 23:00 обучение. starter — стартовый набор,
## если он открыт (иначе обычный).
static func new_night(meta: Dictionary, seed_val: int, first: bool, starter_id := "basic") -> Run:
	var r := Run.new()
	r.seed_value = seed_val
	r.rng.seed = seed_val
	r.first_night = first
	r.unlocks = Meta.unlocks(meta)
	r.eyes = Meta.eyes(meta)
	r.starter = starter_id if r.unlocks.starters.has(starter_id) else "basic"
	r.deck = Meta.starter_deck(r.starter)
	r.pockets = Meta.starter_pockets(r.starter)
	r.grid = ProgramGrid.generate(r.rng.randi(), first, r.unlocks.theories)
	return r


# ================================================================ газета

## Каналы, которые можно обвести в следующей строке.
func available_moves() -> Array:
	if state != "grid":
		return []
	return ProgramGrid.moves(row, channel)


func current_cell() -> Dictionary:
	return ProgramGrid.cell(grid, row, channel)


func choose(ch: int) -> Array:
	if not available_moves().has(ch):
		return [{"t": "deny", "why": "move"}]
	row += 1
	channel = ch
	path.append(ch)
	var cell := current_cell()
	var ev := [{"t": "move", "row": row, "channel": ch, "time": cell.time, "kind": cell.kind}]
	match String(cell.kind):
		"episode", "boss":
			if String(cell.theory) != "":
				state = "theory"
				offer = Theories.offer(cell)
				ev.append({"t": "offer", "kind": "theory", "theory": cell.theory})
			else:
				state = "battle"
				ev.append({"t": "episode", "id": cell.episode_id, "night": cell.night})
		"segment":
			_open_segment(cell.segment, {}, ev)
	return ev


# ================================================================ рубрики и теории

func current_offer() -> Dictionary:
	return offer


## Разрешённые выборы для текущего предложения (боты, проверка ввода).
func choices() -> Array:
	match state:
		"theory":
			return [{"pick": 0}, {"pick": 1}]
		"segment":
			return Segments.choices(self, offer)
	return []


func resolve(choice: Dictionary) -> Array:
	var c: Dictionary = LogicUtil.ints(choice)
	if state == "theory":
		var pick := int(c.get("pick", -1))
		if pick < 0 or pick >= offer.options.size():
			return [{"t": "deny", "why": "choice"}]
		theory = "" if offer.options[pick].id == "plain" else String(offer.theory)
		if theory != "":
			stats.theories += 1
		offer = {}
		state = "battle"
		var cell := current_cell()
		return [{"t": "theory", "theory": theory}, {"t": "episode", "id": cell.episode_id, "night": cell.night}]
	if state == "segment":
		var ev := Segments.apply(self, offer, c)
		if offer.get("done", false):
			_next(ev)
		return ev
	return [{"t": "deny", "why": "state"}]


func _open_segment(kind: String, opts: Dictionary, ev: Array) -> void:
	offer = Segments.offer(kind, self, rng, opts)
	state = "segment"
	ev.append({"t": "offer", "kind": kind, "reason": offer.reason})


## Следующая награда из очереди или обратно в газету.
func _next(ev: Array) -> void:
	if not queue.is_empty():
		var spec: Dictionary = queue.pop_front()
		_open_segment(spec.kind, spec.get("opts", {}), ev)
		return
	offer = {}
	state = "grid"
	ev.append({"t": "grid", "row": row, "moves": available_moves()})


# ================================================================ серии

## Сигнал на серию: 6 (или из серии) + антенна − помеха «Сосед», не меньше 1.
func battle_signal(ep: Dictionary) -> int:
	var base := int(ep.get("cfg", {}).get("signal", Battle.DEFAULTS.signal))
	return maxi(1, base + signal_bonus - signal_penalty)


## Собрать бой для текущей серии. Повторный вызов возвращает уже идущий бой.
func start_battle() -> Battle:
	if state != "battle":
		return null
	if battle != null:
		return battle
	var cell := current_cell()
	var ep: Dictionary = cell.episode.duplicate(true)
	var over := {}
	if theory != "":
		var prep := Theories.prepare(theory, ep, cell)
		ep = prep.ep
		over = prep.cfg
	over.signal = battle_signal(ep)
	over.winks = eyes
	if int(ep.get("level", 0)) > 0:
		over.tape_atk = int(over.get("tape_atk", ep.get("cfg", {}).get("tape_atk", 0))) + int(DIFFICULTY.tape_atk)
		over.film = int(ep.get("film", Battle.DEFAULTS.film)) + int(DIFFICULTY.film_bonus)
	signal_penalty = 0  # помеха «Сосед» действует на одну серию
	battle = Battle.create(ep, deck, pockets, over, rng.randi())
	stats.battles += 1
	return battle


## Фантики за выигранную серию (чистая функция). stats — Battle.stats.
static func fantiki_for(battle_stats: Dictionary, night: bool, theory_id := "") -> Dictionary:
	var parts := [{"why": "night" if night else "win", "n": int(FANTIKI.night if night else FANTIKI.win)}]
	if int(battle_stats.get("signal_lost", 0)) == 0:
		parts.append({"why": "clean", "n": int(FANTIKI.clean)})
	var over := mini(int(battle_stats.get("overkill", 0)), int(FANTIKI.overkill_max))
	if over > 0:
		parts.append({"why": "overkill", "n": over})
	var total := 0
	for p in parts:
		total += int(p.n)
	var mult := Theories.fantiki_mult(theory_id)
	if mult > 1:
		parts.append({"why": "theory", "n": total * (mult - 1)})
		total *= mult
	return {"total": total, "parts": parts}


## Бой окончен (b.over). Победа — фантики, награды, дальше по газете; проигрыш — перемотка или конец ночи.
func finish_battle(b: Battle) -> Array:
	if b == null:
		b = battle
	if state != "battle" or b == null or not b.over:
		return [{"t": "deny", "why": "battle"}]
	battle = b
	var ev := []
	if b.result != "win":
		if rewinds > 0:
			ev.append({"t": "no_signal", "text": TEXT.no_signal, "rewinds": rewinds})
			return ev
		pockets = _pockets_from(b)
		battle = null
		ev.append({"t": "chewed", "text": TEXT.chewed})
		ev.append({"t": "line", "text": LINES.chewed})
		_end_night("lose", ev)
		return ev
	var cell := current_cell()
	pockets = _pockets_from(b)
	battle = null
	stats.wins += 1
	ev.append({"t": "film_break", "text": TEXT.film_break})
	if cell.kind == "boss":
		ev.append({"t": "line", "text": LINES.night_won})
		_end_night("win", ev)
		return ev
	var gain := fantiki_for(b.stats, bool(cell.night), theory)
	fantiki += int(gain.total)
	stats.fantiki_earned += int(gain.total)
	ev.append({"t": "fantiki", "value": fantiki, "delta": gain.total, "why": "battle", "parts": gain.parts})
	if cell.night:
		stats.night_shows += 1
		ev.append({"t": "line", "text": LINES.night})
		queue.append({"kind": "raffle", "opts": {"rarities": ["uncommon", "rare"], "reason": "night"}})
	if theory != "":
		queue.append_array(Theories.reward_queue(theory))
	theory = ""
	_next(ev)
	return ev


## Предметы из боя возвращаются в карманы (потраченные — пустые). Неигровые id в карманы не попадают.
func _pockets_from(b: Battle) -> Array:
	var out := []
	for i in pockets.size():
		out.append(b.items[i] if i < b.items.size() else null)
	return out


func rewind_available() -> bool:
	return state == "battle" and rewinds > 0 and battle != null and battle.can_rewind()


## Перемотка после «НЕТ СИГНАЛА»: на ход назад или к началу серии (у босса — к началу текущей фазы).
func use_rewind(b: Battle, to_start: bool) -> Array:
	if b == null:
		b = battle
	if state != "battle" or b == null or rewinds <= 0 or not b.can_rewind():
		return [{"t": "deny", "why": "rewind"}]
	battle = b
	rewinds -= 1
	stats.rewinds_used += 1
	var ev := b.rewind(to_start)
	ev.append({"t": "rewinds", "value": rewinds, "delta": -1})
	ev.append({"t": "line", "text": LINES.rewind_start if to_start else LINES.rewind})
	return ev


func _end_night(res: String, ev: Array) -> void:
	state = "over"
	result = res
	offer = {}
	queue = []
	theory = ""
	ev.append({"t": "night_over", "result": res, "row": row})


func is_over() -> bool:
	return state == "over"


## Итог ночи для Meta.after_night.
func report() -> Dictionary:
	return {
		"result": result, "row": row, "time": ProgramGrid.TIMES[maxi(row, 0)], "fantiki": fantiki,
		"first_night": first_night, "stats": stats.duplicate(true), "deck_size": deck.size(),
	}


# ================================================================ сохранение

func to_dict() -> Dictionary:
	var d := {"version": SAVE_VERSION, "seed": str(seed_value), "rng": LogicUtil.rng_to_dict(rng)}
	for f in _FIELDS:
		var v = get(f)
		d[f] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	d.battle = battle.to_dict() if battle != null else null
	return d


## null — сохранение другой версии или испорчено.
static func from_dict(d: Dictionary) -> Run:
	if int(d.get("version", 0)) != SAVE_VERSION:
		return null
	var r := Run.new()
	var bd = d.get("battle", null)
	var dd: Dictionary = LogicUtil.ints(d)
	r.seed_value = int(str(dd.seed))
	LogicUtil.rng_from_dict(r.rng, dd.rng)
	for f in _FIELDS:
		if dd.has(f):
			r.set(f, dd[f])
	if bd is Dictionary:
		r.battle = Battle.from_dict(bd)
	return r
