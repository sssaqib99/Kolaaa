# HYPERDRIFT

A polished 3D neon endless runner built **entirely inside Godot 4** with GDScript.
No external assets: every mesh, material, shader, particle and *every single sound*
(all four theme songs included) is generated procedurally at runtime — and the
level itself is generated **on the beat of whatever music is playing**, including
your own MP3 / OGG / WAV files.

## Run it

1. Open **Godot 4.7.2** (or newer).
2. `Import` → select `hyperdrift/project.godot` → **Import & Edit**.
3. Press **F5** (Play).

> Project baseline is Godot `4.7.2` with the compatible Forward+ APIs. The project
> includes a unit-tested beat tracker and automated play-through coverage for
> bridges, hazard types, level-ups, pause/unpause and device music.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Strafe | `A` / `D` or `←` / `→` | Left stick / D-pad |
| Jump | `Space` / `W` / `↑` | `A` |
| Duck (and air-dive) | `S` / `↓` / `Ctrl` | `B` |
| Adrenaline | `E` / `Q` | `LB` / `X` |
| Pause | `Esc` / `P` | `Start` |
| Restart | `R` | `Y` |
| Change map | `←` / `→` (menu or pause) | D-pad |
| **Music & Audio panel** | `F2` (any screen) | `Back` |
| Previous / next track | `[` / `]` (any screen) | – |
| Mute | `M` | – |
| Quality (Performance / Balanced / Ultra) | `F1` | – |
| Fullscreen | `F11` | – |

## Four maps, four theme songs

Cycle maps with `←` / `→` on the title or pause screen. Each map has its own
sky, fog, lighting, road palette, hazard palette, roadside architecture, bridge
colours **and its own procedurally composed soundtrack**:

| # | Map | Look | Theme |
| --- | --- | --- | --- |
| 0 | **NEON GRID** | Midnight cyberpunk city, dense window towers | *Voltage Highway* — 124 BPM four-on-the-floor synthwave |
| 1 | **EMBER CANYON** | Sunset desert, mesa & refinery walls | *Dune Protocol* — 100 BPM half-time desert groove, Phrygian-dominant vamp |
| 2 | **AURORA RIDGE** | Glacier night under drifting aurora curtains, crystal spires | *Polar Circuit* — 138 BPM uplifting trance: off-beat bass, supersaw 16ths, open hats |
| 3 | **NOCTURNE BOULEVARD** | Original Art Deco noir city: crimson dusk, full moon, wet boulevard, pastel towers and violet midnight | *Midnight In Violet* — 92 BPM noir-jazz with brushes, upright-style bass, vibraphone stabs and muted horns |

NOCTURNE BOULEVARD is deliberately not another neon map. It has a real wet
asphalt boulevard with lane markings, a full moon, tall varied Art Deco towers
with tiered crowns and spires, safe background sedans with headlights, and a
soundtrack-driven grade from smoky crimson dusk to blue-violet midnight. Its
unique beat-authored hazards are **Noir Obelisks**, **Shadow Curtains** and
low **Noir Cabs** which sweep a single lane while leaving broad escape routes.

## Sky structures — arc, corkscrew, loop-de-loop, spiral

Roughly every kilometre the highway hands the ship over to a **rail structure**.
The ship rides a smooth parametric frame ("magnetic rails"): strafing slides
along the deck, jumping goes along the deck's up axis, gravity always pulls back
onto the deck — so on the loop you really fly upside down.

| Structure | Shape |
| --- | --- |
| **SKYBRIDGE** | 300 m banking arc |
| **CORKSCREW** | a full 360° barrel roll around the travel axis |
| **LOOP-DE-LOOP** | a lateral-offset vertical hoop with grounded road-to-road entry and exit |
| **SPIRAL HIGHWAY** | a two-turn banked spiral climbing 42 m around a tower and back down |

Every structure is wrapped in a double helix of light that spins with the beat,
lined with XP crystals and XP rings, and hazard-free. While riding one, the
**cinematic camera cuts to a new shot on every bar** (chase / low side / front
quarter / high wide), eases between shots and rolls with the deck. Letterbox
bars slide in. Both are switchable in SETTINGS > EFFECTS.

## The music drives the ship

* **Speed follows the music** — a live loudness / tempo analysis on the Music
  bus scales travel speed between ×0.68 (quiet, slowing) and ×1.16 (loud,
  faster tempo). Breakdowns ease the ship off; the HUD shows `MUSIC ×0.87`.
* **THE DROP** — when the energy jumps well above the rolling average after a
  quiet stretch, the game detects a drop: white-out, hit-stop, camera kick,
  floor shockwave, gobo strobe and **auto-boost for the length of the drop**
  (no energy cost). Every 8 bars the world flashes in the map colour.
* **Concert moving-head gobo lights** — thicker rooftop fixtures fire fans of five beams
  (one MultiMesh for all of them). Programs: FAN, SWEEP, NOD, CHASE, CROSS,
  all clocked by the beat and **accelerating on spikes**; every fixture strobes
  during a drop. Toggle + brightness in SETTINGS > EFFECTS.

## RHYTHM mode

Pick **MODE: RHYTHM** on the title screen. No hazards, no shields, no death —
**beat pads** are laid on the beat grid straight from the live music structure
and you score by flying through them on time (PERFECT / GOOD / EARLY / LATE).
Pattern variants are chosen per phrase from what the music is doing:

| Music | Pads |
| --- | --- |
| quiet / breakdown | sparse single pads every 2 beats |
| normal | one pad per beat, lane random-walk |
| busy hats | 8th-note double pads |
| heavy bass | wide yellow BAR pads on the downbeat |
| drop | triplet fans across all lanes + bars |

Accuracy, streak and pads hit are on the HUD; end the run from the pause menu.

## Adrenaline

Classic mode has an XP-charged **ADRENALINE** meter. XP earned during the run
fills it; pilot level and current run XP increase the eventual duration. Press
`E` when ready to activate, or press `E` again to cancel early. While active the
ship is invincible, receives free auto-boost, and proactively smashes hazards in
its flight corridor. Each smash triggers a no-time-slow destruction burst:
chunky colored debris, a shock ring, kick/snare impact, camera punch and rumble.

## Level Design

The road is 9% wider than the previous build. Wall openings and hurdle notches
now drift between beat gates by a hard cap derived from the ship's actual
strafe speed, and the safe corridor grows at high speed. Structure placement
reserves its entire corridor before spawning, recycles hazards already inside it,
and removes buildings, towers and posts from the path with a 3D clearance test.

## SETTINGS (one compact panel, all clickable)

`⚙ SETTINGS` on the title / pause screen (or `F2`). 820 × 540 px, four tabs:

* **GAME** — mode, map, ship speed follows music, auto-boost on the drop,
  obstacles follow the beat, graphics quality, fullscreen, reset progress.
* **EFFECTS** — glow/bloom strength (default lowered to 0.65), camera shake,
  chromatic aberration, speed blur, gobo lights + beam brightness, beat flash,
  scanlines, cinematic camera, letterbox, ambient dust.
* **AUDIO** — music / SFX / engine volume, live beat-clock + energy + tempo readout.
* **MUSIC** — game themes vs your device music, add files / folder / scan library,
  playlist, shuffle, transport, progress.

## Pilot XP & unlocks

XP is earned from orbs, grazes, on-beat gates, checkpoints, distance and the
sky-bridge. It persists between runs and levels you up as a **PILOT**:

| Level | Perk |
| --- | --- |
| 3 | Boost regen +25% |
| 5 | Combo window +0.6 s |
| 8 | Start every run with 4 shields |
| 12 | Magnet lasts 14 s |
| 16 | Overdrive lasts 9 s |
| 20 | All score ×1.1 |

Levelling up mid-run also restores a shield and refills boost.

## Obstacles that follow the music

The hazard generator runs on a **beat clock**. Every gate is placed where the ship
will be when a future beat lands (4.6 s look-ahead), a subtle ±6 % speed
rubber-band keeps arrivals honest, and passing a gate within ±125 ms of a beat
scores **ON BEAT** (+5 XP) or within ±55 ms **PERFECT** (+10 XP), building the chain.
Eight in a row = a BEAT STREAK boost refill.

* **Built-in themes** — the clock is exact (known BPM + playback position).
* **Your own music** — a live tracker on the Music bus (spectral flux → 8 s
  autocorrelation → comb-filter phase) locks within ~4–5 s and shows
  `SYNC 128 BPM` in the HUD. Unit-tested to ±0.5 BPM / ±18 ms on synthetic
  click tracks.
* Turn it off any time with **OBSTACLES FOLLOW THE BEAT** in the audio panel.

Ten hazard types, colour-coded by required action (pink/red = dodge,
yellow = jump, cyan = duck, orange = it moves, violet = timing):

| Hazard | Behaviour |
| --- | --- |
| Block / Low / Hang | Dodge / jump / duck |
| Mover | Slides sideways |
| Spinner | Rotating bar |
| **Laser gate** | Beam blinks off for the half-beat around every beat — or jump/duck it |
| **Piston** | Slams to the deck on the beat, hovers high in between |
| **Rotor** | Quarter-turn per beat around the travel axis |
| **Hunter** | Drone that tracks your lane until 24 m out — juke it |
| **Pendulum** | Wrecking ball: at the extremes on beats, crossing the centre on half-beats |

## Music & Audio panel (F2)

* **GAME THEMES / MY DEVICE MUSIC** — one toggle, also right on the title screen.
* **+ ADD MUSIC FILES…** — native OS file picker (multi-select), **+ ADD FOLDER…**
  (scans two levels deep), **SCAN MUSIC LIBRARY** (your OS music folder in one click).
* Track list with the current track highlighted, transport, **shuffle**, progress bar.
* **MUSIC / SFX / ENGINE** volume sliders on dedicated audio buses, saved to your profile.
* Beat-clock status readout.
* Library and source persist between sessions. `.mp3`, `.ogg`, `.wav` supported
  through the 4.4+ native loaders (with a hand-rolled fallback decoder).

## How to get a high score

* **Orbs** build your chain. Every 5 chain steps = +1 score multiplier (max **x10**).
* **Graze** hazards for bonus points, chain, XP and energy.
* **Boost** (`Shift`) burns energy for +38% speed and +40% score rate.
* **Checkpoints** every 500 m refill energy and pay a multiplier-scaled bonus.
* **Power-ups**: `SHIELD`, `MAGNET`, `OVERDRIVE` (invincible free boost).
* Ride the beat: on-beat gates are the fastest way to grow the chain.

## Project layout

```
project.godot                Config, layers, autoloads, renderer settings
scenes/main.tscn             Root scene: environment, lights, track, player, camera, HUD, post-FX
scenes/player.tscn           Player Area3D + hitbox + graze zone
scripts/main.gd              Game director: states, scoring, XP, beat scoring, biomes
scripts/biomes.gd            Map + theme data (visual params for every system)
scripts/track.gd             Beat-clock hazard scheduler, patterns, pooling, decor, bridge trigger
scripts/bridge.gd            Rail structures: arc / corkscrew / loop / spiral frames, beat helix
scripts/gobo_rig.gd          Concert moving-head gobo rig (5-beam fans, beat programs, drop strobe)
scripts/beat_tracker.gd      Live beat tracker (pure logic, unit-testable)
scripts/player.gd            Hover-jet: movement, jump/duck, deck following, procedural ship
scripts/obstacle.gd          10 pooled hazard types (5 beat-animated)
scripts/pickup.gd            Orbs, power-ups, XP crystals, XP rings
scripts/camera_rig.gd        Chase cam, trauma shake, beat punch, bridge cinematic, death orbit
scripts/hud.gd               Code-built UI: HUD, XP, beat indicator, letterbox, menus, audio panel
scripts/visuals.gd           Palette + material / particle factories
shaders/sky.gdshader         Synthwave sky + aurora curtains
shaders/grid_floor.gdshader  Infinite neon grid with beat pulse + shock ring
shaders/building.gdshader    City windows / mesa strata / glacier crystal facades
shaders/neon.gdshader        Hazard material with action-coded scrolling arrows
shaders/orb.gdshader         Additive collectible glow
shaders/post.gdshader        Chromatic aberration, speed warp, vignette, grain
autoload/save_manager.gd     Records, XP/levels/perks, settings, music library, InputMap
autoload/audio_director.gd   Synth engine (3 themes, drone, SFX), buses, jukebox, beat clock
```

Everything is text: `.gd`, `.gdshader`, `.tscn`, `.svg`. No binary assets, no plugins.
