class_name Wells
extends Node
## The wells, and the water's edge (a river, a lake). At one, E: Sera drinks her fill, tops up her water pouch (five
## drinks, G, anywhere), and with a bucket in her bag fills it (up to [constant BUCKET_HOLDS] water: one waters a dry
## crop; with a mug, one is a drink away from the well, G). The villagers drink at the
## village's wells, and farmers fill a bucket at one before they water. Water isn't kept in storage: it's drawn.

const RANGE := 1.4                ## units from a well to use it
const BUCKET_HOLDS := 10
const SHORE := 1.2                ## units from the water's edge (a river, a lake) to drink and fill up there

static var active: Wells

var world: World
var miko: Miko
var prompt: Label
var _pressed := false


func setup(w: World, who: Miko, hud: Node) -> void:
	world = w
	miko = who
	active = self
	prompt = HudStyle.label("", 14, "bold")
	prompt.visible = false
	hud.add_child(prompt)
	WorldPrompts.register(prompt)


## The wells standing (px).
func all() -> Array:
	return world.props_named("Well")


## The village's wells (in it, or right by it).
func village() -> Array:
	return all().filter(func(at): return world.village.contains(at, 2.0))


## The village well nearest [param from], or INF.
func nearest(from: Vector2) -> Vector2:
	var best := Vector2.INF
	for at in village():
		if best == Vector2.INF or (at as Vector2).distance_to(from) < best.distance_to(from):
			best = at
	return best


static func has_bucket(bag: Bag) -> bool:
	return bag.items.has("Bucket")


## Something to drink the bucket's water from, away from the well: a mug. (Her water pouch is its own: Needs.pouch.)
static func has_mug(bag: Bag) -> bool:
	return bag.items.has("Mug")


## How much water she can carry for the crops: a bucket's worth, or none.
static func holds(bag: Bag) -> int:
	return BUCKET_HOLDS if has_bucket(bag) else 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and prompt.visible:
		_pressed = true
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var pressed := _pressed or WorldPrompts.take(prompt)
	_pressed = false
	prompt.visible = false
	if miko.locked or BuildMode.is_open() or CharacterPanel.up():
		return
	var near := Vector2.INF
	for at in all():
		if (at as Vector2).distance_to(miko.position) < RANGE * world.px and (near == Vector2.INF or (at as Vector2).distance_to(miko.position) < near.distance_to(miko.position)):
			near = at
	# (no well: the water's edge, a river or a lake, looked for now and then)
	var shore := false
	if near == Vector2.INF:
		var now := Time.get_ticks_msec() / 1000.0
		if now >= _next_shore:
			_next_shore = now + 0.2
			_shore_at = _water_by(miko.position)
		if _shore_at != Vector2.INF and _shore_at.distance_to(miko.position) < (SHORE + 0.6) * world.px:
			near = _shore_at
			shore = true
	if near == Vector2.INF:
		return
	var needs: Needs = miko.get_node_or_null("Needs")
	var carried := miko.bag.count("Water")
	var most := holds(miko.bag)
	var pouch := miko.bag.items.has("WaterPouch") and needs != null
	var bits := ["E  Drink"]
	if pouch:
		bits.append("fill the pouch (%d%%)" % roundi(needs.pouch))
	if most > 0:
		bits.append("fill the bucket (%d/%d)" % [carried, most])
	prompt.visible = true
	prompt.text = "  ·  ".join(bits)
	WorldPrompts.at(prompt, near + Vector2(0, (-0.6 if shore else -1.6) * world.px))
	if not pressed:
		return
	var said := []
	if needs != null and needs.thirst < Needs.MAX - 1.0:
		needs.thirst = Needs.MAX
		said.append("Thirst quenched")
	if pouch and needs.pouch < Needs.MAX - 0.5:
		needs.pouch = Needs.MAX
		said.append("Pouch filled")
	if Party.active != null and Party.active.fill_pouches():
		said.append("Party's pouches filled")
	if carried < most:
		miko.bag.add("Water", most - carried)
		said.append("Bucket filled")
	FloatingText.spawn(world, ", ".join(said) if not said.is_empty() else "Not thirsty", miko.position + Vector2(0, -1.8 * world.px), Color(0.55, 0.78, 1.0))
	if not said.is_empty():
		Sfx.play(world, Sfx.stream(Farming.WATER_SOUND), near, 0.5, 0.1)


var _next_shore := 0.0
var _shore_at := Vector2.INF


# The nearest open water (a river, a lake) within reach of [param at] while she stands on dry ground: where she'd
# dip the pouch. INF when there's none.
func _water_by(at: Vector2) -> Vector2:
	if world.water_depth(at) > 0.0:
		return Vector2.INF
	var best := Vector2.INF
	for i in 12:
		var a := i * TAU / 12.0
		for r in [0.6, 1.0, SHORE]:
			var p: Vector2 = at + Vector2(cos(a), sin(a) * 0.5) * float(r) * world.px
			if world.water_depth(p) > 0.05 and (best == Vector2.INF or p.distance_to(at) < best.distance_to(at)):
				best = p
	return best
