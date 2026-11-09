extends Node2D
## Miko about the exported world. The camera follows her (CameraFollow2D: a little above her, smoothed; the wheel
## zooms). The clock runs from the saved game (GameClock: 12 minutes a day, seasons, weather), and the sky follows it
## (SkyEffects: daylight, cloud shadows, rain, snow, storms). [ and ] move the clock an hour back or on; F6 cycles the weather.
## Command line: [code]-- --hour=h --weather=n --at=x,y --shot=file.png[/code] (see [Shots]).

@onready var world: World = $World
@onready var camera: Camera2D = $Camera
@onready var light: CanvasModulate = $Daylight
@onready var time_label: Label = $Hud/Time

var miko: Miko
var data: Dictionary
var clock: GameClock
var sky: SkyEffects
var snow: SnowCover
var follow_offset := Vector2.ZERO


func _ready() -> void:
	# The player's settings: sound, and the window (size, borderless fullscreen) once a run.
	Settings.load_settings()
	if Shots.arg("grass") != "": Settings.varied_grass = Shots.arg("grass") == "varied"
	Settings.apply_sound()
	Settings.route_sounds(get_tree())
	MapMarks.hide_particles(get_tree())
	if not _window_set and Shots.arg("shot") == "":
		_window_set = true
		Settings.apply_window()
	# Unity's post-processing (its scene volume) toned the picture down a little, with a slight vignette: the "Soft"
	# picture (Settings), on by default.
	_post_processing()
	# The loading screen, over everything while the game sets up and its shaders warm up.
	var loading := LoadingScreen.new()
	loading.name = "Loading"
	add_child(loading)
	# The key prompts beside what they're about, and the performance logger (F3), first so the rest can be measured.
	var prompts := WorldPrompts.new()
	prompts.name = "WorldPrompts"
	add_child(prompts)
	var perf := Perf.new()
	perf.name = "Perf"
	add_child(perf)
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/player.json"))
	miko = Miko.new()
	($WorldPrompts as WorldPrompts).setup(miko)
	miko.name = "Miko"
	world.things.add_child(miko)
	($Loading as LoadingScreen).set_world(world)
	miko.setup(world, data)
	world.player = miko
	# Her own layer: creatures pass by her rather than shove her about (only the fixed world blocks her).
	miko.collision_layer = 4
	miko.collision_mask = 1
	# Gathering, and her bag from the save.
	var miner := Miner.new()
	miner.name = "Miner"
	miko.add_child(miner)
	miner.setup(world, miko, world._load_json("res://data/gather.json").miner, $Hud)
	var sv: Dictionary = {"sections": SaveSystem.start_sections(world)}
	UiKit.setup(world)
	miko.bag.item_data = UiKit.data.items
	if sv.get("sections", {}).has("player.bag"):
		var equipped: Array = []
		if sv.sections.has("player.stats"):
			equipped = JSON.parse_string(sv.sections["player.stats"]).get("equipped", [])
		miko.bag.from_json(sv.sections["player.bag"], equipped)
	# Her stats and combat: casting from the hotbar, and HP and mana bars.
	var combat: Dictionary = world._load_json("res://data/combat.json")
	miko.stats = CharacterStats.new()
	miko.stats.name = "Stats"
	miko.add_child(miko.stats)
	miko.stats.setup(combat.character, combat.items)
	if sv.get("sections", {}).has("player.stats"):
		miko.stats.from_json(sv.sections["player.stats"])
	var caster := SpellCaster.new()
	caster.name = "Caster"
	world.add_child(caster)
	caster.setup(world, miko, miko.stats, combat.spells, combat.caster)
	HudStyle.setup(world)
	var hotbar := Hotbar.new()
	hotbar.name = "Hotbar"
	hotbar.theme = UiKit.theme
	$Hud.add_child(hotbar)
	hotbar.setup(world, caster, miko.bag, miko.stats)
	if sv.get("sections", {}).has("player.hotbar"):
		hotbar.from_json(sv.sections["player.hotbar"])
	# Her card, top left: portrait, level, coins, HP, mana, hunger and rest, her effects and skills cooling down.
	HudStyle.setup(world)
	var bars := PlayerCard.new()
	bars.name = "PlayerCard"
	$Hud.add_child(bars)
	bars.setup(world, miko, caster)
	# Levelling up: a golden moment over her.
	miko.stats.leveled_up.connect(func(lv): LevelUp.play(world, miko, lv))
	# Help hints, once each, above the hotbar.
	var hints := HelpHints.new()
	hints.name = "HelpHints"
	$Hud.add_child(hints)
	hints.setup(world, miko)
	if sv.get("sections", {}).has("help.shown"):
		HelpHints.from_json(sv.sections["help.shown"])
	# Doors open for her as she comes up to them (O keeps a house's open).
	var doors := Doors.new()
	doors.name = "Doors"
	add_child(doors)
	doors.setup(world, miko, (world._load_json("res://data/hud.json") if FileAccess.file_exists("res://data/hud.json") else {}).get("doors", {}), $Hud)
	# Her hunger, energy and sleep (F eats, G drinks tea, Z sleeps), and her life skills.
	if sv.get("sections", {}).has("player.skills"):
		LifeSkills.from_json(sv.sections["player.skills"])
	if FileAccess.file_exists("res://data/needs.json"):
		var needs := Needs.new()
		needs.name = "Needs"
		miko.add_child(needs)
		needs.setup(world, miko, world._load_json("res://data/needs.json"), $Hud)
		if sv.get("sections", {}).has("player"):
			var pl: Dictionary = JSON.parse_string(sv.sections.player)
			needs.set_levels(float(pl.get("hunger", Needs.MAX)), float(pl.get("energy", Needs.MAX)))
		bars.needs = needs
	# The fires (lighting them, cooking at bonfires) and the farm plots.
	if FileAccess.file_exists("res://data/farm.json"):
		var farm_data: Dictionary = world._load_json("res://data/farm.json")
		var fires := Fires.new()
		fires.name = "Fires"
		miko.add_child(fires)
		fires.setup(world, miko, farm_data, $Hud)
		if sv.get("sections", {}).has("world.fires"):
			fires.from_json(sv.sections["world.fires"])
		var farming := Farming.new()
		farming.name = "Farming"
		miko.add_child(farming)
		farming.setup(world, miko, farm_data, $Hud)
		if sv.get("sections", {}).has("world.farms"):
			farming.from_json(sv.sections["world.farms"])
		if sv.get("sections", {}).has("village.kitchen"):
			farming.rotation_from_json(sv.sections["village.kitchen"])
			Kitchen.from_json(sv.sections["village.kitchen"])
		# The mist rotting the forest, and the springs that heal it.
		var springs := Springs.new()
		springs.name = "Springs"
		add_child(springs)
		springs.setup(world, farm_data.get("springs", {}))
		var corruption := Corruption.new()
		corruption.name = "Corruption"
		add_child(corruption)
		corruption.setup(world, farm_data.get("corruption", {}))
		if sv.get("sections", {}).has("world.forest"):
			corruption.from_json(sv.sections["world.forest"])
	# The village: its edge shaded on the ground, its messages (bottom left), and food spoiling.
	var border := VillageBorder.new()
	border.name = "VillageBorder"
	border.setup(world)
	var log_panel := VillageLog.new()
	log_panel.name = "VillageLog"
	log_panel.theme = UiKit.theme
	$Hud.add_child(log_panel)
	var spoilage := Spoilage.new()
	spoilage.name = "Spoilage"
	add_child(spoilage)
	spoilage.setup(world, miko)
	# The villagers: who lives in which bed, and their days (Alt shows who's who).
	if FileAccess.file_exists("res://data/villagers.json"):
		var needs_data: Dictionary = world._load_json("res://data/needs.json") if FileAccess.file_exists("res://data/needs.json") else {}
		var villagers := Villagers.new()
		villagers.name = "Villagers"
		add_child(villagers)
		villagers.setup(world, world._load_json("res://data/villagers.json"), needs_data.get("beds", {}), needs_data.get("eatSound"))
		# The blueprints the villagers build from, and the workbenches they make things at.
		var build_data: Dictionary = world._load_json("res://data/build.json") if FileAccess.file_exists("res://data/build.json") else {}
		villagers.d["workbenches"] = build_data.get("workbenches", {})
		var construction := Construction.new()
		construction.name = "Construction"
		add_child(construction)
		construction.setup(world, build_data)
		if sv.get("sections", {}).has("village.blueprints"):
			construction.from_json(sv.sections["village.blueprints"])
		if Shots.arg("blueprint") != "":
			# A test plan by the banner: a few floor tiles and a wall, ready to build.
			var c0 := world.floors.cell_at(world.village.centre()) + Vector2i(3, -4)
			for i in 3:
				construction._add({"wall": false, "prop": false, "free": false, "x": c0.x + i, "y": c0.y, "type": "DarkBoards", "ready": true, "turned": false, "scale": 1.0})
			construction._add({"wall": true, "prop": false, "free": false, "x": c0.x, "y": c0.y, "alongY": false, "type": "BambooWall", "ready": true, "scale": 1.0})
		if sv.get("sections", {}).has("village.people"):
			villagers.from_json(sv.sections["village.people"])
		var tags := Villagers.Tags.new()
		tags.people = villagers
		tags.set_anchors_preset(Control.PRESET_FULL_RECT)
		tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tags.visible = Shots.arg("tags") != ""
		$Hud.add_child(tags)
		villagers.tags = tags
	# The crystals (teleporting, the cleansing crystals' clearings) and what of the world she's seen.
	var crystals := Crystals.new()
	crystals.name = "Crystals"
	add_child(crystals)
	crystals.setup(world, miko, $Hud)
	var explored := Exploration.new()
	explored.name = "Exploration"
	add_child(explored)
	explored.setup(world)
	if sv.get("sections", {}).has("world.explored"):
		explored.from_json(sv.sections["world.explored"])
	# Flinching when hit; fainting at 0 HP.
	miko.stats.hurt.connect(miko.flinch)
	var monsters: Dictionary = world._load_json("res://data/monsters.json") if FileAccess.file_exists("res://data/monsters.json") else {}
	world.set_meta("lost_bag_icon", int(monsters.get("lostBagIcon", -1)))
	if monsters.has("fainting"):
		var fainting := Fainting.new()
		fainting.name = "Fainting"
		miko.add_child(fainting)
		fainting.setup(world, miko, monsters.fainting, $Hud)
		# What she's picked up this life (it'd fall with her).
		if sv.get("sections", {}).has("player.life"):
			Fainting.from_json(world, sv.sections["player.life"])
	# The Character & Bag window (C or I) and the talents (P).
	var char_panel := CharacterPanel.new()
	char_panel.name = "CharacterPanel"
	char_panel.theme = UiKit.theme
	$Hud.add_child(char_panel)
	char_panel.setup(world, miko, $Hud)
	($Hud/Hotbar as Hotbar).panel = char_panel
	if Shots.arg("bag") != "":
		char_panel.toggle()
	# The village's windows: chests and the town banner (E), the jobs (J), and the workbenches (E at one).
	var desk := VillageDesk.new()
	desk.name = "VillageDesk"
	add_child(desk)
	desk.setup(world, miko, $Hud)
	var people: Villagers = get_node_or_null("Villagers")
	if people != null:
		var jobs := JobsWindow.new()
		jobs.name = "JobsWindow"
		$Hud.add_child(jobs)
		jobs.setup(world, people, miko.get_node_or_null("Farming"))
		var bench := WorkbenchWindow.new()
		bench.name = "WorkbenchWindow"
		$Hud.add_child(bench)
		bench.setup(world, miko, people.d.get("workbenches", {}), $Hud)
	# Where the save left her.
	var saved_game: Dictionary = {"sections": SaveSystem.start_sections(world)}
	if saved_game.get("sections", {}).has("player"):
		var pl: Dictionary = JSON.parse_string(saved_game.sections.player)
		miko.place(Vector2(float(pl.x) * world.px, -float(pl.y) * world.px))
	var at := Shots.arg("at")
	if at != "":
		var p := at.split(",")
		miko.place(Vector2(float(p[0]), float(p[1])))
	clock = GameClock.new()
	clock.name = "Clock"
	add_child(clock)
	clock.seconds_per_day = data.clock.secondsPerDay
	clock.hours = data.clock.startHour
	var save: Dictionary = {"sections": SaveSystem.start_sections(world)}
	if save.get("sections", {}).has("world.clock"):
		clock.from_json(save.sections["world.clock"])
	if Shots.arg("hour") != "":
		clock.set_hour(float(Shots.arg("hour")))
	if Shots.arg("weather") != "":
		clock.set_weather(int(Shots.arg("weather")))
	world.clock = clock
	# The monsters: slimes out of the mist, boars in the woods.
	var spawners := Spawners.new()
	spawners.name = "Spawners"
	add_child(spawners)
	spawners.setup(world, world._load_json("res://data/monsters.json") if FileAccess.file_exists("res://data/monsters.json") else {})
	if Shots.arg("nomonsters") != "":
		spawners.process_mode = Node.PROCESS_MODE_DISABLED
	# The rabbits in their holes, the pens, and grabbing them (E).
	var monsters_data: Dictionary = world._load_json("res://data/monsters.json") if FileAccess.file_exists("res://data/monsters.json") else {}
	var warren := Warren.new()
	warren.name = "Warren"
	add_child(warren)
	warren.setup(world, monsters_data)
	var pens := RabbitPens.new()
	pens.name = "RabbitPens"
	add_child(pens)
	pens.setup(world, monsters_data.get("rabbitPen", {}))
	if save.get("sections", {}).has("world.rabbits"):
		pens.from_json(save.sections["world.rabbits"])
	var hands := RabbitHands.new()
	hands.name = "RabbitHands"
	miko.add_child(hands)
	hands.setup(world, miko, pens, $Hud)
	# The time, the season and day, and the weather, top right.
	time_label.visible = false
	var time_card := TimeCard.new()
	time_card.name = "TimeCard"
	$Hud.add_child(time_card)
	time_card.setup(world, clock)
	# Build mode (B) and its bar.
	var build_mode := BuildMode.new()
	build_mode.name = "BuildMode"
	world.add_child(build_mode)
	build_mode.setup(world, miko, world._load_json("res://data/build.json") if FileAccess.file_exists("res://data/build.json") else {})
	var build_bar := BuildBar.new()
	build_bar.name = "BuildBar"
	$Hud.add_child(build_bar)
	build_bar.setup(build_mode, world, miko)
	# The world's own sounds (rivers, wind, villagers' steps) and build mode's drop-in sounds.
	var sounds_data: Dictionary = world._load_json("res://data/sounds.json") if FileAccess.file_exists("res://data/sounds.json") else {}
	build_mode.drop_sounds = sounds_data.get("drop", {})
	var world_sounds := WorldSounds.new()
	world_sounds.name = "WorldSounds"
	world.add_child(world_sounds)
	world_sounds.setup(world, miko, sounds_data)
	# The minimap over it, and the world map (M).
	var minimap := Minimap.new()
	minimap.name = "Minimap"
	$Hud.add_child(minimap)
	minimap.setup(world, miko, time_card)
	var world_map := WorldMap.new()
	world_map.name = "WorldMap"
	$Hud.add_child(world_map)
	world_map.setup(world, miko)
	# Planting trees (T), and the trees planted before.
	# Her staff smack (left click).
	var melee := Melee.new()
	melee.name = "Melee"
	miko.add_child(melee)
	melee.setup(world, miko)
	# The crystal necklace's light and clearing, while she wears one.
	var necklace := CrystalNecklace.new()
	necklace.name = "CrystalNecklace"
	miko.add_child(necklace)
	necklace.setup(world, miko)
	var planter := TreePlanter.new()
	planter.name = "TreePlanter"
	miko.add_child(planter)
	planter.setup(world, miko, $Hud)
	if save.get("sections", {}).has("world.planted"):
		planter.from_json(save.sections["world.planted"])
	# What was lying on the ground; saving (F5, F8, autosaves) and the save menu (Esc).
	if save.get("sections", {}).has("world.ground"):
		Pickup.from_json(world, save.sections["world.ground"])
	var saving := SaveGame.new()
	saving.name = "SaveGame"
	add_child(saving)
	saving.setup(self, world, miko, $Hud)
	var save_menu := SaveMenu.new()
	save_menu.name = "SaveMenu"
	$Hud.add_child(save_menu)
	save_menu.setup(saving)
	# The HUD that's always up goes behind the windows (the bag, talents, maps, chests...) that open over it.
	for n in ["Minimap", "PlayerCard", "Hotbar", "VillageLog", "HelpHints", "Time"]:
		var node := $Hud.get_node_or_null(n)
		if node != null:
			$Hud.move_child(node, 0)
	sky = SkyEffects.new()
	sky.name = "Sky"
	add_child(sky)
	sky.setup(world, clock, camera, light, data.sky, $Hud)
	snow = SnowCover.new()
	snow.name = "Snow"
	add_child(snow)
	snow.setup(world, clock, world._load_json("res://data/snow.json") if FileAccess.file_exists("res://data/snow.json") else {})
	if Shots.arg("snow") != "":
		snow.set_cover(float(Shots.arg("snow")))
	follow_offset = Vector2(data.camera.offset[0], data.camera.offset[1])
	# Unity's orthographic size is half the view's height, in units: the same view here.
	var view_h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	camera.zoom = Vector2.ONE * view_h / (2.0 * data.camera.ortho * world.px)
	# Locked on her, no easing: smoothed (Unity's 0.15 s follow), the view went on sliding a moment after she stopped
	# and eased to rest, the ground drifting under her.
	camera.position_smoothing_enabled = false
	# The camera is moved every frame to where she's drawn, so it isn't smoothed itself (that would lag it a tick).
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# With physics interpolation on, Godot moves the camera only on physics ticks unless told otherwise: then it lags
	# Miko by up to a tick and the world shakes as she moves. It follows her every drawn frame instead.
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	camera.position = miko.position + follow_offset
	camera.reset_smoothing()
	await get_tree().process_frame
	# The shaders warmed up behind the loading screen (not in test runs, unless asked for).
	if Shots.arg("shot") == "" or Shots.arg("loading") != "":
		var t0 := Time.get_ticks_msec()
		await loading.warm_up(self, world, miko, camera, Exploration.active.px_rect() if Exploration.active != null else Rect2(-20000, -10000, 40000, 20000))
		print("Shaders warmed up in %d ms" % (Time.get_ticks_msec() - t0))
	else:
		loading.queue_free()
	if Shots.arg("shot") != "":
		var walk := Shots.arg("walk")
		if walk != "":
			# Hold a direction for a moment first (for checking movement and collisions from the command line).
			var d := walk.split(",")
			miko.position += Vector2.ZERO
			for i in int(Shots.arg("steps", "60")):
				miko.velocity = Vector2(float(d[0]), float(d[1])).limit_length(1.0) * Vector2(1, miko.vertical_scale) * miko.walk_speed
				miko.moving = true
				miko.move_and_slide()
				await get_tree().physics_frame
			print("Miko at ", miko.position)
		if Shots.arg("cast") != "":
			# Cast a spell at a spot (dx,dy px from her) for testing, with a practice dummy standing there.
			var parts := Shots.arg("cast").split("@")
			var off := parts[1].split(",")
			var spot := miko.position + Vector2(float(off[0]), float(off[1]))
			var dummy := Damageable.new()
			dummy.position = spot
			world.things.add_child(dummy)
			dummy.setup(world, Damageable.Team.ENEMY, 200.0, 0.35 * world.px, 1.2 * world.px)
			dummy.dummy = true
			# --provoke: as if she'd hit it already (an attack shikigami only picks on those); --hurt=N: hurt her first.
			dummy.hit_by_player = Shots.arg("provoke") != ""
			dummy.damaged.connect(func(a): print("Dummy hit for ", a))
			if Shots.arg("hurt") != "":
				miko.stats.damage(float(Shots.arg("hurt")))
			var caster_node: SpellCaster = world.get_node("Caster")
			caster_node.cast_at(parts[0], spot)
			for i in int(Shots.arg("castframes", "60")):
				await get_tree().process_frame
			print("Mana ", miko.stats.mana, ", dummy hp ", dummy.hp, ", her hp ", miko.stats.hp, ", shield ", miko.stats.shield(), ", shikigami out ", Shikigami.active.size())
		if Shots.arg("monster") != "":
			# A monster at a spot (kind@dx,dy px from her: slime, large, boar) for testing; --strike=N: she hits it for
			# N first; --hurt=N: she's hurt first (N past her HP: she faints); run --frames frames.
			var mparts := Shots.arg("monster").split("@")
			var moff := mparts[1].split(",")
			var mspot := miko.position + Vector2(float(moff[0]), float(moff[1]))
			var md: Dictionary = world._load_json("res://data/monsters.json")
			@warning_ignore("incompatible_ternary")
			var m: Creature = Boar.spawn(world, md.boar, mspot) if mparts[0] == "boar" else Slime.spawn(world, md.slime, mparts[0] == "large", mspot, world.mist.power(mspot))
			await get_tree().physics_frame
			if Shots.arg("strike") != "":
				m.hit.hurt(float(Shots.arg("strike")), true)
			if Shots.arg("hurt") != "" and Shots.arg("cast") == "":
				miko.stats.damage(float(Shots.arg("hurt")))
			var hp0 := miko.stats.hp
			for i in int(Shots.arg("frames", "120")):
				await get_tree().process_frame
				if Shots.arg("trace") != "" and i % 20 == 0 and is_instance_valid(m):
					print(i, " ", m.position, " v ", m.velocity, " asleep ", m.asleep, " ", m.get("hopping"), " ", m.get("chasing"), " ", m.get("state"), " target ", m.get("target"), " rest ", m.get("rest_until"), " now ", Creature.now(), " physics ", Engine.get_physics_frames())
			@warning_ignore("incompatible_ternary")
			print("Monster ", m.name if is_instance_valid(m) else "gone", " hp ", m.hit.hp if is_instance_valid(m) else 0.0, "; her hp ", hp0, " -> ", miko.stats.hp, "; creatures ", Creature.all.size(), "; lost bag ", Fainting.LostBag.active != null)
		if Shots.arg("sleep") != "":
			# Lie down (on the nearest bed, if one's in reach) and sleep this many frames, for testing.
			var nd: Needs = miko.get_node("Needs")
			nd.lie_down()
			for i in int(Shots.arg("sleep")):
				await get_tree().process_frame
			print("Sleeping ", nd.sleep, " on ", nd._bed.get("type", "the ground"), "; energy ", nd.energy, " hunger ", nd.hunger, " at ", miko.position)
		if Shots.arg("wait") != "":
			# Let the world run this many frames before the shot (rabbits coming out, monsters about), for testing.
			for i in int(Shots.arg("wait")):
				await get_tree().process_frame
			for vg in Villager.all:
				print("Villager ", vg.name, " state ", Villager.State.keys()[vg.state], " at ", vg.position, " hunger ", int(vg.person.hunger), " energy ", int(vg.person.energy), " in bed ", vg.in_bed, " carrying ", vg.carrying, " ", vg.carry_kind, " job ", vg.job != null)
			var nd: Array = world.walls.nearest_door(miko.position, 3.0 * world.px)
			if not nd.is_empty():
				print("Nearest door ", world.walls.edge_middle(nd[0]), " open ", world.walls.is_open(nd[0]), " Miko at ", miko.position)
			var cr: Crystals = get_node_or_null("Crystals")
			if cr != null:
				print("Teleports ", cr.teleports.map(func(c): return [cr.name_of(c.pos), c.pos]), " wards ", cr.wards.map(func(c): return c.pos))
			if Construction.active != null:
				print("Blueprint pieces left ", Construction.active.pieces.size())
			var v := world.village
			print("Village chests ", v.chests().size(), ", wood ", v.stored("Wood"), "/", v.stash_cap("Wood"), ", potatoes ", v.stored("Potato"), "/", v.stash_cap("Potato"), ", items ", v.items.size(), "/", v.item_slots(), ", Miko has wood ", v.have(miko.bag, miko, "Wood"))
			if Shots.arg("log") != "":
				VillageLog.event("test", "Spoiled in storage: 2 potatoes")
				VillageLog.problem("food", "No food in storage", VillageLog.Kind.WARNING)
				VillageLog.event("attack", "A slime is attacking the village!", VillageLog.Kind.DANGER)
				for i in 5:
					await get_tree().process_frame
			if Corruption.active != null:
				print("Rotten trees ", Corruption.active.corrupted.size(), ", armed ", Corruption.active.armed.size(), ", springs ", Springs.active.all.map(func(sp): return sp.at))
			var out := Rabbit.rabbits.filter(func(r): return r.visible)
			print("Rabbits ", Rabbit.rabbits.size(), " (", out.size(), " out), holes ", (get_node("Warren") as Warren).holes.size(), ", creatures ", Creature.all.size())
		if Shots.arg("gather") != "":
			# Start gathering from the nearest tree or rock, and keep at it this many frames (for testing).
			var gathering: Miner = miko.get_node("Miner")
			var spot := Gatherable.nearest(miko.position, 2.0 * world.px)
			print("Gathering from ", spot.resource if spot else "nothing", ", holding ", spot.remaining() if spot else 0)
			if spot:
				gathering._begin(spot)
				for i in int(Shots.arg("gather")):
					await get_tree().process_frame
				print("Left ", spot.remaining(), "; bag wood ", miko.bag.count("Wood"), " stone ", miko.bag.count("Stone"))
		if Shots.arg("window") != "":
			# Open one of the windows for the shot: chest, totals, ask, banner, grow, jobs, bench, character, talents, picker.
			var vd: VillageDesk = get_node("VillageDesk")
			match Shots.arg("window"):
				"chest", "totals", "ask":
					if not world.village.chests().is_empty():
						miko.place(world.village.chests()[0] + Vector2(0, 0.6 * world.px))
					vd.chest_window.open()
					if Shots.arg("window") == "totals": vd.chest_window.show_totals(true)
					if Shots.arg("window") == "ask": vd.chest_window._ask_for("Wood")
				"banner": vd.banner_panel.open()
				"grow":
					vd.growth.begin()
					get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.75, 0.3))
				"jobs": ($Hud/JobsWindow as JobsWindow).visible = true
				"character": ($Hud/CharacterPanel as CharacterPanel).toggle()
				"talents": ($Hud/CharacterPanel as CharacterPanel).toggle_talents()
				"picker": ($Hud/Hotbar as Hotbar).clicked(0)
				"build":
					var bm := BuildMode.active
					bm.set_open(true)
					if Shots.arg("pick") != "":
						for it in bm.items:
							if it.name == Shots.arg("pick"):
								bm.select(it)
								($Hud/BuildBar as BuildBar).category = it.category
					if Shots.arg("tool") != "": bm.set_tool(Shots.arg("tool"))
					if Shots.arg("tool") == "Inspect" and world.roofs != null and not world.roofs.rooms().is_empty():
						bm.picked_room = world.roofs.rooms()[0]
					if Shots.arg("hide") != "": bm.toggle_hide_buildings()
					get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(float(Shots.arg("mx", "0.55")), float(Shots.arg("my", "0.45"))))
				"roundtrip":
					var now := ($SaveGame as SaveGame).capture()
					var start := SaveSystem.start_sections(world)
					for k in start:
						if not now.has(k): print("Round trip: missing ", k)
						elif JSON.parse_string(now[k]) != JSON.parse_string(start[k]): print("Round trip: differs ", k, "
  was ", str(start[k]).left(300), "
  now ", str(now[k]).left(300))
						else: print("Round trip: same ", k)
				"reload":
					if SaveSystem.loaded_slot == "":
						print("Reloading into ", Shots.arg("slot2"))
						($SaveGame as SaveGame).restart(Shots.arg("slot2"))
						return
					print("Reloaded from ", SaveSystem.loaded_slot, ": villagers ", Villager.all.size(), " creatures ", Creature.all.size(), " gatherables ", Gatherable.all.size(), " Miko at ", miko.position)
				"gust":
					var ws: WorldSounds = world.get_node("WorldSounds")
					ws.gust_now()
					var ch := WorldSounds.chime()
					print("Chime ", ch.get_length(), " s; rivers ", ws._rivers.size(), " river volumes ", ws._rivers.map(func(r): return snappedf(db_to_linear(r.player.volume_db), 0.001)), " playing ", ws._rivers.map(func(r): return r.player.playing), " villager steps ", ws._steps.size())
					for i in 60:
						await get_tree().process_frame
				"settings":
					var sm: SaveMenu = $Hud/SaveMenu
					sm.open()
					sm._set_tab(Shots.arg("tab", "Display"))
				"plant":
					var tp: TreePlanter = miko.get_node("TreePlanter")
					miko.bag.add("Seed", 3)
					miko.facing_right = true
					miko.facing_up = false
					var spot := miko.position + Vector2(2.0, 1.0) * world.px
					print("Plant here? '", tp.why_not(spot), "'")
					var g := tp.plant_at(spot)
					print("Planted: sapling ", g.sapling(), " depleted ", g.depleted(), " scale ", g.art.scale, " next in ", g.hours_to_next(), "h")
					clock.hours += 10.0
					g._grow_up()
					print("After 10h: sapling ", g.sapling(), " wood ", g.left, " scale ", g.art.scale, " next in ", g.hours_to_next(), "h")
					clock.hours += 20.0
					g._grow_up()
					print("After 30h: wood ", g.left, " scale ", g.art.scale, " next in ", g.hours_to_next(), "h; saved ", miko.get_node("TreePlanter").to_json().left(120))
					print("Sleep villagers alpha: ", Villager.all.map(func(v): return [v.in_bed, snappedf(v.modulate.a, 0.01)]))
				"mmbench":
					# The minimap's redraws: standing still, building (a floor a second), then zooming in and out.
					var fl := world.floors
					var other: String = ""
					for n in fl.types:
						if n != fl.base_floor and not fl.is_whole(n):
							other = n
							break
					var t0 := Time.get_ticks_msec()
					print("MMPHASE still")
					for i in 600:
						await get_tree().process_frame
					print("MMPHASE build ", other)
					var c0 := fl.cell_at(miko.position) + Vector2i(3, 3)
					for i in 600:
						if i % 60 == 0:
							fl.paint(c0 + Vector2i(floori(i / 60.0), 0), other)
						await get_tree().process_frame
					print("MMPHASE zoom")
					var mm: Minimap = $Hud/Minimap
					for i in 600:
						if i % 60 == 0:
							mm._step(1 if i % 240 < 120 else -1)
						await get_tree().process_frame
					print("MMPHASE end ", Time.get_ticks_msec() - t0)
				"jump":
					# Space: she hops; the picture at the top of the arc.
					var ev := InputEventKey.new()
					ev.keycode = KEY_SPACE
					ev.pressed = true
					Input.parse_input_event(ev)
					await get_tree().process_frame
					await get_tree().process_frame
					var t0 := Time.get_ticks_msec()
					while Time.get_ticks_msec() - t0 < int(Shots.arg("jumpms", "250")):
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_air.png")
					print("Jump: airborne ", miko.airborne(), " body lift ", miko.wading.extra.y, " shadow ", miko.shadow.scale, " a ", snappedf(miko.shadow.modulate.a, 0.01))
				"necklace":
					# A crystal necklace worn at night out in the mist: its light and clearing; then worn nearly out.
					clock.hours = float(Shots.arg("hour", "22"))
					miko.place(miko.position + Vector2(float(Shots.arg("dx", "0")), float(Shots.arg("dy", "0"))) * world.px)
					miko.bag.items[miko.bag.free_slot()] = "CrystalNecklace"
					var slot := miko.bag.items.find("CrystalNecklace")
					if Shots.arg("nowear") == "": miko.stats.equip(miko.bag, slot)
					print("Necklace worn: ", miko.stats.worn_in("Necklace"), " durability ", miko.stats.durability_left("CrystalNecklace"))
					if Shots.arg("wornout") != "":
						miko.stats.wear["CrystalNecklace"] = 899.0
					for i in 120:
						await get_tree().process_frame
					if Shots.arg("zoom") != "":
						camera.zoom *= float(Shots.arg("zoom"))
					print("After: worn ", miko.stats.worn_in("Necklace"), " durability ", miko.stats.durability_left("CrystalNecklace"), " tier here ", world.mist.tier_at(miko.position))
				"ward":
					# Beside a cleansing crystal, inside its clearing: its curtain and the ring on the ground.
					var cr: Crystals = $Crystals
					for i in 10:
						await get_tree().process_frame   # (the crystals are dressed a frame or two in)
					if not cr.wards.is_empty():
						miko.place(cr.wards[0].pos + Vector2(float(Shots.arg("dx", "1.5")), float(Shots.arg("dy", "2.5"))) * world.px)
					for i in 60:
						await get_tree().process_frame
				"chop":
					# The nearest tree struck until it falls: it shakes, topples and lands (its processing woken for it).
					var g: Gatherable = null
					var best := INF
					for c in Gatherable.all:
						if c.axe and not c.depleted() and c.foot.distance_to(miko.position) < best:
							best = c.foot.distance_to(miko.position)
							g = c
					for i in 5:
						await get_tree().process_frame
					print("Chop: idle trees processing ", Gatherable.all.filter(func(c): return c.is_processing()).size(), " of ", Gatherable.all.size())
					var tilt := 0.0
					while g.left > 0:
						g.strike()
						print("  struck: left ", g.left, " processing ", g.is_processing(), " shaking ", g._shake > 0.0)
						for i in 12:
							await get_tree().process_frame
					for i in 90:
						await get_tree().process_frame
						tilt = maxf(tilt, absf(g.art.rotation))
					print("Chop: fell (most tilt ", snappedf(tilt, 0.01), "), regrow at ", g._regrow_at > 0.0, ", processing ", g.is_processing())
				"stopcam":
					# Walks right, then stops: how far the view's centre is from where she's drawn, frame by frame after.
					Input.action_press("ui_right")
					for i in 40:
						await get_tree().process_frame
					Input.action_release("ui_right")
					var gaps := []
					for i in 30:
						await get_tree().process_frame
						gaps.append(snappedf((camera.get_screen_center_position() - follow_offset - miko.drawn_position()).length(), 0.1))
					print("Stop: view behind her by ", gaps)
				"crops":
					# Five farm plots in a row beside her, one of each crop: growing, then (--ripe) ripe.
					var fm: Farming = miko.get_node("Farming")
					var c0 := world.floors.cell_at(miko.position) + Vector2i(2, 1)
					for k in 5:
						world.props.place(c0 + Vector2i(k, 0), "FarmPlot")
					for i in 3:
						await get_tree().process_frame
					fm._look()
					var row := fm.plots.filter(func(pl): return world.floors.cell_at(pl.pos).y == c0.y and world.floors.cell_at(pl.pos).x >= c0.x and world.floors.cell_at(pl.pos).x < c0.x + 5)
					row.sort_custom(func(x, y): return x.pos.x < y.pos.x)
					for k in row.size():
						fm.sow(row[k], Farming.ORDER[k % Farming.ORDER.size()])
						if Shots.arg("ripe") != "":
							fm._state(row[k]).sownAt = -10000.0
					print("Crops: ", row.size(), " plots: ", row.map(func(pl): return [fm.crop(pl), fm.stage(pl), fm._art(pl, fm.stage(pl))]))
					miko.place(row[2].pos + Vector2(0, 2.0) * world.px if row.size() > 2 else miko.position)
					for i in 20:
						await get_tree().process_frame
				"rotation":
					# Two fields of three plots, planted plot by plot as the villagers do: one crop a field; then the
					# first harvested and planted again, moving on to the next crop together.
					var fm: Farming = miko.get_node("Farming")
					fm.rotation = ["Potato", "Carrot", "Cabbage", "Wheat"]
					var base := world.floors.cell_at(miko.position) + Vector2i(2, 1)
					for k in 3:
						world.props.place(base + Vector2i(k, 0), "FarmPlot")
						world.props.place(base + Vector2i(k, 3), "FarmPlot")
					for i in 3:
						await get_tree().process_frame
					fm._look()
					var fields := [[], []]
					for pl in fm.plots:
						var c := world.floors.cell_at(pl.pos)
						if c.x >= base.x and c.x < base.x + 3 and (c.y == base.y or c.y == base.y + 3):
							fields[0 if c.y == base.y else 1].append(pl)
					var any_seed := func(_s: String) -> bool: return true
					for f in fields:
						for pl in f:
							fm.sow(pl, fm._field_crop(pl, any_seed)[1])
					print("Rotation planted: A ", fields[0].map(func(pl): return fm.crop(pl)), "  B ", fields[1].map(func(pl): return fm.crop(pl)))
					for pl in fields[0]:
						fm._state(pl).sownAt = -10000.0
						fm.harvest(pl)
					for pl in fields[0]:
						fm.sow(pl, fm._field_crop(pl, any_seed)[1])
					print("Rotation next season: A ", fields[0].map(func(pl): return fm.crop(pl)), "  B ", fields[1].map(func(pl): return fm.crop(pl)))
					miko.place(fields[0][1].pos + Vector2(0, 0.45) * world.px)
					for i in 20:
						await get_tree().process_frame
				"sway":
					# Among trees by day: two pictures 0.6 s apart (the sway), then one as a wind gust passes.
					clock.hours = 12.0
					miko.place(miko.position + Vector2(float(Shots.arg("dx", "0")), float(Shots.arg("dy", "0"))) * world.px)
					for i in 30:
						await get_tree().process_frame
					var base := Shots.arg("shot").get_basename()
					get_viewport().get_texture().get_image().save_png(base + "_a.png")
					var t0 := Time.get_ticks_msec()
					while Time.get_ticks_msec() - t0 < 600:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(base + "_b.png")
					var ws: WorldSounds = world.get_node("WorldSounds")
					ws.gust_now()
					t0 = Time.get_ticks_msec()
					while Time.get_ticks_msec() - t0 < int(ws._gust_length * 450.0):
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(base + "_gust.png")
				"spawnspots":
					# Random spots round the rivers: how many the spawners would take that are in or at the water.
					var ws: WorldSounds = world.get_node("WorldSounds")
					var taken := 0
					var wet := 0
					for i in 20000:
						var r: Dictionary = ws._rivers[i % ws._rivers.size()]
						var smp: Array = r.samples[randi() % r.samples.size()]
						var spot_at := world.floors.corner(Vector2(smp[0], smp[1])) + Vector2(randf_range(-4, 4), randf_range(-2, 2)) * world.px
						if Wilds.open(world, spot_at, 0.5):
							taken += 1
							var near_water := world.wet(spot_at)
							for k in 8:
								var ang := k * TAU / 8.0
								if world.wet(spot_at + Vector2(cos(ang), sin(ang) * 0.5) * 0.5 * world.px):
									near_water = true
							if near_water:
								wet += 1
					print("Spawn spots by rivers: ", taken, " taken, ", wet, " of them in or at the water")
				"smack":
					# A slime in front of her; the cursor on it and a left click: she swings and it's hit.
					var md: Dictionary = world._load_json("res://data/monsters.json")
					var spot := miko.position + Vector2(float(Shots.arg("dx", "0.7")), float(Shots.arg("dy", "0.15"))) * world.px
					var sl: Slime = Slime.spawn(world, md.slime, false, spot, 1.0)
					for i in 5:
						await get_tree().process_frame
					var before: float = sl.hit.hp
					var screen := get_viewport().get_canvas_transform() * sl.position
					get_viewport().warp_mouse(screen)
					var click := InputEventMouseButton.new()
					click.button_index = MOUSE_BUTTON_LEFT
					click.pressed = true
					click.position = screen
					click.global_position = screen
					Input.parse_input_event(click)
					var up := click.duplicate() as InputEventMouseButton
					up.pressed = false
					Input.parse_input_event(up)
					var shot_taken := false
					for i in 40:
						await get_tree().process_frame
						if not shot_taken and miko.action_frame() == 3:
							shot_taken = true
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_swing.png")
					print("Smack: slime hp ", before, " -> ", sl.hit.hp if is_instance_valid(sl) else -1.0, ", Miko facing right ", miko.facing_right, ", locked after ", miko.locked)
				"mutants":
					# Four mutated villagers round her, each walking a different diagonal, to see which way they face.
					var md: Dictionary = world._load_json("res://data/monsters.json")
					var dirs := [Vector2(-1, 0.5), Vector2(1, 0.5), Vector2(-1, -0.5), Vector2(1, -0.5)]
					var gap := float(Shots.arg("gap", "2.2"))
					for dv: Vector2 in dirs:
						var mv := MutatedVillager.spawn(world, md.mutatedVillager, miko.position + dv * gap * world.px)
						mv.target = mv.position + dv * 3.0 * world.px
						mv.state = MutatedVillager.State.WALK
						mv.state_until = MutatedVillager.now() + 10.0
					for i in int(Shots.arg("mframes", "25")):
						await get_tree().process_frame
				"chase":
					# In the mist with a mutated villager 4 units off: it comes after her and hits her; back home, it gives up.
					var md: Dictionary = world._load_json("res://data/monsters.json")
					var home_at := miko.position
					# Somewhere in the mist with dry ground all round (no river between them).
					for k in 400:
						var spot := home_at + Vector2.from_angle(randf() * TAU) * randf_range(14.0, 30.0) * world.px
						if world.mist.tier_at(spot) != Mist.Tier.CLEAR and Wilds.dry(world, spot, 5.0):
							miko.place(spot)
							break
					var mv := MutatedVillager.spawn(world, md.mutatedVillager, miko.position + Vector2(4.0, 0.0) * world.px)
					var hp0: float = miko.stats.hp
					var track := []
					var slam_shot := false
					for i in int(Shots.arg("chaseframes", "720")):
						await get_tree().process_frame
						if not slam_shot and mv.state == MutatedVillager.State.ATTACK and mv._hit_done:
							slam_shot = true
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_slam.png")
						if i % 60 == 0:
							track.append([snappedf(mv.position.distance_to(miko.position) / world.px, 0.1), MutatedVillager.State.keys()[mv.state]])
					print("Chase: distance/state each second ", track, ", her HP ", hp0, " -> ", miko.stats.hp)
					miko.place(home_at)
					for i in 30:
						await get_tree().process_frame
					print("Chase: after she's back home: ", MutatedVillager.State.keys()[mv.state])
				"watercover":
					# Every water mesh: how much of it (triangle middles) the depth map, and so the spawners, know is water.
					for n in get_tree().root.find_children("*", "MeshInstance2D", true, false):
						var mi := n as MeshInstance2D
						if mi.mesh == null or not (mi.material is ShaderMaterial) or str(mi.name).begins_with("Cliffs"):
							continue
						var arr := mi.mesh.surface_get_arrays(0)
						var v: PackedVector2Array = arr[Mesh.ARRAY_VERTEX]
						var t: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
						var known := 0
						var tris := 0
						var dry_at := []
						for k in range(0, t.size(), 3):
							var c := mi.global_transform * ((v[t[k]] + v[t[k + 1]] + v[t[k + 2]]) / 3.0)
							tris += 1
							if world.wet(c):
								known += 1
							elif dry_at.size() < 3:
								dry_at.append(world.floors.cell_at(c))
						print("Water ", mi.name, ": ", known, " of ", tris, " known as water; not: ", dry_at)
				"walk":
					# Walks her round a wide loop (through the village and out into the wilds) at running pace, then reports.
					var centre := miko.position
					var radius := float(Shots.arg("radius", "18")) * world.px
					var frames := int(Shots.arg("walkframes", "1200"))
					var wet_ever := {}
					for i in frames:
						var a := TAU * i / 600.0
						miko.place(centre + Vector2(cos(a) * radius, sin(a) * radius * 0.5) - Vector2(radius, 0))
						if i % 10 == 0:
							for c in Creature.all:
								if is_instance_valid(c) and not Wilds.dry(world, c.position, 0.5):
									wet_ever[c.get_instance_id()] = true
						await get_tree().process_frame
					print(Perf.active.summary())
					print("Creatures in water at some point: ", wet_ever.size(), " (of ", Creature.all.size(), " now)")
				"cams":
					for c in get_tree().root.find_children("*", "Camera2D", true, false):
						print("Camera ", c.get_path(), " callback ", c.process_callback, " interp ", c.is_physics_interpolated())
				"eat":
					while Villager.all.is_empty():
						await get_tree().process_frame
					var v: Villager = Villager.all[0]
					v.meal = "Meal"
					v.state = Villager.State.EATING
					v.state_until = Villager.now() + 60.0
					miko.place(v.position + Vector2(1.5, 0.5) * world.px)
					for i in 20:
						v.state = Villager.State.EATING
						await get_tree().process_frame
				"mistcheck":
					# Watches the villagers a while: how often any of them stands in the mist.
					var out := 0
					var looks := 0
					for i in int(Shots.arg("watch", "1500")):
						await get_tree().physics_frame
						for v in Villager.all:
							if v.visible:
								looks += 1
								if not Villager.safe_ground(world, v.position): out += 1
					print("Villagers in the mist: ", out, " of ", looks, " looks")
				"saves":
					if Shots.arg("savenow") != "": ($SaveGame as SaveGame).save(Shots.arg("savenow"), false, "Test save")
					($Hud/SaveMenu as SaveMenu).open()
				"map":
					($Hud/WorldMap as WorldMap).open()
					if Shots.arg("mapzoom") != "":
						for i in int(Shots.arg("mapzoom")): ($Hud/WorldMap as WorldMap)._step(1, null)
				"bench":
					var wb: WorkbenchWindow = $Hud/WorkbenchWindow
					for prop in wb.benches:
						if Shots.arg("bench") != "" and prop != Shots.arg("bench"):
							continue
						if not world.props_named(prop).is_empty():
							miko.place(world.props_named(prop)[0] + Vector2(0, 0.6 * world.px))
							wb.open(prop, world.props_named(prop)[0])
							break
			for i in 10:
				await get_tree().process_frame
		camera.position = miko.position + follow_offset
		camera.reset_smoothing()
		var saved := camera.position
		Shots.take_if_asked(self, camera)
		camera.position = saved


static var _window_set := false


func _post_processing() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.93
	env.adjustment_contrast = 0.94
	env.adjustment_saturation = 0.9
	var we := WorldEnvironment.new()
	we.name = "PostProcessing"
	we.environment = env
	add_child(we)
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	layer.layer = 0
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vignette.gdshader")
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)
	Settings.set_picture(env, rect)


func _window_up() -> bool:
	var over := get_viewport().gui_get_hovered_control()
	if over != null and over.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return true
	if CharacterPanel.up() or BuildMode.is_open():
		return true
	for path in ["Hud/WorldMap", "Hud/JobsWindow", "Hud/WorkbenchWindow", "Hud/SaveMenu"]:
		var n: Control = get_node_or_null(path)
		if n != null and n.visible:
			return true
	var desk: VillageDesk = get_node_or_null("VillageDesk")
	return desk != null and desk.any_open()


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"game.process", __t)


func _process_timed(_delta: float) -> void:
	# Follow where she's drawn (smoothed between physics ticks), not her last physics step: otherwise, on a screen
	# faster than the physics rate, she and the world jump unevenly and look blurred while moving.
	if not BuildMode.is_open() and not has_meta("warming"):
		camera.position = miko.drawn_position() + follow_offset
	time_label.text = "%s · %s, day %d · %s
Wood %d · Stone %d" % [clock.time_text(), GameClock.SEASON_NAMES[clock.season()], clock.day_of_season(), GameClock.WEATHER_NAMES[clock.weather()], miko.bag.count("Wood"), miko.bag.count("Stone")]


func _unhandled_input(event: InputEvent) -> void:
	# The wheel zooms the view, but not over a window or while one is open (it scrolls them instead).
	if not _window_up():
		Shots.wheel_zoom(event, camera, 0.25, 3.0)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BRACKETRIGHT: clock.hours += 1.0
		elif event.keycode == KEY_BRACKETLEFT: clock.hours = maxf(0.0, clock.hours - 1.0)
		elif event.keycode == KEY_F6: clock.set_weather((clock.weather() + 1) % 5)
