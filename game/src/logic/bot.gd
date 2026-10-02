class_name Bot
extends RefCounted
## Боты для проверки баланса (дизайн §17). Чистая логика, без узлов.
##
## Простой — выкладывает самое дорогое, что по карману, в случайную пустую клетку, первым делом
##   закрывает тварей и наброски; предметы — только самые очевидные, глаз-перебежчик не трогает.
## Умный — перебирает раскладки на ход вперёд с учётом текущего кадра и пунктира:
##   1) быстрая оценка по полосам (полосы в сцене независимы: один compute_scene на тип вкладыша);
##   2) лучшие BEAM раскладок (+ лучшая с каждым вкладышем) честно проигрываются на копии боя через PLAY;
##   3) к двум лучшим пробуется по одному предмету или подмигиванию;
##   4) итог хода оценивается: Плёнка, Сигнал, звери на поле, прогноз следующей сцены по новому кадру.
## Бот не подглядывает: новые наброски и вытянутые вкладыши в оценку не входят (только их число).
##
## Ход без выбора (no_choice): (1) кроме PLAY делать нечего, или (2) все разумные варианты — с оценкой
##   не хуже лучшей на MARGIN — ведут к одному и тому же итогу хода (одинаковое поле, шкалы, рука, искры).
##   То есть либо выбора нет, либо он ничего не меняет, либо лучший ход очевиден с большим отрывом.
##
## Если ход добирает вкладыш (Белка-камео, Жвачка), список действий обрывается на нём: новый вкладыш
## ещё не известен. play_battle тогда зовёт бота ещё раз в той же паузе.

const W_FILM := 10.0       # 1 Плёнки
const W_SIG := 11.0        # 1 Сигнала
const DANGER := 6.0        # Сигнал ниже 3 — каждая единица дороже
const W_BOARD := 1.0       # зверь на поле (по _card_val)
const W_TAPE := 1.2        # тварь на плёнке (по _creature_val), со знаком минус
const W_NEXT := 0.5        # вес прогноза следующей сцены
const W_SPARK := 2.5       # искра, донесённая до следующего хода
const W_HAND := 1.0        # вкладыш в руке
const W_FREE := 9.0        # пустая своя клетка: место для блокера или зверя получше (поле не «запирается»)
const ITEM_HOLD := 8.0     # предмет в кармане (зря не тратим)
const WINK_HOLD := 2.0     # подмигивание (на серию, тратить не жалко)
const BEAM := 12           # сколько раскладок проигрывать честно
const ITEM_PLANS := 2      # к скольким лучшим раскладкам пробовать предметы
const MARGIN := 5.0        # «разумный вариант» — не хуже лучшего на столько
const SIMPLE_ITEMS := ["tape", "slipper", "gum", "batteries"]


# ================================================================ простой бот

## Действия на текущую паузу (без финального PLAY).
static func simple_turn(b: Battle, rng: RandomNumberGenerator) -> Array:
	var out := []
	if b.over:
		return out
	var c := b.clone()
	for guard in 8:
		var hi := _priciest(c, rng)
		if hi < 0:
			break
		var lanes := []
		var threat := []
		for l in Battle.LANES:
			if c.can_place(hi, l):
				lanes.append(l)
				if c.tape[l] != null or c.sketches[l] != null:
					threat.append(l)
		if lanes.is_empty():
			break
		var pool: Array = threat if not threat.is_empty() else lanes
		var a := {"type": "place", "hand": hi, "lane": LogicUtil.pick(rng, pool)}
		out.append(a)
		c.apply(a)
	for a in _simple_items(c):
		out.append(a)
		c.apply(a)
	return out


## Индекс самого дорогого вкладыша, который по карману (при равенстве — случайный).
static func _priciest(c: Battle, rng: RandomNumberGenerator) -> int:
	var best := []
	var best_cost := -1
	for i in c.hand.size():
		var cost := int(c.hand[i].cost)
		if cost > c.sparks:
			continue
		if cost > best_cost:
			best_cost = cost
			best = [i]
		elif cost == best_cost:
			best.append(i)
	return -1 if best.is_empty() else int(LogicUtil.pick(rng, best))


## Очевидные предметы: изолента — тому, кто по прогнозу погибнет; тапок — самой злой твари, которая
## бьёт в пустую клетку; жвачка — когда рука пуста; батарейки — когда не хватает на вкладыш.
static func _simple_items(c: Battle) -> Array:
	var out := []
	var fc := c.compute_scene()
	for s in c.items.size():
		var id = c.items[s]
		if id == null or not SIMPLE_ITEMS.has(id):
			continue
		match id:
			"tape":
				if not fc.die_you.is_empty():
					out.append({"type": "item", "slot": s, "lane": fc.die_you[0]})
			"slipper":
				var best := -1
				for l in Battle.LANES:
					var t = c.tape[l]
					if t != null and c.you[l] == null and t.hp <= 3 and not t.badges.has("boss") and t.atk > 0:
						if best < 0 or t.atk > c.tape[best].atk:
							best = l
				if best >= 0:
					out.append({"type": "item", "slot": s, "lane": best})
			"gum":
				if c.hand.is_empty() and c.deck.size() + c.discard.size() > 0:
					out.append({"type": "item", "slot": s})
			"batteries":
				for card in c.hand:
					if int(card.cost) > c.sparks and int(card.cost) <= c.sparks + 2:
						out.append({"type": "item", "slot": s})
						break
		if not out.is_empty():
			break  # не больше одного предмета за паузу
	return out


# ================================================================ умный бот

static func smart_turn(b: Battle, rng: RandomNumberGenerator, rank := 0) -> Array:
	return analyze(b, rng, rank).actions


## Полный разбор паузы: {actions, pass, no_choice, options, score, gap}.
## options — сколько различных по итогу вариантов не хуже лучшего на MARGIN; gap — отрыв лучшего от второго.
## rank — какой по счёту из различных по итогу вариантов взять (0 — лучший; после перемотки — следующий).
static func analyze(b: Battle, rng: RandomNumberGenerator, rank := 0) -> Dictionary:
	var info := {"actions": [], "pass": true, "no_choice": true, "options": 1, "score": 0.0, "gap": INF}
	if b.over:
		return info
	var legal := b.legal_actions()
	if legal.size() <= 1:
		return info
	info.pass = false
	# Жвачка при почти пустой руке — сначала добрать, потом думать.
	var gum := _item_action(legal, b, "gum")
	if not gum.is_empty() and b.hand.size() <= 1 and b.deck.size() + b.discard.size() > 0:
		info.actions = [gum]
		info.no_choice = false
		return info
	var base := b
	var pre := []
	var bat := _item_action(legal, b, "batteries")
	if not bat.is_empty():
		var c := b.clone()
		c.apply(bat)
		if _best_estimate(c) - _best_estimate(b) > ITEM_HOLD:
			base = c
			pre = [bat]
	var cands := _candidates(base, rng)
	cands.sort_custom(func(x, y): return x.score > y.score)
	# группы по итогу хода
	var groups := []
	var seen := {}
	for cd in cands:
		if seen.has(cd.key):
			continue
		seen[cd.key] = true
		groups.append(cd)
	var best: Dictionary = groups[0]
	var reasonable := 0
	for g in groups:
		if g.score >= best.score - MARGIN:
			reasonable += 1
	info.options = reasonable
	if groups.size() > 1:
		info.gap = best.score - groups[1].score
	info.no_choice = reasonable <= 1
	var pick: Dictionary = groups[mini(rank, groups.size() - 1)]
	info.score = pick.score
	info.actions = pre + _cut_after_draw(base, pick)
	return info


## Список действий обрывается после выкладки Белки-камео: она добирает вкладыш, а какой — бот ещё
## не знает (дальше — новый вызов бота). Камео в раскладке всегда идут первыми.
static func _cut_after_draw(b: Battle, cand: Dictionary) -> Array:
	var acts: Array = cand.actions
	var plan: Array = cand.plan
	for i in plan.size():
		var hi := _hand_index(b, plan[i][0])
		if hi >= 0 and b.hand[hi].badges.has("cameo") and i < acts.size() - 1:
			return acts.slice(0, i + 1)
	return acts


static func _item_action(legal: Array, b: Battle, id: String) -> Dictionary:
	for a in legal:
		if a.type == "item" and b.items[int(a.slot)] == id:
			return a
	return {}


# ---------------------------------------------------------------- кандидаты

## Все кандидаты хода, честно проигранные через PLAY: [{actions, score, key}].
static func _candidates(b: Battle, rng: RandomNumberGenerator) -> Array:
	var plans := _plans(b)
	var out := []
	for p in plans:
		out.append(_simulate(b, p, [], rng))
	out.sort_custom(func(x, y): return x.score > y.score)
	# предметы и подмигивания — к лучшим раскладкам
	var top := out.slice(0, ITEM_PLANS)
	for cd in top:
		var c := b.clone()
		for a in cd.actions:
			c.apply(a)
		for a in c.legal_actions():
			if a.type == "wink" or (a.type == "item" and not ["gum", "batteries"].has(c.items[int(a.slot)])):
				out.append(_simulate(b, cd.plan, [a], rng))
	return out


## Проиграть раскладку (+ лишние действия) на копии через PLAY и оценить.
static func _simulate(b: Battle, plan: Array, extra: Array, rng: RandomNumberGenerator) -> Dictionary:
	var c := b.clone()
	var acts := []
	for p in plan:
		var a := {"type": "place", "hand": _hand_index(c, p[0]), "lane": p[1]}
		if a.hand < 0:
			push_error("Bot: в руке нет вкладыша uid=%d" % p[0])
			continue
		acts.append(a)
		c.apply(a)
	for a in extra:
		acts.append(a)
		c.apply(a)
	c.apply({"type": "play"})
	var score := _score(b, c) + rng.randf() * 0.01
	return {"actions": acts, "plan": plan, "score": score, "key": _key(c)}


static func _hand_index(c: Battle, uid: int) -> int:
	for i in c.hand.size():
		if int(c.hand[i].uid) == uid:
			return i
	return -1


## Раскладки для честной проверки: лучшие BEAM по быстрой оценке, лучшая с каждым типом вкладыша
## и «ничего не выкладывать». Раскладка — [[uid, полоса], ...], камео — первыми.
static func _plans(b: Battle) -> Array:
	var est := _estimate_all(b)
	var all: Array = est.plans
	all.sort_custom(func(x, y): return x.est > y.est)
	var out := []
	var keys := {}
	for p in all.slice(0, BEAM):
		_add_plan(out, keys, p.place)
	for ti in est.types.size():
		for p in all:
			if p.types.has(ti):
				_add_plan(out, keys, p.place)
				break
	_add_plan(out, keys, [])
	return out


static func _add_plan(out: Array, keys: Dictionary, place: Array) -> void:
	var k := str(place)
	if keys.has(k):
		return
	keys[k] = true
	out.append(place)


static func _best_estimate(b: Battle) -> float:
	var est := _estimate_all(b)
	var best := -INF
	for p in est.plans:
		best = maxf(best, p.est)
	return best


# ---------------------------------------------------------------- быстрая оценка по полосам

## {types, plans}: типы вкладышей по карману и все раскладки с быстрой оценкой.
static func _estimate_all(b: Battle) -> Dictionary:
	var types := _card_types(b)
	var free := []
	for l in Battle.LANES:
		if b.you[l] == null and l != int(b.cfg.blocked_lane):
			free.append(l)
	var c := b.clone()
	var none_res := c.compute_scene()
	var none_v := []
	for l in Battle.LANES:
		none_v.append(_lane_value(c, null, l, none_res))
	var gain := []
	for t in types:
		for l in free:
			c.you[l] = t.card
		var res := c.compute_scene()
		var row := []
		for l in Battle.LANES:
			row.append(_lane_value(c, t.card, l, res) - none_v[l] if free.has(l) else 0.0)
		gain.append(row)
		for l in free:
			c.you[l] = null
	var plans := []
	var used := []
	used.resize(types.size())
	used.fill(0)
	_enum(types, free, gain, int(b.cfg.carry), 0, b.sparks, [], [], used, 0.0, plans)
	return {"types": types, "plans": plans}


static func _enum(types: Array, free: Array, gain: Array, carry: int, i: int, left: int, place: Array,
		tused: Array, used: Array, est: float, out: Array) -> void:
	if i >= free.size():
		var total := est + W_SPARK * mini(left, carry) - (W_HAND + W_FREE) * place.size()
		var sorted := place.duplicate()
		sorted.sort_custom(func(x, y): return x[2] and not y[2])  # камео — первыми
		var p := []
		for s in sorted:
			p.append([s[0], s[1]])
		out.append({"place": p, "est": total, "types": tused.duplicate()})
		return
	var l: int = free[i]
	_enum(types, free, gain, carry, i + 1, left, place, tused, used, est, out)
	for ti in types.size():
		var t: Dictionary = types[ti]
		if used[ti] >= t.uids.size() or t.cost > left:
			continue
		place.append([t.uids[used[ti]], l, t.card.badges.has("cameo")])
		tused.append(ti)
		used[ti] += 1
		_enum(types, free, gain, carry, i + 1, left - t.cost, place, tused, used, est + gain[ti][l], out)
		used[ti] -= 1
		tused.pop_back()
		place.pop_back()


## Вкладыши в руке по карману, одинаковые склеены в один тип: [{card, cost, uids}].
static func _card_types(b: Battle) -> Array:
	var types := []
	var by_key := {}
	for card in b.hand:
		if int(card.cost) > b.sparks:
			continue
		var k := "%s|%d|%d|%d|%s" % [card.id, card.atk, card.hp, card.cost, ",".join(PackedStringArray(card.badges))]
		if by_key.has(k):
			types[by_key[k]].uids.append(int(card.uid))
		else:
			by_key[k] = types.size()
			types.append({"card": card, "cost": int(card.cost), "uids": [int(card.uid)]})
	return types


## Быстрая ценность полосы l с вкладышем card (или пустой) по расчёту сцены res.
static func _lane_value(c: Battle, card, l: int, res: Dictionary) -> float:
	var v: float = W_FILM * res.film_lanes[l] - W_SIG * res.signal_lanes[l]
	var opp = c.tape[l]
	if opp == null and c.sketches[l] != null and not c.sketches[l].get("hidden", false):
		opp = CardDB.make_creature(c.sketches[l].id, int(c.cfg.tape_hp), int(c.cfg.tape_atk))
	var opp_dead: bool = opp != null and res.die_tape.has(l)
	if opp != null:
		if opp_dead:
			v += W_TAPE * _creature_val(opp)
		else:
			v += 0.5 * W_TAPE * mini(int(res.dmg_tape[l]), int(opp.hp))
	var next_lit := c.planned(l) != bool(c.cfg.invert)
	var alive: bool = card != null and (not res.die_you.has(l) or (card.badges.has("toon") and not card.get("flat", false)))
	if alive:
		v += W_BOARD * _card_val(card) * (0.7 if res.die_you.has(l) else 1.0)
		if next_lit and (opp == null or opp_dead or card.badges.has("flying")):
			v += W_NEXT * W_FILM * int(card.atk)
	elif opp != null and not opp_dead and next_lit:
		v -= W_NEXT * W_SIG * int(opp.atk)
	return v


# ---------------------------------------------------------------- оценка итога хода

static func _card_val(c: Dictionary) -> float:
	var v := 2.0 * int(c.atk) + int(c.hp)
	for bd in c.badges:
		match bd:
			"flying":
				v += 1.5
			"replay":
				v += 1.5 * int(c.atk)
			"quiet", "prickly", "star", "stare", "mug":
				v += 1.0
			"tall":
				v += 0.5
			"toon":
				v += 0.0 if c.get("flat", false) else 2.0
	return v


static func _creature_val(c: Dictionary) -> float:
	var v := 2.0 * int(c.atk) + int(c.hp)
	for bd in c.badges:
		match bd:
			"flying", "static", "prickly":
				v += 1.0
			"glitch", "star":
				v += 0.5
	return v


static func _sig_value(s: int) -> float:
	var low := maxi(0, 3 - s)
	return W_SIG * s - DANGER * low * low


## Оценка состояния c (следующая пауза после PLAY) относительно b (пауза до хода).
static func _score(b: Battle, c: Battle) -> float:
	if c.over:
		if c.result == "win":
			return 10000.0 + 50.0 * c.sig + ITEM_HOLD * _items_left(c) + WINK_HOLD * c.winks
		return -10000.0 - W_FILM * c.film
	var s := 0.0
	if c.phase > b.phase:
		s += 3000.0 + W_FILM * b.film
	else:
		s += W_FILM * (b.film - c.film)
	s += _sig_value(c.sig) - _sig_value(b.sig)
	for l in Battle.LANES:
		if c.you[l] != null:
			s += W_BOARD * _card_val(c.you[l])
		elif l != int(c.cfg.blocked_lane):
			s += W_FREE
		if c.tape[l] != null:
			s -= W_TAPE * _creature_val(c.tape[l])
	# прогноз следующей сцены: новый кадр, но без новых набросков (их игрок ещё не видел)
	var sk := c.sketches
	c.sketches = []
	c.sketches.resize(Battle.LANES)
	var f := c.compute_scene()
	c.sketches = sk
	s += W_NEXT * (W_FILM * mini(int(f.film), c.film) - W_SIG * int(f.signal))
	for l in f.die_you:
		s -= W_NEXT * W_BOARD * _card_val(c.you[l])
	for l in f.die_tape:
		if c.tape[l] != null:
			s += W_NEXT * W_TAPE * _creature_val(c.tape[l])
	s += W_SPARK * c.sparks + W_HAND * c.hand.size() + WINK_HOLD * c.winks + ITEM_HOLD * _items_left(c)
	return s


static func _items_left(c: Battle) -> int:
	var n := 0
	for id in c.items:
		if id != null:
			n += 1
	return n


## Итог хода для сравнения вариантов: одинаковый ключ — одинаковый результат.
static func _key(c: Battle) -> String:
	var parts := [c.over, c.result, c.phase, c.film, c.sig, c.sparks, c.winks, str(c.items)]
	for l in Battle.LANES:
		var y = c.you[l]
		var t = c.tape[l]
		parts.append("-" if y == null else "%s%d/%d" % [y.id, y.atk, y.hp])
		parts.append("-" if t == null else "%s%d/%d" % [t.id, t.atk, t.hp])
	var ids := []
	for card in c.hand:
		ids.append(card.id)
	ids.sort()
	parts.append(",".join(PackedStringArray(ids)))
	for g in c.gazes:
		parts.append("%d>%d" % [g.lane, g.plan])
	return str(parts)


# ================================================================ бой целиком

## Играет бой до конца (или до turn_cap ходов). kind: "smart" / "simple".
## opts: turn_cap (40 ходов серии; переигранные после перемотки не в счёт), rewinds (0 — сколько
##   перемоток «на ход назад» можно потратить; после перемотки умный берёт следующий по оценке вариант
##   хода, на который вернулись), measure (true — считать ходы без выбора и для простого бота; разбор
##   идёт своим генератором и на игру простого бота не влияет).
## Возвращает: result ("win"/"lose"/"cap"), turns (длина итоговой записи серии в PLAY), plays (всего
##   нажатий PLAY с учётом переигранных), pauses, no_choice_turns, pass_turns, signal_lost, film_in /
##   film_off (снято Плёнки в кадре / за кадром), wasted (ударов в пустоту за кадром, впустую),
##   wasted_dmg (сколько они могли бы снять), lanes_lit / lanes_off (полос-ходов в кадре / вне кадра),
##   dead_lit / dead_off (из них «мёртвых» — где за сцену никто никого не ударил), rewinds_used,
##   titles (победа или поражение пришлись на «Титры»), illegal (действия, которые бой отклонил),
##   locked_turns (пауз, где есть вкладыш по карману, но все свои клетки заняты — «поле заперто»).
static func play_battle(b: Battle, kind: String, rng: RandomNumberGenerator, opts := {}) -> Dictionary:
	var cap: int = opts.get("turn_cap", 40)
	var rewinds: int = opts.get("rewinds", 0)
	var measure: bool = opts.get("measure", true)
	var out := {
		"result": "", "turns": 0, "plays": 0, "pauses": 0, "no_choice_turns": 0, "pass_turns": 0,
		"signal_lost": 0, "film_in": 0, "film_off": 0, "wasted": 0, "wasted_dmg": 0,
		"lanes_lit": 0, "lanes_off": 0, "dead_lit": 0, "dead_off": 0, "rewinds_used": 0, "titles": false,
		"illegal": 0, "locked_turns": 0,
	}
	var ranks := {}   # "фаза:ход" → какой вариант брать после перемотки
	var mrng := RandomNumberGenerator.new()
	mrng.seed = 20261002
	while not b.over and b.stats.turns < cap and out.plays < cap * (1 + rewinds):
		var at := "%d:%d" % [b.phase, b.turn]
		var rank: int = ranks.get(at, 0)
		out.pauses += 1
		out.locked_turns += 1 if is_locked(b) else 0
		var counted := false
		for step in 4:
			var info := {}
			var acts: Array
			if kind == "smart":
				info = analyze(b, rng, rank)
			elif measure and not counted:
				info = analyze(b, mrng, rank)
			if not counted and not info.is_empty():
				counted = true
				out.no_choice_turns += 1 if info.no_choice else 0
				out.pass_turns += 1 if info.pass else 0
			if kind == "smart":
				acts = info.actions
			else:
				acts = simple_turn(b, rng)
			if acts.is_empty():
				break
			var drew := false
			for a in acts:
				var ev := b.apply(a)
				if ev.any(func(e): return e.t == "deny"):
					out.illegal += 1
				if ev.any(func(e): return e.t == "draw"):
					drew = true
			if kind == "simple" or not drew:
				break
		_play_and_count(b, out)
		if b.over and b.result == "lose" and rewinds > 0 and b.can_rewind():
			rewinds -= 1
			out.rewinds_used += 1
			b.rewind(false)
			var key := "%d:%d" % [b.phase, b.turn]
			ranks[key] = int(ranks.get(key, 0)) + 1
	out.result = b.result if b.over else "cap"
	out.turns = int(b.stats.turns)
	out.signal_lost = int(b.stats.signal_lost)
	return out


## Поле заперто: свободных клеток нет, а в руке есть вкладыш, на который хватает искр.
static func is_locked(b: Battle) -> bool:
	for l in Battle.LANES:
		if b.you[l] == null and l != int(b.cfg.blocked_lane):
			return false
	for card in b.hand:
		if int(card.cost) <= b.sparks:
			return true
	return false


static func _play_and_count(b: Battle, out: Dictionary) -> void:
	var res := b.compute_scene()
	for l in Battle.LANES:
		var lit := b.lit(l)
		var act: int = res.dmg_you[l] + res.dmg_tape[l] + res.film_lanes[l] + res.signal_lanes[l]
		if lit:
			out.lanes_lit += 1
			out.dead_lit += 1 if act == 0 else 0
			out.film_in += res.film_lanes[l]
		else:
			out.lanes_off += 1
			out.dead_off += 1 if act == 0 else 0
			out.film_off += res.film_lanes[l]
	for s in res.strikes:
		if s.side == "you" and s.target == "offscreen":
			out.wasted += 1
			out.wasted_dmg += int(b.you[s.lane].atk) if b.you[s.lane] != null else 0
	var ev := b.apply({"type": "play"})
	out.plays += 1
	if b.over and ev.any(func(e): return e.t == "titles"):
		out.titles = true
