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

var debug_log := false              # dev: log WHY each pivot is dropped (wired to the
                                    # pivot-linger toggle) so the failing path is named

var reel_speed := 220.0
var rewind_speed := 1000.0
var reeling := false

# Manual lock (X): cap how much rope can be let out below max_length, so the player
# can hang at a chosen depth (e.g. 40m on a 50m rope). Reeling ratchets the lock down.
var locked := false
var lock_length := 0.0

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


# Snapshot / restore the rope state so the player can roll back a frame that
# produced an invalid (teleporting) result -- keeps position and rope consistent.
var _snap_pivots: Array = []
var _snap_rope_out := 0.0

func snapshot() -> void:
    _snap_pivots = pivots.duplicate(true)
    _snap_rope_out = rope_out

func restore() -> void:
    pivots = _snap_pivots.duplicate(true)
    rope_out = _snap_rope_out


# After the player was pushed out of a solid, the rope can't be shorter than the
# straight-line distance to where the player actually is -- otherwise it keeps
# yanking the body back into the wall. Grow rope_out to match the real position.
func relax(player) -> void:
    var pos: Vector2 = player.position
    rope_out = clampf(maxf(rope_out, used_length(pos)), min_out, max_length)


# --- per-frame constraint (called by the player after it moves) -------------

# Lock the rope at its current let-out (X), or release it back to max. Locking
# freezes payout so the player hangs at this length; releasing restores max_length.
func toggle_lock(player) -> void:
    locked = not locked
    if locked:
        lock_length = clampf(maxf(rope_out, used_length(player.position)), min_out, max_length)


func constrain(player, delta: float) -> void:
    _update_wrap(player.position)

    var used := used_length(player.position)
    var cap := lock_length if locked else max_length

    # rope_out is always relative to the player's current position (no drift).
    if reeling:
        rope_out = max(used - reel_speed * delta, min_out)
        if locked:
            lock_length = clampf(min(lock_length, rope_out), min_out, max_length)  # ratchet down
    elif player.on_ground:
        rope_out = min(used, cap)
    elif used > rope_out:
        rope_out = min(used, cap)

    rope_out = clampf(rope_out, 0.0, cap)
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
            if debug_log: print("[ROPE-DROP] reason=BUDGET (rope_out=%.1f too short) dropping %d pivot(s) from i=%d" % [budget, pivots.size() - i, i])
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


# --- wrap / unwrap ----------------------------------------------------------

func _update_wrap(player_pos: Vector2) -> void:
    # Drop pivots whose corner no longer exists: digging a block away leaves its
    # pivot stranded (the rope bends around an "invisible block"). Recover the grid
    # corner from the offset pivot point and require it to still be convex.
    var k := 0
    while k < pivots.size():
        var gp: Vector2 = pivots[k]["pos"]
        var gx := int(round(gp.x / GridWorld.CELL))
        var gy := int(round(gp.y / GridWorld.CELL))
        if not _is_convex_corner(gx, gy):
            if debug_log: print("[ROPE-DROP] reason=STALE (corner %d,%d no longer convex) pos=(%.0f,%.0f)" % [gx, gy, gp.x, gp.y])
            pivots.remove_at(k)
        else:
            k += 1

    # Release a pivot when the rope no longer needs to bend around its corner.
    #
    # A clear prev->next line of sight is NECESSARY but NOT SUFFICIENT for the
    # player-end (last) pivot. The rope is wrapped on one SIDE of the corner; a
    # clear sightline can open while the player is still on that same side (the
    # straight prev->player line just misses the block by routing through a
    # DIFFERENT gap -- a different homotopy class). Dropping the pivot there made
    # the rope teleport across the block: the last pivot "unpivoted" and the
    # penultimate became the last via an illegal shortcut. That is BUG-01.
    #
    # The captured winding `sign` is the real release test: the bend only truly
    # straightens once the player swings PAST the corner, flipping the sign. So
    # the last pivot is released only when LOS is clear AND the winding reversed.
    # Interior pivots (next = another fixed corner) keep the LOS-only rule: their
    # sign cannot reverse on its own, and the dig case legitimately opens a clear
    # prev<->next line that should drop a now-useless inner corner.
    var i := 0
    while i < pivots.size():
        var prev: Vector2 = anchor
        if i > 0:
            prev = pivots[i - 1]["pos"]
        var is_last := i == pivots.size() - 1
        var nxt: Vector2 = player_pos
        if not is_last:
            nxt = pivots[i + 1]["pos"]
        var release := not _los_blocked(prev, nxt)
        if release and is_last:
            # Still wound the same way around the corner? Then the rope is genuinely
            # wrapped (just with an open sightline) -- keep it. This is the fix.
            var pv: Vector2 = pivots[i]["pos"]
            var cur := signf((pv - prev).cross(nxt - pv))
            if cur == pivots[i]["sign"]:
                release = false
        if release:
            if debug_log:
                var pp: Vector2 = pivots[i]["pos"]
                print("[ROPE-DROP] reason=RELEASE (prev->next LOS clear%s) i=%d pos=(%.0f,%.0f) prev=(%.0f,%.0f) next=(%.0f,%.0f)" % [
                    ", winding reversed" if is_last else "", i, pp.x, pp.y, prev.x, prev.y, nxt.x, nxt.y])
            pivots.remove_at(i)
            i = maxi(0, i - 1)               # neighbour changed: recheck previous
        else:
            i += 1

    # Catch new corners while the rope is blocked. Guard caps runaway loops.
    var guard := 0
    while guard < 8:
        guard += 1
        var attach := _attach()
        var corner = _find_wrap_corner(attach, player_pos)
        if corner == null:
            break
        # Don't wrap a corner the rope can't afford to reach.
        if fixed_length() + attach.distance_to(corner) > rope_out:
            break
        var s: float = (corner - attach).cross(player_pos - corner)
        var ws := signf(s)
        if ws == 0.0:
            ws = 1.0                        # degenerate (collinear add): pick a side; self-corrects
        pivots.append({ "pos": corner, "sign": ws })


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
    # Step 0.5px. Corner grazes can be ~1px thin (e.g. jumping straight up glued
    # to a wall): coarser sampling skipped over them, so the rope thought a blocked
    # line was clear and unwrapped straight through a block. 0.5px catches the
    # visible (>~1px) grazes while staying tolerant of sub-pixel tangents.
    var steps := int(dist / 0.5) + 1
    for i in range(1, steps):                       # exclude both endpoints
        var t := float(i) / float(steps)
        if world.point_solid(a + d * t):
            return true
    return false


# --- panic rescue: rewind along the exact path (unwrap then climb) ----------

func start_rewind(extra_exit: Array = []) -> void:
    locked = false                              # a rescue overrides any manual lock
    _rewind_targets.clear()
    for i in range(pivots.size() - 1, -1, -1):
        _rewind_targets.append(pivots[i]["pos"])
    _rewind_targets.append(anchor)
    # Extra waypoints (e.g. slide along the surface, step down beside the shaft)
    # so the climb-out reads smoothly instead of snapping at the winch.
    for p in extra_exit:
        _rewind_targets.append(p)


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
