class_name VillageLog
extends PanelContainer
## The village's messages (from Unity's VillageLog): a short list in the bottom left of the screen of what needs seeing
## to. Ongoing problems ([method problem]: no food in storage, no seed to plant, someone without a home) are raised
## again by whoever notices, every so often while they last, and fade a while after; events ([method event]: the
## village under attack, someone hurt, food spoiled) show for a little while. Danger shows red, warnings amber, news
## plain.

enum Kind { NEWS, WARNING, DANGER }

const PROBLEM_LASTS := 12.0
const EVENT_LASTS := 20.0
const MOST_SHOWN := 6
const WIDTH := 290.0

static var _entries := {}          ## key -> {text, kind, until}
static var _order: Array = []      ## newest first
static var _dirty := true

var _list: VBoxContainer
var _next_sweep := 0.0


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Raises (or keeps up) an ongoing problem under [param key]; it fades a while after it's no longer raised.
static func problem(key: String, text: String, kind := Kind.WARNING) -> void:
	_put(key, text, kind, PROBLEM_LASTS)


## Something that just happened (shown for a little while); the same key again just refreshes it.
static func event(key: String, text: String, kind := Kind.NEWS) -> void:
	_put(key, text, kind, EVENT_LASTS)


static func clear(key: String) -> void:
	if _entries.erase(key):
		_order.erase(key)
		_dirty = true


static func _put(key: String, text: String, kind: int, lasts: float) -> void:
	if _entries.has(key):
		var e: Dictionary = _entries[key]
		if e.text != text or e.kind != kind:
			_dirty = true
		e.text = text
		e.kind = kind
		e.until = _now() + lasts
		return
	_entries[key] = {"text": text, "kind": kind, "until": _now() + lasts}
	_order.push_front(key)
	_dirty = true


## What's listed now, newest first.
static func lines() -> Array:
	return _order.map(func(k): return _entries[k].text)


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.piece("frameDark"))
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	add_child(_list)
	visible = false


func _process(_delta: float) -> void:
	if _now() >= _next_sweep:
		_next_sweep = _now() + 0.5
		for k in _order.duplicate():
			if _entries[k].until < _now():
				_entries.erase(k)
				_order.erase(k)
				_dirty = true
	if not _dirty:
		return
	_dirty = false
	for c in _list.get_children():
		c.queue_free()
	visible = not _order.is_empty()
	if not visible:
		return
	var title := Label.new()
	title.text = "VILLAGE"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UiKit.colors.get("muted", Color(0.7, 0.65, 0.6)))
	_list.add_child(title)
	for i in mini(MOST_SHOWN, _order.size()):
		var e: Dictionary = _entries[_order[i]]
		var l := Label.new()
		l.text = "• " + e.text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(WIDTH - 24, 0)
		l.add_theme_font_size_override("font_size", 14)
		var c: Color = UiKit.colors.get("onDark", Color(0.95, 0.92, 0.85))
		if e.kind == Kind.DANGER: c = UiKit.colors.get("hp", Color(0.9, 0.3, 0.25))
		elif e.kind == Kind.WARNING: c = UiKit.colors.get("gold", Color(0.95, 0.75, 0.3))
		l.add_theme_color_override("font_color", c)
		if UiKit.body_font:
			l.add_theme_font_override("font", UiKit.body_font)
		_list.add_child(l)
	if _order.size() > MOST_SHOWN:
		var more := Label.new()
		more.text = "+%d more" % (_order.size() - MOST_SHOWN)
		more.add_theme_font_size_override("font_size", 12)
		_list.add_child(more)
	reset_size()
	_place.call_deferred()


# Bottom left, growing upwards as lines come.
func _place() -> void:
	await get_tree().process_frame  # once the wrapped lines know their height
	reset_size()
	position = Vector2(12.0, get_viewport_rect().size.y - size.y - 12.0)
