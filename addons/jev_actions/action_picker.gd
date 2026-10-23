@icon("res://addons/jev_actions/icon.svg")
class_name ActionPicker
extends Node
## Turns a sentence or a game state into one allowed action from the catalog with its arguments filled from their option lists.
## Two requests, one choice over the actions plus none, then one choice per argument of the winner.
## Emits picked(action_name, args, ranked) or nothing_fits(ranked, wants_help) or failed(error).

## The catalog of allowed actions
@export var catalog: ActionCatalog
## The JevClient node that sends requests, the first JevClient sibling or child when empty
@export var client_path: NodePath
## The probability the winning action needs, under it nothing_fits is emitted
@export_range(0.0, 1.0) var floor: float = 0.35
## The probability an argument pick needs, under it the argument is left empty
@export_range(0.0, 1.0) var arg_floor: float = 0.5

## An action was picked with every required argument filled
signal picked(action_name: String, args: Dictionary, ranked: Array)
## Nothing in the catalog fit well enough, ranked is every action with its probability
signal nothing_fits(ranked: Array, wants_help: float)
## The request failed
signal failed(error: String)


## Asks Jev which action the input means and fills its arguments. input is a sentence or a dictionary of game state.
func decide(input: Variant) -> void:
	# The pieces have to be there
	var client := _client()
	if client == null:
		failed.emit("no JevClient found")
		return
	if catalog == null:
		failed.emit("no catalog")
		return
	var problem := catalog.validate()
	if problem != "":
		failed.emit(problem)
		return

	# Which action
	var pick_req := build_pick(catalog, input)
	var answers: Dictionary = await client.ask(pick_req["state"], pick_req["questions"])
	if answers.has("error"):
		failed.emit(str(answers["error"]))
		return
	var ranked := rank(answers, catalog)
	var wants_help: float = float((answers.get("wants_help", {}) as Dictionary).get("noul", 0.0))
	if ranked.is_empty() or float(ranked[0]["probability"]) < floor:
		nothing_fits.emit(ranked, wants_help)
		return

	# Its arguments
	var action: Dictionary = catalog.find(str(ranked[0]["name"]))
	var args := {}
	var arg_req := build_args(action, input, catalog.context)
	if not (arg_req["questions"] as Dictionary).is_empty():
		var arg_answers: Dictionary = await client.ask(arg_req["state"], arg_req["questions"])
		if arg_answers.has("error"):
			failed.emit(str(arg_answers["error"]))
			return
		args = fill_args(arg_answers, action, arg_floor)
	else:
		args = fill_args({}, action, arg_floor)

	# Required arguments have to be there
	for g in action.get("args", []):
		if g.get("required", false) and str(args.get(g["name"], "")) == "":
			nothing_fits.emit(ranked, wants_help)
			return

	# Done
	picked.emit(str(action["name"]), args, ranked)


## Makes the state and the one choice over the actions plus none, with a help noul alongside
static func build_pick(cat: ActionCatalog, input: Variant) -> Dictionary:
	var listed := {}
	var options := {}
	for a in cat.actions:
		var desc := str(a.get("description", ""))
		var aliases: Array = a.get("aliases", [])
		if not aliases.is_empty():
			desc += ". Also called: " + ", ".join(PackedStringArray(aliases))
		listed[a["name"]] = desc
		options[a["name"]] = desc
	options[JevClient.NONE] = "Nothing in actions is what the input asks for"
	var state := {"input": input, "actions": listed}
	if cat.context != "":
		state["context"] = cat.context
	return {
		"state": state,
		"questions": {
			"pick": {"type": "choice", "instructions": "Which entry in `actions` is `input` asking for or calling for? The input may use different words than the description.", "criteria": options},
			"wants_help": {"type": "noul", "instructions": "Is `input` asking what can be done, for a list of options, or how this works?"},
		},
	}


## Turns the pick answer into every action ranked highest first
static func rank(answers: Dictionary, cat: ActionCatalog) -> Array:
	var probs: Dictionary = (answers.get("pick", {}) as Dictionary).get("probabilities", {})
	var out := []
	for a in cat.actions:
		out.append({"name": a["name"], "probability": float(probs.get(a["name"], 0.0))})
	out.sort_custom(func(x, y): return x["probability"] > y["probability"] if x["probability"] != y["probability"] else str(x["name"]) < str(y["name"]))
	return out


## Makes the state and one choice per argument over its options plus not stated
static func build_args(action: Dictionary, input: Variant, context: String) -> Dictionary:
	var questions := {}
	var candidates := {}
	for g in action.get("args", []):
		var opts: Array = g.get("options", [])
		candidates[g["name"]] = opts
		var criteria := {}
		for i in range(opts.size()):
			criteria[str(i + 1)] = str(opts[i])
		criteria[JevClient.NONE] = "The input does not say"
		questions[g["name"]] = {
			"type": "choice",
			"instructions": {"argument": str(g.get("description", g["name"])), "question": "For the action \"%s\", which candidate in `candidates.%s` is the value of this argument given `input`?" % [str(action.get("description", "")), str(g["name"])]},
			"criteria": criteria,
		}
	var state := {"input": input, "action": str(action.get("description", "")), "candidates": candidates}
	if context != "":
		state["context"] = context
	return {"state": state, "questions": questions}


## Reads the numbered picks back into values, empty when not stated or under the floor
static func fill_args(answers: Dictionary, action: Dictionary, floor_p: float) -> Dictionary:
	var out := {}
	for g in action.get("args", []):
		var opts: Array = g.get("options", [])
		var value := str(g.get("default", ""))
		var a: Dictionary = answers.get(g["name"], {})
		var pick := str(a.get("choice", ""))
		if pick != "" and pick != JevClient.NONE and pick.is_valid_int():
			var idx := int(pick)
			var p: float = float((a.get("probabilities", {}) as Dictionary).get(pick, 0.0))
			if idx >= 1 and idx <= opts.size() and p >= floor_p:
				value = str(opts[idx - 1])
		out[g["name"]] = value
	return out


# Finds the client, the export first, then a sibling or child named or typed JevClient
func _client() -> JevClient:
	if client_path != NodePath(""):
		return get_node_or_null(client_path) as JevClient
	for n in get_children():
		if n is JevClient:
			return n
	var parent := get_parent()
	if parent != null:
		for n in parent.get_children():
			if n is JevClient:
				return n
	return null
