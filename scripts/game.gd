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
	# Which version this is, small, at the very bottom centre, under the hotbar (more quick bars stack upward).
	var build_line := HudStyle.label(BuildInfo.text(), 11, "bold", Color(HudStyle.color("accentLight"), 0.8))
	build_line.name = "BuildLine"
	build_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	build_line.add_theme_constant_override("outline_size", 4)
	build_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	build_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	build_line.grow_vertical = Control.GROW_DIRECTION_BEGIN
	build_line.offset_bottom = -2
	$Hud.add_child(build_line)
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
	# The land past the map's edges (forest and undergrowth, for looks).
	var outskirts := Outskirts.new()
	outskirts.name = "Outskirts"
	add_child(outskirts)
	outskirts.setup(world)
	# Cellars: cold storage, and the way down into one.
	var cellars := Cellars.new()
	cellars.name = "Cellars"
	add_child(cellars)
	cellars.setup(world, miko, $Hud)
	if sv.get("sections", {}).has("world.cellars"):
		cellars.from_json(sv.sections["world.cellars"])
	# Whether the village uses more than it brings in.
	var ledger := Ledger.new()
	ledger.name = "Ledger"
	add_child(ledger)
	ledger.setup(world)
	# Houses wear out, and are repaired.
	var upkeep := Upkeep.new()
	upkeep.name = "Upkeep"
	upkeep.setup(world)
	if sv.get("sections", {}).has("world.upkeep"):
		upkeep.from_json(sv.sections["world.upkeep"])
	# The mountains along the north-east edge, and the cave in them.
	var mountains := Mountains.new()
	mountains.name = "Mountains"
	add_child(mountains)
	mountains.setup(world, miko, $Hud)
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
	miko.stats.hurt.connect(func(_a): HitFx.sound(world, miko.position))   # (heard too)
	# Her HP and mana over her head while either is short of full.
	var head_bars := HeadBars.new()
	head_bars.name = "HeadBars"
	head_bars.setup(world, miko)
	miko.add_child(head_bars)
	# Her talents' pockets, a blocked hit and Second Wind, shown over her.
	var pockets := func() -> void: miko.bag.bonus_slots = int(miko.stats.stat("bagSlots"))
	miko.stats.changed.connect(pockets)
	pockets.call()
	miko.stats.blocked.connect(func(): FloatingText.spawn(world, "Blocked", miko.position + Vector2(0, -1.6 * world.px), Color(0.7, 0.85, 1.0)))
	miko.stats.second_wind.connect(func():
		FloatingText.spawn(world, "Second Wind!", miko.position + Vector2(0, -1.9 * world.px), Color(1.0, 0.9, 0.2), 30, 1.8, Color(0.85, 0.08, 0.05))
		Puffs.burst(world, miko.position + Vector2(0, -0.5 * world.px), 1.2, 16))
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
	# Now and then, at night, a horde raids the village.
	var raids := Raids.new()
	raids.name = "Raids"
	add_child(raids)
	raids.setup(world, world._load_json("res://data/monsters.json"))
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
	# Talking with villagers (E beside one).
	var talk := Talk.new()
	talk.name = "Talk"
	$Hud.add_child(talk)
	talk.setup(world, miko, $Hud)
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
	var footprints := SnowFootprints.new()
	footprints.name = "SnowFootprints"
	footprints.setup(world, miko, snow)
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
				"jobs":
					($Hud/JobsWindow as JobsWindow).visible = true
					if Shots.arg("tab") != "":
						($Hud/JobsWindow as JobsWindow).tab = Shots.arg("tab")
				"character":
					var cp: CharacterPanel = $Hud/CharacterPanel
					cp.toggle()
					# --sizes: the panel's size with each kind of thing picked in turn (it shouldn't change).
					if Shots.arg("sizes") != "":
						var sizes := []
						for nm in ["", "Wood", "Sachet", "CrystalNecklace", "ShrineCharm"]:
							if nm == "Wood" or nm == "":
								cp.selected = -1 if nm == "" else miko.bag.stack_slot.get("Wood", -1)
							else:
								var slot_at := miko.bag.free_slot()
								miko.bag.items[slot_at] = nm
								cp.selected = slot_at
							cp._dirty = true
							for i in 3:
								await get_tree().process_frame
							var root: Control = cp.get_child(0) if cp.get_child_count() > 0 else cp
							sizes.append([nm, root.size])
						print("Panel sizes: ", sizes)
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
					if Shots.arg("blueprint") != "": bm.blueprint = true
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
					fm.rotation = ["Potato", "Carrot", "Wheat", "Cotton"]
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
						if not shot_taken and miko.action_frame() == int(Shots.arg("atframe", "3")):
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
				"tend":
					# Three plots of potatoes: normal, left dry, and with pests; their growth over 10 game hours; Miko waters
					# the dry one; a villager clears the pests (the emote showing).
					seed(7)
					var fm: Farming = miko.get_node("Farming")
					clock.hours = 12.0
					var c0 := world.floors.cell_at(miko.position) + Vector2i(2, 1)
					for k in 3:
						world.props.place(c0 + Vector2i(k, 0), "FarmPlot")
					for i in 3:
						await get_tree().process_frame
					fm._look()
					var row := fm.plots.filter(func(pl): return world.floors.cell_at(pl.pos).y == c0.y and world.floors.cell_at(pl.pos).x >= c0.x and world.floors.cell_at(pl.pos).x < c0.x + 3)
					row.sort_custom(func(x, y): return x.pos.x < y.pos.x)
					for pl in row:
						fm.sow(pl, "Potato")
					fm._state(row[1]).wateredAt = -1000.0
					fm._state(row[2]).pest = true
					for k in 10:
						clock.hours += 1.0
						for i in 2:
							await get_tree().process_frame
					print("Tend: grown after 10 h (normal, dry, pests): ", row.map(func(pl): return snappedf(fm._grown(pl), 0.1)), " dry ", row.map(func(pl): return fm.dry(pl)), " pests ", row.map(func(pl): return fm.pests(pl)))
					fm.water(row[1])
					print("Tend: watered, dry now ", fm.dry(row[1]))
					clock.hours += 14.0   # the next midday (at 22:00 they're off to bed)
					fm._state(row[2]).pest = true
					for i in 3:
						await get_tree().process_frame
					var v: Villager = Villager.all[0]
					v.position = row[2].pos + Vector2(2.5, 1.0) * world.px
					v.carrying = 0
					v.farm_task = "pests"
					v.planting = false
					v._go_to_plot(row[2])
					var seen_emote := false
					for i in 600:
						await get_tree().process_frame
						if v.emote != null and v.emote.visible and not seen_emote:
							seen_emote = true
							miko.place(row[1].pos + Vector2(-1.5, 1.2) * world.px)
							for k in 3:
								await get_tree().process_frame
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_emote.png")
						if not fm.pests(row[2]):
							break
					print("Tend: villager cleared the pests ", not fm.pests(row[2]), ", saw the emote ", seen_emote, ", status '", v.activity(), "'")
					fm._state(row[0]).pest = true
					fm._state(row[0]).wateredAt = -1000.0
					miko.place(row[1].pos + Vector2(0, 1.6) * world.px)
				"soil":
					# Potato plots: bare, growing (watered), growing (dry), ripe; then a closer look.
					var fm: Farming = miko.get_node("Farming")
					var c0 := world.floors.cell_at(miko.position) + Vector2i(1, -1)
					for k in 4:
						world.props.place(c0 + Vector2i(k, 0), "FarmPlot")
					for i in 3:
						await get_tree().process_frame
					fm._look()
					var row := fm.plots.filter(func(pl): return world.floors.cell_at(pl.pos).y == c0.y and world.floors.cell_at(pl.pos).x >= c0.x and world.floors.cell_at(pl.pos).x < c0.x + 4)
					row.sort_custom(func(x, y): return x.pos.x < y.pos.x)
					for k in range(1, 4):
						fm.sow(row[k], Shots.arg("crop", "Potato"))
					fm._state(row[2]).wateredAt = -1000.0
					fm._state(row[3]).grown = 999.0
					print("Soil: stages ", row.map(func(pl): return fm.stage(pl)), " dry ", row.map(func(pl): return fm.dry(pl)))
					miko.place(row[1].pos + Vector2(-1.5, 1.6) * world.px)
					camera.zoom *= float(Shots.arg("zoom", "1.6"))
					for i in 10:
						await get_tree().process_frame
				"fields":
					# A field of three plots and a lone plot beside it planted mixed (an old save); evened out to one crop;
					# two harvested: the field waits; the last harvested: planted again together, the next crop.
					var fm: Farming = miko.get_node("Farming")
					fm.rotation = ["Potato", "Carrot", "Wheat", "Cotton"]
					var c0 := world.floors.cell_at(miko.position) + Vector2i(2, 1)
					for k in 3:
						world.props.place(c0 + Vector2i(k, 0), "FarmPlot")
					for i in 3:
						await get_tree().process_frame
					fm._look()
					var row := fm.plots.filter(func(pl): return world.floors.cell_at(pl.pos).y == c0.y and world.floors.cell_at(pl.pos).x >= c0.x and world.floors.cell_at(pl.pos).x < c0.x + 3)
					row.sort_custom(func(x, y): return x.pos.x < y.pos.x)
					var mixed := ["Carrot", "Carrot", "Wheat"]
					for k in 3:
						fm.sow(row[k], mixed[k])
						fm._state(row[k]).grown = 999.0
					fm._even_fields()
					print("Fields: evened out ", row.map(func(pl): return fm.crop(pl)))
					var any_seed := func(_s: String) -> bool: return true
					fm.harvest(row[0])
					fm.harvest(row[1])
					print("Fields: two harvested, plantable ", row.map(func(pl): return fm.plantable(pl)), ", still growing ", fm.still_growing(row[0]))
					fm.harvest(row[2])
					print("Fields: all harvested, plantable ", row.map(func(pl): return fm.plantable(pl)))
					for pl in row:
						fm.sow(pl, fm._field_crop(pl, any_seed)[1])
					print("Fields: replanted together ", row.map(func(pl): return fm.crop(pl)))
				"fieldpanel":
					# A field of four carrots part grown (one dry, one with pests), and its panel opened (R).
					var fm: Farming = miko.get_node("Farming")
					fm.rotation = ["Potato", "Carrot", "Wheat", "Cotton"]
					var c0 := world.floors.cell_at(miko.position) + Vector2i(1, 1)
					for k in 4:
						world.props.place(c0 + Vector2i(k % 2, floori(k / 2.0)), "FarmPlot")
					for i in 3:
						await get_tree().process_frame
					fm._look()
					var field := fm.field_of(fm.nearest(world.floors.cell_centre(c0), world.px))
					for pl in field:
						fm.sow(pl, "Carrot")
						fm._state(pl).grown = 22.0
					fm._state(field[1]).wateredAt = -1000.0
					fm._state(field[2]).pest = true
					miko.place(field[0].pos + Vector2(0, 0.4) * world.px)
					await get_tree().process_frame
					fm.panel.open(field[0])
					for i in 10:
						await get_tree().process_frame
					if Shots.arg("winter") != "":
						# Late autumn (a day and a half to winter): the panel's warning; then into winter: the frost.
						var dps: int = clock.days_per_season
						var autumn_day := posmod(GameClock.Season.AUTUMN - clock.start_season, 4) * dps
						clock.hours = float(autumn_day + dps - 2) * 24.0 + 12.0
						for i in 5:
							await get_tree().process_frame
						fm.panel._refresh()
						print("Winter: in ", snappedf(fm.hours_to_winter(), 0.1), " h; panel: ", fm.panel._lines.text.replace("
", " | "))
						get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_autumn.png")
						clock.hours += 40.0
						for i in 5:
							await get_tree().process_frame
						fm.panel._refresh()
						print("Winter: season ", clock.season(), " stages ", field.map(func(pl): return fm.stage(pl)), " plantable ", fm.plantable(field[0]), "; panel: ", fm.panel._lines.text.replace("
", " | "))
				"demolish":
					# A cell with a farm plot, a free flower bush on it and a fence along it: each demolish filter takes only
					# its own; then a sown plot moved with Move keeps its crop.
					var bm := BuildMode.active
					var fm: Farming = miko.get_node("Farming")
					var cell := world.floors.cell_at(miko.position) + Vector2i(2, 1)
					var what := func() -> String: return "plot %s, bush %s, fence %s" % [world.props.get_prop(cell, 0) != "" or world.props.peek_top(cell) == "FarmPlot", world.props.free_props().any(func(e): return world.floors.cell_at(e.pos) == cell), world.walls.get_wall(WallMap.Edge.new(cell, false)) != ""]
					for kind in ["Walls", "Decor", "Farm"]:
						world.props.place(cell, "FarmPlot")
						world.props.place_free(world.floors.cell_centre(cell) + Vector2(10, 4), "FlowerBush")
						world.walls.place(WallMap.Edge.new(cell, false), "Fence")
						bm.set_demolish_only(kind)
						bm._clear_one(cell)
						print("Demolish ", kind, ": ", what.call())
						world.props.remove_all(cell)
						world.walls.remove(WallMap.Edge.new(cell, false))
					bm.set_demolish_only("All")
					world.props.place(cell, "FarmPlot")
					for i in 3:
						await get_tree().process_frame
					fm._look()
					var pl: Dictionary = fm.nearest(world.floors.cell_centre(cell), world.px)
					fm.sow(pl, "Wheat")
					fm._state(pl).grown = 20.0
					bm.carried = world.props.take_top(cell)
					bm.carried.farm = fm.lift_plot(bm.carried.pos)
					var to := cell + Vector2i(3, 0)
					world.props.place(to, "FarmPlot")
					bm._set_plot(world.floors.cell_centre(to))
					bm.carried = {}
					for i in 3:
						await get_tree().process_frame
					fm._look()
					var moved: Dictionary = fm.nearest(world.floors.cell_centre(to), world.px)
					print("Move: the plot there ", not moved.is_empty(), ", crop ", fm.crop(moved) if not moved.is_empty() else "", " grown ", fm._grown(moved) if not moved.is_empty() else -1.0, ", old spot empty ", world.props.peek_top(cell) == "")
				"movefield":
					# A 2x2 field of wheat, part grown, lifted whole with Move; its ghost under the cursor; set down 3 cells on.
					var bm := BuildMode.active
					var fm: Farming = miko.get_node("Farming")
					var cell := world.floors.cell_at(miko.position) + Vector2i(1, 1)
					for k in 4:
						world.props.place(cell + Vector2i(k % 2, floori(k / 2.0)), "FarmPlot")
					for i in 3:
						await get_tree().process_frame
					fm._look()
					for pl in fm.field_of(fm.nearest(world.floors.cell_centre(cell), world.px)):
						fm.sow(pl, "Wheat")
						fm._state(pl).grown = 20.0
					bm.set_open(true)
					bm.set_tool("Move")
					bm._lift_field(cell)
					print("Move field: lifted ", bm.carried.group.size(), " plots, left on the ground ", [0, 1, 2, 3].filter(func(k): return world.props.peek_top(cell + Vector2i(k % 2, floori(k / 2.0))) != "").size())
					var to := cell + Vector2i(3, 0)
					get_viewport().warp_mouse(get_viewport().get_canvas_transform() * world.floors.cell_centre(to))
					for i in 6:
						await get_tree().process_frame
					print("Move field: ghosts ", bm._group_ghost.size(), " tool ", bm.tool, " open ", BuildMode.is_open(), " hover ", bm.hover.get("title", ""))
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_carry.png")
					bm._set_field_down(to)
					bm.carried = {}
					for i in 3:
						await get_tree().process_frame
					fm._look()
					var moved := fm.field_of(fm.nearest(world.floors.cell_centre(to), world.px))
					print("Move field: set down ", moved.size(), " plots, crops ", moved.map(func(pl): return fm.crop(pl)), " grown ", moved.map(func(pl): return snappedf(fm._grown(pl), 1.0)))
					bm.set_open(false)
				"walllag":
					# Build mode, Demolish: house walls removed one every 20 frames; how long each removal and the frames after.
					var bm := BuildMode.active
					bm.set_open(true)
					bm.set_tool("Demolish")
					bm.set_demolish_only("Walls")
					var cells := []
					for k in world.walls.walls.keys().slice(0, 8):
						cells.append(Vector2i(k.x, k.y))
					for c in cells:
						var t0 := Time.get_ticks_usec()
						bm._clear_one(c)
						var took := (Time.get_ticks_usec() - t0) / 1000.0
						var worst := 0.0
						for i in 20:
							var f0 := Time.get_ticks_usec()
							await get_tree().process_frame
							worst = maxf(worst, (Time.get_ticks_usec() - f0) / 1000.0)
						print("Wall off ", c, ": the call ", snappedf(took, 0.1), " ms, worst frame after ", snappedf(worst, 0.1), " ms")
				"barricade":
					# Barricades: three along x and three along y, a fence row beside them to compare.
					var c0 := world.floors.cell_at(miko.position) + Vector2i(2, -2)
					for i in 3:
						world.walls.place(WallMap.Edge.new(c0 + Vector2i(i * 2, 0), false), Shots.arg("wall", "Barricade"))
						world.walls.place(WallMap.Edge.new(c0 + Vector2i(7, i * 2 + 1), true), Shots.arg("wall", "Barricade"))
						world.walls.place(WallMap.Edge.new(c0 + Vector2i(i, -2), false), "Fence")
					miko.place(world.floors.cell_centre(c0 + Vector2i(1, 2)))
					camera.zoom *= float(Shots.arg("zoom", "1.4"))
					for i in 10:
						await get_tree().process_frame
				"hitfx":
					# A villager and a slime beside Miko, both hit: shot mid-flinch (red, jolted).
					while Villager.all.is_empty():
						await get_tree().process_frame
					var v: Villager = Villager.all[0]
					v.position = miko.position + Vector2(-1.2, -0.3) * world.px
					var md: Dictionary = world._load_json("res://data/monsters.json")
					var sl: Slime = Slime.spawn(world, md.slime, false, miko.position + Vector2(1.2, -0.3) * world.px, 1.0)
					camera.zoom *= 1.6
					for i in 10:
						await get_tree().process_frame
					v.hit.hurt(3.0)
					sl.hit.hurt(3.0)
					for i in 4:
						await get_tree().process_frame
					print("Hit fx: villager tint ", v.art.self_modulate, ", jolt ", v.get_node("Wading").extra, "; slime tint ", sl.art.self_modulate)
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_hit.png")
					for i in 40:
						await get_tree().process_frame
					print("Hit fx after: villager tint ", v.art.self_modulate, ", jolt ", v.get_node("Wading").extra)
				"treehit":
					# Miko beside a corrupted tree, which is struck: it blinks red and shakes.
					for i in 5:
						await get_tree().process_frame
					var cr := Corruption.active
					var tree: Gatherable = null
					for t in cr.corrupted:
						if is_instance_valid(t) and t.standing():
							tree = t
							break
					if tree == null:
						print("Tree hit: no corrupted tree")
					else:
						miko.place(tree.foot + Vector2(-0.8, 0.6) * world.px)
						for i in 300:
							await get_tree().process_frame
							if cr.armed.has(tree):
								break
						var dm: Damageable = cr.armed[tree][0] if cr.armed.has(tree) else null
						if dm != null:
							dm.hurt(2.0)
						for i in 4:
							await get_tree().process_frame
						print("Tree hit: armed ", dm != null, ", tint ", tree.art.self_modulate, ", shaken ", tree.art.position != tree._rest)
						get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_tree.png")
				"doorline":
					# Door outlines: how many show with Miko away from them, then beside each back-wall door in turn.
					for i in 10:
						await get_tree().process_frame
					var outlines := func() -> Array:
						var found := []
						for k in world.walls.walls:
							for n in world.walls.nodes_of(WallMap.Edge.of(k)):
								if is_instance_valid(n):
									for o in n.find_children("DoorOutline", "", true, false):
										found.append([k, o])
						return found
					var all_lines: Array = outlines.call()
					miko.place(world.village.centre() + Vector2(0, 14.0) * world.px)
					for i in 40:
						await get_tree().process_frame
					print("Door outlines: ", all_lines.size(), ", showing with Miko away ", outlines.call().filter(func(x): return (x[1] as OccludedOutline).outline.visible).size())
					for x0 in all_lines:
						var key: Vector3i = x0[0]
						miko.place(world.walls.wall_middle(key) + Vector2(0, -0.6) * world.px)
						for i in 40:
							await get_tree().process_frame
						var now_lines: Array = outlines.call().filter(func(y): return y[0] == key)
						if now_lines.is_empty():
							continue
						var x: Array = now_lines[0]
						if (x[1] as OccludedOutline).covered:
							print("Door outline beside ", x[0], ": showing ", (x[1] as OccludedOutline).outline.visible)
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_near.png")
							break
				"mineprompt":
					# Miko by a rock, stepping about beside it: where "Press E to mine" sits from the rock (should stay put).
					for i in 5:
						await get_tree().process_frame
					var rock: Gatherable = null
					var best := INF
					for g in Gatherable.all:
						if is_instance_valid(g) and not g.axe and not g.depleted() and g.foot.distance_to(miko.position) < best:
							best = g.foot.distance_to(miko.position)
							rock = g
					var mn: Node = miko.get_node("Miner")
					var lbl: Label = mn.prompt
					for step in [Vector2(-0.5, 0.4), Vector2(0.4, 0.5), Vector2(0.0, 0.7)]:
						miko.place(rock.foot + step * world.px)
						for i in 10:
							await get_tree().process_frame
						var rock_screen := get_viewport().get_canvas_transform() * rock.foot
						print("Mine prompt: '", lbl.text, "' at ", (lbl.position - rock_screen).round(), " from the rock")
				"ring":
					# A ring of barricades just round the village: their spikes should point out on every side.
					for i in 5:
						await get_tree().process_frame
					var cc := world.floors.cell_at(world.village.centre())
					var h := ceili(world.village.half_size()) + 1
					for x in range(cc.x - h, cc.x + h, 2):
						world.walls.place(WallMap.Edge.new(Vector2i(x, cc.y - h), false), "Barricade")
						world.walls.place(WallMap.Edge.new(Vector2i(x, cc.y + h), false), "Barricade")
					for y in range(cc.y - h, cc.y + h, 2):
						world.walls.place(WallMap.Edge.new(Vector2i(cc.x - h, y), true), "Barricade")
						world.walls.place(WallMap.Edge.new(Vector2i(cc.x + h, y), true), "Barricade")
					for side in [["south", Vector2i(cc.x + h, cc.y + h)], ["north", Vector2i(cc.x - h, cc.y - h)], ["east", Vector2i(cc.x + h, cc.y - h)], ["west", Vector2i(cc.x - h, cc.y + h)]]:
						miko.place(world.floors.cell_centre(side[1]))
						for i in 90:
							await get_tree().process_frame
						get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_" + side[0] + ".png")
				"turnbar":
					# Two barricades side by side, one turned round (R); then saved and loaded back, and the ghost's art.
					for i in 5:
						await get_tree().process_frame
					var c0 := world.floors.cell_at(miko.position) + Vector2i(1, -2)
					var ea := WallMap.Edge.new(c0, false)
					var eb := WallMap.Edge.new(c0 + Vector2i(2, 0), false)
					world.walls.place(ea, "Barricade")
					world.walls.place(eb, "Barricade", true)
					var ec := WallMap.Edge.new(c0 + Vector2i(5, -1), true)
					world.walls.place(ec, "Barricade", true)
					var saved_walls := world.walls.to_json()
					world.walls.from_json(saved_walls)
					world.walls.rebuild()
					print("Turned: plain ", world.walls.is_turned(ea), ", turned ", world.walls.is_turned(eb), ", turned along y ", world.walls.is_turned(ec))
					print("Ghost art: usual ", world.walls.ghost_pieces(ea, "Barricade")[0][0], ", turned ", world.walls.ghost_pieces(ea, "Barricade", true)[0][0])
					world.walls.place(ea, "Barricade", true)
					print("Placed again turned: ", world.walls.is_turned(ea))
					world.walls.place(ea, "Barricade", false)
					miko.place(world.floors.cell_centre(c0 + Vector2i(2, 2)))
					for i in 20:
						await get_tree().process_frame
				"penaway":
					# A rabbit pen, demolished from a corner tile of it (not the middle one it stands on).
					for i in 5:
						await get_tree().process_frame
					var pc := world.floors.cell_at(miko.position) + Vector2i(3, 0)
					world.props.place(pc, "RabbitPen")
					var bm := BuildMode.active
					print("Pen: hover on its corner '", bm._demolish_hover(pc + Vector2i(1, 1), true).get("title", ""), "'")
					bm._clear_one(pc + Vector2i(1, 1))
					print("Pen: left after demolishing its corner ", world.props_named("RabbitPen").filter(func(p): return world.floors.cell_at(p) == pc).size())
				"watersound":
					# A villager sent to water a dry field: the watering sound while they're at it.
					var fm: Farming = miko.get_node("Farming")
					print("Watering sound: ", snappedf(Sfx.stream(Farming.WATER_SOUND).get_length(), 0.01), " s")
					var c0 := world.floors.cell_at(miko.position) + Vector2i(1, -1)
					world.props.place(c0, "FarmPlot")
					for i in 3:
						await get_tree().process_frame
					var pl: Dictionary = fm.plots.filter(func(q): return world.floors.cell_at(q.pos) == c0)[0]
					fm.sow(pl, "Potato")
					fm._state(pl).wateredAt = -1000.0
					clock.hours = float(clock.day() - 1) * 24.0 + 10.0
					while Villager.all.is_empty():
						await get_tree().process_frame
					var v: Villager = Villager.all[0]
					v.position = pl.pos + Vector2(1.5, 0.5) * world.px
					v.carrying = 0
					v.farm_task = "water"
					v.planting = false
					v._go_to_plot(pl)
					var sounds := 0
					var was := -1.0
					for i in 900:
						await get_tree().process_frame
						if v.state == Villager.State.FARM and v._next_till != was:
							was = v._next_till
							sounds += 1
						if not fm.dry(pl):
							break
					print("Watering: watered ", not fm.dry(pl), ", sounds while at it ", sounds)
				"wardglow":
					# A cleansing crystal beside the village's teleport crystal, close up: both glowing and sparkling.
					var tp: Array = world.props_named("TeleportCrystal")
					var near_tp: Vector2 = tp[0] if not tp.is_empty() else miko.position
					var wc := world.floors.cell_at(near_tp) + Vector2i(2, -2)
					world.props.place(wc, "CleansingCrystal")
					miko.place((near_tp + world.floors.cell_centre(wc)) / 2.0 + Vector2(0, 0.9) * world.px)
					camera.zoom *= 1.5
					for i in 90:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_day.png")
					clock.hours = float(clock.day()) * 24.0 + 22.0
					for i in 90:
						await get_tree().process_frame
				"shikitree":
					# The rebuilt shikigami tree: an old save's points come back; every node learnt, its stats; how many
					# of each shikigami can be out; crits and double thrusts on a dummy.
					var st: CharacterStats = miko.stats
					var old := JSON.parse_string(st.to_json()) as Dictionary
					old.erase("tree")
					old.talentIds = ["start", "s0", "sa2", "sd2", "sa6"]
					old.talentRanks = [1, 1, 1, 1, 1]
					old.talentPoints = 2
					st.from_json(JSON.stringify(old))
					print("Shiki tree: old save -> points ", st.talent_points, ", ranks ", st.ranks.keys())
					for tl in st.character.talents:
						if str(tl.region) == "Shikigami":
							st.ranks[tl.id] = 1
					st.changed.emit()
					var tot := st.total()
					for k in ["magic", "castSpeed", "summonAttackSpeed", "summonDoubleAttack", "summonCritChance", "summonCritDamage", "summonSeconds", "summonMagicToAttack", "summonHeal", "healDuration", "lastingHeal", "shieldPower", "shieldManaRegen", "attackerSummons", "healerSummons", "defenderSummons"]:
						print("  ", k, " ", tot.get(k, 0))
					print("Shiki tree: a node in words: '", CharacterStats.describe(st._talents["k5"].perRank), "', '", CharacterStats.describe(st._talents["u1"].perRank), "'")
					var caster_node: SpellCaster = world.get_node("Caster")
					var sd: Dictionary = world._load_json("res://data/shikigami.json")
					var out_now := func() -> Array:
						var by := {}
						for a in Shikigami.active:
							if is_instance_valid(a) and a.dismissed_at < 0.0:
								by[a.kind] = int(by.get(a.kind, 0)) + 1
						return [by]
					for spell in ["ShikigamiAttacker", "ShikigamiAttacker", "ShikigamiAttacker", "ShikigamiHealer"]:
						Shikigami.summon(world, spell, sd[spell], miko, st, caster_node, miko.position + Vector2(1, 0) * world.px)
					await get_tree().process_frame
					print("Shiki out after 3 attackers and a healer: ", out_now.call())
					var at0: Shikigami = Shikigami.active.filter(func(a): return is_instance_valid(a) and a.kind == "Attacker" and a.dismissed_at < 0.0)[0]
					print("Attacker power ", snappedf(at0.power, 0.1), " (magic ", tot.magic, "), lasts ", snappedf(at0.ends_at - at0.born_at, 0.1), " s")
					var dummy := Damageable.new()
					dummy.position = miko.position + Vector2(1.5, 0.3) * world.px
					world.things.add_child(dummy)
					dummy.setup(world, Damageable.Team.ENEMY, 5000.0, 0.35 * world.px, 1.2 * world.px)
					dummy.dummy = true
					dummy.hit_by_player = true
					var hits := []
					dummy.damaged.connect(func(amt): hits.append(snappedf(amt, 0.1)))
					var crit_shot := false
					var seen := 0
					for i in int(Shots.arg("shikiframes", "900")):
						await get_tree().process_frame
						if hits.size() > seen:
							seen = hits.size()
							if not crit_shot and float(hits[-1]) > at0.power * 1.5:
								crit_shot = true
								miko.place(dummy.position + Vector2(-1.5, 1.0) * world.px)
								for k in 8:
									await get_tree().process_frame
								get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_crit.png")
					print("Shiki hits on the dummy: ", hits.size(), " ", hits.slice(0, 16))
				"hearthbody":
					# Every Hearth and Body talent learnt: the stats, the bag, the rabbits, the villagers' pace, a shove,
					# blocked hits, and Second Wind saving her once.
					var st: CharacterStats = miko.stats
					var slots0 := miko.bag.capacity()
					var rpens: RabbitPens = find_child("RabbitPens", true, false)
					var breed0 := rpens._breed_hours()
					for tl in st.character.talents:
						if str(tl.region) in ["Hearth", "Body"]:
							st.ranks[tl.id] = 1
					st.changed.emit()
					var tot := st.total()
					var shown := []
					for k in ["gatherSpeed", "woodYield", "stoneYield", "harvestBonus", "foodKeeps", "cookSpeed", "cookBonus", "craftBonus", "bagSlots", "rabbitBreeding", "butcherBonus", "villageWork", "maxHp", "defense", "calmRegen", "mistResist", "hungerResist", "knockResist", "blockChance", "secondWind"]:
						shown.append("%s %s" % [k, str(tot.get(k, 0))])
					print("Hearth/Body stats: ", ", ".join(shown))
					print("Bag slots ", slots0, " -> ", miko.bag.capacity(), "; rabbits breed every ", breed0, " -> ", snappedf(rpens._breed_hours(), 0.1), " h")
					miko.place(world.village.centre() + Vector2(1, 1) * world.px)
					for i in 400:
						await get_tree().process_frame
					print("Villagers' pace with Miko in the village: ", Villagers.heart)
					miko.knock(Vector2(100, 0), 0.2)
					print("A shove of 100 becomes ", snappedf(miko._knock.length(), 0.1))
					var blocks := [0]
					st.blocked.connect(func(): blocks[0] += 1)
					for i in 400:
						st.hp = float(tot.maxHp)
						st.damage(1.0)
					print("Blocked ", blocks[0], " of 400 hits")
					st.hp = float(tot.maxHp)
					st.damage(99999.0)
					print("Second Wind: after a felling blow HP ", st.hp)
					st.damage(99999.0)
					print("Second Wind: hit again at once, HP ", st.hp)
					for i in 60:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_wind.png")
					for i in 500:
						await get_tree().process_frame
					print("Second Wind: a few seconds on HP ", snappedf(st.hp, 0.1), " of ", tot.maxHp, "; statuses ", (miko.get_node("Needs") as Needs).effects().map(func(x): return x[0]))
					st.damage(99999.0)
					print("Second Wind: felled again while it waits, HP ", st.hp)
				"headbars":
					# Hurt and short of mana: the bars over her head; then full again: gone.
					miko.stats.damage(40.0)
					miko.stats.spend_mana(30.0)
					camera.zoom *= 1.6
					for i in 30:
						await get_tree().process_frame
					var hb: HeadBars = miko.get_node("HeadBars")
					print("Head bars: showing hurt ", hb.visible)
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_hurt.png")
					miko.stats.hp = miko.stats.stat("maxHp")
					miko.stats.mana = miko.stats.stat("maxMana")
					for i in 400:
						await get_tree().process_frame
					print("Head bars: showing when full ", hb.visible)
				"wardshiki":
					# A shield shikigami out, a slime and a mutated villager coming at Miko: they turn on it, it wards her
					# and stands its ground; then she walks off and it follows.
					var st: CharacterStats = miko.stats
					var caster_node: SpellCaster = world.get_node("Caster")
					var sd: Dictionary = world._load_json("res://data/shikigami.json")
					var md: Dictionary = world._load_json("res://data/monsters.json")
					var ward := Shikigami.summon(world, "ShikigamiDefender", sd["ShikigamiDefender"], miko, st, caster_node, miko.position)
					var sl: Slime = Slime.spawn(world, md.slime, false, miko.position + Vector2(3.0, 0.5) * world.px, 1.0)
					sl.angry_until = Creature.now() + 999.0
					var mv := MutatedVillager.spawn(world, md.mutatedVillager, miko.position + Vector2(-3.0, 0.8) * world.px)
					mv.raid_to = miko.position
					var hp0: float = st.hp
					var ward_hp0: float = ward.hp
					var warded := false
					var shot := false
					var stood := Vector2.ZERO
					for i in int(Shots.arg("wardframes", "1100")):
						await get_tree().process_frame
						if not is_instance_valid(ward):
							print("Ward shiki: struck down at frame ", i)
							break
						warded = warded or ward.bubble != null
						if ward.holding and stood == Vector2.ZERO:
							stood = ward.position
						if i % 180 == 0:
							print("Ward shiki ", floori(i / 60.0), ": slime on it ", is_instance_valid(sl) and sl.taunted_by == ward, ", mutant on it ", is_instance_valid(mv) and mv.taunted_by == ward, ", ward up ", ward.bubble != null, ", holding ", ward.holding, ", its HP ", roundi(ward.hp), "/", roundi(ward_hp0), ", her HP ", roundi(st.hp), "/", roundi(hp0))
						if not shot and ward.bubble != null and i > 120:
							shot = true
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_ward.png")
					if is_instance_valid(ward):
						print("Ward shiki: warded ", warded, ", moved while holding ", snappedf(ward.position.distance_to(stood) / world.px, 0.1), " units")
						miko.place(miko.position + Vector2(9.0, 0) * world.px)
						for i in 240:
							await get_tree().process_frame
						if is_instance_valid(ward):
							print("Ward shiki: she went 9 units off; it's ", snappedf(ward.position.distance_to(miko.position) / world.px, 0.1), " units from her, holding ", ward.holding)
				"mikohit":
					# Miko hit: mid-flinch, her tint and jolt (and a picture).
					camera.zoom *= 1.8
					for i in 10:
						await get_tree().process_frame
					miko.stats.damage(10.0)
					for i in 5:
						await get_tree().process_frame
					print("Miko hit: tint ", miko.art.self_modulate, ", jolt ", miko.wading.extra, ", material ", miko.art.material)
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_hit.png")
				"bedtaken":
					# Miko beside a villager's bed: free, the sleep prompt shows; with the villager in it, it doesn't.
					while Villager.all.is_empty():
						await get_tree().process_frame
					var nd: Needs = miko.get_node("Needs")
					var sleeper: Villager = null
					for v in Villager.all:
						if not v.home.is_empty():
							sleeper = v
							break
					if sleeper == null:
						print("Bed taken: no villager with a bed")
					else:
						var bed_at: Vector2 = sleeper.home.pos
						miko.place(bed_at + Vector2(0.5, 0.4) * world.px)
						for i in 20:
							await get_tree().process_frame
						print("Bed taken: free bed, prompt '", nd.prompt.text, "' showing ", nd.prompt.visible)
						Needs.occupants[Needs.bed_key(bed_at)] = sleeper
						for i in 20:
							await get_tree().process_frame
						var found: Dictionary = nd.nearest_bed(miko.position, float(nd.s.bedRange) * world.px)
						print("Bed taken: with ", sleeper.person.name, " in it, prompt showing ", nd.prompt.visible, ", still marked taken ", Needs.occupants.has(Needs.bed_key(bed_at)), ", bed found for her ", "none" if found.is_empty() else ("the same one" if found.pos.distance_to(bed_at) < 1.0 else "another, %.1f units from it" % (found.pos.distance_to(bed_at) / world.px)))
				"wallhit":
					# A barricade struck: mid-flinch, its tint and shake; then back as it was.
					var c0 := world.floors.cell_at(miko.position) + Vector2i(1, -2)
					var eh := WallMap.Edge.new(c0, false)
					world.walls.place(eh, "Barricade", true)
					camera.zoom *= 1.6
					for i in 10:
						await get_tree().process_frame
					world.walls.damage(eh.key(), 20.0)
					for i in 6:
						await get_tree().process_frame
					var art: Node2D = world.walls.nodes_of(eh)[0].get_child(0)
					print("Wall hit: tint ", art.self_modulate, ", shaken ", snappedf(art.position.x - float(art.get_meta("rest_x")), 0.1))
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_hit.png")
					for i in 80:
						await get_tree().process_frame
					print("Wall hit after: tint ", art.self_modulate, ", shaken ", snappedf(art.position.x - float(art.get_meta("rest_x")), 0.1))
				"aoe":
					# Two dummies 1.2 units apart: one staff swing between them, then one fireball at the first; who's hit.
					var hits := {}
					var dums := []
					for k in 2:
						var dm := Damageable.new()
						dm.position = miko.position + Vector2(0.9, -0.3 + 0.6 * k) * world.px
						world.things.add_child(dm)
						dm.setup(world, Damageable.Team.ENEMY, 5000.0, 0.3 * world.px, 1.0 * world.px)
						dm.dummy = true
						hits[k] = []
						dm.damaged.connect(func(a): (hits[k] as Array).append(roundi(a)))
						dums.append(dm)
					print("Aoe: dummies ", snappedf(dums[0].position.distance_to(dums[1].position) / world.px, 0.01), " units apart on screen")
					var ml: Melee = find_child("Melee", true, false)
					ml._toward = Vector2.RIGHT
					ml._strike()
					print("Aoe: one staff swing hit ", hits)
					hits[0] = []
					hits[1] = []
					for k in 2:
						dums[k].position = miko.position + Vector2(3.0 + 1.3 * k, 0) * world.px
					var cn: SpellCaster = world.get_node("Caster")
					cn.cast_at("Fireball", dums[0].position)
					for i in 120:
						await get_tree().process_frame
						if i == 40:
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_boom.png")
					print("Aoe: one fireball at the first hit ", hits)
				"mountains":
					# The cave's mouth at the mountains' foot; then into it, and out again.
					var foot := Mountains.EDGE + 1 - Mountains.DEPTH
					miko.place(world.floors.corner(Vector2(foot - 3.0, 0.5)))
					camera.zoom *= float(Shots.arg("zoom", "0.45"))
					for i in 30:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_range.png")
					print("Mountains: build on the rock ", not Mountains.covers(Vector2i(foot + 2, 20)), ", mist at the mouth ", world.mist.tier_at(miko.position))
					miko.place(world.floors.corner(Vector2(foot + 2.0, 0.0)))
					for i in 90:
						await get_tree().process_frame
					print("Mountains: in the cave ", Mountains.in_cave(miko.position), ", mist there ", world.mist.tier_at(miko.position))
					camera.zoom /= float(Shots.arg("zoom", "0.45"))
					for i in 10:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_cave.png")
					miko.place(Mountains.active._exit())
					for i in 90:
						await get_tree().process_frame
					print("Mountains: out again, in the cave ", Mountains.in_cave(miko.position), ", at cell ", world.floors.cell_at(miko.position))
				"edges":
					# The map's four edges and where the river leaves it, zoomed out: what shows past them.
					camera.zoom *= float(Shots.arg("zoom", "0.35"))
					var spots := {"sw": Vector2(-138, 0), "se": Vector2(0, -138), "nw": Vector2(0, 138), "south": Vector2(-138, -138), "west": Vector2(-138, 138), "east": Vector2(138, -138)}
					if Shots.arg("at") != "":
						var xy := Shots.arg("at").split(",")
						spots = {"at": Vector2(float(xy[0]), float(xy[1]))}
					for k in spots:
						miko.place(world.floors.corner(spots[k]))
						for i in 40:
							await get_tree().process_frame
						get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_" + k + ".png")
				"villager3":
					# The three looks side by side, standing; then the third one's poses in turn (--pose=walkDown...).
					while Villager.all.size() < 2:
						await get_tree().process_frame
					var vs: Villagers = find_child("Villagers", true, false)
					var shown := []
					for k in 3:
						var who := {"name": "Look %d" % k, "look": k}
						vs._fix(who)
						var v := Villager.new()
						v.setup(world, vs, vs._look_for(who), who, {})
						world.things.add_child(v)
						v.position = miko.position + Vector2(-1.6 + k * 1.1, 0.9) * world.px
						v.set_physics_process(false)
						v.set_process(false)
						shown.append(v)
					camera.zoom *= 2.2
					miko.place(miko.position + Vector2(-0.5, 0.2) * world.px)
					for i in 10:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_stand.png")
					var third: Villager = shown[2]
					for pose in ["idleUp", "walkDown", "walkUp", "mineDown", "mineUp", "chopDown", "chopUp", "cookDown", "cookUp", "stabDown", "stabUp", "sleepDown", "sleepUp"]:
						for k in 3:
							var vv: Villager = shown[k]
							var ids: Variant = vv.s.get(pose)
							var list: Array = ids if ids is Array else [ids]
							if not list.is_empty():
								vv._show(int(list[mini(list.size() - 1, int(Shots.arg("frame", "5")) if list.size() > 4 else 1)]))
						for i in 3:
							await get_tree().process_frame
						get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_" + pose + ".png")
					print("Villager 3: shown, look 2 of ", vs.d.looks.size(), ", ", third.person.name)
				"cold":
					# Winter: out in the open, in the snow, by a lit fire; what she suffers each time. And a villager
					# lighting a fire by day.
					var nd: Needs = miko.get_node("Needs")
					var fr: Fires = miko.get_node("Fires")
					clock.forced = -1
					clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 10.0
					var names := func() -> Array: return nd.effects().map(func(x): return x[0])
					miko.place(world.village.centre() + Vector2(9.0, 6.0) * world.px)
					for f in fr.fires:
						fr.lit_until.erase(f.key)
					for w in [GameClock.Weather.CLEAR, GameClock.Weather.SNOW]:
						clock.forced = w
						for i in 20:
							await get_tree().process_frame
						print("Cold: ", GameClock.WEATHER_NAMES[w], " out in the open -> ", nd.cold(), " ", names.call(), ", move speed ", miko.stats.stat("moveSpeed"))
					var bon: Dictionary = fr.fires.filter(func(f): return not bool(f.s.torch))[0]
					miko.place(bon.pos + Vector2(1.2, 0.6) * world.px)
					for i in 20:
						await get_tree().process_frame
					print("Cold: by an unlit fire -> ", nd.cold())
					fr.light(bon)
					for i in 20:
						await get_tree().process_frame
					print("Cold: by it lit -> ", nd.cold(), ", it burns ", snappedf(float(fr.lit_until[bon.key]) - clock.hours, 0.1), " h")
					fr.lit_until.erase(bon.key)
					world.village.put_in_stash("Wood", 20)
					world.village.put_in_stash("Stone", 20)
					for i in int(Shots.arg("coldframes", "1500")):
						await get_tree().process_frame
					print("Cold: villagers lit by day ", fr.fires.filter(func(f): return fr.lit(f)).size(), " of ", fr.fires.size(), " fires and torches (hour ", snappedf(clock.hour(), 0.1), ")")
				"seeddrop":
					# 40 slimes felled: how many dropped a seed, and which.
					var md: Dictionary = world._load_json("res://data/monsters.json")
					var before := world.get_children().filter(func(n): return n is Pickup).size()
					for i in 40:
						var sl: Slime = Slime.spawn(world, md.slime, false, miko.position + Vector2(6.0 + i * 0.1, 3.0) * world.px, 1.0)
						sl.hit.hurt(9999.0)
					for i in 5:
						await get_tree().process_frame
					var kinds := {}
					for n in get_tree().get_nodes_in_group("pickups") if get_tree().has_group("pickups") else []:
						kinds[n.resource] = int(kinds.get(n.resource, 0)) + 1
					var found := {}
					for n in world.find_children("*", "Pickup", true, false):
						found[str(n.get("resource"))] = int(found.get(str(n.get("resource")), 0)) + 1
					print("Seed drops from 40 slimes (", before, " pickups before): ", found)
					var vs: Villagers = find_child("Villagers", true, false)
					for i in 300:
						await get_tree().process_frame
					print("Villagers: up to ", vs.s.newcomersUpTo, " newcomers; here now ", vs.people.map(func(q): return "%s look %d" % [q.name, int(q.look)]))
				"winterload":
					# As loaded (the user's save: winter, weather pinned clear): how much snow lies. Then autumn's last
					# day, pinned clear, run on into winter: the pin drops and it snows.
					# (as if just loaded on winter's third morning, the weather pinned clear, no snow saved)
					clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 8.3
					clock.forced = GameClock.Weather.CLEAR
					snow.set_cover(0.0)
					snow._last_hours = -1.0
					for i in 150:
						await get_tree().process_frame
					print("Winter load: ", GameClock.SEASON_NAMES[clock.season()], " day ", clock.day_of_season(), ", weather ", GameClock.WEATHER_NAMES[clock.weather()], ", pinned ", clock.forced, ", snow lying ", snappedf(snow.cover, 0.01))
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_loaded.png")
					var first_w := float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4)) * 24.0
					clock.hours = first_w - 2.0 + (0.0 if clock.hours < first_w else float(clock.days_per_season * 4) * 24.0)
					clock.forced = GameClock.Weather.CLEAR
					snow.set_cover(0.0)
					for i in 5:
						await get_tree().process_frame
					print("Winter load: back in ", GameClock.SEASON_NAMES[clock.season()], ", pinned ", clock.forced, ", snow ", snappedf(snow.cover, 0.01))
					clock.hours += 5.0
					for i in 5:
						await get_tree().process_frame
					print("Winter load: 5 h on, ", GameClock.SEASON_NAMES[clock.season()], " day ", clock.day_of_season(), ", weather ", GameClock.WEATHER_NAMES[clock.weather()], ", pinned ", clock.forced, ", snow ", snappedf(snow.cover, 0.01))
				"snowmelt":
					# Deep winter, one bonfire and one torch burning: clear ground round them, none inside the houses.
					clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 9.0
					clock.forced = GameClock.Weather.CLOUDY
					snow._last_hours = -1.0
					var fr: Fires = miko.get_node("Fires")
					for i in 10:
						await get_tree().process_frame
					for f in fr.fires:
						fr.lit_until.erase(f.key)
					var bon: Dictionary = fr.fires.filter(func(f): return not bool(f.s.torch))[0]
					fr.light(bon)
					miko.place(bon.pos + Vector2(-3.0, 1.0) * world.px)
					camera.zoom *= 0.75
					for i in 90:
						await get_tree().process_frame
					print("Snow melt: snow ", snow.cover, ", lit ", fr.fires.filter(func(f): return fr.lit(f)).size(), ", houses ", world.roofs.roofs.size())
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_fire.png")
					# Into a house: its roof fades, the floor inside shows.
					var room: Dictionary = world.roofs.roofs[0].cells
					var inside: Vector2i = room.keys()[room.size() >> 1]
					miko.place(world.floors.cell_centre(inside))
					for i in 120:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_house.png")
				"footprints":
					# Deep winter: Miko walked across the snow, her prints behind her.
					clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 9.0
					snow._last_hours = -1.0
					var from := world.village.centre() + Vector2(6.0, 5.0) * world.px
					miko.place(from)
					for i in 20:
						await get_tree().process_frame
					for i in 120:
						miko.position = from + Vector2(i * 0.03, sin(i * 0.05) * 0.4) * world.px
						await get_tree().process_frame
					var fp: SnowFootprints = world.find_child("SnowFootprints", true, false)
					print("Footprints: ", fp._prints.size(), " pressed, snow under her ", snow.ground_snow(miko.position))
					camera.zoom *= 1.5
					for i in 5:
						await get_tree().process_frame
				"villagerdust":
					# A villager sent walking: the dust at their feet, beside Miko's as she walks.
					clock.hours = float(clock.day() - 1) * 24.0 + 10.0
					while Villager.all.is_empty():
						await get_tree().process_frame
					var v: Villager = Villager.all[0]
					v.position = miko.position + Vector2(1.5, 0.8) * world.px
					var most := 0
					var dust: DustTrail = null
					for d in world.things.get_children():
						if d is DustTrail and d.target == v:
							dust = d
					v.state = Villager.State.WALK
					v._set_goal(v.position + Vector2(5.0, 1.0) * world.px)
					camera.zoom *= 1.6
					for i in 150:
						await get_tree().process_frame
						if dust != null:
							most = maxi(most, dust.puffs.size())
						if i == 60:
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_walk.png")
					print("Villager dust: has a trail ", dust != null, ", most puffs at once ", most, ", walked ", snappedf(v.position.distance_to(miko.position) / world.px, 0.1), " units off")
				"sleepers":
					# Every housed villager put to bed: how far each is turned, and a close picture of each.
					clock.hours = float(clock.day() - 1) * 24.0 + 23.0
					for i in 200:
						await get_tree().process_frame
					camera.zoom *= 2.0
					var n := 0
					for v in Villager.all:
						if v.home.is_empty():
							continue
						if not v.in_bed:
							v._go_to_sleep()
						v.sleep_clock = 5.0
						miko.place(v.position + Vector2(0.9, 0.9) * world.px)
						miko.visible = false
						for i in 60:
							for r in world.roofs.roofs:
								for tl in r.tiles:
									if is_instance_valid(tl): (tl as CanvasItem).visible = false
							await get_tree().process_frame
						var fit: Array = Needs._fit(world, v.home, v.look.get("lying", {}).get("sleepUp" if v.facing_up else "sleepDown"), v.facing_right, 1.0)
						if fit.size() >= 5:
							print("  head lands ", ((v.position + (fit[4] as Vector2).rotated(v.art.rotation)) - fit[2]).round(), " px from the pillow, middle ", ((v.position + (fit[3] as Vector2).rotated(v.art.rotation)) - fit[1]).round(), " from the mattress's middle; pillow from middle ", ((fit[2] as Vector2) - fit[1]).round(), ", head from middle ", ((fit[4] as Vector2) - fit[3]).round())
						print("Sleeper ", v.person.name, " look ", int(v.person.look), ": turned ", snappedf(rad_to_deg(v.art.rotation), 0.1), " deg, bed turn ", int(v.home.e.turn))
						get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_%d.png" % n)
						n += 1
				"fireplace":
					# Winter evening: a fireplace put in one house; villagers light it; then who sleeps cold and who warm.
					clock.forced = -1
					clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 17.6
					var fr: Fires = miko.get_node("Fires")
					var room: Dictionary = world.roofs.roofs[0].cells
					var spot := Vector2i.ZERO
					for c in room:
						if world.props.peek_where(c, func(_n): return true) == "" and not BuildMode.active._use_cells().has(c):
							spot = c
					world.props.place(spot, "Fireplace")
					world.village.put_in_stash("Wood", 30)
					for i in 10:
						await get_tree().process_frame
					var hearth: Dictionary = fr.fires.filter(func(f): return bool(f.s.get("hearth", false)))[0]
					fr.lit_until.erase(hearth.key)
					var wood0 := world.village.stored("Wood")
					miko.place(world.floors.cell_centre(spot) + Vector2(0.8, 0.6) * world.px)
					for i in 1500:
						await get_tree().process_frame
						if fr.lit(hearth):
							break
					print("Fireplace: lit by a villager ", fr.lit(hearth), " (hour ", snappedf(clock.hour(), 0.1), "), burns ", snappedf(float(fr.lit_until.get(hearth.key, 0.0)) - clock.hours, 0.1), " h, wood ", wood0, " -> ", world.village.stored("Wood"), ", warm room ", fr.warm_room(room))
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_lit.png")
					clock.hours = floorf(clock.hours / 24.0) * 24.0 + 23.0
					for i in 400:
						await get_tree().process_frame
					for v in Villager.all:
						if not v.home.is_empty():
							print("  ", v.person.name, ": in bed ", v.in_bed, ", sleeping cold ", v._sleeping_cold())
				"winterwarn":
					# Autumn's last two days: what the village log says each.
					var fr: Fires = miko.get_node("Fires")
					clock.forced = -1
					var autumn := float(clock.days_per_season * ((GameClock.Season.AUTUMN - clock.start_season + 4) % 4)) * 24.0
					for back in [3, 2, 1]:
						clock.hours = autumn + float(clock.days_per_season - back) * 24.0 + 9.0
						fr._warned_day = -1
						for i in 5:
							await get_tree().process_frame
						print("Winter warning, ", back, " days of autumn left: ", VillageLog._entries.get("winter-coming", {}).get("text", "(nothing)"))
					print("Winter wood a day: ", fr.winter_wood_a_day(), " from ", fr.fires.size(), " fires")
				"upkeep":
					# Three days of weather on the houses; then one worn right down, and the villagers at it.
					var up := Upkeep.active
					clock.forced = GameClock.Weather.CLEAR
					clock.hours = float(clock.day() - 1) * 24.0 + 8.0
					for i in 5:
						await get_tree().process_frame
					print("Upkeep: houses ", up.houses().map(func(h): return "%d cells %d%% cost %s" % [h.cells.size(), roundi(h.condition), Upkeep.cost(h.cells)]))
					for d in 3:
						clock.hours += 24.0
						for i in 3:
							await get_tree().process_frame
					print("Upkeep: after 3 fair days ", up.houses().map(func(h): return roundi(h.condition)))
					for h in up.houses():
						up.condition[h.key] = 100.0
					var first: Dictionary = up.houses()[0]
					up.condition[first.key] = 20.0
					clock.hours = float(clock.day() - 1) * 24.0 + 9.0
					world.village.put_in_stash("Wood", 40)
					world.village.put_in_stash("Stone", 40)
					var wood0 := world.village.stored("Wood")
					var stone0 := world.village.stored("Stone")
					miko.place((first.middle as Vector2) + Vector2(-3.0, 2.5) * world.px)
					for i in int(Shots.arg("upframes", "2400")):
						await get_tree().process_frame
						if i % 300 == 0:
							print("Upkeep ", floori(i / 60.0), ": house ", roundi(up.condition[first.key]), "%, at it ", Villager.all.filter(func(v): return v.mend == first.key).map(func(v): return v.person.name + " " + Villager.State.keys()[v.state]))
						if i == 30:
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_worn.png")
					print("Upkeep end: house ", roundi(up.condition[first.key]), "%, wood ", wood0, " -> ", world.village.stored("Wood"), ", stone ", stone0, " -> ", world.village.stored("Stone"), ", saved ", up.to_json().left(80))
				"hearth":
					# In a house: where a fireplace may go (each cell's turn), one put against each back wall, lit; the
					# chimney over it, smoking; a house with none: no smoke.
					var bm := BuildMode.active
					var room: Dictionary = world.roofs.roofs[0].cells
					var by_turn := {}
					for c in room:
						var t := bm.hearth_turn(c)
						by_turn[t] = int(by_turn.get(t, 0)) + 1
					print("Hearth: cells by turn (-1 none, 0 back up-right, 1 back up-left) ", by_turn)
					var placed := []
					for want in [0, 1]:
						for c in room:
							if bm.hearth_turn(c) == want and world.props.peek_where(c, func(_n): return true) == "" and not bm._use_cells().has(c) and not placed.has(c):
								world.props.place(c, "Fireplace", 1.0, want)
								placed.append(c)
								break
					for c in room:
						if bm.hearth_turn(c) >= 0 or bm.hearth_turn(c) == -2:
							var why := bm.why_not(bm.item_for("Prop", "Fireplace"), world.floors.cell_centre(c))
							if why != ("Not in a corner" if bm.hearth_turn(c) == -2 else "") and not why.begins_with("Keep clear"):
								print("Hearth: cell ", c, " turn ", bm.hearth_turn(c), " refused '", why, "'")
					print("Hearth: a middle cell refused '", bm.why_not(bm.item_for("Prop", "Fireplace"), world.floors.cell_centre(room.keys().filter(func(c): return bm.hearth_turn(c) < 0)[0])), "'")
					var fr: Fires = miko.get_node("Fires")
					for i in 60:
						await get_tree().process_frame
					var smoking := func() -> Array: return world.roofs.roofs.map(func(r): return r.smoke != null and (r.smoke.get_child(0) as CPUParticles2D).emitting)
					print("Hearth: chimney of the house at ", world.roofs.roofs[0].chimney, ", fireplaces at ", placed, "; smoking ", smoking.call())
					for f in fr.fires:
						fr.lit_until.erase(f.key)
					for i in 60:
						await get_tree().process_frame
					print("Hearth: all fires out, smoking ", smoking.call())
					for f in fr.fires:
						if bool(f.s.get("hearth", false)):
							fr.light(f)
					miko.place(world.floors.cell_centre(room.keys()[12]))
					camera.zoom *= 1.4
					for i in 90:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_in.png")
					miko.place(world.floors.cell_centre(placed[0]) + Vector2(-5.0, 4.0) * world.px)
					for i in 150:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_out.png")
				"daily":
					# Seed kept back; the meals of a day; a torch out by a crystal lit; waking and off.
					var fm: Farming = miko.get_node("Farming")
					clock.forced = GameClock.Weather.CLEAR
					clock.hours = float(clock.day()) * 24.0 + 5.0
					for i in 150:
						await get_tree().process_frame
					var v := world.village
					print("Daily: plots in the village ", fm.plots.filter(func(q): return v.contains(q.pos, 3.0)).size(), ", a plot's crop ", fm._field_crop(fm.plots[0], func(_s: String) -> bool: return true))
					print("Daily: kept for planting ", v.reserve, "; potatoes ", v.stored("Potato"), ", spare ", v.spare("Potato"), "; plots ", fm.plots.size())
					v.stash["Potato"] = int(v.reserve.get("Potato", 0)) + 1
					v.stash["Potato"] = int(v.reserve.get("Potato", 0))
					print("Daily: at the reserve exactly, spare ", v.spare("Potato"), ", potato dish ", Kitchen.next(v).has("Potato"))
					v.put_in_stash("BakedPotato", 30)
					# A torch out by a crystal, well outside the village.
					var out := world.floors.cell_at(v.centre()) + Vector2i(ceili(v.half_size()) + 6, 0)
					world.props.place(out, "CleansingCrystal")
					world.props.place(out + Vector2i(2, 1), "Torch")
					var fr: Fires = miko.get_node("Fires")
					for i in 10:
						await get_tree().process_frame
					var far: Dictionary = fr.fires.filter(func(f): return world.floors.cell_at(f.pos) == out + Vector2i(2, 1))[0]
					fr.lit_until.erase(far.key)
					print("Daily: the torch by the crystal, outside the village: in the village ", v.contains(far.pos, 2.0), ", tended ", fr.tended(far))
					var eaten := {}
					for start in [6.9, 11.9, 17.6]:
						clock.hours = floorf(clock.hours / 24.0) * 24.0 + start
						var t0 := Time.get_ticks_msec()
						while Time.get_ticks_msec() - t0 < 50000:
							await get_tree().process_frame
							for vl in Villager.all:
								if vl.state == Villager.State.EATING and vl.get_meta("ate_at", -9.0) < clock.hours - 0.5:
									vl.set_meta("ate_at", clock.hours)
									eaten[vl.person.name] = (eaten.get(vl.person.name, []) as Array) + [snappedf(clock.hour(), 0.1)]
					print("Daily: by ", snappedf(clock.hour(), 0.1), " h, sat down to eat at ", eaten, "; hunger ", Villager.all.map(func(q): return roundi(q.person.hunger)), "; torch by the crystal lit ", fr.lit(far))
				"scarf":
					# Winter, snowing: a villager out in the open, cold; a scarf put in storage; they take it.
					clock.forced = -1
					clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4)) * 24.0 + 10.0
					while Villager.all.is_empty():
						await get_tree().process_frame
					var fr: Fires = miko.get_node("Fires")
					for f in fr.fires:
						fr.lit_until[f.key] = -1.0
					var vl: Villager = Villager.all[0]
					vl.position = world.village.centre() + Vector2(6.0, 5.0) * world.px
					for i in 30:
						await get_tree().process_frame
					print("Scarf: ", GameClock.WEATHER_NAMES[clock.weather()], ", ", vl.person.name, " chill ", vl.chill(), ", work pace ", snappedf(vl._tool_pace(), 0.01), ", greets '", ($Hud/Talk as Talk)._greeting(vl) if has_node("Hud/Talk") else "", "'")
					print("Scarf: recipe at the tool workbench ", world._load_json("res://data/build.json").workbenches.ToolWorkbench.recipes.filter(func(r): return r.item == "Scarf").size() if world._load_json("res://data/build.json").has("workbenches") else "?", ", item ", UiKit.item("Scarf").get("name", "?"))
					world.village.items.append("Scarf")
					for i in 400:
						await get_tree().process_frame
					print("Scarf: wearing one ", vl.person.get("scarf", false), ", chill ", vl.chill(), ", work pace ", snappedf(vl._tool_pace(), 0.01), ", scarves left in storage ", world.village.items.count("Scarf"))
				"ledger":
					# A day in which food and wood run down, hour by hour: what the log says.
					var lg: Ledger = $Ledger
					var v := world.village
					for f in Villager.FOODS:
						v.stash[f[0]] = 0
					v.stash["BakedPotato"] = 60
					v.stash["Wood"] = 40
					clock.hours = floorf(clock.hours) + 0.5
					lg.notes.clear()
					for h in 12:
						clock.hours += 1.0
						v.stash["BakedPotato"] = v.stored("BakedPotato") - 2
						v.stash["Wood"] = v.stored("Wood") - 1
						v.stash["Stone"] = v.stored("Stone") + 1
						for i in 3:
							await get_tree().process_frame
					print("Ledger: a day's change food ", roundi(lg.a_day("Food")), ", wood ", roundi(lg.a_day("Wood")), ", stone ", roundi(lg.a_day("Stone")))
					for k in ["Food", "Wood", "Stone"]:
						print("  ", k, ": ", VillageLog._entries.get("running-down:" + k, {}).get("text", "(nothing)"))
				"movefood":
					# A cellar built with 150 food up in the chests: the villagers carry it down, load by load.
					var cl: Cellars = $Cellars
					var v := world.village
					for r in Spoilage.PER_DAY:
						v.stash[r] = 0
					v.stash["Potato"] = 100
					v.stash["BakedPotato"] = 50
					clock.forced = GameClock.Weather.CLEAR
					clock.hours = float(clock.day() - 1) * 24.0 + 9.0
					for vl in Villager.all:
						vl.person.hunger = 100.0
					world.props.place(world.floors.cell_at(v.centre()) + Vector2i(4, -5), "Cellar", 1.0, 0)
					for i in 5:
						await get_tree().process_frame
					print("Move food: cellar holds ", cl.holds(), ", food ", cl.food_stored(), ", cold ", cl.cold, ", to move ", cl.to_move(), ", cold share ", cl.cold_share())
					var t0 := Time.get_ticks_msec()
					var last := -1
					while Time.get_ticks_msec() - t0 < int(Shots.arg("moveseconds", "100")) * 1000 and cl.to_move() > 0:
						await get_tree().process_frame
						if cl.cold != last:
							last = cl.cold
							var dn := world.props.node_at(world.floors.cell_at(v.centre()) + Vector2i(4, -5), 1)
							print("  doors open ", cl._open_until.size(), ", art ", world.sprites[int((dn.get_child(0) as Sprite2D).get_meta("sprite", 0))].name if dn != null else "no node")
							print("Move food ", floori((Time.get_ticks_msec() - t0) / 1000.0), " s: cold ", cl.cold, " of ", cl.holds(), ", movers ", Cellars.movers.keys().map(func(q): return q.person.name + " " + q.activity()))
					print("Move food end: cold ", cl.cold, ", food still ", cl.food_stored(), ", cold share ", snappedf(cl.cold_share(), 0.01), ", saved ", cl.to_json())
				"cellardoor":
					# The doors used three times in quick succession, then left: opened once, shut once.
					var cl: Cellars = $Cellars
					if Shots.arg("winter") != "":
						clock.forced = -1
						clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 10.0
						snow._last_hours = -1.0
					var door_at := world.floors.cell_centre(world.floors.cell_at(world.village.centre()) + Vector2i(4, -5))
					world.props.place(world.floors.cell_at(door_at), "Cellar", 1.0, 0)
					for i in 5:
						await get_tree().process_frame
					print("Cellar door: sounds ", snappedf(Sfx.stream(Cellars.OPEN_SOUND).get_length(), 0.1), " s open, ", snappedf(Sfx.stream(Cellars.CLOSE_SOUND).get_length(), 0.1), " s close")
					world.props.place(world.floors.cell_at(door_at) + Vector2i(4, 0), "Cellar", 1.0, 1)
					# One placed freely (off the grid), as with Alt held.
					var free_at := door_at + Vector2(-3.3, 1.7) * world.px
					world.props.place_free(free_at, "Cellar", 1.0, 0)
					for i in 5:
						await get_tree().process_frame
					cl.use_doors(free_at)
					var fn: Node2D = world.props.last_free_node()
					print("Cellar door: one placed freely shows ", world.sprites[int((fn.get_child(0) as Sprite2D).get_meta("sprite", 0))].name)
					miko.place(door_at + Vector2(2.0, 2.5) * world.px)
					for i in 5:
						await get_tree().process_frame
					cl.use_doors(world.floors.cell_centre(world.floors.cell_at(door_at) + Vector2i(4, 0)))
					var states := []
					for n in 3:
						cl.use_doors(door_at + Vector2(20, 30))
						if n == 1:
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_open.png")
						states.append(cl._open_until.size())
						for i in 60:
							await get_tree().process_frame
					var t0 := Time.get_ticks_msec()
					while not cl._open_until.is_empty() and Time.get_ticks_msec() - t0 < 15000:
						await get_tree().process_frame
					print("Cellar door: open after each use ", states, "; shut by itself after ", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1), " s more")
				"cookfetch":
					# A cook with raw food in storage: to storage first, then the fire; what's cooked.
					var v := world.village
					clock.forced = GameClock.Weather.CLEAR
					clock.hours = float(clock.day() - 1) * 24.0 + 9.5
					for r in Spoilage.PER_DAY:
						v.stash[r] = 0
					v.stash["Potato"] = 40
					v.reserve = {}
					var cook: Villager = null
					while Villager.all.size() < 2:
						await get_tree().process_frame
					for q in Villager.all:
						q.person.hunger = 100.0
						if q._cook_skill() > 0 and cook == null:
							cook = q
					print("Cook fetch: cook ", cook.person.name if cook != null else "none", ", goes ", cook._go_cook() if cook != null else false, ", '", cook.activity() if cook != null else "", "'")
					var seen := []
					var t0 := Time.get_ticks_msec()
					while cook != null and Time.get_ticks_msec() - t0 < 70000:
						await get_tree().process_frame
						var what := "%s%s" % [Villager.State.keys()[cook.state], " (holding %d %s)" % [cook._raw_left, cook._raw_kind] if cook._raw_left > 0 else ""]
						if seen.is_empty() or str(seen[-1]).split(" ")[0] != what.split(" ")[0]:
							seen.append(what)
						if cook.state == Villager.State.TO_COOK:
							cook.set_meta("dbg", "%.1f units from the fire, stuck %s, %.0f s left, leg %d of %d, goal %.1f from the fire" % [cook.position.distance_to(cook.stove.pos) / world.px, cook.steer.stuck, cook.state_until - Villager.now(), cook.leg, (cook.route as Array).size() if cook.route != null else -1, cook.target.distance_to(cook.stove.pos) / world.px])
						elif cook.has_meta("dbg"):
							print("Cook fetch: left TO_COOK for ", Villager.State.keys()[cook.state], " at ", cook.get_meta("dbg"))
							cook.remove_meta("dbg")
						if cook.state == Villager.State.STAND and seen.size() > 3:
							break
					print("Cook fetch: went ", seen)
					print("Cook fetch: potatoes ", v.stored("Potato"), ", baked ", v.stored("BakedPotato"))
				"routes":
					# Ways across the village: how many squares something solid stands on, and whether any planned way
					# steps on one (other than where it ends). Then every villager sent across it: who gets stuck.
					var solid := VillagerRoute.solid_squares(world)
					var c := world.village.centre()
					var h := world.village.half_size() * world.px * 0.8
					var ways := 0
					var none := 0
					var on_solid := 0
					for i in 200:
						var from_at := c + Vector2(randf_range(-h, h), randf_range(-h, h) * 0.5)
						var to_at := c + Vector2(randf_range(-h, h), randf_range(-h, h) * 0.5)
						var way: Variant = VillagerRoute.find(world, from_at, to_at)
						if way == null:
							none += 1
							continue
						ways += 1
						for k in (way as Array).size() - 1:
							if solid.has(world.floors.cell_at(way[k].at)) and world.floors.cell_at(way[k].at) != world.floors.cell_at(from_at):
								on_solid += 1
								break
					print("Routes: ", solid.size(), " solid squares; of 200 ways ", ways, " found, ", none, " none, ", on_solid, " stepping on something solid")
				"cellarsnow":
					# Deep winter: a chest down in the cellar, no snow on it.
					clock.forced = -1
					clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 10.0
					snow._last_hours = -1.0
					world.props.place(Cellars.AT + Vector2i(2, 3), "Chest")
					world.props.place(Cellars.AT + Vector2i(3, 3), "Chest")
					miko.place(world.floors.cell_centre(Cellars.AT + Vector2i(2, 1)))
					camera.zoom *= 1.5
					for i in 90:
						await get_tree().process_frame
					print("Cellar snow: snow lying ", snow.cover)
				"cellar":
					# A cellar put in a house: what it keeps cold, what spoils with and without it; down and back up.
					var cl: Cellars = $Cellars
					var v := world.village
					for r in Spoilage.PER_DAY:
						v.stash[r] = 0
					v.stash["Food"] = 80
					v.stash["Potato"] = 120
					print("Cellar: none yet, cold share ", cl.cold_share())
					var spot := world.floors.cell_at(v.centre()) + Vector2i(4, -5)
					world.props.place(spot, "Cellar", 1.0, 0)
					world.props.place(spot + Vector2i(4, 0), "Cellar", 1.0, 1)
					for i in 5:
						await get_tree().process_frame
					print("Cellar: one built, holds ", cl.holds(), " of 200 food: cold share ", cl.cold_share(), " (storage's food spoils at ", snappedf(1.0 - cl.cold_share() * (1.0 - Cellars.COLD_RATE), 0.01), " of the usual)")
					miko.place(world.floors.cell_centre(spot) + Vector2(2.0, 1.2) * world.px)
					miko.position = world.floors.cell_centre(spot) + Vector2(0.4, 1.3) * world.px
					for i in 30:
						await get_tree().process_frame
					print("Cellar: prompt '", cl.prompt.text, "' showing ", cl.prompt.visible)
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_door.png")
					cl._came_from = world.floors.cell_centre(spot)
					cl._go(true)
					for i in 90:
						await get_tree().process_frame
					print("Cellar: down there ", Cellars.inside(miko.position), ", mist ", world.mist.tier_at(miko.position))
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_down.png")
					miko.place(world.floors.cell_centre(cl._door_cell() + Vector2i(0, -1)))
					for i in 120:
						await get_tree().process_frame
					var vl: Villager = Villager.all[0]
					# A villager with potatoes: to the doors, down, and up again with them put away.
					clock.hours = float(clock.day() - 1) * 24.0 + 10.0
					vl.position = world.floors.cell_centre(spot) + Vector2(0.5, 2.5) * world.px
					vl.carrying = 3
					vl.carry_kind = "Potato"
					var had := v.stored("Potato")
					vl._go_store()
					var went_down := false
					for i in 900:
						await get_tree().process_frame
						if vl.state == Villager.State.CELLAR and not went_down:
							went_down = true
							print("Cellar: villager down there, in the room ", Cellars.room_has(world.floors.cell_at(vl.position)), ", '", vl.activity(), "'")
						if went_down and vl.state != Villager.State.CELLAR:
							break
					print("Cellar: villager went down ", went_down, ", back up ", snappedf(vl.position.distance_to(world.floors.cell_centre(spot)) / world.px, 0.1), " units from the doors, potatoes ", had, " -> ", v.stored("Potato"))
					vl.person.hunger = 5.0
					print("Cellar: hungry, heads for the cellar ", vl._go_eat() and vl._via_cellar)
					vl.carrying = 3
					vl.carry_kind = "Potato"
					vl._go_store()
					var food_goes := vl.target.distance_to(world.floors.cell_centre(spot)) / world.px
					vl.carry_kind = "Wood"
					vl._go_store()
					print("Cellar: a villager with potatoes heads ", snappedf(food_goes, 0.1), " units from the trapdoor; with wood, ", snappedf(vl.target.distance_to(world.floors.cell_centre(spot)) / world.px, 0.1))
					vl.carrying = 0
					var bm := BuildMode.active
					var in_room := Cellars.AT + Vector2i(1, 3)
					print("Cellar: building down there: a chest '", bm.why_not(bm.item_for("Prop", "Chest"), world.floors.cell_centre(in_room)), "', a bed '", bm.why_not(bm.item_for("Prop", "WoodenBed"), world.floors.cell_centre(in_room)), "', in bounds ", world.floors.in_bounds(in_room), ", no-build ", bm.no_build(in_room))
					miko.place(world.floors.cell_centre(Cellars.AT + Vector2i(2, 2)))
					for i in 10:
						await get_tree().process_frame
					bm.set_open(true)
					bm.select(bm.item_for("Prop", "Chest"))
					# (the mouse over the room: is anything of the interface taken to be under it?)
					var on_screen := get_viewport().get_canvas_transform() * world.floors.cell_centre(in_room)
					Input.warp_mouse(on_screen)
					var motion := InputEventMouseMotion.new()
					motion.position = on_screen
					motion.global_position = on_screen
					get_viewport().push_input(motion)
					for i in 5:
						await get_tree().process_frame
					var hovered := get_viewport().gui_get_hovered_control()
					print("Cellar: under the mouse in the room: ", str(hovered.name) if hovered != null else "nothing", ", taken as interface ", bm._over_ui())
					# R, then placed: turned?
					var key := InputEventKey.new()
					key.keycode = KEY_R
					key.pressed = true
					var turn0 := bm.prop_turn
					bm._unhandled_input(key)
					bm._place_prop(in_room + Vector2i(2, 0), 1.0)
					var placed_e: Dictionary = world.props.cells.get(Vector3i(in_room.x + 2, in_room.y, 0), {})
					print("Cellar: R pressed, turn ", turn0, " -> ", bm.prop_turn, "; a chest placed then has turn ", placed_e.get("turn", "?"), ", shown mirrored ", not placed_e.is_empty() and world.props.shown_flipped(placed_e))
					bm._place_prop(in_room, 1.0)
					print("Cellar: through build mode, chest status ", bm.status_of(bm.item_for("Prop", "Chest")), ", placed ", world.props.get_prop(in_room, 0), "; a bed there says '", bm.why_not(bm.item_for("Prop", "WoodenBed"), world.floors.cell_centre(in_room + Vector2i(1, 0))), "'")
					bm.set_open(false)
					world.props.place(in_room, "Chest")
					print("Cellar: a chest placed down there ", world.props.get_prop(in_room, 0), "; the villagers' chest spot is in the room ", Cellars.room_has(world.floors.cell_at(UseSpots.nearest_chest_spot(world, v.centre()))))
					print("Cellar: back up, ", snappedf(miko.position.distance_to(world.floors.cell_centre(spot)) / world.px, 0.1), " units from the trapdoor")
				"loothidden":
					# Loot dropped behind a house's back wall and out in the open: which is outlined.
					var room: Dictionary = world.roofs.roofs[0].cells
					var top := Vector2i(-99999, -99999)
					for c in room:
						if c.x + c.y > top.x + top.y:
							top = c
					var behind := world.floors.cell_centre(top + Vector2i(1, 1)) + Vector2(0, 0.2 * world.px)
					var open_at := world.village.centre() + Vector2(7.0, 5.0) * world.px
					var made := []
					for spot_at in [behind, open_at]:
						var pk := Pickup.launch_icon(world, "Crystal", 1, spot_at)
						pk.ground = spot_at
						pk.velocity = Vector2.ZERO
						pk.rise = 0.0
						pk.height = 0.0
						pk.landed_at = 0.0
						made.append(pk)
					miko.place(behind + Vector2(-3.0, 3.5) * world.px)
					for i in 60:
						await get_tree().process_frame
					print("Loot: behind the house, outlined ", (made[0].get_node("OccludedOutline") as OccludedOutline).covered, "; in the open, outlined ", (made[1].get_node("OccludedOutline") as OccludedOutline).covered)
				"plotjitter":
					# A 3x3 field, then one more plot placed beside it through build mode: what changes on the old plots
					# over the next frames (scales, places, what shows).
					var fm: Farming = miko.get_node("Farming")
					if Shots.arg("winter") != "":
						clock.forced = -1
						clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 12.0
						snow._last_hours = -1.0
					var bm := BuildMode.active
					var c0 := world.floors.cell_at(world.village.centre()) + Vector2i(5, 4)
					for x in 3:
						for y in 3:
							world.props.place(c0 + Vector2i(x, y), "FarmPlot")
					for i in 30:
						await get_tree().process_frame
					var snap := func() -> Array:
						var out := []
						for pl in fm.plots:
							if world.floors.cell_at(pl.pos) == c0 + Vector2i(3, 1):
								continue
							var holder: Node2D = pl.node
							var sp: Sprite2D = holder.get_child(0)
							var fl: Sprite2D = pl.flat.get_child(0)
							out.append([holder.scale, holder.position.round(), sp.scale, sp.visible, sp.get_meta("sprite", -1), fl.scale, fl.visible, fl.get_meta("sprite", -1), holder.modulate.a])
						return out
					var before: Array = snap.call()
					bm.set_open(true)
					bm.select(bm.item_for("Prop", "FarmPlot"))
					bm._place_prop(c0 + Vector2i(3, 1), 1.0)
					var seen := {}
					miko.place(world.floors.cell_centre(c0) + Vector2(-2.0, 0.5) * world.px)
					bm.set_open(false)
					for i in 40:
						await get_tree().process_frame
					var fr: Fires = miko.get_node("Fires")
					var lights_before := fr.fires.map(func(f): return f.light)
					world.props.place(c0 + Vector2i(3, 2), "FarmPlot")
					await get_tree().process_frame
					await get_tree().process_frame
					print("Plot jitter: fires' lights kept through a plot placed ", fr.fires.map(func(f): return f.light) == lights_before, " (", fr.fires.size(), " fires)")
					for i in 60:
						await get_tree().process_frame
						if i < 24 or i == 59:
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_f%02d.png" % i)
						var now_is: Array = snap.call()
						if now_is.size() != before.size():
							seen["count %d -> %d" % [before.size(), now_is.size()]] = i
							continue
						for j in now_is.size():
							for k in 9:
								if now_is[j][k] != before[j][k]:
									var what: String = ["holder scale", "holder place", "crop scale", "crop shown", "crop art", "soil scale", "soil shown", "soil art", "alpha"][k]
									if not seen.has(what):
										seen[what] = "frame %d: %s -> %s" % [i, before[j][k], now_is[j][k]]
					print("Plot jitter: plots ", fm.plots.size(), "; changed on the old plots: ", seen)
				"wintersnow":
					# The weather through the last day of autumn and the first two of winter, for a few weather seeds.
					var first_winter := float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4)) * 24.0
					print("Winter snow: weather pinned by hand ", clock.forced)
					clock.forced = -1
					for seed_now in [1234, 1, 99]:
						clock.weather_seed = seed_now
						var seen := []
						for h in range(-24, 48, 6):
							clock.hours = first_winter + h + 1.0
							clock._slot = -1
							clock._update_weather()
							seen.append("%s d%d %s" % [GameClock.SEASON_NAMES[clock.season()], clock.day_of_season(), GameClock.WEATHER_NAMES[clock.weather()]])
						print("Winter snow (seed ", seed_now, "): ", seen)
				"margin":
					# Walls just past the village's edge: a plank wall can't go there, a barricade or gate can (up to 2 tiles).
					for i in 3:
						await get_tree().process_frame
					var bm := BuildMode.active
					var edge_cell := world.floors.cell_at(world.village.centre()) + Vector2i(0, ceili(world.village.half_size()))
					for off in [0, 1, 2, 3, 4]:
						var e := WallMap.Edge.new(edge_cell + Vector2i(0, off), false)
						print("Margin +", off, ": PlankWall out ", bm._wall_outside(e, "PlankWall", false), ", Barricade out ", bm._wall_outside(e, "Barricade", false), ", Gate out ", bm._wall_outside(e, "Gate", false))
				"flee":
					# A villager at 15% health with a mutated villager a few steps off: they run; distance and state each second.
					clock.hours = float(clock.day() - 1) * 24.0 + 10.0
					while Villager.all.is_empty():
						await get_tree().process_frame
					var v: Villager = Villager.all[0]
					v.position = world.village.centre() + Vector2(1.0, 1.0) * world.px
					v.hit.hp = v.hit.max_hp * 0.15
					var md: Dictionary = world._load_json("res://data/monsters.json")
					var mv := MutatedVillager.spawn(world, md.mutatedVillager, v.position + Vector2(2.5, 0.0) * world.px)
					mv.raid_to = v.position
					miko.place(v.position + Vector2(-1.0, 2.5) * world.px)
					var shot := false
					for i in int(Shots.arg("fleeframes", "600")):
						await get_tree().process_frame
						if i % 60 == 0:
							print("Flee ", floori(i / 60.0), " s: ", Villager.State.keys()[v.state], ", ", snappedf(v.position.distance_to(mv.position) / world.px, 0.1), " units from it, HP ", roundi(v.hit.hp), " '", v.activity(), "'")
						if not shot and v.state == Villager.State.FLEE and i > 20:
							shot = true
							miko.place(v.position + Vector2(-1.5, 2.0) * world.px)
							for k in 3:
								await get_tree().process_frame
							print("Flee shot: ", v.person.name, " bark showing ", v._bark != null and v._bark.visible)
						if i == 450:
							miko.place(v.position + Vector2(-1.5, 2.0) * world.px)
							for k in 3:
								await get_tree().process_frame
							print("Flee later: emote showing ", v.emote != null and v.emote.visible, ", bark ", v._bark != null and v._bark.visible, " ", v._bark.text if v._bark != null else "", ", mood ", v.mood, ", bubble ", v.bubble != null and v.bubble.visible)
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_cry.png")
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_run.png")
						if not is_instance_valid(v):
							print("Flee: the villager died")
							break
				"gate":
					# A barricade row with a gate in it each way: shut, then open as Miko comes up to it.
					var c0 := world.floors.cell_at(miko.position) + Vector2i(1, -1)
					for i in [-4, -2, 2, 4]:
						world.walls.place(WallMap.Edge.new(c0 + Vector2i(i, 0), false), "Barricade")
						world.walls.place(WallMap.Edge.new(c0 + Vector2i(7, i + 3), true), "Barricade")
					var gx := WallMap.Edge.new(c0, false)
					var gy := WallMap.Edge.new(c0 + Vector2i(7, 3), true)
					world.walls.place(gx, Shots.arg("gate", "Gate"))
					world.walls.place(gy, "PlankGate" if Shots.arg("gate", "Gate") == "Gate" else "Gate")
					miko.place(world.floors.cell_centre(c0 + Vector2i(3, 4)))
					camera.zoom *= float(Shots.arg("zoom", "1.2"))
					for i in 20:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_shut.png")
					miko.place(world.walls.wall_middle(gx.key()) + Vector2(0, 0.5 * world.px))
					for i in 30:
						await get_tree().process_frame
					print("Gate open by her: ", world.walls.is_open(gx), " (", world.walls.walls.get(gx.key()), "), HP ", world.walls.hp.get(gx.key()))
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_open.png")
					miko.place(world.floors.cell_centre(c0 + Vector2i(3, 5)))
					for i in 240:
						await get_tree().process_frame
					print("Gate after she left: open ", world.walls.is_open(gx))
				"repair":
					# A worn barricade in the village in the morning: someone comes with wood to mend it.
					clock.hours = float(clock.day() - 1) * 24.0 + 9.0
					world.village.put_in_stash("Wood", 5)
					var cv := world.floors.cell_at(world.village.centre()) + Vector2i(3, 3)
					var ek := WallMap.Edge.new(cv, false)
					world.walls.place(ek, "Barricade")
					world.walls.damage(ek.key(), 110.0)
					miko.place(world.walls.wall_middle(ek.key()) + Vector2(-2.5, 1.5) * world.px)
					var shot := false
					var wood0 := world.village.stored("Wood")
					for i in int(Shots.arg("repairframes", "1800")):
						await get_tree().process_frame
						var who: Array = Villager.all.filter(func(v): return v.mend == ek.key())
						if i == 30:
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_worn.png")
						if i % 120 == 0:
							print("Repair ", floori(i / 60.0), " s: HP ", roundi(world.walls.hp.get(ek.key(), -1.0)), ", ", (who[0].person.name + " " + Villager.State.keys()[who[0].state]) if not who.is_empty() else "nobody on it")
						if not shot and not who.is_empty() and who[0].state == Villager.State.REPAIR:
							shot = true
							miko.place(who[0].position + Vector2(-1.5, 1.0) * world.px)
							for k in 20:
								await get_tree().process_frame
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_mend.png")
						if float(world.walls.hp.get(ek.key(), 0.0)) >= 150.0 and who.is_empty():
							break
					print("Repair end: HP ", world.walls.hp.get(ek.key(), -1.0), ", wood ", wood0, " -> ", world.village.stored("Wood"))
				"siege":
					# In the mist, a row of barricades between Miko and a mutated villager and an angry slime: they break it
					# down first, then come for her.
					var md: Dictionary = world._load_json("res://data/monsters.json")
					var home_at := miko.position
					for k in 400:
						var spot := home_at + Vector2.from_angle(randf() * TAU) * randf_range(14.0, 30.0) * world.px
						if world.mist.tier_at(spot) != Mist.Tier.CLEAR and Wilds.dry(world, spot, 6.0):
							miko.place(spot)
							break
					var c := world.floors.cell_at(miko.position)
					for i in range(-3, 4, 2):
						world.walls.place(WallMap.Edge.new(c + Vector2i(2, i), true), "Barricade")
					var east := world.floors.cell_centre(c + Vector2i(4, 0))
					var mv := MutatedVillager.spawn(world, md.mutatedVillager, east)
					var sl: Slime = Slime.spawn(world, md.slime, false, east + Vector2(0, 0.6 * world.px), 1.0)
					sl.angry_until = Creature.now() + 999.0
					var hp_of := func() -> Array: return world.walls.hp.keys().filter(func(k): return world.walls.walls.has(k) and world.walls.walls[k] == "Barricade").map(func(k): return roundi(world.walls.hp[k]))
					var hp0: float = miko.stats.hp
					var shot := false
					for i in int(Shots.arg("siegeframes", "900")):
						await get_tree().process_frame
						if i % 150 == 0:
							print("Siege ", floori(i / 60.0), " s: barricades ", hp_of.call(), ", villager ", MutatedVillager.State.keys()[mv.state], ", her HP ", roundi(miko.stats.hp))
						if not shot and mv.state == MutatedVillager.State.ATTACK and mv._bar_key != null:
							shot = true
							for k in 8:
								await get_tree().process_frame
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_hit.png")
					print("Siege end: barricades ", hp_of.call(), ", her HP ", hp0, " -> ", miko.stats.hp)
				"raid":
					# A raid sent now (at night): the horde comes at the village; where they are and who's hurt, every 5 s.
					clock.hours = float(clock.day() - 1) * 24.0 + 22.0
					var rd: Raids = $Raids
					var n := rd.start(int(Shots.arg("raiders", "6")))
					var c := world.village.centre()
					print("Raid: ", n, " raiders, nearest ", snappedf(rd.raiders.map(func(r): return r.position.distance_to(c)).min() / world.px, 0.1), " units off")
					var vhp := func() -> int: return Villager.all.map(func(v): return roundi(v.hit.hp)).reduce(func(a, b): return a + b, 0)
					var hp0: int = vhp.call()
					var shot := false
					for i in int(Shots.arg("raidframes", "1800")):
						await get_tree().process_frame
						if i % 300 == 0:
							var alive := rd.raiders.filter(func(r): return is_instance_valid(r))
							print("Raid ", floori(i / 60.0), " s: raiders in the village ", alive.filter(func(r): return world.village.contains(r.position)).size(), "/", alive.size(), ", nearest ", snappedf(alive.map(func(r): return r.position.distance_to(c)).min() / world.px if not alive.is_empty() else -1.0, 0.1), ", villagers' HP ", vhp.call(), "/", hp0)
						if not shot and rd.raiders.any(func(r): return is_instance_valid(r) and world.village.contains(r.position)):
							shot = true
							var r0: Node2D = rd.raiders.filter(func(r): return is_instance_valid(r) and world.village.contains(r.position))[0]
							miko.place(r0.position + Vector2(-2, 1.5) * world.px)
							for k in 30:
								await get_tree().process_frame
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_in.png")
					clock.hours += 10.0
					for i in 5:
						await get_tree().process_frame
					print("Raid at dawn: raiders still raiding ", rd.raiders.size())
				"mvdrop":
					# Ten mutated villagers killed: how many dropped a crystal.
					var md: Dictionary = world._load_json("res://data/monsters.json")
					var drops := 0
					for k in 10:
						var mv := MutatedVillager.spawn(world, md.mutatedVillager, miko.position + Vector2(2.0 + k * 0.3, 1.0) * world.px)
						await get_tree().process_frame
						var had := Pickup.all.size()
						mv.hit.hurt(9999.0, true)
						await get_tree().process_frame
						if Pickup.all.any(func(pk): return pk.resource == "Crystal") and Pickup.all.size() > had: drops += 1
						for pk in Pickup.all.duplicate(): pk.queue_free()
						Pickup.all.clear()
					print("Drops: ", drops, " of 10 dropped a crystal")
				"pathout":
					# A cobble path laid out of the village (and into the river, which mustn't take): which cells took it.
					var bm := BuildMode.active
					bm.set_open(true)
					for it in bm.items:
						if it.name == "PathCobble": bm.select(it)
					miko.bag.add("Stone", 50)
					var spot := Vector2.ZERO
					for k in 400:
						var p := world.village.centre() + Vector2.from_angle(randf() * TAU) * randf_range(18.0, 30.0) * world.px
						if not world.village.contains(p, 2.0) and not world.wet(p) and world.floors.get_laid(world.floors.cell_at(p)) == "":
							spot = p
							break
					var c := world.floors.cell_at(spot)
					var took := []
					for i in 3:
						bm._paint(c + Vector2i(i, 0), "PathCobble", false)
						took.append(world.floors.get_laid(c + Vector2i(i, 0)))
					print("Path outside the village: ", took)
					var wet_cell := Vector2i(999999, 0)
					for k in 2000:
						var p := spot + Vector2.from_angle(randf() * TAU) * randf_range(1.0, 60.0) * world.px
						if world.water_depth(p) > 0.5:
							wet_cell = world.floors.cell_at(p)
							break
					bm._paint(wet_cell, "PathCobble", false)
					print("Path in the water: '", world.floors.get_laid(wet_cell), "'")
					bm.set_open(false)
				"levelup":
					# Enough XP for a level: the effect, half a second in.
					miko.stats.gain_xp(miko.stats.xp_to_next() - miko.stats.xp)
					for i in int(Shots.arg("lvframes", "30")):
						await get_tree().process_frame
				"talk":
					# Beside a villager: the prompt, then talking (E): the panel; a reply (1); give food; bye.
					while Villager.all.is_empty():
						await get_tree().process_frame
					var v: Villager = Villager.all[0]
					miko.place(v.position + Vector2(0.6, 0.3) * world.px)
					miko.bag.add("Bread", 2)
					v.person.hunger = 30.0
					for i in 10:
						await get_tree().process_frame
					var tk: Talk = $Hud/Talk
					print("Talk: prompt '", tk.prompt.text, "' shown ", tk.prompt.visible)
					tk.open(v)
					for i in 5:
						await get_tree().process_frame
					print("Talk: ", v.person.name, " says '", tk._line.text, "', replies ", tk._acts.size())
					(tk._acts[1] as Callable).call()
					print("Talk: after food '", tk._line.text, "', hunger ", v.person.hunger)
					print("Tail: visible ", tk._tail.visible, " from ", tk._tail.from, " tip ", tk._tail.tip, " panel ", tk.position, tk.size, " tail global ", tk._tail.global_position)
					for i in 8:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_panel.png")
					tk._say_bye()
					for i in 10:
						await get_tree().process_frame
					print("Talk: closed, speed ", Engine.time_scale, ", bark '", v._bark.text if v._bark else "", "'")
				"doorsee":
					# Every door: whether its outline is showing (hidden behind its house); a picture by a hidden one.
					var hidden_at := Vector2.INF
					for i in 20:
						await get_tree().process_frame
					for o in get_tree().root.find_children("DoorOutline", "", true, false):
						var oc := o as OccludedOutline
						print("Door at ", oc.body.global_position.round(), " covered ", oc.covered, " outline shown ", snappedf(oc.shown, 0.1))
						if oc.covered and hidden_at == Vector2.INF:
							hidden_at = oc.body.global_position
					if hidden_at != Vector2.INF:
						miko.place(hidden_at + Vector2(-2.5, 2.0) * world.px)
						for i in 20:
							await get_tree().process_frame
				"starve":
					# Hunger to 0: her bubble, slower, and the pangs.
					var nd: Needs = miko.get_node("Needs")
					nd.hunger = 0.0
					var hp0: float = miko.stats.hp
					for i in 400:
						await get_tree().process_frame
					print("Starve: bubble '", nd._bubble_label.text if nd._bubble_label else "", "' HP ", hp0, " -> ", miko.stats.hp, " moveSpeed ", miko.stats.stat("moveSpeed"))
					nd._bubble_at = 0.0
					for i in 4:
						await get_tree().process_frame
				"bubbles":
					# Three villagers by Miko, saying, thinking and shouting; Miko starving.
					while Villager.all.size() < 3:
						await get_tree().process_frame
					var keys := ["bark.pests", "bark.hungry", "bark.raid"]
					for k in 3:
						var v: Villager = Villager.all[k]
						v.position = miko.position + Vector2(-2.6 + k * 2.6, -0.4) * world.px
						v.velocity = Vector2.ZERO
						v.bark(keys[k], {"miko": "Miko", "side": "east"}, true)
					var nd: Needs = miko.get_node("Needs")
					nd.hunger = 0.0
					miko.place(miko.position + Vector2(0, 1.6) * world.px)
					for i in 12:
						await get_tree().process_frame
					for k in 3:
						var v: Villager = Villager.all[k]
						if k == 1:
							camera.position = v.position + Vector2(0, -1.0 * world.px)
							camera.reset_smoothing()
							set_meta("warming", true)
							await get_tree().process_frame
							await get_tree().process_frame
							get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_villagers.png")
							remove_meta("warming")
						print("Bubble ", k, ": ", v._bark != null, " visible ", v._bark.visible if v._bark else false, " text '", v._bark.text if v._bark else "", "' at ", v._bark.global_position if v._bark else Vector2.ZERO, " villager ", v.global_position, " in tree ", v.is_inside_tree(), " vis ", v.is_visible_in_tree())
				"pestwatch":
					# A field of six growing plots, all with pests, by day: who goes to clear them, over a game hour or two.
					var fm: Farming = miko.get_node("Farming")
					clock.hours = float(clock.day() - 1) * 24.0 + 9.0
					var c0 := world.floors.cell_at(world.village.centre()) + Vector2i(3, 3)
					for k in 6:
						world.props.place(c0 + Vector2i(k % 3, floori(k / 3.0)), "FarmPlot")
					for i in 3:
						await get_tree().process_frame
					fm._look()
					var field := fm.field_of(fm.nearest(world.floors.cell_centre(c0), world.px))
					for pl in field:
						fm.sow(pl, "Wheat")
						fm._state(pl).pest = true
					print("Pests: field of ", field.size(), " in the village ", world.village.contains(field[0].pos, 3.0), "; villagers ", Villager.all.map(func(v): return [v.person.name, v.person.get("job", 0)]))
					for sec in int(Shots.arg("pestsecs", "60")):
						for i in 60:
							await get_tree().process_frame
						if sec % 10 == 0:
							print("Pests ", sec, " s: left ", field.filter(func(pl): return fm.pests(pl)).size(), "; doing ", Villager.all.map(func(v): return v.activity()))
				"moods":
					while Villager.all.size() < 3:
						await get_tree().process_frame
					var ms := ["affection", "idea", "alarm"]
					for k in 3:
						var v: Villager = Villager.all[k]
						v.position = miko.position + Vector2(-2.6 + k * 2.6, -0.4) * world.px
						v.show_mood(ms[k], 30.0)
					for i in int(Shots.arg("mframes", "40")):
						await get_tree().process_frame
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
					if Shots.arg("hour") != "": clock.hours = float(Shots.arg("hour"))
					if Shots.arg("say") != "":
						miko.stats.xp = floori(miko.stats.xp_to_next() * 0.6)
						FloatingText.spawn(world, Shots.arg("say"), miko.position + Vector2(0, -1.6 * world.px), Color(1, 0.6, 0.5))
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
