class_name Perf
extends CanvasLayer
## The performance logger: how long each part of the game takes each frame, and the engine's own figures.
##
## Every script's _process and _physics_process is timed (a wrapper round it, see tools/instrument.py), summed per
## script each frame with how many times it ran (all the villagers' AI together, say). With those go the engine's
## figures: the frame's time, its process and physics time, rendering (CPU and GPU, the main view and the minimap's),
## draw calls, objects drawn, nodes. F3 shows the costliest parts, averaged over half a second; frames much slower
## than the ones before (a spike) are written to user://perf_log.txt with what took the time in them.

const SPIKE_MS := 25.0          ## a frame this slow counts as a spike...
const SPIKE_FACTOR := 1.8       ## ...or this many times the recent average
const SHOWN := 14

static var active: Perf
static var on := true           ## timing (cheap); the overlay is separate
static var _frame := {}         ## name -> [usec, calls] this frame
static var _window := {}        ## name -> [usec, calls, frames] since the overlay last refreshed
static var _worst := {}         ## name -> worst usec in one frame, this run
static var _total := {}         ## name -> [usec, calls] this run

var _label: RichTextLabel
var _panel: PanelContainer
var _avg_ms := 16.0
var _shown_at := 0.0
var _frames := 0
var _frame_ms_sum := 0.0
var _worst_frame := 0.0
var _log: FileAccess
var _spikes := 0
var _all_frames: PackedFloat32Array = PackedFloat32Array()
var _sub_viewports: Array = []
# What the engine runs by itself, outside any script (so no timer sees it): particle effects (fires, chimney smoke,
# sparkles, rain, snow, motes), lights and sounds. Counted as they come and go.
var _particles := {}
var _lights := {}
var _sounds := {}


## Times one call: [code]var t := Time.get_ticks_usec()[/code] ... [code]Perf.add(&"name", t)[/code].
static func add(nm: StringName, since_usec: int) -> void:
	if not on:
		return
	var us := Time.get_ticks_usec() - since_usec
	var e: Variant = _frame.get(nm)
	if e == null:
		_frame[nm] = [us, 1]
	else:
		e[0] += us
		e[1] += 1


func _ready() -> void:
	active = self
	layer = 120
	process_priority = 1000000          # last of all: the frame's work is in by then
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.04, 0.82)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(12, 150)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size.x = 440
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 12)
	_label.add_theme_font_override("normal_font", ThemeDB.fallback_font)
	_panel.add_child(_label)
	_panel.visible = Shots.arg("perf") == "show"
	add_child(_panel)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	get_tree().node_added.connect(_added)
	get_tree().node_removed.connect(_removed)
	for n in get_tree().root.find_children("*", "", true, false):
		_added(n)
	var f := FileAccess.open("user://perf_log.txt", FileAccess.WRITE)
	_log = f
	if _log != null:
		_log.store_line("Alexandria performance log, %s" % Time.get_datetime_string_from_system())


## A SubViewport (the minimap's, the world map's) whose rendering is measured too.
func watch_viewport(vp: SubViewport, nm: String) -> void:
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	_sub_viewports.append([vp, nm])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	_all_frames.append(ms)
	_frames += 1
	_frame_ms_sum += ms
	_worst_frame = maxf(_worst_frame, ms)
	# A spike: logged with what took the time.
	if _all_frames.size() > 30 and (ms > SPIKE_MS or ms > _avg_ms * SPIKE_FACTOR):
		_spike(ms)
	_avg_ms = lerpf(_avg_ms, ms, 0.05)
	for k in _frame:
		var e: Array = _frame[k]
		var w: Variant = _window.get(k)
		if w == null:
			_window[k] = [e[0], e[1], 1]
		else:
			w[0] += e[0]
			w[1] += e[1]
			w[2] += 1
		_worst[k] = maxi(int(_worst.get(k, 0)), int(e[0]))
		var tt: Variant = _total.get(k)
		if tt == null:
			_total[k] = [e[0], e[1]]
		else:
			tt[0] += e[0]
			tt[1] += e[1]
	_frame.clear()
	var t := Time.get_ticks_msec() / 1000.0
	if t - _shown_at >= 0.5:
		if _panel.visible:
			_show(t - _shown_at)
		_shown_at = t
		_window.clear()
		_frames = 0
		_frame_ms_sum = 0.0
		_worst_frame = 0.0


func _added(n: Node) -> void:
	if n is CPUParticles2D or n is GPUParticles2D:
		_particles[n] = true
	elif n is PointLight2D:
		_lights[n] = true
	elif n is AudioStreamPlayer or n is AudioStreamPlayer2D:
		_sounds[n] = true


func _removed(n: Node) -> void:
	_particles.erase(n)
	_lights.erase(n)
	_sounds.erase(n)


# Whose an engine-run thing is: the nearest script above it (fires, roof_map's smoke, crystals...).
static func _owner_of(n: Node) -> String:
	var p := n.get_parent()
	while p != null:
		var s: Script = p.get_script()
		if s != null:
			return s.resource_path.get_file().get_basename()
		p = p.get_parent()
	return "?"


## The engine-run things now: how many particle effects are emitting (and how many particles they hold), by owner;
## lights on; sounds playing.
func engine_things() -> Dictionary:
	var by := {}
	var emitting := 0
	var particles := 0
	for n in _particles:
		if is_instance_valid(n) and n.emitting and n.is_visible_in_tree():
			emitting += 1
			particles += n.amount
			var o := _owner_of(n)
			by[o] = int(by.get(o, 0)) + n.amount
	var lights := 0
	for n in _lights:
		if is_instance_valid(n) and n.enabled and n.is_visible_in_tree():
			lights += 1
	var sounds := 0
	for n in _sounds:
		if is_instance_valid(n) and n.playing:
			sounds += 1
	return {"effects": emitting, "particles": particles, "by": by, "lights": lights, "sounds": sounds}


## This frame's time in scripts (the top-level timers; the finer ones, "AI: ..." and the like, sit inside them).
static func _script_ms(table: Dictionary) -> float:
	var us := 0
	for k in table:
		if not String(k).contains(":"):
			us += int(table[k][0])
	return us / 1000.0


func _engine() -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	var out := {
		"fps": Engine.get_frames_per_second(),
		"process ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"render cpu ms": RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
		"render gpu ms": RenderingServer.viewport_get_measured_render_time_gpu(vp),
		"draw calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"physics bodies": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
	}
	for v in _sub_viewports:
		if is_instance_valid(v[0]):
			var rid: RID = v[0].get_viewport_rid()
			out[v[1] + " render ms"] = RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return out


func _sorted(table: Dictionary, per: float) -> Array:
	var rows := []
	for k in table:
		rows.append([k, table[k][0] / per / 1000.0, table[k][1] / per])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return rows


func _show(_seconds: float) -> void:
	var frames := maxf(1.0, _frames)
	var e := _engine()
	var t := "[b]%d FPS[/b]  ·  frame %.1f ms avg, %.1f worst  ·  F3 hides\n" % [e.fps, _frame_ms_sum / frames, _worst_frame]
	t += "process %.1f ms · physics %.1f ms · render cpu %.1f gpu %.1f ms\n" % [e["process ms"], e["physics ms"], e["render cpu ms"], e["render gpu ms"]]
	t += "draw calls %d · objects %d · nodes %d · bodies %d\n" % [e["draw calls"], e.objects, e.nodes, e["physics bodies"]]
	var th := engine_things()
	var scripts := 0.0
	for k in _window:
		if not String(k).contains(":"):
			scripts += _window[k][0]
	scripts = scripts / frames / 1000.0
	t += "scripts %.1f ms · outside scripts %.1f ms (engine: particles, physics, animation...)
" % [scripts, maxf(0.0, _frame_ms_sum / frames - scripts - e["render cpu ms"])]
	var owners := []
	for o in th.by:
		owners.append([o, th.by[o]])
	owners.sort_custom(func(x, y): return x[1] > y[1])
	t += "effects %d (%d particles: %s) · lights %d · sounds %d
" % [th.effects, th.particles, ", ".join(owners.slice(0, 5).map(func(o): return "%s %d" % o)), th.lights, th.sounds]
	for k in e:
		if k.ends_with(" render ms") and not k.begins_with("render"):
			t += "%s %.2f\n" % [k, e[k]]
	t += "[color=#9c8b72]ms per frame · calls per frame · worst ms[/color]\n"
	var rows := _sorted(_window, frames)
	for i in mini(SHOWN, rows.size()):
		var r: Array = rows[i]
		var c := "#ff8a6a" if r[1] > 2.0 else ("#f2b544" if r[1] > 0.5 else "#e8dcc8")
		t += "[color=%s]%6.2f[/color]  %5.1f  %6.2f  %s\n" % [c, r[1], r[2], int(_worst.get(r[0], 0)) / 1000.0, r[0]]
	_label.text = t


func _spike(ms: float) -> void:
	_spikes += 1
	var e := _engine()
	var rows := _sorted(_frame, 1.0)
	var th := engine_things()
	var sc := _script_ms(_frame)
	var line := "SPIKE %.1f ms (avg %.1f) at %.2fs | scripts %.1f, outside scripts %.1f | process %.1f physics %.1f render cpu %.1f gpu %.1f | draw %d objects %d nodes %d | effects %d (%d particles) lights %d sounds %d | " % [
		ms, _avg_ms, Time.get_ticks_msec() / 1000.0, sc, maxf(0.0, ms - sc - e["render cpu ms"]), e["process ms"], e["physics ms"], e["render cpu ms"], e["render gpu ms"],
		e["draw calls"], e.objects, e.nodes, th.effects, th.particles, th.lights, th.sounds]
	var parts := []
	for i in mini(8, rows.size()):
		parts.append("%s %.2f×%d" % [rows[i][0], rows[i][1], rows[i][2]])
	line += ", ".join(parts)
	if _log != null:
		_log.store_line(line)
		_log.flush()
	if Shots.arg("perf") != "":
		print(line)


## A summary of the run so far (frame times, the costliest parts on average and at worst), printed and logged.
func summary() -> String:
	var ms := Array(_all_frames)
	ms.sort()
	var n := ms.size()
	if n == 0:
		return "No frames"
	var pick := func(q: float) -> float: return ms[clampi(int(q * (n - 1)), 0, n - 1)]
	var s := "Frames %d: median %.1f ms, 95%% %.1f, 99%% %.1f, worst %.1f; spikes %d\n" % [n, pick.call(0.5), pick.call(0.95), pick.call(0.99), ms[n - 1], _spikes]
	var worst := []
	for k in _worst:
		worst.append([k, _worst[k] / 1000.0])
	worst.sort_custom(func(a, b): return a[1] > b[1])
	var avg := _sorted(_total, float(n))
	s += "Average per frame: " + ", ".join(avg.slice(0, 16).map(func(r): return "%s %.2f ms (%.1f calls)" % [r[0], r[1], r[2]])) + "
"
	s += "Worst single frame per part: " + ", ".join(worst.slice(0, 12).map(func(w): return "%s %.1f" % [w[0], w[1]]))
	if _log != null:
		_log.store_line(s)
		_log.flush()
	return s
