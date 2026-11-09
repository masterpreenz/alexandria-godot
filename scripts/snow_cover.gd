class_name SnowCover
extends Node
## How much snow lies on the world, 0 (none) to 1 (all white) (from Unity's SnowCover): it builds while it snows and
## melts when it stops, quicker under a clear sky and quickest out of winter. Sets the snow_cover global the snow
## shader reads, so the ground whitens in patches, roofs blanket over and things standing get caps. Once the snow has
## settled, sprites that have a snowy version (trees) fade over to it, and back as it melts; past snow_roof_from the
## roofs turn to their snowy look.

var world: World
var clock: GameClock
var build_hours := 4.0
var melt_hours := 10.0
var sun_melt := 2.0
var thaw_melt := 4.0
var snowy_above := 0.45
var bare_below := 0.3
var fade_time := 1.5
var roof_from := 0.55

var cover := 0.0
var snowy := false
var _last_hours := -1.0
var _to_snowy := {}   # sprite id -> snowy id
var _to_plain := {}


func setup(w: World, c: GameClock, d: Dictionary) -> void:
	world = w
	clock = c
	build_hours = d.get("buildHours", build_hours)
	melt_hours = d.get("meltHours", melt_hours)
	sun_melt = d.get("sunMelt", sun_melt)
	thaw_melt = d.get("thawMelt", thaw_melt)
	snowy_above = d.get("snowyAbove", snowy_above)
	bare_below = d.get("bareBelow", bare_below)
	fade_time = d.get("fadeTime", fade_time)
	roof_from = d.get("snowRoofFrom", roof_from)
	for v in d.get("variants", []):
		_to_snowy[int(v[0])] = int(v[1])
		_to_plain[int(v[1])] = int(v[0])
	set_cover(0.0)


func set_cover(v: float) -> void:
	cover = clampf(v, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("snow_cover", cover)


func _process(_delta: float) -> void:
	var passed := 0.0 if _last_hours < 0.0 else maxf(0.0, clock.hours - _last_hours)
	_last_hours = clock.hours
	if clock.weather() == GameClock.Weather.SNOW:
		cover += passed / maxf(0.01, build_hours)
	elif cover > 0.0:
		var rate := 1.0 / maxf(0.01, melt_hours)
		if clock.weather() == GameClock.Weather.CLEAR: rate *= sun_melt
		if clock.season() != GameClock.Season.WINTER: rate *= thaw_melt
		cover -= passed * rate
	set_cover(cover)
	# Snowy trees: swapped when the snow crosses the thresholds.
	var want := cover > bare_below if snowy else cover >= snowy_above
	if want != snowy:
		snowy = want
		_swap()
	if world.roofs != null:
		world.roofs.set_snowed(cover >= roof_from)


func _swap() -> void:
	var map := _to_snowy if snowy else _to_plain
	for holder in world.things.get_children():
		for s in holder.get_children():
			if not s is Sprite2D:
				continue
			var id: int = s.get_meta("sprite", -1)
			if not map.has(id):
				continue
			_ghost(s)
			var flip: float = signf(s.scale.x)
			var size: float = absf(s.scale.x) / (world.px / float(world.sprites[id].ppu))
			world.show_frame(s, map[id], Vector2(flip * size, size))
			# The snowy art has its own snow: no caps on top.
			s.material = null if snowy else world.snow_material(0)


# The old look laid over the new one, fading out: a soft change, not a pop.
func _ghost(s: Sprite2D) -> void:
	var g := s.duplicate() as Sprite2D
	g.material = null
	s.get_parent().add_child(g)
	var tween := g.create_tween()
	tween.tween_property(g, "modulate:a", 0.0, fade_time)
	tween.tween_callback(g.queue_free)
