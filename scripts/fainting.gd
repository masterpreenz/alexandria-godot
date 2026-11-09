class_name Fainting
extends Node
## Miko fainting (from Unity's Fainting): at 0 HP she staggers and falls, the screen goes dark, and she wakes a couple
## of hours later in front of the town banner (else where she started) with half her HP.
##
## Whatever she picked up this life (since she last woke) falls where she fainted, in a lost bag; walking back over it
## takes it all back. Fainting again before then loses the old bag for good. (The bag she wears falling too, with the
## gear in its slots, comes with the character panel's equipment.)

## What she's picked up this life, by resource: what a lost bag would hold.
static var looted := {}

var world: World
var miko: Miko
var s: Dictionary                 ## monsters.json's fainting settings
var fainted := false
var start := Vector2.ZERO
var clock := 0.0
var wake_at := 0.0
var woke := false
var dark: ColorRect
var dark_text: Label


## This life's loot and the bag left where she last fainted, as Unity's player.life (units, y up).
static func to_json(w: World) -> String:
	var loot_list := []
	var bag_list := []
	var lost: LostBag = LostBag.active if LostBag.active != null and is_instance_valid(LostBag.active) else null
	for r in Bag.RESOURCES:
		loot_list.append({"resource": r, "amount": int(looted.get(r, 0))})
		bag_list.append({"resource": r, "amount": int(lost.counts.get(r, 0)) if lost != null else 0})
	var d := {"looted": loot_list, "hasBag": lost != null, "bagX": 0.0, "bagY": 0.0, "bag": bag_list if lost != null else [], "bagWorn": "", "bagGear": []}
	if lost != null:
		d.bagX = lost.position.x / w.px
		d.bagY = -lost.position.y / w.px
	return JSON.stringify(d)


## Puts back this life's loot and any lost bag from the save.
static func from_json(w: World, json: String) -> void:
	looted.clear()
	var d: Variant = JSON.parse_string(json)
	if not d is Dictionary:
		return
	for a in d.get("looted", []):
		if int(a.amount) > 0:
			looted[a.resource] = int(a.amount)
	if bool(d.get("hasBag", false)):
		var counts := {}
		for a in d.get("bag", []):
			if int(a.amount) > 0:
				counts[a.resource] = int(a.amount)
		LostBag.make(w, counts, Vector2(float(d.bagX) * w.px, -float(d.bagY) * w.px))


## Counts [param amount] of [param r] as picked up this life (it'd fall with her).
static func loot(r: String, amount: int) -> void:
	if amount > 0:
		looted[r] = int(looted.get(r, 0)) + amount


func setup(w: World, who: Miko, settings: Dictionary, hud: Node) -> void:
	world = w
	miko = who
	s = settings
	start = miko.position
	miko.stats.downed.connect(func(): if not fainted: faint())
	dark = ColorRect.new()
	dark.color = Color(0, 0, 0, 0)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.visible = false
	hud.add_child(dark)
	dark_text = Label.new()
	dark_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dark_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dark_text.add_theme_font_size_override("font_size", 26)
	if UiKit.body_font:
		dark_text.add_theme_font_override("font", UiKit.body_font)
	dark.add_child(dark_text)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"fainting.process", __t)


func _process_timed(delta: float) -> void:
	if not fainted:
		return
	clock += delta
	# Staggering, falling, then lying there breathing (how long until she's down; the dark only falls after).
	var stagger := 10.0 / float(s.staggerFps)
	var down := stagger + 2.0 / float(s.fallFps)
	if not woke:
		var sheet: Array = s.faintBack if miko.facing_up else s.faintFront
		if sheet.size() >= 16:
			var f: int
			if clock < stagger: f = floori(clock * float(s.staggerFps))
			elif clock < down: f = 10 + floori((clock - stagger) * float(s.fallFps))
			else: f = 12 + floori((clock - down) * float(s.lyingFps)) % 4
			miko.pose = int(sheet[clampi(f, 0, 15)])
			miko.pose_mirror = miko.facing_right != bool(s.faintFacesRight)
		else:
			down = 0.6
		wake_at = maxf(float(s.darkFor), down + float(s.darkAfterFall))
	# Dark in once she's down, a while, she wakes elsewhere, dark out.
	var fade_in := clampf((clock - down) / 0.8, 0.0, 1.0)
	var fade_out := clampf((clock - wake_at - 0.6) / 0.9, 0.0, 1.0)
	_set_dark(1.0 - fade_out if woke else fade_in)
	if not woke and clock >= wake_at:
		_wake_up()
	if woke and fade_out >= 1.0:
		_done()


func faint() -> void:
	fainted = true
	woke = false
	clock = 0.0
	var needs: Needs = miko.get_node_or_null("Needs")
	if needs != null:
		needs.end_sleep_now()
	miko.locked = true
	miko.velocity = Vector2.ZERO
	LostBag.drop(world, miko.bag, looted, miko.position)
	looted = {}
	dark_text.text = "Miko fainted…"


func _wake_up() -> void:
	woke = true
	var at := start
	if world.village.founded():
		at = world.village.centre() + Vector2(0, 0.6 * world.px)
	miko.place(at)
	miko.pose = -1
	var cam := miko.get_viewport().get_camera_2d()
	if cam != null:
		cam.position = at
		cam.reset_smoothing()
	miko.stats.hp = miko.stats.stat("maxHp") * float(s.wakeHp)
	miko.stats.changed.emit()
	if world.clock != null:
		world.clock.hours += float(s.hoursPass)
	dark_text.text = "…and woke up. Your bag was left where you fell." if LostBag.active != null else "…and woke up."


func _done() -> void:
	fainted = false
	_set_dark(0.0)
	miko.locked = false
	if LostBag.active != null:
		FloatingText.spawn(world, "Find your bag", miko.position + Vector2(0, -1.9 * world.px), UiKit.colors.gold)


func _set_dark(a: float) -> void:
	dark.visible = a > 0.001
	dark.color = Color(0, 0, 0, a * 0.92)
	dark_text.modulate.a = clampf(a * 2.0 - 1.0, 0.0, 1.0)


## The bag Miko leaves where she faints, holding what she'd picked up that life. Walking over it takes it all back.
## Only one at a time: a new one replaces it.
class LostBag extends Node2D:
	static var active: LostBag

	var world: World
	var counts := {}
	var icon: Sprite2D
	var phase := 0.0

	## Takes this life's loot out of [param from] into a bag at [param at]; replaces any bag already lying out.
	static func drop(w: World, from: Bag, loot: Dictionary, at: Vector2) -> void:
		var amounts := {}
		for r in loot:
			var n := mini(int(loot[r]), from.count(r))
			if n > 0 and from.spend(r, n):
				amounts[r] = n
		make(w, amounts, at)

	## A lost bag holding [param counts] at [param at] (a new one, or one from the save); replaces any lying out.
	static func make(w: World, amounts: Dictionary, at: Vector2) -> void:
		if active != null and is_instance_valid(active):
			active.queue_free()  # the old one is lost
		active = null
		if amounts.is_empty():
			return
		var b := LostBag.new()
		b.world = w
		b.counts = amounts
		b.position = at
		b.phase = randf() * 6.0
		b.icon = Sprite2D.new()
		var id := int(w.get_meta("lost_bag_icon", -1))
		if id >= 0:
			w.show_frame(b.icon, id)
			b.icon.centered = true
			b.icon.offset = Vector2.ZERO
			var info: Dictionary = w.sprites[id]
			var size := maxf(float(info.rect[2]), float(info.rect[3])) / float(info.ppu)
			b.icon.scale = Vector2.ONE * 0.45 / maxf(0.01, size) * w.px / float(info.ppu)
		b.add_child(b.icon)
		w.things.add_child(b)
		active = b

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"fainting.LostBag.process", __t)


	func _process_timed(_delta: float) -> void:
		# Bobbing and glowing a little, so it's seen from a way off.
		var t := Time.get_ticks_msec() / 1000.0 + phase
		icon.position = Vector2(0, (-0.3 - sin(t * 2.5) * 0.05) * world.px)
		var glow := 0.75 + 0.25 * sin(t * 4.0)
		icon.modulate = Color(1.0, 0.85 * glow + 0.15, 0.45 * glow)
		var p := world.player as Miko
		if p == null or p.position.distance_to(position) > 0.5 * world.px or p.locked:
			return
		var parts := []
		for r in counts:
			var n: int = counts[r]
			if p.bag.add(r, n):
				Fainting.loot(r, n)  # in hand again: it'd fall again
			else:
				Pickup.drop(world, r, n, position)  # no room: it spills beside her
			parts.append("%d %s" % [n, UiKit.resource_name(r)])
		FloatingText.spawn(world, "Recovered your bag: " + ", ".join(parts), position + Vector2(0, -1.2 * world.px), Color(0.62, 0.86, 0.5))
		active = null
		queue_free()
