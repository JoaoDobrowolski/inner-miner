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
const FUNNELS := [60, 120, 180]   # depths where the map funnels to ~3 wide (biome gates)

enum Cell { AIR, DIRT, STONE, BEDROCK, COAL, COPPER, IRON, CRYSTAL }

@export var world_seed := 1337

var cells: PackedByteArray = PackedByteArray()
var rng: RandomNumberGenerator
var _cave_noise: FastNoiseLite
var _ore_noise: FastNoiseLite
var _margin_noise: FastNoiseLite

var _colors := {
    Cell.DIRT: Color(0.55, 0.36, 0.20),
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
    var c := get_cell(cx, cy)
    return c != Cell.AIR and c != Cell.BEDROCK


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

    for cy in range(H):
        var m := _margins(cy)
        for cx in range(W):
            cells[_idx(cx, cy)] = _gen_cell(cx, cy, m.x, m.y)

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

    _margin_noise = FastNoiseLite.new()
    _margin_noise.seed = world_seed + 19
    _margin_noise.frequency = 0.08
    _margin_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX


func _in_funnel(cy: int) -> bool:
    for fy in FUNNELS:
        if absi(cy - fy) <= 2:
            return true
    return false


# Returns bedrock margins (left, right) for a row. Organic elsewhere, forced to
# a centered 3-wide diggable gap inside funnel bands.
func _margins(cy: int) -> Vector2i:
    if _in_funnel(cy):
        var c0 := int(W / 2) - 1
        return Vector2i(c0, W - (c0 + 3))
    var lw := 2 + int(round(2.0 * _margin_noise.get_noise_2d(0.0, cy)))
    var rw := 2 + int(round(2.0 * _margin_noise.get_noise_2d(100.0, cy)))
    return Vector2i(clampi(lw, 1, int(W / 2) - 3), clampi(rw, 1, int(W / 2) - 3))


func _gen_cell(cx: int, cy: int, lm: int, rm: int) -> int:
    if cy == H - 1:
        return Cell.BEDROCK
    if cx < lm or cx >= W - rm:
        return Cell.BEDROCK
    if cy < GROUND:
        return Cell.AIR
    if cy > GROUND + 4 and _cave_noise.get_noise_2d(cx, cy) > 0.55:
        return Cell.AIR                              # organic cavern
    var ore := _roll_ore(cx, cy)
    if ore != -1:
        return ore
    return Cell.DIRT if cy < 30 else Cell.STONE


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
    var sx := int(W / 2)
    for cy in range(GROUND, GROUND + 16):
        _force(sx, cy, Cell.AIR)
        _force(sx + 1, cy, Cell.AIR)
    for cx in range(sx + 1, sx + 9):                 # short L-branch for a rope corner
        _force(cx, GROUND + 8, Cell.AIR)


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
    print("[GridWorld] seed=%d  %dx%d  AIR=%d DIRT=%d STONE=%d BEDROCK=%d  ore: COAL=%d COPPER=%d IRON=%d CRYSTAL=%d" % [
        world_seed, W, H,
        counts.get(Cell.AIR, 0), counts.get(Cell.DIRT, 0), counts.get(Cell.STONE, 0), counts.get(Cell.BEDROCK, 0),
        counts.get(Cell.COAL, 0), counts.get(Cell.COPPER, 0), counts.get(Cell.IRON, 0), counts.get(Cell.CRYSTAL, 0)])
    for fy in FUNNELS:
        var free := 0
        for cx in range(W):
            if get_cell(cx, fy) != Cell.BEDROCK:
                free += 1
        print("  funnel @row %d: free width = %d cells" % [fy, free])


func _draw() -> void:
    for cy in range(H):
        for cx in range(W):
            var c := cells[_idx(cx, cy)]
            if c == Cell.AIR:
                continue
            draw_rect(Rect2(cx * CELL, cy * CELL, CELL, CELL), _colors[c], true)
