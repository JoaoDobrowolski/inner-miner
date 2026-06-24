class_name PanicSystem
extends RefCounted

# Claustrophobia / panic, 0..100. Replaces fuel/oxygen as the core pressure.
# Rises with time, depth and tight (1-wide) spaces; falls near torches or on
# the surface. At 100 the game triggers an emergency rescue (handled by Main).

var value := 0.0

var base_rate := 1.5          # %/s just from being underground
var depth_rate := 0.10        # extra %/s per meter of depth
var tight_rate := 8.0         # extra %/s in a 1-wide tunnel
var recover_rate := 28.0      # %/s inside a safe zone (torch / surface)
var torch_radius := 110.0


func update(delta: float, player_pos: Vector2, world: GridWorld, torches: Array) -> void:
    if _is_safe(player_pos, world, torches):
        value = max(value - recover_rate * delta, 0.0)
        return
    var rate := base_rate + depth_rate * _depth_meters(player_pos)
    if _is_tight(player_pos, world):
        rate += tight_rate
    value = min(value + rate * delta, 100.0)


func _depth_meters(player_pos: Vector2) -> float:
    var rows_below := player_pos.y / GridWorld.CELL - GridWorld.GROUND
    return max(0.0, rows_below * 2.0)              # 1 cell = 2 m


func _is_safe(player_pos: Vector2, _world: GridWorld, torches: Array) -> bool:
    if player_pos.y < GridWorld.GROUND * GridWorld.CELL:
        return true                                 # on / above the surface
    for t in torches:
        if player_pos.distance_to(t) <= torch_radius:
            return true
    return false


# A 1-wide vertical squeeze: solid on both sides of the player's cell.
func _is_tight(player_pos: Vector2, world: GridWorld) -> bool:
    var pc := world.world_to_cell(player_pos)
    return world.is_solid(pc.x - 1, pc.y) and world.is_solid(pc.x + 1, pc.y)
