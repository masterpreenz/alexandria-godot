"""Writes the waysides along the road west to the next village: data/villages/wayside_*.json (VillageTemplate files,
added to games already going too)."""
import json, os

OUT = "data/villages"


def room(x0, y0, w, h, kinds, gaps=()):
    """Walls round a w x h room at (x0, y0) (template cells), each side's pieces taking kinds in turn; gaps: walls left out
    (as (x, y, alongY))."""
    walls = []
    i = 0
    edges = [(x, y0, False) for x in range(x0, x0 + w)] + [(x0 + w, y, True) for y in range(y0, y0 + h)] \
        + [(x, y0 + h, False) for x in range(x0, x0 + w)] + [(x0, y, True) for y in range(y0, y0 + h)]
    for e in edges:
        if e in gaps:
            continue
        walls.append({"alongY": e[2], "type": kinds[i % len(kinds)], "x": e[0], "y": e[1]})
        i += 1
    return walls


def floor(x0, y0, w, h, holes=()):
    return [{"ground": "", "laid": "WornBoards", "roof": "", "turned": False, "x": x, "y": y}
            for x in range(x0, x0 + w) for y in range(y0, y0 + h) if (x, y) not in holes]


def prop(t, x, y, **kw):
    r = {"scale": 1.0, "turn": 0, "type": t, "x": x, "y": y}
    r.update(kw)
    return r


MARGIN = 2   # cells of cleared ground round each one (the woods' canopies otherwise hang over it)


def write(name, at, w, h, floors=(), walls=(), props=()):
    shift = lambda rows: [dict(r, x=r["x"] + MARGIN, y=r["y"] + MARGIN) for r in rows]
    floors, walls, props = shift(floors), shift(walls), shift(props)
    at = (at[0] - MARGIN, at[1] - MARGIN)
    w, h = w + 2 * MARGIN, h + 2 * MARGIN
    t = {"name": name, "at": list(at), "width": w, "height": h, "addToSaves": True, "clear": True,
         "floors": list(floors), "walls": list(walls), "props": list(props), "free": []}
    with open(os.path.join(OUT, name + ".json"), "w", encoding="utf-8", newline="\n") as f:
        f.write("{\n")
        keys = list(t.keys())
        for i, k in enumerate(keys):
            v = t[k]
            end = "," if i < len(keys) - 1 else ""
            if isinstance(v, list) and v and isinstance(v[0], dict):
                f.write('"%s": [\n' % k + ",\n".join(json.dumps(r, separators=(",", ":")) for r in v) + "\n]" + end + "\n")
            else:
                f.write('"%s": %s%s\n' % (k, json.dumps(v), end))
        f.write("}\n")


# 1. A woodcutter's hut gone to ruin, north of the road (its door side open to it).
write("wayside_hut", (-168, 6), 7, 6,
      floor(1, 1, 4, 3, holes={(4, 1)}),
      room(1, 1, 4, 3, ["PlankWall", "BrokenPlankWall", "PlankWall"], gaps={(2, 1, False), (3, 1, False), (5, 2, True)}),
      [prop("Bedroll", 2, 3), prop("Rocks", 6, 0), prop("TallGrass", 0, 4), prop("LumberingSign", 5, 0), prop("Pebble", 3, 5)])

# 2. Travellers' camp south of the road: a fire long out, bedrolls round it.
write("wayside_camp", (-192, -12), 6, 6, (), (),
      [prop("Bonfire", 3, 3, out=True), prop("Bedroll", 1, 2), prop("Bedroll", 4, 1), prop("Rocks", 0, 4),
       prop("Pebble", 5, 4), prop("TallGrass", 2, 5), prop("Bush", 5, 0)])

# 3. A well by the road with its street lamps, north side.
write("wayside_well", (-216, 6), 5, 4, (), (),
      [prop("Well", 2, 1), prop("StreetLamp", 0, 0, turn=1), prop("StreetLamp", 4, 0, turn=0), prop("FlatStone", 1, 2),
       prop("FlatStone", 3, 2), prop("Flowers", 0, 3), prop("GreyPebble3", 4, 3)])

# 4. A watch post where the road turns north, long left: lamps either side of the way, a fire out, a bedroll.
write("wayside_post", (-262, 24), 18, 4, (), (),
      [prop("StreetLamp", 3, 1, turn=1), prop("StreetLamp", 14, 1, turn=0), prop("Bonfire", 1, 0, out=True),
       prop("Bedroll", 16, 2), prop("Rocks", 0, 3), prop("Pebble", 15, 3)])

# 5. A collapsed shed west of the way north.
write("wayside_shed", (-266, 52), 6, 5,
      floor(1, 1, 3, 3, holes={(3, 3)}),
      room(1, 1, 3, 3, ["BrokenPlankWall", "BrokenPlankWall", "PlankWall"], gaps={(4, 1, True), (4, 2, True), (2, 4, False), (3, 4, False)}),
      [prop("Rocks", 2, 2), prop("TallGrass", 0, 0), prop("Bush", 5, 4), prop("Pebble", 1, 4)])

# 6. A last camp short of the next village, east of the way: someone left in a hurry.
write("wayside_lastcamp", (-244, 76), 6, 5, (), (),
      [prop("Bonfire", 2, 2, out=True), prop("Bedroll", 4, 2), prop("Chest", 0, 1), prop("MiningSign", 5, 0),
       prop("Rocks", 1, 4), prop("TallGrass", 4, 4)])
print("ok")
