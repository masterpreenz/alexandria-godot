extends Scenario
## Every water mesh: how much of it (triangle middles) the depth map, and so the spawners, know is water.
## Run with --window=watercover.


func run() -> void:
	for n in get_tree().root.find_children("*", "MeshInstance2D", true, false):
		var mi := n as MeshInstance2D
		if mi.mesh == null or not (mi.material is ShaderMaterial) or str(mi.name).begins_with("Cliffs"):
			continue
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector2Array = arr[Mesh.ARRAY_VERTEX]
		var t: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var known := 0
		var tris := 0
		var dry_at := []
		for k in range(0, t.size(), 3):
			var c := mi.global_transform * ((v[t[k]] + v[t[k + 1]] + v[t[k + 2]]) / 3.0)
			tris += 1
			if world.wet(c):
				known += 1
			elif dry_at.size() < 3:
				dry_at.append(world.floors.cell_at(c))
		print("Water ", mi.name, ": ", known, " of ", tris, " known as water; not: ", dry_at)
