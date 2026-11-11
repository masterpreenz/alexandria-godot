class_name VillageTemplate
## A village laid out ahead of time: everything built over an area of the map (ground and laid floors, walls and
## doors, roofs' looks, props, free-standing props, farm plots, the banner), kept as a file in data/villages/ and
## stamped into the world on a new game. Build mode's "Save area" tool writes one from what's built (drag over the
## area, name it, save): so a village is drafted, rearranged by hand, and saved back.
##
## A file: {name, at: [x, y] (its first cell, where it goes), width, height, tier (the village's size, if it has a
## banner), floors: [{x, y, ground, laid, turned, roof}], walls: [{x, y, alongY, type, turned, hp}],
## props: [{x, y, type, turn, scale, out (a fire that's out)}], free: [{x, y, type, turn, scale}]} (x, y from its first cell; free ones in
## fractions of cells).

const FOLDER := "res://data/villages/"


static func path_of(nm: String) -> String:
	return FOLDER + nm + ".json"


## Every template there is (their names).
static func all_names() -> Array:
	var out := []
	for f in DirAccess.get_files_at(FOLDER):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


static func exists(nm: String) -> bool:
	return FileAccess.file_exists(path_of(nm))


static func load_named(nm: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_of(nm)))
	return d if d is Dictionary else {}


static func save(t: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var f := FileAccess.open(path_of(str(t.name)), FileAccess.WRITE)
	if f == null:
		return false
	# (one entry to a line: readable, and git shows what changed)
	var lines := []
	for k in ["name", "at", "width", "height", "tier", "residents", "addToSaves"]:
		if t.has(k):
			lines.append('"%s": %s' % [k, JSON.stringify(t[k])])
	for k in ["floors", "walls", "props", "free"]:
		var rows: Array = t.get(k, [])
		lines.append('"%s": [\n%s\n]' % [k, ",\n".join(rows.map(func(r): return JSON.stringify(r)))])
	f.store_string("{\n" + ",\n".join(lines) + "\n}\n")
	f.close()
	return true


## What's built over [param area] (cells, both corners in), as a template called [param nm].
static func capture(w: World, area: Rect2i, nm: String) -> Dictionary:
	var lo := area.position
	var hi := area.end - Vector2i.ONE
	var t := {"name": nm, "at": [lo.x, lo.y], "width": area.size.x, "height": area.size.y, "floors": [], "walls": [], "props": [], "free": []}
	var f := w.floors
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var c := Vector2i(x, y)
			var ground := str(f.cells.get(c, ""))
			var laid := str(f.laid.get(c, ""))
			var roof := str(w.roofs.roof_floors.get(c, "")) if w.roofs != null else ""
			if ground != "" or laid != "":
				t.floors.append({"x": x - lo.x, "y": y - lo.y, "ground": ground, "laid": laid, "turned": f.is_turned(c), "roof": roof})
	for k in w.walls.walls:
		var v: Vector3i = k
		if v.x < lo.x or v.y < lo.y or v.x > hi.x + 1 or v.y > hi.y + 1:
			continue
		var row := {"x": v.x - lo.x, "y": v.y - lo.y, "alongY": v.z == 1, "type": str(w.walls.walls[k])}
		if w.walls.turned_round.has(k):
			row["turned"] = true
		if w.walls.hp.has(k) and float(w.walls.hp[k]) < w.walls.max_hp(str(w.walls.walls[k])):
			row["hp"] = float(w.walls.hp[k])
		t.walls.append(row)
	for k in w.props.cells:
		var v: Vector3i = k
		if area.has_point(Vector2i(v.x, v.y)):
			var e: Dictionary = w.props.cells[k]
			t.props.append({"x": v.x - lo.x, "y": v.y - lo.y, "type": str(e.prop), "turn": int(e.get("turn", 0)), "scale": float(e.get("scale", 1.0))})
	for e in w.props.free_props():
		if area.has_point(f.cell_at(e.pos)):
			var fc: Vector2 = f.fractional_cell(e.pos) - Vector2(lo)
			t.free.append({"x": snappedf(fc.x, 0.001), "y": snappedf(fc.y, 0.001), "type": str(e.prop), "turn": int(e.get("turn", 0)), "scale": float(e.get("scale", 1.0))})
	if not w.props_named("TownBanner").filter(func(at): return area.has_point(f.cell_at(at))).is_empty():
		t["tier"] = w.village.tier
	return t


## Builds template [param t] into the world, at its own place or [param at] (its first cell): the trees and rocks
## where it builds cleared (and what was built there before), then its floors, walls, props.
static func stamp(w: World, t: Dictionary, at := Vector2i(1 << 30, 0)) -> void:
	var lo := Vector2i(int(t.at[0]), int(t.at[1])) if at.x == 1 << 30 else at
	var f := w.floors
	# (cleared only where something's built: the trees between the houses stand)
	var used := {}
	for r in t.get("floors", []) + t.get("props", []):
		used[lo + Vector2i(int(r.x), int(r.y))] = true
	for r in t.get("free", []):
		used[lo + Vector2i(floori(float(r.x)), floori(float(r.y)))] = true
	for r in t.get("walls", []):
		var v := lo + Vector2i(int(r.x), int(r.y))
		used[v] = true
		used[v - (Vector2i(1, 0) if bool(r.alongY) else Vector2i(0, 1))] = true
	for c in used:
		if f.in_bounds(c):
			w.props.remove_all(c)
			w.clear_cell(c)
	for r in t.get("floors", []):
		var c := lo + Vector2i(int(r.x), int(r.y))
		if not f.in_bounds(c):
			continue
		if str(r.ground) != "":
			f.paint(c, str(r.ground))
		if str(r.laid) != "":
			f.paint(c, str(r.laid), bool(r.get("turned", false)))
		if str(r.get("roof", "")) != "" and w.roofs != null:
			w.roofs.roof_floors[c] = str(r.roof)
	for r in t.get("walls", []):
		var e := WallMap.Edge.new(lo + Vector2i(int(r.x), int(r.y)), bool(r.alongY))
		w.walls.place(e, str(r.type), bool(r.get("turned", false)))
		if r.has("hp"):
			w.walls.hp[e.key()] = float(r.hp)
	for r in t.get("props", []):
		if w.props.types.has(str(r.type)):
			w.props.place(lo + Vector2i(int(r.x), int(r.y)), str(r.type), float(r.get("scale", 1.0)), int(r.get("turn", 0)))
			if bool(r.get("out", false)):
				Fires.start_out[lo + Vector2i(int(r.x), int(r.y))] = true   # (a fire that's gone out)
	for r in t.get("free", []):
		if w.props.types.has(str(r.type)):
			w.props.place_free(f.corner(Vector2(lo) + Vector2(float(r.x), float(r.y))), str(r.type), float(r.get("scale", 1.0)), int(r.get("turn", 0)))
	if t.has("tier") and w.village != null:
		w.village.tier = int(t.tier)
