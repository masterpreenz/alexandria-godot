class_name UiKit
## The game's UI design system (from Unity's UiTheme and UiKit), built once from data/ui.json: the colours, the 9-sliced
## pieces every panel, button and slot is drawn with, the fonts, and the icons for resources, items, seasons and
## weather. Everything in the UI is made from these, so restyling the export restyles it all.

static var data: Dictionary
static var colors := {}
static var theme: Theme
static var title_font: Font
static var body_font: Font
static var _world: World
static var _icons := {}


static func setup(w: World) -> void:
	_world = w
	data = w._load_json("res://data/ui.json")
	var t: Dictionary = data.theme
	for k in t:
		if t[k] is Array and (t[k] as Array).size() == 4:
			colors[k] = Color(t[k][0], t[k][1], t[k][2], t[k][3])
	if t.titleFont != "": title_font = load(t.titleFont)
	if t.bodyFont != "": body_font = load(t.bodyFont)
	theme = Theme.new()
	if body_font != null:
		theme.default_font = body_font
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", colors.text)
	theme.set_color("font_color", "Button", colors.text)
	theme.set_color("font_hover_color", "Button", colors.text)
	theme.set_color("font_pressed_color", "Button", colors.onSelected)
	theme.set_color("font_focus_color", "Button", colors.text)
	theme.set_stylebox("normal", "Button", piece("button"))
	theme.set_stylebox("hover", "Button", piece("button", Color(1.06, 1.04, 1.0)))
	theme.set_stylebox("pressed", "Button", piece("buttonSelected"))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "PanelContainer", piece("frame"))
	theme.set_stylebox("panel", "Panel", piece("frame"))


## A 9-sliced piece of the theme ("frame", "inset", "slot", "button"...), tinted [param tint].
static func piece(name: String, tint := Color.WHITE) -> StyleBox:
	var p: Variant = data.theme.get(name)
	if p == null:
		return StyleBoxEmpty.new()
	var info: Dictionary = _world.sprites[int(p.s)]
	var sb := StyleBoxTexture.new()
	sb.texture = _world._texture(info.tex)
	sb.region_rect = Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
	# Unity's border is left, bottom, right, top.
	var b: Array = p.border
	sb.texture_margin_left = b[0]
	sb.texture_margin_bottom = b[1]
	sb.texture_margin_right = b[2]
	sb.texture_margin_top = b[3]
	sb.content_margin_left = b[0] * 0.6
	sb.content_margin_right = b[2] * 0.6
	sb.content_margin_top = b[3] * 0.6
	sb.content_margin_bottom = b[1] * 0.6
	sb.modulate_color = tint
	return sb


## A sprite from the sprite table as a texture of its own (for TextureRects).
static func sprite_texture(id: int) -> Texture2D:
	if id < 0:
		return null
	if _icons.has(id):
		return _icons[id]
	var info: Dictionary = _world.sprites[id]
	var at := AtlasTexture.new()
	at.atlas = _world._texture(info.tex)
	at.region = Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
	_icons[id] = at
	return at


## A resource's icon.
static func resource_icon(resource: String) -> Texture2D:
	var r: Dictionary = data.resources.get(resource, {})
	var icon: Variant = r.get("icon")
	if icon == null:
		return null
	if icon.has("s"):
		return sprite_texture(int(icon.s))
	var key: String = icon.tex
	if not _icons.has(key):
		_icons[key] = load(key)
	return _icons[key]


## An item's icon: a sprite number, or {"tex": path} / {"s": sprite} as the resources have it; null when it has none.
static func item_icon(nm: String) -> Texture2D:
	return icon_of(item(nm).get("icon", -1))


## An icon as the data gives it: a sprite number, or {"tex": path} / {"s": sprite}; null for none.
static func icon_of(icon: Variant) -> Texture2D:
	if icon is Dictionary:
		if icon.has("s"):
			return sprite_texture(int(icon.s))
		var key: String = icon.get("tex", "")
		if key == "":
			return null
		if not _icons.has(key):
			_icons[key] = load(key)
		return _icons[key]
	return sprite_texture(int(icon))


static func resource_name(resource: String) -> String:
	return data.resources.get(resource, {}).get("name", resource)


static func item(name: String) -> Dictionary:
	return data.items.get(name, {})


## An item without art of its own shows as a tile of its kind's colour with its initials (as Unity did).
static func kind_color(kind: String) -> Color:
	match kind:
		"OneHanded", "TwoHanded": return Color(0.7, 0.35, 0.25)
		"Shield": return Color(0.45, 0.5, 0.6)
		"Armor": return Color(0.3, 0.5, 0.7)
		"Gloves": return Color(0.6, 0.5, 0.3)
		"Pants": return Color(0.35, 0.45, 0.35)
		"Shoes": return Color(0.45, 0.35, 0.25)
		"Necklace": return Color(0.75, 0.65, 0.25)
	return Color(0.65, 0.4, 0.7)


static func initials(name: String) -> String:
	var words := name.split(" ", false)
	if words.size() >= 2:
		return (words[0].left(1) + words[1].left(1)).to_upper()
	return name.left(2)


## A label in the theme: [param title] for headings (the title font, the title colour).
static func label(text: String, size := 18, title := false, color: Variant = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if title and title_font != null:
		l.add_theme_font_override("font", title_font)
	l.add_theme_color_override("font_color", color if color != null else (colors.title if title else colors.text))
	return l
