class_name Pickup
extends Node2D
## A bit of resource on the ground (from Unity's ResourcePickup), such as a chunk of stone knocked off a rock or a log
## from a felled tree. It flies out in an arc, bounces and settles, bobbing gently; once Miko comes close it drifts to
## her and is picked up into her bag, with a "+1 Stone" rising off it. Lying unclaimed for ten minutes it goes.

const MAGNET := 1.3       ## world units: within this it drifts to her
const REACH := 0.3        ## within this it's picked up
const SETTLE := 0.25      ## seconds after landing before it can be picked up
const LIFETIME := 600.0

static var _pick_sound: AudioStream
static var _last_sound := -1.0
static var _full_said := -10.0
static var _shadow_tex: Texture2D

var world: World
var resource := "Stone"
var amount := 1
var ground := Vector2.ZERO
var velocity := Vector2.ZERO
var height := 0.0
var rise := 0.0
var age := 0.0
var landed_at := -1.0
var bounces := 0
var art: Sprite2D
var shadow: Sprite2D


## Throws sprite [param sprite_id] out of [param from] in a random direction, worth [param amt] of [param res].
static func launch(w: World, res: String, amt: int, sprite_id: int, from: Vector2, scale := 0.35, throw_speed := 1.0) -> Pickup:
	var p := Pickup.new()
	p.world = w
	p.resource = res
	p.amount = amt
	p.ground = from
	var a := randf() * TAU
	var speed := randf_range(0.9, 1.8) * throw_speed * w.px
	p.velocity = Vector2(cos(a), sin(a) * 0.5) * speed  # flatter on screen, as the ground is
	p.rise = randf_range(2.6, 3.6) * w.px
	p.height = 0.35 * w.px
	p.shadow = Sprite2D.new()
	p.shadow.texture = _shadow()
	p.shadow.modulate = Color(0, 0, 0, 0.3)
	p.shadow.scale = Vector2(0.28, 0.14) * (scale / 0.35) * w.px / 32.0
	p.add_child(p.shadow)
	p.art = Sprite2D.new()
	if sprite_id >= 0:
		w.show_frame(p.art, sprite_id, Vector2(scale, scale))
		# Centred on the spot, not standing on its pivot.
		p.art.centered = true
		p.art.offset = Vector2.ZERO
	p.art.rotation_degrees = randf_range(-30.0, 30.0)
	p.add_child(p.art)
	w.things.add_child(p)
	p.position = from
	return p


## Throws [param amt] of [param res] out of [param from], its icon sized to fit (Unity's ResourcePickup.Fit).
static func launch_icon(w: World, res: String, amt: int, from: Vector2, throw_speed := 1.0) -> Pickup:
	var icon: Variant = UiKit.data.resources.get(res, {}).get("icon")
	var id := int(icon.s) if icon is Dictionary and icon.has("s") else -1
	var k := 0.35
	if id >= 0:
		var info: Dictionary = w.sprites[id]
		k = 0.32 / maxf(0.01, maxf(float(info.rect[2]), float(info.rect[3])) / float(info.ppu))
	return launch(w, res, amt, id, from, k, throw_speed)


## Drops [param amount] of [param res] at [param at] in up to three pieces (Unity's Village.Drop: coins from a monster).
static func drop(w: World, res: String, amount: int, at: Vector2) -> void:
	var pieces := clampi(amount, 1, 3)
	for i in pieces:
		var share := amount / pieces + (1 if i < amount % pieces else 0)
		if share > 0:
			launch_icon(w, res, share, at + Vector2(0, -0.3 * w.px))


func _process(delta: float) -> void:
	age += delta
	if age > LIFETIME:
		queue_free()
		return
	var px := world.px
	if landed_at < 0.0:
		# In the air: across the ground, and up and down under gravity.
		ground += velocity * delta
		rise -= 14.0 * px * delta
		height += rise * delta
		if height <= 0.0:
			height = 0.0
			if bounces < 1 and rise < -1.5 * px:
				bounces += 1
				rise = -rise * 0.35
				velocity *= 0.45
			else:
				rise = 0.0
				landed_at = age
	elif world.player != null and age - landed_at > SETTLE:
		var to: Vector2 = world.player.position - ground
		var d := to.length()
		if d < REACH * px:
			var bag: Bag = world.player.get("bag")
			# With no room for a new kind of thing it stays on the ground.
			if bag != null and not bag.add(resource, amount):
				if Time.get_ticks_msec() / 1000.0 - _full_said > 2.5:
					_full_said = Time.get_ticks_msec() / 1000.0
					FloatingText.spawn(world, "Bag full", ground + Vector2(0, -0.6 * px), Color(1, 0.55, 0.45))
				position = ground
				return
			Fainting.loot(resource, amount)  # picked up this life: it'd fall with her
			FloatingText.spawn(world, "+%d %s" % [amount, resource], ground + Vector2(0, -0.4 * px), Color(0.85, 0.86, 0.9))
			_sound()
			queue_free()
			return
		# Drift to her, faster the closer she is.
		if d < MAGNET * px:
			ground += to.normalized() * lerpf(6.0, 1.5, d / (MAGNET * px)) * px * delta
	position = ground
	var bob := sin((age - landed_at) * 4.0) * 0.02 + 0.03 if landed_at >= 0.0 else 0.0
	art.position = Vector2(0, -(height + (bob + 0.04) * px))
	shadow.scale = Vector2(0.28, 0.14) * px / 32.0 * lerpf(1.0, 0.6, clampf(height / px, 0.0, 1.0))


# The pick-up sound, not more than one every so often: a burst of logs picked up together patters, not claps.
func _sound() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_sound < 0.07:
		return
	_last_sound = now
	if _pick_sound == null and ResourceLoader.exists("res://assets/Resources/Sounds/pickup.mp3"):
		_pick_sound = load("res://assets/Resources/Sounds/pickup.mp3")
	Sfx.play(world, _pick_sound, ground, 0.6, 0.08)


static func _shadow() -> Texture2D:
	if _shadow_tex == null:
		_shadow_tex = Waterfall._dot(32, 0.6)
	return _shadow_tex
