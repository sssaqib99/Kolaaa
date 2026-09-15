# HYPERDRIFT — Godot 4.7.2 project

This repository contains **a Godot game, not a website**. There is deliberately no
landing page: the web entry point renders nothing.

## Where the game is

```
hyperdrift/project.godot
```

Open **Godot 4.7.2+** → `Import` → pick `hyperdrift/project.godot` → **Import & Edit** → press **F5**.

Full documentation, controls and architecture notes: [`hyperdrift/README.md`](hyperdrift/README.md).

## What's in the game

* 3D neon endless runner — strafe, jump, duck, boost, graze and chain combos.
* **Four maps**, each with its own sky, architecture, hazard palette and a
  procedurally composed theme song (no audio files anywhere).
* **Obstacles follow the music.** Hazards are scheduled on a beat clock — exact
  for the built-in themes, live-tracked for your own tracks — and passing gates on
  the beat scores XP and chain.
* **Play your own music** (`F2`): native file/folder pickers for MP3 / OGG / WAV,
  playlist, shuffle, and a one-click toggle between game themes and device music.
* **Music / SFX / Engine** volume sliders.
* **SKYBRIDGE**: a cinematic arcing, banking bridge with a beat-locked light helix
  and a swirling lane of XP crystals and rings.
* **Pilot XP** with persistent levels and perk unlocks.
* Nocturne Boulevard: a real wet Art Deco noir street, full moon, tall pastel
  skyline, background traffic, unique cab/shadow/obelisk hazards, and jazz score.
* Thirteen hazard types — lasers, pistons, rotors, hunters, pendulums, Noir Cabs
  and more.
* Everything is generated in GDScript at runtime. No plugins, no binary assets.
