class_name GridWorld
extends Node2D

# Tile grid: the single source of truth for the world.
# Hybrid generation (GDD sec. 6): per-depth probability layers carved by noise
# for organic caves and ore veins, organic bedrock margins with funnels, plus
# injected pre-made chunks (rooms). Also draws itself (colored rects).

const CELL := 32          # pixels per cell (1 cell = 2m in the lore -> 16 px/m)
const W := 48             # width in cells (GDD target 40-60)
const H := 220            # depth in cells
const GROUND := 6         # first solid row (rows above are sky)
const FUNNELS := [60, 120, 180]   # depths where the map necks down to a gate (boss rooms)

# --- funnel walls (unbreakable) --------------------------------------------
# The map funnels with unbreakable DIRT so the player can't run to the map edges
# early. Pickaxe-not-shovel framing: dirt/grass can't be mined, only STONE can.
# The breakable interior channel widens from the 2-wide entry hole down to nearly
# the full map width, then necks back to a gate at each FUNNELS depth.
const EDGE := 2                  # permanent bedrock border (cols per side)
const WALL_MAX := (W >> 1) - EDGE   # widest the interior half-channel ever gets (22)
const INTRO_ROWS := 30           # rows over which the top hole widens to WALL_MAX
const GATE_HALF := 1             # interior half-width at a funnel throat (~2 wide)
const FUNNEL_RAMP := 8           # rows on each side of a FUNNELS row to neck down
const STALL_MAX := 3             # more than this many flat rows forces a wall step

enum Cell { AIR, DIRT, STONE, BEDROCK, COAL, COPPER, IRON, CRYSTAL, GRASS }

@export var world_seed := 1337

var cells: PackedByteArray = PackedByteArray()
var rng: RandomNumberGenerator
var _cave_noise: FastNoiseLite
var _ore_noise: FastNoiseLite
var _wl: PackedInt32Array = PackedInt32Array()   # interior left boundary col, per row
var _wr: PackedInt32Array = PackedInt32Array()   # interior right boundary col (exclusive), per row

var _colors := {
    Cell.GRASS: Color(0.30, 0.55, 0.24),
    Cell.DIRT: Color(0.45, 0.31, 0.18),
    Cell.STONE: Color(0.42, 0.43, 0.50),
    Cell.BEDROCK: Color(0.12, 0.12, 0.15),
    Cell.COAL: Color(0.18, 0.18, 0.20),
    Cell.COPPER: Color(0.72, 0.45, 0.28),
    Cell.IRON: Color(0.78, 0.72, 0.62),
    Cell.CRYSTAL: Color(0.45, 0.85, 0.95),
}

# Pre-made chunk (S=stone wall, .=air, k=crystal). Stone walls are diggable so
# the room is reachable; the bottom edge is left open to connect to caves.
const TREASURE_ROOM := [
    "SSSSSSS",
    "S.....S",
    "S.kkk.S",
    "S..k..S",
    "S.....S",
    "SS...SS",
]


func _ready() -> void:
    _generate()
    queue_redraw()


# --- public API -------------------------------------------------------------

func _idx(cx: int, cy: int) -> int:
    return cy * W + cx


func in_bounds(cx: int, cy: int) -> bool:
    return cx >= 0 and cx < W and cy >= 0 and cy < H


func get_cell(cx: int, cy: int) -> int:
    if not in_bounds(cx, cy):
        return Cell.BEDROCK            # out of bounds counts as a solid wall
    return cells[_idx(cx, cy)]


func set_cell(cx: int, cy: int, v: int) -> void:
    if in_bounds(cx, cy):
        cells[_idx(cx, cy)] = v
        queue_redraw()


func is_solid(cx: int, cy: int) -> bool:
    return get_cell(cx, cy) != Cell.AIR


func is_diggable(cx: int, cy: int) -> bool:
    # Only STONE and ore are breakable. GRASS and DIRT are the unbreakable funnel
    # (pickaxe can't dig packed earth); BEDROCK is the map border.
    var c := get_cell(cx, cy)
    return c == Cell.STONE or is_ore_cell(c)


static func is_ore_cell(v: int) -> bool:
    return v == Cell.COAL or v == Cell.COPPER or v == Cell.IRON or v == Cell.CRYSTAL


# Mine a cell. Returns the cell type that was removed, or -1 if nothing diggable.
func dig(cx: int, cy: int) -> int:
    if is_diggable(cx, cy):
        var mined := get_cell(cx, cy)
        set_cell(cx, cy, Cell.AIR)
        return mined
    return -1


func world_to_cell(p: Vector2) -> Vector2i:
    return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func cell_center(cx: int, cy: int) -> Vector2:
    return Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)


func point_solid(p: Vector2) -> bool:
    var c := world_to_cell(p)
    return is_solid(c.x, c.y)


func regenerate(new_seed: int) -> void:
    world_seed = new_seed
    _generate()
    queue_redraw()


# --- generation -------------------------------------------------------------

func _generate() -> void:
    cells.resize(W * H)
    rng = RandomNumberGenerator.new()
    rng.seed = world_seed
    _setup_noise()
    _compute_walls()

    for cy in range(H):
        for cx in range(W):
            cells[_idx(cx, cy)] = _gen_cell(cx, cy)

    _carve_start_shaft()
    _stamp_chunk(TREASURE_ROOM, int(W / 2) - 3, 100)
    _print_stats()


func _setup_noise() -> void:
    _cave_noise = FastNoiseLite.new()
    _cave_noise.seed = world_seed
    _cave_noise.frequency = 0.07
    _cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

    _ore_noise = FastNoiseLite.new()
    _ore_noise.seed = world_seed + 7
    _ore_noise.frequency = 0.12
    _ore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX


# Precompute the interior (breakable) channel boundaries per row. Each side is an
# independent random walk that drifts toward a depth-dependent target half-width
# (_wall_target) and is forced to move after STALL_MAX flat rows, so the dirt
# walls look organic and never sit as a long straight tube.
func _compute_walls() -> void:
    _wl.resize(H)
    _wr.resize(H)
    var cx := W >> 1
    var wrng := RandomNumberGenerator.new()
    wrng.seed = world_seed + 101
    var hl := 1
    var hr := 1
    var sl := 0
    var sr := 0
    for cy in range(H):
        if cy <= GROUND + 2:
            hl = 1; hr = 1; sl = 0; sr = 0          # hold the 2-wide hole through the dirt lip
            _wl[cy] = cx - 1
            _wr[cy] = cx + 1
            continue
        var t := _wall_target(cy)
        var rl := _walk_step(hl, t, wrng, sl)
        hl = rl.x; sl = rl.y
        var rr := _walk_step(hr, t, wrng, sr)
        hr = rr.x; sr = rr.y
        _wl[cy] = cx - hl
        _wr[cy] = cx + hr


# Target interior half-width at a row: ramps up from the entry hole over
# INTRO_ROWS to WALL_MAX, then necks down to GATE_HALF around each FUNNELS depth.
func _wall_target(cy: int) -> int:
    var d := cy - GROUND
    if d < 0:
        return WALL_MAX
    var base := int(round(lerpf(1.0, float(WALL_MAX), clampf(float(d) / float(INTRO_ROWS), 0.0, 1.0))))
    for fy in FUNNELS:
        var dist := absi(cy - fy)
        if dist <= FUNNEL_RAMP:
            var gate := int(round(lerpf(float(GATE_HALF), float(WALL_MAX), float(dist) / float(FUNNEL_RAMP))))
            base = mini(base, gate)
    return maxi(1, base)


# One random-walk step of a wall toward target t. Returns (new_half_width, stall).
# Mostly drifts toward t with occasional dips for jagged edges; after STALL_MAX
# unchanged rows it is forced to step. Clamped to [1, t] so it hugs the envelope:
# the funnel necks reliably and the intro never overshoots.
func _walk_step(h: int, t: int, r: RandomNumberGenerator, stall: int) -> Vector2i:
    var dir := signi(t - h)
    var s := 0
    var rv := r.randf()
    if dir != 0:
        if rv < 0.7: s = dir
        elif rv < 0.9: s = 0
        else: s = -dir
    else:
        s = (1 if rv < 0.33 else (-1 if rv < 0.66 else 0))
    if s == 0:
        stall += 1
    else:
        stall = 0
    if stall >= STALL_MAX:                            # broke a flat run: force a step
        s = dir if dir != 0 else (1 if h < t else -1)
        stall = 0
    return Vector2i(clampi(h + s, 1, t), stall)


func _gen_cell(cx: int, cy: int) -> int:
    if cy < GROUND:
        return Cell.AIR
    if cx < EDGE or cx >= W - EDGE or cy == H - 1:
        return Cell.BEDROCK                          # permanent outer border
    var cxc := W >> 1
    if cy == GROUND:
        if cx == cxc - 1 or cx == cxc:
            return Cell.AIR                          # the 2-wide entry hole
        return Cell.GRASS                            # unbreakable grass cap
    if cy <= GROUND + 2:                             # 2 solid dirt layers under the cap
        if cx == cxc - 1 or cx == cxc:
            return Cell.AIR                          # ...except the 2-wide entry hole
        return Cell.DIRT
    if cx < _wl[cy] or cx >= _wr[cy]:
        return Cell.DIRT                             # unbreakable funnel wall
    # interior (breakable) channel: organic caves, ore veins, else stone
    if _cave_noise.get_noise_2d(cx, cy) > 0.55:
        return Cell.AIR
    var ore := _roll_ore(cx, cy)
    if ore != -1:
        return ore
    return Cell.STONE


# Ore only inside vein regions (high ore-noise), with depth-gated types.
func _roll_ore(cx: int, cy: int) -> int:
    if _ore_noise.get_noise_2d(cx, cy) < 0.45:
        return -1
    var r := rng.randf()
    if cy < 30:
        return Cell.COAL if r < 0.6 else -1
    elif cy < 80:
        if r < 0.40: return Cell.COAL
        if r < 0.75: return Cell.COPPER
        return -1
    elif cy < 140:
        if r < 0.45: return Cell.COPPER
        if r < 0.80: return Cell.IRON
        return -1
    else:
        if r < 0.45: return Cell.IRON
        if r < 0.62: return Cell.CRYSTAL
        return -1


func _carve_start_shaft() -> void:
    var sx := W >> 1
    for cy in range(GROUND, GROUND + 5):             # shallow ~5-deep entry hole (2 wide)
        _force(sx - 1, cy, Cell.AIR)
        _force(sx, cy, Cell.AIR)


func _stamp_chunk(rows: Array, ox: int, oy: int) -> void:
    for r in range(rows.size()):
        var line: String = rows[r]
        for c in range(line.length()):
            var cell := _char_to_cell(line[c])
            if cell >= 0:
                _force(ox + c, oy + r, cell)


func _char_to_cell(ch: String) -> int:
    match ch:
        ".": return Cell.AIR
        "D": return Cell.DIRT
        "S": return Cell.STONE
        "B": return Cell.BEDROCK
        "c": return Cell.COAL
        "u": return Cell.COPPER
        "i": return Cell.IRON
        "k": return Cell.CRYSTAL
        _: return -1                                 # leave whatever was generated


func _force(cx: int, cy: int, v: int) -> void:
    if in_bounds(cx, cy):
        cells[_idx(cx, cy)] = v


func _print_stats() -> void:
    var counts := {}
    for v in cells:
        counts[v] = counts.get(v, 0) + 1
    print("[GridWorld] seed=%d  %dx%d  AIR=%d GRASS=%d DIRT=%d STONE=%d BEDROCK=%d  ore: COAL=%d COPPER=%d IRON=%d CRYSTAL=%d" % [
        world_seed, W, H,
        counts.get(Cell.AIR, 0), counts.get(Cell.GRASS, 0), counts.get(Cell.DIRT, 0), counts.get(Cell.STONE, 0), counts.get(Cell.BEDROCK, 0),
        counts.get(Cell.COAL, 0), counts.get(Cell.COPPER, 0), counts.get(Cell.IRON, 0), counts.get(Cell.CRYSTAL, 0)])
    print("  channel: top(row %d)=%d  open(row %d)=%d cells" % [
        GROUND + 3, _wr[GROUND + 3] - _wl[GROUND + 3],
        GROUND + INTRO_ROWS, _wr[GROUND + INTRO_ROWS] - _wl[GROUND + INTRO_ROWS]])
    for fy in FUNNELS:
        print("  funnel @row %d: interior channel = %d cells" % [fy, _wr[fy] - _wl[fy]])


func _draw() -> void:
    for cy in range(H):
        for cx in range(W):
            var c := cells[_idx(cx, cy)]
            if c == Cell.AIR:
                continue
            draw_rect(Rect2(cx * CELL, cy * CELL, CELL, CELL), _colors[c], true)
