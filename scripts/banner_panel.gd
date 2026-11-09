class_name BannerPanel
extends PanelContainer
## The town banner's window (from Unity's BannerPanel; E beside the banner): how big the village is, the block of land
## the next growth adds, what it costs against what Miko has (her bag and, in the village, the chests), and a button
## to go and choose where it goes ([VillageGrowth]).

const W := 380.0

var world: World
var miko: Miko
var grow: Callable
var _box: VBoxContainer
var _dirty := false


func setup(w: World, who: Miko, on_grow: Callable) -> void:
	world = w
	miko = who
	grow = on_grow
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	custom_minimum_size.x = W * HudStyle.SCALE
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", int(6 * HudStyle.SCALE))
	add_child(_box)
	w.village.changed.connect(func(): _dirty = true)
	who.bag.changed.connect(func(): _dirty = true)
	visible = false


func open() -> void:
	visible = true
	_build()


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"banner_panel.process", __t)


func _process_timed(_delta: float) -> void:
	if not visible:
		return
	if _dirty:
		_build()
	reset_size()
	position = ((get_viewport_rect().size - size) / 2.0).round() + Vector2(0, 20)


func _build() -> void:
	_dirty = false
	for ch in _box.get_children():
		_box.remove_child(ch)
		ch.queue_free()
	var k := HudStyle.SCALE
	var v := world.village
	var head := HBoxContainer.new()
	head.add_child(HudStyle.label("Town banner", 18, "bold", HudStyle.color("accentLight")))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(HudStyle.label("E / Esc close", 10, "bold", HudStyle.color("faint")))
	_box.add_child(head)
	_box.add_child(HudStyle.label("Village · %d tiles · grown %d of %d times" % [v.area(), v.growths(), v.radii.size() - 1], 12, "bold", HudStyle.color("muted")))
	var nb := v.next_block()
	var about := HudStyle.label("As big as it gets." if v.max_tier() else
		"Next: a %d × %d tile block, added on to whichever side you choose (so none is wasted on water or cliffs)." % [nb.x, nb.y], 12, "body")
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size.x = (W - 36) * k
	_box.add_child(about)
	if not v.max_tier():
		var heads := HBoxContainer.new()
		var h1 := HudStyle.label("TO GROW IT", 10, "bold", HudStyle.color("faint"))
		h1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heads.add_child(h1)
		heads.add_child(HudStyle.label("HAVE / NEED", 10, "bold", HudStyle.color("faint")))
		_box.add_child(heads)
		var can := true
		for c in Village.sum(v.next_upgrade()):
			var have := v.have(miko.bag, miko, c[0])
			var enough: bool = have >= c[1]
			can = can and enough
			var line := PanelContainer.new()
			line.add_theme_stylebox_override("panel", HudStyle.piece("well"))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", int(8 * k))
			var icon := TextureRect.new()
			icon.texture = UiKit.resource_icon(c[0])
			icon.custom_minimum_size = Vector2(18, 18) * k
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon)
			var nm := HudStyle.label(UiKit.resource_name(c[0]), 12, "bold")
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nm)
			row.add_child(HudStyle.label("%d / %d" % [have, c[1]], 12, "bold", HudStyle.color("green") if enough else HudStyle.color("coral")))
			line.add_child(row)
			_box.add_child(line)
		_box.add_child(HudStyle.label("Counts what you carry and what's in the village chests." if v.in_reach(miko) else "Counts what you carry.", 11, "body", HudStyle.color("faint")))
		# Grow it: solid amber when it can be paid for.
		@warning_ignore("incompatible_ternary")
		var b := HudStyle.button("Choose where to grow" if can else "Not enough yet", 13, "barFill" if can else "pill", HudStyle.color("ink") if can else null)
		b.custom_minimum_size.y = 36 * k
		b.disabled = not can
		b.pressed.connect(func(): grow.call())
		_box.add_child(b)
