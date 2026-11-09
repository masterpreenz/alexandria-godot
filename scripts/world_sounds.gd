class_name WorldSounds
extends Node2D
## The world's own sounds (from Unity's River, WindGusts and VillagerSteps):
##  - each river's water, looped: full within a couple of cells of it and trailing away by a dozen, from the side it's on;
##  - now and then a gust of wind (never while it rains or storms; softer indoors): its sound sweeps across the view
##    from one side to the other, with a few faint streaks and leaves blowing over it;
##  - the villagers' footsteps: Miko's step recordings, looped while they walk, softer and lower than hers, heard only
##    near them.
## And the level-up chime, made from four rising notes.

const STEP_VOLUME := 0.35
const STEP_PITCH := 0.82

var world: World
var miko: Miko
var d: Dictionary
var _rivers: Array = []          ## [{player, samples, volume, loud, hear}]
var _wind: AudioStreamPlayer2D
var _wind_settings: Dictionary
var _next_gust := 0.0
var _gust_start := -1.0
var _gust_length := 0.0
var _gust_from := 0.0
var _gust_pace := 0.0
var _motes: Array = []           ## [{leaf, offset, drift, bob, spin, alpha, scale, colour, angle}]
var _steps := {}                 ## Villager -> [grass player, solid player, level, grass mix]
var _grass_step: AudioStream
var _solid_step: AudioStream
static var _chime: AudioStreamWAV


func setup(w: World, who: Miko, data: Dictionary) -> void:
	world = w
	miko = who
	d = data
	z_as_relative = false
	z_index = 4070
	visibility_layer = MapMarks.HIDDEN_LAYER
	for r in d.get("rivers", []):
		var p := AudioStreamPlayer2D.new()
		p.stream = _stream(r.get("flowSound"))
		if p.stream == null:
			continue
		p.attenuation = 0.0
		p.max_distance = 1.0e6
		p.volume_db = -80.0
		add_child(p)
		_rivers.append({"player": p, "samples": r.samples, "volume": float(r.flowVolume), "loud": float(r.loudWithin), "hear": float(r.hearFrom)})
	_wind_settings = d.get("wind", {})
	_wind = AudioStreamPlayer2D.new()
	_wind.stream = _stream(_wind_settings.get("gustSound"))
	_wind.attenuation = 0.0
	_wind.max_distance = 1.0e6
	add_child(_wind)
	_next_gust = _now() + randf_range(6.0, 12.0)
	_grass_step = load("res://assets/Sounds/running_grass.wav")
	_solid_step = load("res://assets/Sounds/running_solid.wav")


static func _stream(path: Variant) -> AudioStream:
	return load(path) if path is String and ResourceLoader.exists(path) else null


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_flow()
	_gusts()
	_villager_steps(delta)
	queue_redraw()


# ---- The rivers ----

func _flow() -> void:
	var at := world.floors.fractional_cell(miko.position)
	for r in _rivers:
		var best := INF
		var nearest := Vector2.ZERO
		for s in r.samples:
			var dist := at.distance_to(Vector2(s[0], s[1])) - float(s[2])
			if dist < best:
				best = dist
				nearest = Vector2(s[0], s[1])
		var t := 1.0 - clampf(inverse_lerp(r.loud, r.hear, best), 0.0, 1.0)
		var vol: float = r.volume * t * t   # falls off quickly at first, then trails away
		var p: AudioStreamPlayer2D = r.player
		p.volume_db = linear_to_db(maxf(vol, 0.0001))
		# Heard from the side the water is on, a little (more as it's further off).
		var water := world.floors.corner(nearest)
		var side := clampf((water.x - miko.position.x) / (6.0 * world.px), -0.5, 0.5) * clampf(best / 3.0, 0.0, 1.0)
		p.global_position = miko.position + Vector2(side * 4.0 * world.px, 0)
		if vol > 0.001 and not p.playing:
			p.play(randf() * p.stream.get_length() * 0.9)
		elif vol <= 0.001 and p.playing:
			p.stop()


# ---- Wind gusts ----

func _wet() -> bool:
	return world.clock != null and world.clock.weather() in [2, 3]   # rain, storm


func _gusts() -> void:
	var t := _now()
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var half := get_viewport_rect().size.x / 2.0 / cam.zoom.x
	if _gust_start < 0.0:
		if t < _next_gust:
			return
		var iv: Array = _wind_settings.get("interval", [20, 45])
		if _wet():
			_next_gust = t + randf_range(float(iv[0]), float(iv[1]))
			return
		gust_now()
		return
	var u := (t - _gust_start) / _gust_length
	if u >= 1.0:
		_gust_start = -1.0
		var iv: Array = _wind_settings.get("interval", [20, 45])
		_next_gust = t + randf_range(float(iv[0]), float(iv[1]))
		return
	var front := _gust_from + (t - _gust_start) * _gust_pace
	var indoors := world.roofs != null and world.roofs.covers(miko.position)
	var strength := sin(clampf(u, 0.0, 1.0) * PI)
	_wind.volume_db = linear_to_db(maxf(float(_wind_settings.get("volume", 0.55)) * (0.5 if indoors else 1.0), 0.0001))
	_wind.global_position = Vector2(cam.global_position.x + clampf((front - cam.global_position.x) / half, -0.8, 0.8) * 3.0 * world.px, cam.global_position.y)
	for m in _motes:
		m.offset.x += m.drift * world.px * get_process_delta_time()
		m.angle += deg_to_rad(m.spin) * get_process_delta_time()
		m.alpha_now = m.alpha * strength
		m.at = Vector2(front + m.offset.x, cam.global_position.y + m.offset.y + sin(t * (5.0 if m.leaf else 1.5) + m.bob) * (0.25 if m.leaf else 0.08) * world.px)


## Sends a gust across now.
func gust_now() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var half := get_viewport_rect().size.x / 2.0 / cam.zoom.x
	var h := get_viewport_rect().size.y / 2.0 / cam.zoom.y
	_gust_from = cam.global_position.x - half - 6.0 * world.px
	var distance := half * 2.0 + 12.0 * world.px
	_gust_length = _wind.stream.get_length() * 0.9 if _wind.stream != null else distance / (float(_wind_settings.get("speed", 7.0)) * world.px)
	_gust_pace = distance / _gust_length
	_gust_start = _now()
	if _wind.stream != null:
		_wind.pitch_scale = randf_range(0.9, 1.1)
		_wind.play()
	_motes.clear()
	var streaks := int(_wind_settings.get("streaks", 6))
	for i in streaks + int(_wind_settings.get("leaves", 9)):
		var leaf := i >= streaks
		_motes.append({"leaf": leaf, "offset": Vector2(randf_range(-5.0, 2.0) * world.px, randf_range(-h * 0.85, h * 0.85)),
			"drift": randf_range(-0.8, 1.2), "bob": randf_range(0.0, 6.3), "spin": randf_range(-360.0, 360.0), "angle": 0.0,
			"alpha": 1.0 if leaf else randf_range(0.18, 0.32), "alpha_now": 0.0, "at": Vector2.ZERO,
			"scale": randf_range(0.7, 1.2) if leaf else randf_range(0.8, 1.6),
			"colour": Color(0.55, 0.7, 0.25).lerp(Color(0.85, 0.65, 0.25), randf()) if leaf else Color.WHITE})


func _draw() -> void:
	if _gust_start < 0.0:
		return
	var k := world.px / 128.0
	for m in _motes:
		if m.alpha_now <= 0.01:
			continue
		var c: Color = m.colour
		c.a = m.alpha_now
		if m.leaf:
			# A tiny leaf in chunky pixels.
			draw_set_transform(m.at, m.angle, Vector2.ONE * m.scale * k * 6.0)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -3), Vector2(2, -1), Vector2(1.5, 1.5), Vector2(0, 3), Vector2(-1.5, 1.5), Vector2(-2, -1)]), c)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			# A thin, soft, slightly curved line.
			var w: float = 96.0 * k * 2.6 * m.scale
			var pts := PackedVector2Array()
			for i in 9:
				var u := i / 8.0
				pts.append(m.at + Vector2((u - 0.5) * w, -sin(u * PI) * 6.0 * k))
			draw_polyline(pts, c, 2.0 * k * 1.6, true)


# ---- The villagers' footsteps ----

func _villager_steps(delta: float) -> void:
	for v in _steps.keys():
		if not is_instance_valid(v) or not Villager.all.has(v):
			for p in _steps[v].slice(0, 2):
				if is_instance_valid(p): p.queue_free()
			_steps.erase(v)
	for v in Villager.all:
		if not _steps.has(v):
			_steps[v] = [_step_player(v, _grass_step), _step_player(v, _solid_step), 0.0, 1.0]
		var e: Array = _steps[v]
		var moving: bool = v.visible and v.velocity.length_squared() > 0.04 * world.px * world.px
		var step := delta / 0.1
		e[2] = move_toward(e[2], 1.0 if moving else 0.0, step)
		e[3] = move_toward(e[3], 0.0 if world.on_floor(v.position) else 1.0, step)
		_mix(e[0], e[2] * e[3])
		_mix(e[1], e[2] * (1.0 - e[3]))


func _step_player(v: Node2D, stream: AudioStream) -> AudioStreamPlayer2D:
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.volume_db = -80.0
	p.pitch_scale = STEP_PITCH * randf_range(0.95, 1.05)
	p.max_distance = 9.0 * world.px
	p.attenuation = 2.0
	v.add_child(p)
	return p


static func _mix(p: AudioStreamPlayer2D, amount: float) -> void:
	if p == null or p.stream == null:
		return
	p.volume_db = linear_to_db(maxf(amount * STEP_VOLUME, 0.0001))
	if amount > 0.001 and not p.playing:
		p.play(randf() * p.stream.get_length() * 0.9)
	elif amount <= 0.001 and p.playing:
		p.stop()


# ---- The level-up chime ----

## Four rising notes (C, E, G, C), each ringing out.
static func chime() -> AudioStreamWAV:
	if _chime != null:
		return _chime
	var rate := 44100
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var step := 0.09
	var ring := 0.9
	var length := ceili((step * (notes.size() - 1) + ring) * rate)
	var data := PackedFloat32Array()
	data.resize(length)
	for n in notes.size():
		var start := roundi(n * step * rate)
		var f: float = notes[n]
		for i in mini(int(ring * rate), length - start):
			var t := float(i) / rate
			var env := minf(1.0, t / 0.005) * exp(-t * 4.5)
			var v := sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t) + 0.12 * sin(TAU * f * 3.0 * t)
			data[start + i] += v * env * 0.22
	var bytes := PackedByteArray()
	bytes.resize(length * 2)
	for i in length:
		bytes.encode_s16(i * 2, clampi(roundi(data[i] * 32767.0), -32768, 32767))
	_chime = AudioStreamWAV.new()
	_chime.format = AudioStreamWAV.FORMAT_16_BITS
	_chime.mix_rate = rate
	_chime.stereo = false
	_chime.data = bytes
	return _chime
