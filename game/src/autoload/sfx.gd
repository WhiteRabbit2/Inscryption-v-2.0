extends Node
## Звук без звуковых файлов: всё синтезируется кодом при первом проигрывании.
## Sfx.play("bell"), Sfx.voice() — бормотание ведущего, Sfx.start_drone() — низкий гул.

const RATE := 22050

var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _drone: AudioStreamPlayer
var _drone_task := -1
var _drone_stream: AudioStreamWAV
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1312
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_players.append(p)
	_drone = AudioStreamPlayer.new()
	_drone.bus = "Music"
	_drone.volume_db = -6.0
	add_child(_drone)


func play(sound: String, volume := 1.0, pitch := 1.0) -> void:
	if Settings.test_speed > 8.0:
		return
	var stream: AudioStreamWAV = _cache.get(sound)
	if stream == null:
		var buf := _build(sound)
		if buf.is_empty():
			return
		stream = _to_wav(buf)
		_cache[sound] = stream
	var p := _free_player()
	p.stream = stream
	p.volume_db = linear_to_db(maxf(volume, 0.001))
	p.pitch_scale = pitch
	p.play()


## Одно «слово» ведущего: короткий низкий формантный звук.
func voice() -> void:
	play("voice%d" % _rng.randi_range(0, 5), 0.8, _rng.randf_range(0.92, 1.08))


func start_drone() -> void:
	if _drone.playing or _drone_task != -1 or DisplayServer.get_name() == "headless":
		return
	_drone_task = WorkerThreadPool.add_task(_build_drone)


func set_tense(v: bool) -> void:
	if _drone:
		create_tween().tween_property(_drone, "pitch_scale", 1.12 if v else 1.0, 2.0)


func _process(_delta: float) -> void:
	if _drone_task != -1 and WorkerThreadPool.is_task_completed(_drone_task):
		WorkerThreadPool.wait_for_task_completion(_drone_task)
		_drone_task = -1
		if _drone_stream:
			_drone.stream = _drone_stream
			_drone.play()


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return _players[0]


# ---------------------------------------------------------------- синтез

func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


func _env(t: float, attack: float, decay: float, peak: float) -> float:
	if t < attack:
		return peak * t / attack
	return peak * exp(-5.5 * (t - attack) / decay)


## Генератор тона: sine / square / saw / triangle, со скольжением частоты f0 → f1.
func _osc(b: PackedFloat32Array, kind: String, f0: float, t0: float, dur: float, peak: float, f1 := 0.0) -> void:
	var start := int(t0 * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		var idx := start + i
		if idx >= b.size():
			break
		var t := float(i) / RATE
		var f := f0 if f1 <= 0.0 else f0 * pow(f1 / f0, t / dur)
		phase = fmod(phase + f / RATE, 1.0)
		var v := 0.0
		match kind:
			"sine": v = sin(phase * TAU)
			"square": v = 1.0 if phase < 0.5 else -1.0
			"saw": v = phase * 2.0 - 1.0
			"triangle": v = 1.0 - 4.0 * absf(phase - 0.5)
		b[idx] += v * _env(t, 0.005, dur, peak)


## Шум через фильтр (lowpass / highpass / bandpass), частота фильтра может ползти fq0 → fq1.
func _noise(b: PackedFloat32Array, t0: float, dur: float, peak: float, mode: String, fq0: float, q := 1.0, fq1 := 0.0) -> void:
	var start := int(t0 * RATE)
	var n := int(dur * RATE)
	var low := 0.0
	var band := 0.0
	var damp := 1.0 / maxf(q, 0.5)
	for i in n:
		var idx := start + i
		if idx >= b.size():
			break
		var t := float(i) / RATE
		var fq := fq0 if fq1 <= 0.0 else fq0 * pow(fq1 / fq0, t / dur)
		var fcoef := 2.0 * sin(PI * minf(fq, RATE * 0.22) / RATE)
		var x := _rng.randf() * 2.0 - 1.0
		low += fcoef * band
		var high := x - low - damp * band
		band += fcoef * high
		var v := low
		if mode == "highpass":
			v = high
		elif mode == "bandpass":
			v = band
		b[idx] += v * _env(t, 0.004, dur, peak)


func _build(sound: String) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	match sound:
		"bell":
			b = _buf(1.8)
			for pair in [[1.0, 0.35], [2.76, 0.16], [5.4, 0.08], [8.93, 0.04]]:
				_osc(b, "sine", 880.0 * pair[0], 0.0, 1.6 / sqrt(pair[0]), pair[1])
			_noise(b, 0.0, 0.03, 0.2, "highpass", 4000.0)
		"place":
			b = _buf(0.15)
			_noise(b, 0.0, 0.05, 0.35, "highpass", 1800.0)
			_osc(b, "sine", 120.0, 0.0, 0.08, 0.3, 60.0)
		"draw":
			b = _buf(0.2)
			_noise(b, 0.0, 0.16, 0.25, "bandpass", 900.0, 0.8, 2500.0)
		"slide":
			b = _buf(0.25)
			_noise(b, 0.0, 0.2, 0.18, "bandpass", 500.0, 0.7, 300.0)
		"hit":
			b = _buf(0.22)
			_noise(b, 0.0, 0.08, 0.6, "lowpass", 2200.0)
			_osc(b, "sine", 140.0, 0.0, 0.16, 0.5, 45.0)
		"creak":
			b = _buf(0.3)
			_osc(b, "saw", 70.0, 0.0, 0.25, 0.12, 55.0)
			_noise(b, 0.0, 0.2, 0.08, "bandpass", 1400.0, 6.0)
		"whoosh":
			b = _buf(0.16)
			_noise(b, 0.0, 0.12, 0.22, "bandpass", 600.0, 1.0, 2400.0)
		"die":
			b = _buf(0.3)
			for i in 3:
				_noise(b, i * 0.04, 0.05, 0.4, "bandpass", 900.0 + i * 500.0, 2.0)
			_osc(b, "square", 90.0, 0.0, 0.2, 0.08, 40.0)
		"squelch":
			b = _buf(0.4)
			_noise(b, 0.0, 0.35, 0.35, "bandpass", 1200.0, 3.0, 200.0)
			_osc(b, "sine", 70.0, 0.0, 0.3, 0.3, 35.0)
		"bone":
			b = _buf(0.12)
			_osc(b, "triangle", 1000.0, 0.0, 0.05, 0.12)
			_osc(b, "triangle", 1300.0, 0.04, 0.04, 0.08)
		"snuff":
			b = _buf(0.7)
			_noise(b, 0.0, 0.6, 0.25, "highpass", 2500.0, 0.7, 6000.0)
		"cuckoo":
			b = _buf(0.65)
			_osc(b, "sine", 690.0, 0.0, 0.22, 0.3)
			_osc(b, "sine", 550.0, 0.28, 0.3, 0.3)
		"tick":
			b = _buf(0.04)
			_noise(b, 0.0, 0.02, 0.25, "highpass", 3000.0)
		"grow":
			b = _buf(0.35)
			_osc(b, "triangle", 300.0, 0.0, 0.3, 0.15, 700.0)
		"item":
			b = _buf(0.3)
			_noise(b, 0.0, 0.25, 0.25, "bandpass", 700.0, 2.0, 2000.0)
			_osc(b, "triangle", 200.0, 0.0, 0.2, 0.1, 400.0)
		"prick":
			b = _buf(0.1)
			_osc(b, "sine", 2200.0, 0.0, 0.08, 0.2)
			_noise(b, 0.0, 0.05, 0.2, "highpass", 5000.0)
		"paper":
			b = _buf(0.4)
			for i in 5:
				_noise(b, i * 0.06, 0.07, 0.12, "highpass", 2500.0 + _rng.randf() * 2000.0)
		"step":
			b = _buf(0.08)
			_noise(b, 0.0, 0.04, 0.25, "bandpass", 600.0, 3.0)
			_osc(b, "sine", 180.0, 0.0, 0.05, 0.15, 90.0)
		"win":
			b = _buf(1.8)
			for i in 4:
				_osc(b, "triangle", [196.0, 247.0, 294.0, 392.0][i], i * 0.12, 1.2, 0.12)
		"lose":
			b = _buf(1.6)
			for i in 4:
				_osc(b, "saw", [220.0, 185.0, 147.0, 110.0][i], i * 0.18, 0.9, 0.07)
		"deny":
			b = _buf(0.3)
			_osc(b, "square", 110.0, 0.0, 0.12, 0.08)
			_osc(b, "square", 98.0, 0.1, 0.15, 0.08)
		"coin":
			b = _buf(0.2)
			_osc(b, "triangle", 1400.0, 0.0, 0.08, 0.12)
			_osc(b, "triangle", 1900.0, 0.06, 0.1, 0.1)
		"static":
			# помехи: белый шум с треском
			b = _buf(0.45)
			_noise(b, 0.0, 0.4, 0.22, "highpass", 1500.0)
			for i in 6:
				_noise(b, _rng.randf() * 0.35, 0.02, 0.35, "bandpass", 3000.0 + _rng.randf() * 3000.0, 2.0)
		"vcr_play":
			# кнопка видика: щелчок, глухой удар механизма, короткий моторчик
			b = _buf(0.5)
			_noise(b, 0.0, 0.02, 0.4, "highpass", 3500.0)
			_osc(b, "sine", 95.0, 0.01, 0.12, 0.45, 50.0)
			_osc(b, "saw", 58.0, 0.08, 0.35, 0.06, 64.0)
			_noise(b, 0.1, 0.3, 0.05, "bandpass", 400.0, 2.0)
		"vcr_rewind":
			# перемотка: моторчик разгоняется, плёнка шуршит
			b = _buf(1.0)
			_osc(b, "square", 160.0, 0.0, 0.9, 0.05, 520.0)
			_noise(b, 0.0, 0.95, 0.14, "bandpass", 800.0, 1.5, 3200.0)
			_noise(b, 0.9, 0.05, 0.3, "highpass", 3000.0)
		"crt_on":
			b = _buf(0.7)
			_osc(b, "sine", 60.0, 0.0, 0.2, 0.5, 30.0)
			_osc(b, "sine", 7800.0, 0.05, 0.6, 0.03)
			_noise(b, 0.0, 0.15, 0.2, "highpass", 2000.0)
		"eye":
			b = _buf(0.14)
			_osc(b, "sine", 620.0, 0.0, 0.12, 0.12, 930.0)
		"pencil":
			b = _buf(0.35)
			for i in 4:
				_noise(b, i * 0.07, 0.06, 0.1, "bandpass", 2800.0 + _rng.randf() * 1500.0, 3.0)
		_:
			if sound.begins_with("voice"):
				b = _voice_buf(int(sound.substr(5)))
	return b


func _voice_buf(seed_value: int) -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = 77 + seed_value
	var b := _buf(0.14)
	var f0 := 70.0 + r.randf() * 40.0
	var formant := 350.0 + r.randf() * 700.0
	var tone := _buf(0.14)
	_osc(tone, "saw", f0, 0.0, 0.11, 0.5, f0 * 0.85)
	# грубый формантный фильтр поверх тона
	var low := 0.0
	var band := 0.0
	var fcoef := 2.0 * sin(PI * formant / RATE)
	for i in tone.size():
		low += fcoef * band
		var high := tone[i] - low - 0.25 * band
		band += fcoef * high
		b[i] = band * 0.6
	return b


func _build_drone() -> void:
	var secs := 8.0
	var b := _buf(secs)
	var low := 0.0
	var band := 0.0
	var wl := 0.0
	var wb := 0.0
	var phases := [0.0, 0.0, 0.0]
	var freqs := [41.25, 41.875, 61.75] # целое число периодов за 8 секунд — петля без щелчка
	var r := RandomNumberGenerator.new()
	r.seed = 9
	for i in b.size():
		var t := float(i) / RATE
		var x := 0.0
		for k in 3:
			phases[k] = fmod(phases[k] + freqs[k] / RATE, 1.0)
			x += phases[k] * 2.0 - 1.0
		var cutoff := 140.0 + 50.0 * sin(TAU * t / secs)
		var fc := 2.0 * sin(PI * cutoff / RATE)
		low += fc * band
		var high := x - low - 0.33 * band
		band += fc * high
		# ветер
		var w := r.randf() * 2.0 - 1.0
		var wf := 2.0 * sin(PI * 320.0 / RATE)
		wl += wf * wb
		var wh := w - wl - 1.6 * wb
		wb += wf * wh
		b[i] = low * 0.11 + wb * 0.05
	# мягкая склейка конца с началом
	var fade := int(0.25 * RATE)
	for i in fade:
		var k := float(i) / fade
		b[b.size() - fade + i] = b[b.size() - fade + i] * (1.0 - k) + b[i] * k
	_drone_stream = _to_wav(b, true)


func _to_wav(buf: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w
