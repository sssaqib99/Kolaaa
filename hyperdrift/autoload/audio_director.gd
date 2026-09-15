extends Node
## Sound — 100% procedural audio, jukebox and the game's BEAT CLOCK.
##
## * Every note and sound effect is synthesised into AudioStreamWAV at boot.
## * Four theme songs (one per map) are composed from scratch in code.
## * Device music (.ogg / .mp3 / .wav) can replace the themes at any time.
## * The beat clock exposes a monotonic beat index + timing used by the level
##   generator and by beat-animated hazards:
##     - synth themes: exact, derived from the known BPM + playback position
##     - device music: live tracked via a spectrum analyzer on the Music bus

const RATE := 22050
const Biomes := preload("res://scripts/biomes.gd")
const BeatTracker := preload("res://scripts/beat_tracker.gd")

## Six detailed bands used for live beat tracking and visual music direction.
## Keeping all bands inside the 20-16k audible range makes the analyzer useful
## for synth bass, acoustic jazz, drones, vocals and user-provided tracks.
const BANDS := [[20.0, 55.0], [55.0, 160.0], [160.0, 500.0], [500.0, 2200.0], [2200.0, 8000.0], [8000.0, 16000.0]]

var _sfx: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _music: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var muted := false
var ready_to_play := false

var _music_target_db := -10.0
var _music_base_db := -9.0
var _engine_target_db := -60.0
var _engine_target_pitch := 1.0

var _music_bus := 0
var _sfx_bus := 0
var _spectrum: AudioEffectSpectrumAnalyzerInstance = null

# ---- jukebox -------------------------------------------------------------
var music_mode := 0 # 0 = built-in synth themes, 1 = music files from the device
var device_paths: PackedStringArray = PackedStringArray()
var device_names: PackedStringArray = PackedStringArray()
var device_index := 0
var device_playing := false
var shuffle := false
var _theme_cache: Dictionary = {}
var _synth_biome := -1
var _order: Array[int] = []
var _order_pos := 0

signal device_library_changed
signal track_changed(track_name: String)
signal source_changed(mode: int)

# ---- beat clock ----------------------------------------------------------
var beat_period := 0.5
var beat_locked := false
var beat_bpm := 120.0
var beat_conf := 0.0
var beat_source := "NONE" # SYNTH / DEVICE / NONE
var _ref_time := 0.0
var _ref_index := 0.0
var _last_emitted := -1
var _tracker = BeatTracker.new()
var _bands_db := PackedFloat32Array()

signal beat(index: int)

# ---- music structure analysis ------------------------------------------
## Everything below is derived live from the spectrum analyzer on the Music bus,
## so it works for the synth themes AND for the player's own files.
var energy := 0.0          # fast loudness, 0..1  (tau ~0.15 s)
var energy_slow := 0.0     # slow loudness, 0..1  (tau ~5 s)
var energy_peak := 0.05    # adaptive normaliser
var bass := 0.0            # 20-130 Hz band, 0..1
var mids := 0.0            # 130-1000 Hz
var highs := 0.0           # 1-12 kHz (hats / air)
## Detailed layer values. These are intentionally separate from the historic
## bass/mids/highs fields above so existing gameplay stays compatible.
var sub_bass := 0.0        # 20-55 Hz: rumble / deep kick body
var bass_wave := 0.0       # 55-160 Hz: synth bass / walking bass / bass drum
var low_mids := 0.0        # 160-500 Hz: drones, pads, guitars, warm body
var presence := 0.0        # 500-2200 Hz: melody, vocals, horn/piano attacks
var air := 0.0             # 2.2-8 kHz: snare, hats, brightness
var shimmer := 0.0         # 8-16 kHz: cymbal air / sparkle
var drone := 0.0           # stable low-mid bed with no sharp transient
var melody := 0.0          # presence-led melodic layer
var percussion := 0.0      # air/shimmer-led rhythmic layer
var transient := 0.0       # short onset / attack strength
var bass_pulse := 0.0      # beat-shaped bass envelope for animation
var visual_energy := 0.0   # aggregate 0..1 for visual systems
var dominant_layer := "DRONE" # BASS / DRONE / MELODY / PERCUSSION / SILENT
var spike := 0.0           # how far fast energy sits above the slow average, 0..1
var intensity := 0.0       # smoothed musical intensity used by speed + gobos, 0..1
var breakdown := false     # quiet section (energy well below the slow average)
var ambient := false       # long quiet section -> ship floats in the sky
var drop_active := false
var drop_time_left := 0.0
var tempo_ratio := 1.0     # current BPM / BPM at track start (slowing music < 1)
var _ref_bpm := 0.0
var _last_drop := -100.0
var _quiet_t := 0.0
var _bar_index := -1
var _spike_fired := false   # rising-edge latch for the spike() signal
var _sub_peak := 0.01
var _bass_peak := 0.01
var _low_mid_peak := 0.01
var _presence_peak := 0.01
var _air_peak := 0.01
var _shimmer_peak := 0.01
var _prev_band_sum := 0.0
var _transient_latch := false
var _dominant_candidate := "DRONE"
var _dominant_hold := 0.0

signal drop(strength: float)
signal breakdown_started
signal breakdown_ended
signal ambient_started
signal ambient_ended
signal bar(index: int)
signal spike_started(intensity: float)   # fired when energy spikes above the slow average
signal transient_detected(strength: float)
signal dominant_layer_changed(layer: String)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 20260117
	_setup_buses()
	for i in 16:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	_music.volume_db = -60.0
	_music.bus = "Music"
	_music.finished.connect(_on_music_finished)
	add_child(_music)
	_engine = AudioStreamPlayer.new()
	_engine.process_mode = Node.PROCESS_MODE_ALWAYS
	_engine.volume_db = -60.0
	_engine.bus = "SFX"
	add_child(_engine)
	_ref_time = now()
	_tracker.latency_comp = 0.025 + 0.04 # push delay + FFT window
	apply_volumes()
	# Let the first frame render before we burn CPU on synthesis.
	call_deferred("_build_bank")


func _setup_buses() -> void:
	_music_bus = _ensure_bus("Music")
	_sfx_bus = _ensure_bus("SFX")
	var fx := AudioEffectSpectrumAnalyzer.new()
	fx.buffer_length = 0.15
	fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	AudioServer.add_bus_effect(_music_bus, fx)
	var inst := AudioServer.get_bus_effect_instance(_music_bus, AudioServer.get_bus_effect_count(_music_bus) - 1)
	_spectrum = inst as AudioEffectSpectrumAnalyzerInstance


func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx


func _process(delta: float) -> void:
	var ud: float = delta / maxf(Engine.time_scale, 0.0001)
	var k := clampf(ud * 6.0, 0.0, 1.0)
	if is_instance_valid(_music):
		_music.volume_db = lerpf(_music.volume_db, -60.0 if muted else _music_target_db, k)
	if is_instance_valid(_engine):
		var eng_db: float = _engine_target_db + linear_to_db(clampf(Persist.engine_volume, 0.001, 1.0))
		_engine.volume_db = lerpf(_engine.volume_db, -60.0 if muted else eng_db, k)
		_engine.pitch_scale = lerpf(_engine.pitch_scale, _engine_target_pitch, clampf(ud * 5.0, 0.0, 1.0))
	_update_beat_clock(ud)


# ---------------------------------------------------------------- public API

func play(sfx_name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if muted or not _sfx.has(sfx_name):
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _sfx[sfx_name]
	p.pitch_scale = clampf(pitch, 0.2, 3.0)
	p.volume_db = volume_db
	p.play()


func start_music() -> void:
	if _music.stream and not _music.playing:
		_music.play()


func set_music_db(db: float) -> void:
	_music_base_db = db
	_music_target_db = db


func refresh_music_volume() -> void:
	apply_volumes()


## Pushes the user's volume settings to the audio buses.
func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(clampf(Persist.music_volume, 0.001, 1.0)))
	AudioServer.set_bus_mute(_music_bus, Persist.music_volume <= 0.001)
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(clampf(Persist.sfx_volume, 0.001, 1.0)))
	AudioServer.set_bus_mute(_sfx_bus, Persist.sfx_volume <= 0.001)


func set_engine(speed01: float, boost: float, alive: bool, ambient: bool = false) -> void:
	if ambient:
		_engine_target_pitch = 0.45 + speed01 * 0.35
		_engine_target_db = (-28.0 + speed01 * 3.0)
	else:
		_engine_target_pitch = 0.55 + speed01 * 0.95 + boost * 0.35
		_engine_target_db = (-16.0 + speed01 * 9.0 + boost * 5.0) if alive else -60.0


func toggle_mute() -> bool:
	muted = not muted
	return muted


# ------------------------------------------------------------------ beat clock

func now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


## Continuous beat count (monotonic float).
func beat_pos() -> float:
	return _ref_index + (now() - _ref_time) / beat_period


func time_of_beat(k: float) -> float:
	return _ref_time + (k - _ref_index) * beat_period


func next_beat_index() -> int:
	return int(ceilf(beat_pos()))


## Signed seconds between a moment and its nearest beat (+ = after the beat).
func beat_offset(at_time: float) -> float:
	var b := (at_time - _ref_time) / beat_period
	return (b - roundf(b)) * beat_period


## 0..1 progress through a cycle of `beats` beats, optionally phase shifted.
func beat_cycle(beats: float, phase_beats: float = 0.0) -> float:
	return fposmod(beat_pos() + phase_beats, beats) / beats


func _theme_period(id: int) -> float:
	return float(int(roundf(60.0 / Biomes.bpm_of(id) * RATE))) / float(RATE)


func _sync_ref(last_beat_wall: float, period: float) -> void:
	var k := _ref_index + (last_beat_wall - _ref_time) / beat_period
	_ref_index = roundf(k)
	_ref_time = last_beat_wall
	beat_period = period


func _update_beat_clock(ud: float) -> void:
	var n := now()
	if music_mode == 0 and _music.playing and _synth_biome >= 0 and _music.stream != null:
		var period := _theme_period(_synth_biome)
		var pos: float = _music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		var phase := fposmod(pos, period) / period
		_sync_ref(n - phase * period, period)
		beat_locked = true
		beat_source = "SYNTH"
		beat_conf = 1.0
		beat_bpm = 60.0 / period
	elif music_mode == 1 and device_playing and _music.playing and not _music.stream_paused:
		_feed_tracker(ud)
		beat_source = "DEVICE"
		beat_conf = _tracker.confidence
		beat_bpm = _tracker.bpm
		if _tracker.locked and _tracker.has_estimate:
			beat_locked = true
			var wall_last: float = n - (_tracker.t - _tracker.last_beat)
			_sync_ref(wall_last, _tracker.period)
		else:
			beat_locked = false
	else:
		beat_locked = false
		beat_source = "NONE"
		beat_conf = 0.0
	var idx := int(floorf(beat_pos()))
	if idx > _last_emitted:
		_last_emitted = idx
		beat.emit(idx)
		var b := int(floorf(float(idx) / 4.0))
		if b != _bar_index:
			_bar_index = b
			bar.emit(b)
	_analyze_structure(ud)


## Detailed structure analysis: six spectrum bands become musical layers that
## can drive gameplay, ships, flares, atmospheric grade and concert lighting.
func _analyze_structure(ud: float) -> void:
	var playing: bool = _music.playing and not _music.stream_paused and _music.stream != null
	if _spectrum == null or not playing:
		_reset_live_analysis(ud)
		return

	# Raw spectrum extraction. The six ranges deliberately separate bass-wave
	# motion from low drone body, melody presence and bright percussion/air.
	var sub_raw: float = _band_lin(20.0, 55.0)
	var bass_raw: float = _band_lin(55.0, 160.0)
	var low_raw: float = _band_lin(160.0, 500.0)
	var presence_raw: float = _band_lin(500.0, 2200.0)
	var air_raw: float = _band_lin(2200.0, 8000.0)
	var shimmer_raw: float = _band_lin(8000.0, 16000.0)
	var raw: float = sub_raw * 1.15 + bass_raw * 1.55 + low_raw * 0.95 + presence_raw * 1.1 + air_raw * 1.25 + shimmer_raw * 0.75

	# Adaptive peak followers normalize any track without a fixed threshold.
	var peak_decay: float = clampf(1.0 - ud * 0.075, 0.90, 1.0)
	_sub_peak = maxf(_sub_peak * peak_decay, sub_raw, 0.00001)
	_bass_peak = maxf(_bass_peak * peak_decay, bass_raw, 0.00001)
	_low_mid_peak = maxf(_low_mid_peak * peak_decay, low_raw, 0.00001)
	_presence_peak = maxf(_presence_peak * peak_decay, presence_raw, 0.00001)
	_air_peak = maxf(_air_peak * peak_decay, air_raw, 0.00001)
	_shimmer_peak = maxf(_shimmer_peak * peak_decay, shimmer_raw, 0.00001)
	energy_peak = maxf(energy_peak * (1.0 - ud * 0.04), raw, 0.00001)

	var fast: float = clampf(ud * 10.0, 0.0, 1.0)
	var musical: float = clampf(ud * 4.0, 0.0, 1.0)
	sub_bass = lerpf(sub_bass, clampf(sub_raw / (_sub_peak * 0.76), 0.0, 1.0), fast)
	bass_wave = lerpf(bass_wave, clampf(bass_raw / (_bass_peak * 0.70), 0.0, 1.0), fast)
	low_mids = lerpf(low_mids, clampf(low_raw / (_low_mid_peak * 0.72), 0.0, 1.0), musical)
	presence = lerpf(presence, clampf(presence_raw / (_presence_peak * 0.72), 0.0, 1.0), musical)
	air = lerpf(air, clampf(air_raw / (_air_peak * 0.68), 0.0, 1.0), fast)
	shimmer = lerpf(shimmer, clampf(shimmer_raw / (_shimmer_peak * 0.62), 0.0, 1.0), fast)

	# Legacy three-band fields remain for older level code.
	var b_target: float = clampf(sub_bass * 0.45 + bass_wave * 0.85, 0.0, 1.0)
	var m_target: float = clampf(low_mids * 0.52 + presence * 0.74, 0.0, 1.0)
	var h_target: float = clampf(air * 0.78 + shimmer * 0.42, 0.0, 1.0)
	bass = lerpf(bass, b_target, fast)
	mids = lerpf(mids, m_target, musical)
	highs = lerpf(highs, h_target, fast)
	var n: float = clampf(raw / (energy_peak * 0.58), 0.0, 1.0)
	energy = lerpf(energy, n, fast)
	energy_slow = lerpf(energy_slow, energy, clampf(ud * 0.2, 0.0, 1.0))
	intensity = lerpf(intensity, clampf(energy * 0.48 + bass * 0.32 + presence * 0.20, 0.0, 1.0), clampf(ud * 1.4, 0.0, 1.0))

	# Spectral flux catches crisp snare/hihat attacks before the slower energy
	# follower reacts. This powers the short flash / flare accents.
	var band_sum: float = sub_bass * 0.8 + bass_wave * 1.0 + low_mids * 0.65 + presence * 1.0 + air * 1.15 + shimmer * 0.9
	var flux: float = maxf(0.0, band_sum - _prev_band_sum)
	_prev_band_sum = band_sum
	transient = lerpf(transient, clampf(flux * 2.6, 0.0, 1.0), fast)
	var transient_now: bool = transient > 0.46 and air + shimmer > 0.25
	if transient_now and not _transient_latch:
		_transient_latch = true
		transient_detected.emit(transient)
	elif not transient_now and transient < 0.18:
		_transient_latch = false

	# Bass pulse combines the actual bass waveform with a beat envelope, giving
	# synth bass and kick-heavy tracks an animation that remains legible between
	# detected beats.
	var beat_phase: float = fposmod(beat_pos(), 1.0)
	var beat_env: float = exp(-beat_phase * 7.5)
	bass_pulse = lerpf(bass_pulse, clampf(bass_wave * 0.76 + sub_bass * 0.36 + beat_env * (0.22 + bass_wave * 0.50), 0.0, 1.0), fast)
	drone = lerpf(drone, clampf(low_mids * 0.72 + energy_slow * 0.38 - transient * 0.28, 0.0, 1.0), musical)
	melody = lerpf(melody, clampf(presence * 0.88 + low_mids * 0.18 - sub_bass * 0.12, 0.0, 1.0), musical)
	percussion = lerpf(percussion, clampf(air * 0.82 + shimmer * 0.60 + transient * 0.42, 0.0, 1.0), fast)
	visual_energy = lerpf(visual_energy, clampf(bass_pulse * 0.38 + drone * 0.22 + melody * 0.28 + percussion * 0.42, 0.0, 1.0), fast)
	_update_dominant_layer(ud)

	spike = clampf((energy - energy_slow) / maxf(energy_slow, 0.15) - 0.15, 0.0, 1.0)
	var spike_now := spike > 0.35
	if spike_now and not _spike_fired:
		_spike_fired = true
		spike_started.emit(spike)
	elif not spike_now and spike < 0.18:
		_spike_fired = false

	# Tempo ratio (slowing music -> < 1).
	if beat_locked:
		if _ref_bpm <= 0.0:
			_ref_bpm = beat_bpm
		tempo_ratio = lerpf(tempo_ratio, clampf(beat_bpm / maxf(_ref_bpm, 1.0), 0.6, 1.4), clampf(ud * 0.8, 0.0, 1.0))

	# Breakdown: quiet for a while.
	if energy < energy_slow * 0.55 and energy_slow > 0.12:
		_quiet_t += ud
	else:
		_quiet_t = maxf(0.0, _quiet_t - ud * 2.0)
	var was := breakdown
	breakdown = _quiet_t > 2.2
	if breakdown and not was:
		breakdown_started.emit()
	elif was and not breakdown:
		breakdown_ended.emit()
	var was_a := ambient
	ambient = energy_slow < 0.10 and energy < 0.16 and _quiet_t > 7.0 and not drop_active
	if ambient and not was_a:
		ambient_started.emit()
	elif was_a and not ambient:
		ambient_ended.emit()

	# Drop: sudden jump well above the slow average after >= 8 s since the last.
	var t := now()
	if drop_active:
		drop_time_left -= ud
		if drop_time_left <= 0.0 or energy < energy_slow * 0.9:
			drop_active = false
	elif t - _last_drop > 8.0 and energy_slow > 0.08 and energy > energy_slow * 1.45 and energy > 0.42 and bass > 0.5:
		_last_drop = t
		drop_active = true
		drop_time_left = clampf(4.0 + energy * 6.0, 4.0, 9.0)
		drop.emit(clampf((energy - energy_slow) / maxf(energy_slow, 0.1), 0.3, 1.0))


func _reset_live_analysis(ud: float) -> void:
	var k: float = clampf(ud * 2.5, 0.0, 1.0)
	for field_name in ["energy", "intensity", "bass", "mids", "highs", "sub_bass", "bass_wave", "low_mids", "presence", "air", "shimmer", "drone", "melody", "percussion", "transient", "bass_pulse", "visual_energy"]:
		set(field_name, lerpf(float(get(field_name)), 0.0, k))
	spike = 0.0
	drop_active = false
	if dominant_layer != "SILENT":
		dominant_layer = "SILENT"
		dominant_layer_changed.emit(dominant_layer)
	if breakdown:
		breakdown = false
		breakdown_ended.emit()


func _update_dominant_layer(ud: float) -> void:
	var scores := {
		"BASS": bass_pulse * 1.25 + sub_bass * 0.44,
		"DRONE": drone * (1.20 if transient < 0.20 else 0.78),
		"MELODY": melody * 1.18 + presence * 0.20,
		"PERCUSSION": percussion * 1.20 + transient * 0.72,
	}
	var best := "DRONE"
	var best_score := -1.0
	for layer in scores:
		var score: float = scores[layer]
		if score > best_score:
			best_score = score
			best = layer
	if energy < 0.035:
		best = "SILENT"
	# Hold a candidate for 0.25 s so a high-hat doesn't make every visual
	# strobe change palette each frame.
	if best != _dominant_candidate:
		_dominant_candidate = best
		_dominant_hold = 0.0
	else:
		_dominant_hold += ud
	if _dominant_candidate != dominant_layer and _dominant_hold > 0.25:
		dominant_layer = _dominant_candidate
		dominant_layer_changed.emit(dominant_layer)


func _band_lin(lo: float, hi: float) -> float:
	var m: Vector2 = _spectrum.get_magnitude_for_frequency_range(lo, hi, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE)
	return (m.x + m.y) * 0.5


func reset_track_analysis() -> void:
	_ref_bpm = 0.0
	tempo_ratio = 1.0
	energy_peak = 0.05
	_sub_peak = 0.01
	_bass_peak = 0.01
	_low_mid_peak = 0.01
	_presence_peak = 0.01
	_air_peak = 0.01
	_shimmer_peak = 0.01
	_prev_band_sum = 0.0
	transient = 0.0
	bass_pulse = 0.0
	drone = 0.0
	melody = 0.0
	percussion = 0.0
	visual_energy = 0.0
	dominant_layer = "DRONE"
	_dominant_candidate = "DRONE"
	_dominant_hold = 0.0
	drop_active = false
	_last_drop = now() - 4.0
	_quiet_t = 0.0
	_spike_fired = false
	_transient_latch = false


func _feed_tracker(ud: float) -> void:
	if _spectrum == null:
		return
	if _bands_db.size() != BANDS.size():
		_bands_db.resize(BANDS.size())
	for i in BANDS.size():
		var lo: float = BANDS[i][0]
		var hi: float = BANDS[i][1]
		var m: Vector2 = _spectrum.get_magnitude_for_frequency_range(lo, hi, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
		var mag := maxf(m.x, m.y)
		_bands_db[i] = maxf(-60.0, linear_to_db(mag + 0.000001))
	_tracker.feed_db(_bands_db, ud)


# ---------------------------------------------------------------- synthesis

func _build_bank() -> void:
	_sfx["jump"] = _wav(_gen_chirp(420.0, 980.0, 0.20), false)
	_sfx["land"] = _wav(_gen_thud(), false)
	_sfx["graze"] = _wav(_gen_graze(), false)
	_sfx["hit"] = _wav(_gen_hit(), false)
	_sfx["shield"] = _wav(_gen_chime([784.0, 1046.5, 1318.5], 0.7), false)
	_sfx["power"] = _wav(_gen_arp_up(), false)
	_sfx["boost"] = _wav(_gen_whoosh(), false)
	_sfx["death"] = _wav(_gen_death(), false)
	_sfx["ui"] = _wav(_gen_chirp(900.0, 1500.0, 0.06), false)
	_sfx["record"] = _wav(_gen_fanfare(), false)
	_sfx["combo"] = _wav(_gen_chime([1174.7, 1568.0], 0.28), false)
	_sfx["levelup"] = _wav(_gen_fanfare(), false)
	# ---- Drum kit: crisp, punchy percussion for the frequent gameplay hits.
	# These replace the arcade chimes on orbs / XP / combo / beat ticks so the
	# feedback sits IN the music instead of on top of it.
	_sfx["kick"] = _wav(_gen_kick(), false)          # deep tight kick
	_sfx["snare"] = _wav(_gen_snare(), false)        # snappy snare with body
	_sfx["hat"] = _wav(_gen_hat(false), false)       # closed hat: 'tk'
	_sfx["hat_open"] = _wav(_gen_hat(true), false)   # open hat: 'tss'
	_sfx["rim"] = _wav(_gen_rim(), false)            # rimshot click
	_sfx["clap"] = _wav(_gen_clap(), false)          # layered clap
	_sfx["smash"] = _wav(_gen_smash(), false)        # adrenaline obstacle break
	_sfx["adren_on"] = _wav(_gen_adren_on(), false)  # adrenaline activation swell
	# Route the frequent events to drums.
	_sfx["orb"] = _sfx["hat"]
	_sfx["xp"] = _sfx["rim"]
	_sfx["combo"] = _sfx["snare"]
	_sfx["tick"] = _sfx["hat"]
	_engine.stream = _wav(_gen_engine(), true)
	_engine.play()
	music_mode = Persist.music_mode
	shuffle = Persist.shuffle
	rebuild_library()
	play_biome_music(Persist.biome)
	if music_mode == 1:
		if device_paths.size() > 0:
			play_device(Persist.device_index)
		else:
			music_mode = 0
	start_music()
	ready_to_play = true


func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := clampf(samples[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


static func _saw(f: float, t: float) -> float:
	return fposmod(f * t, 1.0) * 2.0 - 1.0


static func _sqr(f: float, t: float) -> float:
	return 1.0 if fposmod(f * t, 1.0) < 0.5 else -1.0


static func _sine(f: float, t: float) -> float:
	return sin(TAU * f * t)


func _gen_orb() -> PackedFloat32Array:
	var n := int(RATE * 0.17)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * 22.0)
		var f := 880.0 + 1500.0 * t
		out[i] = (_sine(f, t) * 0.7 + _sine(f * 2.0, t) * 0.25) * env * 0.55
	return out


func _gen_chirp(f0: float, f1: float, dur: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var f: float = lerpf(f0, f1, k * k)
		var env: float = sin(PI * clampf(k, 0.0, 1.0)) * exp(-k * 1.4)
		out[i] = (_sine(f, t) * 0.6 + _sqr(f * 0.5, t) * 0.18) * env * 0.5
	return out


func _gen_thud() -> PackedFloat32Array:
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * 20.0)
		out[i] = (_sine(lerpf(160.0, 55.0, clampf(t * 8.0, 0.0, 1.0)), t) * 0.8 + _rng.randf_range(-1.0, 1.0) * 0.18 * exp(-t * 60.0)) * env * 0.6
	return out


func _gen_graze() -> PackedFloat32Array:
	var n := int(RATE * 0.13)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * 30.0)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.55
		out[i] = (lp * 0.5 + _sine(2400.0 - t * 3000.0, t) * 0.45) * env * 0.45
	return out


func _gen_hit() -> PackedFloat32Array:
	var n := int(RATE * 0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * 7.0)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.25
		var body: float = _sine(lerpf(210.0, 42.0, clampf(t * 4.0, 0.0, 1.0)), t)
		var s := body * 0.7 + lp * 0.6
		out[i] = clampf(s * 1.6, -1.0, 1.0) * env * 0.8
	return out


func _gen_chime(freqs: Array, dur: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for j in freqs.size():
			var f: float = freqs[j]
			var d: float = t - float(j) * 0.05
			if d > 0.0:
				s += _sine(f, d) * exp(-d * 7.0) * 0.35
		out[i] = s * 0.7
	return out


func _gen_arp_up() -> PackedFloat32Array:
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	var step := 0.075
	var n := int(RATE * (step * notes.size() + 0.35))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for j in notes.size():
			var d: float = t - float(j) * step
			if d > 0.0:
				var f: float = notes[j]
				s += (_sqr(f, d) * 0.35 + _sine(f * 2.0, d) * 0.3) * exp(-d * 6.0)
		out[i] = clampf(s, -1.0, 1.0) * 0.4
	return out


func _gen_whoosh() -> PackedFloat32Array:
	var n := int(RATE * 0.75)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var bp := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / 0.75
		var env: float = sin(PI * k)
		var cutoff: float = lerpf(0.02, 0.6, k)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * cutoff
		bp += (lp - bp) * 0.06
		out[i] = ((lp - bp) * 1.4 + _sine(lerpf(90.0, 420.0, k), t) * 0.25) * env * 0.6
	return out


func _gen_death() -> PackedFloat32Array:
	var n := int(RATE * 1.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / 1.5
		var env: float = exp(-t * 2.2)
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.12
		var f: float = lerpf(320.0, 44.0, k * k)
		out[i] = clampf((_saw(f, t) * 0.5 + _sine(f * 0.5, t) * 0.5 + lp * 0.5) * 1.3, -1.0, 1.0) * env * 0.7
	return out


func _gen_fanfare() -> PackedFloat32Array:
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5, 1046.5, 1318.5]
	var step := 0.12
	var n := int(RATE * (step * notes.size() + 0.7))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for j in notes.size():
			var d: float = t - float(j) * step
			if d > 0.0:
				var f: float = notes[j]
				s += (_sqr(f, d) * 0.22 + _saw(f * 1.005, d) * 0.2 + _sine(f * 2.0, d) * 0.18) * exp(-d * 4.0)
		out[i] = clampf(s, -1.0, 1.0) * 0.45
	return out


# ------------------------------------------------------------------ drum kit
## Every drum is a one-shot synthesised at boot: a pitched sine body with a
## fast exponential pitch drop for the kick / snare "thump", filtered noise for
## the snap and air, and a very short click transient so each hit is crisp.

func _gen_kick() -> PackedFloat32Array:
	var n := int(RATE * 0.32)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		# Pitch sweeps 165 Hz -> 46 Hz in ~50 ms: the classic tight kick.
		var f: float = 46.0 + 119.0 * exp(-t * 42.0)
		ph += TAU * f / RATE
		var body: float = sin(ph) * exp(-t * 9.5)
		# Click transient for attack definition.
		var click: float = _rng.randf_range(-1.0, 1.0) * exp(-t * 260.0) * 0.55
		out[i] = clampf((body * 1.15 + click) * 0.95, -1.0, 1.0)
	return out


func _gen_snare() -> PackedFloat32Array:
	var n := int(RATE * 0.26)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var hp_prev := 0.0
	var hp_out := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		# Two-tone body (fundamental + overtone) with a quick pitch drop.
		var f: float = 178.0 + 90.0 * exp(-t * 60.0)
		ph += TAU * f / RATE
		var body: float = (sin(ph) * 0.6 + sin(ph * 1.62) * 0.35) * exp(-t * 22.0)
		# Bright snappy noise: high-passed to keep it crisp, not boomy.
		var white: float = _rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.62
		hp_out = 0.86 * (hp_out + lp - hp_prev)
		hp_prev = lp
		var snap: float = hp_out * exp(-t * 26.0)
		out[i] = clampf((body * 0.75 + snap * 0.95) * 0.9, -1.0, 1.0)
	return out


func _gen_hat(open: bool) -> PackedFloat32Array:
	var dur := 0.30 if open else 0.07
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp_prev := 0.0
	var hp_out := 0.0
	var decay := 14.0 if open else 78.0
	for i in n:
		var t := float(i) / RATE
		# Metallic hat: a stack of detuned square-ish partials + high-passed noise.
		var m: float = 0.0
		for k in [1.0, 1.42, 1.83, 2.37, 2.91, 3.55]:
			m += (1.0 if fposmod(t * 4180.0 * k, 1.0) < 0.5 else -1.0)
		m /= 6.0
		var white: float = _rng.randf_range(-1.0, 1.0)
		var mix: float = m * 0.45 + white * 0.65
		hp_out = 0.92 * (hp_out + mix - hp_prev)
		hp_prev = mix
		out[i] = clampf(hp_out * exp(-t * decay) * 0.6, -1.0, 1.0)
	return out


func _gen_rim() -> PackedFloat32Array:
	var n := int(RATE * 0.06)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		# Very short woody click: 1.1 kHz + 2.8 kHz with a razor decay.
		ph += TAU * 1120.0 / RATE
		var tone: float = (sin(ph) * 0.7 + sin(ph * 2.55) * 0.5) * exp(-t * 95.0)
		var tick: float = _rng.randf_range(-1.0, 1.0) * exp(-t * 420.0) * 0.5
		out[i] = clampf((tone + tick) * 0.85, -1.0, 1.0)
	return out


func _gen_clap() -> PackedFloat32Array:
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var hp_prev := 0.0
	var hp_out := 0.0
	for i in n:
		var t := float(i) / RATE
		var white: float = _rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.5
		hp_out = 0.88 * (hp_out + lp - hp_prev)
		hp_prev = lp
		# Three fast flams then a tail: the layered "hand clap" shape.
		var env: float = 0.0
		for d in [0.0, 0.011, 0.023]:
			var tt: float = t - d
			if tt >= 0.0:
				env += exp(-tt * 140.0)
		env += exp(-t * 18.0) * 0.55
		out[i] = clampf(hp_out * env * 0.42, -1.0, 1.0)
	return out


## Obstacle smash during adrenaline: a kick thump + glassy shatter + air burst.
func _gen_smash() -> PackedFloat32Array:
	var n := int(RATE * 0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f: float = 60.0 + 200.0 * exp(-t * 30.0)
		ph += TAU * f / RATE
		var thump: float = sin(ph) * exp(-t * 11.0)
		var white: float = _rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.35
		# Glassy shards: a cluster of high sines decaying at different rates.
		var glass: float = 0.0
		for k in [2140.0, 2890.0, 3610.0, 4520.0]:
			glass += sin(TAU * k * t) * exp(-t * (18.0 + k * 0.004))
		glass *= 0.22
		var burst: float = lp * exp(-t * 14.0) * 0.8
		out[i] = clampf((thump * 1.1 + glass + burst) * 0.85, -1.0, 1.0)
	return out


## Adrenaline activation: a rising swell that lands on a snare + kick.
func _gen_adren_on() -> PackedFloat32Array:
	var n := int(RATE * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / 0.9
		# Riser: filtered noise opening up over 0.6 s.
		var white: float = _rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * lerpf(0.03, 0.75, clampf(k / 0.66, 0.0, 1.0))
		var riser: float = lp * clampf(k / 0.66, 0.0, 1.0) * 0.6
		# Impact at 0.66 s.
		var imp := 0.0
		var ti: float = t - 0.6
		if ti >= 0.0:
			var f: float = 48.0 + 130.0 * exp(-ti * 40.0)
			ph += TAU * f / RATE
			imp = sin(ph) * exp(-ti * 9.0) * 1.1
			imp += _rng.randf_range(-1.0, 1.0) * exp(-ti * 28.0) * 0.6
		out[i] = clampf((riser + imp) * 0.9, -1.0, 1.0)
	return out


func _gen_engine() -> PackedFloat32Array:
	# Exactly one second, all partials at integer frequencies => seamless loop.
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * 0.08
		var win: float = 0.5 - 0.5 * cos(TAU * t)
		var s := _saw(58.0, t) * 0.35 + _saw(87.0, t) * 0.2 + _sine(29.0, t) * 0.25 + _sqr(116.0, t) * 0.08
		s *= 0.8 + 0.2 * _sine(3.0, t)
		out[i] = s * 0.55 + lp * 0.35 * win
	return out


# -------------------------------------------------- theme 1: VOLTAGE HIGHWAY
## 124 BPM four-on-the-floor synthwave: Am - F - C - G.
func _gen_music() -> PackedFloat32Array:
	var beat := int(roundf(60.0 / 124.0 * RATE))
	var bars := 4
	var total := beat * 4 * bars
	var out := PackedFloat32Array()
	out.resize(total)

	var roots := [55.0, 43.65, 65.41, 49.0]
	var arps := [
		[440.0, 523.25, 659.25, 880.0],
		[349.23, 440.0, 523.25, 698.46],
		[523.25, 659.25, 783.99, 1046.5],
		[392.0, 493.88, 587.33, 783.99],
	]
	var pattern := [0, 1, 2, 3, 2, 1, 3, 2]

	var delay_len := int(beat * 0.75)
	var delay_buf := PackedFloat32Array()
	delay_buf.resize(delay_len)
	var dpos := 0
	var bass_lp := 0.0
	var hat_lp := 0.0
	var sixteenth := beat / 4

	for i in total:
		var t := float(i) / RATE
		var bar := (i / (beat * 4)) % bars
		var beat_i := i % beat
		var bt := float(beat_i) / RATE
		var step := i / sixteenth
		var st := float(i % sixteenth) / RATE
		var root: float = roots[bar]

		var kick_env: float = exp(-bt * 16.0)
		var kick: float = _sine(lerpf(125.0, 46.0, clampf(bt * 22.0, 0.0, 1.0)), bt) * kick_env * 0.85

		var snare := 0.0
		var beat_in_bar := (i / beat) % 4
		if beat_in_bar == 1 or beat_in_bar == 3:
			var se: float = exp(-bt * 26.0)
			snare = (_rng.randf_range(-1.0, 1.0) * 0.6 + _sine(210.0, bt) * 0.35) * se * 0.4

		var hat_t := float(i % (beat / 2)) / RATE
		hat_lp += (_rng.randf_range(-1.0, 1.0) - hat_lp) * 0.75
		var hat: float = hat_lp * exp(-hat_t * 90.0) * 0.16

		var bass_t := float(i % (beat / 2)) / RATE
		var bass_raw: float = _saw(root, t) * 0.6 + _saw(root * 1.004, t) * 0.4 + _sine(root * 0.5, t) * 0.4
		bass_lp += (bass_raw - bass_lp) * 0.16
		var bass: float = bass_lp * exp(-bass_t * 7.0) * 0.55

		var note_i: int = pattern[step % pattern.size()]
		var oct: float = 2.0 if (step % 16) >= 12 else 1.0
		var af: float = arps[bar][note_i] * oct
		var arp: float = (_sqr(af, st) * 0.3 + _saw(af * 1.006, st) * 0.25) * exp(-st * 15.0) * 0.35

		var echoed: float = arp + delay_buf[dpos] * 0.42
		delay_buf[dpos] = echoed
		dpos = (dpos + 1) % delay_len

		var pad: float = (_saw(root * 4.0, t) * 0.5 + _saw(root * 6.0 * 1.003, t) * 0.4) * 0.06
		pad *= 0.6 + 0.4 * _sine(0.25, t)

		var mix: float = kick + snare + hat + bass + echoed * 0.9 + pad
		out[i] = clampf(mix * 0.72, -1.0, 1.0)

	_loop_fade(out, 220)
	return out


# -------------------------------------------------- theme 2: DUNE PROTOCOL
## 100 BPM half-time desert groove: Phrygian-dominant vamp G - F - Ab - F#.
func _gen_music_ember() -> PackedFloat32Array:
	var beat := int(roundf(60.0 / 100.0 * RATE))
	var bars := 4
	var total := beat * 4 * bars
	var out := PackedFloat32Array()
	out.resize(total)

	var roots := [49.0, 43.65, 51.91, 46.25]
	var arps := [
		[392.00, 466.16, 587.33, 783.99],
		[349.23, 440.00, 523.25, 698.46],
		[415.30, 523.25, 622.25, 830.61],
		[369.99, 466.16, 554.37, 739.99],
	]
	var pattern := [0, 2, 1, 3, 2, 0, 3, 1]

	var delay_len := int(beat * 1.0)
	var delay_buf := PackedFloat32Array()
	delay_buf.resize(delay_len)
	var dpos := 0
	var bass_lp := 0.0
	var perc_lp := 0.0
	var sixteenth := beat / 4

	for i in total:
		var t := float(i) / RATE
		var bar := (i / (beat * 4)) % bars
		var beat_i := i % beat
		var beat_in_bar := (i / beat) % 4
		var bt := float(beat_i) / RATE
		var step := i / sixteenth
		var st := float(i % sixteenth) / RATE
		var root: float = roots[bar]

		var kick := 0.0
		if beat_in_bar == 0 or (beat_in_bar == 2 and beat_i >= beat / 2):
			kick = _sine(lerpf(140.0, 42.0, clampf(bt * 20.0, 0.0, 1.0)), bt) * exp(-bt * 11.0) * 0.95

		var snare := 0.0
		if beat_in_bar == 2:
			var se: float = exp(-bt * 9.0)
			snare = (_rng.randf_range(-1.0, 1.0) * 0.55 + _sine(190.0, bt) * 0.3) * se * 0.5

		perc_lp += (_rng.randf_range(-1.0, 1.0) - perc_lp) * 0.85
		var pt: float = float(i % (beat / 4)) / RATE
		var accent: float = 1.0 if (step % 4 == 0) else 0.45
		var perc: float = perc_lp * exp(-pt * 120.0) * 0.13 * accent

		var bass_t := float(i % (beat * 2)) / RATE
		var bass_raw: float = _sine(root * 0.5, t) * 0.8 + _saw(root, t) * 0.25 + _saw(root * 1.006, t) * 0.2
		bass_lp += (bass_raw - bass_lp) * 0.11
		var bass: float = bass_lp * exp(-bass_t * 2.4) * 0.7

		var arp := 0.0
		if step % 2 == 0:
			var note_i: int = pattern[(step / 2) % pattern.size()]
			var oct: float = 1.0 if (step % 32) < 20 else 0.5
			var af: float = arps[bar][note_i] * oct
			arp = (_saw(af, st) * 0.45 + _sqr(af * 2.0, st) * 0.12) * exp(-st * 9.0) * 0.4

		var echoed: float = arp + delay_buf[dpos] * 0.5
		delay_buf[dpos] = echoed
		dpos = (dpos + 1) % delay_len

		var pad: float = (_saw(root * 2.0, t) * 0.35 + _saw(root * 2.0 * 1.008, t) * 0.35
				+ _saw(root * 3.0 * 0.997, t) * 0.2) * 0.075
		pad *= 0.65 + 0.35 * _sine(0.2, t)

		var mix: float = kick + snare + perc + bass + echoed * 0.95 + pad
		out[i] = clampf(mix * 0.74, -1.0, 1.0)

	_loop_fade(out, 260)
	return out


# -------------------------------------------------- theme 3: POLAR CIRCUIT
## 138 BPM uplifting trance: Em - C - G - D. Off-beat bass, supersaw 16ths,
## open hats on the off-beats, clap on 2 & 4 and a dotted-eighth delay.
func _gen_music_polar() -> PackedFloat32Array:
	var beat := int(roundf(60.0 / 138.0 * RATE))
	var bars := 4
	var total := beat * 4 * bars
	var out := PackedFloat32Array()
	out.resize(total)

	var roots := [82.41, 65.41, 98.0, 73.42]
	var arps := [
		[329.63, 392.0, 493.88, 659.25],
		[261.63, 329.63, 392.0, 523.25],
		[392.0, 493.88, 587.33, 783.99],
		[293.66, 369.99, 440.0, 587.33],
	]
	var pattern := [0, 1, 2, 3, 1, 2, 3, 2, 0, 2, 1, 3, 2, 3, 1, 0]

	var delay_len := int(beat * 0.75)
	var delay_buf := PackedFloat32Array()
	delay_buf.resize(delay_len)
	var dpos := 0
	var bass_lp := 0.0
	var hat_lp := 0.0
	var hat_hp := 0.0
	var sixteenth := beat / 4
	var eighth := beat / 2

	for i in total:
		var t := float(i) / RATE
		var bar := (i / (beat * 4)) % bars
		var beat_i := i % beat
		var beat_in_bar := (i / beat) % 4
		var bt := float(beat_i) / RATE
		var step := i / sixteenth
		var st := float(i % sixteenth) / RATE
		var root: float = roots[bar]

		# Punchy kick on every beat.
		var kick: float = _sine(lerpf(150.0, 45.0, clampf(bt * 24.0, 0.0, 1.0)), bt) * exp(-bt * 14.0) * 0.9

		# Clap on 2 and 4 (three noise bursts).
		var clap := 0.0
		if beat_in_bar == 1 or beat_in_bar == 3:
			var burst := fmod(bt, 0.012)
			var ce: float = exp(-bt * 22.0) * (1.0 if bt < 0.04 else 0.55)
			clap = (_rng.randf_range(-1.0, 1.0) * 0.7) * ce * (0.6 + 0.4 * exp(-burst * 300.0)) * 0.45

		# Off-beat bass (the "and" of every beat).
		var bass := 0.0
		if beat_i >= eighth:
			var ob := float(beat_i - eighth) / RATE
			var braw: float = _saw(root, t) * 0.5 + _saw(root * 1.005, t) * 0.35 + _saw(root * 0.995, t) * 0.35 + _sine(root * 0.5, t) * 0.5
			bass_lp += (braw - bass_lp) * 0.2
			bass = bass_lp * exp(-ob * 9.0) * 0.62
		else:
			bass_lp += (0.0 - bass_lp) * 0.2

		# Open hat on the off-beats + soft closed hats on 16ths.
		hat_lp += (_rng.randf_range(-1.0, 1.0) - hat_lp) * 0.6
		hat_hp = hat_lp - hat_hp * 0.3
		var ohat := 0.0
		if beat_i >= eighth:
			var ot := float(beat_i - eighth) / RATE
			ohat = hat_hp * exp(-ot * 18.0) * 0.14
		var chat: float = hat_hp * exp(-st * 110.0) * 0.07

		# Supersaw lead on 16ths (three detuned saws).
		var note_i: int = pattern[step % pattern.size()]
		var oct: float = 2.0 if (step % 32) >= 24 else 1.0
		var af: float = arps[bar][note_i] * oct
		var ss: float = _saw(af, st) + _saw(af * 1.007, st + 0.001) + _saw(af * 0.993, st + 0.002)
		var lead: float = ss * 0.33 * exp(-st * 11.0) * 0.4

		var echoed: float = lead + delay_buf[dpos] * 0.38
		delay_buf[dpos] = echoed
		dpos = (dpos + 1) % delay_len

		# Wide pad.
		var pad: float = (_saw(root * 4.0, t) * 0.4 + _saw(root * 4.0 * 1.006, t) * 0.4 + _saw(root * 6.0 * 0.994, t) * 0.25) * 0.05
		pad *= 0.7 + 0.3 * _sine(0.35, t)

		var mix: float = kick + clap + bass + ohat + chat + echoed * 0.9 + pad
		out[i] = clampf(mix * 0.7, -1.0, 1.0)

	_loop_fade(out, 240)
	return out


## ------------------------------------------------------------------ theme 4: MIDNIGHT IN VIOLET
## 92 BPM original noir-jazz score: brushed swing drums, upright-style walking
## bass, smoky vibraphone/piano stabs and a muted horn pad. It is intentionally
## organic, nocturnal and cinematic rather than a fourth synthwave variation.
func _gen_music_nocturne() -> PackedFloat32Array:
	var beat := int(roundf(60.0 / 92.0 * RATE))
	var bars := 4
	var total := beat * 4 * bars
	var out := PackedFloat32Array()
	out.resize(total)
	# Am7 - Dm7 - E7#9 - Am6: a compact noir turnaround.
	var roots := [55.0, 36.71, 41.20, 55.0]
	var chord_tones := [
		[220.0, 261.63, 329.63, 392.0],
		[293.66, 349.23, 440.0, 523.25],
		[329.63, 415.30, 493.88, 622.25],
		[220.0, 277.18, 329.63, 440.0],
	]
	var walk := [0.5, 0.75, 1.0, 1.25, 1.0, 0.84, 0.75, 0.67]
	var delay_len := int(beat * 0.85)
	var delay_buf := PackedFloat32Array()
	delay_buf.resize(delay_len)
	var dpos := 0
	var bass_lp := 0.0
	var sixteenth := beat / 4
	for i in total:
		var t := float(i) / RATE
		var bar := (i / (beat * 4)) % bars
		var beat_i := i % beat
		var beat_in_bar := (i / beat) % 4
		var bt := float(beat_i) / RATE
		var step := i / sixteenth
		var st := float(i % sixteenth) / RATE
		var root: float = roots[bar]

		# Brushes: soft swish every 8th, a snare brush accent on 2 and 4.
		var brush_t: float = float(i % (beat / 2)) / RATE
		var brush := _rng.randf_range(-1.0, 1.0) * exp(-brush_t * 34.0) * 0.075
		var accent := 0.0
		if beat_in_bar == 1 or beat_in_bar == 3:
			accent = (_rng.randf_range(-1.0, 1.0) * 0.28 + _sine(185.0, bt) * 0.16) * exp(-bt * 18.0)

		# Walking bass: one plucked note per quarter, round and woody.
		var walk_i: int = (bar * 4 + beat_in_bar) % walk.size()
		var bf: float = root * walk[walk_i]
		var bass_raw: float = _sine(bf, bt) * 0.78 + _saw(bf * 0.5, bt) * 0.13
		bass_lp += (bass_raw - bass_lp) * 0.12
		var bass: float = bass_lp * exp(-bt * 5.0) * 0.70

		# Vibraphone/piano hit on swung offbeats. The 2/3 timing supplies the
		# jazz swing without changing the gameplay's steady beat clock.
		var swing_offset := int(float(beat) * 0.66)
		var is_swing := beat_i > swing_offset and beat_i < swing_offset + sixteenth
		var chord := 0.0
		if is_swing or (beat_in_bar == 0 and bt < 0.035):
			var ct := bt if beat_in_bar == 0 else float(beat_i - swing_offset) / RATE
			for f in chord_tones[bar]:
				chord += (_sine(f, ct) * 0.18 + _sine(f * 2.003, ct) * 0.065) * exp(-ct * 4.2)
		var echo: float = chord + delay_buf[dpos] * 0.36
		delay_buf[dpos] = echo
		dpos = (dpos + 1) % delay_len

		# Muted horn pad underneath the rhythm section.
		var pad: float = (_sine(root * 4.0, t) * 0.45 + _sine(root * 5.0 * 1.004, t) * 0.24 + _sine(root * 6.0 * 0.997, t) * 0.18) * 0.045
		pad *= 0.7 + 0.3 * _sine(0.13, t)

		out[i] = clampf((brush + accent + bass + echo + pad) * 0.96, -1.0, 1.0)
	_loop_fade(out, 340)
	return out


func _loop_fade(out: PackedFloat32Array, fade: int) -> void:
	var total := out.size()
	for j in fade:
		var a := float(j) / float(fade)
		out[j] = out[j] * a
		out[total - 1 - j] = out[total - 1 - j] * a


# ------------------------------------------------------------------ jukebox

func _theme_stream(biome_id: int) -> AudioStreamWAV:
	if not _theme_cache.has(biome_id):
		var samples: PackedFloat32Array
		match biome_id:
			Biomes.EMBER:
				samples = _gen_music_ember()
			Biomes.AURORA:
				samples = _gen_music_polar()
			Biomes.NOCTURNE:
				samples = _gen_music_nocturne()
			_:
				samples = _gen_music()
		_theme_cache[biome_id] = _wav(samples, true)
	return _theme_cache[biome_id]


func play_biome_music(biome_id: int) -> void:
	_synth_biome = biome_id
	if music_mode != 0:
		return
	var st := _theme_stream(biome_id)
	if _music.stream != st:
		_music.stream = st
		_music.play()
		reset_track_analysis()
	elif not _music.playing:
		_music.play()


func use_synth() -> void:
	music_mode = 0
	Persist.music_mode = 0
	Persist.save_profile()
	device_playing = false
	_music.stream_paused = false
	_music.stream = null
	play_biome_music(Persist.biome)
	source_changed.emit(0)
	track_changed.emit(current_track_name())


func use_device() -> void:
	if device_paths.is_empty():
		return
	music_mode = 1
	Persist.music_mode = 1
	Persist.save_profile()
	_tracker.reset()
	play_device(device_index)
	source_changed.emit(1)


## Rebuilds the playable list from the persisted files + folders.
func rebuild_library() -> void:
	device_paths = PackedStringArray()
	device_names = PackedStringArray()
	for f in Persist.music_files:
		_add_path(f)
	for d in Persist.music_folders:
		_scan_dir(d, 0)
	_build_order()
	device_index = clampi(Persist.device_index, 0, maxi(device_paths.size() - 1, 0))
	device_library_changed.emit()


func add_files(paths: PackedStringArray) -> int:
	var added := 0
	for p in paths:
		if _is_audio(p) and not Persist.music_files.has(p):
			Persist.music_files.append(p)
			added += 1
	Persist.save_profile()
	rebuild_library()
	return added


func add_folder(path: String) -> int:
	if not Persist.music_folders.has(path):
		Persist.music_folders.append(path)
	Persist.save_profile()
	var before := device_paths.size()
	rebuild_library()
	return device_paths.size() - before


## One-click: import the OS music library folder.
func scan_system_music() -> int:
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return 0
	return add_folder(dir)


func clear_library() -> void:
	Persist.music_files = PackedStringArray()
	Persist.music_folders = PackedStringArray()
	Persist.save_profile()
	if music_mode == 1:
		use_synth()
	rebuild_library()


func set_shuffle(on: bool) -> void:
	shuffle = on
	Persist.shuffle = on
	Persist.save_profile()
	_build_order()


func _build_order() -> void:
	_order.clear()
	for i in device_paths.size():
		_order.append(i)
	if shuffle:
		_order.shuffle()
	_order_pos = 0


static func _is_audio(p: String) -> bool:
	var ext := p.get_extension().to_lower()
	return ext == "ogg" or ext == "mp3" or ext == "wav"


func _add_path(p: String) -> void:
	if device_paths.size() >= 600 or device_paths.has(p):
		return
	device_paths.append(p)
	device_names.append(p.get_file().get_basename())


func _scan_dir(path: String, depth: int) -> void:
	if device_paths.size() >= 600 or depth > 2:
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	if d.list_dir_begin() != OK:
		return
	var f := d.get_next()
	while f != "":
		if not f.begins_with("."):
			if d.current_is_dir():
				_scan_dir(path.path_join(f), depth + 1)
			elif _is_audio(f):
				_add_path(path.path_join(f))
		f = d.get_next()
	d.list_dir_end()


## Loads a music file from anywhere on disk. Godot 4.4+ ships native loaders
## for all three formats; a hand-rolled decoder path remains as a fallback.
func _load_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var st: AudioStream = null
	match path.get_extension().to_lower():
		"ogg":
			st = AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			st = AudioStreamMP3.load_from_file(path)
		"wav":
			st = AudioStreamWAV.load_from_file(path)
	if st == null:
		st = _load_stream_manual(path)
	return st


func _load_stream_manual(path: String) -> AudioStream:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 32:
		return null
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.set_data(bytes)
			return null if mp3.get_data().is_empty() else mp3
		"wav":
			return _parse_wav(bytes)
	return null


static func _fourcc(bytes: PackedByteArray, o: int) -> String:
	if o < 0 or o + 4 > bytes.size():
		return ""
	return bytes.slice(o, o + 4).get_string_from_ascii()


## Minimal RIFF/WAVE reader (8/16/24-bit PCM, 32-bit float).
static func _parse_wav(bytes: PackedByteArray) -> AudioStreamWAV:
	if _fourcc(bytes, 0) != "RIFF" or _fourcc(bytes, 8) != "WAVE":
		return null
	var pos := 12
	var audio_format := 1
	var channels := 1
	var rate := 44100
	var bits := 16
	var data := PackedByteArray()
	while pos + 8 <= bytes.size():
		var id := _fourcc(bytes, pos)
		var size: int = bytes.decode_u32(pos + 4)
		var body := pos + 8
		if size <= 0 or body + size > bytes.size():
			break
		if id == "fmt " and size >= 16:
			audio_format = bytes.decode_u16(body)
			channels = bytes.decode_u16(body + 2)
			rate = bytes.decode_u32(body + 4)
			bits = bytes.decode_u16(body + 14)
		elif id == "data":
			data = bytes.slice(body, body + size)
		pos = body + size + (size & 1)
	if data.is_empty() or rate <= 0 or channels < 1 or channels > 2:
		return null
	var wav := AudioStreamWAV.new()
	wav.mix_rate = rate
	wav.stereo = channels == 2
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	match audio_format:
		1, 0xFFFE:
			if bits == 8:
				wav.format = AudioStreamWAV.FORMAT_8_BITS
				wav.data = data
			elif bits == 16:
				wav.data = data
			elif bits == 24:
				wav.data = _wav24_to_16(data)
			else:
				return null
		3:
			if bits == 32:
				wav.data = _wav_f32_to_16(data)
			else:
				return null
		_:
			return null
	return wav


static func _wav24_to_16(src: PackedByteArray) -> PackedByteArray:
	var n: int = src.size() / 3
	var out := PackedByteArray()
	out.resize(n * 2)
	for i in n:
		var v: int = src[i * 3] | (src[i * 3 + 1] << 8) | (src[i * 3 + 2] << 16)
		if v >= 0x800000:
			v -= 0x1000000
		out.encode_s16(i * 2, clampi(v >> 8, -32768, 32767))
	return out


static func _wav_f32_to_16(src: PackedByteArray) -> PackedByteArray:
	var n: int = src.size() / 4
	var out := PackedByteArray()
	out.resize(n * 2)
	for i in n:
		var fv: float = src.decode_float(i * 4)
		out.encode_s16(i * 2, clampi(int(clampf(fv, -1.0, 1.0) * 32767.0), -32768, 32767))
	return out


func play_device(index: int) -> void:
	if device_paths.is_empty():
		return
	device_index = wrapi(index, 0, device_paths.size())
	Persist.device_index = device_index
	var st := _load_stream(device_paths[device_index])
	if st == null:
		# Unreadable file: skip it so one bad track never stalls the playlist.
		track_changed.emit("SKIPPED: %s" % device_names[device_index])
		if device_paths.size() > 1:
			call_deferred("play_device", device_index + 1)
		return
	music_mode = 1
	device_playing = true
	_music.stream_paused = false
	_music.stream = st
	_music.play()
	_tracker.reset()
	reset_track_analysis()
	track_changed.emit(device_names[device_index])


func _step_track(dir: int) -> void:
	if device_paths.is_empty():
		return
	if shuffle and _order.size() == device_paths.size():
		_order_pos = wrapi(_order_pos + dir, 0, _order.size())
		play_device(_order[_order_pos])
	else:
		play_device(device_index + dir)


func next_track() -> void:
	if music_mode == 1:
		_step_track(1)


func prev_track() -> void:
	if music_mode == 1:
		_step_track(-1)


func toggle_play() -> void:
	if music_mode != 1:
		return
	if _music.playing and not _music.stream_paused:
		_music.stream_paused = true
	else:
		_music.stream_paused = false
		if not _music.playing:
			play_device(device_index)


func is_music_paused() -> bool:
	return music_mode == 1 and _music.stream_paused


func track_progress() -> float:
	if _music.stream == null:
		return 0.0
	var l := _music.stream.get_length()
	if l <= 0.0:
		return 0.0
	return clampf(_music.get_playback_position() / l, 0.0, 1.0)


func track_position() -> float:
	return _music.get_playback_position() if _music.stream != null else 0.0


func track_length() -> float:
	return _music.stream.get_length() if _music.stream != null else 0.0


func _on_music_finished() -> void:
	if music_mode == 1 and device_playing:
		_step_track(1)
	else:
		_music.play()


func current_track_name() -> String:
	if music_mode == 1 and device_index < device_names.size():
		return device_names[device_index]
	return "SYNTH — %s" % Biomes.theme_of(Persist.biome)
