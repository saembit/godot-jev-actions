@icon("res://addons/jev_actions/icon.svg")
class_name FreeTextChoice
extends Node
## Maps whatever the player typed to one of the choices you offer, or none, so a text box can drive an authored branch.
## One request, a choice over the options plus none, with help and off topic nouls alongside.
## Emits matched(index, probability) or unmatched(reason, wants_help, off_topic) or failed(error).

## The JevClient node that sends requests, the first JevClient sibling or child when empty
@export var client_path: NodePath
## The probability the winning choice needs
@export_range(0.0, 1.0) var threshold: float = 0.5
## Recent lines of story or dialogue that give the choices context, optional
@export var context_lines: Array[String] = []

## The player meant choice index
signal matched(index: int, probability: float)
## Nothing matched, reason is none or unsure
signal unmatched(reason: String, wants_help: float, off_topic: float)
## The request failed
signal failed(error: String)


## Asks which of the choices the text means. choices is an array of strings, aliases is an optional array of arrays of extra wordings per choice.
func decide(text: String, choices: Array, aliases: Array = []) -> void:
	var client := _client()
	if client == null:
		failed.emit("no JevClient found")
		return
	if choices.is_empty():
		unmatched.emit("none", 0.0, 0.0)
		return
	var req := build(text, choices, aliases, context_lines)
	var answers: Dictionary = await client.ask(req["state"], req["questions"])
	if answers.has("error"):
		failed.emit(str(answers["error"]))
		return
	var d := shape(answers, choices.size(), threshold)
	if d["index"] >= 0:
		matched.emit(d["index"], d["probability"])
	else:
		unmatched.emit(d["reason"], d["wants_help"], d["off_topic"])


## Makes the state and questions for one line of text
static func build(text: String, choices: Array, aliases: Array, recent: Array) -> Dictionary:
	var listed := {}
	var criteria := {}
	for i in range(choices.size()):
		listed[str(i)] = str(choices[i])
		var extra: Array = aliases[i] if i < aliases.size() and aliases[i] is Array else []
		criteria[str(i)] = (str(choices[i]) + ". Also: " + ", ".join(PackedStringArray(extra))) if not extra.is_empty() else null
	criteria[JevClient.NONE] = "Nothing listed is what the player is trying to do"
	var state := {"player_input": text, "recent": recent, "choices": listed}
	return {
		"state": state,
		"questions": {
			"pick": {"type": "choice", "instructions": "Which entry in `choices` is what the player is trying to do with `player_input`, given `recent`? The player may use different words than the choice text.", "criteria": criteria},
			"wants_help": {"type": "noul", "instructions": "Is `player_input` asking what they can do, for a hint, or how the game works?"},
			"off_topic": {"type": "noul", "instructions": "Is `player_input` about something outside the game, such as talking to the developer or the real world?"},
		},
	}


## Turns the answers into an index or a reason
static func shape(answers: Dictionary, count: int, threshold_p: float) -> Dictionary:
	var pick: Dictionary = answers.get("pick", {})
	var choice := str(pick.get("choice", JevClient.NONE))
	var probs: Dictionary = pick.get("probabilities", {})
	var p: float = float(probs.get(choice, 0.0))
	var out := {
		"index": -1, "reason": "none", "probability": p,
		"wants_help": float((answers.get("wants_help", {}) as Dictionary).get("noul", 0.0)),
		"off_topic": float((answers.get("off_topic", {}) as Dictionary).get("noul", 0.0)),
	}
	if choice == JevClient.NONE or not choice.is_valid_int():
		return out
	if p < threshold_p:
		out["reason"] = "unsure"
		return out
	var idx := int(choice)
	if idx < 0 or idx >= count:
		return out
	out["index"] = idx
	out["reason"] = "matched"
	return out


# Finds the client, the export first, then a sibling or child typed JevClient
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
