extends TestCase
## Ночь эфира: газета → теория → серия → награды → рубрики → босс; фантики, перемотки, сохранение; мета.


func _run(seed_value := 5, first := false, meta := {}) -> Run:
	return Run.new_night(meta if not meta.is_empty() else Meta.new_meta(), seed_value, first)


## Перейти в клетку (row, ch), как будто до этого всё прошли.
func _goto(r: Run, row: int, ch: int) -> Array:
	r.row = row - 1
	r.channel = ch
	r.state = "grid"
	r.offer = {}
	r.battle = null
	return r.choose(ch)


func _force_win(b: Battle, signal_lost := 0, overkill := 0) -> void:
	b.over = true
	b.result = "win"
	b.stats.signal_lost = signal_lost
	b.stats.overkill = overkill


## Проигрываем бой, просто нажимая PLAY.
func _lose(b: Battle) -> void:
	for i in 60:
		if b.over:
			return
		b.apply({"type": "play"})


func _has(ev: Array, t: String) -> bool:
	return ev.any(func(e): return e.t == t)


# ================================================================ начало ночи и газета

func test_new_night_defaults() -> void:
	var r := _run(5, true)
	check_eq(r.deck.map(func(c): return c.id), Array(CardDB.STARTER_DECK), "стартовая колода")
	check_eq(r.pockets, ["tape", null, null], "Синяя изолента в кармане, всего 3 кармана")
	check_eq(r.rewinds, 2, "2 перемотки на ночь")
	check_eq(r.fantiki, 0, "")
	check_eq(r.state, "grid", "начинаем с газеты")
	check_eq(r.available_moves(), [0, 1, 2], "в 23:00 любой канал")
	check(r.grid.rows[0][1].episode.get("tutorial", false), "первая ночь — обучение")


func test_movement_rules() -> void:
	var r := _run()
	var ev := r.choose(0)
	check(not _has(ev, "deny"), "23:00, первый канал")
	check_eq(r.state, "battle", "серия")
	check(_has(r.choose(0), "deny"), "во время серии газету не трогаем")
	var b := r.start_battle()
	_force_win(b)
	r.finish_battle(b)
	check_eq(r.state, "grid", "после серии — газета")
	check_eq(r.available_moves(), [0, 1], "свой или соседний канал")
	check(_has(r.choose(2), "deny"), "через канал прыгать нельзя")
	r.choose(1)
	check_eq(r.state, "segment", "23:30 — Розыгрыш")
	check_eq(r.current_offer().kind, "raffle", "")
	check_eq(r.path, [0, 1], "путь по газете")


# ================================================================ теории

func _theory_battle(id: String, pick := 1) -> Battle:
	var r := _run(21)
	var cell: Dictionary = r.grid.rows[2][1]
	cell.night = false
	cell.theory = id
	cell.theory_cfg = {"blocked_lane": 2} if id == "censors" else {}
	var ev := _goto(r, 2, 1)
	check_eq(r.state, "theory", "перед серией с теорией — выбор")
	check(_has(ev, "offer"), "")
	var o := r.current_offer()
	check_eq(o.options[0].id, "plain", "«Обычный просмотр»")
	check_eq(o.options[1].id, id, "теория")
	r.resolve({"pick": pick})
	check_eq(r.state, "battle", "")
	return r.start_battle()


func test_theory_censors_blocks_lane() -> void:
	var b := _theory_battle("censors")
	check_eq(int(b.cfg.blocked_lane), 2, "вырезанная полоса из газеты")
	check(not b.legal_actions().any(func(a): return a.type == "place" and a.lane == 2), "туда не выложить")


func test_theory_night_ink_hides_sketches() -> void:
	var b := _theory_battle("night_ink")
	check(bool(b.cfg.hidden_sketches), "наброски без имён")


func test_theory_one_wolf_tape_hp() -> void:
	var b := _theory_battle("one_wolf")
	check_eq(int(b.cfg.tape_hp), 1, "твари +1 здоровья")
	var plain := _theory_battle("one_wolf", 0)
	check_eq(int(plain.cfg.tape_hp), 0, "обычный просмотр — без теории")


func test_theory_sleepy_gazes() -> void:
	var b := _theory_battle("sleepy")
	check(not b.gazes.is_empty(), "")
	for g in b.gazes:
		check_eq(g.habit, "sleepy", "оператор уснул")
	var lanes := []
	for i in 4:
		lanes.append(b.gazes[0].lane)
		b.apply({"type": "play"})
		if b.over:
			break
	if lanes.size() == 4:
		check(lanes[0] == lanes[1] and lanes[1] == lanes[2] and lanes[3] != lanes[0], "3 хода стоит, потом прыгает: %s" % [lanes])


func test_theory_prepare_does_not_touch_grid() -> void:
	var ep: Dictionary = Episodes.POOLS[2][0]
	var before := JSON.stringify(ep)
	Theories.prepare("sleepy", ep)
	Theories.prepare("one_wolf", ep)
	check_eq(JSON.stringify(ep), before, "серия в газете не меняется")


# ================================================================ сигнал, подмигивания

func test_battle_signal_and_winks() -> void:
	var meta := Meta.new_meta()
	meta.eyes = 2
	var r := _run(4, false, meta)
	r.signal_bonus = 1
	r.signal_penalty = 1
	_goto(r, 0, 0)
	var b := r.start_battle()
	check_eq(b.sig_max, 6, "6 + антенна − сосед")
	check_eq(b.winks, 2, "подмигивания = глаза")
	check_eq(r.signal_penalty, 0, "помеха соседа — на одну серию")
	check(r.start_battle() == b, "повторный вызов — тот же бой")
	_force_win(b)
	r.finish_battle(b)
	r.choose(0)
	r.resolve({"skip": true})
	_goto(r, 2, 0)
	if r.state == "theory":
		r.resolve({"pick": 0})
	check_eq(r.start_battle().sig_max, 7, "антенна действует до конца ночи")


# ================================================================ фантики

func test_fantiki_math() -> void:
	check_eq(Run.fantiki_for({"signal_lost": 0, "overkill": 0}, false).total, 3, "победа 2 + чистая 1")
	check_eq(Run.fantiki_for({"signal_lost": 2, "overkill": 0}, false).total, 2, "просто победа")
	check_eq(Run.fantiki_for({"signal_lost": 1, "overkill": 2}, false).total, 4, "перебор +2")
	check_eq(Run.fantiki_for({"signal_lost": 1, "overkill": 9}, false).total, 5, "перебор не больше +3")
	check_eq(Run.fantiki_for({"signal_lost": 0, "overkill": 9}, true).total, 8, "Ночной показ 4 + 1 + 3")
	check_eq(Run.fantiki_for({"signal_lost": 0, "overkill": 1}, false, "censors").total, 8, "цензоры: (2+1+1)×2")
	check_eq(Run.fantiki_for({"signal_lost": 0, "overkill": 1}, false, "sleepy").total, 4, "у остальных теорий без множителя")


func test_finish_battle_pays_and_returns_items() -> void:
	var r := _run()
	_goto(r, 0, 1)
	var b := r.start_battle()
	b.items[0] = null  # изоленту потратили в бою
	b.items[2] = "gum"
	_force_win(b, 0, 2)
	var ev := r.finish_battle(b)
	check_eq(r.fantiki, 5, "2 + чистая 1 + перебор 2")
	check(_has(ev, "fantiki") and _has(ev, "film_break"), "события")
	check_eq(r.pockets, [null, null, "gum"], "карманы — как в конце боя")
	check(r.battle == null, "бой убран")
	check_eq(r.state, "grid", "")


func test_night_show_reward() -> void:
	var r := _run(8)
	var ch := -1
	for c in r.grid.rows[2]:
		if c.night:
			ch = c.channel
	_goto(r, 2, ch)
	if r.state == "theory":
		r.resolve({"pick": 0})
	var b := r.start_battle()
	check_eq(b.film_max, 7, "Ночной показ: Плёнка 7")
	_force_win(b, 1, 0)
	r.finish_battle(b)
	check_eq(r.fantiki, 4, "двойные фантики")
	check_eq(r.state, "segment", "награда — вкладыш")
	var o := r.current_offer()
	check(o.kind == "raffle" and o.reason == "night", "")
	for c in o.cards:
		check(CardDB.CARDS[c.id].rarity in ["uncommon", "rare"], "из необычных и редких")
	r.resolve({"pick": 0})
	check_eq(r.state, "grid", "после награды — газета")


func test_theory_rewards() -> void:
	var expect := {"censors": "", "night_ink": "sponsor", "one_wolf": "raffle", "sleepy": "review"}
	for id in expect:
		var r := _run(13)
		var cell: Dictionary = r.grid.rows[4][0]
		cell.night = false
		cell.theory = id
		cell.theory_cfg = {"blocked_lane": 0}
		_goto(r, 4, 0)
		r.resolve({"pick": 1})
		var b := r.start_battle()
		_force_win(b, 1, 0)
		r.finish_battle(b)
		if expect[id] == "":
			check_eq(r.fantiki, 4, "цензоры: фантики ×2")
			check_eq(r.state, "grid", "")
		else:
			check_eq(r.state, "segment", "награда за теорию %s" % id)
			check_eq(r.current_offer().kind, expect[id], "")
			check_eq(r.current_offer().reason, "theory", "")
		check_eq(r.theory, "", "теория сброшена")
	var r2 := _run(13)
	r2.grid.rows[4][0].theory = "one_wolf"
	r2.grid.rows[4][0].night = false
	_goto(r2, 4, 0)
	r2.resolve({"pick": 1})
	var b2 := r2.start_battle()
	_force_win(b2)
	r2.finish_battle(b2)
	# в первую ночь открыто 2 редких: оба в предложении, третий — классом ниже
	var open_rares: Array = r2.unlocks.cards.filter(func(id): return CardDB.CARDS[id].rarity == "rare")
	var offered: Array = r2.current_offer().cards.map(func(c): return c.id)
	for id in open_rares.slice(0, 3):
		check(offered.has(id), "редкий вкладыш %s в предложении" % id)
	for id in offered:
		check(CardDB.CARDS[id].rarity in ["rare", "uncommon"], "награда — редкий (или добор необычным)")


# ================================================================ перемотки

func test_rewinds_count_down_then_tape_chewed() -> void:
	var r := _run(31)
	_goto(r, 2, 0)
	if r.state == "theory":
		r.resolve({"pick": 0})
	var b := r.start_battle()
	check(not r.rewind_available(), "пока не проиграл — перематывать нечего")
	check(_has(r.use_rewind(b, true), "deny"), "")
	for left in [2, 1]:
		_lose(b)
		check_eq(b.result, "lose", "без зверей проигрываем")
		var ev := r.finish_battle(b)
		check(_has(ev, "no_signal"), "НЕТ СИГНАЛА")
		check_eq(r.state, "battle", "ночь продолжается")
		check(r.rewind_available(), "")
		ev = r.use_rewind(b, left == 1)
		check_eq(r.rewinds, left - 1, "перемотка потрачена")
		check(not b.over and _has(ev, "rewind"), "бой продолжается")
	_lose(b)
	var ev2 := r.finish_battle(b)
	check(_has(ev2, "chewed"), "ПЛЁНКУ ЗАЖЕВАЛО")
	check_eq(r.state, "over", "ночь окончена")
	check_eq(r.result, "lose", "")
	check_eq(r.report().row, 2, "дошёл до 00:00")
	check_eq(r.stats.rewinds_used, 2, "")


func test_cassette_adds_rewind() -> void:
	var r := _run()
	r.fantiki = 10
	var o := Segments.offer("shop", r, r.rng)
	o.lots[3].item = "cassette"
	Segments.apply(r, o, {"buy": 3})
	check_eq(r.rewinds, 3, "Чистая кассета +1")


func test_boss_win_ends_night() -> void:
	var r := _run(17)
	_goto(r, 8, 1)
	check_eq(r.current_cell().kind, "boss", "03:00 — Конец эфира")
	var b := r.start_battle()
	check(b.episode.get("boss", false), "")
	_force_win(b)
	var ev := r.finish_battle(b)
	check_eq(r.state, "over", "")
	check_eq(r.result, "win", "ночь выиграна")
	check(_has(ev, "night_over"), "")
	check_eq(r.available_moves(), [], "")


# ================================================================ сохранение

func _roundtrip(r: Run) -> Run:
	return Run.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))


func test_json_roundtrip_mid_battle() -> void:
	var r := _run(44)
	_goto(r, 2, 1)
	if r.state == "theory":
		r.resolve({"pick": 1})
	var b := r.start_battle()
	for i in 2:
		var places := b.legal_actions().filter(func(a): return a.type == "place")
		if not places.is_empty():
			b.apply(places[0])
		b.apply({"type": "play"})
	var r2 := _roundtrip(r)
	check(r2 != null, "загрузилось")
	check_eq(JSON.stringify(r2.to_dict()), JSON.stringify(r.to_dict()), "забег вместе с боем без потерь")
	check(r2.battle != null and r2.state == "battle", "бой восстановлен")
	for i in 3:
		r.battle.apply({"type": "play"})
		r2.battle.apply({"type": "play"})
	check_eq(JSON.stringify(r2.to_dict()), JSON.stringify(r.to_dict()), "и дальше идут одинаково")
	_lose(r.battle)
	_lose(r2.battle)
	r.finish_battle(r.battle)
	r2.finish_battle(r2.battle)
	r.use_rewind(r.battle, true)
	r2.use_rewind(r2.battle, true)
	check_eq(JSON.stringify(r2.to_dict()), JSON.stringify(r.to_dict()), "перемотка после загрузки — та же")


func test_json_roundtrip_mid_segment() -> void:
	var r := _run(45)
	r.fantiki = 12
	_goto(r, 5, 0)
	_goto(r, 5, [0, 1, 2].filter(func(c): return r.grid.rows[5][c].segment == "shop")[0])
	check_eq(r.current_offer().kind, "shop", "")
	r.resolve({"buy": 0})
	var r2 := _roundtrip(r)
	check_eq(JSON.stringify(r2.to_dict()), JSON.stringify(r.to_dict()), "посреди Телемагазина")
	for c in [{"buy": 4}, {"buy": 5}, {"leave": true}]:
		var e1 := JSON.stringify(r.resolve(c))
		var e2 := JSON.stringify(r2.resolve(c))
		check_eq(e2, e1, "те же события")
	check_eq(JSON.stringify(r2.to_dict()), JSON.stringify(r.to_dict()), "и тот же итог")
	check_eq(r2.state, "grid", "")
	r2.choose(r2.available_moves()[0])
	r.choose(r.available_moves()[0])
	if r.state == "theory":
		r.resolve({"pick": 1})
		r2.resolve({"pick": 1})
	check_eq(r2.start_battle().rng.seed, r.start_battle().rng.seed, "генератор забега сохранён")


func test_wrong_save_version() -> void:
	var d := _run().to_dict()
	d.version = 999
	check(Run.from_dict(d) == null, "чужая версия не грузится")


# ================================================================ целая ночь ботом

func _bot_turn(b: Battle) -> void:
	for i in 6:
		var acts := b.legal_actions().filter(func(a): return a.type == "place")
		if acts.is_empty():
			break
		acts.sort_custom(func(x, y): return int(b.hand[x.hand].cost) > int(b.hand[y.hand].cost))
		b.apply(acts[0])
	b.apply({"type": "play"})


func _play_night(r: Run, rng: RandomNumberGenerator) -> int:
	var steps := 0
	while not r.is_over() and steps < 2000:
		steps += 1
		match r.state:
			"grid":
				r.choose(LogicUtil.pick(rng, r.available_moves()))
			"theory", "segment":
				var cs := r.choices()
				if cs.is_empty():
					failures.append("нет выбора в %s" % r.current_offer().get("kind", ""))
					return steps
				r.resolve(LogicUtil.pick(rng, cs))
			"battle":
				var b := r.start_battle()
				if b.over:
					if _has(r.finish_battle(b), "no_signal"):
						r.use_rewind(b, rng.randi_range(0, 1) == 0)
				else:
					_bot_turn(b)
	return steps


func test_full_nights_with_simple_bot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var meta := Meta.new_meta()
	for n in 4:
		var r := Run.new_night(meta, 500 + n, n == 0)
		_play_night(r, rng)
		check(r.is_over(), "ночь %d закончилась" % n)
		check(r.result in ["win", "lose"], "")
		check(r.report().row >= 0, "")
		for c in r.deck:
			check(not Meta.LOCKED.cards.has(c.id) or Meta.unlocks(meta).cards.has(c.id), "закрытый вкладыш в колоде")
		var back := _roundtrip(r)
		check_eq(JSON.stringify(back.to_dict()), JSON.stringify(r.to_dict()), "итог ночи сохраняется")
		meta = Meta.after_night(meta, r.report()).meta
	check_eq(meta.nights, 4, "")


# ================================================================ мета

func test_meta_eyes() -> void:
	var m := Meta.new_meta()
	for want in [1, 2, 3, 3]:
		var res := Meta.after_night(m, {"result": "lose", "row": 2})
		m = res.meta
		check_eq(m.eyes, want, "глаз-перебежчик")
	check_eq(Meta.eyes(m), 3, "не больше 3")
	check_eq(_run(1, false, m).eyes, 3, "глаза → подмигивания в забеге")
	var won := Meta.after_night(m, {"result": "win", "row": 8})
	check_eq(won.meta.eyes, 0, "после победы глаза возвращаются")
	check(won.events.any(func(e): return e.t == "eyes_returned"), "")
	check_eq(won.meta.wins, 1, "")
	check_eq(m.eyes, 3, "after_night не меняет переданную мету")


func test_meta_letters_count_and_order() -> void:
	var m := Meta.new_meta()
	var r := Meta.after_night(m, {"result": "lose", "row": 2})
	check_eq(r.letters.size(), 1, "рано проиграл — 1 письмо")
	check_eq(r.letters[0].id, Meta.LETTERS[0].id, "письма по порядку")
	check(String(r.letters[0].note) != "", "подпись к открытию")
	r = Meta.after_night(r.meta, {"result": "lose", "row": 5})
	check_eq(r.letters.size(), 2, "дошёл до 01:00 — 2 письма")
	r = Meta.after_night(r.meta, {"result": "win", "row": 8})
	check_eq(r.letters.size(), 3, "победа — 3 письма")
	check_eq(r.meta.letters.size(), 6, "")
	check(Meta.is_unlocked(r.meta, "card", "lis"), "письмо открыло Лису")
	check(Meta.is_unlocked(r.meta, "starter", "flyers"), "и Летунов")
	for i in 5:
		r = Meta.after_night(r.meta, {"result": "win", "row": 8})
	check_eq(r.meta.letters.size(), Meta.LETTERS.size(), "все письма прочитаны")
	check_eq(r.letters.size(), 0, "больше писем нет")


func test_letters_unlock_exactly_the_locked_content() -> void:
	var opened := {}
	for l in Meta.LETTERS:
		var u: Dictionary = l.unlock
		var key: String = Meta.KIND_KEYS[u.kind]
		check(Meta.LOCKED[key].has(u.id), "письмо %s открывает закрытое" % l.id)
		check(not opened.has(key + u.id), "одно открытие — одно письмо")
		opened[key + u.id] = true
		check(not Meta.unlock_note(u).is_empty(), "")
		check(String(l.text).length() < 300, "письмо короткое: %s" % l.id)
	var total := 0
	for key in Meta.LOCKED:
		total += Meta.LOCKED[key].size()
	check_eq(opened.size(), total, "всё закрытое открывается письмами")
	check(Meta.LETTERS.size() >= 10, "около 10 писем")


func test_unlocks_feed_the_run() -> void:
	var m := Meta.new_meta()
	var u := Meta.unlocks(m)
	for key in Meta.LOCKED:
		for id in Meta.LOCKED[key]:
			check(not u[key].has(id), "%s закрыт в первую ночь" % id)
	check_eq(Run.new_night(m, 1, false, "flyers").starter, "basic", "закрытый набор не выбрать")
	for i in Meta.LETTERS.size():
		m = Meta.after_night(m, {"result": "win", "row": 8}).meta
	var r := Run.new_night(m, 1, false, "flyers")
	check_eq(r.starter, "flyers", "Летуны открыты")
	check_eq(r.deck.map(func(c): return c.id), Meta.STARTERS.flyers.cards, "колода Летунов")
	check_eq(r.pockets, ["knock", null, null], "")
	check(r.unlocks.cards.has("shatun") and r.unlocks.theories.has("sleepy"), "открытое попадает в забег")


func test_meta_survives_json() -> void:
	var m: Dictionary = Meta.after_night(Meta.new_meta(), {"result": "lose", "row": 6}).meta
	var back := Meta.normalize(JSON.parse_string(JSON.stringify(m)))
	check_eq(JSON.stringify(back), JSON.stringify(m), "мета переживает JSON")
	check_eq(typeof(back.eyes), TYPE_INT, "")
	var old := Meta.normalize({"eyes": 2.0})
	check(old.unlocked.has("cards") and old.eyes == 2, "старое сохранение дополняется")
