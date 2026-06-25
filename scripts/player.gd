class_name Player
extends Node2D

# Custom tile-grid physics (no built-in physics body), so movement integrates
# cleanly with the rope and with digging blocks at runtime.

const GRAVITY := 1200.0
const WALK_SPEED := 140.0
const JUMP_VELOCITY := -380.0       # ~1 cell high; upgradeable later in the lore
const MAX_FALL := 900.0
const AIR_SWING_ACCEL := 360.0
const AIR_SWING_MAX := 280.0
const MAX_FRAME_MOVE := 40.0        # bigger than any legit per-frame move (~16px); above = teleport

var velocity := Vector2.ZERO
var on_ground := false
var rewinding := false
var he := Vector2(11, 14)           # half extents (< 16 so it fits a 32px cell / 1-wide tunnel)

# Dev-toggleable abilities (off by default; flipped from the dev menu).
var max_air_jumps := 0              # air jumps (dev-only; 0 = base game, single ground jump)
var high_jump_enabled := false      # ~2x jump height (height scales with v^2)
var reel_hop_enabled := false       # dev: 1 mid-air hop while reeling, refreshed on new contact
var _air_jumps_used := 0
var _reel_hop_available := false    # the reel-hop charge (granted on a new solid contact)
var _was_touching := false          # touched a solid last frame (for edge-triggered refresh)

var world: GridWorld
var rope: Rope


func setup(w: GridWorld, r: Rope) -> void:
    world = w
    rope = r


func _physics_process(delta: float) -> void:
    if world == null or rope == null:
        return
    if rewinding:
        return                       # rope drives position during the rescue

    var frame_start := position
    var prev_ground := on_ground
    rope.snapshot()                  # last known-good rope state

    _read_horizontal(delta)
    velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL)

    position.x += velocity.x * delta
    _resolve_horizontal()
    position.y += velocity.y * delta
    _resolve_vertical()

    on_ground = _check_below()
    rope.constrain(self, delta)

    # The rope sets the player's position directly and can park the body inside a
    # solid tile (e.g. reeling tight around a corner). The per-axis resolvers only
    # eject a *moving* body, so a stationary embedded player would stay stuck until
    # it jumped. Push out of any overlap every frame, regardless of velocity.
    if _depenetrate():
        # Don't let the rope claim a length shorter than where the player can
        # physically be, otherwise it keeps pulling into the wall (jitter).
        rope.relax(self)
        on_ground = _check_below()

    if on_ground and not prev_ground:
        _air_jumps_used = 0          # landed: refresh air jumps

    # Teleport guard: a single frame can never move the player more than a cell.
    # If the rope/collision produced an implausible jump, it's a bad state --
    # roll BOTH the player and the rope back to the last valid frame instead of
    # flinging the player (e.g. up to the surface). Worst case: a frozen frame.
    if frame_start.distance_to(position) > MAX_FRAME_MOVE:
        position = frame_start
        velocity = Vector2.ZERO
        rope.restore()

    # Reel-hop charge: refresh only on a NEW solid contact (edge-triggered) so it
    # can't be spammed while hugging a wall in a tight shaft. Spent in _try_jump.
    var touching := _touching_solid()
    if touching and not _was_touching:
        _reel_hop_available = true
    _was_touching = touching


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_SPACE or event.physical_keycode == KEY_W:
            _try_jump()


func _try_jump() -> void:
    if rewinding:
        return
    var jv := JUMP_VELOCITY * (sqrt(2.0) if high_jump_enabled else 1.0)
    if on_ground:
        velocity.y = jv
        _air_jumps_used = 0
        return
    if _air_jumps_used < max_air_jumps:
        velocity.y = jv
        _air_jumps_used += 1
        return
    # reel hop (dev): one mid-air hop while being reeled; the charge is regained
    # only by touching a new wall/corner (see the edge-triggered refresh above).
    if reel_hop_enabled and rope.reeling and _reel_hop_available:
        velocity.y = jv
        _reel_hop_available = false


func _read_horizontal(delta: float) -> void:
    var dir := 0.0
    if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
        dir -= 1.0
    if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
        dir += 1.0

    if on_ground:
        if dir != 0.0:
            velocity.x = dir * WALK_SPEED
        else:
            velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED * 3.0 * delta)
    else:
        velocity.x += dir * AIR_SWING_ACCEL * delta
        velocity.x = clampf(velocity.x, -AIR_SWING_MAX, AIR_SWING_MAX)


# --- tile collision ---------------------------------------------------------

func _overlapping_solids() -> Array:
    var c := GridWorld.CELL
    var out: Array = []
    var minx := floori((position.x - he.x) / c)
    var maxx := floori((position.x + he.x) / c)
    var miny := floori((position.y - he.y) / c)
    var maxy := floori((position.y + he.y) / c)
    for cy in range(miny, maxy + 1):
        for cx in range(minx, maxx + 1):
            if world.is_solid(cx, cy):
                out.append(Vector2i(cx, cy))
    return out


func _resolve_horizontal() -> void:
    var c := GridWorld.CELL
    var solids := _overlapping_solids()
    if solids.is_empty():
        return
    if velocity.x > 0.0:
        var min_left := INF
        for cell in solids:
            min_left = min(min_left, cell.x * c)
        position.x = min_left - he.x - 0.01
        velocity.x = 0.0
    elif velocity.x < 0.0:
        var max_right := -INF
        for cell in solids:
            max_right = max(max_right, (cell.x + 1) * c)
        position.x = max_right + he.x + 0.01
        velocity.x = 0.0


func _resolve_vertical() -> void:
    var c := GridWorld.CELL
    var solids := _overlapping_solids()
    if solids.is_empty():
        return
    if velocity.y > 0.0:
        var min_top := INF
        for cell in solids:
            min_top = min(min_top, cell.y * c)
        position.y = min_top - he.y - 0.01
        velocity.y = 0.0
    elif velocity.y < 0.0:
        var max_bot := -INF
        for cell in solids:
            max_bot = max(max_bot, (cell.y + 1) * c)
        position.y = max_bot + he.y + 0.01
        velocity.y = 0.0


func _check_below() -> bool:
    var c := GridWorld.CELL
    var cy := floori((position.y + he.y + 1.0) / c)
    var lx := floori((position.x - he.x + 1.0) / c)
    var rx := floori((position.x + he.x - 1.0) / c)
    return world.is_solid(lx, cy) or world.is_solid(rx, cy)


# True if a solid sits within a couple px of the player's box on any side
# (floor, ceiling or wall). Used to grant the reel-hop charge on contact.
func _touching_solid() -> bool:
    var c := GridWorld.CELL
    var pad := 1.5
    var minx := floori((position.x - he.x - pad) / c)
    var maxx := floori((position.x + he.x + pad) / c)
    var miny := floori((position.y - he.y - pad) / c)
    var maxy := floori((position.y + he.y + pad) / c)
    for cy in range(miny, maxy + 1):
        for cx in range(minx, maxx + 1):
            if world.is_solid(cx, cy):
                return true
    return false


# Push the player out of any solid it overlaps, along the axis of least
# penetration (per overlapping cell, greedily, a few iterations to converge).
# Velocity is left untouched so a queued jump still works. Returns true if moved.
func _depenetrate() -> bool:
    var c := GridWorld.CELL
    var half := c * 0.5
    var moved := false
    for _iter in range(4):
        var solids := _overlapping_solids()
        if solids.is_empty():
            break
        var best_push := Vector2.ZERO
        var best_pen := INF
        for cell in solids:
            var cc: Vector2i = cell
            var dx: float = position.x - (cc.x * c + half)
            var dy: float = position.y - (cc.y * c + half)
            var px: float = (he.x + half) - absf(dx)        # overlap depth on x
            var py: float = (he.y + half) - absf(dy)        # overlap depth on y
            if px <= 0.0 or py <= 0.0:
                continue
            if px < py:
                if px < best_pen:
                    best_pen = px
                    best_push = Vector2((signf(dx) if dx != 0.0 else 1.0) * (px + 0.01), 0.0)
            else:
                if py < best_pen:
                    best_pen = py
                    best_push = Vector2(0.0, (signf(dy) if dy != 0.0 else -1.0) * (py + 0.01))
        if best_pen == INF:
            break
        position += best_push
        moved = true
    return moved


func _draw() -> void:
    draw_rect(Rect2(-he.x, -he.y, he.x * 2.0, he.y * 2.0), Color(0.95, 0.85, 0.30), true)
    draw_rect(Rect2(-he.x, -he.y, he.x * 2.0, he.y * 2.0), Color(0.20, 0.15, 0.05), false, 2.0)
