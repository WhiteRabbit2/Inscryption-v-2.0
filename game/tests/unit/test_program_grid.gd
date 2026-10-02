extends TestCase
## Газета «Программа передач»: форма, расписание по строкам, ходы между каналами, теории.

const SEEDS := 150


func _ids(row: Array) -> Array:
	return row.map(func(c): return c.episode_id)


func test_shape_for_many_seeds() -> void:
	for s in SEEDS:
		var g := ProgramGrid.generate(s + 1, s % 3 == 0)
		check_eq(g.rows.size(), 9, "9 получасов")
		check_eq(g.channels.size(), 3, "3 канала")
		for r in g.rows.size():
			var row: Array = g.rows[r]
			check_eq(row.size(), 3, "в строке 3 клетки")
			for ch in row.size():
				var c: Dictionary = row[ch]
				check_eq(c.time, ProgramGrid.TIMES[r], "время строки")
				check(c.row == r and c.channel == ch, "координаты клетки")
				check(String(c.title) != "" and String(c.sub) != "", "у клетки есть строка газеты")
				check(String(c.icon) != "", "у клетки есть значок")
		if not failures.is_empty():
			return


func test_times_from_2300_to_0300() -> void:
	check_eq(ProgramGrid.TIMES[0], "23:00", "")
	check_eq(ProgramGrid.TIMES[8], "03:00", "")


func test_schedule_rules() -> void:
	for s in SEEDS:
		var first := s % 4 == 0
		var g := ProgramGrid.generate(1000 + s, first)
		var rows: Array = g.rows
		# 23:00 — пилот (в первую ночь обучение)
		for c in rows[0]:
			check(c.kind == "episode" and c.level == 0, "23:00 — серия-пилот")
			check_eq(bool(c.episode.get("tutorial", false)), first, "обучение только в первую ночь")
			check(not c.night and c.theory == "", "у пилота нет ночного показа и теорий")
		# 23:30 — везде Розыгрыш
		for c in rows[1]:
			check(c.kind == "segment" and c.segment == "raffle", "23:30 — Розыгрыш на всех каналах")
		# серии 00:00 / 01:00 / 02:00
		for r in [2, 4, 6]:
			var nights := 0
			for c in rows[r]:
				check(c.kind == "episode", "в %s — серия" % ProgramGrid.TIMES[r])
				check_eq(c.level, r / 2, "уровень серии")
				if c.night:
					nights += 1
					check(c.episode.get("night", false) and int(c.episode.film) == 7, "Ночной показ: Плёнка 7")
					check_eq(c.title, ProgramGrid.TEXT.night, "строка Ночного показа")
			if r == 2:
				check_eq(nights, 1, "в 00:00 ровно один Ночной показ")
			elif r == 4:
				check(nights <= 1, "в 01:00 Ночной показ может быть")
			else:
				check_eq(nights, 0, "в 02:00 Ночного показа нет")
		# рубрики 00:30 / 01:30 / 02:30 — без повторов в строке
		for r in [3, 5, 7]:
			var kinds: Array = rows[r].map(func(c): return c.segment)
			for c in rows[r]:
				check(c.kind == "segment" and Segments.KINDS.has(c.segment), "рубрика")
			check(kinds[0] != kinds[1] and kinds[1] != kinds[2] and kinds[0] != kinds[2], "рубрики в строке разные")
			if r == 5:
				check_eq(kinds.count("shop"), 1, "в 01:30 на одном канале Телемагазин")
			if r == 7:
				check(kinds.has("review"), "в 02:30 есть Разбор")
		# 03:00 — Конец эфира
		for c in rows[8]:
			check(c.kind == "boss" and c.episode_id == Episodes.BOSS.id, "03:00 — босс")
		if not failures.is_empty():
			return


func test_theories_placement() -> void:
	var rows_with := 0
	var rows_total := 0
	var seen := {}
	for s in SEEDS:
		var g := ProgramGrid.generate(2000 + s, false)
		for r in g.rows.size():
			var n := 0
			for c in g.rows[r]:
				if c.theory == "":
					continue
				n += 1
				seen[c.theory] = true
				check(r in [2, 4, 6], "теории только с 00:00 и только на сериях")
				check(not c.night, "на Ночном показе теорий нет")
				check(Theories.THEORIES.has(c.theory), "известная теория")
				if c.theory == "censors":
					var bl := int(c.theory_cfg.get("blocked_lane", -1))
					check(bl >= 0 and bl < Battle.LANES, "цензоры: полоса показана заранее")
			check(n <= 1, "не больше одной теории в строке")
			if r in [2, 4, 6]:
				rows_total += 1
				rows_with += n
	check(rows_with > 0 and rows_with < rows_total, "теории на некоторых сериях, не на всех (%d из %d)" % [rows_with, rows_total])
	check_eq(seen.size(), Theories.THEORIES.size(), "все теории встречаются")


func test_theory_filter() -> void:
	for s in 40:
		var none := ProgramGrid.generate(s, false, [])
		var only := ProgramGrid.generate(s, false, ["sleepy"])
		for r in 9:
			for ch in 3:
				check_eq(none.rows[r][ch].theory, "", "без открытых теорий меток нет")
				check(only.rows[r][ch].theory in ["", "sleepy"], "только открытые теории")


func test_episodes_distinct_within_rows() -> void:
	for s in SEEDS:
		var g := ProgramGrid.generate(3000 + s, false)
		for r in [2, 4, 6]:
			var ids := _ids(g.rows[r])
			check(ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2], "серии в строке %d не повторяются: %s" % [r, ids])
		var pilots := _ids(g.rows[0])
		check(pilots.count(pilots[0]) < 3, "пилоты по возможности разные")
		# Ночной показ 00:00 берёт серию 2-го уровня: в 01:00 она может повториться, только если иначе никак
		var night_id := ""
		for c in g.rows[2]:
			if c.night:
				night_id = c.episode_id
		var at_one := _ids(g.rows[4])
		if g.rows[4].any(func(c): return c.night):
			check(not at_one.has(night_id), "есть из чего выбрать — без повторов за ночь")


func test_deterministic_by_seed() -> void:
	var a := JSON.stringify(ProgramGrid.generate(77, false))
	var b := JSON.stringify(ProgramGrid.generate(77, false))
	var c := JSON.stringify(ProgramGrid.generate(78, false))
	check_eq(a, b, "тот же сид — та же газета")
	check(a != c, "другой сид — другая газета")


func test_movement_rules() -> void:
	check_eq(ProgramGrid.moves(-1, -1), [0, 1, 2], "в первой строке — любой канал")
	check_eq(ProgramGrid.moves(0, 0), [0, 1], "с края — свой или соседний")
	check_eq(ProgramGrid.moves(3, 1), [0, 1, 2], "из середины — все три")
	check_eq(ProgramGrid.moves(5, 2), [1, 2], "")
	check_eq(ProgramGrid.moves(8, 1), [], "после Конца эфира ходить некуда")


func test_episode_numbers_unique() -> void:
	var nums := {}
	for lv in Episodes.POOLS:
		for e in Episodes.POOLS[lv]:
			var n := ProgramGrid.episode_number(e.id)
			check(n >= 1 and n <= 12, "номер серии 1–12: %s → %d" % [e.id, n])
			check(not nums.has(n), "номера не повторяются")
			nums[n] = true
	check_eq(ProgramGrid.episode_number(Episodes.BOSS.id), 13, "Конец эфира — 13-я серия")
	var g := ProgramGrid.generate(5, false)
	var c: Dictionary = g.rows[2][0]
	if not c.night:
		check(String(c.title).contains(str(ProgramGrid.episode_number(c.episode_id))), "в строке газеты номер серии")


func test_grid_survives_json() -> void:
	var g := ProgramGrid.generate(11, true)
	var back: Dictionary = LogicUtil.ints(JSON.parse_string(JSON.stringify(g)))
	check_eq(JSON.stringify(back), JSON.stringify(g), "газета переживает JSON")
	check_eq(typeof(back.rows[2][0].level), TYPE_INT, "числа снова целые")
