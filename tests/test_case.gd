extends RefCounted
## What a test case inherits.
##
## Deliberately small. A test framework that has to be learned is a test
## framework that does not get used, and the four checkers in `tools/` already
## proved that the thing which actually gets run is the thing that is one
## command and no ceremony.
##
## Every assertion carries a sentence saying what was being checked, because a
## failure that reads `expected 4, got 3` costs the reader a trip into the file
## to find out what four meant.

var failures: Array = []
var checks: int = 0

## The name shown in the run. Overridden by every case.
func title() -> String:
	return "unnamed"

## Overridden by every case. Called once; may leave anything it likes behind
## as long as it cleans up files it wrote.
func run() -> void:
	pass

# ---------------------------------------------------------------- assertions

func ok(condition: bool, what: String) -> void:
	checks += 1
	if not condition:
		failures.append(what)

func not_ok(condition: bool, what: String) -> void:
	ok(not condition, what)

func eq(got: Variant, want: Variant, what: String) -> void:
	checks += 1
	if got != want:
		failures.append("%s — wanted %s, got %s" % [what, str(want), str(got)])

func near(got: float, want: float, tolerance: float, what: String) -> void:
	checks += 1
	if absf(got - want) > tolerance:
		failures.append("%s — wanted %f ± %f, got %f"
			% [what, want, tolerance, got])

func between(got: float, low: float, high: float, what: String) -> void:
	checks += 1
	if got < low or got > high:
		failures.append("%s — wanted between %f and %f, got %f"
			% [what, low, high, got])

func is_null(got: Variant, what: String) -> void:
	checks += 1
	if got != null:
		failures.append("%s — wanted nothing, got %s" % [what, str(got)])

func not_null(got: Variant, what: String) -> void:
	checks += 1
	if got == null:
		failures.append("%s — wanted something, got nothing" % what)

## Says what a whole group of assertions was about, so a run reads as prose.
func note(what: String) -> void:
	_notes.append(what)

var _notes: Array = []

func notes() -> Array:
	return _notes
