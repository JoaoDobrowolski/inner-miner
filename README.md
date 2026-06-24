# Inner Miner — Prototype

Vertical slice in Godot 4 to validate the riskiest mechanic first: the **rope
physics** (corner-wrapping, pendulum, manual reel, panic rescue) on top of a
mineable tile grid. No art, no claustrophobia system, no combat — those come
after the rope feels good.

## Requirements

Godot 4.x (single binary, no install needed). Get it from
<https://godotengine.org/download> or on Linux:

```
flatpak install flathub org.godotengine.Godot
```

## Run

1. Open Godot, **Import** this folder (it has `project.godot`).
2. Press **F5** (Play). A portrait window opens.

## Controls (PC / fast iteration)

| Input | Action |
|-------|--------|
| `A` / `D` (or arrows) | Walk on ground · swing in the air |
| `Space` / `W` | Jump |
| Left click on adjacent tile | Dig (left / right / down — never up) |
| `J` (hold) | Reel up the rope (hover / pendulum) |
| `K` | Panic rescue (rewind along the exact path) |
| `R` | Reset position |
| `F1` | Debug view (grid + player AABB) |

## What this proves / how to read the HUD

- `out / max` = rope let out vs maximum. Descending **feeds** rope out to the max;
  hitting the max is the "tranco".
- `used` = real length consumed = wrapped segments + free segment. Walk a zig-zag
  and watch `used` grow without `out` changing — that is the rope wearing down.
- `pivots` = corners the rope is currently wrapped around. Go down the shaft, then
  right into the branch: a pivot should appear on the corner. Come back: it releases.
- `K` (rescue) rewinds the player along anchor→pivots→player in reverse, unwrapping
  corners on the way up.

## Architecture

- `scripts/grid_world.gd` — tile grid (source of truth) + self-render.
- `scripts/rope.gd` — taut-rope logic: pivot stack, wrap/unwrap, length, rewind. **Pure logic (RefCounted), no rendering** — kept separate so it stays testable and so a future networking layer has a clean seam.
- `scripts/player.gd` — custom tile-grid physics + dig + air swing.
- `scripts/main.gd` — wiring, camera, input, HUD, rope drawing.

## Known limitations (expected — to iterate on)

- Wrap/unwrap is greedy and LOS-based; **sharp multi-corner chains** may let the
  rope clip a wall. Single L-bends (the demo case) work.
- The taut clamp can push the player slightly into a wall on hard swings; collision
  recovers next frame.
- No claustrophobia, no offline/idle, no combat — out of scope for this slice.
- Not yet run end-to-end by the author of the scaffold; treat first launch as the
  first real test.
