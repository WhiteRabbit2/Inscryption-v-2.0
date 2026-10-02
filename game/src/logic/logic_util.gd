class_name LogicUtil
extends RefCounted
## Мелкие помощники логики.


## После JSON все числа становятся дробными. Возвращает копию, где целые дроби снова int.
static func ints(v):
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) and absf(v) < 9.0e15 else v
		TYPE_ARRAY:
			var out := []
			for x in v:
				out.append(ints(x))
			return out
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = ints(v[k])
			return out
	return v


## Случайный элемент массива через свой генератор (чтобы перемотка повторяла выбор).
static func pick(rng: RandomNumberGenerator, a: Array):
	if a.is_empty():
		return null
	return a[rng.randi_range(0, a.size() - 1)]


## Перемешать на месте своим генератором.
static func shuffle(rng: RandomNumberGenerator, a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## Состояние генератора — строками, чтобы JSON не терял точность 64-битных чисел.
static func rng_to_dict(rng: RandomNumberGenerator) -> Dictionary:
	return {"seed": str(rng.seed), "state": str(rng.state)}


static func rng_from_dict(rng: RandomNumberGenerator, d: Dictionary) -> void:
	rng.seed = int(str(d.seed))
	rng.state = int(str(d.state))
