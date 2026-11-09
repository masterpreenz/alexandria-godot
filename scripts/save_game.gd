class_name SaveGame
extends Node
## Saving in play (from Unity's SaveGame): F5 quick-saves, F8 quick-loads, Esc opens the save menu ([SaveMenu]); it
## autosaves every few minutes, as each new day starts, and on quitting. A small notice says when it saved or loaded,
## and "Saving…" shows in the corner while it does. Loading a save starts the scene again from it; a new game starts
## it from the beginning (the autosave and quick save are cleared; named saves are kept).
##
## A run for a screenshot (--shot) never writes saves, and starts from the bundled save unless --slot names one.

const AUTOSAVE_MINUTES := 5.0

static var active: SaveGame

var game: Node
var world: World
var miko: Miko
var _next_autosave := 0.0
var _last_day := -1
var _notice: PanelContainer
var _notice_text: Label
var _notice_until := -1.0
var _saving: Label
var _saving_since := -10.0
var _started := 0.0


static func testing() -> bool:
	return Shots.arg("shot") != "" and Shots.arg("allowsave") == ""


func setup(g: Node, w: World, who: Miko, hud: Node) -> void:
	game = g
	world = w
	miko = who
	active = self
	process_mode = Node.PROCESS_MODE_ALWAYS   # its notices keep up while the menu has the game paused
	_notice = PanelContainer.new()
	_notice.add_theme_stylebox_override("panel", HudStyle.piece("pillPlain"))
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_text = HudStyle.label("", 12, "bold")
	_notice.add_child(_notice_text)
	_notice.visible = false
	hud.add_child(_notice)
	_saving = HudStyle.label("", 12, "bold")
	_saving.visible = false
	hud.add_child(_saving)
	_started = _now()
	_next_autosave = _now() + AUTOSAVE_MINUTES * 60.0
	get_tree().auto_accept_quit = false
	if SaveSystem.loaded_slot != "":
		notice("Loaded" if SaveSystem.loaded_slot != SaveSystem.AUTO else "Welcome back", false)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"save_game.process", __t)


func _process_timed(delta: float) -> void:
	var t := _now()
	if get_tree().paused:
		_next_autosave += delta
	else:
		SaveSystem.play_seconds += delta
	if t >= _next_autosave and not get_tree().paused:
		_next_autosave = t + AUTOSAVE_MINUTES * 60.0
		save(SaveSystem.AUTO, true)
	# A fresh day is a good moment to keep: autosave as it starts.
	if world.clock != null:
		var day := world.clock.day()
		if _last_day >= 0 and day > _last_day:
			save(SaveSystem.AUTO, true)
			_next_autosave = t + AUTOSAVE_MINUTES * 60.0
		_last_day = day
	var vp := get_viewport().get_visible_rect().size
	if _notice.visible:
		_notice.reset_size()
		_notice.position = Vector2((vp.x - _notice.size.x) / 2.0, 64.0 * HudStyle.SCALE).round()
		if t > _notice_until:
			_notice.visible = false
	if _saving.visible:
		var a := t - _saving_since
		if a > 1.8:
			_saving.visible = false
		else:
			_saving.text = ("Saving" + ".".repeat(1 + int(a * 3.0) % 3)) if a < 1.2 else "Saved"
			_saving.modulate.a = clampf(minf(a / 0.2, (1.8 - a) / 0.35), 0.0, 1.0)
			_saving.reset_size()
			_saving.position = Vector2(vp.x - _saving.size.x - 22.0, vp.y - _saving.size.y - 18.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			save(SaveSystem.QUICK)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F8:
			load_slot(SaveSystem.QUICK)
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Quitting keeps where she was, for next time.
		save(SaveSystem.AUTO, true)
		get_tree().quit()


# ---- Saving ----

## Saves into [param slot] ([param quiet]: an autosave, just the corner); named [param name] (null keeps its name).
func save(slot: String, quiet := false, nm: Variant = null) -> bool:
	if testing():
		return false
	# Not in a run's first seconds: some parts of the game (the farms, the fires, the forest) are still being put back.
	if _now() - _started < 3.0:
		return false
	var summary := summarise()
	var given: String = str(nm).strip_edges().left(32) if nm != null else ""
	if given == "" and SaveSystem.exists(slot):
		given = str(SaveSystem.peek(slot).get("name", ""))
	summary.name = given if given != "" else SaveSystem.default_name(slot, summary)
	var err := SaveSystem.write(slot, summary, capture())
	if err != "":
		notice("Couldn't save: " + err, true)
		return false
	if not quiet:
		notice("Quick saved" if slot == SaveSystem.QUICK else "Saved", false)
	_saving_since = _now()
	_saving.visible = true
	return true


## Loads [param slot]: the scene starts again from it.
func load_slot(slot: String) -> bool:
	if not SaveSystem.exists(slot):
		notice("No save to load", true)
		return false
	if SaveSystem.read(slot).is_empty():
		notice("Couldn't load: the save won't open", true)
		return false
	restart(slot)
	return true


## A new game: clears the autosave and quick save (named saves are kept) and starts from the beginning.
func new_game() -> void:
	SaveSystem.delete(SaveSystem.AUTO)
	SaveSystem.delete(SaveSystem.QUICK)
	restart("new")


func restart(slot: String) -> void:
	SaveSystem.pending = slot
	SaveSystem.reset_start()
	Engine.time_scale = 1.0
	get_tree().paused = false
	_reset_statics()
	get_tree().reload_current_scene()


# What a run keeps in statics, forgotten before the scene starts again.
func _reset_statics() -> void:
	Villager.all.clear()
	Villager.claimed.clear()
	Villager.gathering.clear()
	Villager.out_of_reach.clear()
	Villager.tending.clear()
	Villager.cooking_at.clear()
	Villager.lighting.clear()
	Villager.building.clear()
	Villager.unreachable.clear()
	Villager.crafting_now.clear()
	Creature.all.clear()
	Rabbit.rabbits.clear()
	Gatherable.all.clear()
	Pickup.all.clear()
	Fainting.looted.clear()
	Fainting.LostBag.active = null
	HelpHints.shown.clear()
	Kitchen.targets.clear()
	Needs.occupants.clear()
	Exploration.show_all = false


func summarise() -> Dictionary:
	var place := "The wilds"
	var room := world.village.room_kind_at(miko.position)
	if room != "":
		place = {"Storage": "Storage house", "Shelter": "Shelter", "House": "House"}.get(room, room)
	elif world.village.contains(miko.position):
		place = "The village"
	var t := Time.get_datetime_dict_from_system(true)
	return {
		"savedAt": "%04d-%02d-%02dT%02d:%02d:%02d.0000000Z" % [t.year, t.month, t.day, t.hour, t.minute, t.second],
		"playSeconds": SaveSystem.play_seconds,
		"day": world.clock.day() if world.clock != null else 1,
		"season": GameClock.SEASON_NAMES[world.clock.season()] if world.clock != null else "",
		"time": world.clock.time_text() if world.clock != null else "",
		"level": miko.stats.level,
		"place": place,
		"name": "",
	}


## Every part of the game as its section of the save (the same sections, in the same shape, as Unity's).
func capture() -> Dictionary:
	var s := {}
	var at := func(path: String) -> Node: return game.get_node_or_null(path)
	var put := func(key: String, node: Variant, f: Callable) -> void:
		if node != null:
			s[key] = f.call(node)
	@warning_ignore("incompatible_ternary")
	s["world.clock"] = world.clock.to_json() if world.clock != null else null
	put.call("world.explored", at.call("Exploration"), func(n): return n.to_json())
	s["world.floors"] = world.floors.to_json()
	s["world.walls"] = world.walls.to_json()
	s["world.props"] = world.props.to_json()
	if world.roofs != null:
		s["world.roofs"] = world.roofs.to_json()
	s["village"] = world.village.to_json()
	var farming: Farming = miko.get_node_or_null("Farming")
	put.call("world.farms", farming, func(n): return n.to_json())
	put.call("village.people", at.call("Villagers"), func(n): return n.to_json())
	put.call("world.fires", miko.get_node_or_null("Fires"), func(n): return n.to_json())
	put.call("village.blueprints", at.call("Construction"), func(n): return n.to_json())
	s["village.kitchen"] = Kitchen.to_json(farming.rotation if farming != null else ["Potato"])
	put.call("world.rabbits", at.call("RabbitPens"), func(n): return n.to_json())
	put.call("world.forest", at.call("Corruption"), func(n): return n.to_json())
	s["player.bag"] = miko.bag.to_json()
	s["player.skills"] = LifeSkills.to_json()
	put.call("player.hotbar", at.call("Hud/Hotbar"), func(n): return n.to_json())
	s["player.stats"] = miko.stats.to_json()
	s["world.ground"] = Pickup.to_json(world)
	var needs: Needs = miko.get_node_or_null("Needs")
	s["player"] = JSON.stringify({"x": miko.position.x / world.px, "y": -miko.position.y / world.px,
		"hunger": needs.hunger if needs != null else 100.0, "energy": needs.energy if needs != null else 100.0})
	s["help.shown"] = HelpHints.to_json()
	put.call("world.planted", miko.get_node_or_null("TreePlanter"), func(n): return n.to_json())
	s["player.life"] = Fainting.to_json(world)
	for k in s.keys():
		if s[k] == null:
			s.erase(k)
		else:
			s[k] = SaveSystem.tidy(s[k])
	return s


func notice(text: String, bad: bool) -> void:
	_notice_text.text = text
	_notice_text.add_theme_color_override("font_color", HudStyle.color("coral") if bad else HudStyle.color("text"))
	_notice.visible = true
	_notice_until = _now() + 1.8
