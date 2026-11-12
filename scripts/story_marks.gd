class_name StoryMarks
extends Control
## Markers over what the story wants Sera to find (the monsters it sends at her early on): a pulsing ring on the ground
## round each and an arrow bobbing over it while it's on screen, and an arrow at the screen's edge pointing the way while
## it's off it. Each also has its outline shown all the time, through whatever stands in front. Gone once they're dead.

const EDGE := 46.0              ## px in from the screen's edge for the arrows pointing off it
const COLOR := Color(1.0, 0.42, 0.32)
const FRIEND := Color(1.0, 0.82, 0.35)   ## someone to go and see (the elder), not to fight

var world: World
var marked: Array = []          ## Creatures, and people (Villagers)
var colors := {}                ## node -> its marks' colour
var uniques := {}               ## unique id -> colour: people marked by who they are (found again if their node's remade)


func setup(w: World) -> void:
	world = w
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Marks [param c] (a Creature, or a Villager to go to): an arrow to it, a ring, and its outline always on.
func mark(c: Node2D, color := COLOR) -> void:
	if marked.has(c):
		return
	marked.append(c)
	colors[c] = color
	var o: Variant = c.get("outline")
	if o is OccludedOutline:
		(o as OccludedOutline).hidden_when = func() -> bool: return true


## Marks the unique character [param id] (whichever villager they are now, and again if they're remade).
func mark_unique(id: String, color := FRIEND) -> void:
	uniques[id] = color


## Takes the marks off the people marked (a beat's over), their outlines back to only behind things.
func unmark_people() -> void:
	uniques.clear()
	for c in marked.duplicate():
		if is_instance_valid(c) and c is Villager:
			marked.erase(c)
			colors.erase(c)
			var o: Variant = c.get("outline")
			if o is OccludedOutline:
				(o as OccludedOutline).hidden_when = Callable()


func _process(_delta: float) -> void:
	var __t := Time.get_ticks_usec()
	marked = marked.filter(func(c): return is_instance_valid(c) and c.get("hit") != null and c.hit.alive())
	for id in uniques:
		for v in Villager.all:
			if is_instance_valid(v) and str(v.person.get("unique", "")) == id and not marked.has(v):
				mark(v, uniques[id])
	visible = not marked.is_empty()
	if visible:
		queue_redraw()
	Perf.add(&"story_marks.process", __t)


func _draw() -> void:
	var xf := get_viewport().get_canvas_transform()
	var view := get_viewport_rect()
	var inner := view.grow(-EDGE)
	var secs := Time.get_ticks_msec() / 1000.0
	var bob := sin(secs * 5.0) * 4.0
	for c: Node2D in marked:
		var art: Variant = c.get("art")
		var col: Color = colors.get(c, COLOR)
		var box := World.sprite_rect(art) if art is Sprite2D else Rect2(c.position - Vector2(30, 60), Vector2(60, 60))
		var top: Vector2 = xf * Vector2(box.get_center().x, box.position.y)
		var feet: Vector2 = xf * c.position
		if view.grow(-8.0).has_point(feet):
			# On screen: a ring pulsing out on the ground round it, and an arrow pointing down at it.
			var zoom := xf.get_scale().x
			var r := maxf(box.size.x * 0.6, 0.45 * world.px) * zoom
			var pulse := fposmod(secs * 1.2, 1.0)
			_ring(feet, r * (0.9 + 0.25 * pulse), Color(col.r, col.g, col.b, 0.85 * (1.0 - pulse)))
			_ring(feet, r * 0.9, Color(col.r, col.g, col.b, 0.55))
			_arrow(top + Vector2(0, bob - 8.0), Vector2.DOWN, 1.4, col)
		else:
			# Off it: at the edge, pointing the way.
			var mid := view.get_center()
			var dir := (feet - mid).normalized()
			var t := INF
			if dir.x != 0.0: t = minf(t, (inner.size.x / 2.0) / absf(dir.x))
			if dir.y != 0.0: t = minf(t, (inner.size.y / 2.0) / absf(dir.y))
			_arrow(mid + dir * t + dir * bob * 0.5, dir, 1.25, col)


# A flat ring on the ground (half as tall as it's wide, as the ground's drawn) round [param centre].
func _ring(centre: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(centre + Vector2(cos(a), sin(a) * 0.5) * radius)
	draw_polyline(pts, color, 3.0, true)


# A filled arrowhead at [param tip], pointing along [param dir], dark-edged so it reads on grass and road.
func _arrow(tip: Vector2, dir: Vector2, big: float, col := COLOR) -> void:
	var side := Vector2(-dir.y, dir.x)
	var l := 16.0 * big
	var w := 10.0 * big
	var pts := PackedVector2Array([tip, tip - dir * l + side * w, tip - dir * l * 0.55, tip - dir * l - side * w])
	draw_colored_polygon(pts, col)
	pts.append(tip)
	draw_polyline(pts, Color(0.12, 0.05, 0.04, 0.9), 2.0, true)
