class_name Scenario
extends Node
## A test scenario: a situation set up in the running game, played out and reported on (printed lines, pictures), for
## checking a feature without playing to it. Each is a file in scripts/scenarios/, named for what it's run by:
##   Godot --path . -- --window=<name> --shot=<picture.png>
## It extends this, and its run() does the work, with the game's own parts to hand ([member world], [member miko],
## [member clock] and the rest; anything else by g.get_node("Hud/...")). The game runs it once everything's loaded.
##
## A new one: scripts/scenarios/<name>.gd with "extends Scenario" and "func run() -> void:". Nothing else to change.

const FOLDER := "res://scripts/scenarios/"
## Other names some scenarios go by (the scenario looks at Shots.arg("window") for which was asked).
const ALIASES := {"totals": "chest", "ask": "chest"}

var g: Node2D                     ## the game (scripts/game.gd)
var world: World:
	get: return g.world
var miko: Miko:
	get: return g.miko
var clock: GameClock:
	get: return g.clock
var snow: SnowCover:
	get: return g.snow
var camera: Camera2D:
	get: return g.camera
var sky: SkyEffects:
	get: return g.sky
var data: Dictionary:
	get: return g.data
var people: Villagers:
	get: return g.get_node_or_null("Villagers")
var vd: VillageDesk:
	get: return g.get_node_or_null("VillageDesk")


## Runs the scenario called [param called] in the game [param game]; says so if there's none.
static func run_named(game: Node2D, called: String) -> void:
	var file: String = FOLDER + str(ALIASES.get(called, called)) + ".gd"
	if not ResourceLoader.exists(file):
		push_warning("No scenario called '%s' (looked for %s)" % [called, file])
		return
	var s: Scenario = (load(file) as GDScript).new()
	s.g = game
	s.name = "Scenario"
	game.add_child(s)
	@warning_ignore("redundant_await")
	await s.run()
	s.queue_free()


## What the scenario does (each file's own).
func run() -> void:
	pass
