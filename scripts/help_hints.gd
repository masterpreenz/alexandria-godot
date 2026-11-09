class_name HelpHints
extends PanelContainer
## Help hints (from Unity's HelpHints): a small card above the hotbar with a tip, shown once, the first time it's
## useful (digging up potatoes, looting a seed, picking up raw meat or coming to a bonfire, getting hungry, getting
## tired). "Got it" closes it (it also fades after a while); "Don't show tips" turns them all off for good. More than
## one waits its turn. Which were shown is saved with the game (help.shown); tips turned off are kept across games.

const SHOW_FOR := 15.0
const FADE := 0.4
const OFF_FILE := "user://help_hints_off"

static var shown := {}

var world: World
var miko: Miko
var _waiting: Array = []
var _icon: TextureRect
var _title: Label
var _body: Label
var _shown_at := -1.0
var _next_check := 0.0
var _last := {}


static func off() -> bool:
	return FileAccess.file_exists(OFF_FILE)


func setup(w: World, who: Miko) -> void:
	world = w
	miko = who
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	custom_minimum_size = Vector2(420, 96) * HudStyle.SCALE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(36, 36) * HudStyle.SCALE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_title = HudStyle.label("", 13, "bold", HudStyle.color("accentLight"))
	col.add_child(_title)
	_body = HudStyle.label("", 12, "body")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(330, 0) * HudStyle.SCALE
	col.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(buttons)
	var off_b := Button.new()
	off_b.text = "Don't show tips"
	off_b.pressed.connect(func():
		var f := FileAccess.open(OFF_FILE, FileAccess.WRITE)
		if f: f.store_string("1")
		_waiting.clear()
		_close())
	buttons.add_child(off_b)
	var got := Button.new()
	got.text = "Got it"
	got.pressed.connect(_close)
	buttons.add_child(got)
	visible = false


## The hints already seen, from the save (Unity's help.shown: {shown: [...]}).
static func from_json(json: String) -> void:
	shown.clear()
	var d: Variant = JSON.parse_string(json)
	if d is Dictionary:
		for id in d.get("shown", []):
			shown[id] = true


## The hints already seen, as Unity's help.shown.
static func to_json() -> String:
	return JSON.stringify({"shown": shown.keys()})


## Shows a hint (once per game): [param id] marks it as seen.
func hint(id: String, icon: Texture2D, title: String, text: String) -> void:
	if off() or shown.has(id):
		return
	shown[id] = true
	_waiting.append([icon, title, text])


func _close() -> void:
	_shown_at = -1.0
	visible = false


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"help_hints.process", __t)


func _process_timed(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t >= _next_check:
		_next_check = t + 0.25
		_watch()
	# On show: fade in, hold, fade out, then the next. Just above the hotbar.
	if _shown_at >= 0.0:
		var vp := get_viewport_rect().size
		position = Vector2((vp.x - size.x) / 2.0, vp.y - size.y - 104.0 * HudStyle.SCALE)
		var a := t - _shown_at
		modulate.a = a / FADE if a < FADE else (clampf((SHOW_FOR - a) / FADE, 0.0, 1.0) if a > SHOW_FOR - FADE else 1.0)
		if a >= SHOW_FOR:
			_close()
		return
	if _waiting.is_empty():
		return
	var h: Array = _waiting.pop_front()
	_icon.texture = h[0]
	_title.text = h[1]
	_body.text = h[2]
	visible = true
	modulate.a = 0.0
	reset_size()
	_shown_at = t


# Picked up just now (more than the bag held last look), or come to something a hint would help with.
func _watch() -> void:
	var bag := miko.bag
	var got := func(r: String) -> bool:
		var n := bag.count(r)
		var more := _last.has(r) and n > int(_last[r])
		_last[r] = n
		return more
	var potato: bool = got.call("Potato")
	var got_seed: bool = got.call("Seed")
	var meat: bool = got.call("Food")
	if potato:
		hint("potato", UiKit.resource_icon("Potato"), "Potatoes", "A potato is its own seed. Build a Farm Plot (B, Farming), then press E on it to plant one: it grows into 3 to 5 more. Or bake it at a bonfire.")
	if got_seed:
		hint("seed", UiKit.resource_icon("Seed"), "A tree seed", "Felled trees sometimes drop a seed. Press T to plant it, and a new tree grows there.")
	var fires: Fires = miko.get_node_or_null("Fires")
	var at_fire := fires != null and not fires.nearest(miko.position, 2.5 * world.px, true, true).is_empty()
	if meat or at_fire:
		hint("cook", UiKit.resource_icon("Meal"), "Warm food", "Cook raw meat at a bonfire (E beside one) for a warm meal: it fills far more hunger than raw meat.")
	var needs: Needs = miko.get_node_or_null("Needs")
	if needs != null and needs.hunger < 35.0:
		hint("hungry", UiKit.resource_icon("Meal"), "Getting hungry", "Eat from time to time: press F, or open the bag (I) and pick something to eat. A warm cooked meal fills the most.")
	if needs != null and needs.energy < 30.0 and not needs.sleeping():
		hint("tired", HudStyle.icon("moon"), "Getting tired", "Sleep in a bed (Z beside it) to get your energy back. Build one in build mode (B).")
