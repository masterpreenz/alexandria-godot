extends Scenario
## The party window: Miyu (or a villager standing in for her) joins Sera; the window opens (C) and says what it shows;
## "Wait here" and "Follow me" pressed in it, the party as it stands after each; her card under Sera's and her name
## under her feet in the world.
## Run with --window=partywindow.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	clock.forced = GameClock.Weather.CLEAR
	var pa := Party.active
	var p := Uniques.person(people, "miyu")
	if p.is_empty():
		p = people.people[0]
		print("Party window: no Miyu in this save; ", p.name, " stands in")
		p["unique"] = "miyu"
		p["name"] = "Miyu"
		if not Traits.has(p, "unique"):
			p["traits"] = Traits.of(p) + ["unique"]
	var body: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and v.person == p:
			body = v
	miko.place(body.position + Vector2(1.5, 0.5) * world.px)
	print("Party window: joined ", pa.join("miyu"), "; members ", pa.members)
	body._follow_start(Villager.now())
	for i in 60:
		await get_tree().process_frame
	var pw: PartyWindow = g.get_node("Hud/PartyWindow")
	var ev := InputEventKey.new()
	ev.keycode = KEY_C
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in 10:
		await get_tree().process_frame
	print("Party window: open after C ", pw.visible, " at ", pw.position, " size ", pw.size, " (screen ", get_viewport().get_visible_rect().size, ")")
	_print_window(pw)
	shot("open")
	_button(pw, "Wait here").pressed.emit()
	for i in 10:
		await get_tree().process_frame
	print("Party window: after Wait here, waiting ", pa.waiting, "; Miyu's at ", body.position, ", ", body.activity())
	# Sera walks off: where Miyu waits, from her.
	miko.place(miko.position + Vector2(9, 3) * world.px)
	for i in 30:
		await get_tree().process_frame
	_print_window(pw)
	shot("waiting")
	_button(pw, "Follow me").pressed.emit()
	for i in 10:
		await get_tree().process_frame
	print("Party window: after Follow me, waiting ", pa.waiting, "; ", body.activity())
	_print_window(pw)
	ev = InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in 120:
		await get_tree().process_frame
	print("Party window: open after Esc ", pw.visible)
	# Sera by her again: her name under her feet.
	miko.place(body.position + Vector2(1.2, 0.4) * world.px)
	for i in 30:
		await get_tree().process_frame
	var plates: Node2D = world.get_node("PartyNameplates")
	print("Party window: nameplates node ", plates != null, ", Miyu ", snappedf(body.position.distance_to(miko.position) / world.px, 0.1), " units from Sera, on screen at ", body.get_global_transform_with_canvas().origin)
	shot("world")
	# A click on her card opens it again.
	var cards: Control = null
	for c in g.get_node("Hud").get_children():
		if c is Party.PartyCards:
			cards = c
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = cards.get_global_rect().get_center()
	click.global_position = click.position
	Input.parse_input_event(click)
	var up := click.duplicate() as InputEventMouseButton
	up.pressed = false
	Input.parse_input_event(up)
	for i in 10:
		await get_tree().process_frame
	print("Party window: open after a click on the card ", pw.visible, " (card at ", cards.get_global_rect(), ", filter ", cards.mouse_filter, ")")
	pw.close()


func _button(pw: PartyWindow, text: String) -> Button:
	for b in pw.find_children("*", "Button", true, false):
		if (b as Button).text == text and not b.is_queued_for_deletion():
			return b
	return null


func _print_window(pw: PartyWindow) -> void:
	var lines: Array = []
	for n in pw.find_children("*", "", true, false):
		if n.is_queued_for_deletion():
			continue
		if n is Label and (n as Label).text != "":
			lines.append((n as Label).text)
		elif n is Button:
			lines.append("[%s%s]" % [(n as Button).text, " (off)" if (n as Button).disabled else ""])
	print("Party window shows: ", " / ".join(PackedStringArray(lines)))
