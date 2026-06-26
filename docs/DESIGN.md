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
- ✅ Rope (`rope.gd`) — taut polyline: corner wrap (LOS) / unwrap (LOS +
  winding-sign gate), manual reel (J), length budget, panic rewind, teleport
  guard, `relax()` anti-embed.
- ✅ Claustrophobia / panic system — rises with depth/tight tunnels, falls near
  torches/surface, 100% → emergency rescue.
- ✅ Hybrid map generation — per-depth probability layers, noise caves & ore veins,
  organic bedrock margins, funnels (biome gates), injected chunks (rooms).

**Known rope caveat:** the taut-polyline needed repeated patching in jagged
geometry (budget clamp, teleport guard, depenetration), and its worst structural
failure — the corner-clip / unpivot shortcut (BUG-01) — is now fixed via the
winding-sign release gate. A **Verlet/PBD rope** remains an optional fallback if
new fragility appears, but it is no longer the only root-cause path — deferred,
not scheduled.

## Phase 1 — Core economy loop ✅ (pending live feel test)

The smallest loop that makes the game *a game*: mine → carry → sell → spend.

1. ✅ **Ore yields on dig.** `grid_world.dig()` returns the mined cell type;
   `GridWorld.is_ore_cell()` filters ore (coal/copper/iron/crystal). Dirt/stone
   yield nothing.
2. ✅ **Backpack** (`backpack.gd`, RefCounted) with flat capacity (20) and per-ore
   sell values. Ore in a **full** backpack stays in the wall (no waste); dirt/stone
   stay diggable. HUD shows `BAG count/cap  value $`.
3. ✅ **Sell at surface.** Auto-sells the whole backpack on reaching layer 0
   (Motherload-style, no shop/chest): `wallet` grows, HUD shows it. Guarded so it
   never fires mid-rescue. (`main._sell_on_surface()` / `_do_sell()`.)
4. ✅ **Rescue penalty (first pass).** Emergency rescue (panic 100%) spills HALF
   the load (`Backpack.drop_half()`) before the surface sells the rest — panicking
   costs you, so claustrophobia *matters*.

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

- **Verlet/PBD rope** — optional fallback; the polyline's worst bug (BUG-01) is
  fixed, so this is no longer the only root-cause path (see Phase 0 caveat).
- **Multiplayer** — kept architecturally possible (rope is pure logic, no
  rendering), not a near-term goal.
- **Combat** — frozen until the mining loop proves fun.

---

# Part 3 — Known Issues

## The rope has two backends — dev toggle "Verlet rope (A/B)"

- **Mode A — taut polyline** (`scripts/rope.gd`): the default. Anchor → convex
  tile-corner pivots → player; wraps by line-of-sight, unwraps when LOS clears
  AND the corner's winding sign reverses (BUG-01 fix).
- **Mode B — Verlet chain** (`scripts/rope_verlet.gd`): an in-progress
  alternative (its original motivation, BUG-01, is now fixed in Mode A). A
  36-point mass chain that drapes over the tiles (point + segment collision) with
  no corner/LOS logic. Toggle live from the dev menu. The player moves under its
  own physics; the rope is a leash that only acts at full extension (decoupled,
  so it doesn't drag — an earlier "viscous" version did).

The full blow-by-blow of every rope attempt lives in the project memory
(`inner-miner-rope-status`).

## BUG-01 "Rope corner-clip / unpivot shortcut" (Mode A) — FIXED (2026-06-26)

**Symptom:** with the rope wrapped on a corner, the *last* pivot suddenly drops
and the rope takes an illegal shortcut (penultimate→player), appearing to "cut
through" a block. NOT cosmetic — the pivot genuinely unwraps: the last pivot
unpivots and the penultimate becomes the last. Triggered only when the player has
a clear sightline to the previous attach point while still on the wrapped side of
the corner (the user's red zone; the green zones are exactly where LOS is blocked).

**Root cause:** `_update_wrap()` released the last pivot the instant
`_los_blocked(prev, player)` read clear — on line-of-sight *alone*. A clear
sightline is necessary but NOT sufficient: it can open while the player is still
on the SAME side of the corner the rope is wound around. The straight prev→player
line then routes through a *different gap* than the wrapped path — a different
homotopy class (rope goes UNDER the block, the straight line goes OVER it).
Dropping the pivot there teleports the rope across the block. Each pivot already
stored a winding `sign` captured at wrap time, but the release path never
consulted it.

**Fix:** the last pivot is released only when LOS is clear AND the winding `sign`
has actually reversed (player swung *past* the corner). Interior pivots keep the
LOS-only rule — their sign can't reverse on its own, and the dig case legitimately
opens a clear prev→next line that should drop a now-useless inner corner. The
wrap-time sign is hardened to never be zero. See the `Rope._update_wrap()` release
loop.

**Validation (headless, `_rope_unwrap_diag.gd`, the user's real geometry — anchor
(784,32), block A at cell (22,3), A-SE pivot):** of the swept player positions
with clear LOS to the anchor, 8006 were still wound the same way (rope genuinely
wrapped) — the old rule wrongly dropped all 8006; the fix drops 0. The 5032
reversed-winding positions (legit unwrap) still release, unchanged. Confirmed in
live play.

**Correction to the record:** the earlier "0.5px LOS-sampling graze / cosmetic
2px draw / structural polyline limit / only solvable by Mode B" diagnosis was
**wrong**. The failure was a real structural unwrap, fixable in Mode A. The 0.5px
LOS sampling is kept (it still catches thin grazes) but was never the cause.

## Mode B (Verlet) — issue status (2026-06-26, headless-validated)

- **B-02 — reel (J) path: FIXED.** The leash + length used a straight line to the
  winch; now they are geodesic (length along the draped chain; the leash clamps to
  the budget remaining past the *last contact* `points[n-2]`, in the rope's local
  direction). The reel follows the rope to the last contact instead of pulling
  straight through geometry. Player stays decoupled (free-fall still hits MAX_FALL —
  no viscosity). *Pending live feel test.*
- **B-03 — flexed at the limit: FIXED (visual only).** `RopeVerlet.draw_points()`
  blends the drawn chain toward the straight anchor→player chord by a tautness factor
  (0→1 as it nears full extension), but only when that chord is clear of solids — a
  real wrap is never flattened. Drawn sag at the limit: 43.8px → 0.1px. Physics
  untouched.
- **B-01 — wrap unwinds over blocks: OPEN, re-diagnosed.** It is **not** the length
  budget. Measured: even with a huge slack budget the Verlet chain cuts ~65px through
  a 2-wide wall — the per-point collision (`_push_out`) shoves each point to its
  *nearest* air edge (sideways), so it cannot route the chain *over the top* of a
  tall obstacle. Shallow 1-cell bumps wrap cleanly. The real fix is a collision-
  routing change (over-the-top bias / corner-anchor hybrid / sub-stepping) — invasive
  and uncertain; deferred pending a decision.
