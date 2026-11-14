class_name Party
extends Node
## Sera's party: up to [constant MOST] companions besides her (four in all), unique characters who've joined her.
## They follow her wherever she goes, keep up (or catch up, a long way behind), fight what comes at her or them, and do
## what she asks: talking to one, "Chop or mine here" (the nearest tree or rock to her, its wood or stone into her bag),
## "Wait here", "Follow me", "Go home" (leave the party). One joins when Sera asks them ("Come with me"), once the story's made them willing
## (the chronicle's "party_join:<id>": Miyu after her rescue, once she's slept it off) or they've been along before.
## Saved (world.party).

const MOST := 3
const BEHIND := 1.4               ## units behind her a companion keeps
const CATCH_UP := 28.0            ## units away a companion's brought up to her (a long way behind: teleported, the road)
const HOME_NEAR := 12.0          ## tiles out from the village a companion sent home still walks back from (further: there at once)
const GUARD := 7.0               ## units from her they go for a monster

static var active: Party

var world: World
var miko: Miko
var people: Villagers
var members: Array = []           ## unique ids, in the order they joined
var waiting := {}                 ## id -> where they were told to wait (px)
var hud: VBoxContainer


func setup(w: World, who: Miko, vs: Villagers, hud_root: Node) -> void:
	world = w
	miko = who
	people = vs
	active = self
	hud = VBoxContainer.new()
	hud.add_theme_constant_override("separation", int(4 * HudStyle.SCALE))
	hud.position = Vector2(18, 140) * HudStyle.SCALE
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(hud)
	var plates := Nameplates.new()
	plates.name = "PartyNameplates"
	plates.party = self
	w.add_child(plates)


func to_json() -> String:
	var w := {}
	for id in waiting:
		w[id] = [waiting[id].x, waiting[id].y]
	return JSON.stringify({"members": members, "waiting": w})


func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	if d is Dictionary:
		members = (d.get("members", []) as Array).map(func(m): return str(m))
		for id in d.get("waiting", {}):
			var p: Array = d.waiting[id]
			waiting[str(id)] = Vector2(float(p[0]), float(p[1]))


## Whether person [param p] is one of Sera's party.
func has_member(p: Dictionary) -> bool:
	return members.has(str(p.get("unique", "")))


## Their place in the party (0 the first), for where they walk.
func place_of(p: Dictionary) -> int:
	return members.find(str(p.get("unique", "")))


## Whether unique [param p] would come along if Sera asked: the story's made them willing ("party_join:<id>") or
## they've been with her before; and they're up (not still sleeping off what happened to them).
static func willing(p: Dictionary) -> bool:
	var ch := Chronicle.active
	if ch == null or not Traits.has(p, "unique"):
		return false
	var id := str(p.get("unique", ""))
	if not ch.happened("party:" + id) and not ch.happened("party_join:" + id):
		return false
	return active == null or active.world.clock.hours >= float(p.get("restUntil", -1.0))


## A companion hungry or thirsty under this (they don't stop to eat or drink while they're with her: it's up to her).
const NEEDY := 35.0


## Hands [param p] the best of what's to eat in their own bag, else in the bag of the one played (not with
## [param own_only]); what they ate, or "" if there's nothing (or they're full).
func feed(p: Dictionary, own_only := false) -> String:
	if float(p.get("hunger", 100.0)) >= 90.0:
		return ""
	var bags := [Companions.pack_of(p)]
	if not own_only:
		bags.append(miko.bag)
	for bag in bags:
		if bag == null:
			continue
		for f in Villager.FOODS:
			var kind := str(f[0])
			if (bag as Bag).count(kind) > 0:
				(bag as Bag).spend(kind, 1)
				p.hunger = minf(100.0, float(p.get("hunger", 100.0)) + float(f[1]))
				return kind
	return ""


## A drink for [param p] from their own water pouch, else from the one played's (not with [param own_only]):
## whether there was one to give.
func give_drink(p: Dictionary, own_only := false) -> bool:
	if float(p.get("thirst", 100.0)) >= 90.0:
		return false
	var whose := [p] if own_only else [p, {}]
	for q in whose:
		if has_pouch(q) and pouch_of(q) >= Needs.POUCH_DRINK - 0.01:
			set_pouch(q, pouch_of(q) - Needs.POUCH_DRINK)
			p["thirst"] = minf(100.0, float(p.get("thirst", 100.0)) + 40.0)
			return true
	return false


## Whether [param p] (a companion; {} the one played) carries a water pouch.
func has_pouch(p: Dictionary) -> bool:
	var bag: Bag = miko.bag if p.is_empty() else Companions.pack_of(p)
	return bag != null and bag.items.has("WaterPouch")


## How full [param p]'s water pouch is (percent; {} the one played's).
func pouch_of(p: Dictionary) -> float:
	if p.is_empty():
		var needs: Needs = miko.get_node_or_null("Needs")
		return needs.pouch if needs != null else 0.0
	return clampf(float(p.get("pouch", Needs.MAX)), 0.0, Needs.MAX)


func set_pouch(p: Dictionary, v: float) -> void:
	v = clampf(v, 0.0, Needs.MAX)
	if p.is_empty():
		var needs: Needs = miko.get_node_or_null("Needs")
		if needs != null:
			needs.pouch = v
	else:
		p["pouch"] = v


## A companion hungry or thirsty eats or drinks from their own bag, if they've anything: whether they did.
func look_after(p: Dictionary) -> bool:
	if float(p.get("hunger", 100.0)) < NEEDY and feed(p, true) != "":
		return true
	return float(p.get("thirst", 100.0)) < NEEDY and give_drink(p, true)


## The party's pouches filled along with the one played's (at a well, a river or a lake): whether any needed it.
func fill_pouches() -> bool:
	var any := false
	for id in members:
		var p := Uniques.person(people, str(id))
		if not p.is_empty() and has_pouch(p) and pouch_of(p) < Needs.MAX - 0.5:
			set_pouch(p, Needs.MAX)
			any = true
	return any


# Each companion back in the village restocks by their kit, once a visit (on their own, if their kit says so).
func _restock_at_home() -> void:
	var v := world.village
	for id in members:
		var p := Uniques.person(people, str(id))
		if p.is_empty():
			continue
		var body := Companions.body_of(p)
		var home := body != null and v.founded() and v.contains(body.position)
		if not home:
			p.erase("kitHome")
		elif not bool(p.get("kitHome", false)):
			p["kitHome"] = true
			if bool(Kit.of(p).get("auto", true)):
				Kit.restock_now(p)


func full() -> bool:
	return members.size() >= MOST


## [param id] joins (if there's room, they're here, and they can).
func join(id: String) -> bool:
	if members.has(id) or full():
		return false
	var p := Uniques.person(people, id)
	if p.is_empty() or not Traits.has(p, "unique"):
		return false
	members.append(id)
	waiting.erase(id)
	if Chronicle.active != null and not Chronicle.active.happened("party:" + id):
		Chronicle.active.record("party:" + id)
	VillageLog.event("party:" + id, "%s has joined you" % str(p.name))
	_hud()
	return true


func leave(id: String) -> void:
	members.erase(id)
	waiting.erase(id)
	_send_home(id)
	_hud()


# Sent home a long way from the village: they're there at once (by their bed, else the banner), not walking back
# across the wilds alone.
func _send_home(id: String) -> void:
	if not world.village.founded():
		return
	for v in Villager.all:
		if not is_instance_valid(v) or str(v.person.get("unique", "")) != id:
			continue
		if world.village.contains(v.position, HOME_NEAR):
			return
		var p: Dictionary = v.person
		var to := Vector2(float(p.bedX), -float(p.bedY)) * world.px if bool(p.get("hasBed", false)) else world.village.centre() + Vector2(1.0, 0.5) * world.px
		v.position = to
		v.reset_physics_interpolation()
		v.route = null
		Puffs.burst(world, to, 0.8)
		return


func wait_here(p: Dictionary, at: Vector2) -> void:
	waiting[str(p.unique)] = at


func follow(p: Dictionary) -> void:
	waiting.erase(str(p.get("unique", "")))


## Where [param p] is to be (px): behind Sera, fanned out by their place; or where they were told to wait.
func spot_for(p: Dictionary) -> Vector2:
	var id := str(p.get("unique", ""))
	if waiting.has(id):
		return waiting[id]
	var i := maxi(0, place_of(p))
	var back := Vector2(-1.0 if miko.facing_right else 1.0, -0.5 if not miko.facing_up else 0.5).normalized()
	var side := Vector2(-back.y, back.x)
	return miko.position + (back * BEHIND + side * (float(i) - float(members.size() - 1) / 2.0) * 0.9) * world.px


var _next := 0.0
var _next_sync := 0.0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_sync:
		_next_sync = now + 0.5
		var __t := Time.get_ticks_usec()
		_companions()
		Perf.add(&"party.companions", __t)
	if now < _next:
		return
	_next = now + 1.0
	# Out of a fight a while: their wounds close quickly too (their HP is their body's).
	if CharacterStats.resting():
		for id in members:
			var body := Companions.body_of(Uniques.person(people, id))
			if body != null and body.hit != null and body.hit.alive() and now - body.hit._last_hit >= CharacterStats.REST_AFTER:
				body.hit.heal(body.hit.max_hp * CharacterStats.REST_HP)
	var __r := Time.get_ticks_usec()
	_restock_at_home()
	Perf.add(&"party.restock", __r)
	_hud()


# Each companion's stats kept up to date with them (their gear, their talents, a level gained), and those with her
# able to cast what they know.
func _companions() -> void:
	for id in members:
		var p := Uniques.person(people, str(id))
		if p.is_empty():
			continue
		Companions.stats_for(p)
		var body := Companions.body_of(p)
		if body != null:
			CompanionMagic.give(body)
	Companions.sync_all()


# Their cards, under Sera's.
func _hud() -> void:
	if hud == null:
		return
	if _cards == null:
		_cards = PartyCards.new()
		_cards.party = self
		hud.get_parent().add_child(_cards)
	_cards.queue_redraw()


var _cards: PartyCards


## [param p]'s face, as on their party card (for the party window).
func face(p: Dictionary) -> Texture2D:
	if _cards == null:
		_hud()
	return _cards.face(p) if _cards != null else null


## The party's cards under Sera's: each a small version of hers: their face (level on its corner), name, HP and mana
## bars drawn as hers are, and what they're at (with her, waiting, fighting, chopping...). A click opens the party
## window.
class PartyCards extends Control:
	const CARD := Vector2(210, 66)
	const FACE := 36.0
	var party: Party
	var _faces := {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	var _player_card: Node = null

	func _process(_delta: float) -> void:
		if _player_card == null:
			var found := get_parent().find_children("*", "PlayerCard", true, false)
			if not found.is_empty():
				_player_card = found[0]
		var card := _player_card
		var k := HudStyle.SCALE
		position = Vector2(16 * k, (card.position.y + float(card.get("bottom")) if card != null else 120.0 * k) + 2 * k)
		size = Vector2(CARD.x, (CARD.y + 6) * maxi(1, party.members.size())) * k
		# (only clicked when there's a card to click)
		mouse_filter = Control.MOUSE_FILTER_IGNORE if party.members.is_empty() else Control.MOUSE_FILTER_STOP
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and PartyWindow.active != null:
			PartyWindow.active.open()
			accept_event()

	func face(p: Dictionary) -> Texture2D:
		# (Sera, a companion while someone else is played: her own portrait)
		if not Playable.villager_look(p).is_empty():
			return HudStyle.icon("portrait")
		var look := int(p.get("look", 0))
		if _faces.has(look):
			return _faces[look]
		var w := party.world
		var info: Dictionary = w.sprites[int(party.people.d.looks[look].settings.idleDown)]
		var at := AtlasTexture.new()
		at.atlas = w._texture(info.tex)
		var frame := Rect2i(int(info.rect[0]), int(info.rect[1]), int(info.rect[2]), int(info.rect[3]))
		var used := frame
		var img := at.atlas.get_image() if at.atlas != null else null
		if img != null:
			var r := img.get_region(frame).get_used_rect()
			if r.size.x > 0:
				used = Rect2i(frame.position + r.position, r.size)
		var side := mini(used.size.x, int(used.size.y * 0.5))
		at.region = Rect2(used.position.x + (used.size.x - side) / 2.0, used.position.y, side, side)
		_faces[look] = at
		return at

	func _text(s: String, at: Vector2, sz: float, kind: String, c: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
		var f := HudStyle.font(kind)
		if f == null:
			f = get_theme_default_font()
		var px := roundi(sz * HudStyle.SCALE)
		draw_string_outline(f, at, s, align, width, px, 3, Color(0, 0, 0, 0.5))
		draw_string(f, at, s, align, width, px, c)

	# A bar as on Sera's card: its icon, the bar, the number at its end ([param y] the row's top, in card units).
	func _bar(card: Rect2, col: float, col_w: float, y: float, h: float, icon: String, c: Color, frac: float, value: String) -> void:
		var k := HudStyle.SCALE
		var tex := HudStyle.icon(icon)
		if tex != null:
			draw_texture_rect(tex, Rect2(card.position + Vector2(col, y * k), Vector2(12, 12) * k), false, c)
		var back := Rect2(card.position + Vector2(col + 18 * k, (y + (12 - h) / 2.0) * k), Vector2(col_w - 18 * k - 32 * k, h * k))
		draw_style_box(HudStyle.piece("barBack"), back)
		if frac > 0.02:
			draw_style_box(HudStyle.piece("barFill", c), Rect2(back.position, Vector2(back.size.x * clampf(frac, 0.0, 1.0), back.size.y)))
		_text(value, card.position + Vector2(col + col_w - 30 * k, (y + 11) * k), 12, "pixel", HudStyle.color("text"), 30 * k, HORIZONTAL_ALIGNMENT_RIGHT)

	func _draw() -> void:
		var k := HudStyle.SCALE
		var y := 0.0
		for id in party.members:
			var p := Uniques.person(party.people, str(id))
			if p.is_empty():
				continue
			var body: Villager = null
			for v in Villager.all:
				if is_instance_valid(v) and v.person == p:
					body = v
			var card := Rect2(Vector2(0, y), CARD * k)
			draw_style_box(HudStyle.piece("panel"), card)
			var fr := Rect2(card.position + Vector2(7, 7) * k, Vector2(FACE, FACE) * k)
			draw_rect(fr, Color(0.08, 0.06, 0.06, 0.9))
			var tex := face(p)
			if tex != null:
				draw_texture_rect(tex, fr, false)
			draw_style_box(HudStyle.piece("portraitFrame"), fr)
			var lv := str(int(p.get("level", 1)))
			var badge := Rect2(fr.end - Vector2(12, 12) * k, Vector2(16, 16) * k)
			var b_tex := HudStyle.icon("badge")
			if b_tex != null:
				draw_texture_rect(b_tex, badge, false)
			_text(lv, badge.position + Vector2(0, badge.size.y * 0.75), 10, "pixel", HudStyle.color("ink"), badge.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			var col := (7 + FACE + 9) * k
			var col_w := CARD.x * k - col - 8 * k
			_text(str(p.name), card.position + Vector2(col, 16 * k), 12, "bold", HudStyle.color("text"))
			# HP and mana, as on Sera's card (mana empty for those who've learned no magic).
			var hp := body.hit.hp if body != null and body.hit != null else float(p.get("hp", 0.0))
			var most := body.hit.max_hp if body != null and body.hit != null else maxf(1.0, float(p.get("maxHp", 1.0)))
			var frac := clampf(hp / maxf(1.0, most), 0.0, 1.0)
			_bar(card, col, col_w, 20, 8, "heart", HudStyle.color("hp"), frac, str(ceili(hp)))
			var mana := float(p.get("mana", 0.0))
			_bar(card, col, col_w, 34, 6, "drop", HudStyle.color("mana"), mana / maxf(1.0, float(p.get("maxMana", 0.0))), str(floori(mana)))
			# What they're at.
			var doing := "Away" if body == null else body.activity()
			var low := frac < 0.3
			_text(doing, card.position + Vector2(7 * k, 60 * k), 10, "body", HudStyle.color("coral") if low else HudStyle.color("muted"), CARD.x * k - 14 * k, HORIZONTAL_ALIGNMENT_LEFT)
			y += (CARD.y + 6) * k


## Each companion's name in the world, small under their feet, so the party's told apart from the villagers. Bright
## whatever the hour.
class Nameplates extends Node2D:
	const SIZE := 15                  ## the name's height on screen at the usual zoom (world pixels)
	const BELOW := 0.08               ## units under their feet
	var party: Party

	func _ready() -> void:
		z_as_relative = false
		z_index = 3996
		World.keep_lit(self)

	func _process(_delta: float) -> void:
		var __t := Time.get_ticks_usec()
		queue_redraw()
		Perf.add(&"party.nameplates", __t)

	func _draw() -> void:
		if party.members.is_empty():
			return
		var f := HudStyle.font("bold")
		if f == null:
			f = ThemeDB.fallback_font
		for v in Villager.all:
			if not is_instance_valid(v) or not v.visible or not party.has_member(v.person):
				continue
			var at := v.position + Vector2(-60.0, BELOW * party.world.px + SIZE)
			draw_string_outline(f, at, str(v.person.name), HORIZONTAL_ALIGNMENT_CENTER, 120.0, SIZE, 4, Color(0, 0, 0, 0.75))
			draw_string(f, at, str(v.person.name), HORIZONTAL_ALIGNMENT_CENTER, 120.0, SIZE, HudStyle.color("accentLight"))
