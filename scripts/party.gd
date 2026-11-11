class_name Party
extends Node
## Sera's party: up to [constant MOST] companions besides her (four in all), unique characters who've joined her.
## They follow her wherever she goes, keep up (or catch up, a long way behind), fight what comes at her or them, and do
## what she asks: talking to one, "Chop or mine here" (the nearest tree or rock to her, its wood or stone into her bag),
## "Wait here", "Follow me", "Go home" (leave the party). One joins when the story says so (the chronicle's
## "party_join:<id>", once they're up and about: Miyu after she's slept off her rescue). Saved (world.party).

const MOST := 3
const BEHIND := 1.4               ## units behind her a companion keeps
const CATCH_UP := 28.0            ## units away a companion's brought up to her (a long way behind: teleported, the road)
const GUARD := 7.0                ## units from her they go for a monster

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
	_hud()


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


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next:
		return
	_next = now + 1.0
	# The story's joins, once they're up and about.
	if Chronicle.active != null and not full():
		for e in Chronicle.active.events:
			var what := str(e.what)
			if not what.begins_with("party_join:"):
				continue
			var id := what.trim_prefix("party_join:")
			if members.has(id) or Chronicle.active.happened("party:" + id) or Uniques.lost(id):
				continue
			var p := Uniques.person(people, id)
			if p.is_empty() or world.clock.hours < float(p.get("restUntil", -1.0)):
				continue
			join(id)
	_hud()


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


## The party's cards under Sera's: each a small version of hers: their face (level on its corner), name, HP, and
## what they're at (with her, waiting, fighting, chopping...).
class PartyCards extends Control:
	const CARD := Vector2(210, 50)
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
		queue_redraw()

	func _face(p: Dictionary) -> Texture2D:
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

	## Whether they have mana (only those who've learned magic: villagers haven't any).
	func _has_mana(p: Dictionary) -> bool:
		return float(p.get("maxMana", 0.0)) > 0.0

	func _height(p: Dictionary) -> float:
		return CARD.y + (12.0 if _has_mana(p) else 0.0)

	func _text(s: String, at: Vector2, sz: float, kind: String, c: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
		var f := HudStyle.font(kind)
		if f == null:
			f = get_theme_default_font()
		var px := roundi(sz * HudStyle.SCALE)
		draw_string_outline(f, at, s, align, width, px, 3, Color(0, 0, 0, 0.5))
		draw_string(f, at, s, align, width, px, c)

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
			var card := Rect2(Vector2(0, y), Vector2(CARD.x, _height(p)) * k)
			draw_style_box(HudStyle.piece("panel"), card)
			var fr := Rect2(card.position + Vector2(7, 7) * k, Vector2(FACE, FACE) * k)
			draw_rect(fr, Color(0.08, 0.06, 0.06, 0.9))
			var face := _face(p)
			if face != null:
				draw_texture_rect(face, fr, false)
			draw_style_box(HudStyle.piece("portraitFrame"), fr)
			var lv := str(int(p.get("level", 1)))
			var badge := Rect2(fr.end - Vector2(12, 12) * k, Vector2(16, 16) * k)
			var b_tex := HudStyle.icon("badge")
			if b_tex != null:
				draw_texture_rect(b_tex, badge, false)
			_text(lv, badge.position + Vector2(0, badge.size.y * 0.75), 10, "pixel", HudStyle.color("ink"), badge.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			var col := (7 + FACE + 9) * k
			var col_w := CARD.x * k - col - 8 * k
			_text(str(p.name), card.position + Vector2(col, 17 * k), 12, "bold", HudStyle.color("text"))
			# HP.
			var hp := body.hit.hp if body != null and body.hit != null else float(p.get("hp", 0.0))
			var most := body.hit.max_hp if body != null and body.hit != null else maxf(1.0, float(p.get("maxHp", 1.0)))
			var heart := HudStyle.icon("heart")
			if heart != null:
				draw_texture_rect(heart, Rect2(card.position + Vector2(col, 22 * k), Vector2(10, 10) * k), false, HudStyle.color("hp"))
			var back := Rect2(card.position + Vector2(col + 14 * k, 24 * k), Vector2(col_w - 14 * k - 30 * k, 6 * k))
			draw_style_box(HudStyle.piece("barBack"), back)
			var frac := clampf(hp / maxf(1.0, most), 0.0, 1.0)
			if frac > 0.02:
				draw_style_box(HudStyle.piece("barFill", HudStyle.color("hp")), Rect2(back.position, Vector2(back.size.x * frac, back.size.y)))
			_text(str(ceili(hp)), card.position + Vector2(col + col_w - 30 * k, 31 * k), 11, "pixel", HudStyle.color("text"), 30 * k, HORIZONTAL_ALIGNMENT_RIGHT)
			# Mana, for those who have it (once they've learned magic).
			var line := 44.0
			if _has_mana(p):
				var mana := float(p.get("mana", 0.0))
				var most_mana := maxf(1.0, float(p.maxMana))
				var drop := HudStyle.icon("drop")
				if drop != null:
					draw_texture_rect(drop, Rect2(card.position + Vector2(col, 34 * k), Vector2(10, 10) * k), false, HudStyle.color("mana"))
				var mb := Rect2(card.position + Vector2(col + 14 * k, 36 * k), Vector2(col_w - 14 * k - 30 * k, 5 * k))
				draw_style_box(HudStyle.piece("barBack"), mb)
				var mf := clampf(mana / most_mana, 0.0, 1.0)
				if mf > 0.02:
					draw_style_box(HudStyle.piece("barFill", HudStyle.color("mana")), Rect2(mb.position, Vector2(mb.size.x * mf, mb.size.y)))
				_text(str(floori(mana)), card.position + Vector2(col + col_w - 30 * k, 43 * k), 11, "pixel", HudStyle.color("text"), 30 * k, HORIZONTAL_ALIGNMENT_RIGHT)
				line = 56.0
			# What they're at.
			var doing := "Away" if body == null else body.activity()
			var low := frac < 0.3
			_text(doing, card.position + Vector2(col, line * k), 10, "body", HudStyle.color("coral") if low else HudStyle.color("muted"), col_w, HORIZONTAL_ALIGNMENT_LEFT)
			y += (_height(p) + 6) * k
