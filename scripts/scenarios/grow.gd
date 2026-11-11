extends Scenario
## The "grow" scenario.
## Run with --window=grow.


func run() -> void:
	vd.growth.begin()
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.75, 0.3))
