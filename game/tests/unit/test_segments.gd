extends TestCase
## Рубрики: Розыгрыш, Телемагазин, Разбор, Пиратский ларёк, Подарок от спонсора, Помехи.


func _run(seed_value := 3) -> Run:
	return Run.new_night(Meta.new_meta(), seed_value, false)


func _offer(r: Run, kind: String, opts := {}) -> Dictionary:
	return Segments.offer(kind, r, r.rng, opts)


func _denied(ev: Array) -> bool:
	return ev.any(func(e): return e.t == "deny")


func test_raffle_offers_three_unlocked_and_pick_adds_card() -> void:
	var r := _run()
	var o := _offer(r, "raffle")
	check_eq(o.cards.size(), 3, "1 из 3")
	var ids: Array = o.cards.map(func(c): return c.id)
	check(ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2], "вкладыши разные")
	for id in ids:
		check(r.unlocks.cards.has(id), "только открытые вкладыши")
	var n := r.deck.size()
	var ev := Segments.apply(r, o, {"pick": 1})
	check(not _denied(ev), "выбор принят")
	check_eq(r.deck.size(), n + 1, "вкладыш в колоде")
	check_eq(r.deck[-1].id, ids[1], "тот самый")
	check(o.done, "розыгрыш закончен")
	check(_denied(Segments.apply(r, o, {"pick": 0})), "второй раз не выбрать")


func test_rarity_weights() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pool: Array = CardDB.CARDS.keys()
	var count := {"common": 0, "uncommon": 0, "rare": 0}
	for i in 600:
		for id in Segments.roll_cards(pool, rng, 1):
			count[CardDB.CARDS[id].rarity] += 1
	check(count.common > count.uncommon and count.uncommon > count.rare and count.rare > 0, "веса классов: %s" % count)


func test_rare_roll_falls_back_to_lower_class() -> void:
	var rng := RandomNumberGenerator.new()
	var pool := ["yozh", "volk", "los", "zhaba", "filin"]
	var ids := Segments.roll_cards(pool, rng, 3, ["rare"])
	check_eq(ids.size(), 3, "добрали до трёх")
	check(ids.has("filin"), "единственный редкий — в предложении")
	var lows: Array = ids.filter(func(id): return id != "filin")
	for id in lows:
		check_eq(CardDB.CARDS[id].rarity, "uncommon", "добор классом ниже")


func test_locked_cards_never_offered() -> void:
	var r := _run(9)
	var locked: Array = Meta.LOCKED.cards
	for i in 120:
		var o := _offer(r, "raffle", {"rarities": ["rare"]} if i % 2 == 0 else {})
		for c in o.cards:
			check(not locked.has(c.id), "закрытый вкладыш %s в розыгрыше" % c.id)
		var s := _offer(r, "shop")
		for lot in s.lots:
			if lot.has("card"):
				check(not locked.has(lot.card.id), "закрытый вкладыш %s в Телемагазине" % lot.card.id)
			if lot.has("item"):
				check(lot.item != "batteries", "закрытый предмет в Телемагазине")
		for it in _offer(r, "sponsor").items:
			check(it != "batteries", "закрытый предмет у спонсора")
	for i in 30:
		check(not Meta.LOCKED.glitches.has(_offer(r, "glitch").scene), "закрытая помеха")


func test_shop_lots_and_prices() -> void:
	var r := _run()
	var o := _offer(r, "shop")
	var cards: Array = o.lots.filter(func(l): return l.type == "card")
	var items: Array = o.lots.filter(func(l): return l.type == "item")
	var bundles: Array = o.lots.filter(func(l): return l.type == "bundle")
	check_eq(cards.size(), 3, "3 вкладыша")
	check_eq(items.size(), 2, "2 предмета")
	check_eq(bundles.size(), 1, "лот «Но это ещё не всё!»")
	check_eq(cards.map(func(l): return l.price), [3, 5, 8], "цены 3, 5, 8")
	check(items[0].item in ["cassette", "antenna"], "кассета или антенна — только здесь")
	check(CardDB.COMMON_ITEMS.has(items[1].item), "обычный предмет")
	check(bundles[0].hidden and CardDB.COMMON_ITEMS.has(bundles[0].item), "в лоте случайный предмет, скрыт")


func test_shop_buying() -> void:
	var r := _run()
	var o := _offer(r, "shop")
	r.fantiki = 4
	check_eq(Segments.check(r, o, {"buy": 1}), "money", "на 5 фантиков не хватает")
	var n := r.deck.size()
	var ev := Segments.apply(r, o, {"buy": 0})
	check(not _denied(ev), "покупка за 3")
	check_eq(r.fantiki, 1, "фантики списаны")
	check_eq(r.deck.size(), n + 1, "вкладыш в колоде")
	check_eq(Segments.check(r, o, {"buy": 0}), "sold", "второй раз не продаётся")
	r.fantiki = 50
	# кассета и антенна действуют сразу, карманы не занимают
	o.lots[3].item = "cassette"
	Segments.apply(r, o, {"buy": 3})
	check_eq(r.rewinds, 3, "Чистая кассета: +1 перемотка")
	check_eq(r.pockets, ["tape", null, null], "кассета не в кармане")
	var o2 := _offer(r, "shop")
	o2.lots[3].item = "antenna"
	Segments.apply(r, o2, {"buy": 3})
	check_eq(r.signal_bonus, 1, "Комнатная антенна: +1 Сигнал")
	var o3 := _offer(r, "shop")
	check_eq(o3.lots[3].item, "cassette", "антенна одна на ночь")
	# лот: вкладыш + предмет
	var b: Dictionary = o3.lots[5]
	n = r.deck.size()
	Segments.apply(r, o3, {"buy": 5})
	check_eq(r.deck.size(), n + 1, "лот: вкладыш")
	check_eq(r.pockets[1], b.item, "лот: предмет в кармане")
	check(not b.hidden, "предмет лота раскрыт")
	# полные карманы — предмет не купить
	r.pockets = ["tape", "gum", "remote"]
	check_eq(Segments.check(r, o3, {"buy": 4}), "pockets", "карманы полны")
	ev = Segments.apply(r, o3, {"leave": true})
	check(o3.done, "повесили трубку")


func test_review_options() -> void:
	var r := _run()
	var o := _offer(r, "review")
	var volk := r.deck.map(func(c): return c.id).find("volk")
	Segments.apply(r, o, {"card": volk, "option": "lead"})
	check(r.deck[volk].atk == 4 and r.deck[volk].hp == 3 and r.deck[volk].reviewed, "Главная роль +1/+1, наклейка")
	check(o.done, "один разбор за рубрику")
	o = _offer(r, "review")
	check_eq(Segments.check(r, o, {"card": volk, "option": "double"}), "reviewed", "каждый вкладыш — один раз")
	var gor := r.deck.map(func(c): return c.id).find("gornostay")
	Segments.apply(r, o, {"card": gor, "option": "double"})
	check_eq(r.deck[gor].hp, 5, "Дублёр +3 здоровья")
	o = _offer(r, "review")
	var yozh := r.deck.map(func(c): return c.id).find("yozh")
	check_eq(Segments.check(r, o, {"card": yozh, "option": "cheap"}), "cost", "дешевле 1 не бывает")
	var zay := r.deck.map(func(c): return c.id).find("zayats")
	Segments.apply(r, o, {"card": zay, "option": "cheap"})
	check_eq(r.deck[zay].cost, 1, "Удешевить −1")
	for c in Segments.choices(r, _offer(r, "review")):
		if c.has("card"):
			check(not r.deck[c.card].reviewed, "в списке выборов нет разобранных")


func test_pirate_copy_and_sell() -> void:
	var r := _run()
	var o := _offer(r, "pirate")
	var volk := r.deck.map(func(c): return c.id).find("volk")
	var n := r.deck.size()
	Segments.apply(r, o, {"copy": volk})
	var copy: Dictionary = r.deck[-1]
	check_eq(r.deck.size(), n + 1, "копия в колоде")
	check_eq(copy.name, "Валк", "имя с опечаткой")
	check(copy.pirate and copy.hp == 1 and copy.atk == 3, "бледная, −1 здоровье")
	check(not r.deck[volk].pirate, "оригинал не тронут")
	check_eq(Segments.check(r, o, {"copy": volk}), "limit", "одна копия за визит")
	var o2 := _offer(r, "pirate")
	check_eq(Segments.check(r, o2, {"copy": r.deck.size() - 1}), "pirate", "с пиратки не копируют")
	var f := r.fantiki
	Segments.apply(r, o2, {"sell": 0})
	check_eq(r.fantiki, f + 2, "сдать за 2 фантика")
	check_eq(r.deck.size(), n, "вкладыш убран")
	Segments.apply(r, o2, {"sell": 0})
	check_eq(Segments.check(r, o2, {"sell": 0}), "limit", "сдать не больше 2 за визит")
	r.deck.resize(Segments.DECK_MIN)
	check_eq(Segments.check(r, _offer(r, "pirate"), {"sell": 0}), "deck_min", "колода не меньше 6")


func test_pirate_copy_min_hp_one() -> void:
	var c := Segments.pirate_copy(CardDB.make("belka"))
	check_eq(c.hp, 1, "здоровье не ниже 1")
	check_eq(c.name, "Белко", "")
	check_eq(Segments.pirate_copy(CardDB.make("barsuk")).short, "Борсук", "короткая подпись для длинного имени")


func test_pirate_names_for_every_card() -> void:
	for id in CardDB.CARDS:
		check(Segments.PIRATE_NAMES.has(id), "нет опечатки для %s" % id)
		check(Segments.PIRATE_NAMES.get(id, CardDB.CARDS[id].name) != CardDB.CARDS[id].name, "опечатка отличается: %s" % id)
	check_eq(Segments.auto_typo("Сова"), "Сава", "запасная опечатка")
	check_eq(Segments.auto_typo("Ёж"), "Ёжъ", "")


func test_sponsor_pick_and_swap() -> void:
	var r := _run()
	var o := _offer(r, "sponsor")
	check_eq(o.items.size(), 3, "1 из 3")
	Segments.apply(r, o, {"pick": 2})
	check_eq(r.pockets[1], o.items[2], "в свободный карман")
	r.pockets = ["tape", "gum", "remote"]
	o = _offer(r, "sponsor")
	check_eq(Segments.check(r, o, {"pick": 0}), "pockets", "карманы полны — нужна замена")
	var ev := Segments.apply(r, o, {"pick": 0, "slot": 1})
	check(not _denied(ev), "замена")
	check_eq(r.pockets[1], o.items[0], "предмет заменён")
	check(ev.any(func(e): return e.t == "lose_item" and e.item == "gum"), "старый предмет ушёл")


func test_every_glitch_scene_every_choice() -> void:
	for id in Segments.GLITCHES:
		var opts: Array = Segments.GLITCHES[id].options
		check(opts.size() >= 2 and opts.size() <= 3, "2–3 варианта в «%s»" % id)
		var probe := _run()
		probe.unlocks.glitches = [id]
		var o := _offer(probe, "glitch")
		check_eq(o.scene, id, "")
		for c in Segments.choices(probe, o):
			var r := _run()
			r.unlocks.cards = CardDB.CARDS.keys()
			r.unlocks.glitches = [id]
			var oo := _offer(r, "glitch")
			var ev := Segments.apply(r, oo, c)
			check(not _denied(ev), "помеха %s, выбор %s" % [id, c])
			check(oo.done and r.seen_glitches.has(id), "помеха закончилась")
	check_eq(Segments.GLITCHES.size(), 6, "6 помех")


func _glitch_run(id: String) -> Run:
	var r := _run()
	r.unlocks.cards = CardDB.CARDS.keys()
	r.unlocks.glitches = [id]
	return r


func test_glitch_effects() -> void:
	var r := _glitch_run("neighbor")
	var o := _offer(r, "glitch")
	var yozh := r.deck.map(func(c): return c.id).find("yozh")
	Segments.apply(r, o, {"pick": 0, "card": yozh})
	check_eq(r.signal_penalty, 1, "сосед: −1 Сигнал в следующей серии")
	check_eq(CardDB.CARDS[r.deck[yozh].id].rarity, "uncommon", "вкладыш классом выше")
	r = _glitch_run("ripple")
	o = _offer(r, "glitch")
	var volk := r.deck.map(func(c): return c.id).find("volk")
	Segments.apply(r, o, {"pick": 0, "card": volk})
	check(r.deck[volk].id != "volk" and r.deck[volk].cost == 3, "рябь: другой вкладыш той же цены")
	r = _glitch_run("tracking")
	Segments.apply(r, _offer(r, "glitch"), {"pick": 0})
	check_eq(r.fantiki, 2, "трекинг: +2 фантика")
	r = _glitch_run("chew")
	var n := r.deck.size()
	Segments.apply(r, _offer(r, "glitch"), {"pick": 0})
	check(r.rewinds == 1 and r.deck.size() == n + 1 and CardDB.CARDS[r.deck[-1].id].rarity == "rare", "видик: −1 перемотка, редкий")
	r.rewinds = 0
	r.seen_glitches.clear()
	check(not _offer(r, "glitch").options[0].ok, "без перемоток карандашом не вытащить")
	r = _glitch_run("surge")
	Segments.apply(r, _offer(r, "glitch"), {"pick": 0, "card": volk})
	check(r.deck[volk].atk == 4 and r.deck[volk].hp == 1, "скачок: +1 атака, −1 здоровье")
	check_eq(Segments.check(r, _offer(r, "glitch"), {"pick": 0, "card": volk}), "card", "хилого не подзарядить")


func test_choices_are_all_valid() -> void:
	for kind in Segments.KINDS:
		for s in 6:
			var r := _run(40 + s)
			r.fantiki = 10
			var o := _offer(r, kind)
			var cs := Segments.choices(r, o)
			check(not cs.is_empty(), "у рубрики %s есть выбор" % kind)
			for c in cs:
				check_eq(Segments.check(r, o, c), "", "%s %s" % [kind, c])
