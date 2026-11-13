class_name Salvage
extends Node
## The overrun village's bookshelves: E by one searches it. The old woman's shelf (in the house on the west side,
## with two beds) holds the book of water magic Miyu went there to borrow: found once, into Sera's bag (or storage
## if her bag's full); the rest hold nothing worth carrying. Whether it's been found is in the chronicle
## ("water_tome_found").

const BOOK := "WaterTome"
const BOOK_SHELF := Vector2i(13, 8)      ## the old woman's shelf, in the overrun village's own cells
const SHELVES := ["Bookshelf", "WideBookshelf"]
const REACH := 1.4                       ## units from a shelf to search it
const NOTHING := [
	"Damp ledgers and a cookbook. Nothing worth carrying.",
	"Almanacs, swollen with the wet. Nothing here.",
	"Someone's letters, tied with string. You leave them be.",
]

var world: World
var miko: Miko
var prompt: Label
var _pressed := false
var _shelves: Array = []                 ## the overrun village's shelves (px), looked up again when props change
var _looked_at := -1


func setup(w: World, who: Miko, hud: Node) -> void:
	world = w
	miko = who
	prompt = HudStyle.label("", 14, "bold")
	prompt.visible = false
	hud.add_child(prompt)
	WorldPrompts.register(prompt)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and prompt.visible:
		_pressed = true
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"salvage.process", __t)


func _process_timed(_delta: float) -> void:
	var pressed := _pressed or WorldPrompts.take(prompt)
	_pressed = false
	prompt.visible = false
	# (only out there: nothing to do anywhere else)
	if not Wildlands.WEST_VILLAGE.grow(2).has_point(world.floors.cell_at(miko.position)) or miko.locked:
		return
	if world.props.version != _looked_at:
		_looked_at = world.props.version
		_shelves = []
		for nm in SHELVES:
			for at in world.props_named(nm):
				if Wildlands.WEST_VILLAGE.has_point(world.floors.cell_at(at)):
					_shelves.append(at)
	var near := Vector2.INF
	for at in _shelves:
		if miko.position.distance_to(at) < REACH * world.px and (near == Vector2.INF or miko.position.distance_to(at) < miko.position.distance_to(near)):
			near = at
	if near == Vector2.INF:
		return
	prompt.visible = true
	prompt.text = "E  Search the bookshelf"
	WorldPrompts.at(prompt, near + Vector2(0, -1.0 * world.px))
	if pressed:
		_search(near)


# What's on the shelf at [param at]: Miyu's book on the old woman's (once), else nothing much.
func _search(at: Vector2) -> void:
	var over := miko.position + Vector2(0, -2.0 * world.px)
	var ch := Chronicle.active
	var hers := world.floors.cell_at(at) == Wildlands.WEST_VILLAGE.position + BOOK_SHELF
	if hers and ch != null and not ch.happened("water_tome_found"):
		var slot := miko.bag.free_slot()
		if slot >= 0:
			miko.bag.items[slot] = BOOK
		else:
			world.village.store_crafted(BOOK)
		ch.record("water_tome_found")
		FloatingText.spawn(world, "The Water Spell Book: Miyu's book!", over, Color(0.6, 0.85, 1.0), 18, 2.5)
		return
	FloatingText.spawn(world, NOTHING[absi(hash(world.floors.cell_at(at))) % NOTHING.size()], over, Color(0.8, 0.8, 0.75), 14, 2.0)
