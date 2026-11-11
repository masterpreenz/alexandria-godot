class_name Wells
extends Node
## The wells. At one, E: Sera drinks her fill, and with a bucket in her bag fills it (up to [constant BUCKET_HOLDS]
## water: one waters a dry crop; with a mug, one is a drink away from the well, G). The villagers drink at the
## village's wells, and farmers fill a bucket at one before they water. Water isn't kept in storage: it's drawn.

const RANGE := 1.4                ## units from a well to use it
const BUCKET_HOLDS := 10

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


static func has_mug(bag: Bag) -> bool:
	return bag.items.has("Mug")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and prompt.visible:
		_pressed = true
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var pressed := _pressed
	_pressed = false
	prompt.visible = false
	if miko.locked or BuildMode.is_open() or CharacterPanel.up():
		return
	var near := Vector2.INF
	for at in all():
		if (at as Vector2).distance_to(miko.position) < RANGE * world.px and (near == Vector2.INF or (at as Vector2).distance_to(miko.position) < near.distance_to(miko.position)):
			near = at
	if near == Vector2.INF:
		return
	var needs: Needs = miko.get_node_or_null("Needs")
	var carried := miko.bag.count("Water")
	prompt.visible = true
	prompt.text = "E  Drink" + (("  ·  fill the bucket (%d/%d)" % [carried, BUCKET_HOLDS]) if has_bucket(miko.bag) else "  ·  (a bucket carries water)")
	WorldPrompts.at(prompt, near + Vector2(0, -1.6 * world.px))
	if not pressed:
		return
	var said := []
	if needs != null and needs.thirst < Needs.MAX - 1.0:
		needs.thirst = Needs.MAX
		said.append("Thirst quenched")
	if has_bucket(miko.bag) and carried < BUCKET_HOLDS:
		miko.bag.add("Water", BUCKET_HOLDS - carried)
		said.append("Bucket filled")
	FloatingText.spawn(world, ", ".join(said) if not said.is_empty() else "Not thirsty", miko.position + Vector2(0, -1.8 * world.px), Color(0.55, 0.78, 1.0))
	if not said.is_empty():
		Sfx.play(world, Sfx.stream(Farming.WATER_SOUND), near, 0.5, 0.1)
