class_name Battle
extends RefCounted
## Одна серия (бой). Чистая логика: состояние + apply(action) → список событий.
##
## Поле — LANES полос × 2 ряда: you[] — твои вкладыши, tape[] — твари с плёнки, sketches[] — наброски
## (кто выйдет на следующем PLAY). Ход: ПАУЗА (выкладываешь, применяешь предметы) → PLAY:
## наброски прорисовываются → Сцена (все бьют одновременно) → Монтаж (взгляды переезжают на пунктир,
## считается новый пунктир, рисуются новые наброски) → следующая ПАУЗА.
##
## Главное правило — «Не видел — не было»: удар в пустую клетку снимает шкалу соперника, только если
## полоса засчитывается (lit). Обычно засчитываются полосы под взглядами; во 2-й фазе босса — наоборот.
##
## Действия (apply):
##   {"type": "place", "hand": i, "lane": l}
##   {"type": "item", "slot": i, "lane": l, "gaze": g, "dir": ±1}   — lane/gaze/dir по нужде предмета
##   {"type": "wink", "gaze": g, "dir": ±1}                          — «подмигивание» (глаз-перебежчик)
##   {"type": "play"}
## Перемотка — rewind(to_start) после поражения; сколько перемоток осталось на ночь, считает забег (Run).

const LANES := 4

## Параметры по умолчанию. Серия и забег переопределяют нужное через cfg.
## Что входит в снимок состояния (для перемотки и сохранения).
const _FIELDS := ["you", "tape", "sketches", "hand", "deck", "discard", "items", "gazes", "sparks", "film",
	"film_max", "sig", "sig_max", "turn", "phase", "winks", "over", "result", "stats", "_uid", "_script_pos"]

const DEFAULTS := {
	"film": 5,               # Плёнка серии
	"signal": 6,             # Сигнал игрока
	"income": 3,             # искр за ход
	"carry": 2,              # сколько искр переходит на следующий ход
	"spark_cap": 5,          # больше этого за ход не бывает (кроме Батареек)
	"opening_hand": 3,       # вкладышей в руке до первого хода (плюс 1 в начале хода); ep.hand — сценарная раздача
	"hand_max": 7,
	"offscreen": 0,          # сколько снимает удар в пустоту за кадром (0 — ничего; запасной вариант — 1)
	"squint_turn": 7,        # с этого хода «Присматривается» добавляет взгляд
	"titles_turn": 10,       # с этого хода «Титры» снимают по 1 с обеих шкал
	"invert": false,         # «Негатив»: засчитывается то, что вне кадра
	"blocked_lane": -1,      # теория «Цензоры»: сюда выкладывать нельзя
	"hidden_sketches": false,  # теория «Рисовали ночью»: набросок не говорит, кто выйдет
	"tape_hp": 0,            # теория «Один волк»: +здоровье тварям
	"tape_atk": 0,           # «Ночной показ»
	"winks": 0,              # подмигивания от глаз-перебежчиков
}

var cfg: Dictionary
var episode: Dictionary
var rng := RandomNumberGenerator.new()

var you: Array = []        # LANES × (null | карта)
var tape: Array = []       # LANES × (null | тварь)
var sketches: Array = []   # LANES × (null | {"id", "hidden"})
var hand: Array = []
var deck: Array = []       # верх колоды — конец массива
var discard: Array = []
var items: Array = []      # id предметов в карманах (null — пустой карман)
var gazes: Array = []      # см. Gaze
var sparks := 0
var film := 0
var film_max := 0
var sig := 0
var sig_max := 0
var turn := 1
var phase := 1             # фаза босса (1 или 2); у обычной серии всегда 1
var winks := 0
var over := false
var result := ""           # "" / "win" / "lose"
var stats := {"signal_lost": 0, "overkill": 0, "turns": 0, "film_hits": 0, "offscreen_hits": 0}
## Снимки для перемотки: начало 1-го хода серии (или 2-й фазы босса), 2-го, 3-го...
var snaps: Array = []
## false — снимки не копятся (копии для ботов: перемотка им не нужна, а снимок стоит времени).
var keep_snaps := true
var _uid := 0
var _script_pos := 0       # сколько ходов сценария уже нарисовано


# ================================================================ создание

## deck_cards — карты колоды забега (словари CardDB.make), pockets — карманы с предметами.
static func create(ep: Dictionary, deck_cards: Array, pockets: Array, overrides := {}, seed_value := 1) -> Battle:
	var b := Battle.new()
	b.episode = ep
	b.cfg = DEFAULTS.duplicate()
	for k in ep.get("cfg", {}):
		b.cfg[k] = ep.cfg[k]
	if ep.has("film"):
		b.cfg.film = ep.film
	for k in overrides:
		b.cfg[k] = overrides[k]
	b.rng.seed = seed_value
	b.items = pockets.duplicate()
	b.winks = int(b.cfg.winks)
	b._setup(deck_cards)
	return b


func _setup(deck_cards: Array) -> void:
	you.resize(LANES)
	tape.resize(LANES)
	sketches.resize(LANES)
	you.fill(null)
	tape.fill(null)
	sketches.fill(null)
	for c in deck_cards:
		var card: Dictionary = c.duplicate(true)
		card.uid = _next_uid()
		deck.append(card)
	_shuffle(deck)
	_stack_hand(episode.get("hand", []))
	film_max = int(cfg.film)
	film = film_max
	sig_max = int(cfg.signal)
	sig = sig_max
	_start_phase_board(episode)
	for i in int(cfg.opening_hand):
		_draw([])
	snaps = []
	_begin_pause([])


## Сценарная раздача (пилот): вкладыши с этими id кладутся на верх колоды, чтобы прийти в руку по порядку.
## Каких нет в колоде — пропускаются.
func _stack_hand(ids: Array) -> void:
	var top := []
	for id in ids:
		for i in deck.size():
			if deck[i].id == id:
				top.append(deck.pop_at(i))
				break
	top.reverse()
	deck.append_array(top)


## Расстановка в начале серии или фазы: твари со старта, взгляды, первые наброски.
func _start_phase_board(script: Dictionary) -> void:
	for s in script.get("start", []):
		var lane: int = s.lane
		tape[lane] = _creature(s.c, lane)
	gazes = []
	for g in script.get("gazes", _default_gazes()):
		gazes.append(Gaze.make(g))
	_script_pos = 0
	_draw_sketches([])
	var taken := []
	for g in gazes:
		Gaze.plan_base(g, self, taken)
	_adjust_plans([])


func _default_gazes() -> Array:
	var n := int(episode.get("gaze_count", 2))
	if n <= 1:
		return [{"lane": 0, "habit": "pan", "dir": 1}]
	return [{"lane": 0, "habit": "pan", "dir": 1}, {"lane": LANES - 1, "habit": "pan", "dir": -1}]


func _creature(id: String, lane := 0) -> Dictionary:
	var c := CardDB.make_creature(id, int(cfg.tape_hp), int(cfg.tape_atk))
	c.uid = _next_uid()
	c.side = "tape"
	if c.badges.has("glitch"):
		c.glitch_dir = 1 if lane < LANES - 1 else -1
	return c


func _next_uid() -> int:
	_uid += 1
	return _uid


# ================================================================ запросы

## Засчитывается ли удар в пустоту в этой полосе (без учёта Тихони).
func lit(lane: int) -> bool:
	return in_frame(lane) != bool(cfg.invert)


func in_frame(lane: int) -> bool:
	for g in gazes:
		if g.lane == lane:
			return true
	return false


func planned(lane: int) -> bool:
	for g in gazes:
		if g.plan == lane:
			return true
	return false


func can_place(hand_index: int, lane: int) -> bool:
	if over or hand_index < 0 or hand_index >= hand.size() or lane < 0 or lane >= LANES:
		return false
	if you[lane] != null or lane == int(cfg.blocked_lane):
		return false
	return int(hand[hand_index].cost) <= sparks


## Все разрешённые действия сейчас (для ботов и проверки ввода).
func legal_actions() -> Array:
	var out := []
	if over:
		return out
	for i in hand.size():
		for l in LANES:
			if can_place(i, l):
				out.append({"type": "place", "hand": i, "lane": l})
	for s in items.size():
		var id = items[s]
		if id == null:
			continue
		for a in _item_targets(id, s):
			out.append(a)
	if winks > 0:
		for gi in gazes.size():
			for d in [-1, 1]:
				if Gaze.can_shift(gazes[gi], d):
					out.append({"type": "wink", "gaze": gi, "dir": d})
	out.append({"type": "play"})
	return out


func _item_targets(id: String, slot: int) -> Array:
	var out := []
	match id:
		"slipper":
			for l in LANES:
				if tape[l] != null and tape[l].hp <= 3 and not tape[l].badges.has("boss"):
					out.append({"type": "item", "slot": slot, "lane": l})
		"tape":
			for l in LANES:
				if you[l] != null:
					out.append({"type": "item", "slot": slot, "lane": l})
		"knock":
			for gi in gazes.size():
				for d in [-1, 1]:
					if Gaze.can_shift(gazes[gi], d):
						out.append({"type": "item", "slot": slot, "gaze": gi, "dir": d})
		"remote", "gum", "batteries":
			out.append({"type": "item", "slot": slot})
	return out


# ================================================================ действия

func apply(action: Dictionary) -> Array:
	var ev := []
	if over:
		return ev
	match action.get("type", ""):
		"place":
			_place(int(action.hand), int(action.lane), ev)
		"item":
			_use_item(int(action.slot), action, ev)
		"wink":
			_wink(int(action.gaze), int(action.dir), ev)
		"play":
			_play(ev)
	return ev


func _place(hi: int, lane: int, ev: Array) -> void:
	if not can_place(hi, lane):
		ev.append({"t": "deny", "why": "place"})
		return
	var card: Dictionary = hand[hi]
	hand.remove_at(hi)
	sparks -= int(card.cost)
	card.side = "you"
	card.flat = false
	you[lane] = card
	ev.append({"t": "place", "uid": card.uid, "lane": lane, "hand": hi})
	ev.append({"t": "sparks", "value": sparks})
	if card.badges.has("cameo"):
		_draw(ev)
	if CardDB.has_eye(card):
		_adjust_plans(ev)


func _use_item(slot: int, a: Dictionary, ev: Array) -> void:
	if slot < 0 or slot >= items.size() or items[slot] == null:
		ev.append({"t": "deny", "why": "item"})
		return
	var id: String = items[slot]
	var ok := false
	match id:
		"remote":
			for g in gazes:
				g.base = g.lane
				g.base_by = "remote"
			_adjust_plans(ev)
			ok = true
		"slipper":
			var l: int = a.get("lane", -1)
			if l >= 0 and l < LANES and tape[l] != null and tape[l].hp <= 3 and not tape[l].badges.has("boss"):
				var c: Dictionary = tape[l]
				tape[l] = null
				ev.append({"t": "item_hit", "item": id, "lane": l, "uid": c.uid})
				ev.append({"t": "die", "uid": c.uid, "lane": l, "side": "tape"})
				ok = true
		"tape":
			var l: int = a.get("lane", -1)
			if l >= 0 and l < LANES and you[l] != null:
				you[l].hp += 2
				ev.append({"t": "heal", "uid": you[l].uid, "lane": l, "hp": you[l].hp})
				ok = true
		"knock":
			ok = _shift_plan(int(a.get("gaze", -1)), int(a.get("dir", 0)), "knock", ev)
		"gum":
			_draw(ev)
			_draw(ev)
			ok = true
		"batteries":
			sparks += 2
			ev.append({"t": "sparks", "value": sparks})
			ok = true
	if not ok:
		ev.append({"t": "deny", "why": "item"})
		return
	items[slot] = null
	ev.push_front({"t": "item", "item": id, "slot": slot})


func _wink(gi: int, d: int, ev: Array) -> void:
	if winks <= 0 or not _shift_plan(gi, d, "wink", ev):
		ev.append({"t": "deny", "why": "wink"})
		return
	winks -= 1
	ev.push_front({"t": "wink", "left": winks})


## Сдвинуть пунктир одного взгляда на соседнюю полосу (Стукнуть, подмигивание).
func _shift_plan(gi: int, d: int, by: String, ev: Array) -> bool:
	if gi < 0 or gi >= gazes.size() or not Gaze.can_shift(gazes[gi], d):
		return false
	var g: Dictionary = gazes[gi]
	g.base = g.plan + d
	g.base_by = by
	_adjust_plans(ev)
	return true


# ================================================================ PLAY

func _play(ev: Array) -> void:
	ev.append({"t": "play", "turn": turn})
	_ink(ev)
	var res := compute_scene()
	_apply_scene(res, ev)
	if turn >= int(cfg.titles_turn):
		film -= 1
		sig -= 1
		ev.append({"t": "titles"})
		ev.append({"t": "film", "value": film, "delta": -1})
		ev.append({"t": "signal", "value": sig, "delta": -1})
	stats.turns += 1
	if film <= 0:
		stats.overkill = maxi(stats.overkill, -film)
		if phase == 1 and episode.has("phase2"):
			_start_phase2(ev)
			return
		_finish("win", ev)
		return
	if sig <= 0:
		_finish("lose", ev)
		return
	_montage(ev)
	_begin_pause(ev)


## Наброски становятся тварями (только в пустые клетки).
func _ink(ev: Array) -> void:
	for l in LANES:
		var s = sketches[l]
		if s == null:
			continue
		sketches[l] = null
		if tape[l] != null:
			ev.append({"t": "cut", "lane": l, "id": s.id})
			continue
		tape[l] = _creature(s.id, l)
		ev.append({"t": "ink", "lane": l, "uid": tape[l].uid, "id": s.id})


## Расчёт сцены без изменения состояния. Наброски считаются уже прорисованными.
## Возвращает: strikes (по порядку), dmg_you/dmg_tape (урон по полосам), film/sig (урон по шкалам),
## die_you/die_tape (полосы, где карта погибнет, без учёта «Как в мультике»),
## hidden — полосы со скрытым наброском («Рисовали ночью»): кто там выйдет, прогноз не знает и считает клетку пустой.
func compute_scene() -> Dictionary:
	var tape_row := tape.duplicate()
	var res := {
		"strikes": [], "dmg_you": [0, 0, 0, 0], "dmg_tape": [0, 0, 0, 0], "film": 0, "signal": 0,
		"die_you": [], "die_tape": [], "film_lanes": [0, 0, 0, 0], "signal_lanes": [0, 0, 0, 0], "hidden": [],
	}
	for l in LANES:
		if tape_row[l] != null or sketches[l] == null:
			continue
		if sketches[l].get("hidden", false):
			res.hidden.append(l)
		else:
			tape_row[l] = CardDB.make_creature(sketches[l].id, int(cfg.tape_hp), int(cfg.tape_atk))
	for l in LANES:
		_strikes_from(you[l], tape_row[l], l, "you", res)
		_strikes_from(tape_row[l], you[l], l, "tape", res)
	for l in LANES:
		if you[l] != null and you[l].hp - res.dmg_you[l] <= 0:
			res.die_you.append(l)
		if tape_row[l] != null and tape_row[l].hp - res.dmg_tape[l] <= 0:
			res.die_tape.append(l)
	return res


func _strikes_from(att, opp, lane: int, side: String, res: Dictionary) -> void:
	if att == null or int(att.atk) <= 0:
		return
	var times := 2 if att.badges.has("replay") else 1
	var dmg: int = att.atk + (1 if att.badges.has("star") and lit(lane) else 0)
	var foe := "tape" if side == "you" else "you"
	var flies_over: bool = att.badges.has("flying") and opp != null and not opp.badges.has("tall")
	for i in times:
		if opp != null and not flies_over:
			res["dmg_" + foe][lane] += dmg
			res.strikes.append({"side": side, "lane": lane, "target": "card", "dmg": dmg})
			if opp.badges.has("prickly"):
				res["dmg_" + side][lane] += 1
				res.strikes.append({"side": foe, "lane": lane, "target": "thorns", "dmg": 1})
			continue
		var counts: bool = lit(lane) or att.badges.has("quiet")
		var hit := dmg if counts else mini(dmg, int(cfg.offscreen))
		var scale := "film" if side == "you" else "signal"
		res[scale] += hit
		res[scale + "_lanes"][lane] += hit
		res.strikes.append({"side": side, "lane": lane, "target": scale if hit > 0 else "offscreen", "dmg": hit})


func _apply_scene(res: Dictionary, ev: Array) -> void:
	for s in res.strikes:
		ev.append({"t": "strike", "side": s.side, "lane": s.lane, "target": s.target, "dmg": s.dmg})
		if s.target == "offscreen" and s.side == "you":
			stats.offscreen_hits += 1
	for l in LANES:
		if res.dmg_you[l] > 0 and you[l] != null:
			you[l].hp -= res.dmg_you[l]
			ev.append({"t": "damage", "uid": you[l].uid, "lane": l, "side": "you", "dmg": res.dmg_you[l], "hp": you[l].hp})
		if res.dmg_tape[l] > 0 and tape[l] != null:
			tape[l].hp -= res.dmg_tape[l]
			ev.append({"t": "damage", "uid": tape[l].uid, "lane": l, "side": "tape", "dmg": res.dmg_tape[l], "hp": tape[l].hp})
	if res.film > 0:
		film -= res.film
		stats.film_hits += 1
		ev.append({"t": "film", "value": film, "delta": -res.film})
	if res.signal > 0:
		sig -= res.signal
		stats.signal_lost += res.signal
		ev.append({"t": "signal", "value": sig, "delta": -res.signal})
	# гибель: сначала твои слева направо, потом твари; потом значки «при гибели»
	var dead := []
	for side in ["you", "tape"]:
		var row: Array = you if side == "you" else tape
		for l in LANES:
			var c = row[l]
			if c == null or c.hp > 0:
				continue
			if c.badges.has("toon") and not c.get("flat", false):
				c.flat = true
				c.atk = 1
				c.hp = 1
				c.badges.erase("toon")
				ev.append({"t": "flatten", "uid": c.uid, "lane": l, "side": side})
				continue
			row[l] = null
			dead.append([side, l, c])
			ev.append({"t": "die", "uid": c.uid, "lane": l, "side": side})
	for d in dead:
		var side: String = d[0]
		var l: int = d[1]
		var c: Dictionary = d[2]
		if side == "you":
			discard.append(_restore(c))
		elif c.badges.has("static") and tape[l] == null:
			tape[l] = _creature("sneg", l)
			ev.append({"t": "snow", "lane": l, "uid": tape[l].uid})


## Погибший вкладыш уходит в сброс целым — с теми цифрами, что были в колоде.
func _restore(c: Dictionary) -> Dictionary:
	var src: Dictionary = c.get("src", {})
	var out := c.duplicate(true)
	for k in src:
		out[k] = src[k]
	out.erase("side")
	out.erase("flat")
	return out


func _finish(res: String, ev: Array) -> void:
	over = true
	result = res
	ev.append({"t": "result", "result": res})


# ================================================================ Монтаж и пауза

func _montage(ev: Array) -> void:
	ev.append({"t": "montage", "turn": turn})
	_glitch_swaps(ev)
	for i in gazes.size():
		var g: Dictionary = gazes[i]
		var from: int = g.lane
		g.lane = g.plan
		if from != g.lane:
			ev.append({"t": "gaze_move", "gaze": i, "from": from, "to": g.lane})
	turn += 1
	if turn >= int(cfg.squint_turn) and not bool(cfg.invert):
		_squint(ev)
	_draw_sketches(ev)
	var taken := []
	for g in gazes:
		Gaze.plan_base(g, self, taken)
	_adjust_plans(ev)


## «Присматривается»: добавляет неподвижный взгляд на первую полосу не в кадре.
func _squint(ev: Array) -> void:
	for l in LANES:
		if not in_frame(l):
			var g := Gaze.make({"lane": l, "habit": "fixed"})
			gazes.append(g)
			ev.append({"t": "gaze_add", "gaze": gazes.size() - 1, "lane": l})
			return


## СБОЙ: тварь меняется местами с соседней клеткой ряда плёнки.
func _glitch_swaps(ev: Array) -> void:
	var done := {}
	for l in LANES:
		var c = tape[l]
		if c == null or not c.badges.has("glitch") or done.has(c.uid):
			continue
		done[c.uid] = true
		var to: int = l + int(c.glitch_dir)
		if to < 0 or to >= LANES:
			c.glitch_dir = -int(c.glitch_dir)
			to = l + int(c.glitch_dir)
		var other = tape[to]
		tape[to] = c
		tape[l] = other
		if other != null:
			done[other.uid] = true
		ev.append({"t": "swap", "from": l, "to": to, "uid": c.uid})
		# стрелка на следующий раз: от края — разворот
		var nxt: int = to + int(c.glitch_dir)
		if nxt < 0 or nxt >= LANES:
			c.glitch_dir = -int(c.glitch_dir)


## Пунктир с учётом значков глаза: base (по привычке или после Стукнуть/Пульта) → Гляделки → Кривляка.
## Событие gaze_plan — только если пунктир или «кто сдвинул» поменялись.
func _adjust_plans(ev: Array) -> void:
	for i in gazes.size():
		var g: Dictionary = gazes[i]
		var old: int = g.plan
		var old_by: String = g.by
		g.plan = g.base
		g.by = g.base_by
		var st = you[g.lane]
		if st != null and st.badges.has("stare"):
			g.plan = g.lane
			g.by = "card:%d" % st.uid
		elif g.habit != "glued":
			for d in [-1, 1]:
				var nl: int = g.plan + d
				if nl < 0 or nl >= LANES:
					continue
				var m = you[nl]
				if m != null and m.badges.has("mug") and (you[g.plan] == null or not you[g.plan].badges.has("mug")):
					g.plan = nl
					g.by = "card:%d" % m.uid
					break
		if g.plan != old or g.by != old_by:
			ev.append({"t": "gaze_plan", "gaze": i, "lane": g.lane, "plan": g.plan, "by": g.by})


## Наброски на следующий PLAY по сценарию серии.
func _draw_sketches(ev: Array) -> void:
	var sc: Dictionary = episode if phase == 1 else episode.get("phase2", {})
	var turns: Array = sc.get("turns", [])
	var step: Array = []
	if _script_pos < turns.size():
		step = turns[_script_pos]
	else:
		var loop: Array = sc.get("loop", [])
		if not loop.is_empty():
			step = loop[(_script_pos - turns.size()) % loop.size()]
	_script_pos += 1
	for s in step:
		var want = s.get("lane", "random")
		if s.has("if") and not _cond(s["if"]):
			if not s.has("else"):
				continue
			want = s["else"]
		var lane := _pick_lane(want)
		if lane < 0:
			ev.append({"t": "cut_script", "id": s.c})
			continue
		sketches[lane] = {"id": s.c, "hidden": bool(cfg.hidden_sketches)}
		ev.append({"t": "sketch", "lane": lane, "id": s.c, "hidden": bool(cfg.hidden_sketches)})


func _cond(c) -> bool:
	# "you_empty:2" — в твоей клетке 3-й полосы пусто; "you_full:1"; "tape_empty:0"; "turn_ge:5"
	var parts := String(c).split(":")
	var arg := int(parts[1]) if parts.size() > 1 else 0
	match parts[0]:
		"you_empty":
			return you[arg] == null
		"you_full":
			return you[arg] != null
		"tape_empty":
			return tape[arg] == null and sketches[arg] == null
		"turn_ge":
			return turn >= arg
	return true


func _free(l: int) -> bool:
	return tape[l] == null and sketches[l] == null


## Полоса для наброска: число — желаемая полоса (если занята — ближайшая свободная);
## "open" — где твоя клетка пуста; "strong" — напротив самого сильного твоего; "weak" — напротив самого хилого;
## "lit" — в кадре на следующем PLAY; "random". Нет свободных — -1 (набросок вырезан).
func _pick_lane(sel) -> int:
	var free := []
	for l in LANES:
		if _free(l):
			free.append(l)
	if free.is_empty():
		return -1
	if typeof(sel) == TYPE_INT or typeof(sel) == TYPE_FLOAT:
		return _nearest_free(int(sel), free)
	var pool := []
	match String(sel):
		"open":
			for l in free:
				if you[l] == null:
					pool.append(l)
		"lit":
			for l in free:
				if lit(l):
					pool.append(l)
		"strong", "weak":
			var best := -1
			var best_v := 0
			for l in free:
				if you[l] == null:
					continue
				var v: int = you[l].atk * 10 + you[l].hp if sel == "strong" else -(you[l].hp * 10) - you[l].atk
				if best < 0 or v > best_v:
					best = l
					best_v = v
			if best >= 0:
				return best
	if pool.is_empty():
		pool = free
	return pool[rng.randi_range(0, pool.size() - 1)]


func _nearest_free(want: int, free: Array) -> int:
	var best := -1
	for l in free:
		if best < 0 or absi(l - want) < absi(best - want):
			best = l
	return best


func _begin_pause(ev: Array) -> void:
	var carry := mini(sparks, int(cfg.carry))
	sparks = mini(carry + int(cfg.income), int(cfg.spark_cap))
	ev.append({"t": "pause", "turn": turn, "sparks": sparks})
	_draw(ev)
	if keep_snaps:
		snaps.append(_snapshot())


func _draw(ev: Array) -> void:
	if hand.size() >= int(cfg.hand_max):
		return
	if deck.is_empty():
		if discard.is_empty():
			return
		deck = discard
		discard = []
		_shuffle(deck)
		ev.append({"t": "shuffle", "count": deck.size()})
	var c: Dictionary = deck.pop_back()
	if not c.has("src"):
		c.src = {"atk": c.atk, "hp": c.hp, "cost": c.cost, "badges": c.badges.duplicate()}
	hand.append(c)
	ev.append({"t": "draw", "uid": c.uid})


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


# ================================================================ босс

func _start_phase2(ev: Array) -> void:
	var p2: Dictionary = episode.phase2
	phase = 2
	turn = 1
	cfg.invert = bool(p2.get("invert", true))
	film_max = int(p2.get("film", 6))
	film = film_max
	sig = sig_max
	tape.fill(null)
	sketches.fill(null)
	ev.append({"t": "phase", "phase": 2})
	_start_phase_board(p2)
	ev.append({"t": "film", "value": film, "delta": 0})
	ev.append({"t": "signal", "value": sig, "delta": 0})
	snaps = []
	_begin_pause(ev)


# ================================================================ перемотка

## Снимки делаются в начале каждой паузы: snaps[0] — 1-й ход серии (или 2-й фазы босса), дальше по ходу.
func can_rewind() -> bool:
	return over and result == "lose" and not snaps.is_empty()


## to_start — к началу серии (у босса — к началу текущей фазы), иначе на ход назад:
## к началу хода перед тем, на котором пропал Сигнал. Счётчик перемоток ведёт забег.
func rewind(to_start: bool) -> Array:
	var idx := 0 if to_start else maxi(snaps.size() - 2, 0)
	var keep := snaps.slice(0, idx + 1)
	_load(snaps[idx])
	snaps = keep
	return [{"t": "rewind", "to_start": to_start, "turn": turn}]


# ================================================================ сохранение


func _snapshot() -> Dictionary:
	var d := {"cfg": cfg.duplicate(true), "rng_seed": str(rng.seed), "rng_state": str(rng.state)}
	for f in _FIELDS:
		var v = get(f)
		d[f] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return d


## copy = false — забрать массивы снимка как есть (снимок только что сделан и больше никому не нужен).
func _load(d: Dictionary, copy := true) -> void:
	cfg = d.cfg.duplicate(true) if copy else d.cfg
	rng.seed = int(d.rng_seed)
	rng.state = int(d.rng_state)
	for f in _FIELDS:
		var v = d[f]
		set(f, v.duplicate(true) if copy and (v is Array or v is Dictionary) else v)


func to_dict() -> Dictionary:
	var d := _snapshot()
	d.episode = episode.duplicate(true)
	d.snaps = snaps.duplicate(true)
	return d


static func from_dict(d: Dictionary) -> Battle:
	var dd: Dictionary = LogicUtil.ints(d)
	var b := Battle.new()
	b.episode = dd.episode
	b._load(dd)
	b.snaps = dd.get("snaps", [])
	return b


## Быстрая копия для ботов (без снимков перемотки и без новых снимков).
func clone() -> Battle:
	var b := Battle.new()
	b.episode = episode
	b._load(_snapshot(), false)
	b.keep_snaps = false
	return b
