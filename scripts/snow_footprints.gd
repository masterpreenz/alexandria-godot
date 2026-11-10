class_name SnowFootprints
extends Node2D
## Footprints in the snow (from Unity's SnowFootprints): while Miko walks where the ground is white, a print is pressed
## every step (left, right, turned the way she walks). Prints fill in over time and go as the snow melts. Not on laid
## floors (indoors), nor where the snow's been cleared (round a fire).

const STRIDE := 0.3              ## units walked between prints
const GAIT := 0.06               ## units each foot is from the middle of her path
const LIFETIME := 40.0           ## seconds a print takes to fill back in
const MOST := 120
const TINT := Color(0.5, 0.58, 0.75, 0.7)

static var _print: Texture2D

var world: World
var miko: Miko
var snow: SnowCover
var _prints: Array = []          ## [Sprite2D, when made]
var _last := Vector2.ZERO
var _walked := 0.0
var _left := false


func setup(w: World, who: Miko, cover: SnowCover) -> void:
	world = w
	miko = who
	snow = cover
	_last = miko.position
	World.keep_lit(self)
	w.add_ground_layer(self, -9960)


func _process(_delta: float) -> void:
	var at := miko.position
	var step := at - _last
	_last = at
	var px := world.px
	if step.length_squared() > 0.0001 and step.length() < px and not miko.airborne():
		_walked += Vector2(step.x, step.y * 2.0).length()
		if _walked >= STRIDE * px:
			_walked = 0.0
			_left = not _left
			_press(at, step.normalized())
	if _prints.is_empty():
		return
	# Filling back in with time, and going with the snow.
	var now := Time.get_ticks_msec() / 1000.0
	var lying := clampf(snow.cover * 3.0, 0.0, 1.0)
	for p in _prints:
		var sp: Sprite2D = p[0]
		var a := TINT.a * clampf(1.0 - (now - float(p[1])) / LIFETIME, 0.0, 1.0) * lying
		sp.modulate.a = a
		sp.visible = a > 0.01


func _press(at: Vector2, dir: Vector2) -> void:
	if snow.ground_snow(at) < 0.5:
		return
	var side := Vector2(-dir.y, dir.x * 0.5) * (GAIT if _left else -GAIT) * world.px
	var sp: Sprite2D
	if _prints.size() < MOST:
		sp = Sprite2D.new()
		sp.texture = _texture()
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.scale = Vector2.ONE * world.px / 64.0
		add_child(sp)
	else:
		sp = _prints.pop_front()[0]
	sp.position = at + side
	sp.rotation = dir.angle() + PI / 2.0
	sp.modulate = TINT
	_prints.append([sp, Time.get_ticks_msec() / 1000.0])


# A small boot print, pointing up: a sole and a heel, soft at the edges.
static func _texture() -> Texture2D:
	if _print == null:
		var w := 8
		var h := 14
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var u := (x + 0.5 - w / 2.0) / (w / 2.0)
				var sole := Vector2(u / 0.95, (y + 0.5 - 4.5) / 4.5).length_squared() <= 1.0
				var heel := Vector2(u / 0.8, (y + 0.5 - 11.5) / 2.5).length_squared() <= 1.0
				var on := sole or heel
				var edge := on and (x == 0 or x == w - 1 or y == 0 or y == h - 1)
				img.set_pixel(x, y, Color(1, 1, 1, 0.6 if edge else 1.0) if on else Color(0, 0, 0, 0))
		_print = ImageTexture.create_from_image(img)
	return _print
