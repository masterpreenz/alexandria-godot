extends Scenario
## Villagers' requests: one wants a pouch (a ! over their head), Sera hears them out and gives her word (in the
## journal), then hands a Sachet over: they carry more, she's thanked with gold. Then the whole village wants pouches:
## Sachets put in storage go to those without, and it's settled once all have one. Run with --window=requests.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _choices(t: Talk) -> Array:
	var out := []
	for c in t._choices.get_children():
		if not c.is_queued_for_deletion():
			out.append((c as Button).text)
	return out


func run() -> void:
	await _secs(1.0)
	var req := Requests.active
	print("Requests: founded ", world.village.founded(), ", villagers ", Villager.all.size())
	var carriers: Array = Villager.all.filter(func(v): return is_instance_valid(v) and not v.person.has("unique") and Villager.jobs_of(v.person).any(func(j): return Requests.CARRIERS.has(j)))
	print("Requests: workers who carry ", carriers.size())
	if carriers.is_empty():
		return
	for v in carriers:
		v.person["bag"] = ""
		v.person["bagSlots"] = 0
	var v: Villager = carriers[0]
	var key := req.offer(req.by_id["pouch"], v)
	print("Requests: offered ", key, " by ", v.person.name, " (state ", v.state, "), emote ", v._rumor_emote())
	# Sera goes to them and talks.
	miko.position = v.position + Vector2(0.6, 0.3) * world.px
	var t := Talk.active
	t.open(v)
	await _secs(0.3)
	print("Requests: talk choices ", _choices(t))
	t._ask_request(key)
	await _secs(0.3)
	print("Requests: they say \"", t._line.text, "\", replies ", _choices(t))
	shot("ask")
	t._accept_request(key)
	print("Requests: after her word: ", req.asks[key].state, ", in the journal ", req.listed().has(key), ", emote now '", v._rumor_emote(), "'")
	# A Sachet in her bag: handing it over.
	var slot := miko.bag.free_slot()
	miko.bag.items[slot] = "Sachet"
	miko.bag.changed.emit()
	var gold := miko.bag.count("Gold")
	t.open(v)
	await _secs(0.3)
	print("Requests: talk choices with a Sachet ", _choices(t))
	t._give_request(key)
	await _secs(0.3)
	print("Requests: thanks \"", t._line.text, "\"; ", v.person.name, " bag ", v.person.bag, " +", v.person.bagSlots, " slots; state ", req.asks[key].state, "; gold ", gold, " -> ", miko.bag.count("Gold"), "; Sachet still in her bag ", miko.bag.items.has("Sachet"))
	shot("thanks")
	t.close()
	# The whole village: pouches for every worker.
	req._raise_every()
	var every := "pouches_all"
	print("Requests: whole-village ask offered ", req.asks.has(every), " by ", req.asks.get(every, {}).get("by", "-"), ", progress ", req.progress(every) if req.asks.has(every) else Vector2i.ZERO)
	if not req.asks.has(every):
		return
	req.accept(every)
	var p := req.progress(every)
	for i in p.y - p.x - 1:
		world.village.items.append("Sachet")
	world.village.changed.emit()
	await _secs(float(p.y - p.x) + 1.5)
	print("Requests: after ", p.y - p.x - 1, " Sachets in storage: progress ", req.progress(every), ", state ", req.asks[every].state, ", Sachets left in storage ", world.village.items.count("Sachet"))
	# The last one, handed over in a talk.
	var last: Villager = null
	for c in carriers:
		if req.wanting(c.person, "bag"):
			last = c
	if last != null:
		miko.bag.items[miko.bag.free_slot()] = "Sachet"
		gold = miko.bag.count("Gold")
		miko.position = last.position + Vector2(0.6, 0.3) * world.px
		t.open(last)
		await _secs(0.3)
		print("Requests: last one's choices ", _choices(t))
		print("Requests: handed over: \"", req.give(req.open_for(last), last), "\"; state ", req.asks[every].state, "; gold ", gold, " -> ", miko.bag.count("Gold"))
		t.close()
	# The journal.
	var j: Array = g.find_children("*", "RumorsWindow", true, false)
	if not j.is_empty():
		var w: RumorsWindow = j[0]
		w.chosen = "req:" + every
		w.open()
		await _secs(0.5)
		shot("journal")
		w.close()
	print("Requests: listed ", req.listed())
