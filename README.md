# HYPERDRIFT — Hover Hangar Build

A Godot 4.7.2 game (3D neon endless runner) **plus** a web-based live ship-select
preview. This checkout merges the **absolute** project with the **PHANTOM Art
Deco heavy cruiser + its effects** and adds a **live preview selection UI**
(the HANGAR) in both the game and the browser.

## What's where

```
hyperdrift/project.godot   The game — open in Godot 4.7.2+, press F5
src/                       Web hangar preview (React + Three.js, mirrors the game)
Kolaaa-*.zip               Source bundle (absolute snapshot + project)
alochaax).zip              Source bundle (Phantom cruiser + music effects)
absolute).zip              (inside the bundle above) the absolute project snapshot
```

## Run the game

1. Open **Godot 4.7.2** (or newer).
2. `Import` → select `hyperdrift/project.godot` → **Import & Edit**.
3. Press **F5**.

Full game docs, controls and architecture: [`hyperdrift/README.md`](hyperdrift/README.md).

## Run the web hangar preview

```sh
npm install
npm run dev      # → http://localhost:5173
```

A live Three.js hangar: see both ships on a rotating turntable with engine
glow, music flares and a simulated 124 BPM reactivity readout — geometry,
sizes, positions and palette mirrored 1:1 from
`hyperdrift/scripts/ship_factory.gd`. Drag to orbit, scroll to zoom,
`←`/`→` to browse, `ENTER` to select (persisted to localStorage).

## What was merged

Base is the newest absolute code (including the off-road building fix), plus
from the Phantom drop:

* **PHANTOM Art Deco heavy cruiser** (`player.gd`): wedge hull, swept
  chrome-edged wings, violet engine pods, exhaust spine.
* **Ship effects**: six texture-free music lens flares
  (`shaders/music_flare.gdshader`), bass/drone/melody/percussion hull
  reactivity, engine-glow pulsing — all driven by Sound's six-band music
  director (`autoload/audio_director.gd`).
* World music-layer visuals (road/grid layer colors, gobo palettes), persistent
  `ship_id` (`save_manager.gd`), `game.set_ship()` (`main.gd`).

## New in this build: the HANGAR (live preview selection UI)

* `hyperdrift/scripts/ship_factory.gd` — **shared** Vector/Phantom geometry,
  music flares and ship metadata. The game ship and the preview build from the
  same code, so WYSIWYG.
* `hyperdrift/scripts/ship_preview.gd` — live 3D turntable preview
  (own-world SubViewport): neon stage, engine glow, music flares, thruster,
  per-ship lighting, switch spin-pulse. Animates from real music when a track
  plays, idle wave otherwise.
* **SETTINGS → HANGAR tab** (`hud.gd`) — docked live preview; selection
  applies instantly behind the panel.
* **Title → HANGAR** (or `H`) — full-screen hangar overlay reusing the same
  live preview; `←`/`→` browse, `ENTER` selects.
* Title quick-select arrows + `GAME` tab current-ship row with `OPEN HANGAR →`.
* Both ships keep identical collision/handling — selection is pure style.
