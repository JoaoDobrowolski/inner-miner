# Inner Miner — Design Document

Single source of truth for **lore** and the **implementation roadmap**. This is
*intent*, not contract: the lore is final-ish, the roadmap is honest about what's
done, what's next (detailed), and what's still fuzzy (deliberately vague — no fake
precision on distant work).

Written in English to match the README. Ask if you'd rather have it in pt-BR.

---

# Part 1 — Lore & World Bible

A slow-burn psychological horror wrapped in a cozy pixel-art mining loop. The
comfort is the bait; the depth is the dread.

## Premise

A small mining operation at the mouth of a vertical shaft. An **old man** runs the
winch at the surface; **you** descend on the rope to mine. The loop feels safe at
the top and increasingly oppressive the deeper you go.

## Pillars

1. **Cozy surface, hostile depth.** Warm and human at the top; claustrophobic,
   silent, wrong at the bottom. The contrast *is* the horror.
2. **The rope is a lifeline, not a tool.** Someone has to pull you up — a
   dependency that is mechanical (rope physics) *and* emotional (the old man).
3. **Power lives in the person, not the loot.** No epic gear. You get stronger;
   your equipment stays humble and breakable.

## Core narrative decisions

- **Finite depth, infinite mining.** The map has a bottom with a real narrative
  climax, but each run/prestige extends reachable depth and unlocks different ores.
  Target feeling: *"descend fast with accumulated power"* — needs depth + reset + a
  power curve, not literal infinity.
- **Reset is an earthquake.** Each prestige a quake buries the shaft; you lose
  money, consumables, and physical equipment. Clean in-world justification for a
  reset.
- **Progression stays on the character.** Stats with narrative reasons:
  claustrophobia resistance (trauma overcome), strength (labor), mining efficiency
  (technique), backpack capacity, manual climb speed.
- **The old man stays alive through the whole prestige loop.** The rope needs
  someone pulling — he doesn't die every run. Winch automation (idle layer) is an
  *upgrade*, not a forced replacement.
- **His death is a one-time ending.** Played once; you inherit the guardian's duty.
  After that the rope becomes 100% machine and the radio goes silent — mechanical
  degradation mirrors the loss.
- **Motivation is inherited duty, not compulsion.** "Compulsion to mine" was
  rejected (reads badly). The framing is a duty passed down.
- **No talking ghost.** It would cheapen the loss. Catharsis via *one-directional
  echoes*: a diary and tapes the old man left for the next guardian (also the
  delivery vehicle for infinite-mode lore), objects on the surface, the radio
  playing fragments. The sad ending is intentional.

## Open questions

- Map width at the start (~60 blocks to test in portrait).
- Pendulum feel in portrait — *(rope prototype exists; see roadmap)*.
- How tapes/diary deliver progressive lore without becoming a wall of text.
- Whether combat ever leaves the freezer (out of scope for now; map + mining first).

---

# Part 2 — Implementation Roadmap

Status legend: ✅ done · 🔨 next · 📋 planned · ❓ uncertain/needs design.

## Phase 0 — Risk prototype ✅

Validate the riskiest mechanic before anything else.

- ✅ Engine: Godot 4.x, GDScript, portrait 540×960, `gl_compatibility`.
- ✅ Tile grid (`grid_world.gd`) — source of truth + self-render.
- ✅ Custom tile-grid player physics (`player.gd`) — walk, jump, air-swing,
  per-axis collision, **unconditional depenetration** (never rests inside a solid).
- ✅ Digging — adjacent cells, never straight up.
- ✅ Rope (`rope.gd`) — taut polyline: corner wrap/unwrap (LOS), manual reel (J),
  length budget, panic rewind, teleport guard, `relax()` anti-embed.
- ✅ Claustrophobia / panic system — rises with depth/tight tunnels, falls near
  torches/surface, 100% → emergency rescue.
- ✅ Hybrid map generation — per-depth probability layers, noise caves & ore veins,
  organic bedrock margins, funnels (biome gates), injected chunks (rooms).

**Known rope caveat:** the taut-polyline is fragile in jagged geometry; it's been
patched repeatedly (budget clamp, teleport guard, depenetration). If fragility
keeps biting, the root-cause fix is a **Verlet/PBD rope** — deferred, not free
(length accounting + rewind get messier). Tracked, not scheduled.

## Phase 1 — Core economy loop 🔨 (IN PROGRESS)

The smallest loop that makes the game *a game*: mine → carry → sell → spend.

1. ✅ **Ore yields on dig.** `grid_world.dig()` returns the mined cell type;
   `GridWorld.is_ore_cell()` filters ore (coal/copper/iron/crystal). Dirt/stone
   yield nothing.
2. ✅ **Backpack** (`backpack.gd`, RefCounted) with flat capacity (20) and per-ore
   sell values. Ore in a **full** backpack stays in the wall (no waste); dirt/stone
   stay diggable. HUD shows `BAG count/cap  value $`.
3. 🔨 **Sell at surface.** Returning to the surface (or a sell zone) converts the
   backpack to currency. HUD shows wallet.
4. 📋 **Rescue penalty becomes real.** Emergency rescue (panic 100%) costs you —
   drop part/all of the backpack. This is what makes claustrophobia *matter*.

Deliverable: a player can descend, mine ore, risk the panic threshold, surface,
sell, and see a wallet grow. No upgrades yet.

## Phase 2 — Character progression 📋

- Surface upgrade screen; spend currency on stats: claustrophobia resistance,
  strength (dig speed), mining efficiency (yield), backpack capacity, manual climb
  speed, rope length.
- Each upgrade gated by cost curve; first pass at the power fantasy.

## Phase 3 — Idle / offline layer 📋

- The old man mines passively, scaled by deepest depth reached.
- Winch automation upgrade (auto-reel).
- Offline progress computed on app reopen.

## Phase 4 — Prestige (earthquake reset) 📋

- Depth milestone triggers the quake → reset money/consumables/equipment, keep
  character stats.
- Each prestige: deeper map, new ore tiers, escalating dread.

## Phase 5 — Narrative delivery 📋 / ❓

- Diary + tapes system delivering progressive lore (❓ pacing so it isn't a text
  wall).
- Radio fragments on the surface.
- The one-time ending: old man's death, guardian inheritance, rope→machine, radio
  goes silent.

## Phase 6 — Mobile & polish 📋

- Touch controls: double-tap to descend, drag to swing (swipe-up removed per
  design). Re-map the PC prototype inputs.
- Portrait UI/HUD redesign for thumbs.
- Art pass (pixel art), audio, game feel / juice.

## Phase 7 — Release prep 📋

- Save system, balancing pass, store assets (iOS/Android), build pipeline.

## Cross-cutting / deferred ❓

- **Verlet/PBD rope** if the polyline stays fragile (see Phase 0 caveat).
- **Multiplayer** — kept architecturally possible (rope is pure logic, no
  rendering), not a near-term goal.
- **Combat** — frozen until the mining loop proves fun.
