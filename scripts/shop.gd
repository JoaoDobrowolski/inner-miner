class_name Shop
extends PanelContainer

# Surface upgrade shop. Progression lives on the miner (character stats), not on
# loot -- per the design decisions. Data-driven like DevMenu: register each stat
# once with getters/cost/apply; refresh() re-syncs labels and button state from
# the wallet so costs grey out when unaffordable or maxed.

var _rows: VBoxContainer
var _wallet_lbl: Label
var _refreshers: Array[Callable] = []

var wallet_getter: Callable          # func() -> int
var spend: Callable                  # func(cost: int) -> bool ; deducts and returns success


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP     # eat clicks so they don't dig/move
    _rows = VBoxContainer.new()
    add_child(_rows)
    var title := Label.new()
    title.text = "SUPERFÍCIE — MELHORIAS"
    _rows.add_child(title)
    _wallet_lbl = Label.new()
    _rows.add_child(_wallet_lbl)


# label: stat name. get_level: current level. max_level: cap. cost_of(level): price
# for the NEXT level. on_buy: applies the purchase (caller bumps its own state).
func add_upgrade(label_text: String, get_level: Callable, max_level: int, cost_of: Callable, on_buy: Callable) -> void:
    var row := HBoxContainer.new()
    var name_lbl := Label.new()
    name_lbl.custom_minimum_size.x = 210
    row.add_child(name_lbl)
    var btn := Button.new()
    btn.custom_minimum_size.x = 96
    row.add_child(btn)
    _rows.add_child(row)

    _refreshers.append(func() -> void:
        var lvl: int = int(get_level.call())
        name_lbl.text = "%s  Lv %d/%d" % [label_text, lvl, max_level]
        if lvl >= max_level:
            btn.text = "MAX"
            btn.disabled = true
        else:
            var cost: int = int(cost_of.call(lvl))
            btn.text = "$%d" % cost
            btn.disabled = int(wallet_getter.call()) < cost)

    btn.pressed.connect(func() -> void:
        var lvl: int = int(get_level.call())
        if lvl >= max_level:
            return
        var cost: int = int(cost_of.call(lvl))
        if spend.call(cost):
            on_buy.call()
        refresh())


func refresh() -> void:
    _wallet_lbl.text = "Carteira  $%d" % int(wallet_getter.call())
    for r in _refreshers:
        r.call()
