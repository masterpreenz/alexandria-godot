class_name Talk
extends PanelContainer
## Talking with a villager (E beside one, when nothing else nearby takes E): a speech bubble over them, its tail
## pointing down at them, with their face,
## name and work, what they say, and Miko's replies (click, or 1 to 4): how things are, giving them something to eat,
## what they need, bye. While it's open the game runs slowly and they stand facing her. Every line comes from the
## language file (lang/<language>.json's talk.*), picked at random from its pool.

const RANGE := 1.1               ## units from her to talk to someone

const GOLD := Color(1.0, 0.82, 0.3)   ## the option that leads to a rumor

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


static var active: Talk


## Whether someone in reach of her has a story scene waiting (the elder after the fight): their talk comes before the
## banner or a chest there, so E goes to them.
static func scene_in_reach() -> bool:
	if active == null:
		return false
	var v := active._nearest()
	return v != null and not Scenes.for_speaker(v.person).is_empty()


func setup(w: World, m: Miko, hud: Node) -> void:
	active = self
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
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var i: int = event.keycode - KEY_1
			if i < _acts.size():
				_act_or_finish(_acts[i])
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var pressed := _pressed or WorldPrompts.take(prompt)
	_pressed = false
	if visible:
		_type_on()
		prompt.visible = false
		if who == null or not is_instance_valid(who) or who.in_bed:
			close()
			return
		_place()
		return
	var v := _nearest()
	prompt.visible = v != null
	if not prompt.visible:
		return
	# (someone with a story scene waiting: picked first when it's one of several)
	prompt.set_meta("first", not Scenes.for_speaker(v.person).is_empty())
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
	_show_who(v)
	# (someone unique: the day's first talk brings them a little closer, and they greet her their own way)
	var own := ""
	if Intimacy.has(v.person):
		if Intimacy.talked(v.person, world.clock.day() if world.clock != null else 0):
			_closer(Intimacy.DAILY_TALK)
		if not v._hungry():
			own = Intimacy.greeting(v.person)
	# (something the story's waiting for her to hand them: handed over now)
	Story.hand_over(v)
	# (a story scene waiting on this one: it plays instead)
	var scene := Scenes.for_speaker(v.person)
	if not scene.is_empty():
		_play(scene, 0)
	else:
		_show(own if own != "" else _greeting(v))
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
	var vals := {"miko": Miko.NAME, "name": v.person.name}
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
	_start_typing()
	for c in _choices.get_children():
		c.queue_free()
	_acts.clear()
	_add(Loc.t("talk.choice.how"), _ask_how)
	var food := _food_to_give()
	if food != "":
		_add(Loc.t("talk.choice.food", {"food": UiKit.resource_name(food).to_lower()}), _give_food.bind(food))
	# (only with a rumor to tell; the way to ask stands out: a gold border)
	if Rumors.active != null and Rumors.active.has_offer(who):
		_add(Loc.t("talk.choice.rumor"), _ask_rumor, true)
	# (someone unique: something of their own to talk about, and a gift)
	if Intimacy.has(who.person):
		_hearts()
		var topic := Intimacy.topic(who.person)
		if not topic.is_empty():
			_add(str(topic.ask), _ask_topic.bind(topic))
		_add(Loc.t("talk.choice.gift"), _pick_gift)
	# (one of her party: orders; a unique who's joined her before, or been asked by the story: come along)
	if Party.active != null and Party.active.has_member(who.person):
		_add("Chop or mine here", _order_gather)
		if Party.active.waiting.has(str(who.person.unique)): _add("Follow me", _order_follow)
		else: _add("Wait here", _order_wait)
		_add("Go home", _order_home)
		if float(who.person.get("hunger", 100.0)) < 90.0:
			_add("Have something to eat", _order_eat)
		if float(who.person.get("thirst", 100.0)) < 90.0:
			_add("Have a drink", _order_drink)
	elif Party.active != null and Party.willing(who.person) and not Party.active.full():
		_add("Come with me", _order_join)
	# (a spell book of theirs in Sera's bag: Miyu's book of water magic)
	var book := Companions.book_for(who.person, miko.bag)
	if not book.is_empty():
		_add(str(book.offer), _give_book.bind(book), true)
	_add(Loc.t("talk.choice.need"), _ask_need)
	_add(Loc.t("talk.choice.bye"), _say_bye)


func _add(text: String, act: Callable, gold := false) -> void:
	var tint: Variant = null
	if gold:
		tint = GOLD
	var b := HudStyle.button("%d   %s" % [_acts.size() + 1, text], 12, "pill", tint)
	if gold:
		var rim := Panel.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(GOLD, 0.1)
		box.border_color = GOLD
		box.set_border_width_all(maxi(2, roundi(2 * HudStyle.SCALE)))
		box.set_corner_radius_all(roundi(14 * HudStyle.SCALE))
		rim.add_theme_stylebox_override("panel", box)
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rim.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(rim)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 28 * HudStyle.SCALE
	b.pressed.connect(func() -> void: _act_or_finish(act))
	_choices.add_child(b)
	_acts.append(act)


# What they've heard: a rumor, if they have one to tell (it goes in the journal); else nothing new.
func _ask_rumor() -> void:
	var rumor: Dictionary = Rumors.active.offer_from(who)
	if rumor.is_empty():
		_show(Loc.pick("talk.reply.norumor", {"miko": Miko.NAME}))
		return
	who.show_mood("idea", 3.0)
	var told := Rumors.active.hear(str(rumor.id), who)
	FloatingText.spawn(world, "New rumor (J)", miko.position + Vector2(0, -2.2 * world.px), Color(1, 0.86, 0.45), 20, 2.0)
	# (a plea to answer: Sera's word is the one reply; she says it, and the talk's over)
	if str(rumor.get("accept", "")) != "":
		_show_replies(told, [[str(rumor.accept), _accept.bind(str(rumor.accept))]])
		return
	_show(told)


# Sera gives her word (a rumor's "accept"): said aloud, and the talk closes.
func _accept(line: String) -> void:
	close()
	var nd: Needs = miko.get_node_or_null("Needs")
	if nd != null:
		nd.say(line, 3.5)


# ---- Someone unique: their hearts, their own topics, gifts ----

func _hearts() -> void:
	_work.text = "%s   %s" % [Intimacy.hearts(who.person), JobsWindow.jobs_text(who.person)]


# A line of theirs with replies to pick from, in place of the usual choices.
func _show_replies(line: String, replies: Array) -> void:
	_line.text = line
	_start_typing()
	for c in _choices.get_children():
		c.queue_free()
	_acts.clear()
	for r in replies:
		_add(str(r[0]), r[1])


func _ask_topic(topic: Dictionary) -> void:
	who.show_mood("ellipsis", 3.0)
	var replies := []
	for r in topic.get("replies", []):
		replies.append([str(r.text), _answer_topic.bind(topic, r)])
	_show_replies(str(topic.says).format({"miko": Miko.NAME}), replies)


func _answer_topic(topic: Dictionary, reply: Dictionary) -> void:
	var gain := float(reply.get("gain", 0))
	var said := Intimacy.answer(who.person, topic, reply)
	_closer(gain)
	_show(said)


# What's in her bag to give, the ones they'd like best first (up to five), and never mind.
func _pick_gift() -> void:
	var day := world.clock.day() if world.clock != null else 0
	if Intimacy.gifted_today(who.person, day):
		_show(Intimacy.line(who.person, "giftSays", "already"))
		return
	var order := {"loved": 0, "liked": 1, "plain": 2, "disliked": 3}
	var have := Bag.RESOURCES.filter(func(r): return miko.bag.count(r) > 0)
	have.sort_custom(func(a, b): return int(order[Intimacy.taste(who.person, a)]) < int(order[Intimacy.taste(who.person, b)]))
	var replies := []
	for r in have.slice(0, 5):
		replies.append([UiKit.resource_name(r), _give_gift.bind(r)])
	replies.append([Loc.t("talk.choice.nevermind"), func(): _show(Loc.t("talk.reply.nevermind"))])
	_show_replies(Loc.t("talk.reply.gift.pick") if have.size() > 0 else Loc.t("talk.reply.gift.none"), replies)


func _give_gift(item: String) -> void:
	if not miko.bag.spend(item, 1):
		return
	var day := world.clock.day() if world.clock != null else 0
	var took := Intimacy.give(who.person, item, day)
	FloatingText.spawn(world, "-1 " + UiKit.resource_name(item), miko.position + Vector2(0, -1.6 * world.px), Color(0.96, 0.68, 0.32))
	who.show_mood({"loved": "affection", "liked": "cheerful", "plain": "relaxed", "disliked": "frustration"}[took[0]], 4.0)
	_closer(float(Intimacy.GIFT[took[0]]))
	_show(str(took[1]))


# Closer, or less so: said over them.
func _closer(by: float) -> void:
	if by == 0.0:
		return
	FloatingText.spawn(world, ("♥ +%d" if by > 0.0 else "♥ %d") % roundi(by), who.position + Vector2(0, -2.0 * world.px), Color(1.0, 0.55, 0.7) if by > 0.0 else Color(0.7, 0.7, 0.8), 20, 1.6)


# ---- Orders for her party ----

func _order_gather() -> void:
	var v := who
	close()
	if not v.errand_gather():
		v.show_mood("ellipsis", 2.5)
		FloatingText.spawn(world, "Nothing to chop or mine near here", miko.position + Vector2(0, -1.8 * world.px), Color(0.85, 0.8, 0.7))


func _order_wait() -> void:
	Party.active.wait_here(who.person, who.position)
	_show("I'll wait here.")


func _order_follow() -> void:
	Party.active.follow(who.person)
	_show("Right behind you.")


func _order_home() -> void:
	var p := who.person
	Party.active.leave(str(p.unique))
	who._stand(Villager.now(), 0.5)
	_show("I'll head back to the village, then.")


func _order_eat() -> void:
	var ate := Party.active.feed(who.person)
	_show(("Thank you, that's better." if ate != "" else "You've nothing to eat in your bag..."))


func _order_drink() -> void:
	_show("Ah... thank you." if Party.active.give_drink(who.person) else "Your pouch is empty. A well, or the river...")


# The book handed over: they learn its spells there and then, and say so (its scene, if it has one).
func _give_book(book: Dictionary) -> void:
	var got := Companions.give_book(who.person, book, miko.bag)
	who.show_mood("success", 4.0)
	if not got.is_empty():
		var names := PackedStringArray(got.map(func(sp): return Companions.spell_name(str(sp))))
		FloatingText.spawn(world, "%s learned %s" % [str(who.person.name), ", ".join(names)], who.position + Vector2(0, -2.2 * world.px), Color(0.65, 0.88, 1.0), 20, 3.0)
	var scene := Scenes.for_speaker(who.person)
	if not scene.is_empty():
		_play(scene, 0)
	else:
		_show(str(book.get("says", "")).format({"miko": Miko.NAME}))


func _order_join() -> void:
	Party.active.join(str(who.person.unique))
	who._follow_start(Villager.now())
	_show("Let's go!")


func _ask_how() -> void:
	var doing := who.activity().to_lower()
	who.show_mood("cheerful", 3.0)
	_show(Loc.pick("talk.reply.how", {"doing": doing, "doing_cap": who.activity(), "miko": Miko.NAME}))


# The best food in her bag to hand over (the villagers' own order of liking), or "".
func _food_to_give() -> String:
	for f in Villager.FOODS:
		if miko.bag.count(f[0]) > 0:
			return f[0]
	return ""


func _give_food(food: String) -> void:
	if float(who.person.get("hunger", 100.0)) >= 95.0:
		_show(Loc.pick("talk.reply.full", {"miko": Miko.NAME}))
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
	_show(Loc.pick("talk.reply.food", {"food": UiKit.resource_name(food), "miko": Miko.NAME}))


# What they need most: a bed, food in storage, tools for their work; else nothing.
func _ask_need() -> void:
	var p := who.person
	var key := "talk.need.nothing"
	if not bool(p.get("hasBed", true)):
		key = "talk.need.bed"
	elif who._food_in_storage() == 0:
		key = "talk.need.food"
	elif (Villager.jobs_of(p).has(Villager.Job.MINING) or Villager.jobs_of(p).has(Villager.Job.LUMBERING)) and int(p.get("toolsLeft", 0)) <= 0:
		key = "talk.need.tools"
	elif world.clock != null and world.clock.season() == GameClock.Season.WINTER and not bool(p.get("scarf", false)):
		key = "talk.need.scarf"
	who.show_mood("relaxed" if key == "talk.need.nothing" else "worried", 4.0)
	_show(Loc.pick(key, {"miko": Miko.NAME}))


# ---- Story scenes: a conversation played a line at a time (Continue, or 1) ----

# ---- The line typed out a letter at a time, a blip in the speaker's voice as it goes ----

const TYPE_SPEED := 45.0            ## letters a second (in real time: the world's slowed while she talks)
const BLIP_EVERY := 2               ## a blip every this many letters (spaces and stops are silent)
const BEEP := "res://assets/Sounds/Dialog/beep.wav"   ## the one beep (the user's), pitched for each voice
const SERA_PITCH := 1.15
## A voice (the beep's pitch) for each look (villagers.json's looks, in order): the man, the woman, Miyu, the old man,
## the old woman.
const LOOK_PITCH := [0.9, 1.05, 1.25, 0.78, 0.95]

var _voice := 1.0                   ## the speaker's pitch (0: no voice)
var _typed := -1.0                  ## letters shown so far (fractional); below 0 when the whole line's shown
var _typed_at := 0                  ## when the typing last moved on (msec)
var _blip: AudioStreamPlayer


func _voice_of(v: Villager) -> float:
	var look := int(v.person.get("look", 0))
	return float(LOOK_PITCH[clampi(look, 0, LOOK_PITCH.size() - 1)])


# A new line: typed out from its first letter.
func _start_typing() -> void:
	_typed = 0.0
	_typed_at = Time.get_ticks_msec()
	_line.visible_characters = 0


# Shows the rest of the line at once.
func _finish_typing() -> void:
	_typed = -1.0
	_line.visible_characters = -1


# A choice pressed: while the line's still being typed it shows the rest of it instead.
func _act_or_finish(act: Callable) -> void:
	if _typed >= 0.0:
		_finish_typing()
		return
	act.call()


# The typing moves on (in real time), a blip for every other letter that comes.
func _type_on() -> void:
	if _typed < 0.0:
		return
	var now := Time.get_ticks_msec()
	var was := int(_typed)
	_typed += (now - _typed_at) / 1000.0 * TYPE_SPEED
	_typed_at = now
	var text := _line.text
	var shown := mini(int(_typed), text.length())
	for i in range(was, shown):
		var ch := text.unicode_at(i)
		var letter := (ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch > 127
		if letter and i % BLIP_EVERY == 0:
			_play_blip()
			break   # (one a frame at most, however many letters came)
	if shown >= text.length():
		_finish_typing()
	else:
		_line.visible_characters = shown


func _play_blip() -> void:
	if _voice <= 0.0:
		return
	if _blip == null:
		_blip = AudioStreamPlayer.new()
		_blip.max_polyphony = 3
		_blip.volume_db = linear_to_db(0.5)
		_blip.stream = Sfx.stream(BEEP)
		add_child(_blip)
	_blip.pitch_scale = _voice * randf_range(0.97, 1.03)   # (a little different each time, as speech is)
	_blip.play()


## Their portrait (head and shoulders: the top of what's drawn in their standing frame, square).
func _face_of(v: Villager) -> Texture2D:
	return _face_from(int(v.s.idleDown))


## A portrait from one frame (sprite [param id]: a standing frame), head and shoulders, square.
func _face_from(id: int) -> Texture2D:
	if id < 0:
		return null
	var info: Dictionary = world.sprites[id]
	var at := AtlasTexture.new()
	at.atlas = world._texture(info.tex)
	var frame := Rect2i(int(info.rect[0]), int(info.rect[1]), int(info.rect[2]), int(info.rect[3]))
	var used := frame
	var img := at.atlas.get_image() if at.atlas != null else null
	if img != null:
		var r := img.get_region(frame).get_used_rect()
		if r.size.x > 0:
			used = Rect2i(frame.position + r.position, r.size)
	var side := mini(used.size.x, int(used.size.y * 0.5))
	at.region = Rect2(used.position.x + (used.size.x - side) / 2.0, used.position.y, side, side)
	return at


var _speaking: Node2D        ## who the bubble's tail points at (a scene's speaker; else whoever she's talking to)


# The window's head as [param v]'s: their face, name, work and ways.
func _show_who(v: Villager) -> void:
	_speaking = v
	_voice = _voice_of(v)
	_face.texture = _face_of(v)
	_name.text = str(v.person.name)
	_work.text = JobsWindow.jobs_text(v.person) + "".join(Traits.shown(v.person).map(func(x): return "  ·  " + str(x[0])))


# The window's head as a scene line's speaker: Sera (her own portrait), or whoever it is ("elder", a unique's id, or
# a name: Taro, Hana...), found among the villagers; just the name if they aren't about.
func _show_speaker(speaker: String) -> void:
	if speaker == "sera":
		_speaking = miko
		_voice = SERA_PITCH
		# (her standing frame, as anyone's: the same look as theirs)
		var idle: Array = miko.data.frames.get("idleDownLeft", [])
		_face.texture = _face_from(int(idle[0])) if not idle.is_empty() else HudStyle.icon("portrait")
		_name.text = Miko.NAME
		_work.text = "Shrine maiden"
		return
	var nm := str(Uniques.all().get(speaker, {}).get("name", speaker))
	for v in Villager.all:
		if is_instance_valid(v) and (str(v.person.get("unique", "")) == speaker or str(v.person.name) == nm):
			_show_who(v)
			return
	_speaking = who
	_voice = _voice_of(who) if who != null and is_instance_valid(who) else 1.0
	_face.texture = null
	_name.text = nm
	_work.text = ""


func _play(scene: Dictionary, i: int) -> void:
	var lines: Array = scene.lines
	if i >= lines.size():
		Scenes.done(scene)
		# (a scene that ends with them coming along: "joins", they're in her party from here)
		if str(scene.get("joins", "")) != "" and Party.active != null and Party.active.join(str(scene.joins)) and who != null and is_instance_valid(who):
			who._follow_start(Villager.now())
		var next := Scenes.for_speaker(who.person) if who != null and is_instance_valid(who) else {}
		if not next.is_empty():
			_play(next, 0)   # (another waiting on them: straight on into it)
			return
		if bool(scene.get("closes", false)):
			close()
			return
		if who != null and is_instance_valid(who):
			_show_who(who)
		_name.text = str(who.person.name) if who != null else ""
		_show(Loc.pick("talk.hello", {"miko": Miko.NAME, "name": who.person.name}) if who != null else "")
		return
	var line: Array = lines[i]
	var speaker := str(line[0])
	_show_speaker(speaker)
	_line.text = str(line[1]).format({"miko": Miko.NAME})
	_start_typing()
	for c in _choices.get_children():
		c.queue_free()
	_acts.clear()
	_add("Continue" if i < lines.size() - 1 else "...", _play.bind(scene, i + 1))


func _say_bye() -> void:
	if who != null and is_instance_valid(who):
		who.bark("talk.reply.bye", {"miko": Miko.NAME}, true)
	close()


# The top of [param n]'s head, a little above (a villager, or Sera).
func _head_of(n: Node2D) -> Vector2:
	if n is Villager:
		return n.position + Vector2(0, -(n as Villager)._top() - 0.15 * world.px)
	if n == miko and miko.art != null:
		return Vector2(miko.position.x, World.sprite_rect(miko.art).position.y - 0.15 * world.px)
	return n.position


# Over their head, a little to the side, kept on screen; the tail from its bottom edge down to their head.
func _place() -> void:
	reset_size()
	var k := HudStyle.SCALE
	var vp := get_viewport_rect().size
	var head := get_viewport().get_canvas_transform() * _head_of(_speaking if _speaking != null and is_instance_valid(_speaking) else who)
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
