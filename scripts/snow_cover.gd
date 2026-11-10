class_name SnowCover
extends Node
## How much snow lies on the world, 0 (none) to 1 (all white) (from Unity's SnowCover): it builds while it snows and
## melts when it stops, quicker under a clear sky and quickest out of winter; in winter it doesn't melt at all. Sets the snow_cover global the snow
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
## Where no snow lies: a picture a cell a pixel, [constant CLEAR_SIZE] cells a side round the village: white inside
## houses and round burning fires (fading out to their reach), which the snow shader reads.
const CLEAR_SIZE := 128
const FIRE_REACH := 5.0           ## cells round a burning bonfire kept clear
const TORCH_REACH := 2.5
var _clear_image: Image
var _clear_tex: ImageTexture
var _clear_key := ""
var _clear_first := Vector2i.ZERO
var _next_clear := 0.0


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


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"snow_cover.process", __t)


func _process_timed(_delta: float) -> void:
	var winter := clock.season() == GameClock.Season.WINTER
	# Loaded into winter (the snow isn't saved): it lies as it would by now, its first day's fall and all after.
	if _last_hours < 0.0 and winter:
		cover = 1.0 if clock.day_of_season() > 1 else clampf(clock.hour() / maxf(0.01, build_hours), 0.0, 1.0)
	var passed := 0.0 if _last_hours < 0.0 else maxf(0.0, clock.hours - _last_hours)
	_last_hours = clock.hours
	if clock.weather() == GameClock.Weather.SNOW:
		cover += passed / maxf(0.01, build_hours)
	elif winter:
		# (it lies all winter: a clear winter's day doesn't melt it. Skipped ahead into winter past its first
		# day's snow, it's lying already)
		if clock.day_of_season() > 1:
			cover = maxf(cover, 1.0)
	elif cover > 0.0:
		var rate := 1.0 / maxf(0.01, melt_hours)
		if clock.weather() == GameClock.Weather.CLEAR: rate *= sun_melt
		if clock.season() != GameClock.Season.WINTER: rate *= thaw_melt
		cover -= passed * rate
	set_cover(cover)
	_clear_map()
	# Snowy trees: swapped when the snow crosses the thresholds.
	var want := cover > bare_below if snowy else cover >= snowy_above
	if want != snowy:
		snowy = want
		_swap()
	if world.roofs != null:
		world.roofs.set_snowed(cover >= roof_from)


## How much snow lies on the ground at [param p] (px): 0 none (no snow about, a laid floor, indoors, by a burning
## fire) to 1.
func ground_snow(p: Vector2) -> float:
	if cover < 0.5:
		return 0.0
	var cell := world.floors.cell_at(p)
	if world.floors.get_laid(cell) != "":
		return 0.0
	if _clear_image != null:
		var at: Vector2i = cell - _clear_first
		if Rect2i(0, 0, CLEAR_SIZE, CLEAR_SIZE).has_point(at) and _clear_image.get_pixelv(at).r > 0.45:
			return 0.0
	return 1.0


# The no-snow map, made again when the houses, the fires or which of them burn change (looked at twice a second,
# and only while there's snow).
func _clear_map() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if cover <= 0.001 or now < _next_clear or world.roofs == null or world.player == null:
		return
	_next_clear = now + 0.5
	var fires: Fires = world.player.get_node_or_null("Fires")
	var lit := []
	if fires != null:
		for f in fires.fires:
			if fires.lit(f):
				lit.append(f)
	var middle := world.floors.cell_at(world.village.centre() if world.village.founded() else world.player.position)
	@warning_ignore("integer_division")
	var first := middle - Vector2i(CLEAR_SIZE / 2, CLEAR_SIZE / 2)
	var key := "%s %d %d %s" % [first, world.walls.rooms_version, world.props.version, lit.map(func(f): return f.key)]
	if key == _clear_key:
		return
	_clear_key = key
	_clear_first = first
	if _clear_image == null:
		_clear_image = Image.create(CLEAR_SIZE, CLEAR_SIZE, false, Image.FORMAT_R8)
	_clear_image.fill(Color(0, 0, 0))
	var box := Rect2i(0, 0, CLEAR_SIZE, CLEAR_SIZE)
	for roof in world.roofs.roofs:
		for c in roof.cells:
			var at: Vector2i = c - first
			if box.has_point(at):
				_clear_image.set_pixelv(at, Color(1, 0, 0))
	for f in lit:
		var reach := TORCH_REACH if bool(f.s.torch) else FIRE_REACH
		var centre: Vector2 = world.floors.fractional_cell(f.pos) - Vector2(first)
		for x in range(floori(centre.x - reach), ceili(centre.x + reach) + 1):
			for y in range(floori(centre.y - reach), ceili(centre.y + reach) + 1):
				if not box.has_point(Vector2i(x, y)):
					continue
				var d := (Vector2(x + 0.5, y + 0.5) - centre).length()
				var v := clampf(1.0 - (d - reach * 0.55) / (reach * 0.45), 0.0, 1.0)
				if v > _clear_image.get_pixel(x, y).r:
					_clear_image.set_pixel(x, y, Color(v, 0, 0))
	if _clear_tex == null:
		_clear_tex = ImageTexture.create_from_image(_clear_image)
		world.set_snow_param("clear_map", _clear_tex)
		world.set_snow_param("clear_size", float(CLEAR_SIZE))
		world.set_snow_param("floor_origin", Vector2(world.floors.origin.x, -world.floors.origin.y) / world.px)
		world.set_snow_param("clear_on", 1.0)
	else:
		_clear_tex.update(_clear_image)
	world.set_snow_param("clear_origin", Vector2(first))


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
			if s.get_meta("sway", false):
				s.material = world.tree_material(snowy)   # still swaying, snowy or not
			else:
				s.material = null if snowy else world.snow_material(0)


# The old look laid over the new one, fading out: a soft change, not a pop.
func _ghost(s: Sprite2D) -> void:
	var g := s.duplicate() as Sprite2D
	g.material = null
	s.get_parent().add_child(g)
	var tween := g.create_tween()
	tween.tween_property(g, "modulate:a", 0.0, fade_time)
	tween.tween_callback(g.queue_free)
