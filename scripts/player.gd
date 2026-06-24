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

var velocity := Vector2.ZERO
var on_ground := false
var rewinding := false
var he := Vector2(11, 14)           # half extents (< 16 so it fits a 32px cell / 1-wide tunnel)

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

    _read_horizontal(delta)
    velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL)

    position.x += velocity.x * delta
    _resolve_horizontal()
    position.y += velocity.y * delta
    _resolve_vertical()

    on_ground = _check_below()
    rope.constrain(self, delta)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_SPACE or event.physical_keycode == KEY_W:
            if on_ground and not rewinding:
                velocity.y = JUMP_VELOCITY


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


func _draw() -> void:
    draw_rect(Rect2(-he.x, -he.y, he.x * 2.0, he.y * 2.0), Color(0.95, 0.85, 0.30), true)
    draw_rect(Rect2(-he.x, -he.y, he.x * 2.0, he.y * 2.0), Color(0.20, 0.15, 0.05), false, 2.0)
