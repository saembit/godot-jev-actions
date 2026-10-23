# godot-jev-actions

[img](path)

Jev decisions as Godot nodes, your code runs them

# TOC
- [About](#about)
- [Install](#install)
- [Nodes](#nodes)
- [The catalog](#the-catalog)
- [Testing](#testing)
- [Todo](#todo)

# About

godot-jev-actions is a Godot 4 addon with three nodes and a resource on top of Jev, the TypeSafe model that gives back a probability for each answer you define instead of writing text. ActionCatalog is the allowlist of things an NPC or a command box may do, each action with a description and arguments whose values are a closed list, ActionPicker takes a sentence or a dictionary of game state and emits one allowed action with its arguments filled, or nothing_fits, and FreeTextChoice takes whatever the player typed and emits which of your authored choices they meant, or none. Jev can only pick from what you listed so it can never make the game do something you didn't write, and since every answer comes with a probability your code decides how sure is sure enough. If you want the raw api in GDScript, AlvianEka's godot-jev on the Asset Library is the SDK, this one is the designer facing layer with the question packs from jeff-act and jeff-ink. It may not be perfect but it's better than nothing.

Not affiliated with TypeSafe or Godot.

# Install

Copy addons/jev_actions into your project and enable Jev Actions under Project, Project Settings, Plugins. Set the key on the JevClient node, or as the jev/api_key project setting, or in the TYPESAFE_API_KEY environment variable. A shipped game should not carry the key, point BASE_URL at a proxy you run, see the todo.

# Nodes

JevClient sends one request with a state and a map of typed questions and returns the answers, retries 429, 529 and 5xx with a short wait, and has a fake Callable for tests so nothing leaves the machine.

ActionPicker needs a catalog and a JevClient (the client_path export, or a sibling or child). decide(input) sends two requests, one choice over the actions plus none with a wants_help yes/no alongside, then one choice per argument of the winner over its options plus not stated. It emits picked(action_name, args, ranked) when the winner clears floor and every required argument is filled, nothing_fits(ranked, wants_help) otherwise, failed(error) when the api did. ranked is every action with its probability so you can fall through to the next one yourself.

```gdscript
picker.catalog = ActionCatalog.from_dict({
	"context": "A small smart home.",
	"actions": [
		{"name": "lights", "description": "Turn a light on or off", "aliases": ["lamp"], "args": [
			{"name": "room", "description": "the room", "options": ["kitchen", "porch"], "required": true},
			{"name": "state", "description": "on or off", "options": ["on", "off"], "required": true},
		]},
	],
})
picker.picked.connect(func(action, args, _ranked): do_thing(action, args))
picker.decide("dim the porch lamp")
```

FreeTextChoice takes the text and an array of choice strings, plus an optional array of alias arrays, and emits matched(index, probability), unmatched(reason, wants_help, off_topic) where reason is none or unsure, or failed(error). context_lines is a few recent lines of dialogue that give the choices context. It is the Godot version of jeff-ink.

```gdscript
ftc.decide(line_edit.text, ["Go inside the cottage", "Climb the lighthouse", "Call out"], [["enter", "walk in"], ["go up", "take the stairs"], ["shout", "yell"]])
```

# The catalog

A catalog is an ActionCatalog resource, edited in the inspector or built from a dictionary with the same shape as jeff-act's yaml, context, then actions with name, description, aliases and args, each arg with name, description, options and required. Every argument is a closed set because Jev picks but never writes, if a value has to come from the sentence find the candidates in code first and put them in options before calling decide. validate() tells you what is wrong with a catalog.

# Testing

```bash
godot --headless --path . --import      # once, builds the class cache
godot --headless --path .               # runs tests/run_tests.tscn, exit 1 on a failure
```

The pure builders and the nodes against a fake client always run, the live checks run when TYPESAFE_API_KEY is set.

# Todo

- [ ] Add the image
- [ ] A proxy mode so a shipped game never holds the key
- [ ] A DialogueRouter node that picks the next line from a set given the conversation so far
- [ ] A Director node, a score of player frustration and skill from an event log, for pacing
- [ ] Images in the state now that Jev 1.14 takes them, a screenshot as game state
- [ ] Asset Library listing
