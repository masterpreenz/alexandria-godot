class_name PlayerCard
extends Control
## Miko's card, top left (from Unity's PlayerHud): her portrait with a level badge (click it for the character panel,
## with phase 5's character step), her name and coins (carried and stored), HP (with any shield as a blue band over
## it) and mana, then hunger and rest. Mana flashes red when a spell wanted more; hunger and rest turn coral when low.
## Under the card, a row of tags for her buffs and debuffs (green for good, red for bad, with any time left; hovering
## one says what it does), and under that a rack of small squares for skills cooling down.

const CARD := Vector2(272, 74)
const COL_X := 74.0
const CHIP := 32.0
const TAG_H := 20.0

var bottom := 0.0                ## how far down the card and what's under it reach (px): the party's cards go below

var world: World
var miko: Miko
var stats: CharacterStats
var needs: Needs
var caster: SpellCaster
var _mana_flash := 0.0
var _hovered := -1
var _tag_rects: Array = []


func setup(w: World, who: Miko, c: SpellCaster) -> void:
	world = w
	miko = who
	stats = who.stats
	needs = who.get_node_or_null("Needs")
	caster = c
	position = Vector2(16, 16)
	size = Vector2(CARD.x, 200) * HudStyle.SCALE
	mouse_filter = Control.MOUSE_FILTER_PASS
	stats.out_of_mana.connect(func(): _mana_flash = 1.0)


func _k(v: float) -> float:
	return v * HudStyle.SCALE


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"player_card.process", __t)


func _process_timed(delta: float) -> void:
	_mana_flash = move_toward(_mana_flash, 0.0, delta * 2.0)
	# Hovering a tag shows what it does.
	var m := get_local_mouse_position()
	_hovered = -1
	for i in _tag_rects.size():
		if (_tag_rects[i] as Rect2).has_point(m):
			_hovered = i
	queue_redraw()


func _draw() -> void:
	var k := HudStyle.SCALE
	var card := Rect2(Vector2.ZERO, CARD * k)
	draw_style_box(HudStyle.piece("panel"), card)
	# Portrait, its frame, and the level badge on its corner.
	var portrait := HudStyle.icon("portrait")
	var pr := Rect2(Vector2(8, 8) * k, Vector2(56, 56) * k)
	if portrait != null:
		draw_texture_rect(portrait, pr, false)
	draw_style_box(HudStyle.piece("portraitFrame"), pr)
	var badge := Rect2(Vector2(8 + 56 - 15, 8 + 56 - 15) * k, Vector2(20, 20) * k)
	var b_tex := HudStyle.icon("badge")
	if b_tex != null:
		draw_texture_rect(b_tex, badge, false)
	_text(str(stats.level), badge.position + Vector2(0, badge.size.y * 0.75), 12, "pixel", HudStyle.color("ink"), badge.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var col_w := CARD.x - COL_X - 8.0
	# Name, her level beside it, and coins.
	_text(Miko.NAME, Vector2(COL_X, 20) * k, 14, "bold", HudStyle.color("text"))
	var nf := HudStyle.font("bold")
	var nw := nf.get_string_size(Miko.NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14 * k)).x if nf else 36.0 * k
	_text("Lv %d" % stats.level, Vector2(COL_X * k + nw + 6 * k, 20 * k), 12, "pixel", HudStyle.color("accentLight"))
	var coins := miko.bag.count("Gold") + world.village.stored("Gold")
	var coin_text := str(coins)
	var f := HudStyle.font("pixel")
	var cw := f.get_string_size(coin_text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(13 * k)).x if f else 30.0
	_text(coin_text, Vector2(COL_X, 20) * k, 13, "pixel", HudStyle.color("accentLight"), col_w * k, HORIZONTAL_ALIGNMENT_RIGHT)
	var gold := UiKit.resource_icon("Gold")
	if gold != null:
		draw_texture_rect(gold, Rect2(Vector2((COL_X + col_w) * k - cw - 18 * k, 8 * k), Vector2(14, 14) * k), false)
	# HP (with the shield band over it) and mana.
	var t := stats.total()
	var max_hp := maxf(1.0, float(t.get("maxHp", 100.0)))
	var shield := stats.shield()
	_bar(26, 8, "heart", HudStyle.color("hp"), stats.hp / max_hp, str(ceili(stats.hp + shield)),
		Color(0.62, 0.8, 1.0) if shield > 0.5 else HudStyle.color("text"), shield / max_hp)
	var back_tint := Color.WHITE.lerp(Color(1, 0.35, 0.3), _mana_flash)
	_bar(40, 6, "drop", HudStyle.color("mana"), stats.mana / maxf(1.0, float(t.get("maxMana", 50.0))), str(floori(stats.mana)), HudStyle.color("text"), 0.0, back_tint)
	# Hunger and rest.
	if needs != null:
		var low := HudStyle.color("coral")
		var calm := HudStyle.color("muted")
		var meal := UiKit.resource_icon("Meal")
		if meal != null:
			draw_texture_rect(meal, Rect2(Vector2(COL_X, 53) * k, Vector2(14, 14) * k), false)
		_text(str(ceili(needs.hunger)), Vector2(COL_X + 18, 66) * k, 12, "pixel", low if needs.hunger < 20.0 else calm)
		var moon := HudStyle.icon("moon")
		if moon != null:
			draw_texture_rect(moon, Rect2(Vector2(COL_X + 50, 54) * k, Vector2(12, 12) * k), false, HudStyle.color("rest"))
		_text(("Asleep " if needs.sleeping() else "Rest ") + str(ceili(needs.energy)), Vector2(COL_X + 66, 66) * k, 12, "pixel", low if needs.energy < 20.0 else calm)
	# Experience: a thin bar along the card's foot, filling towards the next level.
	var need := maxi(1, stats.xp_to_next())
	var xr := Rect2(Vector2(8, CARD.y - 6) * k, Vector2(CARD.x - 16, 3) * k)
	draw_rect(xr, Color(0, 0, 0, 0.45))
	draw_rect(Rect2(xr.position, Vector2(xr.size.x * clampf(float(stats.xp) / need, 0.0, 1.0), xr.size.y)), HudStyle.color("accent"))
	# The effect tags under the card, and the cooldown rack under them.
	var y := (CARD.y + 6.0) * k
	_tag_rects.clear()
	var tip := {}
	if needs != null:
		var x := 0.0
		for e in needs.effects():
			var c: Color = HudStyle.color("green") if e[1] else HudStyle.color("coral")
			var nm: String = e[0]
			var bf := HudStyle.font("bold")
			var w := (bf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11 * k)).x if bf else 60.0) + 16 * k
			var r := Rect2(Vector2(x, y), Vector2(w, TAG_H * k))
			draw_style_box(HudStyle.piece("panel"), r)
			_text(nm, r.position + Vector2(0, r.size.y * 0.72), 11, "bold", c, w, HORIZONTAL_ALIGNMENT_CENTER)
			if _tag_rects.size() == _hovered:
				tip = {"name": nm, "color": c, "what": e[2] if e.size() > 2 else "", "x": x}
			_tag_rects.append(r)
			x += w + 4 * k
		if not needs.effects().is_empty():
			y += (TAG_H + 6.0) * k
	_rack(y)
	bottom = y + (CHIP + 8.0) * k   # (what's under it starts below the rack's room)
	if not tip.is_empty() and tip.what != "":
		_tip(tip, y)


func _text(s: String, at: Vector2, sz: float, kind: String, c: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := HudStyle.font(kind)
	if f == null:
		f = get_theme_default_font()
	var px := roundi(sz * HudStyle.SCALE)
	draw_string_outline(f, at, s, align, width, px, 3, Color(0, 0, 0, 0.5))
	draw_string(f, at, s, align, width, px, c)


# A bar row: its icon, the track and fill (and an overlay band), and the number at the right.
func _bar(y: float, h: float, icon: String, c: Color, frac: float, value: String, value_c: Color, band := 0.0, back_tint := Color.WHITE) -> void:
	var k := HudStyle.SCALE
	var col_w := CARD.x - COL_X - 8.0
	var tex := HudStyle.icon(icon)
	if tex != null:
		draw_texture_rect(tex, Rect2(Vector2(COL_X, y) * k, Vector2(12, 12) * k), false, c)
	var back := Rect2(Vector2(COL_X + 18, y + (12 - h) / 2.0) * k, Vector2(col_w - 18 - 32, h) * k)
	draw_style_box(HudStyle.piece("barBack", back_tint), back)
	if frac > 0.02:
		draw_style_box(HudStyle.piece("barFill", c), Rect2(back.position, Vector2(back.size.x * clampf(frac, 0.0, 1.0), back.size.y)))
	if band > 0.004:
		draw_style_box(HudStyle.piece("barFill", Color(0.36, 0.62, 0.96, 0.92)), Rect2(back.position, Vector2(back.size.x * clampf(band, 0.0, 1.0), back.size.y)))
	_text(value, Vector2(COL_X + col_w - 30, y + 11) * k, 12, "pixel", value_c, 30 * k, HORIZONTAL_ALIGNMENT_RIGHT)


# The rack of skills cooling down: each skill's icon darkened by a sweep that unwinds as it cools, the seconds left.
func _rack(y: float) -> void:
	if caster == null:
		return
	var k := HudStyle.SCALE
	var cooling := []
	for sp in caster.ready_at:
		var left := caster.cooldown_left(sp)
		if left > 0.0:
			cooling.append([sp, left, caster.cooldown_total(sp)])
	cooling.sort_custom(func(a, b): return a[1] < b[1])
	for i in cooling.size():
		var r := Rect2(Vector2(i * (CHIP + 5) * k, y + 2 * k), Vector2(CHIP, CHIP) * k)
		draw_style_box(HudStyle.piece("panel"), r)
		var held := is_inf(cooling[i][1])
		var icon := UiKit.sprite_texture(int(caster.spells[cooling[i][0]].get("icon", -1)))
		var inner := r.grow(-4 * k)
		if icon != null:
			draw_texture_rect(icon, inner, false, Color(1, 1, 1, 0.55) if held else Color.WHITE)
		var share := 1.0 if held else clampf(cooling[i][1] / maxf(0.01, cooling[i][2]), 0.0, 1.0)
		_sweep(inner.get_center(), inner.size.x * 0.5, share)
		var left: float = cooling[i][1]
		var label := "OUT" if held else (str(ceili(left)) if left >= 10.0 else "%.1f" % left)
		_text(label, r.position + Vector2(0, r.size.y * 0.65), 9.0 if held else 12.0, "pixel", Color.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


# A dark sweep over the share still to cool, from the top, unwinding.
func _sweep(c: Vector2, r: float, share: float) -> void:
	if share <= 0.0:
		return
	var pts := PackedVector2Array([c])
	var n := maxi(3, int(36 * share))
	for i in n + 1:
		var a := -PI / 2.0 - TAU * share * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r * 1.42)
	var clip := PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)])
	for poly in Geometry2D.intersect_polygons(pts, clip):
		draw_colored_polygon(poly, Color(0.05, 0.04, 0.04, 0.62))


# The tip under a hovered tag: its name, then what it does.
func _tip(tip: Dictionary, y: float) -> void:
	var k := HudStyle.SCALE
	var w := 220.0 * k
	var f := HudStyle.font("body")
	var px := roundi(11 * k)
	var lines := f.get_multiline_string_size(tip.what, HORIZONTAL_ALIGNMENT_LEFT, w - 20 * k, px).y if f else 40.0
	var r := Rect2(Vector2(tip.x, y), Vector2(w, 26 * k + lines + 10 * k))
	draw_style_box(HudStyle.piece("panelStrong"), r)
	_text(tip.name, r.position + Vector2(10, 20) * k, 13, "bold", tip.color)
	if f:
		draw_multiline_string(f, r.position + Vector2(10 * k, 26 * k + px), tip.what, HORIZONTAL_ALIGNMENT_LEFT, w - 20 * k, px, -1, HudStyle.color("muted"))
