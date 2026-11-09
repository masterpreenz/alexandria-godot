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
	# Gathering, and her bag from the save.
	var miner := Miner.new()
	miner.name = "Miner"
	miko.add_child(miner)
	miner.setup(world, miko, world._load_json("res://data/gather.json").miner, $Hud)
	var sv: Dictionary = world._load_json("res://data/save.json") if FileAccess.file_exists("res://data/save.json") else {}
	if sv.get("sections", {}).has("player.bag"):
		miko.bag.from_json(sv.sections["player.bag"])
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
