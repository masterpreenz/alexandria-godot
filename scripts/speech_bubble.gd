class_name SpeechBubble
extends Control
## A comic bubble over someone's head with a few words in it, from the bubble art (assets/Art/UI/Bubbles): SAY a plain
## rounded bubble with a tail, FANCY a gold-framed one (something special), THINK a cloud trailing little puffs
## (thinking out loud: hungry, tired), SHOUT a spiky burst (urgent: a fight, no food), ALARM a red spiky burst (danger:
## hurt, a raid, starving), which shakes a little. The art is stretched across its middle to fit the words (its sides,
## with the tail or puffs, kept as drawn). Its tail's tip sits where it's placed, over the head. Bright whatever the
## hour.

enum Kind { SAY, THINK, SHOUT, FANCY, ALARM }

const INK := Color(0.16, 0.12, 0.1)
## Each look: its art; the left and right parts kept as drawn (px of the art); how tall it's drawn (times the words'
## size); room beside the words (px, drawn); where the words sit down it (share of its height); where the tail's tip
## is across the art (share of its width, measured from the left part; past 1: in the right part).
const LOOKS := {
	Kind.SAY: {"art": "say", "left": 140, "right": 44, "tall": 3.4, "pad": 34, "y": 0.4, "tip": 0.44, "ink": [0.16, 0.12, 0.1]},
	Kind.FANCY: {"art": "fancy", "left": 150, "right": 52, "tall": 3.6, "pad": 44, "y": 0.4, "tip": 0.46, "ink": [0.16, 0.12, 0.1]},
	Kind.THINK: {"art": "think", "left": 60, "right": 96, "tall": 3.6, "pad": 34, "y": 0.42, "tip": 0.93, "ink": [0.16, 0.12, 0.1]},
	Kind.SHOUT: {"art": "shout", "left": 96, "right": 96, "tall": 4.2, "pad": 52, "y": 0.52, "tip": 0.5, "ink": [0.45, 0.1, 0.06]},
	Kind.ALARM: {"art": "alarm", "left": 104, "right": 104, "tall": 4.4, "pad": 56, "y": 0.52, "tip": 0.5, "ink": [0.78, 0.12, 0.08]},
}

static var _arts := {}
static var _font: Font
const FONT := "res://assets/Fonts/ComicNeue-Bold.ttf"   ## comic lettering (OFL), in capitals, as manga's


## The bubbles' lettering font.
static func letters() -> Font:
	if _font == null:
		_font = load(FONT) if ResourceLoader.exists(FONT) else HudStyle.font("bold")
	return _font

var kind := Kind.SAY
var text := ""
var font_size := 15
var _look: Dictionary = {}
var _tex: Texture2D
var _k := 1.0                    ## how much the art is scaled
var _w := 0.0                    ## the width it's drawn
var _born := 0.0
var _lines: Array = []           ## the words broken into lines that fit
const WRAP := 150.0              ## widest a line goes (px, at its size) before the words go on to the next
const LINE := 1.15               ## a line's height (times the words' size)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_as_relative = false
	z_index = 3999
	World.keep_lit(self)


static func _art(look: String) -> Texture2D:
	if not _arts.has(look):
		_arts[look] = load("res://assets/Art/UI/Bubbles/bubble_%s.png" % look)
	return _arts[look]


# The cloud and the bursts are scaled as a whole to fit the words (stretching them would flatten their puffs and
# spikes); the plain bubbles stretch across their middle.
func _stretches() -> bool:
	return kind == Kind.SAY or kind == Kind.FANCY


## Shows [param words] as [param how] (Kind).
func say(words: String, how: int) -> void:
	text = words.to_upper()   # (lettered in capitals, as a comic's)
	kind = how as Kind
	_look = LOOKS[kind]
	_tex = _art(_look.art)
	var art := _tex.get_size()
	_k = font_size * float(_look.tall) / art.y
	var f := letters()
	_lines = _wrap(f, text)
	var tw := 0.0
	for ln in _lines:
		tw = maxf(tw, f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if f else 80.0)
	# (more than a line: the bubble that much taller to hold them)
	var extra := (_lines.size() - 1) * font_size * LINE
	_k = maxf(_k, (font_size * float(_look.tall) + extra * 1.6) / art.y)
	if _stretches():
		_w = maxf(art.x * _k, tw + float(_look.pad) * 2.0)
	else:
		# The words fill about the middle share of it.
		_k = maxf(_k, (tw + float(_look.pad) * 2.0) / art.x)
		_w = art.x * _k
	size = Vector2(_w, art.y * _k)
	_born = Time.get_ticks_msec() / 1000.0
	queue_redraw()


# [param words] broken into lines no wider than [constant WRAP] (a word too long on its own has a line to itself).
func _wrap(f: Font, words: String) -> Array:
	if f == null:
		return [words]
	var out := []
	var cur := ""
	for w in words.split(" ", false):
		var tried := w if cur == "" else cur + " " + w
		if cur != "" and f.get_string_size(tried, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > WRAP:
			out.append(cur)
			cur = w
		else:
			cur = tried
	if cur != "":
		out.append(cur)
	return out if not out.is_empty() else [words]


## Where the tail's tip goes (over the head), in its parent's space.
func place(at: Vector2) -> void:
	position = (at - Vector2(_tip_x(), size.y)).round()


# The tail's tip across the drawn bubble: in the left part, the right part, or the middle (no tail: spiky).
func _tip_x() -> float:
	if _look.is_empty():
		return size.x / 2.0
	var t := float(_look.tip)
	var art_w := _tex.get_size().x
	if kind == Kind.SHOUT or kind == Kind.ALARM:
		return _w / 2.0
	if not _stretches():
		return t * art_w * _k
	if t * art_w <= float(_look.left):
		return t * art_w * _k
	# In the right part: measured from the art's right edge.
	return _w - (art_w - t * art_w) * _k


func _process(_delta: float) -> void:
	if visible and kind == Kind.ALARM:
		queue_redraw()   # it shakes


func _draw() -> void:
	if _tex == null:
		return
	var shake := Vector2.ZERO
	if kind == Kind.ALARM:
		var t := Time.get_ticks_msec() / 1000.0 - _born
		shake = Vector2(sin(t * 47.0), cos(t * 39.0)) * 1.5 * clampf(1.0 - t / 1.2, 0.3, 1.0)
	var art := _tex.get_size()
	var l := float(_look.left)
	var r := float(_look.right)
	var h := art.y * _k
	if not _stretches():
		draw_texture_rect(_tex, Rect2(shake, Vector2(_w, h)), false)
	else:
		_draw_stretched(shake, art, l, r, h)
	var f := letters()
	if f != null:
		var ink: Array = _look.ink
		var cx := _w / 2.0 - (_w * 0.06 if kind == Kind.THINK else 0.0)   # (the cloud's body, not its puffs)
		var step := font_size * LINE
		var top := h * float(_look.y) + font_size * 0.36 - (_lines.size() - 1) * step / 2.0
		for i in _lines.size():
			var at := shake + Vector2(cx - _w / 2.0, top + i * step)
			draw_string(f, at, _lines[i], HORIZONTAL_ALIGNMENT_CENTER, _w, font_size, Color(ink[0], ink[1], ink[2]))


# Left part and right part as drawn; the middle stretched between them.
func _draw_stretched(shake: Vector2, art: Vector2, l: float, r: float, h: float) -> void:
	draw_texture_rect_region(_tex, Rect2(shake, Vector2(l * _k, h)), Rect2(0, 0, l, art.y))
	draw_texture_rect_region(_tex, Rect2(shake + Vector2(l * _k, 0), Vector2(_w - (l + r) * _k, h)), Rect2(l, 0, art.x - l - r, art.y))
	draw_texture_rect_region(_tex, Rect2(shake + Vector2(_w - r * _k, 0), Vector2(r * _k, h)), Rect2(art.x - r, 0, r, art.y))
