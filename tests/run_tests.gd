extends Node
## Headless test runner, every check is a plain assertion, exit code 1 on any failure.
## Runs the pure builders, the nodes against a fake client, and one live request when TYPESAFE_API_KEY is set.

var failures := 0
var checks := 0


func _ready() -> void:
	print("start")
	_test_catalog_validate()
	print("validate done")
	_test_build_pick_and_rank()
	print("pick done")
	_test_build_and_fill_args()
	print("args done")
	await _test_action_picker_with_fake()
	print("picker fake done")
	await _test_free_text_choice_with_fake()
	print("ftc fake done")
	await _test_live()
	print("live done")
	print("checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


# Waits up to max_frames for the dictionary to get something in it
func wait_for(d: Dictionary, max_frames: int = 900) -> void:
	for i in range(max_frames):
		if not d.is_empty():
			return
		await get_tree().process_frame


func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		push_error("FAIL: " + what)
		print("FAIL: " + what)


func _catalog() -> ActionCatalog:
	return ActionCatalog.from_dict({
		"context": "A small smart home.",
		"actions": [
			{"name": "lights", "description": "Turn a light on or off", "aliases": ["lamp"], "args": [
				{"name": "room", "description": "the room", "options": ["kitchen", "porch"], "required": true},
				{"name": "state", "description": "on or off", "options": ["on", "off"], "required": true, "default": "on"},
			]},
			{"name": "music", "description": "Play music", "args": [{"name": "genre", "options": ["jazz", "rock"], "required": true}]},
		],
	})


func _test_catalog_validate() -> void:
	check(_catalog().validate() == "", "a good catalog validates")
	check(ActionCatalog.from_dict({"actions": []}).validate() != "", "empty catalog is rejected")
	check(ActionCatalog.from_dict({"actions": [{"name": "none", "description": "x"}]}).validate() != "", "reserved name is rejected")
	check(ActionCatalog.from_dict({"actions": [{"name": "a", "description": "x", "args": [{"name": "r"}]}]}).validate() != "", "arg without options is rejected")
	check(ActionCatalog.from_dict({"actions": [{"name": "a", "description": "x", "args": [{"name": "r", "options": ["1"]}, {"name": "R", "options": ["1"]}]}]}).validate() != "", "duplicate arg ignoring case is rejected")


func _test_build_pick_and_rank() -> void:
	var req := ActionPicker.build_pick(_catalog(), "turn the lamp on")
	var opts: Dictionary = req["questions"]["pick"]["criteria"]
	check(opts.size() == 3 and opts.has(JevClient.NONE), "pick has every action plus none")
	check(str(opts["lights"]).contains("lamp"), "aliases are folded into the description")
	check(req["state"]["context"] == "A small smart home.", "context rides along")
	var ranked := ActionPicker.rank({"pick": {"choice": "music", "probabilities": {"music": 0.6, "lights": 0.3, "none": 0.1}}}, _catalog())
	check(ranked[0]["name"] == "music" and ranked[1]["name"] == "lights", "ranked highest first")


func _test_build_and_fill_args() -> void:
	var action: Dictionary = _catalog().find("lights")
	var req := ActionPicker.build_args(action, "porch please", "")
	check((req["questions"] as Dictionary).size() == 2, "one question per arg")
	check(req["questions"]["room"]["criteria"]["2"] == "porch", "options are numbered")
	var filled := ActionPicker.fill_args({
		"room": {"choice": "2", "probabilities": {"2": 0.9}},
		"state": {"choice": "none", "probabilities": {"none": 0.8}},
	}, action, 0.5)
	check(filled["room"] == "porch", "picked arg is read back")
	check(filled["state"] == "on", "not stated falls back to the default")
	var weak := ActionPicker.fill_args({"room": {"choice": "2", "probabilities": {"2": 0.2}}}, action, 0.5)
	check(weak["room"] == "", "a pick under the floor is empty")


func _test_action_picker_with_fake() -> void:
	var client := JevClient.new()
	client.fake = func(_state, questions):
		if questions.has("pick"):
			return {"pick": {"choice": "lights", "probabilities": {"lights": 0.9, "music": 0.05, "none": 0.05}}, "wants_help": {"noul": 0.02}}
		return {"room": {"choice": "2", "probabilities": {"2": 0.95}}, "state": {"choice": "2", "probabilities": {"2": 0.9}}}
	client.name = "FakeClientA"
	add_child(client)
	var picker := ActionPicker.new()
	picker.catalog = _catalog()
	add_child(picker)
	picker.client_path = client.get_path()
	var got := {}
	picker.picked.connect(func(n, a, r): got.merge({"name": n, "args": a, "ranked": r}, true))
	picker.failed.connect(func(e): print("picker failed: ", e))
	picker.decide("porch light off")
	await wait_for(got)
	check(got.get("name", "") == "lights", "picker emits the action")
	check(got.get("args", {}).get("room", "") == "porch" and got["args"]["state"] == "off", "picker fills the args")
	check((got.get("ranked", []) as Array).size() == 2, "picker hands back the ranking")

	# Nothing fits when none wins
	client.fake = func(_state, _q): return {"pick": {"choice": "none", "probabilities": {"none": 0.9}}, "wants_help": {"noul": 0.8}}
	var nothing := {}
	picker.nothing_fits.connect(func(r, h): nothing.merge({"ranked": r, "help": h}, true))
	picker.decide("what can you do")
	await wait_for(nothing)
	check(nothing.get("help", 0.0) == 0.8, "nothing fits carries the help flag")
	remove_child(picker)
	remove_child(client)
	picker.free()
	client.free()


func _test_free_text_choice_with_fake() -> void:
	var client := JevClient.new()
	client.fake = func(_state, _q): return {"pick": {"choice": "1", "probabilities": {"1": 0.85}}, "wants_help": {"noul": 0.05}, "off_topic": {"noul": 0.02}}
	client.name = "FakeClientB"
	add_child(client)
	var ftc := FreeTextChoice.new()
	add_child(ftc)
	ftc.client_path = client.get_path()
	var hit := {}
	ftc.matched.connect(func(i, p): hit.merge({"index": i, "p": p}, true))
	ftc.failed.connect(func(e): print("ftc failed: ", e))
	ftc.decide("I walk out of here", ["Look around", "Leave"], [[], ["go out"]])
	await wait_for(hit)
	check(hit.get("index", -1) == 1 and hit.get("p", 0.0) == 0.85, "free text choice emits the index")
	var req := FreeTextChoice.build("x", ["Look around", "Leave"], [[], ["go out"]], ["You wake."])
	check(str(req["questions"]["pick"]["criteria"]["1"]).contains("go out"), "aliases fold into the option")
	var shaped := FreeTextChoice.shape({"pick": {"choice": "0", "probabilities": {"0": 0.3}}}, 2, 0.5)
	check(shaped["reason"] == "unsure", "a weak pick is unsure")
	remove_child(ftc)
	remove_child(client)
	ftc.free()
	client.free()


func _test_live() -> void:
	if OS.get_environment("TYPESAFE_API_KEY") == "":
		print("live: skipped, no key")
		return
	var client := JevClient.new()
	client.name = "LiveClient"
	add_child(client)
	var picker := ActionPicker.new()
	picker.catalog = _catalog()
	add_child(picker)
	picker.client_path = client.get_path()
	var got := {}
	picker.picked.connect(func(n, a, _r): got.merge({"name": n, "args": a}, true))
	picker.failed.connect(func(e): got.merge({"error": e}, true))
	picker.nothing_fits.connect(func(r, _h): got.merge({"nothing": r}, true))
	picker.decide("turn the porch light off")
	await wait_for(got, 3600)
	check(got.get("name", "") == "lights" and got.get("args", {}).get("room", "") == "porch" and got["args"]["state"] == "off", "live: porch light off picks lights porch off, got " + str(got))

	var ftc := FreeTextChoice.new()
	add_child(ftc)
	ftc.client_path = client.get_path()
	var hit := {}
	ftc.matched.connect(func(i, p): hit.merge({"index": i, "p": p}, true))
	ftc.unmatched.connect(func(r, h, o): hit.merge({"index": -1, "reason": r, "help": h, "off": o}, true))
	ftc.failed.connect(func(e): hit.merge({"index": -1, "error": e}, true))
	ftc.decide("head up the tower to check the lamp", ["Go inside the cottage", "Climb the lighthouse", "Call out"])
	await wait_for(hit, 3600)
	check(hit.get("index", -1) == 1, "live: tower sentence maps to climb, got " + str(hit))
