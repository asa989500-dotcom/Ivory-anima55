extends "res://tests/test_case.gd"

func title() -> String:
	return "image import"

func run() -> void:
	note("shared loader returns bounded RGBA8 images")
	var dir: String = "user://ivory_import_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path: String = dir + "/tiny.png"
	var src: Image = Image.create(32, 20, false, Image.FORMAT_RGBA8)
	src.fill(Color(1, 1, 1, 1))
	ok(src.save_png(path) == OK, "test PNG can be written")
	var loaded: Dictionary = ImageImport.load_path(path, 4096)
	ok(bool(loaded.get("ok", false)), "shared import accepts a valid PNG")
	var img: Image = loaded.get("image", null)
	not_null(img, "loader returns an Image")
	if img != null:
		eq(img.get_width(), 32, "width is preserved")
		eq(img.get_height(), 20, "height is preserved")
		eq(img.get_format(), Image.FORMAT_RGBA8, "loader normalises to RGBA8")
		ok(bool(loaded.get("micros", 0)) >= 0, "loader reports elapsed time")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

