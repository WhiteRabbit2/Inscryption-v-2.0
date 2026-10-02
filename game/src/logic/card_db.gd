class_name CardDB
extends RefCounted
## Справочник: значки, вкладыши игрока, твари с плёнки, предметы.
## Чистые данные без узлов и картинок. Строки на русском — они же ключи для будущего перевода (tr()).
##
## Карта в колоде — словарь (см. make()): id, name, cost, atk, hp, badges, плюс отметки забега
## (reviewed — уже был Разбор, pirate — пиратская копия). Бой копирует такие словари и раздаёт им uid.

## Значки. side: "both" — бывают у обеих сторон, "tape" — только у тварей. eye — значок глаза (двигает пунктир).
const BADGES := {
	"flying": {"name": "ЛЕТАЕТ", "side": "both",
		"text": "Бьёт поверх карты напротив прямо по шкале, если полоса засчитывается."},
	"tall": {"name": "ВЫСОКИЙ", "side": "both",
		"text": "Перехватывает летающих в своей полосе."},
	"prickly": {"name": "КОЛЮЧИЙ", "side": "both",
		"text": "Кто его ударил, получает 1 урона."},
	"star": {"name": "ЗВЕЗДА", "side": "both",
		"text": "В кадре бьёт на 1 сильнее."},
	"quiet": {"name": "ТИХОНЯ", "side": "both",
		"text": "Его удар в пустую клетку засчитывается и за кадром."},
	"mug": {"name": "КРИВЛЯКА", "side": "you", "eye": true,
		"text": "Если пунктир взгляда ложится на соседнюю полосу, он перескакивает на полосу Кривляки."},
	"stare": {"name": "ГЛЯДЕЛКИ", "side": "you", "eye": true,
		"text": "Пока её полоса в кадре, взгляд с этой полосы не уходит."},
	"cameo": {"name": "КАМЕО", "side": "you",
		"text": "Выходя на экран, приносит 1 вкладыш из колоды."},
	"toon": {"name": "КАК В МУЛЬТИКЕ", "side": "both",
		"text": "В первый раз не погибает, а расплющивается в «блин» 1/1."},
	"replay": {"name": "ПОВТОР", "side": "both",
		"text": "Бьёт дважды за сцену."},
	"static": {"name": "ПОМЕХА", "side": "tape",
		"text": "Погибая, оставляет в клетке «Снег» 0/2."},
	"glitch": {"name": "СБОЙ", "side": "tape",
		"text": "В каждом Монтаже меняется местами с соседней клеткой. Куда — показывает стрелка."},
	"boss": {"name": "ЗВЕЗДА ЭФИРА", "side": "tape",
		"text": "Тапком не прихлопнуть."},
}

## Вкладыши игрока. rarity: common / uncommon / rare. art — id рисунка в Art.ARTS.
const CARDS := {
	"yozh": {"name": "Ёж", "cost": 1, "atk": 1, "hp": 3, "badges": ["prickly"], "rarity": "common", "art": "yozh",
		"flavor": "Из тумана вышел. Обратно не собирается."},
	"belka": {"name": "Белка", "cost": 1, "atk": 1, "hp": 1, "badges": ["cameo"], "rarity": "common", "art": "belka",
		"flavor": "Приносит орехи. И вкладыши."},
	"vorobey": {"name": "Воробей", "cost": 1, "atk": 1, "hp": 1, "badges": ["flying"], "rarity": "common", "art": "vorobey",
		"flavor": "Слово — не воробей. А этот — воробей."},
	"gusenitsa": {"name": "Гусеница", "cost": 1, "atk": 0, "hp": 2, "badges": ["toon"], "rarity": "common",
		"art": "gusenitsa", "flavor": "Станет бабочкой. Не в этой серии."},
	"lisyonok": {"name": "Лисёнок", "cost": 1, "atk": 1, "hp": 2, "badges": ["star"], "rarity": "uncommon",
		"art": "lisyonok", "flavor": "Улыбается в камеру. Камера улыбается в ответ."},
	"gornostay": {"name": "Горностай", "cost": 2, "atk": 2, "hp": 2, "badges": [], "rarity": "common", "art": "gornostay",
		"flavor": "Белый воротничок. Работает за еду и за тебя."},
	"soroka": {"name": "Сорока", "cost": 2, "atk": 1, "hp": 2, "badges": ["mug"], "rarity": "uncommon", "art": "soroka",
		"flavor": "Тащит всё блестящее. Даже его взгляд."},
	"zayats": {"name": "Заяц", "cost": 2, "atk": 2, "hp": 1, "badges": ["star"], "rarity": "common", "art": "zayats",
		"flavor": "Нигде не задерживается. Кроме камеры."},
	"kot": {"name": "Чёрный кот", "short": "Кот", "cost": 2, "atk": 2, "hp": 1, "badges": ["toon"], "rarity": "uncommon",
		"art": "kot", "flavor": "Девятая жизнь? В мультиках их не считают."},
	"kvaksha": {"name": "Квакша", "cost": 2, "atk": 1, "hp": 3, "badges": ["tall"], "rarity": "common", "art": "kvaksha",
		"flavor": "Прыгает выше головы. Своей и чужой."},
	"motylek": {"name": "Мотылёк", "cost": 2, "atk": 0, "hp": 2, "badges": ["stare"], "rarity": "uncommon",
		"art": "motylek", "flavor": "Летит на свет кинескопа и никуда не уходит."},
	"uzh": {"name": "Уж", "cost": 2, "atk": 1, "hp": 2, "badges": ["quiet"], "rarity": "common", "art": "uzh",
		"flavor": "Прополз мимо всех. Даже мимо сюжета."},
	"surok": {"name": "Сурок", "cost": 2, "atk": 0, "hp": 4, "badges": ["tall"], "rarity": "common", "art": "surok",
		"flavor": "Стоит столбиком. Работает стенкой."},
	"volk": {"name": "Волк", "cost": 3, "atk": 3, "hp": 2, "badges": [], "rarity": "common", "art": "volk",
		"flavor": "Классика. Зубы, шерсть, никаких сюрпризов."},
	"krot": {"name": "Крот", "cost": 3, "atk": 2, "hp": 3, "badges": ["quiet"], "rarity": "uncommon", "art": "krot",
		"flavor": "Его никто не видел. Результат видели все."},
	"sova": {"name": "Сова", "cost": 3, "atk": 2, "hp": 2, "badges": ["flying"], "rarity": "common", "art": "sova",
		"flavor": "Не то, чем кажется. Но в этот раз — именно сова."},
	"barsuk": {"name": "Барсук-киномеханик", "short": "Барсук", "cost": 3, "atk": 1, "hp": 4, "badges": ["replay"],
		"rarity": "uncommon", "art": "barsuk", "flavor": "А теперь в замедленном повторе."},
	"lis": {"name": "Лиса", "cost": 3, "atk": 2, "hp": 3, "badges": ["mug"], "rarity": "rare", "art": "lis",
		"flavor": "Знает, куда смотрят. И как сделать, чтобы смотрели сюда."},
	"zhaba": {"name": "Жаба", "cost": 3, "atk": 1, "hp": 5, "badges": ["prickly"], "rarity": "uncommon", "art": "zhaba",
		"flavor": "Бородавки по сценарию."},
	"netopyr": {"name": "Нетопырь", "cost": 3, "atk": 1, "hp": 2, "badges": ["flying", "replay"], "rarity": "rare",
		"art": "netopyr", "flavor": "Висит вниз головой. Смотрит на тебя так же."},
	"los": {"name": "Лось", "cost": 4, "atk": 3, "hp": 5, "badges": ["tall"], "rarity": "uncommon", "art": "los",
		"flavor": "Ходит где хочет. Потому что может."},
	"vepr": {"name": "Вепрь", "cost": 4, "atk": 3, "hp": 4, "badges": ["prickly"], "rarity": "rare", "art": "vepr",
		"flavor": "Щетина как гвозди. Характер тоже."},
	"kabanchik": {"name": "Кабанчик", "cost": 4, "atk": 4, "hp": 3, "badges": [], "rarity": "uncommon", "art": "kabanchik",
		"flavor": "Прёт прямо. Монтажёр не успевает."},
	"filin": {"name": "Филин", "cost": 5, "atk": 3, "hp": 4, "badges": ["flying", "stare"], "rarity": "rare",
		"art": "filin", "flavor": "Он моргнёт первым. Филин — нет."},
	"shatun": {"name": "Шатун", "cost": 5, "atk": 4, "hp": 6, "badges": [], "rarity": "rare", "art": "shatun",
		"flavor": "Не спит ночами. Как и ты."},
}

## Твари с плёнки. tier — для подбора по уровню серии. Токены (Снег, блин) не выпадают сами.
const CREATURES := {
	"pen": {"name": "Декорация-пень", "short": "Пень", "atk": 0, "hp": 4, "badges": [], "tier": 1, "art": "pen",
		"flavor": "Нарисован на фанере. Фанера крепче, чем кажется."},
	"bity": {"name": "Битый кадр", "atk": 2, "hp": 1, "badges": ["static"], "tier": 1, "art": "krysa",
		"flavor": "Мелькнул на долю секунды. Остался навсегда."},
	"klyaksa": {"name": "Летучая клякса", "short": "Клякса", "atk": 1, "hp": 2, "badges": ["flying"], "tier": 1,
		"art": "netopyr", "flavor": "Тушь капнула с кисточки и улетела."},
	"skleyka": {"name": "Склейка", "atk": 2, "hp": 3, "badges": [], "tier": 2, "art": "gadyuka",
		"flavor": "Два куска плёнки, и оба не отсюда."},
	"perevolk": {"name": "Перерисованный волк", "short": "Перевол", "atk": 3, "hp": 2, "badges": ["glitch"], "tier": 2,
		"art": "volk", "flavor": "В этой серии его рисовал другой художник. Плохой."},
	"negayozh": {"name": "Ёж-негатив", "short": "Негатив", "atk": 1, "hp": 4, "badges": ["prickly"], "tier": 2,
		"art": "yozh", "flavor": "Белые иголки, чёрный нос. Всё наоборот."},
	"dvoynik": {"name": "Двойник", "atk": 2, "hp": 2, "badges": ["star"], "tier": 2, "art": "zayats",
		"flavor": "Тот же заяц, только смотрит не туда."},
	"zatyorly": {"name": "Затёртый лось", "short": "Затёртый", "atk": 3, "hp": 5, "badges": ["tall"], "tier": 3,
		"art": "los", "flavor": "Кассету смотрели так часто, что от лося остался контур."},
	"ryaboy": {"name": "Рябой шатун", "short": "Рябой", "atk": 4, "hp": 4, "badges": [], "tier": 3, "art": "shatun",
		"flavor": "Пошёл рябью ещё в девяносто первом."},
	# токены
	"sneg": {"name": "Снег", "atk": 0, "hp": 2, "badges": [], "tier": 0, "art": "",
		"flavor": "Шшшшш."},
	# босс «Конец эфира»
	"ulybaka": {"name": "Улыбака", "atk": 2, "hp": 8, "badges": ["boss"], "tier": 9, "art": "ulybaka",
		"flavor": "Талисман «Кривой опушки». Улыбка шире головы, и это не фигура речи."},
	"podtanc": {"name": "Подтанцовка", "atk": 1, "hp": 1, "badges": [], "tier": 9, "art": "kukushonok",
		"flavor": "Пляшет на заднем плане. Иногда на переднем."},
	"aplod": {"name": "Аплодисменты", "short": "Хлоп", "atk": 1, "hp": 2, "badges": ["flying"], "tier": 9,
		"art": "motylek", "flavor": "Записаны в 1991 году. Хлопают до сих пор."},
}

## Предметы. battle — можно применить в бою; target: "" / "tape" / "you" / "gaze".
const ITEMS := {
	"remote": {"name": "Пульт", "battle": true, "target": "",
		"text": "В ближайший Монтаж взгляды не сдвигаются."},
	"slipper": {"name": "Тапок", "battle": true, "target": "tape",
		"text": "Прихлопнуть тварь со здоровьем не больше 3."},
	"tape": {"name": "Синяя изолента", "short": "Изолента", "battle": true, "target": "you",
		"text": "Своему зверю +2 здоровья."},
	"knock": {"name": "Стукнуть по телевизору", "short": "Стукнуть", "battle": true, "target": "gaze",
		"text": "Сдвинуть один пунктир на соседнюю полосу."},
	"gum": {"name": "Жвачка «Опушка»", "short": "Жвачка", "battle": true, "target": "",
		"text": "2 вкладыша в руку."},
	"batteries": {"name": "Батарейки на изоленте", "short": "Батарейки", "battle": true, "target": "",
		"text": "+2 искры в этот ход."},
	"cassette": {"name": "Чистая кассета", "short": "Кассета", "battle": false, "target": "",
		"text": "+1 перемотка на эту ночь."},
	"antenna": {"name": "Комнатная антенна", "short": "Антенна", "battle": false, "target": "",
		"text": "+1 Сигнал до конца ночи. Действует сама."},
}

const STARTER_DECK := ["yozh", "yozh", "belka", "vorobey", "gornostay", "gornostay", "zayats", "volk"]
const STARTER_ITEMS := ["tape"]
## Предметы, которые встречаются в наградах и у спонсора (кассета и антенна — только в Телемагазине).
const COMMON_ITEMS := ["remote", "slipper", "tape", "knock", "gum", "batteries"]


## Новая карта колоды по id вкладыша.
static func make(id: String) -> Dictionary:
	var c: Dictionary = CARDS[id]
	return {
		"id": id, "name": c.name, "cost": c.cost, "atk": c.atk, "hp": c.hp,
		"badges": (c.badges as Array).duplicate(), "reviewed": false, "pirate": false,
	}


## Новая тварь по id. hp_bonus — для теории «Все звери тут — один волк» и «Ночного показа».
static func make_creature(id: String, hp_bonus := 0, atk_bonus := 0) -> Dictionary:
	var c: Dictionary = CREATURES[id]
	var atk: int = c.atk + (atk_bonus if c.atk > 0 else 0)
	return {
		"id": id, "name": c.name, "cost": 0, "atk": atk, "hp": c.hp + hp_bonus,
		"badges": (c.badges as Array).duplicate(), "reviewed": false, "pirate": false,
	}


static func starter_deck() -> Array:
	var out := []
	for id in STARTER_DECK:
		out.append(make(id))
	return out


static func has_eye(card: Dictionary) -> bool:
	for b in card.get("badges", []):
		if BADGES.get(b, {}).get("eye", false):
			return true
	return false


static func cards_of(rarity: String) -> Array:
	var out := []
	for id in CARDS:
		if CARDS[id].rarity == rarity:
			out.append(id)
	return out


## Короткое имя для подписи на поле.
static func short_name(card: Dictionary) -> String:
	if card.has("short"):
		return card.short
	var src: Dictionary = CARDS.get(card.id, CREATURES.get(card.id, {}))
	if card.get("pirate", false):
		return card.name
	return src.get("short", card.name)
