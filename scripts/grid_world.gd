class_name GridWorld
extends Node2D

# Tile grid: the single source of truth for the world.
# Also draws itself (colored rects) so the prototype needs no art pipeline.

const CELL := 32          # pixels per cell (1 cell = 2m in the lore -> 16 px/m)
const W := 30             # width in cells (final game targets 40-60; smaller here to iterate)
const H := 120            # depth in cells
const GROUND := 6         # first solid row (rows above are sky)

enum Cell { AIR, DIRT, STONE, BEDROCK }

var cells: PackedByteArray = PackedByteArray()

var _colors := {
    Cell.DIRT: Color(0.55, 0.36, 0.20),
    Cell.STONE: Color(0.42, 0.43, 0.50),
    Cell.BEDROCK: Color(0.12, 0.12, 0.15),
}


func _ready() -> void:
    _generate()
    queue_redraw()


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
    return c == Cell.DIRT or c == Cell.STONE


func dig(cx: int, cy: int) -> bool:
    if is_diggable(cx, cy):
        set_cell(cx, cy, Cell.AIR)
        return true
    return false


func world_to_cell(p: Vector2) -> Vector2i:
    return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func cell_center(cx: int, cy: int) -> Vector2:
    return Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)


func point_solid(p: Vector2) -> bool:
    var c := world_to_cell(p)
    return is_solid(c.x, c.y)


func _gen_cell(cx: int, cy: int) -> int:
    if cx == 0 or cx == W - 1 or cy == H - 1:
        return Cell.BEDROCK
    if cy < GROUND:
        return Cell.AIR
    if cy < 40:
        return Cell.DIRT
    return Cell.STONE


func _generate() -> void:
    cells.resize(W * H)
    for cy in range(H):
        for cx in range(W):
            cells[_idx(cx, cy)] = _gen_cell(cx, cy)

    # Carve a starting layout that exercises the rope:
    # a 2-wide vertical shaft, then an L-branch to the right so the rope
    # has a convex corner to wrap around.
    var sx := int(W / 2)
    for cy in range(GROUND, 22):
        cells[_idx(sx, cy)] = Cell.AIR
        cells[_idx(sx + 1, cy)] = Cell.AIR
    for cx in range(sx + 1, sx + 9):
        cells[_idx(cx, 14)] = Cell.AIR


func _draw() -> void:
    for cy in range(H):
        for cx in range(W):
            var c := cells[_idx(cx, cy)]
            if c == Cell.AIR:
                continue
            draw_rect(Rect2(cx * CELL, cy * CELL, CELL, CELL), _colors[c], true)
