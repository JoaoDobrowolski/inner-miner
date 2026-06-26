class_name Backpack
extends RefCounted

# Ore the player is carrying down in the shaft. Pure logic (RefCounted) so it
# stays testable and decoupled, like the rope. Capacity is a flat count for now;
# it becomes a character stat in the progression phase.

var capacity := 20
var items: Dictionary = {}          # Cell type (int) -> count (int)

# Base sell value per ore type (currency units). Tuned later in balancing.
var _value := {
    GridWorld.Cell.COAL: 1,
    GridWorld.Cell.COPPER: 3,
    GridWorld.Cell.IRON: 6,
    GridWorld.Cell.CRYSTAL: 25,
}


func count() -> int:
    var n := 0
    for k in items:
        n += items[k]
    return n


func is_full() -> bool:
    return count() >= capacity


func add(ore_type: int) -> bool:
    if is_full():
        return false
    items[ore_type] = items.get(ore_type, 0) + 1
    return true


func value() -> int:
    var v := 0
    for k in items:
        v += int(_value.get(k, 0)) * int(items[k])
    return v


# Emergency-rescue penalty: spill half the load (keep the floor of each stack so
# a single ore is fully lost). Returns the sell value dropped, for HUD feedback.
func drop_half() -> int:
    var lost := 0
    for k in items.keys():
        var keep: int = items[k] / 2          # integer floor
        lost += int(_value.get(k, 0)) * (items[k] - keep)
        if keep > 0:
            items[k] = keep
        else:
            items.erase(k)
    return lost


func clear_all() -> void:
    items.clear()
