extends SceneTree
## Симуляция боёв ботами без окна (дизайн §17 и §21): баланс по каждой серии.
##
##   godot --headless --path . -s res://tests/sim.gd -- [battles=N] [bot=smart|simple] [offscreen=0|1]
##       [deck=start|mid|both] [rewinds=2] [ep=id,id] [seed=1] [trace=1] [film_add=N] [set=ключ:число,...]
##       [mode=battles]
##
## mode=battles (по умолчанию) — каждая серия из Episodes.POOLS, «Ночной показ» уровней 2–3 (как его даёт
##   Episodes.pick(level - 1, rng, true)), пилот (TUTORIAL) и босс; две колоды: стартовая и «середина ночи».
## trace=1 — подробный ход за ходом (удобно вместе с ep=id battles=1).
## Опыты с балансом без правки данных: film_add=3 — всем сериям (и 2-й фазе босса) +3 Плёнки;
##   set=signal:5,tape_atk:1 — любые параметры Battle.DEFAULTS.
## Задел: mode=night (полная ночь через Run из run.gd) добавляется отдельной функцией _night_mode —
##   разбор аргументов, колоды и печать таблиц уже общие.

## Колода «середина ночи»: старт + то, что обычно приходит с Розыгрышей к 01:00.
const MID_EXTRA := ["kvaksha", "krot", "sova", "soroka"]
const MID_ITEMS := ["tape", "slipper"]
const NIGHT_LEVELS := [2, 3]  # «Ночной показ» бывает в 00:00 (твари ур. 2) и в 01:00 (ур. 3)

var opts := {
	"mode": "battles", "battles": 40, "bot": "smart", "offscreen": 0, "deck": "both", "rewinds": 2,
	"ep": "", "seed": 1, "trace": 0, "film_add": 0, "set": "",
}
var overrides := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and opts.has(kv[0]):
			opts[kv[0]] = kv[1] if opts[kv[0]] is String else int(kv[1])
	overrides = {"offscreen": int(opts.offscreen)}
	for pair in String(opts.set).split(",", false):
		var p := pair.split(":")
		if p.size() == 2:
			overrides[p[0]] = (p[1] == "true") if p[1] in ["true", "false"] else int(p[1])
	match opts.mode:
		"battles":
			_battle_mode()
		_:
			print("Неизвестный режим: ", opts.mode)
	quit()


# ================================================================ колоды и серии

static func deck_cards(kind: String) -> Array:
	var ids: Array = CardDB.STARTER_DECK.duplicate()
	if kind == "mid":
		ids.append_array(MID_EXTRA)
	var out := []
	for id in ids:
		out.append(CardDB.make(id))
	return out


static func deck_items(kind: String) -> Array:
	var items: Array = (MID_ITEMS if kind == "mid" else CardDB.STARTER_ITEMS).duplicate()
	while items.size() < 3:
		items.append(null)
	return items


## Все серии для отчёта: [{ep, tag}]; tag — уровень, «Н» — ночной показ, «Б» — босс.
static func episode_list() -> Array:
	var out := [{"ep": Episodes.TUTORIAL, "tag": "П"}]
	for lv in [0, 1, 2, 3]:
		for e in Episodes.POOLS[lv]:
			out.append({"ep": e, "tag": str(lv)})
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for lv in NIGHT_LEVELS:
		for e in Episodes.POOLS[lv]:
			var avoid := []
			for o in Episodes.POOLS[lv]:
				if o.id != e.id:
					avoid.append(o.id)
			out.append({"ep": Episodes.pick(lv - 1, rng, true, avoid), "tag": "Н%d" % lv})
	out.append({"ep": Episodes.BOSS, "tag": "Б"})
	return out


static func seed_for(ep_id: String, deck: String, i: int, base: int) -> int:
	return absi(hash("%s|%s|%d|%d" % [ep_id, deck, i, base])) % 2147483647 + 1


# ================================================================ режим «серии»

func _battle_mode() -> void:
	var decks: Array = ["start", "mid"] if opts.deck == "both" else [opts.deck]
	var eps := episode_list()
	if opts.ep != "":
		var want := String(opts.ep).split(",")
		eps = eps.filter(func(x): return want.has(x.ep.id))
	for row in eps:
		row.ep = _prep_episode(row.ep)
	var t0 := Time.get_ticks_msec()
	print("Бот: %s · боёв на строку: %d · перемоток на бой: %d · параметры: %s%s" % [
		"умный" if opts.bot == "smart" else "простой", opts.battles, opts.rewinds, str(overrides),
		" · Плёнка %+d" % opts.film_add if opts.film_add != 0 else ""])
	print(_header())
	var totals := {}
	for d in decks:
		totals[d] = _new_acc()
	for row in eps:
		for d in decks:
			var acc := _new_acc()
			for i in opts.battles:
				var r := _one_battle(row.ep, d, i)
				_add(acc, r)
				_add(totals[d], r)
			print(_line(row.ep.name, row.tag, int(row.ep.get("film", 5)), d, acc))
	print("-".repeat(_header().length()))
	for d in decks:
		print(_line("ВСЕ СЕРИИ", "", 0, d, totals[d]))
	var ms := Time.get_ticks_msec() - t0
	print("Время: %.1f с; поб%% — без перемоток, +пер%% — с перемотками «на ход назад»; ход — длина серии в PLAY;" % (ms / 1000.0))
	print("бвыб% — пауз без выбора (только PLAY или один разумный итог), пас% — только PLAY, зап% — поле заперто")
	print("(есть вкладыш по карману, но все клетки заняты); сиг− — Сигнала снято тварями;")
	print("пл.к / пл.вне — Плёнки снято за бой в кадре / за кадром; впуст — ударов в пустоту за кадром (сколько могли снять);")
	print("мёртв к/вне — полос-ходов, где за сцену никто никого не ударил (в кадре / вне кадра); тит% — бой решили «Титры».")


## Копия серии с поправкой Плёнки (film_add).
func _prep_episode(ep: Dictionary) -> Dictionary:
	var e := ep.duplicate(true)
	var add := int(opts.film_add)
	if add != 0:
		e.film = int(e.get("film", Battle.DEFAULTS.film)) + add
		if e.has("phase2"):
			e.phase2.film = int(e.phase2.get("film", 6)) + add
	return e


func _one_battle(ep: Dictionary, deck: String, i: int) -> Dictionary:
	var s := seed_for(ep.id + str(ep.get("night", false)), deck, i, int(opts.seed))
	var b := Battle.create(ep, deck_cards(deck), deck_items(deck), overrides, s)
	var rng := RandomNumberGenerator.new()
	rng.seed = s ^ 0x5bd1e995
	if int(opts.trace) != 0:
		_trace(b, rng)
	var r := Bot.play_battle(b, opts.bot, rng, {"rewinds": int(opts.rewinds)})
	if r.illegal > 0:
		push_error("Бот сделал недопустимый ход: %s, сид %d" % [ep.id, s])
	if r.result == "cap":
		push_error("Бой не закончился: %s, сид %d" % [ep.id, s])
	return r


# ================================================================ счёт и таблица

static func _new_acc() -> Dictionary:
	return {"n": 0, "win0": 0, "win": 0, "turns": 0, "pauses": 0, "nc": 0, "pass": 0, "sig": 0, "fin": 0, "foff": 0,
		"wasted": 0, "wasted_dmg": 0, "ll": 0, "lo": 0, "dl": 0, "do": 0, "titles": 0, "locked": 0}


static func _add(acc: Dictionary, r: Dictionary) -> void:
	acc.n += 1
	acc.win += 1 if r.result == "win" else 0
	acc.win0 += 1 if r.result == "win" and r.rewinds_used == 0 else 0
	acc.turns += r.turns
	acc.pauses += r.pauses
	acc.nc += r.no_choice_turns
	acc.pass += r.pass_turns
	acc.sig += r.signal_lost
	acc.fin += r.film_in
	acc.foff += r.film_off
	acc.wasted += r.wasted
	acc.wasted_dmg += r.wasted_dmg
	acc.ll += r.lanes_lit
	acc.lo += r.lanes_off
	acc.dl += r.dead_lit
	acc.do += r.dead_off
	acc.titles += 1 if r.titles else 0
	acc.locked += r.locked_turns


static func _pct(a: float, b: float) -> String:
	return "%3d" % roundi(100.0 * a / b) if b > 0 else "  -"


static func _header() -> String:
	return "%s %s %s %s | поб%% +пер%% ход  бвыб%% пас%% зап%% сиг−  пл.к пл.вне впуст     мёртв к/вне тит%%" % [
		"серия".rpad(30), "ур".rpad(2), "пл", "колода"]


static func _line(name: String, tag: String, film: int, deck: String, a: Dictionary) -> String:
	var n := float(maxi(a.n, 1))
	return "%s %s %s %s | %s  %s  %4.1f  %s  %s  %s %4.1f  %4.1f %4.1f  %4.1f(%4.1f)   %s / %s  %s" % [
		name.left(30).rpad(30), tag.rpad(2), ("%2d" % film) if film > 0 else "  ", ("старт" if deck == "start" else "серед").rpad(6),
		_pct(a.win0, n), _pct(a.win, n), a.turns / n, _pct(a.nc, a.pauses), _pct(a.pass, a.pauses), _pct(a.locked, a.pauses),
		a.sig / n,
		a.fin / n, a.foff / n, a.wasted / n, a.wasted_dmg / n, _pct(a.dl, a.ll), _pct(a.do, a.lo), _pct(a.titles, n)]


# ================================================================ подробный ход (trace=1)

## Проигрывает копию боя и печатает каждую паузу: поле, кадр, пунктир, руку, решение бота и итог сцены.
func _trace(b0: Battle, rng0: RandomNumberGenerator) -> void:
	var b := b0.clone()
	var rng := RandomNumberGenerator.new()
	rng.state = rng0.state
	print("=== %s · Плёнка %d · Сигнал %d" % [b.episode.name, b.film, b.sig])
	for guard in 40:
		if b.over:
			break
		print(_board(b))
		var info := Bot.analyze(b, rng)
		var acts: Array = info.actions if opts.bot == "smart" else Bot.simple_turn(b, rng)
		print("  вариантов: %d%s%s · ход: %s" % [info.options, " · ПАС" if info.pass else "",
			" · без выбора" if info.no_choice else "", _acts_text(b, acts)])
		for a in acts:
			b.apply(a)
		if opts.bot == "smart" and not acts.is_empty() and acts.back().type == "place":
			var more: Array = Bot.analyze(b, rng).actions
			if not more.is_empty():
				print("  добор → ещё: %s" % _acts_text(b, more))
				for a in more:
					b.apply(a)
		var ev := b.apply({"type": "play"})
		var film := 0
		var sig := 0
		for e in ev:
			if e.t == "film":
				film += -int(e.delta)
			elif e.t == "signal":
				sig += -int(e.delta)
		print("  PLAY → Плёнка −%d (=%d), Сигнал −%d (=%d)" % [film, b.film, sig, b.sig])
	print("=== итог: %s за %d ходов" % [b.result, b.stats.turns])


static func _board(b: Battle) -> String:
	var rows := ["", "", ""]
	for l in Battle.LANES:
		var t = b.tape[l]
		var sk = b.sketches[l]
		var y = b.you[l]
		var top := "%s %d/%d" % [CardDB.short_name(t), t.atk, t.hp] if t != null else ""
		if sk != null:
			top += "(+%s)" % sk.id
		var mark := ("[КАДР]" if b.in_frame(l) else "") + ("[пункт]" if b.planned(l) else "")
		rows[0] += (top if top != "" else "·").rpad(18)
		rows[1] += mark.rpad(18)
		rows[2] += ("%s %d/%d" % [CardDB.short_name(y), y.atk, y.hp] if y != null else "·").rpad(18)
	var hand := []
	for c in b.hand:
		hand.append("%s(%d)" % [CardDB.short_name(c), c.cost])
	return "ход %d · искры %d · Плёнка %d · Сигнал %d · рука: %s · карманы: %s\n  %s\n  %s\n  %s" % [
		b.turn, b.sparks, b.film, b.sig, ", ".join(PackedStringArray(hand)), str(b.items), rows[0], rows[1], rows[2]]


static func _acts_text(b: Battle, acts: Array) -> String:
	if acts.is_empty():
		return "ничего"
	var c := b.clone()
	var parts := []
	for a in acts:
		match a.type:
			"place":
				parts.append("%s→%d" % [CardDB.short_name(c.hand[a.hand]), a.lane])
			"item":
				parts.append("предмет %s %s" % [c.items[a.slot], str(a)])
			_:
				parts.append(str(a))
		c.apply(a)
	return ", ".join(PackedStringArray(parts))
