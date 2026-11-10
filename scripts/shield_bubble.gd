class_name ShieldBubble
extends Node2D
## The ward a shield shikigami raises where it was sent (from Unity's ShieldBubble): a faint blue dome over a circle
## turning on the ground. Whoever stands inside it (its summoner and their allies) takes a little less damage and builds
## up a shield over time, up to a limit. When the shikigami's time is up the dome fades; the shields it gave stay until
## they're used up.

const FADE_IN := 0.35
const FADE_OUT := 0.5
const SPIN := 25.0

static var _dome: Texture2D

var world: World
var owner_stats: CharacterStats
var owner_node: Node2D
var radius := 0.0
var guard := 0.0
var cap := 0.0
var rate := 0.0
var tint := Color.WHITE
var age := 0.0
var end_at := -1.0
var owner_shield := 0.0
var allies := {}           ## Damageable -> its shield from this ward
var ground: Sprite2D
var flat: Node2D
var shell: Sprite2D


static func spawn(w: World, stats: CharacterStats, who: Node2D, at: Vector2, area: float, guard_percent: float, shield_cap: float, fill_seconds: float, circle: int, c: Color) -> ShieldBubble:
	var b := ShieldBubble.new()
	b.world = w
	b.owner_stats = stats
	b.owner_node = who
	b.radius = area
	b.guard = guard_percent
	b.cap = shield_cap
	b.rate = shield_cap / maxf(0.1, fill_seconds)
	b.tint = c
	b.position = at
	# The circle on the ground, squashed flat onto the 2:1 ground, under everyone.
	b.flat = Node2D.new()
	b.flat.position = at
	w.add_ground_layer(b.flat, -9979)
	b.ground = Sprite2D.new()
	if circle >= 0:
		var info: Dictionary = w.sprites[circle]
		b.ground.texture = w._texture(info.tex)
		b.ground.region_enabled = true
		b.ground.region_rect = Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
		var k: float = area / (float(info.rect[2]) * 0.5)
		b.flat.scale = Vector2(k, k * 0.5)
	b.flat.add_child(b.ground)
	# The dome: a soft bubble, clear in the middle and bright at the rim, over everyone.
	b.shell = Sprite2D.new()
	b.shell.texture = dome()
	b.shell.z_as_relative = false
	b.shell.z_index = 3985
	var d := float(b.shell.texture.get_width())
	b.shell.position = Vector2(0, -area * 0.32)
	b.shell.scale = Vector2(area * 2.0 / d, area * 1.35 / d)
	b.add_child(b.shell)
	b._paint(0.0)
	w.add_child(b)
	return b


## Lets the ward fade (its shikigami is gone); the shields it gave stay.
func end() -> void:
	if end_at < 0.0:
		end_at = age


func _inside(p: Vector2) -> bool:
	var d := p - position
	return Vector2(d.x, d.y * 2.0).length() <= radius


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"shield_bubble.process", __t)


func _process_timed(delta: float) -> void:
	age += delta
	var shown := clampf(age / FADE_IN, 0.0, 1.0)
	if end_at >= 0.0:
		shown = minf(shown, 1.0 - clampf((age - end_at) / FADE_OUT, 0.0, 1.0))
		if shown <= 0.0:
			queue_free()
			return
	ground.rotation -= deg_to_rad(SPIN) * delta
	var live := end_at < 0.0
	# The summoner: warded while inside, the shield building up to its limit.
	if owner_stats != null and is_instance_valid(owner_node):
		var warded := live and _inside(owner_node.position)
		owner_stats.set_guard(self, guard if warded else 0.0)
		# Still Waters: mana comes back faster inside.
		var calm := owner_stats.stat("shieldManaRegen") if warded else 0.0
		if calm > 0.0:
			if not owner_stats.buffs.has(self):
				owner_stats.set_buff(self, {"manaRegen": calm})
		elif owner_stats.buffs.has(self):
			owner_stats.set_buff(self, null)
		# What the shield soaked is gone; it refills from there.
		owner_shield = minf(owner_shield, owner_stats.shield_from(self))
		if warded:
			owner_shield = minf(cap, owner_shield + rate * delta)
		if live:
			owner_stats.set_shield(self, owner_shield)
	if live:
		for a in Damageable.all:
			if a.team != Damageable.Team.ALLY or not a.alive():
				continue
			if a is Shikigami and a.kind == "Defender":
				continue  # not itself
			if not _inside(a.global_position):
				continue
			var sh := minf(cap, minf(float(allies.get(a, 0.0)), a.shield_from(self)) + rate * delta)
			allies[a] = sh
			a.set_shield(self, sh)
	_paint(shown)


func _paint(shown: float) -> void:
	var pulse := 0.85 + 0.15 * sin(age * 2.5)
	ground.modulate = Color(tint, 0.55 * shown)
	shell.modulate = Color(tint, 0.55 * shown * pulse)


# Gone: the damage cut ends, but the shields it built stay until they're used up.
func _exit_tree() -> void:
	if is_instance_valid(flat):
		flat.queue_free()
	if owner_stats != null and is_instance_valid(owner_stats):
		owner_stats.set_guard(self, 0.0)
		owner_stats.set_buff(self, null)


## A bubble: nearly clear inside, a soft bright rim, a gleam near the top.
static func dome() -> Texture2D:
	if _dome != null:
		return _dome
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x - (n - 1) * 0.5) / (n * 0.5)
			var v := -(y - (n - 1) * 0.5) / (n * 0.5)
			var d := sqrt(u * u + v * v)
			if d > 1.0:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
				continue
			var rim := pow(d, 4.0) * 0.55
			var edge := clampf((1.0 - d) * 18.0, 0.0, 1.0)
			var gleam := clampf(1.0 - Vector2(u + 0.35, v - 0.45).length() * 4.0, 0.0, 1.0) * 0.35
			img.set_pixel(x, y, Color(1, 1, 1, (0.06 + rim + gleam) * edge))
	_dome = ImageTexture.create_from_image(img)
	return _dome
