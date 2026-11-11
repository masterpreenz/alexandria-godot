extends Scenario
## Loot dropped behind a house's back wall and out in the open: which is outlined.
## Run with --window=loothidden.


func run() -> void:
	var room: Dictionary = world.roofs.roofs[0].cells
	var top := Vector2i(-99999, -99999)
	for c in room:
		if c.x + c.y > top.x + top.y:
			top = c
	var behind := world.floors.cell_centre(top + Vector2i(1, 1)) + Vector2(0, 0.2 * world.px)
	var open_at := world.village.centre() + Vector2(7.0, 5.0) * world.px
	var made := []
	for spot_at in [behind, open_at]:
		var pk := Pickup.launch_icon(world, "Crystal", 1, spot_at)
		pk.ground = spot_at
		pk.velocity = Vector2.ZERO
		pk.rise = 0.0
		pk.height = 0.0
		pk.landed_at = 0.0
		made.append(pk)
	miko.place(behind + Vector2(-3.0, 3.5) * world.px)
	for i in 60:
		await get_tree().process_frame
	print("Loot: behind the house, outlined ", (made[0].get_node("OccludedOutline") as OccludedOutline).covered, "; in the open, outlined ", (made[1].get_node("OccludedOutline") as OccludedOutline).covered)
