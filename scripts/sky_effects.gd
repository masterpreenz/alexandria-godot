class_name SkyEffects
extends Node2D
## The sky over the world (from Unity's SkyEffects): the light through the day (night to day through a warm
## twilight, then greyer and dimmer under cloud, cooler in snow), drifting cloud shadows, rain and snow falling over
## the view, and in a storm lightning that flashes white with thunder a moment later. Indoors (under a roof) nothing
## falls, no shadows cross the floor, the rain sounds muffled and the lightning only glows.
##
## Weather changes ease in over a few seconds.

const RAIN_SPEED := 10.0   ## world units a second
const SNOW_SPEED := 0.8

var world: World
var clock: GameClock
var camera: Camera2D
var light: CanvasModulate
var sky: Dictionary               ## colours and intensities (data/player.json's sky)

var blend := 3.0
var lightning_gap := Vector2(5.0, 14.0)
var lightning_color := Color(0.85, 0.9, 1.0)
var lightning_boost := 1.6
var shadow_darkness := 0.42

var overcast := 0.0
var storm := 0.0
var shadows := 0.0
var wet := 0.0
var white := 0.0
var indoors := false
var _inside := 0.0
var _next_strike := 4.0
var _flash_time := -10.0
var _thunder_at := -1.0

var _rain: CPUParticles2D
var _snow: CPUParticles2D
var _shade: Node2D
var _shade_mat: ShaderMaterial
var _flash: ColorRect
var _rain_sound: AudioStreamPlayer
var _thunder: AudioStreamPlayer
var _muffle: AudioEffectLowPassFilter


func setup(w: World, c: GameClock, cam: Camera2D, modulate_node: CanvasModulate, sky_data: Dictionary, overlay: CanvasLayer) -> void:
	world = w
	clock = c
	camera = cam
	light = modulate_node
	sky = sky_data
	_rain = _fall(false)
	_snow = _fall(true)
	# Cloud shadows over the world, under rain and snow.
	_shade = ViewRect.new()
	_shade.camera = camera
	_shade_mat = ShaderMaterial.new()
	_shade_mat.shader = preload("res://shaders/cloud_shadows.gdshader")
	_shade_mat.set_shader_parameter("unit", world.px)
	_shade_mat.set_shader_parameter("darkness", shadow_darkness)
	_shade.material = _shade_mat
	_shade.z_as_relative = false
	_shade.z_index = 4060
	add_child(_shade)
	# A white sheet over everything for a flash (under the HUD).
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(lightning_color, 0.0)
	overlay.add_child(_flash)
	overlay.move_child(_flash, 0)
	# Sounds: the rain loop on its own bus (muffled indoors), and thunder.
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Rain")
	_muffle = AudioEffectLowPassFilter.new()
	_muffle.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(bus, _muffle)
	_rain_sound = AudioStreamPlayer.new()
	# A seamless copy of the rain loop (made from rain_loop.mp3 as Unity did at runtime: the MP3's quiet padding
	# trimmed off, its end crossfaded into its start), so it loops without a gap or a click.
	var loop: AudioStream = load("res://assets/Sounds/rain_loop_seamless.ogg")
	if loop is AudioStreamOggVorbis:
		(loop as AudioStreamOggVorbis).loop = true
	_rain_sound.stream = loop
	_rain_sound.bus = "Rain"
	add_child(_rain_sound)
	_thunder = AudioStreamPlayer.new()
	_thunder.stream = load("res://assets/Sounds/thunder.mp3")
	add_child(_thunder)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"sky_effects.process", __t)


func _process_timed(delta: float) -> void:
	var w := clock.weather()
	var step := delta / maxf(0.01, blend)
	var rainy := w == GameClock.Weather.RAIN or w == GameClock.Weather.STORM
	overcast = move_toward(overcast, 1.0 if rainy or w == GameClock.Weather.SNOW else 0.1 if w == GameClock.Weather.CLOUDY else 0.0, step)
	storm = move_toward(storm, 1.0 if w == GameClock.Weather.STORM else 0.0, step)
	shadows = move_toward(shadows, 1.0 if w == GameClock.Weather.CLOUDY else 0.15 if w == GameClock.Weather.CLEAR else 0.0, step)
	wet = move_toward(wet, 1.6 if w == GameClock.Weather.STORM else 1.0 if w == GameClock.Weather.RAIN else 0.0, step)
	white = move_toward(white, 1.0 if w == GameClock.Weather.SNOW else 0.0, step)
	indoors = world.player != null and world.roofs != null and world.roofs.covers(world.player.position)
	_light()
	_shade_mat.set_shader_parameter("strength", 0.0 if indoors else shadows * clock.daylight())
	_shade.visible = not indoors and shadows * clock.daylight() > 0.01
	_drive(_rain, 0.0 if indoors else wet, 500.0)
	_drive(_snow, 0.0 if indoors else white, 140.0)
	_sound(delta)


# Night to day through a warm twilight, then greyer and dimmer under cloud; lightning flashes over it.
func _light() -> void:
	var d := clock.daylight()
	var warm := 1.0 - absf(d * 2.0 - 1.0)
	var night := _c(sky.night)
	var c := night.lerp(_c(sky.day), d).lerp(_c(sky.twilight), warm * 0.6)
	c = c.lerp(c * Color(0.78, 0.8, 0.86), overcast)
	c = c.lerp(Color(0.9, 0.95, 1.05), white * 0.3)
	var intensity := lerpf(sky.nightIntensity, sky.dayIntensity, d) * lerpf(1.0, 0.75, overcast) * lerpf(1.0, 0.8, storm)
	var flash := _lightning()
	var lit := c * intensity
	lit = lit.lerp(lightning_color, clampf(flash, 0.0, 1.0)) * (1.0 + flash * lightning_boost * 0.4)
	light.color = Color(lit.r, lit.g, lit.b, 1.0)
	_flash.color = Color(lightning_color, flash * 0.35)


static func _c(a: Array) -> Color:
	return Color(a[0], a[1], a[2])


## A lightning strike now: a flash, and thunder a moment later.
func strike() -> void:
	var now := _now()
	_flash_time = now
	_next_strike = now + randf_range(lightning_gap.x, lightning_gap.y)
	_thunder_at = now + randf_range(0.3, 1.6)


# How bright the lightning is now: strikes come at random in a storm, flicker twice and fade.
func _lightning() -> float:
	var now := _now()
	if storm > 0.5 and now >= _next_strike:
		strike()
	if _thunder_at > 0.0 and now >= _thunder_at:
		_thunder_at = -1.0
		_thunder.pitch_scale = randf_range(0.8, 1.1)
		_thunder.volume_db = linear_to_db(0.3 * (0.6 if indoors else 1.0))
		_thunder.play()
	var t := now - _flash_time
	var f := 0.0
	if t >= 0.0 and t < 0.7:
		f = 1.0 if t < 0.06 else 0.3 if t < 0.12 else 0.8 if t < 0.2 else lerpf(0.6, 0.0, (t - 0.2) / 0.5)
	return f * (0.35 if indoors else 1.0)


func _sound(delta: float) -> void:
	_inside = move_toward(_inside, 1.0 if indoors else 0.0, delta * 2.0)
	var vol := 0.5 * clampf(wet * 0.75, 0.0, 1.0) * lerpf(1.0, 0.55, _inside)
	_muffle.cutoff_hz = lerpf(20000.0, 3500.0, _inside)
	_rain_sound.volume_db = linear_to_db(maxf(vol, 0.0001))
	if vol > 0.001 and not _rain_sound.playing:
		_rain_sound.play()
	elif vol <= 0.001 and _rain_sound.playing:
		_rain_sound.stop()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# Rain or snow falling over the view, as heavy as [param strength].
func _drive(p: CPUParticles2D, strength: float, rate: float) -> void:
	var view := get_viewport_rect().size / camera.zoom
	p.position = camera.get_screen_center_position() + Vector2(0, -view.y * 0.5 - 40.0)
	p.emission_rect_extents = Vector2(view.x * 0.7, 4.0)
	var speed := RAIN_SPEED if p == _rain else SNOW_SPEED
	p.lifetime = (view.y + 80.0) / (speed * world.px)
	var want := int(rate * strength * (view.x / world.px) / 12.0 * p.lifetime)
	p.emitting = strength > 0.01
	# Changing the count restarts the fall, so only on a real change, and pre-filled so the view is never empty.
	if p.emitting and absi(p.amount - want) > maxi(p.amount / 2, 20):
		p.amount = clampi(want, 1, 3000)
		p.preprocess = p.lifetime


func _fall(flakes: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Snow" if flakes else "Rain"
	p.emitting = false
	p.amount = 100
	p.local_coords = true  # moves with the view (as Unity did): walking never leaves the bottom of the screen dry
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.gravity = Vector2.ZERO
	p.direction = Vector2(0, 1)
	p.spread = 0.0
	if flakes:
		p.initial_velocity_min = SNOW_SPEED * 0.9 * world.px
		p.initial_velocity_max = SNOW_SPEED * 1.1 * world.px
		p.direction = Vector2(0, 1)
		p.spread = 18.0
		p.texture = Waterfall._dot(16, 1.0)
		p.scale_amount_min = 0.06 * world.px / 16.0
		p.scale_amount_max = 0.12 * world.px / 16.0
		p.color = Color(1, 1, 1, 0.9)
	else:
		# Slanted streaks.
		p.direction = Vector2(-0.16, 1).normalized()
		p.initial_velocity_min = RAIN_SPEED * 0.95 * world.px
		p.initial_velocity_max = RAIN_SPEED * 1.05 * world.px
		p.texture = _streak()
		p.particle_flag_align_y = true
		p.scale_amount_min = 1.3
		p.scale_amount_max = 1.6
		p.color = Color(0.8, 0.87, 1.0, 0.75)
	p.z_as_relative = false
	p.z_index = 4070
	add_child(p)
	return p


static func _streak() -> Texture2D:
	var img := Image.create(4, 36, false, Image.FORMAT_RGBA8)
	for y in 36:
		for x in 4:
			img.set_pixel(x, y, Color(1, 1, 1, (1.0 if x == 1 or x == 2 else 0.3) * (float(y) / 35.0)))
	return ImageTexture.create_from_image(img)


## A rectangle covering the camera's view (for the cloud shadows).
class ViewRect extends Node2D:
	var camera: Camera2D

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"sky_effects.ViewRect.process", __t)


	func _process_timed(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var view := get_viewport_rect().size / camera.zoom
		var c := camera.get_screen_center_position()
		draw_rect(Rect2(c - view * 0.6, view * 1.2), Color.WHITE)
