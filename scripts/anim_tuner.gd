class_name AnimTuner
extends PanelContainer
## The animation tuner (F4, dev builds only, as the place editor is): a character look picked (the villagers' looks in
## data/villagers.json, labelled by who wears them, or Sera as the player), one of its animations and which way they
## face, and it plays there in a large preview at the game's own size, frame by frame if wanted, sliding over the
## ground at the look's real walking pace for a walk or a run, with the look's standing frame (and Sera) beside it on
## a baseline so a sheet drawn too big or too small shows at once. Beside the preview the animation's pace (walkCycle,
## walkSpeed, its fps, the frames where a blow lands) and the size of its frames (scale and a pivot nudge): every
## change is seen at once on everyone in the world wearing that look, the played body too. Save writes them back
## (the look's own line in villagers.json, or player.json; the frames' lines in sprites.json, and data/art_tune.json
## so a re-import keeps the size); Revert puts back what was loaded. Esc or F4 closes it.

const VILLAGERS := "res://data/villagers.json"
const PLAYER := "res://data/player.json"
const SPRITES := "res://data/sprites.json"
const ART_TUNE := "res://data/art_tune.json"
## The paces a villager look's line may be saved with.
const LOOK_KEYS := ["walkCycle", "walkFps", "walkFpsUp", "walkSpeed", "idleFps", "chopFps", "chopStrikesDown",
	"chopStrikesUp", "mineFps", "mineStrikesDown", "mineStrikesUp", "cookFps", "lieDownFrames", "lieDownFps",
	"asleepFps", "faintFps", "stabFps", "stabStrikes"]
const PLAYER_KEYS := ["walkSpeed", "runSpeed", "idleFps", "walkFps", "runFps", "attackFps"]
const LOOK_ANIMS := ["walk", "idle", "chop", "mine", "cook", "fish", "sleep", "faint", "stab"]
const PLAYER_ANIMS := ["run", "walk", "idle", "attack", "cast", "fish"]
const PREVIEW := Vector2(600, 430)

static var active: AnimTuner

var world: World
var miko: Miko
var people: Villagers
var look := 5                     ## the look tuned: a villagers.json look, or -1 for Sera (player.json)
var anim := "walk"
var facing_up := false
var mirrored := false
var moving := true                ## a walk or a run slides over the ground at its real pace
var big := false                  ## the preview drawn twice the game's size
var with_sera := false            ## Sera's standing frame beside, for size
var mark := true                  ## everyone wearing the look marked in the world
var playing := true
var clock := 0.0                  ## the animation's time in the preview
var travelled := 0.0              ## how far the figure has slid, in screen px
var held := -1                    ## the frame shown while paused and stepped (-1: by the clock)
var said := ""                    ## the last thing Save or Revert said
var _loaded := {}                 ## look (or -1) -> {key: value as loaded, or null when it had none}
var _tokens := {}                 ## look (or -1) -> {key: its text in the file as loaded}
var _base := {}                   ## sprite id -> {ppu, pivot}: as imported, before any size tune
var _orig := {}                   ## sprite id -> {ppu, pivot, line}: as loaded
var _tune := {}                   ## sprite name -> {scale, nudge}: data/art_tune.json
var _bounds := {}                 ## sprite id -> its drawn part's rectangle in the sheet
var _view: Preview
var _marks: Marks
var _top: VBoxContainer
var _controls: VBoxContainer
var _frame_label: Label
var _info: Label
var _said: Label
var _play: Button


func setup(w: World, m: Miko, vs: Villagers) -> void:
	world = w
	miko = m
	people = vs
	active = self
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 2   # (over the world prompts' key rings)
	visible = false
	if FileAccess.file_exists(ART_TUNE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ART_TUNE))
		if d is Dictionary:
			_tune = (d as Dictionary).get("sprites", {})


func _k(v: float) -> float:
	return v * HudStyle.SCALE


static func allowed() -> bool:
	return OS.is_debug_build()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	held = -1
	playing = true
	_build()
	move_to_front()


func close() -> void:
	visible = false
	if get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_get_focus_owner().release_focus()
	if _marks != null:
		_marks.queue_free()
		_marks = null


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	# (plain F4 only: Alt+F4 still closes the game's window)
	if k.keycode == KEY_F4 and not (k.alt_pressed or k.ctrl_pressed or k.shift_pressed or k.meta_pressed) and allowed():
		toggle()
		get_viewport().set_input_as_handled()
		return
	if visible and k.keycode == KEY_ESCAPE:
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null:
			focus.release_focus()
		else:
			close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"anim_tuner.process", __t)


func _process_timed(delta: float) -> void:
	if not visible:
		return
	position = Vector2(_k(16), _k(70))
	if playing:
		clock += delta
		travelled += delta * _speed_px()
	var frames := frames_now()
	var i := frame_index()
	var strike := strikes().has(i)
	_frame_label.text = "Frame %d / %d%s" % [i + 1, frames.size(), "   STRIKE" if strike else ""] if not frames.is_empty() else "No frames"
	_frame_label.add_theme_color_override("font_color", HudStyle.color("coral") if strike else HudStyle.color("text"))
	_view.queue_redraw()
	if mark and _marks == null:
		_marks = Marks.new()
		_marks.tuner = self
		_marks.z_index = 4000
		_marks.visibility_layer |= LightMap.UNLIT_LAYER
		world.add_child(_marks)
	elif not mark and _marks != null:
		_marks.queue_free()
		_marks = null
	if _marks != null:
		_marks.queue_redraw()


# ---- What's tuned ----

## The settings being tuned: the look's in villagers.json (the very ones its wearers read), or player.json's.
func settings() -> Dictionary:
	if look < 0:
		return Playable.active._lead_data if Playable.active != null else miko.data
	return people.d.looks[look].settings


func anims() -> Array:
	var out := []
	for a in (PLAYER_ANIMS if look < 0 else LOOK_ANIMS):
		if not _frames_of(str(a), false).is_empty() or not _frames_of(str(a), true).is_empty():
			out.append(a)
	return out


## The frames of the animation as it's shown now (its facing, mirrored or not).
func frames_now() -> Array:
	return _frames_of(anim, facing_up)


func _frames_of(a: String, up: bool) -> Array:
	var s := settings()
	if look < 0:
		var f: Dictionary = s.get("frames", {})
		match a:
			"run", "walk":
				var right: Array = f.get("runUpRight" if up else "runDownRight", [])
				return right if mirrored and not right.is_empty() else f.get("runUpLeft" if up else "runDownLeft", [])
			"idle": return f.get("idleUpLeft" if up else "idleDownLeft", [])
			"attack": return f.get("attackUpLeft" if up else "attackDownLeft", [])
			"cast": return f.get("castUpLeft" if up else "castDownLeft", [])
			"fish": return s.get("fishing", {}).get("up" if up else "down", [])
		return []
	if a == "idle":
		var own: Array = s.get("idleUpAnim" if up else "idleDownAnim", [])
		return own if not own.is_empty() else [int(s.idleUp if up else s.idleDown)]
	var down: Array = s.get(a + "Down", [])
	var upward: Array = s.get(a + "Up", [])
	return upward if up and not upward.is_empty() else down


## Whether it's drawn turned about (east): a villager always; Sera only where she's no east-facing frames of her own.
func flipped() -> bool:
	if not mirrored:
		return false
	if look < 0 and (anim == "run" or anim == "walk"):
		var f: Dictionary = settings().get("frames", {})
		return (f.get("runUpRight" if facing_up else "runDownRight", []) as Array).is_empty()
	return true


## Frames a second, as the game plays it (for a villager's walk: as Villager._walk_fps works it out).
func fps() -> float:
	var s := settings()
	if look < 0:
		var up_pace := float(s.get("upPace", 1.0)) if facing_up else 1.0
		match anim:
			"run": return float(s.get("runFps", 12)) * up_pace
			"walk": return float(s.get("walkFps", 8)) * up_pace
			"idle": return float(s.get("idleFps", 4))
			"attack": return float(s.get("attackFps", 16))
			"fish": return Fishing.CAST_FPS
		return 1.0
	match anim:
		"walk":
			if s.has("walkCycle"):
				return frames_now().size() / maxf(0.05, float(s.walkCycle))
			return float(s.walkFpsUp) if facing_up and s.has("walkFpsUp") else float(s.walkFps)
		"idle": return float(s.get("idleFps", 6))
		"sleep": return float(s.get("lieDownFps", 9))
		"fish": return Fishing.CAST_FPS
	return float(s.get(anim + "Fps", 8))


## Which setting holds the frames where a blow lands, for this animation and facing ("" for none).
func strike_key() -> String:
	if look < 0:
		return ""
	var s := settings()
	match anim:
		"chop", "mine":
			var upward := facing_up and not (s.get(anim + "Up", []) as Array).is_empty()
			return anim + ("StrikesUp" if upward else "StrikesDown")
		"stab": return "stabStrikes"
	return ""


func strikes() -> Array:
	var k := strike_key()
	if k == "":
		return []
	# (whole numbers: as loaded from the file they're fractional)
	return (settings().get(k, []) as Array).map(func(x): return int(x))


## The frame shown now: stepped to by hand, or by the clock as the game would play it.
func frame_index() -> int:
	var n := frames_now().size()
	if n == 0:
		return 0
	if held >= 0:
		return held % n
	return index_at(clock, n)


func index_at(t: float, n: int) -> int:
	var s := settings()
	if anim == "sleep" and look >= 0:
		# Lying down, then breathing asleep a few times round, then again from the start.
		var lie := int(s.lieDownFrames)
		var lie_time := lie / maxf(0.01, float(s.lieDownFps))
		var asleep := maxf(0.01, float(s.asleepFps))
		t = fmod(t, lie_time + 3.0 * maxi(1, n - lie) / asleep)
		if t < lie_time:
			return mini(int(t * float(s.lieDownFps)), n - 1)
		return clampi(lie + int((t - lie_time) * asleep) % maxi(1, n - lie), 0, n - 1)
	if anim == "fish":
		var cast := Fishing.CAST_FRAMES / Fishing.CAST_FPS
		return Fishing.cast_frame(fmod(t, cast + 2.0 * maxi(1, n - Fishing.CAST_FRAMES) / Fishing.WAIT_FPS), n)
	return int(t * fps()) % n


## How fast the figure goes over the ground (world px a second), 0 when it doesn't.
func speed() -> float:
	var s := settings()
	if look < 0:
		# (her diagonal: the keys' half-height step down the screen)
		var diag := Vector2(0.7071, 0.7071 * float(s.get("verticalScale", 0.5))).length()
		if anim == "run": return float(s.get("runSpeed", 896)) * diag
		if anim == "walk": return float(s.get("walkSpeed", 492.8)) * diag
		return 0.0
	return float(s.walkSpeed) * world.px if anim == "walk" else 0.0


func _speed_px() -> float:
	return speed() * view_scale() if moving else 0.0


## How big a world px is in the preview: the game's camera zoom (twice that with x2).
func view_scale() -> float:
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam != null else 1.0
	return z * (2.0 if big else 1.0)


## Which way the figure slides: south-west facing down, north-west facing up, east mirrored.
func heading() -> Vector2:
	return Vector2(2.0 if mirrored else -2.0, -1.0 if facing_up else 1.0).normalized()


# ---- Changing it ----

func _remember() -> void:
	if _loaded.has(look):
		return
	var s := settings()
	var was := {}
	for k in (PLAYER_KEYS if look < 0 else LOOK_KEYS):
		was[k] = (s[k] as Array).duplicate() if s.get(k) is Array else s.get(k)
	_loaded[look] = was
	var toks := {}
	var line := _line_text()
	for k in was:
		var m := _token_re(str(k)).search(line)
		if m != null:
			toks[k] = m.get_string(1)
	_tokens[look] = toks


## Sets [param key] of the look tuned, seen at once by everyone wearing it.
func set_value(key: String, v: Variant) -> void:
	_remember()
	var s := settings()
	s[key] = v
	if key == "walkCycle":
		# (kept with it, as the importer keeps them: what the frames a second come to)
		var c := maxf(0.05, float(v))
		if s.has("walkFps"):
			s["walkFps"] = snappedf((s.get("walkDown", []) as Array).size() / c, 0.01)
		if s.has("walkFpsUp"):
			s["walkFpsUp"] = snappedf((s.get("walkUp", []) as Array).size() / c, 0.01)
	refresh_played()


## The played body (and Sera when she's a companion) brought up to date with what's been changed.
func refresh_played() -> void:
	var pl := Playable.active
	if pl == null:
		return
	var lead := pl._lead_data
	miko.walk_speed = float(lead.get("walkSpeed", miko.walk_speed))
	miko.run_speed = float(lead.get("runSpeed", miko.run_speed))
	if not pl._lead_look.is_empty():
		pl._lead_look.settings["walkFps"] = float(lead.get("walkFps", 8))
		pl._lead_look.settings["stabFps"] = float(lead.get("attackFps", 16))
	pl._looks.clear()
	if not is_same(miko.data, lead):
		var d := pl.player_look(pl.who, pl.played)
		for k in ["walkFps", "runFps", "idleFps", "attackFps", "upPace"]:
			if d.has(k):
				miko.data[k] = d[k]
			else:
				miko.data.erase(k)
		pl._looks[pl.who] = miko.data


## Puts back the paces and sizes as they were loaded.
func revert() -> void:
	if _loaded.has(look):
		var s := settings()
		var was: Dictionary = _loaded[look]
		for k in was:
			if was[k] == null:
				s.erase(k)
			else:
				s[k] = (was[k] as Array).duplicate() if was[k] is Array else was[k]
	for id in _orig:
		var info: Dictionary = world.sprites[int(id)]
		info["ppu"] = _orig[id].ppu
		info["pivot"] = (_orig[id].pivot as Array).duplicate()
		var nm := str(info.get("name", ""))
		if _orig[id].had_tune:
			_tune[nm] = (_orig[id].tune as Dictionary).duplicate(true)
		else:
			_tune.erase(nm)
	refresh_played()
	said = "Reverted to what was loaded (not saved yet)."
	_build()


# ---- The size of the frames ----

## The scale and nudge of the animation's frames now: {scale, nudge}.
func size_tune() -> Dictionary:
	var frames := frames_now()
	if frames.is_empty():
		return {"scale": 1.0, "nudge": [0.0, 0.0]}
	var nm := str(world.sprites[int(frames[0])].get("name", ""))
	var t: Dictionary = _tune.get(nm, {})
	return {"scale": float(t.get("scale", 1.0)), "nudge": (t.get("nudge", [0.0, 0.0]) as Array).duplicate()}


## Draws the animation's frames (this facing) [param sc] times as big, the pivot nudged by [param nudge] sheet px:
## their ppu and pivot in the sprite table, read each time they're drawn.
func set_frame_size(sc: float, nudge: Array) -> void:
	sc = maxf(0.05, sc)
	var lines := PackedStringArray()
	for f in frames_now():
		var id := int(f)
		var info: Dictionary = world.sprites[id]
		var nm := str(info.get("name", ""))
		if not _base.has(id):
			if lines.is_empty():
				lines = _sprite_lines()
			# (as imported: what's drawn now, less any tune already saved)
			var t: Dictionary = _tune.get(nm, {})
			var was_sc := float(t.get("scale", 1.0))
			var was_n: Array = t.get("nudge", [0.0, 0.0])
			var pv: Array = info.pivot
			_base[id] = {"ppu": float(info.ppu) * was_sc, "pivot": [float(pv[0]) - float(was_n[0]), float(pv[1]) - float(was_n[1])]}
			_orig[id] = {"ppu": info.ppu, "pivot": pv.duplicate(), "line": str(lines[id + 1]) if id + 1 < lines.size() else "",
				"had_tune": _tune.has(nm), "tune": t.duplicate(true)}
		var b: Dictionary = _base[id]
		info["ppu"] = snappedf(float(b.ppu) / sc, 0.01)
		info["pivot"] = [snappedf(float(b.pivot[0]) + float(nudge[0]), 0.1), snappedf(float(b.pivot[1]) + float(nudge[1]), 0.1)]
		if is_equal_approx(sc, 1.0) and is_zero_approx(float(nudge[0])) and is_zero_approx(float(nudge[1])):
			_tune.erase(nm)
		else:
			_tune[nm] = {"scale": snappedf(sc, 0.001), "nudge": [snappedf(float(nudge[0]), 0.1), snappedf(float(nudge[1]), 0.1)]}


## The drawn (not see-through) part of a frame, in its sheet's px from the frame's corner.
func drawn_rect(id: int) -> Rect2:
	if _bounds.has(id):
		return _bounds[id]
	var info: Dictionary = world.sprites[id]
	var r := Rect2(0, 0, info.rect[2], info.rect[3])
	var tex := world._texture(str(info.tex))
	if tex != null:
		var img := tex.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			var used := img.get_region(Rect2i(int(info.rect[0]), int(info.rect[1]), int(info.rect[2]), int(info.rect[3]))).get_used_rect()
			if used.size != Vector2i.ZERO:
				r = Rect2(used)
	_bounds[id] = r
	return r


# ---- Saving ----

## Writes the look's paces back (its own line in villagers.json, or player.json) and the sizes changed (their lines
## in sprites.json, and art_tune.json for the importer). Says what it did.
func save() -> bool:
	var ok := true
	var n := 0
	if _loaded.has(look):
		var r := _save_paces()
		ok = ok and r >= 0
		n += maxi(r, 0)
	var r2 := _save_sizes()
	ok = ok and r2 >= 0
	n += maxi(r2, 0)
	said = ("Saved %d change%s." % [n, "" if n == 1 else "s"]) if ok else "Couldn't save: see the log."
	if _said != null:
		_said.text = said
	return ok


func _file_of_look() -> String:
	return PLAYER if look < 0 else VILLAGERS


func _token_re(key: String) -> RegEx:
	var re := RegEx.new()
	re.compile(("(?m)^" if look < 0 else "") + "\"" + key + "\":(-?[0-9.eE+-]+|\\[[^\\[\\]]*\\])")
	return re


# The look's line in villagers.json (each look is one line), or the whole of player.json.
func _line_text() -> String:
	var text := FileAccess.get_file_as_string(_file_of_look())
	if look < 0:
		return text
	var lines := text.split("\r\n" if text.contains("\r\n") else "\n")
	var at := _look_line(lines)
	return lines[at] if at >= 0 else ""


func _look_line(lines: PackedStringArray) -> int:
	for i in lines.size():
		if lines[i].begins_with("\"looks\":["):
			var at := i + look
			return at if at < lines.size() and lines[at].contains("{\"settings\":{") else -1
	return -1


static func num_text(v: Variant) -> String:
	if v is Array:
		var parts := PackedStringArray()
		for x in v:
			parts.append(num_text(x))
		return "[" + ",".join(parts) + "]"
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else String.num(f, 3)


static func same(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	if a is Array or b is Array:
		if not (a is Array and b is Array) or (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not is_equal_approx(float(a[i]), float(b[i])):
				return false
		return true
	return is_equal_approx(float(a), float(b))


# Returns how many settings changed in the file, or -1.
func _save_paces() -> int:
	var path := _file_of_look()
	var text := FileAccess.get_file_as_string(path)
	var nl := "\r\n" if text.contains("\r\n") else "\n"
	var lines := text.split(nl)
	var at := -1 if look < 0 else _look_line(lines)
	if look >= 0 and at < 0:
		push_error("AnimTuner: look %d's line not found in villagers.json" % look)
		return -1
	var line := text if look < 0 else lines[at]
	var s := settings()
	var was: Dictionary = _loaded[look]
	var toks: Dictionary = _tokens[look]
	var n := 0
	for k in was:
		var key := str(k)
		var re := _token_re(key)
		var m := re.search(line)
		var now: Variant = s.get(key)
		if now == null:
			if m != null:
				# (taken away again: the key and its comma)
				var whole := m.get_string(0)
				line = line.replace(whole + ",", "") if line.contains(whole + ",") else line.replace("," + whole, "")
				n += 1
			continue
		# (back as loaded: its own text again, as it was written)
		var tok := str(toks[key]) if same(now, was[key]) and toks.has(key) else num_text(now)
		if m != null:
			if m.get_string(1) != tok:
				line = line.substr(0, m.get_start(1)) + tok + line.substr(m.get_end(1))
				n += 1
		elif look >= 0:
			line = line.replace("{\"settings\":{", "{\"settings\":{\"%s\":%s," % [key, tok])
			n += 1
	if n == 0:
		return 0
	if look >= 0:
		lines[at] = line
		text = nl.join(lines)
	else:
		text = line
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return -1
	f.store_string(text)
	f.close()
	return n


func _sprite_lines() -> PackedStringArray:
	var text := FileAccess.get_file_as_string(SPRITES)
	return text.split("\r\n" if text.contains("\r\n") else "\n")


# Returns how many frames' lines changed in sprites.json, or -1.
func _save_sizes() -> int:
	if _orig.is_empty():
		return 0
	var text := FileAccess.get_file_as_string(SPRITES)
	var nl := "\r\n" if text.contains("\r\n") else "\n"
	var lines := text.split(nl)
	var pv_re := RegEx.new()
	pv_re.compile("\"pivot\":\\[[^\\]]*\\]")
	var ppu_re := RegEx.new()
	ppu_re.compile("\"ppu\":-?[0-9.eE+-]+")
	var n := 0
	for id in _orig:
		var i := int(id) + 1
		var info: Dictionary = world.sprites[int(id)]
		if i >= lines.size() or not lines[i].contains("\"name\":\"%s\"" % str(info.get("name", ""))):
			push_error("AnimTuner: sprite %d's line not found in sprites.json" % int(id))
			return -1
		var o: Dictionary = _orig[id]
		var line: String
		if same(info.ppu, o.ppu) and same(info.pivot, o.pivot):
			line = str(o.line)
		else:
			line = pv_re.sub(lines[i], "\"pivot\":" + num_text(info.pivot))
			line = ppu_re.sub(line, "\"ppu\":" + num_text(info.ppu))
		if line != lines[i]:
			lines[i] = line
			n += 1
	if n > 0:
		var f := FileAccess.open(SPRITES, FileAccess.WRITE)
		if f == null:
			return -1
		f.store_string(nl.join(lines))
		f.close()
	_save_art_tune()
	return n


# data/art_tune.json: each frame's size tune by its sprite name, one a line (none left: the file goes).
func _save_art_tune() -> void:
	var names := _tune.keys()
	names.sort()
	if names.is_empty():
		if FileAccess.file_exists(ART_TUNE):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(ART_TUNE))
		return
	var rows := PackedStringArray()
	for nm in names:
		var t: Dictionary = _tune[nm]
		rows.append("  \"%s\": {\"scale\": %s, \"nudge\": %s}" % [nm, num_text(t.scale), num_text(t.nudge)])
	var body := "{\n \"_about\": \"Frames drawn bigger or smaller than they were imported, by sprite name (the animation tuner, F4, writes it): scale 1.25 draws them a quarter bigger (ppu / 1.25), nudge moves the pivot in sheet px. tools/import_miyu.py keeps these on a re-import.\",\n \"sprites\": {\n"
	body += ",\n".join(rows) + "\n }\n}\n"
	var f := FileAccess.open(ART_TUNE, FileAccess.WRITE)
	if f != null:
		f.store_string(body)
		f.close()


# ---- The panel ----

## The look's name in the picker: by who wears it.
func look_name(i: int) -> String:
	if i < 0:
		return "Sera (player)"
	var s: Dictionary = people.d.looks[i].settings
	var names := []
	var own := str(s.get("uniqueTo", ""))
	for id in Uniques.all():
		var u: Dictionary = Uniques.all()[id]
		if int(u.get("look", -1)) == i and (own == "" or own == str(id)) and str(id) != Playable.LEAD:
			names.append(str(u.get("name", id)))
	if names.is_empty():
		for v in Villager.all:
			if is_instance_valid(v) and is_same(v.s, s) and names.size() < 2:
				names.append(str(v.person.get("name", "")))
		return "%d Villagers%s" % [i, (": " + ", ".join(names)) if not names.is_empty() else ""]
	return "%d %s" % [i, ", ".join(names)]


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if not anims().has(anim):
		anim = str(anims()[0]) if not anims().is_empty() else "idle"
	held = -1 if playing else held
	_top = VBoxContainer.new()
	_top.add_theme_constant_override("separation", roundi(_k(6)))
	add_child(_top)
	# The head.
	var head := HBoxContainer.new()
	_top.add_child(head)
	var title := HudStyle.label("Animation tuner  ·  F4", 16, "bold", HudStyle.color("accentLight"))
	head.add_child(title)
	var hint := HudStyle.label("   dev only: changes show at once on everyone wearing the look; Save writes them", 10, "body", HudStyle.color("muted"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hint)
	var x := HudStyle.button("x", 12)
	x.custom_minimum_size = Vector2(_k(26), _k(24))
	x.pressed.connect(close)
	head.add_child(x)
	# Look, animation, facing.
	var looks := [-1]
	for i in people.d.looks.size():
		looks.append(i)
	looks.sort()
	var look_pills := []
	for i in looks:
		look_pills.append([look_name(int(i)), int(i) == look, _pick_look.bind(int(i))])
	_pills("Look", look_pills)
	var anim_pills := []
	for a in anims():
		anim_pills.append([str(a), a == anim, _pick_anim.bind(str(a))])
	_pills("Animation", anim_pills)
	var flip_pills := [["Down (SW)", not facing_up, _set_facing.bind(false)], ["Up (NW)", facing_up, _set_facing.bind(true)],
		["Mirrored (E)", mirrored, _flip.bind("mirrored")]]
	if speed() > 0.0:
		flip_pills.append(["Moving", moving, _flip.bind("moving")])
	flip_pills.append(["x2", big, _flip.bind("big")])
	flip_pills.append(["Sera beside", with_sera, _flip.bind("with_sera")])
	flip_pills.append(["Mark in world", mark, _flip.bind("mark")])
	_pills("Facing", flip_pills)
	# The preview and its controls.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_k(12)))
	_top.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", roundi(_k(4)))
	row.add_child(left)
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(well)
	_view = Preview.new()
	_view.tuner = self
	_view.custom_minimum_size = PREVIEW * HudStyle.SCALE
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(_view)
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", roundi(_k(6)))
	left.add_child(transport)
	var back := HudStyle.button("<", 12)
	back.custom_minimum_size.x = _k(34)
	back.pressed.connect(func(): step(-1))
	transport.add_child(back)
	_play = HudStyle.button("Pause" if playing else "Play", 12)
	_play.custom_minimum_size.x = _k(70)
	_play.pressed.connect(func(): set_playing(not playing))
	transport.add_child(_play)
	var fwd := HudStyle.button(">", 12)
	fwd.custom_minimum_size.x = _k(34)
	fwd.pressed.connect(func(): step(1))
	transport.add_child(fwd)
	_frame_label = HudStyle.label("", 13, "pixel")
	_frame_label.custom_minimum_size.x = _k(170)
	transport.add_child(_frame_label)
	_info = HudStyle.label(_info_text(), 10, "body", HudStyle.color("muted"))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = PREVIEW.x * HudStyle.SCALE
	left.add_child(_info)
	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", roundi(_k(6)))
	_controls.custom_minimum_size.x = _k(400)
	row.add_child(_controls)
	_fill_controls()
	# Save, Revert.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", roundi(_k(8)))
	_top.add_child(foot)
	var sv := HudStyle.button("Save", 12)
	sv.custom_minimum_size.x = _k(80)
	sv.pressed.connect(save)
	foot.add_child(sv)
	var rv := HudStyle.button("Revert", 12)
	rv.custom_minimum_size.x = _k(80)
	rv.pressed.connect(revert)
	foot.add_child(rv)
	_said = HudStyle.label(said, 11, "body", HudStyle.color("green"))
	_said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_said)
	var note := HudStyle.label("Save writes %s, sprites.json (the frames' sizes) and art_tune.json. tools/import_miyu.py keeps walkCycle and art_tune.json's sizes on a re-import (it resets her strike frames)." % ("player.json" if look < 0 else "villagers.json (this look's line only)"), 9, "body", HudStyle.color("faint"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = (PREVIEW.x + 412) * HudStyle.SCALE
	_top.add_child(note)
	reset_size()


func _pills(title: String, items: Array) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", roundi(_k(4)))
	_top.add_child(r)
	var h := HudStyle.label(title, 11, "bold", HudStyle.color("muted"))
	h.custom_minimum_size.x = _k(80)
	r.add_child(h)
	for it in items:
		var accent: Variant = HudStyle.color("accentLight")
		var b := HudStyle.button(str(it[0]), 10, "tileOn" if it[1] else "pill", accent if it[1] else null)
		b.pressed.connect(it[2])
		r.add_child(b)


func _pick_look(i: int) -> void:
	look = i
	if look < 0 and not PLAYER_ANIMS.has(anim):
		anim = "run"
	if look >= 0 and not LOOK_ANIMS.has(anim):
		anim = "walk"
	clock = 0.0
	travelled = 0.0
	held = -1
	_build()


func _pick_anim(a: String) -> void:
	anim = a
	clock = 0.0
	travelled = 0.0
	held = -1
	playing = true
	_build()


# One of the on-or-off pills (mirrored, moving, x2, Sera beside, mark in world).
func _flip(what: String) -> void:
	set(what, not bool(get(what)))
	_build()


func _set_facing(up: bool) -> void:
	facing_up = up
	held = -1 if playing else 0
	_build()


func set_playing(on: bool) -> void:
	if on and held >= 0:
		# (on from the frame stepped to)
		clock = (held + 0.5) / maxf(0.01, fps()) if anim != "sleep" and anim != "fish" else 0.0
	held = -1 if on else frame_index()
	playing = on
	if _play != null:
		_play.text = "Pause" if playing else "Play"


func step(by: int) -> void:
	var n := frames_now().size()
	if n == 0:
		return
	if playing:
		set_playing(false)
	held = posmod(frame_index() + by, n)


func _info_text() -> String:
	var n := frames_now().size()
	var f := fps()
	var t := "%d frames at %s fps: %s s a cycle." % [n, String.num(f, 2), String.num(n / maxf(0.01, f), 2)]
	if speed() > 0.0:
		var units := speed() / world.px
		t += "  Ground speed %s units/s: %s units a cycle (the ground slides under at that pace)." % [String.num(units, 2), String.num(units * n / maxf(0.01, f), 2)]
	if look >= 0 and (anim == "chop" or anim == "mine"):
		t += "  In the world: times %s (WORK_PACE) and their skill." % String.num(Villager.WORK_PACE, 2)
	if anim == "fish":
		t += "  Fishing's pace is the game's (Fishing: cast %s fps, then waiting %s fps)." % [String.num(Fishing.CAST_FPS, 1), String.num(Fishing.WAIT_FPS, 1)]
	if look >= 0 and anim == "faint":
		t += "  (A played body staggers at monsters.json's fainting pace.)"
	return t


func _fill_controls() -> void:
	var s := settings()
	_controls.add_child(HudStyle.label("Pace", 13, "bold", HudStyle.color("accentLight")))
	if look < 0:
		match anim:
			"run":
				_num_row("runFps", "runFps", 2, 30, 0.1)
				_num_row("runSpeed", "runSpeed px/s", 100, 2000, 1)
			"walk":
				_num_row("walkFps", "walkFps", 2, 30, 0.1)
				_num_row("walkSpeed", "walkSpeed px/s", 100, 1500, 1)
			"idle": _num_row("idleFps", "idleFps", 0.5, 20, 0.1)
			"attack": _num_row("attackFps", "attackFps", 2, 40, 0.5)
	else:
		match anim:
			"walk":
				if s.has("walkCycle"):
					_num_row("walkCycle", "walkCycle s", 0.3, 3.0, 0.01)
					_controls.add_child(_note("Seconds one stride cycle takes, both ways (it sets walkFps / walkFpsUp: now %s / %s)." % [String.num(float(s.get("walkFps", 0)), 2), String.num(float(s.get("walkFpsUp", s.get("walkFps", 0))), 2)]))
				else:
					_num_row("walkFps", "walkFps", 2, 30, 0.1)
					if s.has("walkFpsUp"):
						_num_row("walkFpsUp", "walkFpsUp", 2, 30, 0.1)
					var use := HudStyle.button("Use walkCycle (one pace both ways)", 10)
					use.pressed.connect(func():
						set_value("walkCycle", snappedf((s.get("walkDown", []) as Array).size() / maxf(0.1, float(s.walkFps)), 0.01))
						_build())
					_controls.add_child(use)
				_num_row("walkSpeed", "walkSpeed u/s", 0.2, 3.0, 0.01)
			"idle":
				if s.has("idleDownAnim"):
					_num_row("idleFps", "idleFps", 0.5, 20, 0.1)
				else:
					_controls.add_child(_note("One standing frame: no pace."))
			"chop", "mine", "cook", "faint", "stab": _num_row(anim + "Fps", anim + "Fps", 1, 30, 0.1)
			"sleep":
				_num_row("lieDownFrames", "lieDownFrames", 0, maxf(1, frames_now().size() - 1), 1)
				_num_row("lieDownFps", "lieDownFps", 0.5, 30, 0.1)
				_num_row("asleepFps", "asleepFps", 0.1, 10, 0.1)
	if strike_key() != "":
		_strikes_row()
	# The frames' size.
	_controls.add_child(HudStyle.label("Size of these frames (%s, %s)" % [anim, "up" if facing_up else "down"], 13, "bold", HudStyle.color("accentLight")))
	var st := size_tune()
	_slider_row("Scale", float(st.scale), 0.5, 2.0, 0.01, func(v: float):
		set_frame_size(v, size_tune().nudge))
	_slider_row("Pivot x", float(st.nudge[0]), -60, 60, 0.5, func(v: float):
		var t := size_tune()
		set_frame_size(float(t.scale), [v, t.nudge[1]]))
	_slider_row("Pivot y", float(st.nudge[1]), -60, 60, 0.5, func(v: float):
		var t := size_tune()
		set_frame_size(float(t.scale), [t.nudge[0], v]))
	_controls.add_child(_note("Scale 1.25 draws them a quarter bigger (ppu / 1.25), about the feet; the pivot nudge (sheet px; y up raises the feet line) puts the feet back on the baseline. The green line is the standing frame's head, the white one the ground."))


func _note(text: String) -> Label:
	var l := HudStyle.label(text, 9, "body", HudStyle.color("faint"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _k(400)
	return l


func _num_row(key: String, title: String, lo: float, hi: float, stp: float) -> void:
	var v := float(settings().get(key, 0.0))
	_slider_row(title, v, lo, hi, stp, func(x: float):
		if key == "lieDownFrames":
			set_value(key, int(x))
		else:
			set_value(key, x)
		if _info != null:
			_info.text = _info_text())


# A setting as a slider and the number beside it (typed and Enter, or left).
func _slider_row(title: String, v: float, lo: float, hi: float, stp: float, apply: Callable) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", roundi(_k(6)))
	_controls.add_child(r)
	var h := HudStyle.label(title, 11, "body")
	h.custom_minimum_size.x = _k(120)
	r.add_child(h)
	var slider := HSlider.new()
	slider.min_value = minf(lo, v)
	slider.max_value = maxf(hi, v)
	slider.step = stp
	slider.value = v
	slider.custom_minimum_size = Vector2(_k(190), _k(20))
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	r.add_child(slider)
	var field := LineEdit.new()
	field.text = String.num(v, 3)
	field.custom_minimum_size = Vector2(_k(70), _k(24))
	field.add_theme_stylebox_override("normal", HudStyle.piece("well"))
	field.add_theme_stylebox_override("focus", HudStyle.piece("well"))
	field.add_theme_font_size_override("font_size", roundi(_k(11)))
	r.add_child(field)
	slider.value_changed.connect(func(x: float):
		field.text = String.num(x, 3)
		apply.call(x))
	var typed := func():
		if field.text.strip_edges().is_valid_float():
			var x := float(field.text)
			slider.max_value = maxf(slider.max_value, x)
			slider.min_value = minf(slider.min_value, x)
			slider.set_value_no_signal(x)
			apply.call(x)
		field.release_focus()
	field.text_submitted.connect(func(_text: String): typed.call())
	field.focus_exited.connect(typed)


# The frames where a blow lands: typed ("7, 12"), or the frame shown made one (or not).
func _strikes_row() -> void:
	var key := strike_key()
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", roundi(_k(6)))
	_controls.add_child(r)
	var h := HudStyle.label(key, 11, "body")
	h.custom_minimum_size.x = _k(120)
	r.add_child(h)
	var field := LineEdit.new()
	field.text = ", ".join(strikes().map(func(x): return str(int(x))))
	field.custom_minimum_size = Vector2(_k(110), _k(24))
	field.add_theme_stylebox_override("normal", HudStyle.piece("well"))
	field.add_theme_stylebox_override("focus", HudStyle.piece("well"))
	field.add_theme_font_size_override("font_size", roundi(_k(11)))
	r.add_child(field)
	var typed := func():
		var out := []
		for part in field.text.split(",", false):
			if part.strip_edges().is_valid_int():
				out.append(int(part))
		set_value(key, out)
		field.release_focus()
	field.text_submitted.connect(func(_text: String): typed.call())
	field.focus_exited.connect(typed)
	var here := HudStyle.button("Strike here", 10)
	here.pressed.connect(func():
		var list: Array = strikes().duplicate()
		var i := frame_index()
		if list.has(i): list.erase(i)
		else:
			list.append(i)
			list.sort()
		set_value(key, list)
		field.text = ", ".join(list.map(func(x): return str(int(x)))))
	r.add_child(here)
	_controls.add_child(_note("Frames count from 0 (the label above counts from 1). The preview flashes on a strike."))


## The preview: the animation playing at the game's size, on a strip of ground, the look's standing frame beside it.
class Preview extends Control:
	var tuner: AnimTuner

	func _draw() -> void:
		var t := tuner
		var w := t.world
		var sz := size
		var k := t.view_scale()
		var frames := t.frames_now()
		var ground_y := sz.y * 0.78
		var ref_x := sz.x * 0.16
		var fig_x := sz.x * 0.5
		var sera_x := sz.x * 0.84
		# The ground: lines a half unit apart both ways along it, as the floor's diamonds go.
		# The ground: lines a half unit apart both ways, as the floor's diamonds go; for a walk or a run it slides
		# under the figure at its real pace the other way (a treadmill), so a planted foot should go along with it.
		var cell := 0.5 * w.px * k
		var dir := t.heading()
		var off := -dir * t.travelled if t.moving and t.speed() > 0.0 else Vector2.ZERO
		var mid := Vector2(sz.x * 0.5, ground_y)
		var faint := Color(1, 1, 1, 0.09)
		var along_a := Vector2(2, 1).normalized() * 2000.0
		var along_b := Vector2(2, -1).normalized() * 2000.0
		var shift_a := fposmod(off.x - 2.0 * off.y, 2.0 * cell)
		var shift_b := fposmod(off.x + 2.0 * off.y, 2.0 * cell)
		for i in range(-40, 41):
			var a := mid + Vector2(i * cell * 2.0 + shift_a, 0)
			draw_line(a - along_a, a + along_a, faint, 1.0)
			var b := mid + Vector2(i * cell * 2.0 + shift_b, 0)
			draw_line(b - along_b, b + along_b, faint, 1.0)
		var feet := Vector2(fig_x, ground_y)
		# The baseline at the feet, and the standing frame's head.
		var ref_id := -1
		var idle: Array = t.settings().get("frames", {}).get("idleDownLeft", []) if t.look < 0 else [t.settings().get("idleDown", -1)]
		if not idle.is_empty():
			ref_id = int(idle[0])
		draw_line(Vector2(0, ground_y), Vector2(sz.x, ground_y), Color(1, 1, 1, 0.45), 1.0)
		if ref_id >= 0:
			var top := _top_of(ref_id, k)
			draw_line(Vector2(0, ground_y + top), Vector2(sz.x, ground_y + top), Color(0.5, 0.95, 0.5, 0.6), 1.0)
			_figure(ref_id, Vector2(ref_x, ground_y), k, false, Color(1, 1, 1, 0.85))
			draw_string(HudStyle.font("body"), Vector2(ref_x - 30, sz.y - 8), "standing", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
		if t.with_sera:
			var sf: Array = t.miko.data.get("frames", {}).get("idleDownLeft", []) if Playable.active == null else Playable.active._lead_data.frames.get("idleDownLeft", [])
			if not sf.is_empty():
				_figure(int(sf[0]), Vector2(sera_x, ground_y), k, false, Color(1, 1, 1, 0.85))
				draw_string(HudStyle.font("body"), Vector2(sera_x - 16, sz.y - 8), "Sera", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
		if frames.is_empty():
			return
		var i := t.frame_index()
		var id := int(frames[i])
		var strike := t.strikes().has(i)
		if strike:
			draw_rect(Rect2(Vector2.ZERO, sz), Color(1.0, 0.45, 0.35, 0.18))
			draw_rect(Rect2(Vector2(2, 2), sz - Vector2(4, 4)), Color(1.0, 0.45, 0.35, 0.9), false, 4.0)
		_figure(id, feet, k, t.flipped(), Color.WHITE)
		# This frame's own head, as a tick over it.
		var my_top := _top_of(id, k)
		draw_line(Vector2(feet.x - 30, feet.y + my_top), Vector2(feet.x + 30, feet.y + my_top), Color(1.0, 0.55, 0.45, 0.9), 2.0)
		draw_circle(feet, 3.0, Color(1.0, 0.55, 0.45, 0.9))

	# How far above the feet a frame's drawing starts (negative: up), on screen.
	func _top_of(id: int, k: float) -> float:
		var info: Dictionary = tuner.world.sprites[id]
		var sc := World.BODY_SCALE * tuner.world.px / float(info.ppu) * k
		return (tuner.drawn_rect(id).position.y - float(info.pivot[1])) * sc

	func _figure(id: int, feet: Vector2, k: float, flip: bool, tint: Color) -> void:
		var w := tuner.world
		var info: Dictionary = w.sprites[id]
		var tex := w._texture(str(info.tex))
		if tex == null:
			return
		var sc := World.BODY_SCALE * w.px / float(info.ppu) * k
		draw_set_transform(feet, 0.0, Vector2(-sc if flip else sc, sc))
		var region := Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
		draw_texture_rect_region(tex, Rect2(Vector2(-float(info.pivot[0]), -float(info.pivot[1])), region.size), region, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Rings in the world at the feet of everyone wearing the look tuned (the played body too).
class Marks extends Node2D:
	var tuner: AnimTuner

	func _draw() -> void:
		var t := tuner
		var s := t.settings()
		var at := []
		for v in Villager.all:
			if is_instance_valid(v) and v.visible and is_same(v.s, s):
				at.append(v.position)
		var pl := Playable.active
		if t.look < 0:
			if is_same(t.miko.data, s):
				at.append(t.miko.position)
			if pl != null and not pl._lead_look.is_empty():
				for v in Villager.all:
					if is_instance_valid(v) and is_same(v.s, pl._lead_look.settings):
						at.append(v.position)
		elif pl != null and pl.who != Playable.LEAD:
			var li := int(pl.played.get("look", Uniques.all().get(pl.who, {}).get("look", 0)))
			if li == t.look:
				at.append(t.miko.position)
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 200.0)
		var px := t.world.px
		for p in at:
			draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
			draw_arc(Vector2.ZERO, 0.45 * px, 0.0, TAU, 40, Color(1.0, 0.85, 0.35, pulse), 4.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
