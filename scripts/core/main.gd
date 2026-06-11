# Anthesis entry point
extends Node3D


func _ready() -> void:
	var name_str: String = ProjectSettings.get_setting("application/config/name", "Anthesis")
	var version_str: String = ProjectSettings.get_setting("application/config/version", "0.1.0-dev")
	print("%s v%s" % [name_str, version_str])
