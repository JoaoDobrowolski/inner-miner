extends SceneTree

# BUG-01 winding-sign diagnosis / regression test.
#
# Reconstructs the user's geometry: anchor=winch (784,32), block A at cell (22,3)
# -> A-SE pivot (738,130), player swinging below-left. The last pivot is wrapped
# on A-SE. We sweep player positions that have a CLEAR line of sight back to the
# previous attach point (the anchor here) and classify each by winding:
#   * same-winding  -> rope is STILL genuinely wrapped on that corner.
#   * reversed      -> player swung past the corner; the wrap should release.
#
# OLD rule (LOS only): releases on every clear-LOS point  -> drops same-winding
#   points too == BUG-01 (the illegal shortcut the user reported).
# NEW rule (LOS + winding gate): releases only reversed-winding points.
#
# We also call the REAL Rope._update_wrap per point so this doubles as a before/
# after check: run it before the fix (expect same-winding points DROPPED) and
# after the fix (expect same-winding points KEPT).

const C := 32
const W := 48
const H := 220

var world
var rope


func _initialize() -> void:
    print("=== BUG-01 winding-sign diagnosis ===")
    _build([Vector2i(22, 3)])
    var anchor: Vector2 = rope.anchor
    var pse: Vector2 = rope._corner_point(23, 4)        # A-SE pivot point (738,130)
    print("  anchor=%s  A-SE pivot=%s  convex=%s" % [
        str(anchor), str(pse), str(rope._is_convex_corner(23, 4))])

    # Sanity: induce a REAL wrap from a wrap-side blocked-LOS position and read
    # the sign the game assigns, so the test uses the engine's own convention.
    rope.pivots.clear()
    rope.rope_out = 1e9
    rope._update_wrap(Vector2(600, 200))
    var stored := 1.0
    var found := false
    for p in rope.pivots:
        if (p["pos"] as Vector2).distance_to(pse) < 4.0:
            stored = p["sign"]
            found = true
    print("  induced wrap -> pivots=%d  A-SE found=%s  stored_sign=%.0f" % [
        rope.pivots.size(), str(found), stored])

    # Sweep.
    var same_total := 0          # clear-LOS, same winding (rope still wrapped)
    var rev_total := 0           # clear-LOS, reversed winding (should release)
    var same_dropped := 0        # real _update_wrap dropped a still-wrapped pivot (BUG count)
    var rev_dropped := 0         # real _update_wrap released a reversed pivot (correct count)
    var sample_bug := Vector2.ZERO
    for py in range(120, 340, 2):
        for px in range(400, 784, 2):
            var pl := Vector2(px, py)
            if _solid(pl):
                continue
            if rope._los_blocked(anchor, pl):
                continue                                # LOS blocked: neither rule releases
            var cur := signf((pse - anchor).cross(pl - pse))
            var same := cur == stored

            # Drive the REAL release logic on a freshly-wrapped single pivot.
            rope.pivots = [{ "pos": pse, "sign": stored }]
            rope.rope_out = 1e9
            rope._update_wrap(pl)
            var kept := false
            for p in rope.pivots:
                if (p["pos"] as Vector2).distance_to(pse) < 4.0:
                    kept = true
            if same:
                same_total += 1
                if not kept:
                    same_dropped += 1
                    if sample_bug == Vector2.ZERO:
                        sample_bug = pl
            else:
                rev_total += 1
                if not kept:
                    rev_dropped += 1

    print("  clear-LOS SAME-winding (rope still wrapped): %d  | real engine DROPPED %d  <- BUG count" % [
        same_total, same_dropped])
    print("  clear-LOS REVERSED-winding (should release):  %d  | real engine RELEASED %d  (correct)" % [
        rev_total, rev_dropped])
    if sample_bug != Vector2.ZERO:
        print("  e.g. BUG point player=%s : clear LOS to anchor yet still wrapped on A-SE" % str(sample_bug))
    print("=== expect AFTER fix: BUG count == 0, RELEASED == %d ===" % rev_total)
    quit()


func _row(x0: int, x1: int, y: int) -> Array:
    var out: Array = []
    for x in range(x0, x1 + 1):
        out.append(Vector2i(x, y))
    return out


func _build(solids: Array) -> void:
    world = GridWorld.new()
    world.cells = PackedByteArray()
    world.cells.resize(W * H)
    world.cells.fill(0)
    for s in solids:
        var v: Vector2i = s
        world.set_cell(v.x, v.y, 2)
    rope = Rope.new(world, Vector2(784, 32), 500.0 * 16.0)


func _solid(p: Vector2) -> bool:
    return world.is_solid(floori(p.x / C), floori(p.y / C))
