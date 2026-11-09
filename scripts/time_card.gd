class_name TimeCard
extends Control
## The top-right card (the lower half of Unity's WorldHud; the minimap above it comes with the maps): the weather's
## icon, the time, and the season and day. Clicking the season and day skips to the next season; clicking the weather
## icon cycles the weather (the season's own, then each kind by hand).

const W := 200.0
const H := 28.0

var world: World
var clock: GameClock
var top := 16.0                    ## how far down, on its own
var holder: Control                ## the minimap it sits inside (top centre), or null
var _weather_rect := Rect2()
var _season_rect := Rect2()


func setup(w: World, c: GameClock) -> void:
	world = w
	clock = c
	size = Vector2(W, H) * HudStyle.SCALE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	if holder != null:
		position = Vector2((holder.size.x - size.x) / 2.0, 10.0 * HudStyle.SCALE)
	else:
		position = Vector2(get_viewport_rect().size.x - size.x - 16.0, top)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _weather_rect.has_point(event.position):
			# The season's own weather, then each kind by hand.
			var next := clock.forced + 1
			clock.set_weather(next if next < GameClock.WEATHER_NAMES.size() else -1)
			accept_event()
		elif _season_rect.has_point(event.position):
			# On to the first day of the next season.
			var days := clock.days_per_season
			var day := clock.day() - 1
			clock.hours = float((day / days + 1) * days) * 24.0 + clock.hour()
			accept_event()


func _draw() -> void:
	var k := HudStyle.SCALE
	draw_style_box(HudStyle.piece("pillPlain", Color(1, 1, 1, 0.92)), Rect2(Vector2.ZERO, size))
	var icons: Array = UiKit.data.theme.get("weatherIcons", [])
	var wx := clock.weather()
	_weather_rect = Rect2(Vector2(9, 5) * k, Vector2(18, 18) * k)
	if wx < icons.size() and int(icons[wx]) >= 0:
		draw_texture_rect(UiKit.sprite_texture(int(icons[wx])), _weather_rect, false)
	var f := HudStyle.font("pixel")
	var b := HudStyle.font("bold")
	draw_string(f, Vector2(32, 19) * k, clock.time_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12 * k), HudStyle.color("text"))
	var season := "%s, day %d" % [GameClock.SEASON_NAMES[clock.season()], clock.day_of_season()]
	var px := roundi(10 * k)
	var sw := b.get_string_size(season, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_season_rect = Rect2(Vector2(size.x - sw - 12 * k, 0), Vector2(sw + 12 * k, size.y))
	draw_string(b, Vector2(size.x - sw - 11 * k, 18.5 * k), season, HORIZONTAL_ALIGNMENT_LEFT, -1, px, HudStyle.color("accentLight"))
