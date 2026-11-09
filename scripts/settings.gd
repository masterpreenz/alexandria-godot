class_name Settings
## The player's settings (kept in user://settings.cfg, across games): the window's resolution, windowed or borderless
## fullscreen, the UI's size, and whether the FPS meter shows. Applied at start and whenever they change (the UI's size
## once the game starts again).

const FILE := "user://settings.cfg"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const UI_SIZES := [0.8, 0.9, 1.0, 1.1, 1.2, 1.3]

static var resolution := Vector2i(1600, 900)
static var borderless := false
static var ui_size := 1.0
static var show_fps := true
static var master := 1.0
static var sfx := 1.0
static var bgm := 0.8
static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(FILE) != OK:
		return
	resolution = cfg.get_value("display", "resolution", resolution)
	borderless = bool(cfg.get_value("display", "borderless", borderless))
	ui_size = float(cfg.get_value("display", "ui_size", ui_size))
	show_fps = bool(cfg.get_value("display", "show_fps", show_fps))
	master = float(cfg.get_value("sound", "master", master))
	sfx = float(cfg.get_value("sound", "sfx", sfx))
	bgm = float(cfg.get_value("sound", "bgm", bgm))


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "resolution", resolution)
	cfg.set_value("display", "borderless", borderless)
	cfg.set_value("display", "ui_size", ui_size)
	cfg.set_value("display", "show_fps", show_fps)
	cfg.set_value("sound", "master", master)
	cfg.set_value("sound", "sfx", sfx)
	cfg.set_value("sound", "bgm", bgm)
	cfg.save(FILE)


## The window as set: borderless fullscreen over the whole screen, or a window of the chosen size, centred.
static func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if borderless:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := Vector2i(mini(resolution.x, screen.size.x), mini(resolution.y, screen.size.y))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


## The resolutions that fit the screen (and the one set, if it doesn't).
static func resolutions() -> Array:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var out := []
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y:
			out.append(r)
	if not out.has(resolution):
		out.append(resolution)
	return out


# ---- Sound: three buses, SFX and BGM feeding Master ----

## A volume by name ("master", "sfx" or "bgm"), 0 to 1.
static func volume(which: String) -> float:
	match which:
		"master": return master
		"sfx": return sfx
	return bgm


static func set_volume(which: String, v: float) -> void:
	match which:
		"master": master = v
		"sfx": sfx = v
		_: bgm = v
	apply_sound()
	save_settings()

## Makes the SFX and BGM buses (once) and sets every bus's volume.
static func apply_sound() -> void:
	for name in ["SFX", "BGM"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, name)
			AudioServer.set_bus_send(i, "Master")
	_volume("Master", master)
	_volume("SFX", sfx)
	_volume("BGM", bgm)


static func _volume(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


## Every sound player put in the game plays through the SFX bus (music goes on BGM by setting its bus itself).
static func route_sounds(tree: SceneTree) -> void:
	if tree.node_added.is_connected(_on_node_added):
		return
	tree.node_added.connect(_on_node_added)


static func _on_node_added(n: Node) -> void:
	if n is AudioStreamPlayer or n is AudioStreamPlayer2D:
		if n.bus == &"Master":
			n.bus = &"SFX"
