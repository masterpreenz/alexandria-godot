class_name VillagerDebug
extends Node2D
## With the F3 debug view open: each villager's way drawn in red (from them, along their route round walls, to where
## they're going), and over their head what they're at: their task, their state, and how long they've been trying to
## get somewhere without getting further than a step. A way round the mist (over cleared ground) is
## drawn in orange; someone held up past 3 seconds has their line and words in a stronger red.

var world: World


func _ready() -> void:
	z_as_relative = false
	z_index = 4000
	visible = false


func _process(_delta: float) -> void:
	var __t := Time.get_ticks_usec()
	var on := Perf.active != null and Perf.active._panel != null and Perf.active._panel.visible
	if on != visible:
		visible = on
	if visible:
		queue_redraw()
	Perf.add(&"villager debug", __t)


func _draw() -> void:
	var px := world.px
	var font := ThemeDB.fallback_font
	var cam := get_viewport().get_canvas_transform()
	var view := Rect2(-cam.origin / cam.get_scale(), get_viewport_rect().size / cam.get_scale()).grow(4.0 * px)
	var k := 1.0 / maxf(0.01, cam.get_scale().x)
	for v: Villager in Villager.all:
		if not is_instance_valid(v) or not v.visible or not view.has_point(v.position):
			continue
		var held := v._trying_for > 3.0 or (v.state in [Villager.State.FIGHT, Villager.State.HUNT] and Villager.now() - v._chase_best_at > 3.0)
		var red := Color(1.0, 0.1, 0.1, 0.95) if held else Color(1.0, 0.25, 0.25, 0.75)
		var going := v._going() or v.state in [Villager.State.FIGHT, Villager.State.FOLLOW, Villager.State.HUNT]
		if going:
			var pts := PackedVector2Array([v.position])
			if v._detour != Vector2.INF:
				var way := PackedVector2Array([v.position])
				for p in v._mist_way:
					way.append(p)
				if way.size() == 1:
					way.append(v._detour)
				draw_polyline(way, Color(1.0, 0.6, 0.1, 0.9), 3.0 * k)
			if v.route != null:
				for i in range(v.leg, v.route.size()):
					pts.append(v.route[i].at)
			pts.append(v.target)
			# (a hunter: on to the game)
			if v.state == Villager.State.HUNT and v.prey != null and is_instance_valid(v.prey):
				pts.append(v.prey.position)
			draw_polyline(pts, red, (5.0 if held else 3.0) * k)
			draw_circle(v.target, 6.0 * k, red)
		var lines: Array[String] = [str(v.person.get("name", "")) + ": " + v.activity(), Villager.State.keys()[v.state]]
		if v._trying_for > 0.5:
			lines[1] += "  stuck %.1fs" % v._trying_for
		var chasing := v.state in [Villager.State.FIGHT, Villager.State.HUNT] and Villager.now() - v._chase_best_at > 1.5
		if chasing:
			lines[1] += "  no nearer %.1fs" % (Villager.now() - v._chase_best_at)
		if v._detour != Vector2.INF:
			lines[1] += "  round the mist"
		if world.mist != null and not Villager.safe_ground(world, v.position):
			lines[1] += "  in the mist"
		if v.mist_sick > 0.01:
			lines[1] += "  mist sick %d%%" % roundi(v.mist_sick * 50.0)
		var size := 15.0 * k
		var at := v.position + Vector2(0, -1.6 * px)
		for i in lines.size():
			var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(size)).x
			var p := at + Vector2(-w * 0.5, i * size * 1.2)
			draw_string_outline(font, p, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(size), roundi(4 * k), Color(0, 0, 0, 0.85))
			draw_string(font, p, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(size), red if (held and i == 1) else Color(1, 1, 1))
