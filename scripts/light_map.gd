class_name LightMap
extends CanvasLayer
## The world's lights drawn in one pass over the screen (shaders/light_pass.gdshader), not by Godot's 2D lights: those
## add up where they overlap (two torches close together lit twice as bright) and cost more the more sprites each one
## reaches. Every PointLight2D in the game stays where it is and as it's set (its colour, energy, size, on or off: the
## fires, torches, crystals and the rest keep making and switching them as before) but lights nothing itself; each
## frame those on screen are gathered, and each pixel takes the brightest of them. Over the world, under the HUD.

const MOST := 48                     ## lights gathered at most (the nearest the middle of the screen first)
const UNLIT_LAYER := 1 << 12         ## the render layer of what's shown as drawn (bubbles, numbers, outlines): not lit again
const MASK_SCALE := 0.5              ## the mask of those, drawn at this share of the screen's size

var world: World
var daylight: CanvasModulate
var _rect: ColorRect
var _mat: ShaderMaterial
var _lights: Array = []              ## every PointLight2D in the game
var _mask: SubViewport                ## just what's kept unlit, drawn where it is on screen (its alpha the mask)


func setup(w: World, light: CanvasModulate) -> void:
	world = w
	daylight = light
	name = "LightMap"
	layer = 0                        # (over the world, as the vignette is; drawn before it)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/light_pass.gdshader")
	_mat.set_shader_parameter("glow", Fires._glow())
	_rect.material = _mat
	add_child(_rect)
	_mask = SubViewport.new()
	_mask.name = "UnlitMask"
	_mask.world_2d = get_viewport().world_2d
	_mask.transparent_bg = true
	_mask.disable_3d = true
	_mask.canvas_cull_mask = UNLIT_LAYER
	_mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_mask)
	_mat.set_shader_parameter("unlit_mask", _mask.get_texture())
	get_tree().node_added.connect(_added)
	for n in get_tree().root.find_children("*", "PointLight2D", true, false):
		_added(n)


# A light made: it lights nothing itself (its range takes in no sprites); this draws it.
func _added(n: Node) -> void:
	if n is PointLight2D:
		(n as PointLight2D).range_item_cull_mask = 0
		_lights.append(n)


func _process(_delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_gather()
	Perf.add(&"light_map.process", __t)


func _gather() -> void:
	var vp := get_viewport()
	var xf := vp.get_canvas_transform()
	var size := vp.get_visible_rect().size
	var msize := Vector2i((size * MASK_SCALE).ceil())
	if _mask.size != msize:
		_mask.size = msize
	_mask.canvas_transform = Transform2D().scaled(Vector2(MASK_SCALE, MASK_SCALE)) * xf
	var zoom := xf.get_scale().x
	var view := Rect2(Vector2.ZERO, size)
	var found := []
	var keep := []
	for l in _lights:
		if not is_instance_valid(l):
			continue
		keep.append(l)
		var p := l as PointLight2D
		if not p.enabled or not p.is_visible_in_tree() or p.energy <= 0.0 or p.texture == null:
			continue
		var r := p.texture.get_width() * p.texture_scale * absf(p.global_scale.x) * 0.5 * zoom
		var at: Vector2 = xf * (p.global_position + p.offset)
		if not view.grow(r).has_point(at):
			continue
		found.append([at.distance_squared_to(size / 2.0), at, r, Vector3(p.color.r, p.color.g, p.color.b) * p.energy * p.color.a])
	_lights = keep
	found.sort_custom(func(a, b): return a[0] < b[0])
	var pos := PackedVector4Array()
	var col := PackedVector3Array()
	for i in mini(found.size(), MOST):
		pos.append(Vector4(found[i][1].x, found[i][1].y, found[i][2], 0.0))
		col.append(found[i][3])
	while pos.size() < MOST:
		pos.append(Vector4.ZERO)
		col.append(Vector3.ZERO)
	_mat.set_shader_parameter("lights", pos)
	_mat.set_shader_parameter("colours", col)
	_mat.set_shader_parameter("count", mini(found.size(), MOST))
	# (no light on screen, or broad daylight where they'd add next to nothing: no pass at all, no mask drawn)
	var c0 := daylight.color if daylight != null else Color.WHITE
	var on := not found.is_empty() and minf(c0.r, minf(c0.g, c0.b)) < 0.97
	_rect.visible = on
	_mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_mat.set_shader_parameter("screen_px", size)
	var c := daylight.color if daylight != null else Color.WHITE
	_mat.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
