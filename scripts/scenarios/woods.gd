extends Scenario
## The woods by map section: how many trees, how many rotten, and the mist there.
## Run with --window=woods.


func run() -> void:
	for col in MapMarks.SECTIONS:
		for row in MapMarks.SECTIONS:
			var b := MapMarks.section_bounds(col, row)
			var trees := 0
			var rot := 0
			var tiers := [0, 0, 0]
			for gt in Gatherable.all:
				if gt.axe and not gt.depleted() and b.has_point(world.floors.cell_at(gt.foot)):
					trees += 1
					rot += 1 if gt.corrupted else 0
					tiers[world.mist.tier_at(gt.foot)] += 1
			if trees >= 6:
				print("Woods: ", MapMarks.section_name(col, row), " cells ", b, ": trees ", trees, ", rotten ", rot, ", clear/normal/strong ", tiers)
	print("Woods: village centre cell ", world.floors.cell_at(world.village.centre()))
