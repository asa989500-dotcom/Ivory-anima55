extends "res://tests/test_case.gd"
## The AI pipeline, everything except the network itself.
##
## What can be tested here is most of what actually goes wrong: the payload,
## the base64 encoding, the premultiplied conversion in both directions,
## reading an answer back out of bytes, and whether a missing key is caught
## before a request is made rather than after. None of it needs a token, an
## endpoint, or a second of network time, so it runs in the same suite as
## everything else and on a machine with no connection at all.
##
## What is *not* tested here is whether Hugging Face answers. That is not a
## property of this code and no test here can establish it.

func title() -> String:
	return "ai pipeline"

func run() -> void:
	_the_key_is_checked_before_anything_is_sent()
	_a_drawing_survives_the_round_trip()
	_the_payload_says_what_it_should()
	_an_answer_is_read_back_out_of_bytes()
	_a_character_stays_the_same_character()

func _sketch(side: int = 64) -> Image:
	var img: Image = Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for i in range(side):
		img.set_pixel(i, i, Color(0.8, 0.3, 0.2, 1.0))
		# A half-transparent pixel, because that is the one the premultiplied
		# conversion can get wrong and a solid pixel cannot.
		img.set_pixel(i, mini(i + 1, side - 1), Color(0.5, 0.5, 0.5, 0.5))
	return img

func _the_key_is_checked_before_anything_is_sent() -> void:
	note("a missing key is a sentence, not a silent nothing")
	# The file the settings write to, put aside so a real key on this machine
	# is not disturbed by the test.
	var had: String = ""
	if FileAccess.file_exists(AIAssistant.KEY_FILE):
		var f: FileAccess = FileAccess.open(AIAssistant.KEY_FILE,
			FileAccess.READ)
		if f != null:
			had = f.get_as_text()
			f.close()

	AIAssistant.remember_key("")
	eq(AIAssistant.token(), AIAssistant.API_TOKEN,
		"with nothing typed, the constant is what is used")
	# The rule, either way round: a real key counts and the placeholder does
	# not. Asserted as the rule rather than as one of its two answers, so the
	# test keeps meaning the same thing whether or not there is a key in the
	# constant on the machine it runs on.
	eq(AIAssistant.key_ready(),
		not AIAssistant.API_TOKEN.ends_with("YOUR_API_KEY_HERE"),
		"the constant counts as a key exactly when it is not the placeholder")

	AIAssistant.remember_key("hf_pretend_key_for_the_test")
	ok(AIAssistant.key_ready(), "a typed key counts")
	eq(AIAssistant.token(), "Bearer hf_pretend_key_for_the_test",
		"and the word Bearer is added when it is missing")

	AIAssistant.remember_key("Bearer hf_already_said_it")
	eq(AIAssistant.token(), "Bearer hf_already_said_it",
		"and not added twice when it is already there")

	AIAssistant.remember_key("")
	not_ok(FileAccess.file_exists(AIAssistant.KEY_FILE),
		"forgetting the key removes the file")
	if had != "":
		AIAssistant.remember_key(had)

func _a_drawing_survives_the_round_trip() -> void:
	note("premultiplied pixels are straightened on the way out and put back")
	var before: Image = _sketch()
	var after: Image = before.duplicate()
	AIAssistant._straighten(after)
	AIAssistant.premultiply(after)

	var worst: int = 0
	var a: PackedByteArray = before.get_data()
	var b: PackedByteArray = after.get_data()
	eq(b.size(), a.size(), "the same number of bytes came back")
	for i in range(a.size()):
		worst = maxi(worst, absi(int(a[i]) - int(b[i])))
	# Not exact, and cannot be: the conversion divides by the transparency
	# and multiplies back, and both steps round to whole bytes. What matters
	# is that it does not drift — a soft edge that darkens by one step per
	# round trip would be black after a dozen improvements.
	ok(worst <= 2, "nothing moved by more than a rounding step")

	note("and a drawing becomes a data URI the service can read")
	var uri: String = AIAssistant.data_uri(before)
	ok(uri.begins_with("data:image/png;base64,"),
		"the URI says what it is carrying")
	var packed: String = uri.split(",")[1]
	var raw: PackedByteArray = Marshalls.base64_to_raw(packed)
	var back: Image = Image.new()
	eq(back.load_png_from_buffer(raw), OK,
		"and what it carries is a PNG that loads")
	eq(back.get_size(), before.get_size(), "at the size it was sent")

func _the_payload_says_what_it_should() -> void:
	note("words alone")
	var words_only: Dictionary = _parsed(AIAssistant._payload({
		"prompt": "a knight in silver armour",
		"size": Vector2i(768, 512),
	}))
	eq(String(words_only.get("inputs", "")), "a knight in silver armour",
		"the description is the input")
	not_ok(words_only.has("image"), "and no picture is sent with it")
	var parameters: Dictionary = words_only.get("parameters", {})
	eq(int(parameters.get("width", 0)), 768, "the width asked for")
	eq(int(parameters.get("height", 0)), 512, "and the height")
	not_ok(parameters.has("strength"),
		"strength means nothing without a drawing, so it is not sent")

	note("words with a drawing")
	var with_art: Dictionary = _parsed(AIAssistant._payload({
		"prompt": "clean line art",
		"size": Vector2i(512, 512),
		"sketch": _sketch(),
		"strength": 0.38,
	}))
	ok(String(with_art.get("image", "")).begins_with("data:image/png;base64,"),
		"the drawing goes up as a data URI")
	near(float((with_art.get("parameters", {}) as Dictionary)
		.get("strength", 0.0)), 0.38, 0.001,
		"and how far it may stray goes with it")

	note("a repeated request is not answered from a cache")
	var options: Dictionary = with_art.get("options", {})
	not_ok(bool(options.get("use_cache", true)),
		"asking twice has to be able to give two different pictures")

	note("sizes are rounded to what the model works in")
	# 1000/16 is 62.5 and rounds up; 999/16 is 62.4 and rounds down. The two
	# sides are rounded separately, which is why an almost-square request can
	# come back very slightly not square.
	eq(AIAssistant._fit(Vector2i(1000, 999)), Vector2i(1008, 992),
		"each side to its own nearest sixteen")
	eq(AIAssistant._fit(Vector2i(4000, 30)), Vector2i(1024, 256),
		"and kept inside what the service accepts")

func _an_answer_is_read_back_out_of_bytes() -> void:
	note("the picture arrives as bytes and becomes an Image")
	var sent: Image = _sketch(48)
	var png: PackedByteArray = sent.save_png_to_buffer()
	var got: Image = AIAssistant._decode(png)
	not_null(got, "PNG bytes are read")
	if got != null:
		eq(got.get_size(), Vector2i(48, 48), "at the right size")

	note("and JSON holding base64 is read too, since some providers answer that way")
	var wrapped: PackedByteArray = JSON.stringify({
		"image": "data:image/png;base64," + Marshalls.raw_to_base64(png),
	}).to_utf8_buffer()
	not_null(AIAssistant._decode(wrapped), "a JSON answer is read")

	note("and nonsense is refused rather than half-read")
	is_null(AIAssistant._decode(PackedByteArray()), "no bytes, no picture")
	is_null(AIAssistant._decode("not a picture at all".to_utf8_buffer()),
		"and neither is a sentence")

	note("the server's own words are used when it complains")
	var complaint: PackedByteArray = JSON.stringify(
		{"error": "Model too busy"}).to_utf8_buffer()
	eq(AIAssistant._complaint_in(complaint, 500), "Model too busy",
		"what the service said, not the status number")

## The consistency machinery: the seed, the spine and the palette.
##
## What can be checked without a network is that the same character produces
## the same seed on every request, that the palette is actually read off the
## artist's drawing rather than off the model's first answer, and that the
## words the character contributes reach the payload. Whether the model then
## honours them is the model's business.
func _a_character_stays_the_same_character() -> void:
	note("a character is given one seed and keeps it")
	var knight: AiIdentity = AiIdentity.make("Sir Kay",
		"a knight in silver armour, cel shaded")
	ok(knight.seed_value > 0, "a seed was chosen")
	var first: Dictionary = knight.parameters()
	var second: Dictionary = knight.parameters()
	eq(int(first["seed"]), int(second["seed"]),
		"and it is the same on the second request as on the first")
	ok(knight.ready(), "a description alone is enough to be worth attaching")

	note("the palette is read off the drawing, not guessed at")
	var drawn: Image = Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	drawn.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(0, 40):
		for x in range(64):
			drawn.set_pixel(x, y, Color(0.15, 0.35, 0.75, 1.0))   # a blue
	for y in range(40, 64):
		for x in range(64):
			drawn.set_pixel(x, y, Color(0.75, 0.25, 0.15, 1.0))   # a red
	knight.refresh_from(drawn)
	eq(knight.palette.size(), 2, "two colours in, two colours out")
	ok(String(knight.palette[0]).begins_with("#"), "written as hex")
	# Most-used first: the blue covers more of the drawing than the red, so
	# the first colour out has to be the bluer of the two.
	var top: Color = Color(String(knight.palette[0]))
	ok(top.b > top.r, "the most-used colour comes first")
	ok(knight.refreshed_at > 0, "and it recorded when it read it")

	note("white paper and black ink are not the character's colours")
	var mostly_paper: Image = Image.create_empty(32, 32, false,
		Image.FORMAT_RGBA8)
	mostly_paper.fill(Color(1.0, 1.0, 1.0, 1.0))
	for x in range(32):
		mostly_paper.set_pixel(x, 16, Color(0.2, 0.6, 0.3, 1.0))
	var plain: AiIdentity = AiIdentity.make("", "a leaf")
	plain.refresh_from(mostly_paper)
	eq(plain.palette.size(), 1,
		"only the green counts; the paper and the ink are ignored")

	note("the character's words reach the payload, in front of the request")
	var body: Dictionary = _parsed(AIAssistant._payload({
		"prompt": "from the left",
		"size": Vector2i(512, 512),
		"who": knight,
	}))
	var said: String = String(body.get("inputs", ""))
	ok(said.contains("Sir Kay"), "the character is named")
	ok(said.contains("silver armour"), "and described")
	ok(said.contains(String(knight.palette[0])), "with its colours stated")
	ok(said.ends_with("from the left"),
		"and what was asked for comes last, after who it is about")
	eq(int((body.get("parameters", {}) as Dictionary).get("seed", 0)),
		knight.seed_value, "and the seed went with it")

	note("and a character survives being saved and read back")
	var stored: AiIdentity = AiIdentity.from_dict(knight.to_dict())
	not_null(stored, "it came back")
	eq(stored.seed_value, knight.seed_value,
		"with the seed intact — losing it would lose the character")
	eq(stored.palette.size(), knight.palette.size(), "and its palette")
	is_null(AiIdentity.from_dict({}), "and nothing comes back as nothing")

func _parsed(text: String) -> Dictionary:
	var got: Variant = JSON.parse_string(text)
	if typeof(got) != TYPE_DICTIONARY:
		return {}
	return got
