class_name RabbitHands
extends Node
## Miko and rabbits (from Unity's RabbitInteractor): by a rabbit out in the wild, E grabs it alive; by a rabbit pen, E
## lets in the live rabbits she's carrying, or (carrying none) butchers one for raw meat.

const PEN_RANGE := 2.1

var world: World
var miko: Miko
var pens: RabbitPens
var prompt: Label
var _pressed := false


func setup(w: World, who: Miko, p: RabbitPens, hud: Node) -> void:
	world = w
	miko = who
	pens = p
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt.add_theme_constant_override("outline_size", 6)
	if UiKit.body_font:
		prompt.add_theme_font_override("font", UiKit.body_font)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_top = -150
	prompt.offset_bottom = -120
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.add_child(prompt)


## Whether a rabbit or a pen is within reach of [param at] (E is theirs, not the miner's, then).
func claims(at: Vector2) -> bool:
	return Rabbit.nearest(at, Rabbit.GRAB_RANGE * world.px) != null or (pens != null and pens.nearest(at, PEN_RANGE * world.px) != null)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_pressed = true


func _process(_delta: float) -> void:
	var pressed := _pressed
	_pressed = false
	if miko.locked:
		_say("")
		return
	var r := Rabbit.nearest(miko.position, Rabbit.GRAB_RANGE * world.px)
	if r != null:
		_say("Press E to grab the rabbit")
		if pressed:
			r.grab()
			miko.bag.add("Rabbit", 1)
			FloatingText.spawn(world, "+1 Rabbit", miko.position + Vector2(0, -1.6 * world.px), Color(0.9, 0.8, 0.6))
		return
	var p := pens.nearest(miko.position, PEN_RANGE * world.px) if pens != null else null
	if p == null:
		_say("")
		return
	var at := p.at + Vector2(0, -1.2 * world.px)
	var carrying := miko.bag.count("Rabbit")
	var n := pens.count(p)
	var litter := pens.hours_to_litter(p)
	var status := "Rabbit pen  ·  %d/%d" % [n, RabbitPens.MOST]
	if litter >= 0.0:
		status += "  ·  a litter in %d h" % ceili(litter)
	elif n == 1:
		status += "  ·  needs two to breed"
	var space := RabbitPens.MOST - n
	if carrying > 0 and space > 0:
		var k := mini(carrying, space)
		_say("Press E to let %d rabbit%s in  ·  %s" % [k, "" if k == 1 else "s", status])
		if pressed:
			var went := pens.put_in(p, carrying)
			miko.bag.spend("Rabbit", went)
			FloatingText.spawn(world, "%d into the pen" % went, at, Color(0.9, 0.8, 0.6))
		return
	if n > 0:
		_say("Press E to butcher a rabbit for meat  ·  " + status)
		if pressed:
			var meat := pens.butcher(p)
			if meat > 0:
				miko.bag.add("Food", meat)
				FloatingText.spawn(world, "+%d Raw meat" % meat, miko.position + Vector2(0, -1.6 * world.px), Color(0.95, 0.6, 0.5))
		return
	_say(("The pen is full  ·  " + status) if carrying > 0 else "Rabbit pen  ·  empty: grab rabbits in the wild (E) and bring them here")


func _say(text: String) -> void:
	prompt.text = text
	prompt.visible = text != ""
