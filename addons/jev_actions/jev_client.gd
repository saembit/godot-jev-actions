@icon("res://addons/jev_actions/icon.svg")
class_name JevClient
extends Node
## Sends a state and typed questions to TypeSafe's Jev and hands back the answers.
## The key comes from the api_key export, the jev/api_key project setting, or the TYPESAFE_API_KEY env var, in that order.

# The api root
const BASE_URL := "https://api.typesafe.ai"

# The option name that means nothing fits, shared by the nodes
const NONE := "none"

## The api key, leave empty to read the project setting or the env var
@export var api_key: String = ""
## The model alias or versioned id
@export var model: String = "jev-latest"
## Seconds before a request gives up
@export var timeout: float = 20.0
## Retries after the first attempt on 429, 529 and 5xx
@export var max_retries: int = 2

# A fake for tests, when set the request never leaves the machine
var fake: Callable


## Asks one request and returns the answers dictionary, or an empty dictionary with "error" set.
func ask(state: Variant, questions: Dictionary) -> Dictionary:
	# Nothing to ask
	if questions.is_empty():
		return {"error": "no questions"}

	# The test double
	if fake.is_valid():
		return await fake.call(state, questions)

	# The key from the export, the project setting or the env
	var key := _key()
	if key == "":
		return {"error": "missing api key, set JevClient.api_key, the jev/api_key project setting, or TYPESAFE_API_KEY"}

	# The body
	var body := JSON.stringify({"model": model, "state": state, "questions": questions})
	var headers := PackedStringArray(["Authorization: Bearer " + key, "Content-Type: application/json"])

	# The first attempt and the retries
	var last_error := ""
	for attempt in range(max_retries + 1):
		# Wait before every attempt after the first
		if attempt > 0:
			await get_tree().create_timer(0.5 * pow(2.0, attempt - 1)).timeout

		# One request node per attempt
		var http := HTTPRequest.new()
		http.timeout = timeout
		add_child(http)
		var err := http.request(BASE_URL + "/v1/systemone", headers, HTTPClient.METHOD_POST, body)
		if err != OK:
			http.queue_free()
			return {"error": "request failed to start: " + str(err)}
		var result: Array = await http.request_completed
		http.queue_free()

		# The pieces of the signal
		var code: int = result[1]
		var raw: PackedByteArray = result[3]

		# Try again on a rate limit or overload
		if code == 429 or code == 529 or code >= 500:
			last_error = "HTTP " + str(code)
			continue

		# Anything else that isn't 2xx is final
		if code < 200 or code >= 300:
			return {"error": "HTTP " + str(code) + ": " + raw.get_string_from_utf8().left(200)}

		# Decode the answers
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		if parsed == null or not parsed.has("answers"):
			return {"error": "response had no answers"}
		return parsed["answers"]

	# Every attempt failed
	return {"error": last_error if last_error != "" else "request failed"}


# Finds the key from the export, the project setting or the env
func _key() -> String:
	if api_key != "":
		return api_key
	if ProjectSettings.has_setting("jev/api_key"):
		var s: String = str(ProjectSettings.get_setting("jev/api_key"))
		if s != "":
			return s
	return OS.get_environment("TYPESAFE_API_KEY")
