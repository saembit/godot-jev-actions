@icon("res://addons/jev_actions/icon.svg")
class_name ActionCatalog
extends Resource
## The allowlist of things an ActionPicker may pick, edited in the inspector or loaded from a dictionary.
## Each action is a dictionary with name, description, aliases (array of strings), and args, where each arg is
## a dictionary with name, description, options (the closed set of values, array of strings), and required (bool).

## Shared facts every question can see
@export_multiline var context: String = ""
## The actions, see the class comment for the shape of each one
@export var actions: Array[Dictionary] = []


## Loads a catalog from a dictionary with context and actions, same shape as jeff-act's yaml
static func from_dict(d: Dictionary) -> ActionCatalog:
	var c := ActionCatalog.new()
	c.context = str(d.get("context", ""))
	var list: Array[Dictionary] = []
	for a in d.get("actions", []):
		list.append(a)
	c.actions = list
	return c


## Gives the action with the name, or an empty dictionary
func find(action_name: String) -> Dictionary:
	for a in actions:
		if str(a.get("name", "")) == action_name:
			return a
	return {}


## Checks the catalog, returns an error string or empty when fine
func validate() -> String:
	if actions.is_empty():
		return "catalog has no actions"
	var seen := {}
	var name_re := RegEx.create_from_string("^[a-zA-Z][a-zA-Z0-9_]*$")
	for a in actions:
		var n := str(a.get("name", ""))
		if name_re.search(n) == null:
			return "action \"%s\": name must be letters, digits and underscores" % n
		if n == JevClient.NONE:
			return "action \"%s\": that name is reserved" % n
		if seen.has(n):
			return "action \"%s\": duplicate name" % n
		seen[n] = true
		if str(a.get("description", "")) == "":
			return "action \"%s\": needs a description" % n
		var arg_seen := {}
		for g in a.get("args", []):
			var gn := str(g.get("name", ""))
			if name_re.search(gn) == null:
				return "action \"%s\": arg \"%s\": bad name" % [n, gn]
			if arg_seen.has(gn.to_lower()):
				return "action \"%s\": arg \"%s\": duplicate name" % [n, gn]
			arg_seen[gn.to_lower()] = true
			if (g.get("options", []) as Array).is_empty():
				return "action \"%s\": arg \"%s\": needs options, every arg is a closed set" % [n, gn]
	return ""
