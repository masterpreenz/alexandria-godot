extends Node2D
## Phase 1: Miko walking about the exported world. The camera follows her (CameraFollow2D: a little above her,
## smoothed; the wheel zooms). The clock runs (GameClock: 12 minutes a day) and the light follows it (SkyEffects:
## night to day through a warm twilight). [ and ] move the clock an hour back or on.
## Command line: [code]-- --hour=h --at=x,y --shot=file.png[/code] (see [Shots]).

@onready var world: World = $World
@onready var camera: Camera2D = $Camera
@onready var light: CanvasModulate = $Daylight
@onready var time_label: Label = $Hud/Time

var miko: Miko
var data: Dictionary
var hours := 8.0
var seconds_per_day := 720.0
var follow_offset := Vector2.ZERO


func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/player.json"))
	miko = Miko.new()
	miko.name = "Miko"
	world.things.add_child(miko)
	miko.setup(world, data)
	world.player = miko
	var at := Shots.arg("at")
	if at != "":
		var p := at.split(",")
		miko.place(Vector2(float(p[0]), float(p[1])))
	seconds_per_day = data.clock.secondsPerDay
	hours = float(Shots.arg("hour", str(data.clock.startHour)))
	follow_offset = Vector2(data.camera.offset[0], data.camera.offset[1])
	# Unity's orthographic size is half the view's height, in units: the same view here.
	var view_h := float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	camera.zoom = Vector2.ONE * view_h / (2.0 * data.camera.ortho * world.px)
	camera.position_smoothing_speed = 1.0 / max(0.02, data.camera.smooth)
	# The camera is moved every frame to where she's drawn, so it isn't smoothed itself (that would lag it a tick).
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position = miko.position + follow_offset
	camera.reset_smoothing()
	_daylight()
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
		camera.position = miko.position + follow_offset
		camera.reset_smoothing()
		var saved := camera.position
		Shots.take_if_asked(self, camera)
		camera.position = saved


func _process(delta: float) -> void:
	# Follow where she's drawn (smoothed between physics ticks), not her last physics step: otherwise, on a screen
	# faster than the physics rate, she and the world jump unevenly and look blurred while moving.
	camera.position = miko.drawn_position() + follow_offset
	hours = fmod(hours + delta * 24.0 / seconds_per_day, 24.0 * 10000.0)
	_daylight()


func _unhandled_input(event: InputEvent) -> void:
	Shots.wheel_zoom(event, camera, 0.25, 3.0)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BRACKETRIGHT: hours += 1.0
		elif event.keycode == KEY_BRACKETLEFT: hours = max(0.0, hours - 1.0)


## How light it is outside: 0 at night, 1 in full day, in between at dawn and dusk.
func daylight() -> float:
	var h := fmod(hours, 24.0)
	if h < 5.0 or h >= 20.0: return 0.0
	if h < 7.0: return smoothstep(0.0, 1.0, (h - 5.0) / 2.0)
	if h < 18.0: return 1.0
	return smoothstep(1.0, 0.0, (h - 18.0) / 2.0)


func _daylight() -> void:
	var sky: Dictionary = data.sky
	var d := daylight()
	var warm := 1.0 - absf(d * 2.0 - 1.0)  # strongest half way through dawn and dusk
	var night := Color(sky.night[0], sky.night[1], sky.night[2])
	var day := Color(sky.day[0], sky.day[1], sky.day[2])
	var twilight := Color(sky.twilight[0], sky.twilight[1], sky.twilight[2])
	var c := night.lerp(day, d).lerp(twilight, warm * 0.6)
	var intensity := lerpf(sky.nightIntensity, sky.dayIntensity, d)
	light.color = Color(c.r * intensity, c.g * intensity, c.b * intensity, 1.0)
	var h := fmod(hours, 24.0)
	var hh := int(h)
	time_label.text = "%d:%02d %s" % [(hh + 11) % 12 + 1, int((h - hh) * 60.0), "AM" if hh < 12 else "PM"]
