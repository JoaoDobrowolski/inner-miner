class_name RopeVerlet
extends RefCounted

# Verlet/PBD rope: a chain of point masses from the winch (anchor) to the player.
# It drapes over the tile grid via per-point AND per-segment collision, so it
# wraps corners with NO explicit corner/LOS logic and NO add/release oscillation
# -- the structural failure of the taut-polyline (see BUG-01). Gravity gives the
# rope natural sag/swing (dynamic feel).
#
# Drop-in for `Rope`: exposes the same surface player.gd/main.gd call
# (constrain/snapshot/restore/relax/used_length/rope_out/max_length/anchor/
# start_rewind/rewind_step/reeling/debug_log) plus `points` for drawing. `pivots`
# is an always-empty stub so main.gd's pivot-count/clear calls stay valid.

var world: GridWorld
var anchor: Vector2
var max_length: float
var rope_out: float
var min_out := 16.0
var reeling := false
var debug_log := false
var pivots: Array = []              # interface stub (always empty; Verlet has no pivots)

# --- feel tunables ---------------------------------------------------------
var point_count := 36
var iterations := 24
var gravity := 750.0                # sag / dynamics
var damp := 0.96
var reel_speed := 220.0
var rewind_speed := 1000.0

var points: Array = []              # Vector2 chain: [0]=anchor ... [n-1]=player end
var _prev: Array = []
var _inited := false


func _init(w: GridWorld, anchor_pos: Vector2, max_len: float) -> void:
    world = w
    anchor = anchor_pos
    max_length = max_len
    rope_out = max_len * 0.5


func _init_chain(ppos: Vector2) -> void:
    points.clear()
    _prev.clear()
    for i in range(point_count):
        var p: Vector2 = anchor.lerp(ppos, float(i) / float(point_count - 1))
        points.append(p)
        _prev.append(p)
    _inited = true


# Straight-line budget (geodesic ~ straight when the path is mostly clear). v1
# simplification: the leash itself is enforced by the collision-aware chain below,
# which pulls the end back around corners, so this is only the rope_out policy.
func used_length(player_pos: Vector2) -> float:
    return anchor.distance_to(player_pos)


func chain_length() -> float:
    var t := 0.0
    for i in range(points.size() - 1):
        t += (points[i] as Vector2).distance_to(points[i + 1])
    return t


# --- snapshot/restore for the teleport guard -------------------------------
var _snap_points: Array = []
var _snap_prev: Array = []
var _snap_rope_out := 0.0

func snapshot() -> void:
    _snap_points = points.duplicate()
    _snap_prev = _prev.duplicate()
    _snap_rope_out = rope_out

func restore() -> void:
    points = _snap_points.duplicate()
    _prev = _snap_prev.duplicate()
    rope_out = _snap_rope_out


func relax(player) -> void:
    var pos: Vector2 = player.position
    rope_out = clampf(maxf(rope_out, used_length(pos)), min_out, max_length)


# --- per-frame constraint (called by the player after it moves) -------------
func constrain(player, delta: float) -> void:
    var ppos: Vector2 = player.position
    if not _inited:
        _init_chain(ppos)

    var used := used_length(ppos)
    if reeling:
        rope_out = max(rope_out - reel_speed * delta, min_out)
    elif player.on_ground:
        rope_out = min(used, max_length)
    elif used > rope_out:
        rope_out = min(used, max_length)
    rope_out = clampf(rope_out, min_out, max_length)

    # Leash: the rope only acts at its LIMIT. Within reach the player moves under
    # its own physics with NO drag; only when fully extended does it clamp + kill
    # the outward speed (a taut rope catching you). This is what keeps free-fall
    # and walking from feeling "viscous".
    _apply_leash(player)
    # The visual chain then drapes between the anchor and the (clamped) player --
    # it follows the player, it does NOT move it.
    _simulate_visual(player.position)


# Clamp the player to within rope_out of the anchor (straight line) and remove
# only the outward radial velocity, preserving tangential swing.
func _apply_leash(player) -> void:
    var to: Vector2 = player.position - anchor
    var d := to.length()
    if d <= rope_out or d < 0.001:
        return
    var n := to / d
    player.position = anchor + n * rope_out
    var radial: float = player.velocity.dot(n)
    if radial > 0.0:
        player.velocity -= n * radial


# Drape the chain between the pinned anchor and the pinned player end. Interior
# points sag under gravity, are kept within rope_out by max-distance constraints,
# and collide with tiles (point + segment) so the rope wraps corners cleanly.
func _simulate_visual(ppos: Vector2) -> void:
    var dt := 1.0 / 60.0
    for i in range(1, point_count - 1):                # interior only; ends pinned
        var cur: Vector2 = points[i]
        var vel: Vector2 = (cur - _prev[i]) * damp
        _prev[i] = cur
        points[i] = cur + vel + Vector2(0, gravity) * dt * dt
    points[0] = anchor
    points[point_count - 1] = ppos

    var rest := rope_out / float(point_count - 1)
    for _it in range(iterations):
        for i in range(point_count - 1):
            var a: Vector2 = points[i]
            var b: Vector2 = points[i + 1]
            var d := b - a
            var dist := d.length()
            if dist > rest and dist > 0.0001:          # max-distance: shorter ok (sag)
                var corr := d * (((dist - rest) / dist) * 0.5)
                if i != 0:
                    points[i] = a + corr
                if i + 1 != point_count - 1:
                    points[i + 1] = b - corr
        points[0] = anchor
        points[point_count - 1] = ppos
        for i in range(1, point_count - 1):
            points[i] = _push_out(points[i])
        for i in range(point_count - 1):
            _collide_segment(i)


# push the deepest interior sample of segment i out of any solid, splitting the
# correction between its two endpoints (weighted by where along the segment it is).
func _collide_segment(i: int) -> void:
    var a: Vector2 = points[i]
    var b: Vector2 = points[i + 1]
    var d := b - a
    var dist := d.length()
    if dist < 0.3:
        return
    var ss := int(dist / 1.5) + 1
    var worst := 0.0
    var worst_out := Vector2.ZERO
    var worst_t := 0.0
    for s in range(1, ss):
        var t := float(s) / float(ss)
        var p: Vector2 = a + d * t
        var out: Vector2 = _push_out(p) - p
        var l := out.length()
        if l > worst:
            worst = l
            worst_out = out
            worst_t = t
    if worst > 0.0:
        if i != 0:
            points[i] = (points[i] as Vector2) + worst_out * (1.0 - worst_t)
        if i + 1 != point_count - 1:
            points[i + 1] = (points[i + 1] as Vector2) + worst_out * worst_t


# push a point out of a solid to the nearest air-facing edge (a few iterations)
func _push_out(p: Vector2) -> Vector2:
    var c := GridWorld.CELL
    for _k in range(3):
        var cx := floori(p.x / c)
        var cy := floori(p.y / c)
        if not world.is_solid(cx, cy):
            return p
        var lx := p.x - cx * c
        var rx := (cx + 1) * c - p.x
        var ty := p.y - cy * c
        var by := (cy + 1) * c - p.y
        var best := INF
        var push := Vector2.ZERO
        if not world.is_solid(cx - 1, cy) and lx < best: best = lx; push = Vector2(-(lx + 0.01), 0)
        if not world.is_solid(cx + 1, cy) and rx < best: best = rx; push = Vector2(rx + 0.01, 0)
        if not world.is_solid(cx, cy - 1) and ty < best: best = ty; push = Vector2(0, -(ty + 0.01))
        if not world.is_solid(cx, cy + 1) and by < best: best = by; push = Vector2(0, by + 0.01)
        if best == INF:
            push = Vector2(0, -(ty + 0.01))         # fully buried: shove up
        p += push
    return p


# --- panic rescue: reel the player up toward the anchor ---------------------
func start_rewind() -> void:
    pass                                            # nothing to precompute; reel below

func rewind_step(player, delta: float) -> bool:
    player.velocity = Vector2.ZERO
    rope_out = max(rope_out - rewind_speed * delta, min_out)
    _apply_leash(player)                            # shrinking rope_out pulls the player in
    _simulate_visual(player.position)
    return player.position.distance_to(anchor) <= 24.0
