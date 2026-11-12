class_name Culler
## Keeps what needn't run from running: each thing watched has a test (on screen; near Sera) asked five times a
## second, and while it says no the thing's process and physics are switched off altogether (not just returning
## early: not called at all). The map grows as it's played and nothing's unloaded, so the far side of it mustn't cost.

const EVERY := 0.2

static var _watched: Array = []      ## [node, wanted: Callable]
static var _next := 0.0


## Watches [param n]: its process and physics on only while [param wanted] says so.
static func watch(n: Node, wanted: Callable) -> void:
	_watched.append([n, wanted])


## Looks again at everything watched (the world calls it every frame; it does its work five times a second).
static func tick() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t < _next:
		return
	_next = t + EVERY
	var keep := []
	for w in _watched:
		var v: Variant = w[0]
		if not is_instance_valid(v):
			continue   # (gone: dropped)
		var n := v as Node
		keep.append(w)
		if not n.is_inside_tree():
			continue   # (not in the world yet, or for now: looked at again)
		var on: bool = (w[1] as Callable).call()
		if n.is_processing() != on:
			n.set_process(on)
		if n.is_physics_processing() != on:
			n.set_physics_process(on)
	_watched = keep
	_hide_far()


# ---- Hiding the map's still things off screen: filed by square, a square at a time ----

const SQUARE := 16.0                 ## units a square of the map is, for hiding
static var _squares := {}            ## Vector2i -> Array of CanvasItems that never move (trees, props, growth)
static var _shown := {}              ## Vector2i -> true: squares shown now
static var _world: World


## Files [param n] (something that stays where it is) by where it stands, to be hidden while its square's off screen
## (and off the minimap).
static func still(w: World, n: CanvasItem, at: Vector2) -> void:
	_world = w
	var k := Vector2i(floori(at.x / (SQUARE * w.px)), floori(at.y / (SQUARE * w.px)))
	(_squares.get_or_add(k, []) as Array).append(n)
	if _shown_set and not _shown.has(k):
		n.visible = false


static var _shown_set := false


## Everything shown at once (the world map opening: it draws all of it).
static func show_all() -> void:
	for k in _squares:
		for n in _squares[k]:
			if is_instance_valid(n):
				(n as CanvasItem).visible = true
		_shown[k] = true


# The squares in sight: the screen and what the minimap shows, a square round them; everything while the world map's
# open (it draws all of it).
static func _hide_far() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var want := {}
	var whole: bool = WorldMap.showing()
	if not whole:
		var rects: Array = [_world.view_rect()]
		if Minimap.active != null and is_instance_valid(Minimap.active):
			rects.append(Minimap.active.shown_rect())
		var sq := SQUARE * _world.px
		for r: Rect2 in rects:
			r = r.grow(sq)
			for x in range(floori(r.position.x / sq), floori(r.end.x / sq) + 1):
				for y in range(floori(r.position.y / sq), floori(r.end.y / sq) + 1):
					want[Vector2i(x, y)] = true
	for k in _squares:
		var on := whole or want.has(k)
		if on == _shown.has(k) and _shown_set:
			continue
		if on: _shown[k] = true
		else: _shown.erase(k)
		var list: Array = _squares[k]
		var keep := []
		for n in list:
			if is_instance_valid(n):
				(n as CanvasItem).visible = on
				keep.append(n)
		_squares[k] = keep
	_shown_set = true
