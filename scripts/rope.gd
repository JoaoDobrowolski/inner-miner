class_name Rope
extends RefCounted

# Taut rope modeled as a polyline: anchor -> pivots... -> player.
# Pivots are convex tile corners the rope is currently wrapped around.
# This is NOT a mass-spring rope: it stays extended and wraps/unwraps on
# corners, which gives clean length accounting and a free rewind path.

var world: GridWorld
var anchor: Vector2
var max_length: float
var rope_out: float                 # rope currently let out (<= max_length)
var min_out := 16.0
var pivots: Array = []              # each: { "pos": Vector2, "sign": float }

var reel_speed := 220.0
var rewind_speed := 1000.0
var reeling := false

var _rewind_targets: Array = []


func _init(w: GridWorld, anchor_pos: Vector2, max_len: float) -> void:
    world = w
    anchor = anchor_pos
    max_length = max_len
    rope_out = max_len * 0.5


# --- geometry helpers -------------------------------------------------------

func _attach() -> Vector2:
    return pivots.back()["pos"] if pivots.size() > 0 else anchor


func fixed_length() -> float:
    var total := 0.0
    var prev := anchor
    for p in pivots:
        total += prev.distance_to(p["pos"])
        prev = p["pos"]
    return total


func used_length(player_pos: Vector2) -> float:
    return fixed_length() + _attach().distance_to(player_pos)


# --- per-frame constraint (called by the player after it moves) -------------

func constrain(player, _delta: float) -> void:
    _update_wrap(player.position)

    var used := used_length(player.position)

    # Feed rope out automatically as the player descends/moves away, up to max.
    # Skipped while reeling, otherwise the auto-feed would instantly cancel it.
    if not reeling and used > rope_out and rope_out < max_length:
        rope_out = min(used, max_length)
    rope_out = clampf(rope_out, 0.0, max_length)

    # Limit the WHOLE bent path (anchor -> pivots -> player) to the paid-out
    # rope, not just the last segment. Since rope_out <= max_length, used_length
    # can never exceed the maximum -- and any wrapped corners the rope can't
    # afford are dropped, so reeling never stalls in a phantom over-budget range.
    _limit_to_budget(player, rope_out)


# Walk anchor -> pivots... -> player allowing at most `budget` of rope. Places
# the player at the reachable point and drops pivots beyond the budget.
func _limit_to_budget(player, budget: float) -> void:
    var prev := anchor
    var remaining := budget
    for i in range(pivots.size()):
        var pv: Vector2 = pivots[i]["pos"]
        var seg := prev.distance_to(pv)
        if seg > remaining:
            player.position = prev + (pv - prev) / seg * remaining if seg > 0.001 else prev
            _kill_radial(player, prev)
            for j in range(pivots.size() - 1, i - 1, -1):
                pivots.remove_at(j)
            return
        remaining -= seg
        prev = pv

    var to_p: Vector2 = player.position - prev
    var d := to_p.length()
    if d > remaining and d > 0.001:
        player.position = prev + to_p / d * remaining
        _kill_radial(player, prev)


# Remove only the outward (radial) part of velocity, keeping the tangential
# component so the pendulum swing is preserved.
func _kill_radial(player, pivot: Vector2) -> void:
    var n: Vector2 = player.position - pivot
    var dlen := n.length()
    if dlen < 0.001:
        return
    n /= dlen
    var radial: float = player.velocity.dot(n)
    if radial > 0.0:
        player.velocity -= n * radial


func reel(delta: float) -> void:
    rope_out = max(rope_out - reel_speed * delta, min_out + fixed_length())


# --- wrap / unwrap ----------------------------------------------------------

func _update_wrap(player_pos: Vector2) -> void:
    # Release pivots no longer needed: if the previous attach can "see" the
    # player without hitting solid tiles, the corner is doing nothing.
    while pivots.size() > 0:
        var prev: Vector2 = (pivots[pivots.size() - 2]["pos"] if pivots.size() >= 2 else anchor)
        if not _los_blocked(prev, player_pos):
            pivots.pop_back()
        else:
            break

    # Catch new corners while the rope is blocked. Guard caps runaway loops.
    var guard := 0
    while guard < 8:
        guard += 1
        var attach := _attach()
        var corner = _find_wrap_corner(attach, player_pos)
        if corner == null:
            break
        var s: float = (corner - attach).cross(player_pos - corner)
        pivots.append({ "pos": corner, "sign": signf(s) })


func _find_wrap_corner(a: Vector2, b: Vector2):
    if not _los_blocked(a, b):
        return null
    var c := GridWorld.CELL
    var minx := floori(min(a.x, b.x) / c) - 1
    var maxx := floori(max(a.x, b.x) / c) + 2
    var miny := floori(min(a.y, b.y) / c) - 1
    var maxy := floori(max(a.y, b.y) / c) + 2

    var best = null
    var best_cost := INF
    for gy in range(miny, maxy + 1):
        for gx in range(minx, maxx + 1):
            if not _is_convex_corner(gx, gy):
                continue
            var cn := _corner_point(gx, gy)
            if cn.distance_to(a) < 1.0:
                continue
            if _los_blocked(a, cn):                 # corner must be reachable now
                continue
            var cost := a.distance_to(cn) + cn.distance_to(b)
            if cost < best_cost:
                best_cost = cost
                best = cn
    return best


# A grid corner (gx,gy) is convex/exposed when exactly one of its four
# surrounding cells is solid -> the rope can catch on that block's corner.
func _is_convex_corner(gx: int, gy: int) -> bool:
    var s := 0
    if world.is_solid(gx - 1, gy - 1): s += 1
    if world.is_solid(gx, gy - 1): s += 1
    if world.is_solid(gx - 1, gy): s += 1
    if world.is_solid(gx, gy): s += 1
    return s == 1


# Nudge the wrap point a couple px into the air, away from the solid cell,
# so line-of-sight checks don't graze the block the rope sits on.
func _corner_point(gx: int, gy: int) -> Vector2:
    var c := GridWorld.CELL
    var corner := Vector2(gx * c, gy * c)
    var e := 2.0
    if world.is_solid(gx, gy):
        return corner + Vector2(-e, -e)
    elif world.is_solid(gx - 1, gy):
        return corner + Vector2(e, -e)
    elif world.is_solid(gx, gy - 1):
        return corner + Vector2(-e, e)
    else:
        return corner + Vector2(e, e)


func _los_blocked(a: Vector2, b: Vector2) -> bool:
    var d := b - a
    var dist := d.length()
    if dist < 1.0:
        return false
    var steps := int(dist / (GridWorld.CELL * 0.25)) + 1
    for i in range(1, steps):                       # exclude both endpoints
        var t := float(i) / float(steps)
        if world.point_solid(a + d * t):
            return true
    return false


# --- panic rescue: rewind along the exact path (unwrap then climb) ----------

func start_rewind() -> void:
    _rewind_targets.clear()
    for i in range(pivots.size() - 1, -1, -1):
        _rewind_targets.append(pivots[i]["pos"])
    _rewind_targets.append(anchor)


func rewind_step(player, delta: float) -> bool:
    player.velocity = Vector2.ZERO
    if _rewind_targets.is_empty():
        return true
    var target: Vector2 = _rewind_targets[0]
    var to_t: Vector2 = target - player.position
    var step := rewind_speed * delta
    if to_t.length() <= step:
        player.position = target
        _rewind_targets.pop_front()
        if pivots.size() > 0:
            pivots.pop_back()
        return _rewind_targets.is_empty()
    player.position += to_t.normalized() * step
    return false
