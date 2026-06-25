extends Node2D

# Wires the prototype together: world, player, rope, camera, input and HUD.

const PPM := 16.0                   # pixels per meter (cell 32px = 2m), for display only
const MAX_ROPE_METERS := 30.0
const DEFAULT_ZOOM := 1.4
const DEFAULT_BAG := 20

var world: GridWorld
var player: Player
var rope: Rope
var camera: Camera2D
var hud: Label
var panic: PanicSystem
var panic_overlay: ColorRect
var panic_fill: ColorRect
var backpack: Backpack
var dev_menu: DevMenu

var panicking := false
var emergency := false
var debug_view := false
var torches: Array = []

# dev-mode state
var claustrophobia_off := false
var free_cam := false
var free_cam_y := 0.0

var _spawn := Vector2.ZERO
var _last_player_pos := Vector2.ZERO
var _have_last := false


func _ready() -> void:
    world = GridWorld.new()
    world.show_behind_parent = true     # tiles draw behind the rope overlay
    add_child(world)

    var sx := int(GridWorld.W / 2)
    var anchor_pos := Vector2((sx + 0.5) * GridWorld.CELL, 1.0 * GridWorld.CELL)
    rope = Rope.new(world, anchor_pos, MAX_ROPE_METERS * PPM)
    panic = PanicSystem.new()
    backpack = Backpack.new()

    player = Player.new()
    add_child(player)
    _spawn = Vector2((sx - 3 + 0.5) * GridWorld.CELL, (GridWorld.GROUND - 1) * GridWorld.CELL)
    player.position = _spawn
    player.setup(world, rope)

    camera = Camera2D.new()
    camera.zoom = Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM)
    camera.position_smoothing_enabled = true
    add_child(camera)                   # child of main, not player: free cam needs it
    camera.global_position = player.position
    camera.make_current()

    _build_hud()


func _build_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)

    # full-screen red vignette that intensifies with panic
    panic_overlay = ColorRect.new()
    panic_overlay.color = Color(0.7, 0.0, 0.0, 0.0)
    panic_overlay.anchor_right = 1.0
    panic_overlay.anchor_bottom = 1.0
    panic_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(panic_overlay)

    # panic bar pinned to the bottom-left, clear of the top-left text HUD
    var bar_bg := ColorRect.new()
    bar_bg.color = Color(0, 0, 0, 0.5)
    bar_bg.anchor_top = 1.0
    bar_bg.anchor_bottom = 1.0
    bar_bg.offset_left = 12
    bar_bg.offset_right = 232
    bar_bg.offset_top = -34
    bar_bg.offset_bottom = -16
    bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(bar_bg)

    panic_fill = ColorRect.new()
    panic_fill.color = Color(0.2, 0.8, 0.3)
    panic_fill.anchor_top = 1.0
    panic_fill.anchor_bottom = 1.0
    panic_fill.offset_left = 14
    panic_fill.offset_right = 14
    panic_fill.offset_top = -32
    panic_fill.offset_bottom = -18
    panic_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(panic_fill)

    # text HUD: span the full width and wrap so long lines never run off-screen
    hud = Label.new()
    hud.offset_left = 12
    hud.offset_top = 12
    hud.anchor_right = 1.0
    hud.offset_right = -12
    hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hud.add_theme_font_size_override("font_size", 13)
    hud.add_theme_color_override("font_color", Color.WHITE)
    hud.add_theme_color_override("font_outline_color", Color.BLACK)
    hud.add_theme_constant_override("outline_size", 4)
    layer.add_child(hud)

    _build_dev_menu(layer)


func _build_dev_menu(layer: CanvasLayer) -> void:
    dev_menu = DevMenu.new()
    dev_menu.anchor_left = 1.0
    dev_menu.anchor_right = 1.0
    dev_menu.offset_left = -320
    dev_menu.offset_right = -12
    dev_menu.offset_top = 12
    layer.add_child(dev_menu)

    # rope length: free numeric input (meters), uncapped
    var get_rope: Callable = func(): return rope.max_length / PPM
    var set_rope: Callable = func(v): rope.max_length = maxf(1.0, v) * PPM
    dev_menu.add_number("Rope max m", get_rope, set_rope)

    var get_zoom: Callable = func(): return camera.zoom.x
    var set_zoom: Callable = func(v): camera.zoom = Vector2(v, v)
    dev_menu.add_slider("Zoom", 0.1, 2.0, 0.05, get_zoom, set_zoom)

    var get_bag: Callable = func(): return float(backpack.capacity)
    var set_bag: Callable = func(v): backpack.capacity = int(v)
    dev_menu.add_slider("Bag cap", 5.0, 200.0, 5.0, get_bag, set_bag)

    var get_claustro: Callable = func(): return claustrophobia_off
    var set_claustro: Callable = func(v): _set_claustro_off(v)
    dev_menu.add_toggle("Claustro off", get_claustro, set_claustro)

    var get_freecam: Callable = func(): return free_cam
    var set_freecam: Callable = func(v): _set_free_cam(v)
    dev_menu.add_toggle("Free cam UP/DN", get_freecam, set_freecam)

    # air jumps: dev-only, off by default (0). Works in free fall and while reeling.
    var get_aj: Callable = func(): return float(player.max_air_jumps)
    var set_aj: Callable = func(v): player.max_air_jumps = int(v)
    dev_menu.add_slider("Air jumps", 0.0, 5.0, 1.0, get_aj, set_aj)

    var get_hj: Callable = func(): return player.high_jump_enabled
    var set_hj: Callable = func(v): player.high_jump_enabled = v
    dev_menu.add_toggle("High jump 2x", get_hj, set_hj)

    dev_menu.add_button("Reset to defaults", _dev_reset_defaults)


func _set_claustro_off(v: bool) -> void:
    claustrophobia_off = v
    if v:
        panic.value = 0.0               # clear the vignette immediately


func _set_free_cam(v: bool) -> void:
    free_cam = v
    if v:
        free_cam_y = camera.global_position.y


func _dev_reset_defaults() -> void:
    rope.max_length = MAX_ROPE_METERS * PPM
    camera.zoom = Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM)
    backpack.capacity = DEFAULT_BAG
    claustrophobia_off = false
    free_cam = false
    player.max_air_jumps = 0
    player.high_jump_enabled = false
    dev_menu.refresh()


# Free cam detaches vertical framing from the player: UP/DOWN pan across the whole
# map (pan faster when zoomed out). Otherwise the camera just follows the player.
func _update_camera(delta: float) -> void:
    if free_cam:
        var dir := 0.0
        if Input.is_physical_key_pressed(KEY_UP):
            dir -= 1.0
        if Input.is_physical_key_pressed(KEY_DOWN):
            dir += 1.0
        var speed := 600.0 / camera.zoom.y
        free_cam_y = clampf(free_cam_y + dir * speed * delta, 0.0, GridWorld.H * GridWorld.CELL)
        camera.global_position = Vector2(player.position.x, free_cam_y)
    else:
        camera.global_position = player.position


func _physics_process(delta: float) -> void:
    rope.reeling = Input.is_physical_key_pressed(KEY_J) and not panicking
    if panicking:
        if rope.rewind_step(player, delta):
            _end_panic()
    elif not claustrophobia_off:
        panic.update(delta, player.position, world, torches)
        if panic.value >= 100.0:
            emergency = true
            _start_panic()

    _update_camera(delta)
    _update_hud()
    queue_redraw()

    # Teleport detector: a single-frame jump bigger than ~1.5 cells while not in
    # a rescue should never happen. Log the rope state so the bug can be traced.
    if _have_last and not panicking:
        var jump := _last_player_pos.distance_to(player.position)
        if jump > 48.0:
            print("[TELEPORT] jump=%.0fpx  reeling=%s on_ground=%s pivots=%d rope_out=%.1f used=%.1f  from=%s to=%s" % [
                jump, str(rope.reeling), str(player.on_ground), rope.pivots.size(),
                rope.rope_out, rope.used_length(player.position), str(_last_player_pos), str(player.position)])
    _last_player_pos = player.position
    _have_last = true


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.physical_keycode:
            KEY_F1:
                debug_view = not debug_view
            KEY_F3:
                dev_menu.toggle()
            KEY_K:
                _start_panic()
            KEY_T:
                _place_torch()
            KEY_G:
                world.regenerate(randi())
                _reset()
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
    # Ore in a full backpack stays in the wall (pressure to surface) instead of
    # being destroyed for nothing. Dirt/stone can always be dug to move around.
    var target := world.get_cell(tc.x, tc.y)
    if GridWorld.is_ore_cell(target) and backpack.is_full():
        return
    var mined := world.dig(tc.x, tc.y)
    if GridWorld.is_ore_cell(mined):
        backpack.add(mined)


func _place_torch() -> void:
    if panicking:
        return
    var pc := world.world_to_cell(player.position)
    torches.append(world.cell_center(pc.x, pc.y))


func _start_panic() -> void:
    if panicking:
        return
    panicking = true
    player.rewinding = true
    player.velocity = Vector2.ZERO
    rope.start_rewind()


func _end_panic() -> void:
    panicking = false
    emergency = false
    player.rewinding = false
    player.position = _spawn                 # land on solid ground, not over the open shaft
    player.velocity = Vector2.ZERO
    panic.value = 0.0
    rope.pivots.clear()
    rope.rope_out = rope.max_length * 0.5


func _reset() -> void:
    panicking = false
    emergency = false
    player.rewinding = false
    player.position = _spawn
    player.velocity = Vector2.ZERO
    panic.value = 0.0
    rope.pivots.clear()
    rope.rope_out = rope.max_length * 0.5


func _update_hud() -> void:
    var used_m := rope.used_length(player.position) / PPM
    var status := ("[ EMERGENCY RESCUE ]" if emergency else ("[ RESCUE ]" if panicking else ""))
    hud.text = "ROPE  out %.1fm / max %.1fm  used %.1fm  pivots %d\n" % [
        rope.rope_out / PPM, rope.max_length / PPM, used_m, rope.pivots.size()]
    hud.text += "PANIC %d%%   torches %d   %s\n" % [int(panic.value), torches.size(), status]
    var bag_warn := "  [FULL]" if backpack.is_full() else ""
    hud.text += "BAG %d/%d  value $%d%s\n" % [backpack.count(), backpack.capacity, backpack.value(), bag_warn]
    var pc := world.world_to_cell(player.position)
    var depth_m := maxf(0.0, (player.position.y / GridWorld.CELL - GridWorld.GROUND) * 2.0)
    hud.text += "POS x=%.0f y=%.0f  cell=(%d,%d)  depth=%.0fm  ground=%s  vel=(%.0f,%.0f)\n" % [
        player.position.x, player.position.y, pc.x, pc.y, depth_m,
        str(player.on_ground), player.velocity.x, player.velocity.y]
    hud.text += "A/D move·swing  SPACE jump  click=dig  J=reel  T=torch  K=rescue  R=reset  G=regen  F1=debug  F3=dev"

    var f := clampf(panic.value / 100.0, 0.0, 1.0)
    panic_overlay.color.a = f * 0.45
    panic_fill.offset_right = panic_fill.offset_left + 216.0 * f
    panic_fill.color = Color(0.2, 0.8, 0.3).lerp(Color(0.9, 0.1, 0.1), f)


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

    for t in torches:
        draw_circle(t, panic.torch_radius, Color(1.0, 0.7, 0.2, 0.07))   # safe zone
        draw_circle(t, 5.0, Color(1.0, 0.6, 0.1))                        # torch

    if debug_view:
        var c := GridWorld.CELL
        var grid_col := Color(1, 1, 1, 0.10)
        for gx in range(GridWorld.W + 1):
            draw_line(Vector2(gx * c, 0), Vector2(gx * c, GridWorld.H * c), grid_col, 1.0)
        for gy in range(GridWorld.H + 1):
            draw_line(Vector2(0, gy * c), Vector2(GridWorld.W * c, gy * c), grid_col, 1.0)
        var box := Rect2(player.position - player.he, player.he * 2.0)
        draw_rect(box, Color(0, 1, 0, 0.8), false, 1.5)
