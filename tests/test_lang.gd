extends "res://tests/test_case.gd"
## The translation table, checked rather than trusted.
##
## A row that is short by one is invisible at the call site: the string simply
## comes out in English and looks like something somebody forgot to wrap. You
## asked for every string to be translated literally in every language, and
## the only way to keep that true while the table grows by a dozen rows a
## build is to count it on every run.

func title() -> String:
	return "translations"

func run() -> void:
	_every_language_is_complete()
	_the_table_is_usable()
	_numbers_follow_the_language()

func _every_language_is_complete() -> void:
	note("no language is missing a row")
	for code in range(Lang.NAMES.size()):
		var cover: Dictionary = Lang.coverage(code)
		var missing: Array = Lang.gaps(code)
		eq(missing.size(), 0, "%s has every row filled in%s" % [
			Lang.name_of(code),
			"" if missing.is_empty() else " (first missing: %s)"
				% String(missing[0])])
		eq(int(cover["done"]), int(cover["total"]),
			"%s is complete" % Lang.name_of(code))

func _the_table_is_usable() -> void:
	note("looking a string up gives the language that is switched on")
	var was: int = Lang.current
	Lang.current = Lang.L.EN
	eq(Lang.t("Brush"), "Brush", "English gives back the key")
	Lang.current = Lang.L.AR
	ok(Lang.t("Brush") != "Brush", "Arabic gives back something else")
	ok(Lang.is_rtl(), "and reads right to left")
	Lang.current = Lang.L.JA
	not_ok(Lang.is_rtl(), "Japanese does not")

	note("a string nobody has translated falls back rather than disappearing")
	eq(Lang.t("A string that is certainly not in the table"),
		"A string that is certainly not in the table",
		"an unknown key comes back as itself")
	eq(Lang.t("Another unknown one", "a stated fallback"), "a stated fallback",
		"unless a fallback was offered")
	Lang.current = was

func _numbers_follow_the_language() -> void:
	note("digits are written the way the language writes them")
	var was: int = Lang.current
	Lang.current = Lang.L.EN
	eq(Lang.number(1990), "1990", "English keeps western digits")
	Lang.current = Lang.L.AR
	eq(Lang.number(12), "١٢", "Arabic uses eastern ones")
	ok(Lang.decimal(1.5, 1).length() > 0, "and a decimal still comes out")
	Lang.current = was
