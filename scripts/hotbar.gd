class_name Hotbar
extends PanelContainer
## The hotbar at the bottom of the screen (from Unity's Hotbar): eight slots on keys 1-8 (more rows on Shift and Ctrl
## come with the picker). A slot holds a skill (it aims, or casts on oneself) or something to eat or drink (pressing it
## eats one; the slot shows how many are carried). Skill slots show their mana cost, darken with a sweep while cooling
## down and grey out without enough mana; the one being aimed rings in the accent. What's in each slot comes from the
## save. (Choosing what goes in a slot, the picker, comes with the character panel.)

const CELL := 50.0
const COLUMNS := 8

var world: World
var caster: SpellCaster
var bag: Bag
var stats: CharacterStats
var slots: Array = []    ## "spell:Name", "food:Resource" or ""
var rows := 1
var _cells: Array[HotCell] = []


func setup(w: World, c: SpellCaster, b: Bag, st: CharacterStats) -> void:
	world = w
	caster = c
	bag = b
	stats = st
	add_theme_stylebox_override("panel", UiKit.piece("frameDark"))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 4)
	add_child(grid)
	for i in COLUMNS:
		var cell := HotCell.new()
		cell.bar = self
		cell.index = i
		cell.custom_minimum_size = Vector2(CELL, CELL)
		grid.add_child(cell)
		_cells.append(cell)
	slots.resize(COLUMNS * 3)
	slots.fill("")


## The saved bar (Unity's player.hotbar: rows, and each slot's contents).
func from_json(json: String) -> void:
	var d: Dictionary = JSON.parse_string(json)
	rows = int(d.get("rows", 1))
	var saved: Array = d.get("slots", [])
	for i in mini(saved.size(), slots.size()):
		slots[i] = saved[i] if saved[i] != null else ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not event.shift_pressed and not event.ctrl_pressed:
		var k: int = event.keycode - KEY_1
		if k >= 0 and k < COLUMNS:
			use(k)
			get_viewport().set_input_as_handled()


## Pressing slot [param i]: aims (or casts) its skill, or eats one of its food.
func use(i: int) -> void:
	var s: String = slots[i]
	if s.begins_with("spell:"):
		var spell := s.substr(6)
		if stats.known_spells().has(spell):
			caster.toggle_aiming(spell)
	elif s.begins_with("food:"):
		var r := s.substr(5)
		var needs: Needs = world.player.get_node_or_null("Needs")
		if needs != null:
			needs.eat(r)
		elif bag.spend(r, 1):
			FloatingText.spawn(world, "Ate %s" % UiKit.resource_name(r), world.player.position + Vector2(0, -1.6 * world.px), UiKit.colors.worldText)


func _process(_delta: float) -> void:
	for c in _cells:
		c.queue_redraw()


## One slot: its icon, key, mana cost or count, cooldown sweep, and the aiming ring.
class HotCell extends Control:
	var bar: Hotbar
	var index := 0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			bar.use(index)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiKit.piece("slot"), r)
		var f: Font = UiKit.body_font if UiKit.body_font else get_theme_default_font()
		var s: String = bar.slots[index]
		var inner := r.grow(-7)
		if s.begins_with("spell:"):
			var name := s.substr(6)
			var spell: Dictionary = bar.caster.spells.get(name, {})
			var known := bar.stats.known_spells().has(name)
			var icon := UiKit.sprite_texture(int(spell.get("icon", -1)))
			var dim := not known or bar.stats.mana + 0.001 < float(spell.get("manaCost", 0.0))
			if icon != null:
				draw_texture_rect(icon, inner, false, Color(0.45, 0.45, 0.5) if dim else Color.WHITE)
			# The cooldown: a dark sweep shrinking as it comes back.
			var left := bar.caster.cooldown_left(name)
			if is_inf(left):
				# Out summoned: its cooldown starts once the summon is gone.
				draw_rect(inner, Color(0, 0, 0, 0.55))
			elif left > 0.0:
				var share := left / maxf(0.01, bar.caster.cooldown_total(name))
				draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * share)), Color(0, 0, 0, 0.55))
				draw_string_outline(f, Vector2(0, size.y * 0.62), "%d" % ceili(left), HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, 4, Color(0, 0, 0, 0.8))
				draw_string(f, Vector2(0, size.y * 0.62), "%d" % ceili(left), HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color.WHITE)
			# Its mana cost, bottom right.
			var cost := str(int(spell.get("manaCost", 0)))
			draw_string_outline(f, Vector2(0, size.y - 4), cost, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 13, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(0, size.y - 4), cost, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 13, Color(0.6, 0.78, 1.0))
			if bar.caster.aiming == name:
				draw_rect(r.grow(-1), UiKit.colors.gold, false, 3.0)
		elif s.begins_with("food:"):
			var res := s.substr(5)
			var icon := UiKit.resource_icon(res)
			var n := bar.bag.count(res)
			if icon != null:
				draw_texture_rect(icon, inner, false, Color.WHITE if n > 0 else Color(0.45, 0.45, 0.5))
			draw_string_outline(f, Vector2(0, size.y - 4), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 14, 4, Color(0, 0, 0, 0.8))
			draw_string(f, Vector2(0, size.y - 4), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 14, Color.WHITE)
		# Its key, top left.
		draw_string_outline(f, Vector2(4, 15), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.8))
		draw_string(f, Vector2(4, 15), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.85))
