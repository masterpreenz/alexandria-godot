class_name Crystals
extends Node
## The crystals (from Unity's TeleportCrystal, MistWard, WardBarrier and the travel part of VillageInteractor).
## - Teleport crystals glow blue, pulsing, with motes rising round the pedestal and sparkles winking on the crystal.
##   Standing at one, E opens the list of the others; picking one takes Miko there in a flash of light. Each has a
##   name: one given by hand (saved with the village), the village's, or where it lies from the village.
## - Cleansing crystals clear the mist round them (Mist does the clearing) and glow violet. The edge of the clearing
##   shows as a low curtain of light rising from the ground, rippling, motes drifting up along it, only where there's
##   mist beyond it (where clearings meet, the shared stretch fades). While Miko stands inside, a soft ring on the
##   ground marks its reach.

const RANGE := 1.0                 ## units: how near a crystal she must stand to use it
const WARD_RADIUS := 7.0           ## units: how far round a cleansing crystal the mist is cleared
const SEGMENTS := 160
const HEIGHT := 1.1

var world: World
var miko: Miko
var teleports: Array = []          ## [{pos, node, light, parts}]
var wards: Array = []              ## [{pos, node, light, barrier: Node2D, ring: MeshInstance2D, shown: [], wanted: [], ring_shown}]
var _looked_at := -1
var _clock := 0.0
var _check_at := 0.0
var _pressed := false
var prompt: Label
var panel: PanelContainer
var flash: ColorRect
var _flash_until := 0.0


func setup(w: World, who: Miko, hud: Node) -> void:
	world = w
	miko = who
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt.add_theme_constant_override("outline_size", 6)
	if UiKit.body_font:
		prompt.add_theme_font_override("font", UiKit.body_font)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_top = -150
	prompt.offset_bottom = -120
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.visible = false
	hud.add_child(prompt)
	WorldPrompts.register(prompt)
	panel = PanelContainer.new()
	panel.theme = UiKit.theme
	panel.add_theme_stylebox_override("panel", UiKit.piece("frame"))
	panel.visible = false
	hud.add_child(panel)
	flash = ColorRect.new()
	flash.color = Color(0.85, 0.97, 1.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(flash)


func _px() -> float:
	return world.px


# ---- Names ----

## A crystal's name: given by hand, else the village's, else where it lies from the village (or the map's middle).
func name_of(at: Vector2) -> String:
	for n in world.village.crystal_names:
		if Vector2(float(n.x), -float(n.y)).distance_to(at / _px()) < 0.2:
			return str(n.name)
	if world.village.contains(at):
		return "Village crystal"
	var from := world.village.centre() if world.village.founded() else Vector2.ZERO
	var i := _direction(at, from)
	var same := 0
	for c in teleports:
		if c.pos == at:
			break
		if not world.village.contains(c.pos) and _direction(c.pos, from) == i:
			same += 1
	var names := ["East", "North-east", "North", "North-west", "West", "South-west", "South", "South-east"]
	return names[i] + " crystal" + (" %d" % (same + 1) if same > 0 else "")


func _direction(at: Vector2, from: Vector2) -> int:
	var d := at - from
	# Up the screen is north; the ground's y is halved, so weigh it back up.
	var a := rad_to_deg(atan2(-d.y * 2.0, d.x))
	return roundi(fposmod(a, 360.0) / 45.0) % 8


# ---- Building their looks ----

func _look() -> void:
	for c in teleports + wards:
		for n in c.get("nodes", []):
			if is_instance_valid(n): n.queue_free()
	teleports.clear()
	wards.clear()
	for e in world.props.drawn_named("TeleportCrystal"):
		teleports.append(_dress_teleport(e))
	for e in world.props.drawn_named("CleansingCrystal"):
		wards.append(_dress_ward(e))
	# How much of each one's edge shows (not inside another's clearing): fixed while the crystals stay put.
	for wd in wards:
		var edge := PackedFloat32Array()
		for i in SEGMENTS + 1:
			var a := i * TAU / SEGMENTS
			edge.append(_edge_shown(wd.pos + Vector2(cos(a), -sin(a) * 0.5) * WARD_RADIUS * _px(), wd))
		wd.edge = edge
		_build_ring(wd)


func _light(at: Vector2, c: Color, radius: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = Fires._glow()
	l.color = c
	l.texture_scale = radius * 2.0 * _px() / float(Fires._glow().get_width())
	l.position = at
	world.add_child(l)
	return l


func _dress_teleport(e: Dictionary) -> Dictionary:
	var px := _px()
	var holder: Node2D = e.node
	var base: Vector2 = (holder.get_child(0) as Node2D).position if holder.get_child_count() > 0 else Vector2.ZERO
	# Sparkles winking on its facets.
	var sp := CPUParticles2D.new()
	sp.amount = 4
	sp.lifetime = 0.6
	sp.lifetime_randomness = 0.4
	sp.local_coords = true
	sp.position = base + Vector2(0, -1.25 * px)
	sp.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sp.emission_rect_extents = Vector2(0.14, 0.37) * px
	sp.gravity = Vector2.ZERO
	sp.initial_velocity_min = 0.0
	sp.initial_velocity_max = 0.0
	sp.texture = _star()
	sp.scale_amount_min = 0.28 * px / 24.0
	sp.scale_amount_max = 0.42 * px / 24.0
	var twinkle := Curve.new()
	twinkle.add_point(Vector2(0, 0))
	twinkle.add_point(Vector2(0.35, 1))
	twinkle.add_point(Vector2(1, 0))
	sp.scale_amount_curve = twinkle
	sp.color = Color(0.9, 1, 1)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sp.material = add
	holder.add_child(sp)
	var l := _light(e.pos + Vector2(0, -0.6 * px), Color(0.45, 0.85, 1.0), 2.2)
	return {"pos": e.pos, "nodes": [sp, l], "light": l, "phase": randf() * 10.0}


func _dress_ward(e: Dictionary) -> Dictionary:
	var px := _px()
	var l := _light(e.pos + Vector2(0, -0.82 * px), Color(0.78, 0.6, 1.0), 2.4)
	# The curtain: its back half drawn behind what stands in the clearing, its front half over the ground in front.
	var back := MeshInstance2D.new()
	var front := MeshInstance2D.new()
	var phase := randf() * 10.0
	for half in [back, front]:
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/crystal_curtain.gdshader")
		m.set_shader_parameter("base", 0.22 if half == back else 0.16)
		m.set_shader_parameter("height", HEIGHT * px)
		m.set_shader_parameter("phase", phase)
		(half as MeshInstance2D).material = m
	var r := WARD_RADIUS * px
	var back_holder := Node2D.new()
	back_holder.position = e.pos + Vector2(0, -r * 0.5)
	back.position = -back_holder.position + e.pos
	back_holder.add_child(back)
	var front_holder := Node2D.new()
	front_holder.position = e.pos + Vector2(0, r * 0.5)
	front.position = -front_holder.position + e.pos
	front_holder.add_child(front)
	world.things.add_child(back_holder)
	world.things.add_child(front_holder)
	var motes := CPUParticles2D.new()
	motes.amount = 50
	motes.lifetime = 2.6
	motes.lifetime_randomness = 0.4
	motes.local_coords = false
	motes.emitting = false
	motes.gravity = Vector2.ZERO
	motes.direction = Vector2(0, -1)
	motes.spread = 6.0
	motes.initial_velocity_min = 0.35 * px
	motes.initial_velocity_max = 0.6 * px
	motes.texture = Fires._soft_dot()
	motes.scale_amount_min = 0.05 * px / 64.0 * 2.0
	motes.scale_amount_max = 0.11 * px / 64.0 * 2.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0.85, 0.72, 1, 0), Color(0.9, 0.8, 1, 0.9), Color(1, 0.95, 1, 0.7), Color(1, 1, 1, 0)])
	motes.color_ramp = g
	motes.z_as_relative = false
	motes.z_index = 3990
	world.add_child(motes)
	var ring := MeshInstance2D.new()
	ring.position = e.pos
	world.add_ground_layer(ring, -9966)
	var shown := []
	shown.resize(SEGMENTS + 1)
	shown.fill(-1.0)
	var wanted := []
	wanted.resize(SEGMENTS + 1)
	wanted.fill(1.0)
	return {"pos": e.pos, "nodes": [l, back_holder, front_holder, motes, ring], "light": l, "back": back, "front": front,
		"motes": motes, "ring": ring, "shown": shown, "wanted": wanted, "ring_shown": 0.0, "phase": phase, "mote_clock": 0.0,
		"edge": PackedFloat32Array(), "built": false}


# A four-point star.
static var _star_tex: Texture2D
static func _star() -> Texture2D:
	if _star_tex != null:
		return _star_tex
	var n := 24
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := absf(x + 0.5 - n / 2.0) / (n / 2.0)
			var v := absf(y + 0.5 - n / 2.0) / (n / 2.0)
			var ray := maxf(clampf(1.0 - u * 8.0, 0.0, 1.0) * (1.0 - v), clampf(1.0 - v * 8.0, 0.0, 1.0) * (1.0 - u))
			var core := clampf(1.0 - sqrt(u * u + v * v) * 3.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(maxf(ray, core), 0.0, 1.0)))
	_star_tex = ImageTexture.create_from_image(img)
	return _star_tex


# ---- Each frame ----

func _night_factor() -> float:
	var daylight := get_tree().current_scene.get_node_or_null("Daylight") as CanvasModulate
	if daylight == null:
		return 1.0
	return clampf(maxf(daylight.color.r, maxf(daylight.color.g, daylight.color.b)), 0.2, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E: _pressed = true
		elif event.keycode == KEY_ESCAPE and panel.visible:
			panel.visible = false
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"crystals.process", __t)


func _process_timed(delta: float) -> void:
	var pressed := _pressed
	_pressed = false
	if world.props.version != _looked_at:
		_looked_at = world.props.version
		_look()
	_clock += delta
	var night := 1.4 / sqrt(_night_factor())
	for c in teleports:
		c.light.energy = (0.75 + 0.25 * sin((_clock + c.phase) * 2.2)) * 0.6 * night
	for wd in wards:
		wd.light.energy = (0.75 + 0.2 * sin((_clock + wd.phase) * 1.6)) * 0.6 * night
	if Villager.now() >= _check_at:
		_check_at = Villager.now() + 0.5
		for wd in wards:
			_check_edge(wd)
	for wd in wards:
		_curtain(wd, delta)
		_reach(wd, delta)
	flash.color.a = clampf((_flash_until - Villager.now()) / 0.5, 0.0, 1.0) * 0.85
	_travel(pressed)


# ---- Teleport ----

func _at_crystal(reach: float) -> Dictionary:
	for c in teleports:
		if c.pos.distance_to(miko.position) <= reach * _px():
			return c
	return {}


func _travel(pressed: bool) -> void:
	if panel.visible:
		if _at_crystal(RANGE * 1.8).is_empty() or pressed:
			panel.visible = false
		prompt.visible = false
		return
	var c := {} if miko.locked or CharacterPanel.up() else _at_crystal(RANGE)
	prompt.visible = not c.is_empty()
	if c.is_empty():
		return
	WorldPrompts.at(prompt, c.pos + Vector2(0, -1.5 * _px()))
	if teleports.size() < 2:
		prompt.text = "%s  ·  place another crystal to travel" % name_of(c.pos)
		return
	prompt.text = "Press E to travel  ·  %s" % name_of(c.pos)
	if pressed:
		_open(c)


# The list of the other crystals, nearest first, each with its distance and a Travel button.
func _open(from: Dictionary) -> void:
	for ch in panel.get_children():
		ch.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Teleport  ·  from %s" % name_of(from.pos)
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var others := teleports.filter(func(c): return c != from)
	others.sort_custom(func(a, b): return _gap(from.pos, a.pos) < _gap(from.pos, b.pos))
	for c in others:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s  (%d away)" % [name_of(c.pos), roundi(_gap(from.pos, c.pos))]
		l.custom_minimum_size = Vector2(300, 0)
		row.add_child(l)
		var b := Button.new()
		b.text = "Travel ›"
		var to: Dictionary = c
		b.pressed.connect(func(): _go(to))
		row.add_child(b)
		box.add_child(row)
	var hint := Label.new()
	hint.text = "E or Esc to close"
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	panel.visible = true
	panel.reset_size()
	panel.position = (panel.get_viewport_rect().size - panel.size) / 2.0


func _gap(a: Vector2, b: Vector2) -> float:
	var d := (b - a) / _px()
	return sqrt(d.x * d.x + 4.0 * d.y * d.y)


func _go(to: Dictionary) -> void:
	if _at_crystal(RANGE * 1.8).is_empty():
		return
	panel.visible = false
	var arrival: Vector2 = to.pos + Vector2(0, 0.45 * _px())
	miko.place(arrival)
	var cam := miko.get_viewport().get_camera_2d()
	if cam != null:
		cam.position = arrival
		cam.reset_smoothing()
	_flash_until = Villager.now() + 0.5
	FloatingText.spawn(world, name_of(to.pos), to.pos + Vector2(0, -1.6 * _px()), Color(0.6, 0.9, 1.0))


# ---- The cleansing crystal's edge ----

# How far [param at] lies inside any other crystal's clearing: 1 or more outside them all, less the deeper in.
func _outside_others(at: Vector2, me: Dictionary) -> float:
	var least := 2.0
	for wd in wards:
		if wd == me:
			continue
		var d: Vector2 = (at - wd.pos) / _px()
		least = minf(least, Vector2(d.x, d.y * 2.0).length() / WARD_RADIUS)
	return least


func _edge_shown(at: Vector2, me: Dictionary) -> float:
	return clampf((_outside_others(at, me) - 0.985) / 0.015, 0.0, 1.0)


# Just past the edge: still mist there, or cleared by something else?
func _check_edge(wd: Dictionary) -> void:
	var r := (WARD_RADIUS + 0.8) * _px()
	for i in SEGMENTS + 1:
		var a := i * TAU / SEGMENTS
		var beyond: Vector2 = wd.pos + Vector2(cos(a) * r, -sin(a) * r * 0.5)
		var clear := world.mist.tier_at(beyond) == Mist.Tier.CLEAR and _outside_others(beyond, wd) >= 1.0
		wd.wanted[i] = 0.0 if clear else 1.0
	# Motes drift up only along the stretches that show.
	var pts := PackedVector2Array()
	for i in SEGMENTS:
		var a := i * TAU / SEGMENTS
		var p: Vector2 = Vector2(cos(a), -sin(a) * 0.5) * WARD_RADIUS * _px()
		if wd.wanted[i] > 0.5 and wd.edge[i] > 0.5:
			pts.append(p)
	var m: CPUParticles2D = wd.motes
	m.position = wd.pos
	m.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	m.emission_points = pts
	@warning_ignore("integer_division")
	m.amount = clampi(pts.size() / 3, 1, 60)
	m.emitting = not pts.is_empty()


func _shown_at(wd: Dictionary, a: float) -> float:
	var f := fposmod(a, TAU) / TAU * SEGMENTS
	var i := clampi(floori(f), 0, SEGMENTS - 1)
	return lerpf(wd.shown[i], wd.shown[i + 1], f - i)


# The curtain eases where it shows towards where it should; its mesh is built again only while that's changing
# (the rippling and swaying are in its shader).
func _curtain(wd: Dictionary, delta: float) -> void:
	var changed: bool = not wd.built
	for i in SEGMENTS + 1:
		var was: float = wd.shown[i]
		wd.shown[i] = wd.wanted[i] if was < 0.0 else move_toward(was, wd.wanted[i], delta * 1.5)
		if wd.shown[i] != was:
			changed = true
	if not changed:
		return
	wd.built = true
	_half(wd, wd.back, true)
	_half(wd, wd.front, false)



# One half of the curtain at rest: a band round the ellipse, both rows on the ground (the shader raises the top
# row and ripples its brightness), the ground row as bright as that stretch shows.
func _half(wd: Dictionary, mi: MeshInstance2D, back_half: bool) -> void:
	@warning_ignore("integer_division")
	var n := SEGMENTS / 2
	var r := WARD_RADIUS * _px()
	var start := 0 if back_half else n
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var tris := PackedInt32Array()
	for i in n + 1:
		# The back half runs over the top of the ellipse (0 to pi), the front half under it.
		var k := start + i
		var a := k * TAU / SEGMENTS
		var ground := Vector2(cos(a) * r, -sin(a) * r * 0.5)
		verts.append(ground)
		verts.append(ground)
		uvs.append(Vector2(a, 0.0))
		uvs.append(Vector2(a, 1.0))
		var shows: float = maxf(0.0, wd.shown[k]) * (wd.edge[k] if k < wd.edge.size() else 1.0)
		cols.append(Color(0.82, 0.68, 1.0, shows))
		cols.append(Color(0.9, 0.82, 1.0, 0.0))
		if i == n:
			continue
		var v := i * 2
		tris.append_array([v, v + 1, v + 2, v + 1, v + 3, v + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = tris
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh


# While Miko is within its reach, a soft ring on the ground along the edge of its clearing, gently pulsing (the ring
# is built once, with the crystal; its pulse and fade are its modulate).
func _reach(wd: Dictionary, delta: float) -> void:
	var d: Vector2 = (miko.position - wd.pos) / _px()
	var inside := Vector2(d.x, d.y * 2.0).length() <= WARD_RADIUS
	wd.ring_shown = move_toward(wd.ring_shown, 1.0 if inside else 0.0, delta * 3.0)
	var mi: MeshInstance2D = wd.ring
	mi.visible = wd.ring_shown > 0.0
	if mi.visible:
		mi.modulate.a = (0.28 + 0.08 * sin((_clock + wd.phase) * 2.0)) * wd.ring_shown


func _build_ring(wd: Dictionary) -> void:
	var px := _px()
	var half := 0.0225 * px
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var tris := PackedInt32Array()
	for i in SEGMENTS + 1:
		var a := i * TAU / SEGMENTS
		var p := Vector2(cos(a), -sin(a) * 0.5) * WARD_RADIUS * px
		var nrm := Vector2(cos(a) * 0.5, -sin(a)).normalized() * half
		verts.append(p - nrm)
		verts.append(p + nrm)
		var c := Color(0.9, 0.84, 1.0, wd.edge[i])
		cols.append(c)
		cols.append(c)
		if i == SEGMENTS:
			continue
		var v := i * 2
		tris.append_array([v, v + 1, v + 2, v + 1, v + 3, v + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = tris
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	(wd.ring as MeshInstance2D).mesh = mesh
