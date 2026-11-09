class_name VillageDesk
extends Node
## Miko's side of the village (from Unity's VillageInteractor): E at a chest opens the village storage (the
## [ChestWindow]), E at the town banner opens the [BannerPanel] (how big the village is, and growing it); walking
## into the village, or a room given to something (a storage house, a shelter), says so over her head.

const CHEST_RANGE := 1.1
const BANNER_RANGE := 1.7

var world: World
var miko: Miko
var prompt: Label
var chest_window: ChestWindow
var banner_panel: BannerPanel
var growth: VillageGrowth
var _pressed := false
var _esc := false
var _started := false
var _was_in := false
var _last_room := ""


func setup(w: World, who: Miko, hud: Node) -> void:
	world = w
	miko = who
	prompt = HudStyle.label("", 16, "bold")
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_top = -210
	prompt.offset_bottom = -180
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.visible = false
	hud.add_child(prompt)
	chest_window = ChestWindow.new()
	chest_window.name = "ChestWindow"
	hud.add_child(chest_window)
	chest_window.setup(w, who, hud)
	growth = VillageGrowth.new()
	growth.name = "VillageGrowth"
	w.add_child(growth)
	growth.setup(w, who, hud)
	banner_panel = BannerPanel.new()
	banner_panel.name = "BannerPanel"
	hud.add_child(banner_panel)
	banner_panel.setup(w, who, func():
		banner_panel.close()
		growth.begin())


## Whether one of its windows is up.
func any_open() -> bool:
	return chest_window.visible or banner_panel.visible or growth.active


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_pressed = true
		elif event.keycode == KEY_ESCAPE and (chest_window.visible or banner_panel.visible):
			_esc = true
			get_viewport().set_input_as_handled()


func _nearest_chest(range: float) -> Variant:
	var best: Variant = null
	var best_d := range * world.px
	for at in world.props_named("Chest"):
		var d: float = miko.position.distance_to(at)
		if d < best_d:
			best_d = d
			best = at
	return best


func _process(_delta: float) -> void:
	var pressed := _pressed
	var esc := _esc
	_pressed = false
	_esc = false
	_say_where_she_is()
	if growth.active:
		prompt.visible = false
		return
	var v := world.village
	# A chest, opened: the totals or the how-many box over it close first.
	if chest_window.visible:
		prompt.visible = false
		if _nearest_chest(CHEST_RANGE * 1.8) == null:
			chest_window.close()
		elif chest_window.asking():
			if esc:
				chest_window.cancel_ask()
		elif chest_window.totals_open():
			if esc or pressed:
				chest_window.show_totals(false)
		elif esc or pressed:
			chest_window.close()
		return
	if banner_panel.visible:
		prompt.visible = false
		if esc or pressed or miko.position.distance_to(v.centre()) > BANNER_RANGE * 1.8 * world.px:
			banner_panel.close()
		return
	var busy := miko.locked or CharacterPanel.up()
	var needs: Needs = miko.get_node_or_null("Needs")
	if needs != null and needs.sleeping():
		busy = true
	var chest: Variant = null if busy else _nearest_chest(CHEST_RANGE)
	if chest != null:
		prompt.visible = true
		if not v.contains(chest):
			prompt.text = "Outside the village: this chest isn't connected" if v.founded() else "Place a town banner to use chests"
			return
		prompt.text = "E  Open chest"
		if pressed:
			chest_window.open()
		return
	if not busy and v.founded() and miko.position.distance_to(v.centre()) < BANNER_RANGE * world.px:
		prompt.visible = true
		prompt.text = "E  Town banner" if v.max_tier() else "E  Town banner  ·  grow the village"
		if pressed:
			banner_panel.open()
		return
	prompt.visible = false


# Says so when she walks into the village, or into a room given to something.
func _say_where_she_is() -> void:
	var v := world.village
	var inside := v.contains(miko.position)
	var room := v.room_kind_at(miko.position)
	if not _started:
		_started = true
		_was_in = inside
		_last_room = room
		return
	var over := miko.position + Vector2(0, -1.9 * world.px)
	if inside != _was_in:
		_was_in = inside
		FloatingText.spawn(world, "Entering the village" if inside else "Leaving the village", over, HudStyle.color("accentLight"))
	if room != _last_room:
		_last_room = room
		if room != "":
			FloatingText.spawn(world, "%s · %s" % [ROOM_NAMES[room], ROOM_PERKS[room]], over + Vector2(0, -0.3 * world.px), HudStyle.color("muted"))


const ROOM_NAMES := {"Storage": "Storage house", "Shelter": "Shelter", "House": "House"}
const ROOM_PERKS := {"Storage": "Chests here hold double", "Shelter": "Beds here rest better", "House": "Mixed use: give it to one thing for a bonus"}
