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
var block_edit := false

# rope penetration probe (dev, opt-in): logs how far the drawn rope runs INSIDE a
# solid (the "solid-chord" in px). This is the correct cut metric -- distance to
# the nearest air edge collapses to ~0 at a convex corner even when the rope cuts
# a real triangle off it, so the earlier metric hid genuine cuts. Edge-triggered:
# a settled scene logs once.
const PEN_CHORD_MIN := 1.5
var rope_pen_probe := false
var _pen_armed := true

# pivot linger (dev): ghost each released pivot for ~1s (cyan, labelled with its
# corner direction NW/NE/SW/SE) and log every pivot add/remove. A one-frame wrong
# wrap -- e.g. snapping to the NW corner while moving left -- becomes visible and
# traceable instead of flashing past.
const PIVOT_GHOST_LIFE := 1.0
var pivot_linger := false
var _ghosts: Array = []          # each: { "pos": Vector2, "dir": String, "life": float }
var _prev_piv: Array = []        # previous frame's pivot positions (add/remove diff)

# digging: hold a direction into a solid; it breaks after break_time seconds
var break_time := 0.5
var _dig_timer := 0.0
var _dig_target := Vector2i(-2, -2)

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

    # reel hop: 1 mid-air hop while reeling (J), refreshed on a new wall contact
    var get_rh: Callable = func(): return player.reel_hop_enabled
    var set_rh: Callable = func(v): player.reel_hop_enabled = v
    dev_menu.add_toggle("Reel hop", get_rh, set_rh)

    var get_hj: Callable = func(): return player.high_jump_enabled
    var set_hj: Callable = func(v): player.high_jump_enabled = v
    dev_menu.add_toggle("High jump 2x", get_hj, set_hj)

    # block editor: LMB add, RMB remove, anywhere the mouse is (no adjacency)
    var get_be: Callable = func(): return block_edit
    var set_be: Callable = func(v): block_edit = v
    dev_menu.add_toggle("Block edit LMB/RMB", get_be, set_be)

    # rope penetration probe: logs px depth of any real rope-vs-block crossing
    var get_pen: Callable = func(): return rope_pen_probe
    var set_pen: Callable = func(v): rope_pen_probe = v; _pen_armed = true
    dev_menu.add_toggle("Rope pen probe (log)", get_pen, set_pen)

    # pivot linger: ghost released pivots + log pivot add/remove with corner dir
    var get_lg: Callable = func(): return pivot_linger
    var set_lg: Callable = func(v): pivot_linger = v; rope.debug_log = v; _ghosts.clear(); _prev_piv.clear()
    dev_menu.add_toggle("Pivot linger (dbg)", get_lg, set_lg)

    var get_bt: Callable = func(): return break_time
    var set_bt: Callable = func(v): break_time = v
    dev_menu.add_slider("Break time s", 0.0, 2.0, 0.1, get_bt, set_bt)

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
    block_edit = false
    rope_pen_probe = false
    pivot_linger = false
    break_time = 0.5
    player.max_air_jumps = 0
    player.high_jump_enabled = false
    player.reel_hop_enabled = false
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
    _update_block_edit()
    _update_digging(delta)
    _update_hud()
    queue_redraw()

    if rope_pen_probe and not panicking:
        _check_rope_pen()
    if pivot_linger:
        _update_pivot_linger(delta)

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


# Dev block editor: paint solid with LMB, erase with RMB, anywhere on the map.
func _update_block_edit() -> void:
    if not block_edit:
        return
    # don't paint through the dev-menu panel while clicking its widgets
    if dev_menu.visible and dev_menu.get_global_rect().has_point(get_viewport().get_mouse_position()):
        return
    var cell := world.world_to_cell(get_global_mouse_position())
    if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        world.set_cell(cell.x, cell.y, GridWorld.Cell.STONE)
    elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
        world.set_cell(cell.x, cell.y, GridWorld.Cell.AIR)


# Directional digging: hold S (down), W (up), or A/D into a wall. The targeted
# block breaks after break_time seconds of holding. Releasing/retargeting resets.
func _update_digging(delta: float) -> void:
    if panicking or block_edit:
        _dig_timer = 0.0
        _dig_target = Vector2i(-2, -2)
        return
    var pc := world.world_to_cell(player.position)
    var target := Vector2i(-2, -2)
    if Input.is_physical_key_pressed(KEY_S) and world.is_diggable(pc.x, pc.y + 1):
        target = Vector2i(pc.x, pc.y + 1)
    elif (Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)) and world.is_diggable(pc.x - 1, pc.y):
        target = Vector2i(pc.x - 1, pc.y)
    elif (Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) and world.is_diggable(pc.x + 1, pc.y):
        target = Vector2i(pc.x + 1, pc.y)
    elif Input.is_physical_key_pressed(KEY_W) and world.is_diggable(pc.x, pc.y - 1):
        target = Vector2i(pc.x, pc.y - 1)

    if target == Vector2i(-2, -2):
        _dig_timer = 0.0
        _dig_target = target
        return
    if target != _dig_target:
        _dig_target = target
        _dig_timer = 0.0
    _dig_timer += delta
    if _dig_timer >= break_time:
        # Ore in a full backpack stays in the wall instead of being wasted.
        var tc := world.get_cell(target.x, target.y)
        if GridWorld.is_ore_cell(tc) and backpack.is_full():
            _dig_timer = 0.0
            return
        world.dig(target.x, target.y)
        if GridWorld.is_ore_cell(tc):
            backpack.add(tc)
        _dig_timer = 0.0
        _dig_target = Vector2i(-2, -2)


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
    hud.text += "A/D move·swing  SPACE jump  dig: S down · W up · hold A/D into wall  J=reel  T=torch  K=rescue  R=reset  G=regen  F1=debug  F3=dev"

    var f := clampf(panic.value / 100.0, 0.0, 1.0)
    panic_overlay.color.a = f * 0.45
    panic_fill.offset_right = panic_fill.offset_left + 216.0 * f
    panic_fill.color = Color(0.2, 0.8, 0.3).lerp(Color(0.9, 0.1, 0.1), f)


# --- pivot linger debug (dev, opt-in) ---------------------------------------

# Corner direction of a pivot, recovered from its 2px air offset.
func _pivot_dir(pos: Vector2) -> String:
    var gx := int(round(pos.x / GridWorld.CELL))
    var gy := int(round(pos.y / GridWorld.CELL))
    var dx := pos.x - gx * GridWorld.CELL
    var dy := pos.y - gy * GridWorld.CELL
    return ("N" if dy < 0.0 else "S") + ("W" if dx < 0.0 else "E")


func _has_pos(arr: Array, pos: Vector2) -> bool:
    for q in arr:
        if (q as Vector2).distance_to(pos) < 0.5:
            return true
    return false


func _update_pivot_linger(delta: float) -> void:
    var cur: Array = []
    for p in rope.pivots:
        cur.append(p["pos"])

    # log additions / removals vs last frame, with corner direction
    for pos in cur:
        if not _has_pos(_prev_piv, pos):
            var gx := int(round((pos as Vector2).x / GridWorld.CELL))
            var gy := int(round((pos as Vector2).y / GridWorld.CELL))
            print("[PIVOT] +%s corner(%d,%d) at (%.0f,%.0f)  pivots=%d" % [
                _pivot_dir(pos), gx, gy, (pos as Vector2).x, (pos as Vector2).y, rope.pivots.size()])
    for pos in _prev_piv:
        if not _has_pos(cur, pos):
            var gx := int(round((pos as Vector2).x / GridWorld.CELL))
            var gy := int(round((pos as Vector2).y / GridWorld.CELL))
            print("[PIVOT] -%s corner(%d,%d) at (%.0f,%.0f)" % [
                _pivot_dir(pos), gx, gy, (pos as Vector2).x, (pos as Vector2).y])
    _prev_piv = cur.duplicate()

    # refresh ghosts for current pivots; age the rest out over PIVOT_GHOST_LIFE
    for pos in cur:
        var hit := false
        for g in _ghosts:
            if (g["pos"] as Vector2).distance_to(pos) < 0.5:
                g["life"] = PIVOT_GHOST_LIFE
                hit = true
                break
        if not hit:
            _ghosts.append({ "pos": pos, "dir": _pivot_dir(pos), "life": PIVOT_GHOST_LIFE })
    var k := 0
    while k < _ghosts.size():
        if not _has_pos(cur, _ghosts[k]["pos"]):
            _ghosts[k]["life"] -= delta
        if _ghosts[k]["life"] <= 0.0:
            _ghosts.remove_at(k)
        else:
            k += 1


# --- rope penetration probe (dev, opt-in) -----------------------------------

# Longest contiguous run of a segment that lies INSIDE a solid (px), plus the
# midpoint of that run. This is the real "how far the rope cuts through" measure;
# it does NOT collapse to ~0 at a convex corner the way dist-to-air-edge does.
func _seg_solid_chord(a: Vector2, b: Vector2) -> Dictionary:
    var d := b - a
    var dist := d.length()
    if dist < 0.5:
        return {"chord": 0.0, "mid": a}
    var steps := int(dist / 0.1) + 1
    var step_px := dist / float(steps)
    var best := 0.0
    var best_mid := a
    var run := 0
    var run_start := 0
    for s in range(0, steps + 1):
        if world.point_solid(a + d * (float(s) / float(steps))):
            if run == 0:
                run_start = s
            run += 1
            var chord := float(run) * step_px
            if chord > best:
                best = chord
                best_mid = a + d * (float(run_start + s) * 0.5 / float(steps))
        else:
            run = 0
    return {"chord": best, "mid": best_mid}


# Scan the drawn polyline (anchor -> pivots -> player) for the longest solid-chord.
# Edge-triggered logging: a settled scene logs once.
func _check_rope_pen() -> void:
    var pts: Array = [rope.anchor]
    for p in rope.pivots:
        pts.append(p["pos"])
    pts.append(player.position)

    var worst := 0.0
    var worst_seg := -1
    var worst_pt := Vector2.ZERO
    for i in range(pts.size() - 1):
        var r := _seg_solid_chord(pts[i], pts[i + 1])
        if r["chord"] > worst:
            worst = r["chord"]
            worst_seg = i
            worst_pt = r["mid"]

    if worst < PEN_CHORD_MIN:
        if worst < PEN_CHORD_MIN * 0.5:
            _pen_armed = true
        return
    if not _pen_armed:
        return
    _pen_armed = false
    _log_rope_pen(pts, worst, worst_seg, worst_pt)


func _log_rope_pen(pts: Array, chord: float, seg: int, pt: Vector2) -> void:
    var along := 0.0                                  # rope length from anchor to the cut
    for i in range(seg):
        along += (pts[i] as Vector2).distance_to(pts[i + 1])
    along += (pts[seg] as Vector2).distance_to(pt)
    var bend := 180.0                                 # bend angle at the corner entering this segment
    if seg >= 1 and seg < pts.size() - 1:
        var v1: Vector2 = ((pts[seg - 1] as Vector2) - (pts[seg] as Vector2)).normalized()
        var v2: Vector2 = ((pts[seg + 1] as Vector2) - (pts[seg] as Vector2)).normalized()
        bend = rad_to_deg(acos(clampf(v1.dot(v2), -1.0, 1.0)))
    var pc := world.world_to_cell(player.position)
    var xc := world.world_to_cell(pt)
    var piv := ""
    for p in rope.pivots:
        piv += "(%d,%d) " % [int(p["pos"].x), int(p["pos"].y)]

    print("[ROPE-PEN] solid_chord=%.2fpx (rope cuts through block)  seg=%d/%d  bend=%.0fdeg  along_rope=%.0fpx" % [
        chord, seg, pts.size() - 2, bend, along])
    print("  player cell=(%d,%d) pos=(%.0f,%.0f) on_ground=%s vel=(%.0f,%.0f)" % [
        pc.x, pc.y, player.position.x, player.position.y, str(player.on_ground),
        player.velocity.x, player.velocity.y])
    print("  rope_out=%.1f used=%.1f pivots=%d: [%s]" % [
        rope.rope_out, rope.used_length(player.position), rope.pivots.size(), piv.strip_edges()])
    print("  crossing px=(%.0f,%.0f) cell=(%d,%d)   (# solid · o pivot · P player · X crossing)" % [
        pt.x, pt.y, xc.x, xc.y])
    var pivot_cells := {}
    for p in rope.pivots:
        pivot_cells[Vector2i(floori(p["pos"].x / GridWorld.CELL), floori(p["pos"].y / GridWorld.CELL))] = true
    for cy in range(xc.y - 6, xc.y + 7):
        var line := "  "
        for cx in range(xc.x - 10, xc.x + 11):
            if cx == xc.x and cy == xc.y: line += "X"
            elif cx == pc.x and cy == pc.y: line += "P"
            elif pivot_cells.has(Vector2i(cx, cy)): line += "o"
            elif world.is_solid(cx, cy): line += "#"
            else: line += "."
        print(line)


func _draw() -> void:
    if rope == null or player == null:
        return

    # rope polyline: anchor -> pivots... -> player
    var pts: Array = [rope.anchor]
    for p in rope.pivots:
        pts.append(p["pos"])
    pts.append(player.position)
    for i in range(pts.size() - 1):
        draw_line(pts[i], pts[i + 1], Color(0.20, 0.50, 1.0), 2.0)

    draw_circle(rope.anchor, 5.0, Color(0.60, 0.40, 0.20))   # winch
    for p in rope.pivots:
        draw_circle(p["pos"], 4.0, Color(1.0, 0.30, 0.30))   # wrap corners

    # pivot linger: fading cyan ghosts of recent pivots, labelled with corner dir
    if pivot_linger:
        var font := ThemeDB.fallback_font
        for g in _ghosts:
            var a: float = clampf(g["life"] / PIVOT_GHOST_LIFE, 0.0, 1.0)
            draw_circle(g["pos"], 6.0, Color(0.2, 0.9, 1.0, a * 0.7))
            if font != null:
                draw_string(font, (g["pos"] as Vector2) + Vector2(7, -7), g["dir"],
                    HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.95, 1.0, a))

    # dig progress feedback on the targeted block
    if _dig_target.x >= 0 and _dig_timer > 0.0 and break_time > 0.0:
        var dc := GridWorld.CELL
        var r := Rect2(_dig_target.x * dc, _dig_target.y * dc, dc, dc)
        var prog := clampf(_dig_timer / break_time, 0.0, 1.0)
        draw_rect(r, Color(1, 1, 1, 0.12), true)
        draw_rect(Rect2(r.position, Vector2(dc * prog, 5)), Color(1.0, 0.9, 0.3, 0.9), true)

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
