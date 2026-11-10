class_name RabbitPens
extends Node
## The rabbit pens (from Unity's RabbitPen): each RabbitPen prop is a 3x3 tile patch of hay with a fence round it (the
## Fence wall's own pieces; a side running along another pen is left open, so pens placed together join into one), a
## burrow inside, and the rabbits put in it hopping about. Two or more breed: one more every day, up to [constant MOST].
## Miko lets the rabbits she's carrying in, or, carrying none, butchers one for raw meat (see RabbitHands). How many
## each holds is kept by where it stands, and saved (world.rabbits).

const MOST := 6
const HOP_FRAMES := [7, 4, 5, 6]

var world: World
var s: Dictionary                 ## the pen's settings (monsters.json rabbitPen)
var states := {}                  ## Vector2i key -> {count, bredAt}
var pens := {}                    ## Vector2i key -> Pen
var _looked_at := -1


class Pen:
	var at := Vector2.ZERO        ## where the prop stands
	var cell := Vector2i.ZERO     ## its middle tile
	var key := Vector2i.ZERO
	var nodes: Array = []         ## fence pieces, burrow and the fence's body
	var hoppers: Array = []       ## [sprite, at, to, until, clock, hopping, back, flip]


func setup(w: World, settings: Dictionary) -> void:
	world = w
	s = settings


## Unity keeps a pen by where it stands, in eighths of a unit (y up).
func _key(at: Vector2) -> Vector2i:
	return Vector2i(roundi(at.x / world.px * 8.0), roundi(-at.y / world.px * 8.0))


func _hours() -> float:
	return world.clock.hours if world.clock != null else Time.get_ticks_msec() / 1000.0 / 30.0


func from_json(json: String) -> void:
	var data: Variant = JSON.parse_string(json)
	states.clear()
	if data is Dictionary:
		for p in data.get("pens", []):
			states[Vector2i(roundi(float(p.x) * 8.0), roundi(float(p.y) * 8.0))] = {"count": int(p.count), "bredAt": float(p.bredAt)}


func to_json() -> String:
	var list := []
	for k in states:
		list.append({"x": k.x / 8.0, "y": k.y / 8.0, "count": states[k].count, "bredAt": states[k].bredAt})
	return JSON.stringify({"pens": list})


func _state(p: Pen) -> Dictionary:
	if not states.has(p.key):
		states[p.key] = {"count": 0, "bredAt": 0.0}
	return states[p.key]


func count(p: Pen) -> int:
	return int(_state(p).count)


## Game hours to the next litter, or -1 when there aren't two to breed (or it's full).
func hours_to_litter(p: Pen) -> float:
	var st := _state(p)
	if st.count < 2 or st.count >= MOST:
		return -1.0
	return maxf(0.0, _breed_hours() - (_hours() - float(st.bredAt)))


## The nearest pen within [param range] px of [param at], or null.
func nearest(at: Vector2, reach: float) -> Pen:
	var best: Pen = null
	var best_d := reach
	for p in pens.values():
		var d: float = p.at.distance_to(at)
		if d < best_d:
			best_d = d
			best = p
	return best


## Lets up to [param n] rabbits in; how many went in.
func put_in(p: Pen, n: int) -> int:
	var st := _state(p)
	var add := clampi(n, 0, MOST - int(st.count))
	if add <= 0:
		return 0
	# The breeding clock starts when the second one arrives.
	if st.count < 2 and st.count + add >= 2:
		st.bredAt = _hours()
	st.count += add
	return add


## Butchers one: the raw meat it gives (0 if the pen's empty).
func butcher(p: Pen) -> int:
	var st := _state(p)
	if st.count <= 0:
		return 0
	st.count -= 1
	return int(s.meat) + int(_talent("butcherBonus"))   # (Rabbit Keeper)


# Miko's talent stat [param nm] (her Hearth talents reach the pens).
func _talent(nm: String) -> float:
	var p := world.player
	return p.stats.stat(nm) if p != null and p.stats != null else 0.0


# Game hours between litters: fewer with Soft Hay and Rabbit Keeper.
func _breed_hours() -> float:
	return float(s.breedHours) / CharacterStats.percent(maxf(0.0, _talent("rabbitBreeding")))


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"rabbit_pens.process", __t)


func _process_timed(delta: float) -> void:
	if world.props.version != _looked_at:
		_looked_at = world.props.version
		_look()
	var breed_hours := _breed_hours() if not pens.is_empty() else 0.0
	for p in pens.values():
		# A litter: one more, every so often, while there are two.
		var st := _state(p)
		if st.count >= 2 and st.count < MOST and _hours() - float(st.bredAt) >= breed_hours:
			st.count += 1
			st.bredAt = _hours()
			FloatingText.spawn(world, "A new rabbit in the pen!", p.at + Vector2(0, -1.0 * world.px), Color(0.9, 0.8, 0.6))
		_show(p, int(st.count), delta)


# The pens among the placed props: new ones are built, gone ones taken down (and the fences round them redone).
func _look() -> void:
	var seen := {}
	for at in world.props_named("RabbitPen"):
		var k := _key(at)
		seen[k] = true
		if not pens.has(k):
			var p := Pen.new()
			p.at = at
			p.key = k
			p.cell = world.floors.cell_at(at)
			pens[k] = p
	for k in pens.keys():
		if not seen.has(k):
			_clear(pens[k])
			pens.erase(k)
			states.erase(k)
	for p in pens.values():
		_build(p)


func _clear(p: Pen) -> void:
	for n in p.nodes:
		if is_instance_valid(n):
			n.queue_free()
	p.nodes.clear()
	for h in p.hoppers:
		if is_instance_valid(h[0]):
			h[0].queue_free()
	p.hoppers.clear()


func _covers(p: Pen, c: Vector2i) -> bool:
	return absi(c.x - p.cell.x) <= 1 and absi(c.y - p.cell.y) <= 1


func _other_pen_on(me: Pen, c: Vector2i) -> bool:
	for p in pens.values():
		if p != me and _covers(p, c):
			return true
	return false


# The fence: the Fence wall's pieces on the 12 edges round the 3x3 tiles centred on the pen's own; a side that runs
# along another pen is left open. And the burrow near the back corner.
func _build(p: Pen) -> void:
	var hoppers := p.hoppers
	p.hoppers = []
	for n in p.nodes:
		if is_instance_valid(n):
			n.queue_free()
	p.nodes.clear()
	p.hoppers = hoppers
	var walls := world.walls
	var fence: Dictionary = walls.types.get("Fence", {})
	var body := StaticBody2D.new()
	body.name = "PenFence"
	world.add_child(body)
	p.nodes.append(body)
	var low := p.cell - Vector2i.ONE
	for i in 3:
		_side(p, body, fence, WallMap.Edge.new(low + Vector2i(i, 0), false), low + Vector2i(i, -1))
		_side(p, body, fence, WallMap.Edge.new(low + Vector2i(i, 3), false), low + Vector2i(i, 3))
		_side(p, body, fence, WallMap.Edge.new(low + Vector2i(0, i), true), low + Vector2i(-1, i))
		_side(p, body, fence, WallMap.Edge.new(low + Vector2i(3, i), true), low + Vector2i(3, i))
	var burrow := int(s.get("burrow", -1))
	if burrow >= 0:
		var b := Sprite2D.new()
		world.show_frame(b, burrow, Vector2.ONE * float(s.burrowScale))
		var holder := Node2D.new()
		holder.position = world.floors.cell_centre(p.cell) + Vector2(0.05, -0.42) * world.px
		holder.add_child(b)
		world.add_ground_layer(holder, -9985)
		p.nodes.append(holder)


func _side(p: Pen, body: StaticBody2D, fence: Dictionary, e: WallMap.Edge, outside: Vector2i) -> void:
	if _other_pen_on(p, outside):
		return
	var walls := world.walls
	var a := walls.vertex_position(e.vertex)
	var b := walls.vertex_position(e.end())
	var shape := CollisionShape2D.new()
	var seg := SegmentShape2D.new()
	seg.a = a
	seg.b = b
	shape.shape = seg
	body.add_child(shape)
	if fence.is_empty():
		return
	var own_y: bool = e.along_y and int(fence.leftY) >= 0
	var art := int(fence.leftY if own_y else fence.left)
	if art < 0:
		return
	var holder := Node2D.new()
	holder.position = (a + b) / 2.0
	var sprite := Sprite2D.new()
	world.show_frame(sprite, art, Vector2(-1 if e.along_y and not own_y else 1, 1))
	holder.add_child(sprite)
	world.things.add_child(holder)
	p.nodes.append(holder)


# The rabbits inside: as many as it holds, sitting and hopping about the hay.
func _show(p: Pen, n: int, delta: float) -> void:
	while p.hoppers.size() < n:
		var sp := Sprite2D.new()
		var holder := Node2D.new()
		holder.add_child(sp)
		world.things.add_child(holder)
		var at := _spot(p)
		p.hoppers.append([holder, at, at, Rabbit.now() + randf_range(0.5, 3.0), 0.0, false, false, false])
	while p.hoppers.size() > n:
		var last: Array = p.hoppers.pop_back()
		if is_instance_valid(last[0]):
			last[0].queue_free()
	var t := Rabbit.now()
	for h in p.hoppers:
		if not h[5] and t >= h[3]:
			h[2] = _spot(p)
			h[5] = true
			h[4] = 0.0
			var dd: Vector2 = h[2] - h[1]
			h[6] = dd.y < -0.02 * world.px
			h[7] = dd.x > 0.0
		var frame: int
		if h[5]:
			h[4] += delta * 9.0
			frame = HOP_FRAMES[floori(h[4]) % HOP_FRAMES.size()]
			if frame == 4 or frame == 5:
				h[1] = (h[1] as Vector2).move_toward(h[2], 1.6 * world.px * delta)
			if (h[1] as Vector2).distance_to(h[2]) < 0.02 * world.px and frame == 6:
				h[5] = false
				h[3] = t + randf_range(1.5, 5.0)
		else:
			var twitch := fposmod(t * 0.7 + h[1].x / world.px * 3.0, 4.0)
			frame = 1 if twitch < 0.15 else (2 if twitch > 2.0 and twitch < 2.12 else 0)
		var sheet: Array = s.back if h[6] else s.front
		var k := float(s.rabbitScale)
		var holder: Node2D = h[0]
		holder.position = h[1]
		world.show_frame(holder.get_child(0), int(sheet[frame]), Vector2(-k if h[7] else k, k))


# Somewhere on the hay inside the fence (the inner part of the 3x3 diamond).
func _spot(p: Pen) -> Vector2:
	var c := world.floors.cell_centre(p.cell)
	var u := randf_range(-1.0, 1.0) * 1.05
	var v := randf_range(-1.0, 1.0) * 1.05
	# Tile axes on the ground: +x is (0.5, 0.25) a tile, +y is (-0.5, 0.25) (y up in Unity: down here).
	return c + Vector2(0.5 * (u - v), -0.25 * (u + v)) * world.px
