class_name Rescue
extends Node
## Miyu's rescue, as the rumor "The elder's granddaughter" plays out. Coming near the overrun village, its monsters are
## there (only monsters: nobody's left). Reaching it, Miyu lies in the street, unconscious. E picks her up: Sera carries
## her (slower), and setting foot back in her own village sets her down: Miyu comes to live there, and sleeps the whole
## day through. All of it in the chronicle ("miyu_home"). If the day runs out before Sera comes, the rumor says she's
## gone. What it's at is saved (world.rescue).

const WHO := "miyu"
const RUMOR := "find_miyu"
const LIES_AT := Vector2i(-250, 113)   ## in the street, by the square
const MONSTERS := {"slime": 6, "boar": 2, "mutatedVillager": 4}
const NEAR := 40.0                      ## cells from the village its monsters are met
const REACH := 1.3                      ## units from her to pick her up
const SLEEPS := 24.0                    ## game hours she sleeps once she's home
const CARRY_SLOW := -35.0               ## Sera's move speed carrying her (percent)

static var active: Rescue

var world: World
var miko: Miko
var people: Villagers
var monster_data: Dictionary
var state := ""                         ## "", "lying", "carried", "home"
var monsters_out := false
var prompt: Label
var _body: Sprite2D
var _pressed := false


func setup(w: World, who: Miko, vs: Villagers, md: Dictionary, hud: Node) -> void:
	world = w
	miko = who
	people = vs
	monster_data = md
	active = self
	prompt = HudStyle.label("", 14, "bold")
	prompt.visible = false
	hud.add_child(prompt)
	WorldPrompts.register(prompt)


func to_json() -> String:
	return JSON.stringify({"state": state, "monsters": monsters_out})


func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	if d is Dictionary:
		state = str(d.get("state", ""))
		monsters_out = bool(d.get("monsters", false))
	if state == "carried":
		_carry(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and prompt.visible:
		_pressed = true
		get_viewport().set_input_as_handled()


func _rumor() -> Dictionary:
	return Rumors.active.heard.get(RUMOR, {}) if Rumors.active != null else {}


func _process(_delta: float) -> void:
	var pressed := _pressed
	_pressed = false
	prompt.visible = false
	var st := _rumor()
	if st.is_empty() or state == "home":
		return
	var open: bool = st.state == "open"
	var village := Wildlands.WEST_VILLAGE
	var here := world.floors.cell_at(miko.position)
	# The village overrun: its monsters, as she comes near.
	if open and not monsters_out and Rect2i(village.position - Vector2i.ONE * int(NEAR), village.size + Vector2i.ONE * int(NEAR) * 2).has_point(here):
		monsters_out = true
		_monsters()
	# Reached: Miyu in the street.
	if open and state == "" and int(st.step) >= 1:
		state = "lying"
	if state == "lying":
		_show_lying()
		if not open:
			return
		var at := world.floors.cell_centre(LIES_AT)
		if miko.position.distance_to(at) < REACH * world.px and not miko.locked:
			prompt.visible = true
			prompt.text = "E  Pick up Miyu"
			WorldPrompts.at(prompt, at + Vector2(0, -0.9 * world.px))
			if pressed:
				_carry(false)
	elif state == "carried":
		_show_carried()
		# Home: she's set down, and taken in.
		if world.village.founded() and world.village.contains(miko.position):
			_home()


func _monsters() -> void:
	var area := Wildlands.WEST_VILLAGE
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for kind in MONSTERS:
		for i in int(MONSTERS[kind]):
			var c := Vector2i(rng.randi_range(area.position.x + 3, area.end.x - 4), rng.randi_range(area.position.y + 3, area.end.y - 4))
			var at := world.floors.cell_centre(c)
			match kind:
				"slime": Slime.spawn(world, monster_data.slime, rng.randf() < 0.3, at, world.mist.power(at))
				"boar": Boar.spawn(world, monster_data.boar, at)
				"mutatedVillager": MutatedVillager.spawn(world, monster_data.mutatedVillager, at)


# Her lying form: her collapsed pose (the last of her fainting frames), else her sleeping one, flat on the street.
func _frame() -> int:
	var look: Dictionary = people.d.looks[int(Uniques.all()[WHO].look)]
	var faint: Array = look.settings.get("faintDown", [])
	if not faint.is_empty():
		return int(faint[-1])
	var frames: Array = look.settings.sleepDown
	return int(frames[mini(int(look.settings.lieDownFrames), frames.size() - 1)]) if not frames.is_empty() else int(look.settings.idleDown)


func _sprite() -> Sprite2D:
	if _body == null:
		_body = Sprite2D.new()
		world.show_frame(_body, _frame(), Vector2.ONE * World.BODY_SCALE)
		world.things.add_child(_body)
	return _body


func _show_lying() -> void:
	var b := _sprite()
	b.position = world.floors.cell_centre(LIES_AT)
	b.rotation = 0.0
	b.z_as_relative = true
	b.z_index = 0


# In her arms as she walks.
func _show_carried() -> void:
	var b := _sprite()
	b.position = miko.position + Vector2((0.12 if miko.facing_right else -0.12) * world.px, -0.22 * world.px)
	b.rotation = deg_to_rad(-8.0 if miko.facing_right else 8.0)
	b.flip_h = miko.facing_right
	b.z_as_relative = false
	b.z_index = 3900


func _carry(loading: bool) -> void:
	state = "carried"
	miko.stats.set_buff("carrying", {"moveSpeed": CARRY_SLOW})
	if not loading:
		FloatingText.spawn(world, "Miyu's breathing. Get her home.", miko.position + Vector2(0, -2.0 * world.px), Color(1.0, 0.86, 0.6), 18, 2.5)
		if Chronicle.active != null:
			Chronicle.active.record("miyu_found")


func _home() -> void:
	state = "home"
	miko.stats.set_buff("carrying", null)
	if _body != null:
		_body.queue_free()
		_body = null
	Uniques.arrive(people, WHO)
	var p := Uniques.person(people, WHO)
	if not p.is_empty():
		p["restUntil"] = world.clock.hours + SLEEPS
		p["hp"] = float(p.get("maxHp", 40.0)) * 0.3
	Chronicle.active.record("miyu_home")
	FloatingText.spawn(world, "Miyu's home. She'll sleep the day through.", miko.position + Vector2(0, -2.0 * world.px), Color(0.7, 1.0, 0.7), 18, 2.5)
	VillageLog.event("miyu_home", "Miyu is home, asleep in the elder's house. The elders want to speak with you.")
