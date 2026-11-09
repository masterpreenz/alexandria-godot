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
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/player.json"))
	miko = Miko.new()
	miko.name = "Miko"
	world.things.add_child(miko)
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
	var sv: Dictionary = world._load_json("res://data/save.json") if FileAccess.file_exists("res://data/save.json") else {}
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
	var hotbar := Hotbar.new()
	hotbar.name = "Hotbar"
	hotbar.theme = UiKit.theme
	$Hud.add_child(hotbar)
	hotbar.setup(world, caster, miko.bag, miko.stats)
	if sv.get("sections", {}).has("player.hotbar"):
		hotbar.from_json(sv.sections["player.hotbar"])
	hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 14)
	var bars := StatusBars.new()
	bars.stats = miko.stats
	bars.position = Vector2(16, 84)
	$Hud.add_child(bars)
	# Flinching when hit; fainting at 0 HP.
	miko.stats.hurt.connect(miko.flinch)
	var monsters: Dictionary = world._load_json("res://data/monsters.json") if FileAccess.file_exists("res://data/monsters.json") else {}
	world.set_meta("lost_bag_icon", int(monsters.get("lostBagIcon", -1)))
	if monsters.has("fainting"):
		var fainting := Fainting.new()
		fainting.name = "Fainting"
		miko.add_child(fainting)
		fainting.setup(world, miko, monsters.fainting, $Hud)
	# The bag window (I).
	var bag_window := BagWindow.new()
	bag_window.name = "BagWindow"
	bag_window.theme = UiKit.theme
	$Hud.add_child(bag_window)
	bag_window.setup(world, miko.bag)
	bag_window.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	bag_window.visible = Shots.arg("bag") != ""
	# Where the save left her.
	var saved_game: Dictionary = world._load_json("res://data/save.json") if FileAccess.file_exists("res://data/save.json") else {}
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
	var save: Dictionary = world._load_json("res://data/save.json") if FileAccess.file_exists("res://data/save.json") else {}
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
	camera.position_smoothing_speed = 1.0 / max(0.02, data.camera.smooth)
	# The camera is moved every frame to where she's drawn, so it isn't smoothed itself (that would lag it a tick).
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position = miko.position + follow_offset
	camera.reset_smoothing()
	await get_tree().process_frame
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
			print("Monster ", m.name if is_instance_valid(m) else "gone", " hp ", m.hit.hp if is_instance_valid(m) else 0.0, "; her hp ", hp0, " -> ", miko.stats.hp, "; creatures ", Creature.all.size(), "; lost bag ", Fainting.LostBag.active != null)
		if Shots.arg("wait") != "":
			# Let the world run this many frames before the shot (rabbits coming out, monsters about), for testing.
			for i in int(Shots.arg("wait")):
				await get_tree().process_frame
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
		camera.position = miko.position + follow_offset
		camera.reset_smoothing()
		var saved := camera.position
		Shots.take_if_asked(self, camera)
		camera.position = saved


func _process(delta: float) -> void:
	# Follow where she's drawn (smoothed between physics ticks), not her last physics step: otherwise, on a screen
	# faster than the physics rate, she and the world jump unevenly and look blurred while moving.
	camera.position = miko.drawn_position() + follow_offset
	time_label.text = "%s · %s, day %d · %s
Wood %d · Stone %d" % [clock.time_text(), GameClock.SEASON_NAMES[clock.season()], clock.day_of_season(), GameClock.WEATHER_NAMES[clock.weather()], miko.bag.count("Wood"), miko.bag.count("Stone")]


func _unhandled_input(event: InputEvent) -> void:
	Shots.wheel_zoom(event, camera, 0.25, 3.0)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BRACKETRIGHT: clock.hours += 1.0
		elif event.keycode == KEY_BRACKETLEFT: clock.hours = maxf(0.0, clock.hours - 1.0)
		elif event.keycode == KEY_F6: clock.set_weather((clock.weather() + 1) % 5)
