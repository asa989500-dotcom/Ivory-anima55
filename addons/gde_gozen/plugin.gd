@tool
class_name GoZenServer
extends EditorPlugin
## Registers the optional VideoPlayback node only when the native GoZen
## classes are loaded. This keeps the editor import/parser clean on a source
## checkout that has not compiled GoZen for the current platform.

var _registered: bool = false

func _enter_tree() -> void:
	if not ClassDB.class_exists("GoZenVideo"):
		return
	add_custom_type(
			"VideoPlayback", "Control",
			load("res://addons/gde_gozen/video_playback.gd"),
			load("res://addons/gde_gozen/icon.webp"))
	_registered = true

func _exit_tree() -> void:
	if _registered:
		remove_custom_type("VideoPlayback")
	_registered = false
