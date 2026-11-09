class_name OccludedOutline
extends Node
## Keeps a character findable behind things (from Unity's OccludedOutline): once nearly all of their body is hidden
## (90% of its drawn pixels, by what's actually drawn in front, not the pictures' boxes), a soft outline of them and a
## faint fill show over everything, fading in and out; it stays until less than 80% is hidden. For the player, what's
## hiding them also fades to see-through while they're behind it, and back once they're out.

const COLS := 8
const ROWS := 12

var world: World
var body: Sprite2D           ## the character's art
var fade_covers := true      ## fade what hides them (the player's own; others only get the outline)
var strength := 0.9
var fade_speed := 6.0
var cover_needed := 0.9
var cover_keep := 0.8
var cover_alpha := 0.45
var cover_fade_speed := 5.0

var outline: Sprite2D
var shown := 0.0
var covered := false
var next_check := 0.0
var covering := {}           # Sprite2D -> true: what's hiding them now
var fading := {}             # Sprite2D -> how far faded (0 solid .. 1 see-through)


func setup(w: World, art: Sprite2D, color := Color(1, 0.96, 0.88, 1)) -> void:
	world = w
	body = art
	outline = Sprite2D.new()
	outline.name = "Outline"
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/sprite_outline.gdshader")
	mat.set_shader_parameter("outline_color", color)
	mat.set_shader_parameter("fill_color", Color(color.r, color.g, color.b, 0.22))
	outline.material = mat
	outline.z_as_relative = false
	outline.z_index = 4000  # over the world
	outline.visible = false
	body.get_parent().add_child(outline)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"occluded_outline.process", __t)


func _process_timed(delta: float) -> void:
	if body == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now >= next_check:
		next_check = now + 0.1
		covered = _covered()
	if fade_covers:
		_fade_covers(delta)
	shown = move_toward(shown, 1.0 if covered else 0.0, delta * fade_speed)
	outline.visible = shown > 0.0 and body.visible
	if not outline.visible:
		return
	outline.texture = body.texture
	outline.region_enabled = true
	outline.region_rect = body.region_rect
	outline.centered = false
	outline.offset = body.offset
	outline.position = body.position
	outline.scale = body.scale
	outline.modulate = Color(1, 1, 1, shown * strength)


# Whether nearly all of the body is hidden: points over its drawn pixels, and how many something in front draws over.
func _covered() -> bool:
	covering.clear()
	var b := World.sprite_rect(body)
	var mine := (body.get_parent() as Node2D).global_position.y
	var front := []
	for s in world.occluders_near(b):
		var sprite: Sprite2D = s
		if not sprite.is_visible_in_tree():
			continue
		# In front: it sorts after them (its sort point is lower on screen).
		if (sprite.get_parent() as Node2D).global_position.y <= mine:
			continue
		var r := World.sprite_rect(sprite)
		if r.size.y < b.size.y * 0.75 or not r.intersects(b):
			continue  # nothing low (a stump, a fence, a rock) hides anyone
		front.append([sprite, r])
	if front.is_empty():
		return false
	var total := 0
	var hid := 0
	var hiding := {}
	for i in COLS:
		for j in ROWS:
			var p := b.position + Vector2((i + 0.5) / COLS * b.size.x, (j + 0.5) / ROWS * b.size.y)
			if not world.drawn_at(body, p):
				continue
			total += 1
			# Every one drawn over this point is hiding her (so all of them fade, not just the first found).
			var over := false
			for f in front:
				if f[1].has_point(p) and world.drawn_at(f[0], p):
					over = true
					hiding[f[0]] = true
			if over:
				hid += 1
	var hidden := total > 0 and hid >= total * (cover_keep if covered else cover_needed)
	if hidden and fade_covers:
		covering = hiding
	return hidden


# Fades what hides them towards see-through, and what no longer does back to solid.
func _fade_covers(delta: float) -> void:
	for s in covering:
		if not fading.has(s):
			fading[s] = 0.0
	for s in fading.keys():
		if not is_instance_valid(s):
			fading.erase(s)
			continue
		var f := move_toward(fading[s], 1.0 if covering.has(s) else 0.0, delta * cover_fade_speed)
		(s as Sprite2D).modulate.a = lerpf(1.0, cover_alpha, f)
		if f <= 0.0:
			fading.erase(s)
		else:
			fading[s] = f
