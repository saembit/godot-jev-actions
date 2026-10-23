extends Node
## The smallest wiring, a catalog, a client, a picker, and a line of text.

@onready var client: JevClient = $JevClient
@onready var picker: ActionPicker = $ActionPicker


func _ready() -> void:
	picker.catalog = ActionCatalog.from_dict({
		"context": "A small smart home. Rooms are kitchen, porch, bedroom and office.",
		"actions": [
			{"name": "lights", "description": "Turn a light in a room on or off", "aliases": ["lamp", "lighting"], "args": [
				{"name": "room", "description": "the room", "options": ["kitchen", "porch", "bedroom", "office"], "required": true},
				{"name": "state", "description": "on or off", "options": ["on", "off"], "required": true},
			]},
			{"name": "music", "description": "Play music in a room", "aliases": ["song", "tunes"], "args": [
				{"name": "genre", "description": "the kind of music", "options": ["jazz", "rock", "lofi"], "required": true},
			]},
		],
	})
	picker.picked.connect(func(action, args, _ranked): print("do ", action, " with ", args))
	picker.nothing_fits.connect(func(_ranked, help): print("nothing fits", ", they want help" if help > 0.5 else ""))
	picker.failed.connect(func(err): push_error(err))
	picker.decide("dim the porch lamp")
