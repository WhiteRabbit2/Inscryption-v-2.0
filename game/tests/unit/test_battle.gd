extends TestCase
## Правила боя: взгляд, одновременная сцена, искры, значки, перемотка.

const EMPTY_EP := {"id": "t", "name": "проверка", "level": 1, "turns": [], "loop": []}


## Бой с пустым сценарием и заданной рукой (колода — копии одной карты, чтобы добор был предсказуем).
func _battle(hand_ids: Array, ep := EMPTY_EP, over := {}) -> Battle:
	var deck := []
	for i in 10:
		deck.append(CardDB.make("gornostay"))
	var b := Battle.create(ep, deck, ["tape", null, null], over, 7)
	b.hand.clear()
	for id in hand_ids:
		var c := CardDB.make(id)
		c.uid = b._next_uid()
		c.src = {"atk": c.atk, "hp": c.hp, "cost": c.cost, "badges": c.badges.duplicate()}
		b.hand.append(c)
	b.sparks = 5
	return b


func _put_tape(b: Battle, lane: int, id: String) -> Dictionary:
	b.tape[lane] = b._creature(id, lane)
	return b.tape[lane]


func _set_gazes(b: Battle, lanes: Array, plans: Array = []) -> void:
	b.gazes.clear()
	for i in lanes.size():
		var g := Gaze.make({"lane": lanes[i], "habit": "fixed"})
		g.plan = plans[i] if i < plans.size() else lanes[i]
		g.base = g.plan
		b.gazes.append(g)


func test_hit_in_frame_takes_film() -> void:
	var b := _battle(["volk"])
	_set_gazes(b, [0])
	b.apply({"type": "place", "hand": 0, "lane": 0})
	b.apply({"type": "play"})
	check_eq(b.film, 2, "волк 3 в кадре по пустой клетке: плёнка 5-3")


func test_hit_off_frame_does_nothing() -> void:
	var b := _battle(["volk"])
	_set_gazes(b, [1])
	b.apply({"type": "place", "hand": 0, "lane": 0})
	var ev := b.apply({"type": "play"})
	check_eq(b.film, 5, "за кадром удар в пустоту не засчитывается")
	var off := ev.filter(func(e): return e.t == "strike" and e.target == "offscreen")
	check_eq(off.size(), 1, "событие «за кадром»")


func test_offscreen_param_one() -> void:
	var b := _battle(["volk"], EMPTY_EP, {"offscreen": 1})
	_set_gazes(b, [1])
	b.apply({"type": "place", "hand": 0, "lane": 0})
	b.apply({"type": "play"})
	check_eq(b.film, 4, "с параметром «вне кадра 1» снимается 1")


func test_quiet_counts_off_frame() -> void:
	var b := _battle(["krot"])
	_set_gazes(b, [3])
	b.apply({"type": "place", "hand": 0, "lane": 0})
	b.apply({"type": "play"})
	check_eq(b.film, 3, "Тихоня бьёт по плёнке и за кадром")


func test_simultaneous_trade() -> void:
	var b := _battle(["gornostay"])
	_set_gazes(b, [3])
	_put_tape(b, 0, "skleyka")  # 2/3
	b.apply({"type": "place", "hand": 0, "lane": 0})
	b.apply({"type": "play"})
	check(b.you[0] == null, "горностай 2/2 погибает от склейки 2")
	check(b.tape[0] != null and b.tape[0].hp == 1, "склейка получила 2 одновременно")


func test_creature_hits_signal_only_in_frame() -> void:
	var b := _battle([])
	_set_gazes(b, [0])
	_put_tape(b, 0, "bity")
	_put_tape(b, 2, "bity")
	b.apply({"type": "play"})
	check_eq(b.sig, 4, "в кадре тварь снимает сигнал, за кадром — нет")


func test_flying_over_and_tall_blocks() -> void:
	var b := _battle(["vorobey", "vorobey"])
	_set_gazes(b, [0, 1])
	_put_tape(b, 0, "pen")
	_put_tape(b, 1, "zatyorly")  # высокий
	b.apply({"type": "place", "hand": 0, "lane": 0})
	b.apply({"type": "place", "hand": 0, "lane": 1})
	b.apply({"type": "play"})
	check_eq(b.film, 4, "воробей перелетел пень, но не высокого лося")
	check_eq(b.tape[1].hp, 4, "высокий перехватил воробья")


func test_prickly_thorns() -> void:
	var b := _battle(["gornostay"])
	_set_gazes(b, [3])
	_put_tape(b, 0, "negayozh")  # 1/4 колючий
	b.apply({"type": "place", "hand": 0, "lane": 0})
	b.apply({"type": "play"})
	check(b.you[0] == null, "горностай 2/2: 1 от удара + 1 от колючек = погиб")


func test_star_bonus_in_frame() -> void:
	var b := _battle(["zayats", "zayats"])
	_set_gazes(b, [0])
	b.apply({"type": "place", "hand": 0, "lane": 0})
	b.apply({"type": "place", "hand": 0, "lane": 1})
	b.apply({"type": "play"})
	check_eq(b.film, 2, "заяц в кадре бьёт на 3, второй за кадром — 0")


func test_replay_hits_twice() -> void:
	var b := _battle(["barsuk"])
	_set_gazes(b, [0])
	b.apply({"type": "place", "hand": 0, "lane": 0})
	b.apply({"type": "play"})
	check_eq(b.film, 3, "барсук 1 × 2 удара")


func test_toon_flattens_once() -> void:
	var b := _battle(["kot"])
	_set_gazes(b, [3])
	_put_tape(b, 0, "skleyka")
	b.apply({"type": "place", "hand": 0, "lane": 0})
	var ev := b.apply({"type": "play"})
	check(b.you[0] != null and b.you[0].atk == 1 and b.you[0].hp == 1, "кот стал блином 1/1")
	check(ev.any(func(e): return e.t == "flatten"), "событие flatten")
	b.apply({"type": "play"})
	check(b.you[0] == null, "во второй раз блин погибает")
	check_eq(b.discard.size(), 1, "погибший уходит в сброс")
	check_eq(b.discard[0].atk, 2, "в сброс — с исходными цифрами")
	check(b.discard[0].badges.has("toon"), "и со значком")


func test_static_leaves_snow() -> void:
	var b := _battle(["volk"])
	_set_gazes(b, [3])
	_put_tape(b, 0, "bity")
	b.apply({"type": "place", "hand": 0, "lane": 0})
	b.apply({"type": "play"})
	check(b.tape[0] != null and b.tape[0].id == "sneg", "битый кадр оставил снег")


func test_sparks_income_and_carry() -> void:
	var b := _battle([])
	b.sparks = 4
	b.apply({"type": "play"})
	check_eq(b.sparks, 5, "2 в запас + 3 = 5")
	b.sparks = 0
	b.apply({"type": "play"})
	check_eq(b.sparks, 3, "без запаса — 3")


func test_cannot_place_without_sparks_or_on_occupied() -> void:
	var b := _battle(["volk", "yozh"])
	b.sparks = 2
	check(not b.can_place(0, 0), "волк стоит 3")
	check(b.can_place(1, 0), "ёж стоит 1")
	b.apply({"type": "place", "hand": 1, "lane": 0})
	b.sparks = 5
	check(not b.can_place(0, 0), "в занятую клетку нельзя")


func test_cameo_draws() -> void:
	var b := _battle(["belka"])
	var n := b.hand.size()
	b.apply({"type": "place", "hand": 0, "lane": 0})
	check_eq(b.hand.size(), n, "белка ушла из руки и принесла вкладыш")


func test_pan_habit_bounces() -> void:
	var g := Gaze.make({"lane": 2, "habit": "pan", "dir": 1})
	var b := _battle([])
	var seq := []
	for i in 6:
		Gaze.plan_base(g, b)
		g.lane = g.base
		seq.append(g.lane)
	check_eq(seq, [3, 2, 1, 0, 1, 2], "панорама разворачивается у края")


func test_closeup_habit() -> void:
	var g := Gaze.make({"lane": 0, "habit": "closeup", "dir": 1})
	var b := _battle([])
	var seq := [g.lane]
	for i in 7:
		Gaze.plan_base(g, b)
		g.lane = g.base
		seq.append(g.lane)
	check_eq(seq, [0, 0, 2, 2, 0, 0, 2, 2], "крупный план: 2 хода стоит, прыгает на 2")


func test_plan_becomes_frame_after_montage() -> void:
	var b := _battle([])
	_set_gazes(b, [0], [2])
	b.apply({"type": "play"})
	check_eq(b.gazes[0].lane, 2, "взгляд переехал на пунктир")


func test_stare_holds_gaze() -> void:
	var b := _battle(["motylek"])
	_set_gazes(b, [1], [2])
	var ev := b.apply({"type": "place", "hand": 0, "lane": 1})
	check_eq(b.gazes[0].plan, 1, "Гляделки удерживают пунктир на своей полосе")
	check(ev.any(func(e): return e.t == "gaze_plan" and e.by.begins_with("card:")), "стрелка «кто сдвинул»")


func test_mug_pulls_adjacent_plan() -> void:
	var b := _battle(["soroka"])
	_set_gazes(b, [0], [1])
	b.apply({"type": "place", "hand": 0, "lane": 2})
	check_eq(b.gazes[0].plan, 2, "Кривляка перетянула соседний пунктир")


func test_knock_and_remote_items() -> void:
	var b := _battle([])
	_set_gazes(b, [0], [1])
	b.items = ["knock", "remote", null]
	b.apply({"type": "item", "slot": 0, "gaze": 0, "dir": 1})
	check_eq(b.gazes[0].plan, 2, "Стукнуть сдвинул пунктир")
	check_eq(b.gazes[0].by, "knock", "")
	b.apply({"type": "item", "slot": 1})
	check_eq(b.gazes[0].plan, 0, "Пульт: взгляд не сдвинется")
	b.apply({"type": "play"})
	check_eq(b.gazes[0].lane, 0, "")
	check(b.items[0] == null and b.items[1] == null, "предметы израсходованы")


func test_slipper_and_tape_items() -> void:
	var b := _battle(["gornostay"])
	b.items = ["slipper", "tape", null]
	_put_tape(b, 2, "skleyka")
	b.apply({"type": "place", "hand": 0, "lane": 0})
	b.apply({"type": "item", "slot": 0, "lane": 2})
	check(b.tape[2] == null, "тапок прихлопнул склейку (3 здоровья)")
	b.apply({"type": "item", "slot": 1, "lane": 0})
	check_eq(b.you[0].hp, 4, "изолента +2")


func test_slipper_cannot_hit_boss() -> void:
	var b := _battle([])
	b.items = ["slipper", null, null]
	_put_tape(b, 1, "ulybaka")
	b.tape[1].hp = 2
	b.apply({"type": "item", "slot": 0, "lane": 1})
	check(b.tape[1] != null, "Улыбаку тапком не взять")
	check_eq(b.items[0], "slipper", "предмет не потрачен")


func test_sketch_inks_into_empty_cell_only() -> void:
	var ep := EMPTY_EP.duplicate(true)
	ep.turns = [[{"c": "bity", "lane": 2}]]
	var b := _battle([], ep)
	check(b.sketches[2] != null, "набросок нарисован в Монтаже до первого PLAY")
	b.apply({"type": "play"})
	check(b.tape[2] != null and b.tape[2].id == "bity", "набросок стал тварью")


func test_sketch_goes_to_nearest_free() -> void:
	var ep := EMPTY_EP.duplicate(true)
	ep.start = [{"c": "pen", "lane": 2}]
	ep.turns = [[{"c": "bity", "lane": 2}]]
	var b := _battle([], ep)
	check(b.sketches[2] == null and (b.sketches[1] != null or b.sketches[3] != null), "занято — ближайшая свободная")


func test_glitch_swaps_with_arrow() -> void:
	var b := _battle([])
	_set_gazes(b, [0])
	var w := _put_tape(b, 3, "perevolk")
	check_eq(w.glitch_dir, -1, "у правого края стрелка влево")
	_put_tape(b, 2, "pen")
	b.apply({"type": "play"})
	check(b.tape[2] != null and b.tape[2].id == "perevolk", "сбой поменялся местами")
	check(b.tape[3] != null and b.tape[3].id == "pen", "")


func test_win_and_lose() -> void:
	var b := _battle(["volk", "volk"])
	_set_gazes(b, [0, 1])
	b.film = 3
	b.apply({"type": "place", "hand": 0, "lane": 0})
	b.apply({"type": "play"})
	check(b.over and b.result == "win", "плёнка кончилась — победа")
	check_eq(b.stats.overkill, 0, "")
	var c := _battle([])
	_set_gazes(c, [0])
	c.sig = 2
	_put_tape(c, 0, "bity")
	c.apply({"type": "play"})
	check(c.over and c.result == "lose", "сигнал кончился — поражение")


func test_titles_tie_goes_to_player() -> void:
	var b := _battle([], EMPTY_EP, {"titles_turn": 1})
	_set_gazes(b, [0])
	b.film = 1
	b.sig = 1
	b.apply({"type": "play"})
	check_eq(b.result, "win", "обе шкалы в ноль на титрах — победа зрителя")


func test_squint_adds_gazes() -> void:
	var b := _battle([], EMPTY_EP, {"squint_turn": 2, "titles_turn": 99})
	_set_gazes(b, [0])
	b.apply({"type": "play"})
	check_eq(b.gazes.size(), 2, "присматривается: +1 взгляд")
	b.apply({"type": "play"})
	b.apply({"type": "play"})
	check_eq(b.gazes.size(), 4, "до 4 полос")
	b.apply({"type": "play"})
	check_eq(b.gazes.size(), 4, "больше не добавляет")


func test_rewind_restores_exact_state() -> void:
	var ep: Dictionary = Episodes.POOLS[1][0]
	var b := Battle.create(ep, CardDB.starter_deck(), ["tape", null, null], {}, 42)
	var start := JSON.stringify(b._snapshot())
	var hands := []
	for t in 30:
		if b.over:
			break
		hands.append(b.hand.map(func(c): return c.id))
		b.apply({"type": "play"})  # ничего не выкладываем — проиграем
	check(b.over and b.result == "lose", "без зверей сигнал кончается")
	var turn_lost := b.turn
	b.rewind(false)
	check(not b.over, "после перемотки бой продолжается")
	check_eq(b.turn, maxi(turn_lost - 1, 1), "на ход назад")
	b.rewind(true)
	check_eq(JSON.stringify(b._snapshot()), start, "к началу серии — всё как было, включая генератор")
	b.apply({"type": "play"})
	check_eq(b.hand.map(func(c): return c.id), hands[1], "та же раздача после перемотки")


func test_save_load_roundtrip_through_json() -> void:
	var b := Battle.create(Episodes.POOLS[2][0], CardDB.starter_deck(), ["tape", "gum", null], {}, 9)
	b.apply({"type": "play"})
	var text := JSON.stringify(b.to_dict())
	var c := Battle.from_dict(JSON.parse_string(text))
	check_eq(JSON.stringify(c._snapshot()), JSON.stringify(b._snapshot()), "сохранение и загрузка без потерь")
	b.apply({"type": "play"})
	c.apply({"type": "play"})
	check_eq(JSON.stringify(c._snapshot()), JSON.stringify(b._snapshot()), "и дальше идут одинаково")


func test_boss_phase_two_inverts() -> void:
	var b := Battle.create(Episodes.BOSS, CardDB.starter_deck(), [null, null, null], {}, 3)
	check_eq(b.gazes[0].lane, 1, "первый взгляд приклеен к Улыбаке")
	check(b.tape[1] != null and b.tape[1].id == "ulybaka", "")
	b.film = 1
	b.you[0] = CardDB.make("volk")
	b.you[0].uid = b._next_uid()
	b.you[0].side = "you"
	_set_gazes(b, [0])
	b.sketches.fill(null)
	var ev := b.apply({"type": "play"})
	check(ev.any(func(e): return e.t == "phase"), "переход во 2-ю фазу")
	check(not b.over, "бой продолжается")
	check_eq(b.phase, 2, "")
	check(bool(b.cfg.invert), "негатив")
	check_eq(b.film, 6, "")
	check(b.you[0] != null, "твои звери остаются")
	for l in Battle.LANES:
		check_eq(b.lit(l), not b.in_frame(l), "засчитывается то, что вне кадра")


func test_forecast_matches_scene() -> void:
	var b := Battle.create(Episodes.POOLS[1][2], CardDB.starter_deck(), [null, null, null], {}, 5)
	for i in b.hand.size():
		if b.can_place(0, i):
			b.apply({"type": "place", "hand": 0, "lane": i})
	var fc := b.compute_scene()
	var film0 := b.film
	var sig0 := b.sig
	b.apply({"type": "play"})
	if not b.over:
		check_eq(film0 - b.film, fc.film, "прогноз плёнки")
		check_eq(sig0 - b.sig, fc.signal, "прогноз сигнала")
