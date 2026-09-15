class_name AndroidPlatform
extends RefCounted
## One Godot-facing gateway for Ivory's Android native layer.
## The native side lives in android/plugin_src/ivory_media and remains optional
## on desktop, so editor and non-Android fallbacks keep working.

static func available() -> bool:
	return OS.has_feature("android") and Engine.has_singleton("IvoryAndroid")

static func file_picker_available() -> bool:
	return OS.has_feature("android") and Engine.has_singleton("IvoryFilePicker")

static func android() -> Object:
	if not available():
		return null
	return Engine.get_singleton("IvoryAndroid")

static func picker() -> Object:
	if not file_picker_available():
		return null
	return Engine.get_singleton("IvoryFilePicker")

static func sdk_info() -> Dictionary:
	var api: Object = android()
	return api.sdkInfo() if api != null else {}

static func display_info() -> Dictionary:
	var api: Object = android()
	return api.displayInfo() if api != null else {}
