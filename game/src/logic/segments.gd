class_name Segments
extends RefCounted
## Рубрики между сериями (§13): Розыгрыш, Телемагазин, Разбор, Пиратский ларёк, Подарок от спонсора, Помехи.
## Те же рубрики выдают награды после серий (Ночной показ, Теории) — с opts.reason.
##
## offer(kind, run, rng, opts) — что предлагается (обычный словарь, переживает JSON);
## choices(run, offer)         — все разрешённые выборы (для ботов и проверки ввода);
## check(run, offer, choice)   — "" если выбор разрешён, иначе причина отказа;
## apply(run, offer, choice)   — применить выбор к забегу, вернуть события. Закончилась рубрика — offer.done = true.
## Телемагазин и Ларёк открыты, пока не выбран {"leave": true}; остальные закрываются после одного выбора.
##
## Выборы (i — номер в предложении, k — номер вкладыша в колоде забега run.deck):
##   raffle   {"pick": i} | {"skip": true}
##   shop     {"buy": i} | {"leave": true}
##   review   {"card": k, "option": "lead" | "double" | "cheap"} | {"skip": true}
##   pirate   {"copy": k} | {"sell": k} | {"leave": true}
##   sponsor  {"pick": i} | {"pick": i, "slot": s} — замена, если карманы полны | {"skip": true}
##   glitch   {"pick": i} | {"pick": i, "card": k} — если вариант просит вкладыш (у варианта есть "card")
##
## События: gain_card {card, index}, lose_card {card, index}, card_changed {card, index},
##   card_replaced {old, card, index}, fantiki {value, delta, why}, gain_item {item, slot}, lose_item {item, slot},
##   rewinds {value, delta}, signal_bonus {value}, signal_penalty {value}, line {text}, deny {why}, done {kind}.
## Случайности при apply берутся из run.rng — он сохраняется вместе с забегом.

const RARITY_ORDER := ["common", "uncommon", "rare"]
const RARITY_WEIGHTS := {"common": 60, "uncommon": 30, "rare": 10}
const RAFFLE_SIZE := 3
const SPONSOR_SIZE := 3
## Цены Телемагазина в фантиках. Вкладыши — по классу (3 / 5 / 8), item — обычный предмет.
const SHOP_PRICES := {"common": 3, "uncommon": 5, "rare": 8, "cassette": 6, "antenna": 4, "item": 3, "bundle": 6}
const SELL_PRICE := 2
const DECK_MIN := 6
## Решение, где документ молчит: в Ларьке за визит 1 пиратская копия и не больше 2 сданных вкладышей.
const PIRATE_COPIES := 1
const PIRATE_SELLS := 2

## Рубрики: название, шапка в газете, подписи для газеты (выбираются случайно), реплика ведущего в костюме.
const KINDS := {
	"raffle": {
		"name": "Розыгрыш", "title": "РОЗЫГРЫШ",
		"subs": ["Разворачиваем жвачку в прямом эфире", "Вкладыш каждому третьему. Остальным — жвачка",
			"Призы от спонсора. Спонсор просил не уточнять"],
		"line": "Барабан крутится, шары прыгают. Тяните, пока я не передумал.",
	},
	"shop": {
		"name": "Телемагазин", "title": "ТЕЛЕМАГАЗИН",
		"subs": ["Звоните прямо сейчас! Операторы почти не спят", "Но это ещё не всё!",
			"Цены ниже плинтуса. Плинтус у нас высокий"],
		"line": "Звоните прямо сейчас! Первым трём дозвонившимся — ничего, но с выражением.",
	},
	"review": {
		"name": "Разбор", "title": "РАЗБОР",
		"subs": ["Крупный план, лупа и красный маркер", "Обратите внимание на левый угол кадра",
			"Стоп-кадр. Перематываем. Ещё раз"],
		"line": "Берём вкладыш крупным планом. Сейчас найдём, за что его похвалить.",
	},
	"pirate": {
		"name": "Пиратский ларёк", "title": "ПИРАТСКИЙ ЛАРЁК",
		"subs": ["Копии с опечатками. Гарантия до выхода из ларька", "Перепишем что угодно. Даже то, что не надо",
			"Лицензия? Какая лицензия?"],
		"line": "Кепку надел — значит, я не я. Копии свежие, опечатки бесплатно.",
	},
	"sponsor": {
		"name": "Подарок от спонсора", "title": "ПОДАРОК ОТ СПОНСОРА",
		"subs": ["Жвачка «Опушка»: жуй и смотри", "Спонсор показа передаёт привет. И коробку",
			"Бесплатно. Почти без подвоха"],
		"line": "Спонсор показа — жвачка «Опушка». Берите один подарок, коробка у нас одна.",
	},
	"glitch": {
		"name": "Помехи", "title": "ПОМЕХИ",
		"subs": ["Технический перерыв. Не крутите ручки", "Изображение временно отсутствует. Как и смысл",
			"Не переключайтесь. Серьёзно, не надо"],
		"line": "Технические неполадки. Не крутите ручки. Ладно, крутите.",
	},
}

## Реплика вместо обычной, если рубрика — награда после серии.
const REASON_LINES := {
	"night": "Ночной показ досмотрели до конца. Держите вкладыш из-под прилавка.",
	"theory": "Теория подтвердилась! Ну, почти. Награда — по-настоящему.",
}

const REVIEW_OPTIONS := [
	{"id": "lead", "name": "Главная роль", "text": "+1 атака и +1 здоровье."},
	{"id": "double", "name": "Дублёр", "text": "+3 здоровья."},
	{"id": "cheap", "name": "Удешевить", "text": "−1 к цене, но не ниже 1."},
]

## Реплики после выбора.
const LINES := {
	"raffle": "Отличный вкладыш. Жвачку можете выплюнуть.",
	"skip": "Скромность украшает. Колоду — не очень.",
	"buy": "Заказ принят! Курьер — это вы.",
	"bundle": "Но это ещё не всё! В коробке нашлось: %s.",
	"lead": "Главная роль! Сейчас ему позавидует весь лес.",
	"double": "Дублёр: как он, только крепче. И зарплата меньше.",
	"cheap": "Удешевили. Теперь он по карману даже вам.",
	"copy": "Копия готова. Опечатка в подарок.",
	"sell": "Сдан! Деньги не пахнут. Фантики — немного жвачкой.",
	"sponsor": "Спонсор доволен. Спонсор всегда доволен.",
	"swap_item": "Старое — на антресоль, новое — в карман.",
}

## Пиратские имена — опечатки для каждого вкладыша CardDB.CARDS. Нет в таблице — auto_typo().
const PIRATE_NAMES := {
	"yozh": "Ёшь", "belka": "Белко", "vorobey": "Варабей", "gusenitsa": "Гусиница", "lisyonok": "Лисёнак",
	"gornostay": "Горнастай", "soroka": "Сарока", "zayats": "Заиц", "kot": "Чорный кот", "kvaksha": "Квакжа",
	"motylek": "Матылёк", "uzh": "Ушь", "surok": "Сурог", "volk": "Валк", "krot": "Кроть", "sova": "Сава",
	"barsuk": "Борсук-кинамеханик", "lis": "Лиза", "zhaba": "Жоба", "netopyr": "Нетапырь", "los": "Лосъ",
	"vepr": "Вепырь", "kabanchik": "Кобанчик", "filin": "Фелин", "shatun": "Шотун",
}
## Короткие подписи для длинных пиратских имён (у оригиналов есть CardDB.CARDS[id].short).
const PIRATE_SHORT := {"kot": "Котъ", "barsuk": "Борсук"}

## Помехи — короткие сценки. У варианта: card — какой вкладыш колоды он просит ("any", "upgradable", "sturdy"),
## after — реплика после выбора. Какие сценки открыты сразу, решает Meta.LOCKED.
const GLITCHES := {
	"ripple": {
		"name": "Рябь", "text": "По экрану пошла рябь. Один вкладыш в колоде тоже поплыл.",
		"options": [
			{"id": "swap", "text": "Обменять вкладыш на случайный той же цены", "card": "any",
				"after": "Был один зверь — стал другой. Никто не заметил. Даже он сам."},
			{"id": "pass", "text": "Переждать рябь", "after": "Рябь прошла. Осадочек остался."},
		],
	},
	"neighbor": {
		"name": "Сосед стучит по батарее", "text": "Три часа ночи — время тишины. По мнению соседа.",
		"options": [
			{"id": "loud", "text": "Сделать погромче: −1 Сигнал в следующей серии, зато вкладыш станет классом выше",
				"card": "upgradable", "after": "Сосед стучит в ритм. Почти аплодисменты."},
			{"id": "quiet", "text": "Сделать потише", "after": "Тише едешь — меньше слышишь. Логично."},
		],
	},
	"tracking": {
		"name": "Трекинг поехал", "text": "Картинка уползает вверх. На видике есть колёсико, его давно никто не трогал.",
		"options": [
			{"id": "wheel", "text": "Крутить колёсико: +2 фантика",
				"after": "Из-под видика выкатились фантики. Откуда — не спрашивайте."},
			{"id": "slap", "text": "Хлопнуть по корпусу: случайный предмет в карман",
				"after": "Из видика что-то выпало. Берите, пока он не передумал."},
		],
	},
	"surge": {
		"name": "Скачок напряжения", "text": "Лампочка в подъезде мигнула. Телевизор щёлкнул и задумался о вечном.",
		"options": [
			{"id": "charge", "text": "Подзарядить вкладыш: +1 атака, −1 здоровье", "card": "sturdy",
				"after": "Искрит. Значит, работает."},
			{"id": "unplug", "text": "Выдернуть вилку и переждать",
				"after": "Темнота. Тишина. Красота. Включаем обратно."},
		],
	},
	"rerun": {
		"name": "Повтор вчерашнего", "text": "По ошибке пустили вчерашнюю запись. Лица знакомые, сюжет тоже.",
		"options": [
			{"id": "watch", "text": "Досмотреть: копия случайного вкладыша из колоды",
				"after": "Повтор — мать учения. И колоды."},
			{"id": "switch", "text": "Переключить: +1 фантик",
				"after": "Переключили. На другом канале тот же повтор. Ладно."},
		],
	},
	"chew": {
		"name": "Видик жуёт кассету", "text": "Видик подозрительно хрустит. Внутри что-то есть, кроме плёнки.",
		"options": [
			{"id": "pull", "text": "Вытащить карандашом: −1 перемотка, редкий вкладыш",
				"after": "Плёнку спасли не всю. Зато нашли кое-что поинтереснее."},
			{"id": "stop", "text": "Нажать STOP", "after": "Хруст прекратился. Видик обиделся, но молчит."},
		],
	},
}


# ================================================================ предложение

static func offer(kind: String, run: Run, rng: RandomNumberGenerator, opts := {}) -> Dictionary:
	var reason := String(opts.get("reason", ""))
	var o := {"kind": kind, "reason": reason, "done": false, "line": REASON_LINES.get(reason, KINDS[kind].line)}
	match kind:
		"raffle":
			o.cards = []
			for id in roll_cards(run.unlocks.get("cards", []), rng, RAFFLE_SIZE, opts.get("rarities", [])):
				o.cards.append(CardDB.make(id))
		"shop":
			o.lots = _shop_lots(run, rng)
		"review":
			o.options = REVIEW_OPTIONS.duplicate(true)
			o.free = bool(opts.get("free", false))
		"pirate":
			o.copies_left = PIRATE_COPIES
			o.sells_left = PIRATE_SELLS
			o.sell_price = SELL_PRICE
		"sponsor":
			o.items = roll_items(run.unlocks.get("items", []), rng, SPONSOR_SIZE)
		"glitch":
			o.merge(_glitch_offer(run, rng))
	return o


## n разных вкладышей из pool (открытые id). rarities — из каких классов (пусто — из всех) по весам RARITY_WEIGHTS.
## Не хватает открытых вкладышей нужного класса — добираем классом ниже.
static func roll_cards(pool: Array, rng: RandomNumberGenerator, n: int, rarities: Array = [], exclude: Array = []) -> Array:
	var allowed: Array = RARITY_ORDER.duplicate() if rarities.is_empty() else rarities.duplicate()
	var out := []
	while out.size() < n:
		var by_r := _by_rarity(pool, allowed, exclude + out)
		var total := 0
		for r in by_r:
			total += int(RARITY_WEIGHTS[r])
		if total == 0:
			var low := RARITY_ORDER.size()
			for r in allowed:
				low = mini(low, RARITY_ORDER.find(r))
			if low <= 0:
				break
			allowed.append(RARITY_ORDER[low - 1])
			continue
		var roll := rng.randi_range(1, total)
		for r in RARITY_ORDER:
			if not by_r.has(r):
				continue
			roll -= int(RARITY_WEIGHTS[r])
			if roll <= 0:
				out.append(LogicUtil.pick(rng, by_r[r]))
				break
	return out


static func _by_rarity(pool: Array, allowed: Array, exclude: Array) -> Dictionary:
	var out := {}
	for id in pool:
		var r: String = CardDB.CARDS[id].rarity
		if allowed.has(r) and not exclude.has(id):
			if not out.has(r):
				out[r] = []
			out[r].append(id)
	return out


## n разных предметов из pool.
static func roll_items(pool: Array, rng: RandomNumberGenerator, n: int) -> Array:
	var a := pool.duplicate()
	LogicUtil.shuffle(rng, a)
	return a.slice(0, mini(n, a.size()))


static func _shop_lots(run: Run, rng: RandomNumberGenerator) -> Array:
	var cards: Array = run.unlocks.get("cards", [])
	var items: Array = run.unlocks.get("items", [])
	var lots := []
	var taken := []
	for r in RARITY_ORDER:
		var ids := roll_cards(cards, rng, 1, [r], taken)
		if ids.is_empty():
			continue
		taken.append(ids[0])
		lots.append({"type": "card", "card": CardDB.make(ids[0]), "price": int(SHOP_PRICES[CardDB.CARDS[ids[0]].rarity]),
			"sold": false})
	# Кассета и антенна продаются только здесь. Антенна — одна на ночь.
	var special := "cassette"
	if not run.flags.get("antenna", false) and rng.randi_range(0, 1) == 0:
		special = "antenna"
	lots.append({"type": "item", "item": special, "price": int(SHOP_PRICES[special]), "sold": false})
	var common := roll_items(items, rng, 1)
	if not common.is_empty():
		lots.append({"type": "item", "item": common[0], "price": int(SHOP_PRICES.item), "sold": false})
	# Лот «Но это ещё не всё!»: вкладыш плюс случайный предмет (предмет скрыт до покупки).
	var b_card := roll_cards(cards, rng, 1, ["common", "uncommon"], taken)
	var b_item := roll_items(items, rng, 1)
	if not b_card.is_empty() and not b_item.is_empty():
		lots.append({"type": "bundle", "name": "Но это ещё не всё!", "card": CardDB.make(b_card[0]), "item": b_item[0],
			"hidden": true, "price": int(SHOP_PRICES.bundle), "sold": false})
	return lots


static func _glitch_offer(run: Run, rng: RandomNumberGenerator) -> Dictionary:
	var open: Array = run.unlocks.get("glitches", [])
	var pool := []
	for id in open:
		if not run.seen_glitches.has(id):
			pool.append(id)
	if pool.is_empty():
		pool = open.duplicate()
	var id: String = LogicUtil.pick(rng, pool)
	var g: Dictionary = GLITCHES[id]
	var options := []
	for o in g.options:
		var oo: Dictionary = o.duplicate(true)
		oo.ok = _glitch_ok(run, oo)
		options.append(oo)
	return {"scene": id, "name": g.name, "text": g.text, "options": options}


# ================================================================ проверка и список выборов

## Все разрешённые выборы для текущего предложения.
static func choices(run: Run, o: Dictionary) -> Array:
	var cands := []
	var n := run.deck.size()
	match String(o.get("kind", "")):
		"raffle":
			for i in o.cards.size():
				cands.append({"pick": i})
			cands.append({"skip": true})
		"shop":
			for i in o.lots.size():
				cands.append({"buy": i})
			cands.append({"leave": true})
		"review":
			for k in n:
				for opt in REVIEW_OPTIONS:
					cands.append({"card": k, "option": opt.id})
			cands.append({"skip": true})
		"pirate":
			for k in n:
				cands.append({"copy": k})
				cands.append({"sell": k})
			cands.append({"leave": true})
		"sponsor":
			for i in o.items.size():
				cands.append({"pick": i})
				for s in run.pockets.size():
					cands.append({"pick": i, "slot": s})
			cands.append({"skip": true})
		"glitch":
			for i in o.options.size():
				if o.options[i].has("card"):
					for k in n:
						cands.append({"pick": i, "card": k})
				else:
					cands.append({"pick": i})
	return cands.filter(func(c): return check(run, o, c) == "")


## "" — выбор разрешён; иначе короткая причина отказа (для события deny).
static func check(run: Run, o: Dictionary, c: Dictionary) -> String:
	if o.get("done", false):
		return "done"
	var kind := String(o.get("kind", ""))
	if c.get("leave", false) or c.get("skip", false):
		return "" if kind in ["raffle", "shop", "review", "pirate", "sponsor"] else "choice"
	var why := "choice"
	match kind:
		"raffle":
			why = _check_index(c, "pick", o.cards.size())
		"shop":
			why = _check_shop(run, o, c)
		"review":
			why = _check_review(run, c)
		"pirate":
			why = _check_pirate(run, o, c)
		"sponsor":
			why = _check_sponsor(run, o, c)
		"glitch":
			why = _check_glitch(run, o, c)
	return why


static func _check_index(c: Dictionary, key: String, size: int) -> String:
	if not c.has(key):
		return "choice"
	var i := int(c[key])
	return "" if i >= 0 and i < size else "index"


static func _check_shop(run: Run, o: Dictionary, c: Dictionary) -> String:
	var why := _check_index(c, "buy", o.lots.size())
	if why != "":
		return why
	var lot: Dictionary = o.lots[int(c.buy)]
	if lot.sold:
		why = "sold"
	elif run.fantiki < int(lot.price):
		why = "money"
	elif _lot_needs_pocket(lot) and free_pocket(run) < 0:
		why = "pockets"
	return why


static func _lot_needs_pocket(lot: Dictionary) -> bool:
	if lot.type == "bundle":
		return true
	return lot.type == "item" and bool(CardDB.ITEMS[lot.item].battle)


static func _check_review(run: Run, c: Dictionary) -> String:
	var why := _check_index(c, "card", run.deck.size())
	if why != "":
		return why
	var card: Dictionary = run.deck[int(c.card)]
	var opt := String(c.get("option", ""))
	if card.get("reviewed", false):
		why = "reviewed"
	elif not opt in ["lead", "double", "cheap"]:
		why = "option"
	elif opt == "cheap" and int(card.cost) <= 1:
		why = "cost"
	return why


static func _check_pirate(run: Run, o: Dictionary, c: Dictionary) -> String:
	var why := "choice"
	if c.has("copy"):
		why = _check_index(c, "copy", run.deck.size())
		if why == "" and int(o.copies_left) <= 0:
			why = "limit"
		elif why == "" and run.deck[int(c.copy)].get("pirate", false):
			why = "pirate"
	elif c.has("sell"):
		why = _check_index(c, "sell", run.deck.size())
		if why == "" and int(o.sells_left) <= 0:
			why = "limit"
		elif why == "" and run.deck.size() <= DECK_MIN:
			why = "deck_min"
	return why


static func _check_sponsor(run: Run, o: Dictionary, c: Dictionary) -> String:
	var why := _check_index(c, "pick", o.items.size())
	if why != "":
		return why
	var free := free_pocket(run)
	if c.has("slot"):
		var s := int(c.slot)
		# замена — только когда карманы полны
		if free >= 0:
			why = "pockets_free"
		elif s < 0 or s >= run.pockets.size():
			why = "slot"
	elif free < 0:
		why = "pockets"
	return why


static func _check_glitch(run: Run, o: Dictionary, c: Dictionary) -> String:
	var why := _check_index(c, "pick", o.options.size())
	if why != "":
		return why
	var opt: Dictionary = o.options[int(c.pick)]
	if not _glitch_ok(run, opt):
		why = "option"
	elif opt.has("card"):
		why = _check_index(c, "card", run.deck.size())
		if why == "" and not card_fits(run, String(opt.card), run.deck[int(c.card)]):
			why = "card"
	return why


## Доступен ли вариант помехи сейчас (без учёта выбранного вкладыша).
static func _glitch_ok(run: Run, opt: Dictionary) -> bool:
	var ok := true
	match String(opt.id):
		"slap":
			ok = free_pocket(run) >= 0 and not run.unlocks.get("items", []).is_empty()
		"pull":
			ok = run.rewinds > 0 and not _open_of(run, "rare").is_empty()
		"watch":
			ok = not run.deck.is_empty()
	if ok and opt.has("card"):
		ok = run.deck.any(func(card): return card_fits(run, String(opt.card), card))
	return ok


## Подходит ли вкладыш колоды под вариант помехи.
static func card_fits(run: Run, filter: String, card: Dictionary) -> bool:
	var fits := true
	match filter:
		"upgradable":
			var nxt := next_rarity(_rarity(card))
			fits = nxt != "" and not _open_of(run, nxt).is_empty()
		"sturdy":
			fits = int(card.hp) >= 2
	return fits


static func _rarity(card: Dictionary) -> String:
	return String(CardDB.CARDS.get(card.id, {}).get("rarity", "common"))


static func next_rarity(r: String) -> String:
	var i := RARITY_ORDER.find(r)
	return RARITY_ORDER[i + 1] if i >= 0 and i + 1 < RARITY_ORDER.size() else ""


static func _open_of(run: Run, rarity: String) -> Array:
	return run.unlocks.get("cards", []).filter(func(id): return CardDB.CARDS[id].rarity == rarity)


## Первый пустой карман или -1.
static func free_pocket(run: Run) -> int:
	return run.pockets.find(null)


# ================================================================ применение

static func apply(run: Run, o: Dictionary, choice: Dictionary) -> Array:
	var c: Dictionary = LogicUtil.ints(choice)
	var why := check(run, o, c)
	if why != "":
		return [{"t": "deny", "why": why}]
	var ev := []
	if c.get("leave", false) or c.get("skip", false):
		if c.get("skip", false):
			ev.append({"t": "line", "text": LINES.skip})
		_done(o, ev)
		return ev
	match String(o.kind):
		"raffle":
			_add_card(run, o.cards[int(c.pick)].duplicate(true), ev)
			ev.append({"t": "line", "text": LINES.raffle})
			_done(o, ev)
		"shop":
			_buy(run, o, int(c.buy), ev)
		"review":
			_review(run, int(c.card), String(c.option), ev)
			_done(o, ev)
		"pirate":
			_pirate(run, o, c, ev)
		"sponsor":
			_sponsor(run, o, c, ev)
			_done(o, ev)
		"glitch":
			_glitch(run, o, c, ev)
			_done(o, ev)
	return ev


static func _done(o: Dictionary, ev: Array) -> void:
	o.done = true
	ev.append({"t": "done", "kind": o.kind})


static func _add_card(run: Run, card: Dictionary, ev: Array) -> void:
	run.deck.append(card)
	ev.append({"t": "gain_card", "card": card.duplicate(true), "index": run.deck.size() - 1})


static func _fantiki(run: Run, delta: int, why: String, ev: Array) -> void:
	run.fantiki += delta
	ev.append({"t": "fantiki", "value": run.fantiki, "delta": delta, "why": why})


## Выдать предмет: кассета и антенна действуют сразу, остальные — в первый пустой карман (или в slot).
static func give_item(run: Run, id: String, ev: Array, slot := -1) -> void:
	match id:
		"cassette":
			run.rewinds += 1
			ev.append({"t": "rewinds", "value": run.rewinds, "delta": 1})
		"antenna":
			run.signal_bonus += 1
			run.flags.antenna = true
			ev.append({"t": "signal_bonus", "value": run.signal_bonus})
		_:
			var s := slot if slot >= 0 else free_pocket(run)
			if s < 0:
				ev.append({"t": "deny", "why": "pockets"})
				return
			if run.pockets[s] != null:
				ev.append({"t": "lose_item", "item": run.pockets[s], "slot": s})
			run.pockets[s] = id
			ev.append({"t": "gain_item", "item": id, "slot": s})


static func _buy(run: Run, o: Dictionary, i: int, ev: Array) -> void:
	var lot: Dictionary = o.lots[i]
	lot.sold = true
	_fantiki(run, -int(lot.price), "shop", ev)
	ev.append({"t": "buy", "lot": i})
	match String(lot.type):
		"card":
			_add_card(run, lot.card.duplicate(true), ev)
		"item":
			give_item(run, lot.item, ev)
		"bundle":
			lot.hidden = false
			_add_card(run, lot.card.duplicate(true), ev)
			give_item(run, lot.item, ev)
			ev.append({"t": "line", "text": LINES.bundle % CardDB.ITEMS[lot.item].name})
			return
	ev.append({"t": "line", "text": LINES.buy})


static func _review(run: Run, k: int, opt: String, ev: Array) -> void:
	var card: Dictionary = run.deck[k]
	match opt:
		"lead":
			card.atk = int(card.atk) + 1
			card.hp = int(card.hp) + 1
		"double":
			card.hp = int(card.hp) + 3
		"cheap":
			card.cost = maxi(1, int(card.cost) - 1)
	card.reviewed = true
	ev.append({"t": "card_changed", "card": card.duplicate(true), "index": k, "why": opt})
	ev.append({"t": "line", "text": LINES[opt]})


static func _pirate(run: Run, o: Dictionary, c: Dictionary, ev: Array) -> void:
	if c.has("copy"):
		_add_card(run, pirate_copy(run.deck[int(c.copy)]), ev)
		o.copies_left = int(o.copies_left) - 1
		ev.append({"t": "line", "text": LINES.copy})
	else:
		var k := int(c.sell)
		var card: Dictionary = run.deck.pop_at(k)
		ev.append({"t": "lose_card", "card": card, "index": k})
		_fantiki(run, int(o.sell_price), "sell", ev)
		o.sells_left = int(o.sells_left) - 1
		ev.append({"t": "line", "text": LINES.sell})
	# больше делать нечего — ларёк закрывается сам
	if choices(run, o).size() <= 1:
		_done(o, ev)


static func _sponsor(run: Run, o: Dictionary, c: Dictionary, ev: Array) -> void:
	give_item(run, o.items[int(c.pick)], ev, int(c.get("slot", -1)))
	ev.append({"t": "line", "text": LINES.swap_item if c.has("slot") else LINES.sponsor})


static func _glitch(run: Run, o: Dictionary, c: Dictionary, ev: Array) -> void:
	var opt: Dictionary = o.options[int(c.pick)]
	var k := int(c.get("card", -1))
	match String(opt.id):
		"swap":
			var card: Dictionary = run.deck[k]
			_replace(run, k, _swap_target(run, card), ev)
		"loud":
			run.signal_penalty += 1
			ev.append({"t": "signal_penalty", "value": run.signal_penalty})
			var nxt := next_rarity(_rarity(run.deck[k]))
			_replace(run, k, LogicUtil.pick(run.rng, _open_of(run, nxt)), ev)
		"wheel":
			_fantiki(run, 2, "glitch", ev)
		"slap":
			give_item(run, LogicUtil.pick(run.rng, run.unlocks.items), ev)
		"charge":
			var card: Dictionary = run.deck[k]
			card.atk = int(card.atk) + 1
			card.hp = maxi(1, int(card.hp) - 1)
			ev.append({"t": "card_changed", "card": card.duplicate(true), "index": k, "why": "charge"})
		"watch":
			var src: Dictionary = LogicUtil.pick(run.rng, run.deck)
			_add_card(run, CardDB.make(src.id), ev)
		"switch":
			_fantiki(run, 1, "glitch", ev)
		"pull":
			run.rewinds -= 1
			ev.append({"t": "rewinds", "value": run.rewinds, "delta": -1})
			_add_card(run, CardDB.make(LogicUtil.pick(run.rng, _open_of(run, "rare"))), ev)
	if not run.seen_glitches.has(o.scene):
		run.seen_glitches.append(o.scene)
	ev.append({"t": "line", "text": opt.after})


## «Рябь»: случайный открытый вкладыш той же цены (другой id). Таких нет — цена ±1, потом любой другой.
static func _swap_target(run: Run, card: Dictionary) -> String:
	var open: Array = run.unlocks.get("cards", [])
	var cost := int(card.cost)
	for spread in [0, 1, 5]:
		var pool := open.filter(func(id): return id != card.id and absi(int(CardDB.CARDS[id].cost) - cost) <= spread)
		if not pool.is_empty():
			return LogicUtil.pick(run.rng, pool)
	return String(card.id)


static func _replace(run: Run, k: int, id: String, ev: Array) -> void:
	var old: Dictionary = run.deck[k]
	run.deck[k] = CardDB.make(id)
	ev.append({"t": "card_replaced", "old": old, "card": run.deck[k].duplicate(true), "index": k})


# ================================================================ пиратские копии

## Пиратская копия: бледная (pirate = true), −1 здоровье (не ниже 1), имя с опечаткой. Остальное — как у оригинала.
static func pirate_copy(card: Dictionary) -> Dictionary:
	var c: Dictionary = card.duplicate(true)
	c.name = pirate_name(card)
	c.hp = maxi(1, int(c.hp) - 1)
	c.pirate = true
	if PIRATE_SHORT.has(card.id):
		c.short = PIRATE_SHORT[card.id]
	return c


static func pirate_name(card: Dictionary) -> String:
	if PIRATE_NAMES.has(card.id):
		return PIRATE_NAMES[card.id]
	return auto_typo(String(card.name))


## Опечатка для вкладыша без записи в PIRATE_NAMES: о→а, а→о, е→и, и→е (первая найденная), иначе «ъ» в конце.
static func auto_typo(name: String) -> String:
	for pair in [["о", "а"], ["а", "о"], ["е", "и"], ["и", "е"]]:
		var i := name.find(pair[0])
		if i >= 0:
			return name.substr(0, i) + pair[1] + name.substr(i + 1)
	return name + "ъ"
