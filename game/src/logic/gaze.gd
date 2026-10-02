class_name Gaze
extends RefCounted
## Взгляд Многоглазого — словарь:
##   lane    — полоса, куда он смотрит сейчас (её удары в пустоту засчитываются на этом PLAY);
##   plan    — пунктир: куда он ляжет на следующем PLAY (после значков глаза);
##   base    — пунктир по привычке или после Пульта/Стукнуть, до значков глаза;
##   base_by — кто сдвинул base ("" — привычка, "knock", "wink", "remote");
##   by      — кто сдвинул итоговый пунктир (base_by или "card:<uid>") — для стрелки на экране;
##   habit   — привычка, dir/hold/hold_n/jump — её состояние.
##
## Привычки:
##   pan     «Панорама»: каждый ход на 1 полосу, у края разворот;
##   closeup «Крупный план»: стоит hold_n хода (2), потом прыгает на jump полосы (2), от края отражается;
##   sleepy  «Оператор уснул»: как Крупный план, но стоит 3 хода;
##   hero    «На героя»: полоса с самой большой атакой на поле (обе стороны и наброски), при равенстве левая;
##   glued   «Приклеен»: смотрит на босса (uid в target), пока тот жив, иначе как Панорама;
##   fixed   стоит на месте (взгляды «Присматривается»).

const HABITS := {
	"pan": {"name": "Панорама", "text": "Каждый ход сдвигается на 1 полосу, у края разворачивается."},
	"closeup": {"name": "Крупный план", "text": "Стоит 2 хода, потом прыгает на 2 полосы."},
	"sleepy": {"name": "Оператор уснул", "text": "Стоит 3 хода, потом прыгает на 2 полосы."},
	"hero": {"name": "На героя", "text": "Смотрит туда, где самая большая атака на поле."},
	"glued": {"name": "Приклеен", "text": "Не сводит глаз со звезды эфира."},
	"fixed": {"name": "Присматривается", "text": "Стоит на месте до конца серии."},
}


static func make(spec: Dictionary) -> Dictionary:
	var habit: String = spec.get("habit", "pan")
	var g := {
		"lane": int(spec.get("lane", 0)), "plan": int(spec.get("lane", 0)), "base": int(spec.get("lane", 0)),
		"base_by": "", "by": "", "habit": habit, "dir": int(spec.get("dir", 1)), "hold": 0,
		"hold_n": int(spec.get("hold_n", 3 if habit == "sleepy" else 2)), "jump": int(spec.get("jump", 2)),
		"target": spec.get("target", ""),
	}
	return g


static func can_shift(g: Dictionary, d: int) -> bool:
	var p: int = g.plan + d
	return d != 0 and p >= 0 and p < Battle.LANES


## Пунктир по привычке (вызывается в Монтаже, после того как взгляд переехал).
## taken — полосы, уже выбранные другими взглядами «На героя» (второй берёт вторую по силе).
static func plan_base(g: Dictionary, b: Battle, taken: Array = []) -> void:
	g.base_by = ""
	match g.habit:
		"pan":
			g.base = _step(g, 1)
		"closeup", "sleepy":
			if g.hold < g.hold_n - 1:
				g.hold += 1
				g.base = g.lane
			else:
				g.hold = 0
				g.base = _step(g, g.jump)
		"hero":
			g.base = _hero_lane(b, taken)
			taken.append(g.base)
		"glued":
			var lane := _find_uid(b, g.target)
			g.base = lane if lane >= 0 else _step(g, 1)
		_:
			g.base = g.lane


## Шаг на n полос в сторону dir; если выходит за край — разворот.
static func _step(g: Dictionary, n: int) -> int:
	var to: int = g.lane + g.dir * n
	if to < 0 or to >= Battle.LANES:
		g.dir = -g.dir
		to = g.lane + g.dir * n
	return clampi(to, 0, Battle.LANES - 1)


static func _hero_lane(b: Battle, taken: Array) -> int:
	var best := 0
	var best_v := -1
	for l in Battle.LANES:
		if taken.has(l):
			continue
		var v := 0
		if b.you[l] != null:
			v = maxi(v, int(b.you[l].atk))
		if b.tape[l] != null:
			v = maxi(v, int(b.tape[l].atk))
		elif b.sketches[l] != null:
			v = maxi(v, int(CardDB.CREATURES[b.sketches[l].id].atk) + int(b.cfg.tape_atk))
		if v > best_v:
			best_v = v
			best = l
	return best


static func _find_uid(b: Battle, target) -> int:
	# target — id твари (например "ulybaka"): смотрим на первую такую на плёнке
	for l in Battle.LANES:
		if b.tape[l] != null and b.tape[l].id == str(target):
			return l
	return -1
