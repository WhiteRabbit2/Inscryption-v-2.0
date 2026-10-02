extends TestCase
## Боты: только разрешённые ходы, бой доводят до конца, умный сильнее простого, одинаковый сид — одинаковый бой.

const EMPTY_EP := {"id": "t", "name": "проверка", "level": 1, "turns": [], "loop": []}
const SEEDS := [3, 11, 29, 47, 61, 83, 97, 131]


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _mid_deck() -> Array:
	var d := CardDB.starter_deck()
	for id in ["kvaksha", "krot", "sova", "soroka", "filin", "lis"]:
		d.append(CardDB.make(id))
	return d


## Применяет действия, проверяя, что каждое есть среди legal_actions() и бой его не отклонил.
func _apply_checked(b: Battle, acts: Array, who: String) -> bool:
	for a in acts:
		if not b.legal_actions().has(a):
			check(false, "%s: недопустимое действие %s (ход %d)" % [who, str(a), b.turn])
			return false
		var ev := b.apply(a)
		if ev.any(func(e): return e.t == "deny"):
			check(false, "%s: бой отклонил %s" % [who, str(a)])
			return false
	return true


func _play_checked(b: Battle, kind: String, rng: RandomNumberGenerator) -> void:
	for guard in 60:
		if b.over:
			return
		for step in 4:
			var acts: Array = Bot.smart_turn(b, rng) if kind == "smart" else Bot.simple_turn(b, rng)
			if acts.is_empty() or not _apply_checked(b, acts, kind):
				break
			if kind == "simple":
				break
		b.apply({"type": "play"})
	check(b.over, "%s: бой не закончился за 60 ходов" % kind)


func test_bots_emit_only_legal_actions() -> void:
	var eps: Array = [Episodes.POOLS[1][0], Episodes.POOLS[2][0], Episodes.POOLS[3][1], Episodes.BOSS]
	for i in eps.size():
		for kind in ["simple", "smart"]:
			var b := Battle.create(eps[i], _mid_deck(), ["tape", "slipper", "knock"], {"winks": 2}, 100 + i)
			_play_checked(b, kind, _rng(5 + i))


func test_smart_uses_all_item_kinds_legally() -> void:
	# предметы, меняющие руку и искры (жвачка, батарейки), и пульт — тоже только разрешённым ходом
	for s in SEEDS.slice(0, 4):
		var b := Battle.create(Episodes.POOLS[2][1], CardDB.starter_deck(), ["gum", "batteries", "remote"], {}, s)
		_play_checked(b, "smart", _rng(s))


func test_both_bots_finish_battles() -> void:
	for kind in ["simple", "smart"]:
		for ep in [Episodes.TUTORIAL, Episodes.POOLS[0][1], Episodes.POOLS[3][2], Episodes.BOSS]:
			var b := Battle.create(ep, CardDB.starter_deck(), ["tape", null, null], {}, 7)
			var r := Bot.play_battle(b, kind, _rng(1))
			check(r.result == "win" or r.result == "lose", "%s / %s: итог %s" % [kind, ep.id, r.result])
			check_eq(r.illegal, 0, "%s / %s: недопустимых ходов" % [kind, ep.id])
			check(r.pauses >= r.turns and r.turns > 0, "%s / %s: счётчики ходов" % [kind, ep.id])


func test_smart_beats_simple() -> void:
	# потяжелее обычного (Плёнка +6), иначе оба выигрывают всё
	var score := {"simple": 0, "smart": 0}
	var wins := {"simple": 0, "smart": 0}
	for ep0 in [Episodes.POOLS[3][1], Episodes.POOLS[3][2], Episodes.BOSS]:
		var ep: Dictionary = ep0.duplicate(true)
		ep.film = int(ep.get("film", 5)) + 6
		if ep.has("phase2"):
			ep.phase2.film = int(ep.phase2.film) + 6
		for s in SEEDS:
			for kind in ["simple", "smart"]:
				var b := Battle.create(ep, CardDB.starter_deck(), ["tape", null, null], {}, s)
				var r := Bot.play_battle(b, kind, _rng(s), {"measure": false})
				wins[kind] += 1 if r.result == "win" else 0
				score[kind] += (100 if r.result == "win" else 0) - r.turns + b.sig
	check(wins.smart >= wins.simple, "умный выигрывает не реже простого: %s" % str(wins))
	check(score.smart > score.simple, "умный в среднем сильнее: %s" % str(score))


func test_same_seed_same_battle() -> void:
	for kind in ["simple", "smart"]:
		var out := []
		for k in 2:
			var b := Battle.create(Episodes.POOLS[2][2], CardDB.starter_deck(), ["tape", null, null], {}, 4242)
			var r := Bot.play_battle(b, kind, _rng(99), {"rewinds": 2})
			out.append(JSON.stringify(r) + JSON.stringify(b.to_dict()))
		check_eq(out[0], out[1], "%s: тот же сид — тот же бой" % kind)


func test_only_play_is_no_choice() -> void:
	var b := Battle.create(EMPTY_EP, CardDB.starter_deck(), [null, null, null], {}, 1)
	b.hand.clear()
	var info := Bot.analyze(b, _rng(1))
	check(info.pass and info.no_choice, "пустая рука — пауза без выбора")
	check(info.actions.is_empty(), "делать нечего")
	check(Bot.simple_turn(b, _rng(1)).is_empty(), "простому тоже")


func _setup_lane_test(hand_ids: Array, frame: Array, plans: Array) -> Battle:
	var b := Battle.create(EMPTY_EP, CardDB.starter_deck(), [null, null, null], {}, 1)
	b.hand.clear()
	for id in hand_ids:
		var c := CardDB.make(id)
		c.uid = b._next_uid()
		c.src = {"atk": c.atk, "hp": c.hp, "cost": c.cost, "badges": c.badges.duplicate()}
		b.hand.append(c)
	b.gazes.clear()
	for i in frame.size():
		var g := Gaze.make({"lane": frame[i], "habit": "fixed"})
		g.plan = plans[i]
		g.base = plans[i]
		b.gazes.append(g)
	return b


func test_smart_takes_the_win() -> void:
	var b := _setup_lane_test(["volk", "yozh"], [2], [2])
	b.film = 3
	b.sparks = 3
	b.tape[0] = b._creature("bity", 0)
	var acts := Bot.smart_turn(b, _rng(1))
	_apply_checked(b, acts, "smart")
	b.apply({"type": "play"})
	check_eq(b.result, "win", "волк в кадре по пустой клетке добивает Плёнку")


func test_smart_blocks_lethal_hit() -> void:
	var b := _setup_lane_test(["yozh", "zayats"], [1, 3], [1, 3])
	b.sig = 2
	b.film = 5
	b.sparks = 1
	b.tape[1] = b._creature("bity", 1)  # 2/1 в кадре по пустой клетке — смерть
	var acts := Bot.smart_turn(b, _rng(1))
	check_eq(acts, [{"type": "place", "hand": 0, "lane": 1}], "ёж закрывает удар")
	var simple := Bot.simple_turn(b, _rng(1))
	check_eq(simple, [{"type": "place", "hand": 0, "lane": 1}], "простой тоже закрывает тварь")


func test_smart_prefers_lit_lane_and_plan() -> void:
	# кадр — полоса 0, пунктир — полоса 3: горностай в кадр бьёт сразу, а не за кадр
	var b := _setup_lane_test(["gornostay"], [0], [3])
	b.sparks = 2
	var acts := Bot.smart_turn(b, _rng(1))
	check_eq(acts, [{"type": "place", "hand": 0, "lane": 0}], "в кадр")


func test_rewinds_are_used_on_loss() -> void:
	var b := Battle.create(Episodes.POOLS[3][1], [CardDB.make("gusenitsa"), CardDB.make("gusenitsa")],
		[null, null, null], {"signal": 2}, 5)
	var r := Bot.play_battle(b, "simple", _rng(1), {"rewinds": 2})
	check_eq(r.result, "lose", "гусеницами не отбиться")
	check_eq(r.rewinds_used, 2, "обе перемотки потрачены")
	check(r.plays > r.turns, "переигранные ходы считаются в plays")
