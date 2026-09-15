extends RefCounted
## Biome (map) definitions. Every visual parameter AND the theme song are data
## driven here, so adding a map is a matter of filling in one dictionary.
## NOTE: intentionally no `class_name` - autoload scripts are parsed before the
## global class cache is ready, so consumers use:
##     const Biomes := preload("res://scripts/biomes.gd")

const NEON := 0
const EMBER := 1
const AURORA := 2
const NOCTURNE := 3
const COUNT := 4

const THEME_NAMES := ["VOLTAGE HIGHWAY", "DUNE PROTOCOL", "POLAR CIRCUIT", "MIDNIGHT IN VIOLET"]
const THEME_BPM := [124.0, 100.0, 138.0, 92.0]


static func name_of(id: int) -> String:
	return visual(id)["name"]


static func subtitle_of(id: int) -> String:
	return visual(id)["sub"]


static func theme_of(id: int) -> String:
	return THEME_NAMES[clampi(id, 0, COUNT - 1)]


static func bpm_of(id: int) -> float:
	return THEME_BPM[clampi(id, 0, COUNT - 1)]


static func visual(id: int) -> Dictionary:
	match id:
		EMBER:
			return {
				"name": "EMBER CANYON",
				"sub": "SECTOR 02 — DUNE PROTOCOL",
				"sky": {
					"zenith": Color(0.05, 0.012, 0.07), "horizon": Color(1.0, 0.33, 0.07),
					"ground": Color(0.06, 0.02, 0.02), "sun": Color(1.0, 0.72, 0.25),
					"sun_core": Color(1.0, 0.97, 0.82), "stars": 0.9965, "intensity": 1.15,
					"aurora": 0.0, "aurora_a": Color(1, 0.6, 0.2), "aurora_b": Color(1, 0.2, 0.3),
				},
				"fog": {
					"color": Color(0.62, 0.2, 0.06), "density": 0.0165,
					"vol": 0.016, "vol_albedo": Color(0.95, 0.62, 0.32), "vol_emission": Color(0.28, 0.07, 0.02),
				},
				"grid": {"base": Color(0.045, 0.016, 0.01), "grid": Color(1.0, 0.55, 0.12), "edge": Color(1.0, 0.16, 0.3), "cell": 4.0},
				"orb": Color(1.0, 0.85, 0.3),
				"obst": {
					"block": Color(1.0, 0.2, 0.16), "low": Color(1.0, 0.78, 0.18), "hang": Color(0.25, 0.95, 0.88),
					"mover": Color(1.0, 0.42, 0.1), "spin": Color(1.0, 0.92, 0.6), "hunter": Color(1.0, 0.12, 0.1),
					"laser": Color(1.0, 0.75, 0.35),
				},
				"rail": {"albedo": Color(0.09, 0.04, 0.03), "emit": Color(1.0, 0.4, 0.12), "energy": 2.6},
				"post": {"albedo": Color(0.07, 0.03, 0.02), "emit": Color(1.0, 0.72, 0.2), "energy": 3.4},
				"arch": {"albedo": Color(0.08, 0.035, 0.025), "emit": Color(1.0, 0.35, 0.1), "energy": 2.4},
				"tower": {"albedo": Color(0.09, 0.045, 0.03), "emit": Color(0.75, 0.3, 0.1), "energy": 0.7},
				"building": {
					"style": 1, "base": Color(0.115, 0.055, 0.04), "window": Color(1.0, 0.62, 0.18),
					"accent": Color(1.0, 0.18, 0.08), "density": 0.34, "energy": 2.6,
					"h_min": 10.0, "h_max": 62.0, "w_min": 12.0, "w_max": 30.0, "d_min": 24.0, "d_max": 98.0,
				},
				"bridge": {"deck": Color(0.1, 0.05, 0.03), "rail": Color(1.0, 0.55, 0.15), "swirl_a": Color(1.0, 0.75, 0.25), "swirl_b": Color(1.0, 0.25, 0.2)},
				"light": {
					"ambient": Color(0.6, 0.34, 0.22), "ambient_e": 0.62, "key": Color(1.0, 0.78, 0.52), "key_e": 1.15,
					"fill": Color(1.0, 0.28, 0.12), "fill_e": 0.5,
				},
				"dust": Color(1.0, 0.62, 0.25),
			}
		AURORA:
			return {
				"name": "AURORA RIDGE",
				"sub": "SECTOR 03 — GLACIER PROTOCOL",
				"sky": {
					"zenith": Color(0.01, 0.02, 0.07), "horizon": Color(0.05, 0.42, 0.5),
					"ground": Color(0.01, 0.02, 0.04), "sun": Color(0.55, 0.95, 1.0),
					"sun_core": Color(0.95, 1.0, 1.0), "stars": 0.975, "intensity": 1.0,
					"aurora": 1.0, "aurora_a": Color(0.2, 1.0, 0.55), "aurora_b": Color(0.55, 0.3, 1.0),
				},
				"fog": {
					"color": Color(0.08, 0.3, 0.36), "density": 0.0135,
					"vol": 0.011, "vol_albedo": Color(0.6, 0.9, 1.0), "vol_emission": Color(0.02, 0.1, 0.14),
				},
				"grid": {"base": Color(0.012, 0.03, 0.05), "grid": Color(0.55, 0.95, 1.0), "edge": Color(0.3, 1.0, 0.7), "cell": 4.0},
				"orb": Color(0.85, 1.0, 0.95),
				"obst": {
					"block": Color(1.0, 0.3, 0.5), "low": Color(1.0, 0.85, 0.3), "hang": Color(0.4, 0.9, 1.0),
					"mover": Color(1.0, 0.55, 0.2), "spin": Color(0.75, 0.55, 1.0), "hunter": Color(1.0, 0.2, 0.35),
					"laser": Color(0.75, 0.95, 1.0),
				},
				"rail": {"albedo": Color(0.03, 0.06, 0.09), "emit": Color(0.35, 1.0, 0.75), "energy": 2.4},
				"post": {"albedo": Color(0.03, 0.05, 0.08), "emit": Color(0.6, 0.95, 1.0), "energy": 3.2},
				"arch": {"albedo": Color(0.03, 0.05, 0.08), "emit": Color(0.55, 0.4, 1.0), "energy": 2.2},
				"tower": {"albedo": Color(0.04, 0.07, 0.1), "emit": Color(0.2, 0.55, 0.7), "energy": 0.6},
				"building": {
					"style": 2, "base": Color(0.05, 0.1, 0.16), "window": Color(0.5, 0.95, 1.0),
					"accent": Color(0.6, 1.0, 0.8), "density": 0.3, "energy": 2.4,
					"h_min": 16.0, "h_max": 78.0, "w_min": 7.0, "w_max": 17.0, "d_min": 22.0, "d_max": 92.0,
				},
				"bridge": {"deck": Color(0.03, 0.06, 0.1), "rail": Color(0.5, 1.0, 0.85), "swirl_a": Color(0.3, 1.0, 0.65), "swirl_b": Color(0.6, 0.4, 1.0)},
				"light": {
					"ambient": Color(0.3, 0.45, 0.6), "ambient_e": 0.55, "key": Color(0.7, 0.9, 1.0), "key_e": 1.0,
					"fill": Color(0.4, 1.0, 0.7), "fill_e": 0.4,
				},
				"dust": Color(0.75, 1.0, 0.95),
			}
		NOCTURNE:
			return {
				"name": "NOCTURNE BOULEVARD",
				"sub": "SECTOR 04 — CRIMSON DUSK TO VIOLET MIDNIGHT",
				"sky": {
					"zenith": Color(0.19, 0.012, 0.025), "horizon": Color(0.78, 0.055, 0.09),
					"ground": Color(0.012, 0.008, 0.026), "sun": Color(0.58, 0.04, 0.06),
					"sun_core": Color(0.95, 0.17, 0.14), "stars": 0.991, "intensity": 0.82,
					"aurora": 0.0, "aurora_a": Color(0.26, 0.14, 0.52), "aurora_b": Color(0.68, 0.2, 0.4),
					"night_zenith": Color(0.006, 0.006, 0.035), "night_horizon": Color(0.10, 0.024, 0.23),
					"moon": 1.0, "moon_color": Color(0.95, 0.91, 0.72), "moon_size": 0.115,
				},
				"fog": {
					"color": Color(0.42, 0.025, 0.075), "density": 0.012,
					"vol": 0.008, "vol_albedo": Color(0.28, 0.05, 0.16), "vol_emission": Color(0.055, 0.005, 0.028),
				},
				"grid": {"base": Color(0.026, 0.025, 0.055), "grid": Color(0.18, 0.25, 0.42), "edge": Color(0.72, 0.18, 0.35), "cell": 6.0},
				"road": {
					"street_mode": 1.0, "asphalt": Color(0.045, 0.055, 0.10), "curb": Color(0.22, 0.12, 0.34),
					"line": Color(0.82, 0.72, 0.52), "center": Color(0.92, 0.58, 0.22), "wetness": 0.82,
				},
				"orb": Color(0.92, 0.73, 0.42),
				"obst": {
					"block": Color(0.38, 0.04, 0.085), "low": Color(0.74, 0.38, 0.18), "hang": Color(0.22, 0.28, 0.48),
					"mover": Color(0.62, 0.10, 0.18), "spin": Color(0.54, 0.3, 0.72), "hunter": Color(0.08, 0.08, 0.14),
					"laser": Color(0.92, 0.68, 0.44), "obelisk": Color(0.085, 0.09, 0.16), "dustwall": Color(0.18, 0.035, 0.09),
					"cab": Color(0.045, 0.055, 0.10), "cab_trim": Color(0.92, 0.7, 0.32),
				},
				"rail": {"albedo": Color(0.05, 0.06, 0.12), "emit": Color(0.26, 0.24, 0.5), "energy": 0.42},
				"post": {"albedo": Color(0.07, 0.06, 0.12), "emit": Color(0.88, 0.72, 0.44), "energy": 0.65},
				"arch": {"albedo": Color(0.06, 0.055, 0.10), "emit": Color(0.58, 0.28, 0.46), "energy": 0.48},
				"tower": {"albedo": Color(0.025, 0.026, 0.055), "emit": Color(0.20, 0.16, 0.34), "energy": 0.18},
				"building": {
					"style": 4, "base": Color(0.025, 0.03, 0.07), "window": Color(0.96, 0.73, 0.28),
					"accent": Color(0.42, 0.08, 0.16), "density": 0.27, "energy": 0.72,
					"h_min": 32.0, "h_max": 146.0, "w_min": 8.0, "w_max": 26.0, "d_min": 38.0, "d_max": 92.0,
				},
				"bridge": {"deck": Color(0.055, 0.055, 0.11), "rail": Color(0.68, 0.32, 0.58), "swirl_a": Color(0.86, 0.6, 0.38), "swirl_b": Color(0.30, 0.22, 0.62)},
				"light": {
					"ambient": Color(0.22, 0.07, 0.24), "ambient_e": 0.52, "key": Color(0.92, 0.35, 0.30), "key_e": 0.86,
					"fill": Color(0.24, 0.18, 0.50), "fill_e": 0.40,
				},
				"dust": Color(0.58, 0.18, 0.32),
			}
		_:
			return {
				"name": "NEON GRID",
				"sub": "SECTOR 01 — MIDNIGHT CITY",
				"sky": {
					"zenith": Color(0.015, 0.005, 0.06), "horizon": Color(0.42, 0.04, 0.42),
					"ground": Color(0.008, 0.004, 0.025), "sun": Color(1.0, 0.32, 0.62),
					"sun_core": Color(1.0, 0.85, 0.45), "stars": 0.986, "intensity": 1.0,
					"aurora": 0.0, "aurora_a": Color(0.2, 1.0, 0.55), "aurora_b": Color(0.55, 0.3, 1.0),
				},
				"fog": {
					"color": Color(0.2, 0.045, 0.36), "density": 0.0125,
					"vol": 0.012, "vol_albedo": Color(0.55, 0.4, 0.9), "vol_emission": Color(0.07, 0.02, 0.16),
				},
				"grid": {"base": Color(0.012, 0.008, 0.035), "grid": Color(0.13, 0.85, 1.0), "edge": Color(1.0, 0.13, 0.58), "cell": 4.0},
				"orb": Color(0.18, 0.95, 1.0),
				"obst": {
					"block": Color(1.0, 0.16, 0.62), "low": Color(1.0, 0.78, 0.16), "hang": Color(0.18, 0.95, 1.0),
					"mover": Color(1.0, 0.46, 0.12), "spin": Color(0.62, 0.36, 1.0), "hunter": Color(1.0, 0.15, 0.25),
					"laser": Color(1.0, 0.45, 0.75),
				},
				"rail": {"albedo": Color(0.06, 0.02, 0.12), "emit": Color(1.0, 0.16, 0.62), "energy": 2.4},
				"post": {"albedo": Color(0.04, 0.03, 0.09), "emit": Color(0.18, 0.95, 1.0), "energy": 3.2},
				"arch": {"albedo": Color(0.05, 0.02, 0.1), "emit": Color(0.62, 0.36, 1.0), "energy": 2.2},
				"tower": {"albedo": Color(0.03, 0.02, 0.07), "emit": Color(0.35, 0.12, 0.6), "energy": 0.55},
				"building": {
					"style": 0, "base": Color(0.025, 0.02, 0.055), "window": Color(0.2, 0.9, 1.0),
					"accent": Color(1.0, 0.3, 0.72), "density": 0.44, "energy": 3.2,
					"h_min": 18.0, "h_max": 92.0, "w_min": 9.0, "w_max": 22.0, "d_min": 24.0, "d_max": 96.0,
				},
				"bridge": {"deck": Color(0.04, 0.02, 0.09), "rail": Color(0.2, 0.95, 1.0), "swirl_a": Color(0.2, 0.95, 1.0), "swirl_b": Color(1.0, 0.2, 0.7)},
				"light": {
					"ambient": Color(0.32, 0.24, 0.55), "ambient_e": 0.5, "key": Color(0.78, 0.72, 1.0), "key_e": 0.95,
					"fill": Color(1.0, 0.35, 0.72), "fill_e": 0.35,
				},
				"dust": Color(0.4, 0.9, 1.0),
			}
