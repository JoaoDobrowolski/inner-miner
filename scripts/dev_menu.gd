class_name DevMenu
extends PanelContainer

# Toggleable developer panel (F3) for live tuning without code edits or restarts.
# Data-driven: call add_slider/add_number/add_toggle/add_button once per control.
# Getter/setter are Callables so the panel stays decoupled from what it controls.
# refresh() re-syncs every widget from its getter (used after "reset to defaults").

var _rows: VBoxContainer
var _refreshers: Array[Callable] = []


func _ready() -> void:
    visible = false
    mouse_filter = Control.MOUSE_FILTER_STOP     # eat clicks so they don't dig
    _rows = VBoxContainer.new()
    add_child(_rows)
    var title := Label.new()
    title.text = "DEV MENU  (F3)"
    _rows.add_child(title)


func _row(label_text: String) -> HBoxContainer:
    var row := HBoxContainer.new()
    var name_lbl := Label.new()
    name_lbl.text = label_text
    name_lbl.custom_minimum_size.x = 110
    row.add_child(name_lbl)
    _rows.add_child(row)
    return row


func add_slider(label_text: String, lo: float, hi: float, step: float, getter: Callable, setter: Callable) -> void:
    var row := _row(label_text)
    var slider := HSlider.new()
    slider.min_value = lo
    slider.max_value = hi
    slider.step = step
    slider.value = float(getter.call())
    slider.custom_minimum_size.x = 150
    row.add_child(slider)
    var val_lbl := Label.new()
    val_lbl.custom_minimum_size.x = 48
    val_lbl.text = str(snappedf(float(getter.call()), step))
    row.add_child(val_lbl)
    slider.value_changed.connect(func(v: float) -> void:
        setter.call(v)
        val_lbl.text = str(snappedf(v, step)))
    _refreshers.append(func() -> void:
        slider.set_value_no_signal(float(getter.call()))
        val_lbl.text = str(snappedf(float(getter.call()), step)))


func add_number(label_text: String, getter: Callable, setter: Callable) -> void:
    var row := _row(label_text)
    var edit := LineEdit.new()
    edit.custom_minimum_size.x = 100
    edit.text = str(getter.call())
    row.add_child(edit)
    edit.text_submitted.connect(func(t: String) -> void:
        if t.is_valid_float():
            setter.call(t.to_float())
        edit.text = str(getter.call()))
    _refreshers.append(func() -> void:
        edit.text = str(getter.call()))


func add_toggle(label_text: String, getter: Callable, setter: Callable) -> void:
    var row := _row(label_text)
    var cb := CheckButton.new()
    cb.button_pressed = bool(getter.call())
    row.add_child(cb)
    cb.toggled.connect(func(pressed: bool) -> void:
        setter.call(pressed))
    _refreshers.append(func() -> void:
        cb.set_pressed_no_signal(bool(getter.call())))


func add_button(label_text: String, action: Callable) -> void:
    var btn := Button.new()
    btn.text = label_text
    btn.pressed.connect(action)
    _rows.add_child(btn)


func refresh() -> void:
    for r in _refreshers:
        r.call()


func toggle() -> void:
    visible = not visible
