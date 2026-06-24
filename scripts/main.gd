extends Node2D

# Wires the prototype together: world, player, rope, camera, input and HUD.

const PPM := 16.0                   # pixels per meter (cell 32px = 2m), for display only
const MAX_ROPE_METERS := 30.0

var world: GridWorld
var player: Player
var rope: Rope
var camera: Camera2D
var hud: Label

var panicking := false
var debug_view := false

var _spawn := Vector2.ZERO


func _ready() -> void:
    world = GridWorld.new()
    world.show_behind_parent = true     # tiles draw behind the rope overlay
    add_child(world)

    var sx := int(GridWorld.W / 2)
    var anchor_pos := Vector2((sx + 0.5) * GridWorld.CELL, 1.0 * GridWorld.CELL)
    rope = Rope.new(world, anchor_pos, MAX_ROPE_METERS * PPM)

    player = Player.new()
    add_child(player)
    _spawn = Vector2((sx - 3 + 0.5) * GridWorld.CELL, (GridWorld.GROUND - 1) * GridWorld.CELL)
    player.position = _spawn
    player.setup(world, rope)

    camera = Camera2D.new()
    camera.zoom = Vector2(1.4, 1.4)
    camera.position_smoothing_enabled = true
    player.add_child(camera)
    camera.make_current()

    _build_hud()


func _build_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(12, 12)
    hud.add_theme_color_override("font_color", Color.WHITE)
    hud.add_theme_color_override("font_outline_color", Color.BLACK)
    hud.add_theme_constant_override("outline_size", 5)
    layer.add_child(hud)


func _physics_process(delta: float) -> void:
    rope.reeling = Input.is_physical_key_pressed(KEY_J) and not panicking
    if panicking:
        if rope.rewind_step(player, delta):
            _end_panic()
    elif rope.reeling:
        rope.reel(delta)

    _update_hud()
    queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.physical_keycode:
            KEY_F1:
                debug_view = not debug_view
            KEY_K:
                _start_panic()
            KEY_R:
                _reset()
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        _try_dig(get_global_mouse_position())


func _try_dig(world_pos: Vector2) -> void:
    if panicking:
        return
    var pc := world.world_to_cell(player.position)
    var tc := world.world_to_cell(world_pos)
    var dx := tc.x - pc.x
    var dy := tc.y - pc.y
    # adjacent cells only, and never straight up (per the GDD)
    if abs(dx) + abs(dy) != 1:
        return
    if dy < 0:
        return
    world.dig(tc.x, tc.y)


func _start_panic() -> void:
    if panicking:
        return
    panicking = true
    player.rewinding = true
    player.velocity = Vector2.ZERO
    rope.start_rewind()


func _end_panic() -> void:
    panicking = false
    player.rewinding = false
    player.position = _spawn                 # land on solid ground, not over the open shaft
    player.velocity = Vector2.ZERO
    rope.pivots.clear()
    rope.rope_out = rope.max_length * 0.5


func _reset() -> void:
    panicking = false
    player.rewinding = false
    player.position = _spawn
    player.velocity = Vector2.ZERO
    rope.pivots.clear()
    rope.rope_out = rope.max_length * 0.5


func _update_hud() -> void:
    var used_m := rope.used_length(player.position) / PPM
    hud.text = "ROPE  out %.1fm / max %.1fm  used %.1fm  pivots %d\n" % [
        rope.rope_out / PPM, rope.max_length / PPM, used_m, rope.pivots.size()]
    hud.text += "ground:%s  %s\n" % [str(player.on_ground), ("[ RESCUE ]" if panicking else "")]
    hud.text += "A/D move·swing   SPACE jump   click=dig L/R/down   J=reel up   K=rescue   R=reset   F1=debug"


func _draw() -> void:
    if rope == null or player == null:
        return

    # rope polyline: anchor -> pivots... -> player
    var pts: Array = [rope.anchor]
    for p in rope.pivots:
        pts.append(p["pos"])
    pts.append(player.position)
    for i in range(pts.size() - 1):
        draw_line(pts[i], pts[i + 1], Color(0.20, 0.50, 1.0), 3.0)

    draw_circle(rope.anchor, 5.0, Color(0.60, 0.40, 0.20))   # winch
    for p in rope.pivots:
        draw_circle(p["pos"], 4.0, Color(1.0, 0.30, 0.30))   # wrap corners

    if debug_view:
        var c := GridWorld.CELL
        var grid_col := Color(1, 1, 1, 0.10)
        for gx in range(GridWorld.W + 1):
            draw_line(Vector2(gx * c, 0), Vector2(gx * c, GridWorld.H * c), grid_col, 1.0)
        for gy in range(GridWorld.H + 1):
            draw_line(Vector2(0, gy * c), Vector2(GridWorld.W * c, gy * c), grid_col, 1.0)
        var box := Rect2(player.position - player.he, player.he * 2.0)
        draw_rect(box, Color(0, 1, 0, 0.8), false, 1.5)
