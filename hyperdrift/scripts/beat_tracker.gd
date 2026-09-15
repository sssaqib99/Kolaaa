extends RefCounted
## Live beat tracker for music streamed from the player's device.
##
## Pipeline (all real-time, no pre-analysis needed):
##   per-band spectral flux  ->  onset strength signal at 60 Hz
##   -> autocorrelation over an 8 s window with a mild tempo prior  -> BPM
##   -> comb-filter phase alignment -> time of the last beat
##
## Pure logic with zero engine dependencies so it can be unit-tested headless.

const FS := 60.0            # analysis rate (Hz)
const WIN := 480            # 8 s ring buffer
const MIN_LAG := 20         # 180 BPM
const MAX_LAG := 60         # 60 BPM
const BAND_W := [1.4, 2.0, 1.2, 0.8, 1.0, 0.6]

var bpm := 120.0
var period := 0.5
var confidence := 0.0
var locked := false
var last_beat := 0.0        # tracker-time of the most recent beat estimate
var t := 0.0                # tracker time (seconds fed so far)
var has_estimate := false
## Seconds subtracted from every phase estimate: sample-push delay plus the
## FFT window latency of the spectrum analyzer feeding us.
var latency_comp := 0.025

var _buf := PackedFloat32Array()
var _head := 0
var _filled := 0
var _acc := 0.0
var _pending := 0.0
var _prev_db := PackedFloat32Array()
var _since := 0.0
var _hist: Array[float] = []


func _init() -> void:
	_buf.resize(WIN)
	_buf.fill(0.0)


func reset() -> void:
	_buf.fill(0.0)
	_head = 0
	_filled = 0
	_acc = 0.0
	_pending = 0.0
	_prev_db = PackedFloat32Array()
	_since = 0.0
	_hist.clear()
	confidence = 0.0
	locked = false
	has_estimate = false


## bands_db: current level of each analysis band in dB. dt: real seconds elapsed.
func feed_db(bands_db: PackedFloat32Array, dt: float) -> void:
	var flux := 0.0
	if _prev_db.size() == bands_db.size():
		for i in bands_db.size():
			var d: float = bands_db[i] - _prev_db[i]
			if d > 0.0:
				var w: float = BAND_W[i] if i < BAND_W.size() else 1.0
				flux += d * w
	_prev_db = bands_db.duplicate()
	feed_flux(flux, dt)


## Raw onset strength input (used directly by the unit test).
func feed_flux(flux: float, dt: float) -> void:
	t += dt
	_pending = maxf(_pending, flux)
	_acc += dt
	var step := 1.0 / FS
	while _acc >= step:
		_acc -= step
		_buf[_head] = _pending
		_pending = 0.0
		_head = (_head + 1) % WIN
		_filled = mini(_filled + 1, WIN)
	_since += dt
	if _since >= 0.5 and _filled >= int(FS * 3.0):
		_since = 0.0
		_analyze()


func next_beat(now: float) -> float:
	if not has_estimate:
		return now
	var n: float = ceilf((now - last_beat) / period)
	return last_beat + n * period


func phase(now: float) -> float:
	if not has_estimate:
		return 0.0
	return fposmod(now - last_beat, period) / period


# ------------------------------------------------------------------ analysis

func _analyze() -> void:
	var W := _filled
	var n := PackedFloat32Array()
	n.resize(W)
	var start := (_head - W + WIN) % WIN
	var mean := 0.0
	for i in W:
		n[i] = _buf[(start + i) % WIN]
		mean += n[i]
	mean /= float(W)
	var energy := 0.0
	for i in W:
		n[i] = maxf(0.0, n[i] - mean)
		energy += n[i] * n[i]
	if energy < 1e-6:
		confidence = maxf(0.0, confidence - 0.2)
		locked = false
		return

	# Autocorrelation for lags 10..120 samples (covers sub-divisions and doubles).
	var top_lag: int = mini(2 * MAX_LAG, W / 2)
	var r := PackedFloat32Array()
	r.resize(top_lag + 2)
	for L in range(MIN_LAG / 2, top_lag + 1):
		var s := 0.0
		for i in range(L, W):
			s += n[i] * n[i - L]
		r[L] = s / float(W - L)

	var sc := PackedFloat32Array()
	sc.resize(MAX_LAG + 2)
	var best_L := -1
	var best := -1.0
	var sum := 0.0
	var cnt := 0
	for L in range(MIN_LAG, MAX_LAG + 1):
		var s: float = r[L]
		if 2 * L <= top_lag:
			s += 0.5 * r[2 * L]
		var half: int = L / 2
		if half >= MIN_LAG / 2:
			if L % 2 == 0:
				s += 0.3 * r[half]
			else:
				s += 0.15 * (r[half] + r[half + 1])
		var bpm_l := 60.0 * FS / float(L)
		var prior: float = exp(-pow((bpm_l - 122.0) / 42.0, 2.0))
		s *= 0.4 + 0.6 * prior
		sc[L] = s
		sum += s
		cnt += 1
		if s > best:
			best = s
			best_L = L
	if best_L < 0 or best <= 0.0:
		return
	var mean_s := sum / float(cnt)

	# Parabolic peak refinement for sub-sample period precision.
	var lf := float(best_L)
	if best_L > MIN_LAG and best_L < MAX_LAG:
		var a: float = sc[best_L - 1]
		var b: float = sc[best_L]
		var c: float = sc[best_L + 1]
		var den := a - 2.0 * b + c
		if absf(den) > 1e-6:
			lf += clampf(0.5 * (a - c) / den, -0.5, 0.5)
	var bpm_new := 60.0 * FS / lf

	_hist.append(bpm_new)
	if _hist.size() > 5:
		_hist.pop_front()
	var sorted := _hist.duplicate()
	sorted.sort()
	var med: float = sorted[sorted.size() / 2]
	var stable := false
	if _hist.size() < 3:
		bpm = med
	else:
		stable = absf(bpm_new - med) / med < 0.04
		bpm = lerpf(bpm, bpm_new, 0.5) if stable else med
	period = 60.0 / bpm

	var prom := (best - mean_s) / maxf(best, 1e-6)
	var conf_raw := clampf((prom - 0.1) / 0.4, 0.0, 1.0) * (1.0 if stable else 0.5)
	confidence = lerpf(confidence, conf_raw, 0.4)
	locked = confidence > 0.35 and _filled >= int(FS * 4.0)
	_estimate_phase(n, W)


func _estimate_phase(n: PackedFloat32Array, W: int) -> void:
	var p := period * FS
	var best_o := 0.0
	var best_sc := -1.0
	var o := 0.0
	while o < p:
		var s := 0.0
		var wsum := 0.0
		var k := 0
		while k < 24:
			var idx := W - 1 - int(round(o + float(k) * p))
			if idx < 0:
				break
			var w := pow(0.85, float(k))
			var v: float = n[idx]
			if idx > 0:
				v = maxf(v, n[idx - 1] * 0.8)
			if idx < W - 1:
				v = maxf(v, n[idx + 1] * 0.8)
			s += v * w
			wsum += w
			k += 1
		s /= maxf(wsum, 1e-6)
		if s > best_sc:
			best_sc = s
			best_o = o
		o += 0.5
	var t_newest := t - _acc
	var new_last := t_newest - best_o / FS - latency_comp
	if has_estimate:
		var steps: float = roundf((new_last - last_beat) / period)
		var predicted: float = last_beat + steps * period
		var diff: float = new_last - predicted
		if absf(diff) < 0.3 * period:
			last_beat = predicted + 0.5 * diff
		else:
			last_beat = new_last
	else:
		last_beat = new_last
	has_estimate = true
