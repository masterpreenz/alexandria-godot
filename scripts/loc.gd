class_name Loc
## The game's words, by key, for translating (res://lang/<language>.json: {"key": "text"}). [method t] looks a key up
## in the language set (Settings) and falls back to English, then to the key itself; {name}-style blanks in the text
## are filled from the values given. A key can hold a list of lines (barks): [method pick] chooses one.
##
## To add a language: copy lang/en.json to lang/<code>.json and translate the values, keeping the keys and the {blanks}.

const FALLBACK := "en"

static var language := "en"
static var _tables := {}         ## language -> {key: text or [texts]}


static func _table(lang: String) -> Dictionary:
	if not _tables.has(lang):
		var path := "res://lang/%s.json" % lang
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_tables[lang] = d if d is Dictionary else {}
	return _tables[lang]


static func _raw(key: String) -> Variant:
	var v: Variant = _table(language).get(key)
	if v == null and language != FALLBACK:
		v = _table(FALLBACK).get(key)
	return v


## The text for [param key] in the language set, its {blanks} filled from [param values].
static func t(key: String, values := {}) -> String:
	var v: Variant = _raw(key)
	if v is Array:
		v = v[0] if not (v as Array).is_empty() else key
	return _fill(str(v) if v != null else key, values)


## One of the lines under [param key] (a list), at random, its {blanks} filled; "" when there are none.
static func pick(key: String, values := {}) -> String:
	var v: Variant = _raw(key)
	if v is Array and not (v as Array).is_empty():
		return _fill(str((v as Array).pick_random()), values)
	return _fill(str(v), values) if v != null else ""


## Whether [param key] has any text.
static func has(key: String) -> bool:
	return _raw(key) != null


static func _fill(text: String, values: Dictionary) -> String:
	for k in values:
		text = text.replace("{%s}" % k, str(values[k]))
	return text
