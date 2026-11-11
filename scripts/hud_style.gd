class_name HudStyle
## The HUD's look (from Unity's HudStyle): its dark-ink pieces (panels, slots, pills, bars, badges, the portrait's
## frame), its icons (heart, drop, moon, sun, ...), its colours and its three fonts (pixel, body, bold), from
## data/hud.json. Sizes are Unity's HUD units times [member SCALE] (the player's UI size, Settings).

static var SCALE := 1.0

static var data: Dictionary = {}
static var _world: World
static var _fonts := {}


static func setup(w: World) -> void:
	_world = w
	Settings.load_settings()
	SCALE = Settings.ui_size
	if FileAccess.file_exists("res://data/hud.json"):
		data = w._load_json("res://data/hud.json")


static func style() -> Dictionary:
	return data.get("style", {})


## A colour of the HUD's (text, muted, faint, accent, accentLight, coral, green, hp, mana, rest, ink).
## Whether something's being typed (a search box, the rumor notes): the keys are the text's, not the game's.
static func typing(viewport: Viewport) -> bool:
	var focus := viewport.gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


## Which way a key press steps through a window's tabs: -1 for Q (the one before), 1 for E (the next), 0 for anything
## else, or while something's being typed. The same in every window with tabs.
static func tab_step(event: InputEvent, viewport: Viewport) -> int:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return 0
	var focus := viewport.gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return 0
	if event.keycode == KEY_Q: return -1
	if event.keycode == KEY_E: return 1
	return 0


static func color(name: String, fallback := Color.WHITE) -> Color:
	var c: Variant = style().get(name)
	return Color(c[0], c[1], c[2], c[3]) if c is Array else fallback


## A sprite id of the HUD's (an icon or a piece), or -1.
static func sprite(name: String) -> int:
	var v: Variant = style().get(name)
	return int(v) if v != null and not v is String and not v is Array else -1


static func icon(name: String) -> Texture2D:
	return UiKit.sprite_texture(sprite(name))


## A 9-sliced piece (panel, panelStrong, slot, slotOn, tile, pill, well, barBack, barFill, badge, portraitFrame...).
static func piece(name: String, tint := Color.WHITE) -> StyleBox:
	var id := sprite(name)
	if id < 0 or _world == null:
		return StyleBoxEmpty.new()
	var info: Dictionary = _world.sprites[id]
	var sb := HudPiece.new()
	sb.texture = _world._texture(info.tex)
	sb.region = Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
	# Unity's border is left, bottom, right, top (in the sprite's pixels).
	var b: Array = data.get("borders", {}).get(str(id), [0, 0, 0, 0])
	sb.left = b[0]
	sb.bottom = b[1]
	sb.right = b[2]
	sb.top = b[3]
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.tint = tint
	return sb


## One of its fonts: "pixel", "body" or "bold".
static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path: Variant = style().get(kind)
	var f: Font = load(path) if path is String and ResourceLoader.exists(path) else null
	_fonts[kind] = f
	return f


## A label in the HUD's look: [param size] in Unity's HUD points, in [param kind]'s font, outlined lightly.
static func label(text: String, size: float, kind := "body", c: Variant = null) -> Label:
	var l := Label.new()
	l.text = text
	var f := font(kind)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", roundi(size * SCALE))
	l.add_theme_color_override("font_color", c if c is Color else color("text"))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A button in the HUD's look: [param piece_name]'s piece (lighter when hovered, dimmed when disabled), its text in
## the bold font.
static func button(text: String, size: float = 12.0, piece_name := "pill", text_c: Variant = null) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", piece(piece_name))
	b.add_theme_stylebox_override("hover", piece(piece_name, Color(1.15, 1.12, 1.05)))
	b.add_theme_stylebox_override("pressed", piece(piece_name, Color(0.85, 0.85, 0.85)))
	b.add_theme_stylebox_override("disabled", piece(piece_name, Color(1, 1, 1, 0.4)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var f := font("bold")
	if f != null:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", roundi(size * SCALE))
	var c: Color = text_c if text_c is Color else color("text")
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, c)
	b.add_theme_color_override("font_disabled_color", color("faint", Color(1, 1, 1, 0.4)))
	return b
