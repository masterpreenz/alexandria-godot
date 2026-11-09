class_name SaveSystem
## Save games (from Unity's SaveSystem), in the same files Unity writes, so a save made by either opens in the other: a
## save is JSON ({version, game, summary, sections: [{key, json}]}, each section one part of the game), gzipped, then
## encrypted with AES-256 (CBC, a fresh random IV each save) and signed with HMAC-SHA256 so any change to the file is
## caught on loading. Each file's two keys come from a master key (PBKDF2 of the game's secret, worked out once) and a
## random salt kept in the file:  "MIKOSAVE" | format (int) | salt (16) | IV (16) | ciphertext | HMAC (32).
## Each save goes to a temporary file first and then replaces the old one, which is kept as a .bak; a save that won't
## open falls back to its .bak.
##
## Saves live in user://Saves. With none there yet, the Unity game's saves are copied over (left where they were).

const FORMAT_VERSION := 1
const DATA_VERSION := 1
const AUTO := "auto"
const QUICK := "quick"
const FOLDER := "user://Saves"
const MAGIC := "MIKOSAVE"
const SECRET := "miko-shrine::v1::7c2f9a4e1b6d48a3b0e5f1c9d2a7e6b4"
const ITERATIONS := 20000

static var pending := ""              ## a slot to load when the scene starts again ("" none; "new" a new game)
static var loaded_slot := ""          ## the slot the running game came from ("" the bundled start)
static var play_seconds := 0.0
static var _master := PackedByteArray()
static var _start: Variant = null     ## the sections the running game started from
static var _imported := false


# ---- Where ----

static func path_of(slot: String) -> String:
	return FOLDER.path_join(slot + ".sav")


## The Unity game's save folder (Application.persistentDataPath/Saves for preenzraven/Alexandria).
static func unity_folder() -> String:
	var home := OS.get_environment("USERPROFILE")
	if home == "":
		home = OS.get_environment("HOME")
	return home.path_join("AppData/LocalLow/preenzraven/Alexandria/Saves")


## Copies the Unity game's saves over when there are none here yet (they're left where they were).
static func import_unity() -> int:
	if _imported:
		return 0
	_imported = true
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var here := DirAccess.get_files_at(FOLDER)
	for f in here:
		if f.ends_with(".sav"):
			return 0
	var from := unity_folder()
	if not DirAccess.dir_exists_absolute(from):
		return 0
	var n := 0
	for f in DirAccess.get_files_at(from):
		if f.ends_with(".sav") or f.ends_with(".sav.bak"):
			if DirAccess.copy_absolute(from.path_join(f), ProjectSettings.globalize_path(FOLDER.path_join(f))) == OK:
				n += 1
	if n > 0:
		print("Saves copied over from ", from, ": ", n)
	return n


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path_of(slot)) or FileAccess.file_exists(path_of(slot) + ".bak")


# ---- The start: the save to begin from ----

## The sections the running game starts from: the slot asked for, else the latest autosave or quick save, else the
## start bundled with the game (data/save.json). Worked out once per run of the scene.
static func start_sections(w: World) -> Dictionary:
	if _start != null:
		return _start
	var slot := pending
	pending = ""
	if Shots.arg("shot") != "" and slot == "":
		# A test run: the bundled start, unless it names a slot.
		slot = Shots.arg("slot")
	elif slot == "":
		import_unity()
		slot = latest()
	var file: Dictionary = {}
	if slot != "" and slot != "new":
		file = read(slot)
		if not file.is_empty():
			loaded_slot = slot
			play_seconds = float(file.get("summary", {}).get("playSeconds", 0.0))
	if file.is_empty():
		loaded_slot = ""
		play_seconds = 0.0
		var bundled: Dictionary = w._load_json("res://data/save.json") if FileAccess.file_exists("res://data/save.json") and slot != "new" else {}
		_start = bundled.get("sections", {})
		return _start
	var sections := {}
	for s in file.get("sections", []):
		sections[s.key] = s.json
	_start = sections
	return _start


## Forgets the start, so the scene loaded next works it out again.
static func reset_start() -> void:
	_start = null


## The slot saved most recently (auto or quick), or "".
static func latest() -> String:
	var best := ""
	var best_at := -1
	for slot in [AUTO, QUICK]:
		var p := path_of(slot)
		if FileAccess.file_exists(p):
			var at := FileAccess.get_modified_time(p)
			if at > best_at:
				best_at = at
				best = slot
	return best


# ---- Reading ----

## Reads [param slot] (or its backup if it's damaged); {} if neither opens.
static func read(slot: String) -> Dictionary:
	for candidate in [path_of(slot), path_of(slot) + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var bytes := FileAccess.get_file_as_bytes(candidate)
		var plain := open(bytes)
		if plain.is_empty():
			push_warning("Couldn't open " + candidate)
			continue
		var d: Variant = JSON.parse_string(plain.get_string_from_utf8())
		if d is Dictionary and int(d.get("version", 1)) <= DATA_VERSION:
			if candidate != path_of(slot):
				push_warning("Save '%s' was damaged; loaded its backup." % slot)
			return d
	return {}


## A slot's summary without loading it, or {}.
static func peek(slot: String) -> Dictionary:
	return read(slot).get("summary", {}) if exists(slot) else {}


## Every save with its summary: the autosave and quick save first, then the rest, newest first. [[slot, summary]].
static func list() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(FOLDER):
		return out
	var slots := {}
	for f in DirAccess.get_files_at(FOLDER):
		if f.ends_with(".sav"): slots[f.trim_suffix(".sav")] = true
		elif f.ends_with(".sav.bak"): slots[f.trim_suffix(".sav.bak")] = true
	for slot in slots:
		var s := peek(slot)
		if not s.is_empty():
			out.append([slot, s])
	var rank := func(slot: String) -> int: return 0 if slot == AUTO else (1 if slot == QUICK else 2)
	out.sort_custom(func(a, b):
		var ra: int = rank.call(a[0])
		var rb: int = rank.call(b[0])
		return ra < rb if ra != rb else str(a[1].get("savedAt", "")) > str(b[1].get("savedAt", "")))
	return out


static func delete(slot: String) -> void:
	for p in [path_of(slot), path_of(slot) + ".bak", path_of(slot) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# ---- Writing ----

## A section as Unity's JsonUtility reads it: whole numbers written as whole numbers (Godot reads every JSON number as
## a float, and "7.0" won't go into an int field).
static func tidy(json: String) -> String:
	var d: Variant = JSON.parse_string(json)
	return JSON.stringify(_whole(d)) if d != null else json


static func _whole(v: Variant) -> Variant:
	if v is float:
		return int(v) if is_finite(v) and v == floorf(v) and absf(v) < 9.0e15 else v
	if v is Array:
		return v.map(func(x): return _whole(x))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _whole(v[k])
		return out
	return v


## Saves [param sections] ({key: json}) with [param summary] into [param slot]; "" when it worked, else why not.
static func write(slot: String, summary: Dictionary, sections: Dictionary) -> String:
	var entries := []
	for k in sections:
		if sections[k] != null:
			entries.append({"key": k, "json": sections[k]})
	var file := {"version": DATA_VERSION, "game": "Alexandria", "summary": summary, "sections": entries}
	var bytes := seal(JSON.stringify(file).to_utf8_buffer())
	return _write_safely(path_of(slot), bytes)


## Renames the save in [param slot] (the game isn't touched).
static func rename(slot: String, name: String) -> String:
	var file := read(slot)
	if file.is_empty():
		return "No save there"
	file.summary.name = name.strip_edges().left(32) if name.strip_edges() != "" else default_name(slot, file.summary)
	return _write_safely(path_of(slot), seal(JSON.stringify(file).to_utf8_buffer()))


static func default_name(slot: String, s: Dictionary) -> String:
	if slot == AUTO: return "Autosave"
	if slot == QUICK: return "Quick save"
	return "%s · Day %d" % [s.get("season", ""), int(s.get("day", 1))]


## A fresh slot for a new named save.
static func new_slot() -> String:
	var t := Time.get_datetime_dict_from_system(true)
	return "save-%04d%02d%02d-%02d%02d%02d-%03d" % [t.year, t.month, t.day, t.hour, t.minute, t.second, Time.get_ticks_msec() % 1000]


# Writes beside the file, then swaps it in, keeping the old one as .bak: a crash mid-save never loses a save.
static func _write_safely(path: String, bytes: PackedByteArray) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp := path + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return "Couldn't write the save (%s)" % error_string(FileAccess.get_open_error())
	f.store_buffer(bytes)
	f.close()
	if FileAccess.file_exists(path):
		var backup := path + ".bak"
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		DirAccess.rename_absolute(path, backup)
	var err := DirAccess.rename_absolute(temp, path)
	return "" if err == OK else "Couldn't put the save in place (%s)" % error_string(err)


# ---- Sealing: gzip, AES-256-CBC, HMAC-SHA256 (as Unity's) ----

static func _hmac(key: PackedByteArray, msg: PackedByteArray) -> PackedByteArray:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, msg)


## The master key: PBKDF2-HMAC-SHA256 of the secret (one 32-byte block), worked out once.
static func master() -> PackedByteArray:
	if not _master.is_empty():
		return _master
	var password := SECRET.to_ascii_buffer()
	var salt := "MikoSaveMaster.v1".to_ascii_buffer()
	salt.append_array(PackedByteArray([0, 0, 0, 1]))
	var crypto := Crypto.new()
	var u := crypto.hmac_digest(HashingContext.HASH_SHA256, password, salt)
	var t := u.duplicate()
	for i in ITERATIONS - 1:
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
		for j in 32:
			t[j] = t[j] ^ u[j]
	_master = t
	return _master


static func _keys(salt: PackedByteArray) -> Array:
	var a := salt.duplicate()
	a.append(1)
	var b := salt.duplicate()
	b.append(2)
	return [_hmac(master(), a), _hmac(master(), b)]


static func _int32(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_s32(0, n)
	return b


static func seal(plain: PackedByteArray) -> PackedByteArray:
	var packed := plain.compress(FileAccess.COMPRESSION_GZIP)
	var crypto := Crypto.new()
	var salt := crypto.generate_random_bytes(16)
	var iv := crypto.generate_random_bytes(16)
	var keys := _keys(salt)
	# PKCS7 padding, then AES-256-CBC.
	var pad := 16 - packed.size() % 16
	for i in pad:
		packed.append(pad)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, keys[0], iv)
	var cipher := aes.update(packed)
	aes.finish()
	var body := MAGIC.to_ascii_buffer()
	body.append_array(_int32(FORMAT_VERSION))
	body.append_array(salt)
	body.append_array(iv)
	body.append_array(cipher)
	body.append_array(_hmac(keys[1], body))
	return body


## The plain bytes of a sealed save, or empty when it isn't one, was changed or is damaged.
static func open(file: PackedByteArray) -> PackedByteArray:
	var head := MAGIC.length() + 4 + 16 + 16
	if file.size() < head + 16 + 32 or file.slice(0, MAGIC.length()).get_string_from_ascii() != MAGIC:
		return PackedByteArray()
	if file.decode_s32(MAGIC.length()) != FORMAT_VERSION:
		return PackedByteArray()
	var salt := file.slice(MAGIC.length() + 4, MAGIC.length() + 20)
	var iv := file.slice(MAGIC.length() + 20, head)
	var keys := _keys(salt)
	var signed := file.size() - 32
	var expected := _hmac(keys[1], file.slice(0, signed))
	var diff := 0
	for i in 32:
		diff |= expected[i] ^ file[signed + i]
	if diff != 0:
		return PackedByteArray()
	var cipher := file.slice(head, signed)
	if cipher.size() % 16 != 0:
		return PackedByteArray()
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, keys[0], iv)
	var packed := aes.update(cipher)
	aes.finish()
	var pad := packed[packed.size() - 1]
	if pad < 1 or pad > 16:
		return PackedByteArray()
	packed = packed.slice(0, packed.size() - pad)
	return packed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
