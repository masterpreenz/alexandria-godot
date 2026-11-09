class_name Waterfall
## The waterfall's spray and mist (new in Godot): droplets thrown up and out where the falls hit the water below,
## falling back, and soft mist rising off the foot and drifting, fading. Both made of particles, drawn over the water.


## The particles for a falls whose face is [param verts] (with [param uvs]: y 1 along its foot).
static func spray(verts: PackedVector2Array, uvs: PackedVector2Array) -> Node2D:
	var holder := Node2D.new()
	holder.name = "Spray"
	# The foot: the face's bottom edge, its middle and how wide it is.
	var foot := []
	for i in verts.size():
		if i < uvs.size() and uvs[i].y > 0.5:
			foot.append(verts[i])
	if foot.size() < 2:
		return holder
	var a: Vector2 = foot[0]
	var b: Vector2 = foot[1]
	var mid := (a + b) / 2.0
	var half_width := a.distance_to(b) / 2.0
	holder.add_child(_droplets(mid, half_width))
	holder.add_child(_mist(mid, half_width))
	return holder


static func _droplets(at: Vector2, half_width: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Droplets"
	p.position = at
	p.amount = 90
	p.lifetime = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(half_width * 0.85, 4.0)
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 150.0
	p.gravity = Vector2(0, 420)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.texture = _dot(8, 0.2)
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 1.0, 1.0, 0.9))
	g.set_color(1, Color(0.85, 0.95, 1.0, 0.0))
	p.color_ramp = g
	return p


static func _mist(at: Vector2, half_width: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Mist"
	p.position = at + Vector2(0, -6)
	p.amount = 26
	p.lifetime = 3.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(half_width, 6.0)
	p.direction = Vector2(0.2, -1)
	p.spread = 25.0
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 28.0
	p.gravity = Vector2(6, -4)
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	p.texture = _dot(64, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.2, Color(0.92, 0.97, 1.0, 0.32))
	g.add_point(0.7, Color(0.92, 0.97, 1.0, 0.14))
	p.color_ramp = g
	return p


static var _dots := {}

# A round, soft-edged dot, [param size] px across, [param softness] of its radius fading out.
static func _dot(size: int, softness: float) -> Texture2D:
	var key := Vector2(size, softness)
	if _dots.has(key):
		return _dots[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - size / 2.0, y + 0.5 - size / 2.0).length() / (size / 2.0)
			var a := clampf((1.0 - d) / maxf(softness, 0.01), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	var tex := ImageTexture.create_from_image(img)
	_dots[key] = tex
	return tex
