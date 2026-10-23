@tool
extends EditorPlugin

# Registers the nodes and the resource so they show up in the add node dialog
func _enter_tree() -> void:
	add_custom_type("JevClient", "Node", preload("res://addons/jev_actions/jev_client.gd"), null)
	add_custom_type("ActionPicker", "Node", preload("res://addons/jev_actions/action_picker.gd"), null)
	add_custom_type("FreeTextChoice", "Node", preload("res://addons/jev_actions/free_text_choice.gd"), null)
	add_custom_type("ActionCatalog", "Resource", preload("res://addons/jev_actions/action_catalog.gd"), null)


# Removes them again
func _exit_tree() -> void:
	remove_custom_type("JevClient")
	remove_custom_type("ActionPicker")
	remove_custom_type("FreeTextChoice")
	remove_custom_type("ActionCatalog")
