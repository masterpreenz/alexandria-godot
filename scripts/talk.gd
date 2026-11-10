class_name Talk
extends PanelContainer
## Talking with a villager (E beside one, when nothing else nearby takes E): a speech bubble over them, its tail
## pointing down at them, with their face,
## name and work, what they say, and Miko's replies (click, or 1 to 4): how things are, giving them something to eat,
## what they need, bye. While it's open the game runs slowly and they stand facing her. Every line comes from the
## language file (lang/<language>.json's talk.*), picked at random from its pool.

const RANGE := 1.1               ## units from her to talk to someone

var world: World
var miko: Miko
var prompt: Label
var who: Villager = null         ## the one she's talking with
var _face: TextureRect
var _name: Label
var _work: Label
var _line: Label
var _choices: VBoxContainer
var _acts: Array = []            ## the replies shown: [callable]
var _pressed := false
var _speed_before := 1.0
var _tail: Tail                  ## the bubble's tail, down to their head


func setup(w: World, m: Miko, hud: Node) -> void:
	world = w
	miko = m
	var k := HudStyle.SCALE
	prompt = HudStyle.label("", 14, "bold")
	prompt.visible = false
	hud.add_child(prompt)
	WorldPrompts.register(prompt)
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(8 * k))
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(10 * k))
	col.add_child(head)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	head.add_child(frame)
	_face = TextureRect.new()
	_face.custom_minimum_size = Vector2(56, 56) * k
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_face)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(names)
	_name = HudStyle.label("", 16, "bold", HudStyle.color("accentLight"))
	names.add_child(_name)
	_work = HudStyle.label("", 11, "bold", HudStyle.color("muted"))
	names.add_child(_work)
	_line = HudStyle.label("", 13, "body", HudStyle.color("text"))
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size.x = 300 * k
	col.add_child(_line)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", int(4 * k))
	col.add_child(_choices)
	visible = false
	_tail = Tail.new()
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.visible = false
	hud.add_child(_tail)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_E and not visible and prompt.visible:
		_pressed = true
	elif visible:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			_say_bye()
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			var i: int = event.keycode - KEY_1
			if i < _acts.size():
				(_acts[i] as Callable).call()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var pressed := _pressed
	_pressed = false
	if visible:
		prompt.visible = false
		if who == null or not is_instance_valid(who) or who.in_bed:
			close()
			return
		_place()
		return
	var v := _nearest()
	# Only when nothing else here takes E (a chest, a fire, a field...).
	var other := false
	for l in WorldPrompts._labels:
		if l != prompt and is_instance_valid(l) and l.visible and l.text != "":
			other = true
	prompt.visible = v != null and not other
	if not prompt.visible:
		return
	prompt.text = Loc.t("talk.prompt", {"name": v.person.name})
	WorldPrompts.at(prompt, v.position + Vector2(0, -v._top() * 0.5))   # (the arrow to their middle)
	if pressed:
		open(v)


func _nearest() -> Villager:
	if miko.locked or CharacterPanel.up() or BuildMode.is_open():
		return null
	var best: Villager = null
	var best_d := RANGE * world.px
	for v in Villager.all:
		if not is_instance_valid(v) or not v.visible or v.in_bed or v.state == Villager.State.FIGHT or v.state == Villager.State.FLEE or v.state == Villager.State.ASLEEP:
			continue
		var dd := v.position.distance_to(miko.position)
		if dd < best_d:
			best_d = dd
			best = v
	return best


## Starts talking with [param v].
func open(v: Villager) -> void:
	who = v
	v.talking = true
	miko.locked = true
	_speed_before = Engine.time_scale
	Engine.time_scale = 0.25   # the world goes on, slowly
	var info: Dictionary = world.sprites[int(v.s.idleDown)]
	var at := AtlasTexture.new()
	at.atlas = world._texture(info.tex)
	# Head and shoulders: the top of what's drawn in the frame, square.
	var frame := Rect2i(int(info.rect[0]), int(info.rect[1]), int(info.rect[2]), int(info.rect[3]))
	var used := frame
	var img := at.atlas.get_image() if at.atlas != null else null
	if img != null:
		var r := img.get_region(frame).get_used_rect()
		if r.size.x > 0:
			used = Rect2i(frame.position + r.position, r.size)
	var side := mini(used.size.x, int(used.size.y * 0.5))
	at.region = Rect2(used.position.x + (used.size.x - side) / 2.0, used.position.y, side, side)
	_face.texture = at
	_name.text = str(v.person.name)
	_work.text = Loc.t("job.%d" % int(v.person.get("job", 0)))
	_show(_greeting(v))
	visible = true
	_tail.visible = true
	move_to_front()
	_tail.move_to_front()


func close() -> void:
	visible = false
	_tail.visible = false
	if who != null and is_instance_valid(who):
		who.talking = false
	who = null
	miko.locked = false
	Engine.time_scale = _speed_before


# What they open with: by how they are (hungry, worn out, no bed), else a plain hello.
func _greeting(v: Villager) -> String:
	var vals := {"miko": "Miko", "name": v.person.name}
	if v._hungry():
		return Loc.pick("talk.hello.hungry", vals)
	if v.chill() > 0:
		return Loc.pick("talk.hello.cold", vals)
	if float(v.person.get("energy", 100.0)) < 30.0:
		return Loc.pick("talk.hello.tired", vals)
	if not bool(v.person.get("hasBed", true)):
		return Loc.pick("talk.hello.homeless", vals)
	return Loc.pick("talk.hello", vals)


# Shows what they say, and Miko's replies under it.
func _show(line: String) -> void:
	_line.text = line
	for c in _choices.get_children():
		c.queue_free()
	_acts.clear()
	_add(Loc.t("talk.choice.how"), _ask_how)
	var food := _food_to_give()
	if food != "":
		_add(Loc.t("talk.choice.food", {"food": UiKit.resource_name(food).to_lower()}), _give_food.bind(food))
	_add(Loc.t("talk.choice.need"), _ask_need)
	_add(Loc.t("talk.choice.bye"), _say_bye)


func _add(text: String, act: Callable) -> void:
	var b := HudStyle.button("%d   %s" % [_acts.size() + 1, text], 12, "pill")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 28 * HudStyle.SCALE
	b.pressed.connect(act)
	_choices.add_child(b)
	_acts.append(act)


func _ask_how() -> void:
	var doing := who.activity().to_lower()
	who.show_mood("cheerful", 3.0)
	_show(Loc.pick("talk.reply.how", {"doing": doing, "doing_cap": who.activity(), "miko": "Miko"}))


# The best food in her bag to hand over (the villagers' own order of liking), or "".
func _food_to_give() -> String:
	for f in Villager.FOODS:
		if miko.bag.count(f[0]) > 0:
			return f[0]
	return ""


func _give_food(food: String) -> void:
	if float(who.person.get("hunger", 100.0)) >= 95.0:
		_show(Loc.pick("talk.reply.full", {"miko": "Miko"}))
		return
	var fills := 20.0
	for f in Villager.FOODS:
		if f[0] == food:
			fills = float(f[1])
	if not miko.bag.spend(food, 1):
		return
	who.person.hunger = minf(100.0, float(who.person.get("hunger", 0.0)) + fills)
	FloatingText.spawn(world, "-1 " + UiKit.resource_name(food), miko.position + Vector2(0, -1.6 * world.px), Color(0.96, 0.68, 0.32))
	who.show_mood("affection", 4.0)
	_show(Loc.pick("talk.reply.food", {"food": UiKit.resource_name(food), "miko": "Miko"}))


# What they need most: a bed, food in storage, tools for their work; else nothing.
func _ask_need() -> void:
	var p := who.person
	var key := "talk.need.nothing"
	if not bool(p.get("hasBed", true)):
		key = "talk.need.bed"
	elif who._food_in_storage() == 0:
		key = "talk.need.food"
	elif int(p.get("job", 0)) in [Villager.Job.MINING, Villager.Job.LUMBERING] and int(p.get("toolsLeft", 0)) <= 0:
		key = "talk.need.tools"
	elif world.clock != null and world.clock.season() == GameClock.Season.WINTER and not bool(p.get("scarf", false)):
		key = "talk.need.scarf"
	who.show_mood("relaxed" if key == "talk.need.nothing" else "worried", 4.0)
	_show(Loc.pick(key, {"miko": "Miko"}))


func _say_bye() -> void:
	if who != null and is_instance_valid(who):
		who.bark("talk.reply.bye", {"miko": "Miko"}, true)
	close()


# Over their head, a little to the side, kept on screen; the tail from its bottom edge down to their head.
func _place() -> void:
	reset_size()
	var k := HudStyle.SCALE
	var vp := get_viewport_rect().size
	var head := get_viewport().get_canvas_transform() * (who.position + Vector2(0, -who._top() - 0.15 * world.px))
	var at := head + Vector2(-60 * k, -size.y - 34 * k)
	at.x = clampf(at.x, 8.0, vp.x - size.x - 8.0)
	at.y = clampf(at.y, 8.0, vp.y - size.y - 8.0)
	position = at.round()
	# The tail's root on the bubble's bottom edge, near the head, its tip at the head.
	var root_x := clampf(head.x, position.x + 24 * k, position.x + size.x - 40 * k)
	_tail.from = Vector2(root_x, position.y + size.y - 3 * k)
	_tail.width = 22 * k
	_tail.tip = head
	_tail.queue_redraw()


## The bubble's tail: a wedge from the bubble down to the speaker, in the panel's colours.
class Tail extends Control:
	var from := Vector2.ZERO
	var tip := Vector2.ZERO
	var width := 22.0

	func _draw() -> void:
		var fill := Color8(28, 20, 16, 244)
		var edge := Color8(90, 70, 50, 255)
		var a := from + Vector2(-width / 2.0, 0)
		var b := from + Vector2(width / 2.0, 0)
		draw_colored_polygon(PackedVector2Array([a, b, tip]), fill)
		draw_line(a, tip, edge, 2.0, true)
		draw_line(b, tip, edge, 2.0, true)
