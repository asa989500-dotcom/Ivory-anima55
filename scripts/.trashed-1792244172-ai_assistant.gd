class_name AIAssistant
extends Node
## Talks to FLUX.1 through Hugging Face, and is the only thing in IVORY that
## does.
##
## Everything the app asks of a model goes through here — improving a layer,
## drawing from a description, filling in the missing turns of a character —
## so there is one place that knows about tokens, cold starts, retries and
## how a picture comes back over a wire. Three features sharing one pipeline
## rather than three copies of the same HTTP code, because the second copy is
## where the first bug lives on after it is fixed.
##
## The shape of the node is the one you specified:
##
##     AIAssistant  (this)
##       └─ NetworkRequest  (HTTPRequest, made in `_ready`)
##
## Nothing is held on the device. A request goes out as text, an image comes
## back as bytes, the bytes become an `Image` and then an `ImageTexture`, and
## that is the whole of the memory cost — no model, no weights, no gigabytes
## of download. A phone that can show the picture can make the picture.
##
## ─────────────────────────────────────────────────────────────────────────
##  YOUR API KEY GOES ON THE `API_TOKEN` LINE BELOW.
##  Keep the word `Bearer` and the space, and replace only what follows it.
## ─────────────────────────────────────────────────────────────────────────

## The model. Open source, and fast enough to be worth waiting for on a
## tablet: schnell is the four-step FLUX, seconds rather than a minute.
const MODEL: String = "black-forest-labs/FLUX.1-schnell"

## ## Why nothing ever came back
##
## The app *was* calling the site. The site was answering, and what it
## answered was **410 Gone**.
##
## The address here was `api-inference.huggingface.co`, and Hugging Face
## retired that host. Through 2025 it returned a refusal naming its own
## replacement — "no longer supported, please use router.huggingface.co
## instead" — and by the end of that year it was decommissioned outright.
## Every request this app made was reaching a door that had been bricked up,
## being told so politely, and reporting the polite refusal as an ordinary
## failure. The key was never the problem. The key is fine. The address was
## two years stale.
##
## ## Why there is a list of them and not one
##
## Because that will happen again. An address compiled into a build is a
## promise about somebody else's infrastructure, and this one has already been
## broken once while the app sat still.
##
## So the addresses are tried in order and the app **remembers which one
## answered**, in `user://ai_endpoint.txt`, so the cost of finding it is paid
## once rather than on every request. A refusal that means "wrong door" — 404,
## 410, or a body that names a different host — advances to the next and tries
## again immediately, without troubling the person. A refusal that means
## anything else is reported, because a wrong key is not a wrong door and
## walking down the list would only hide it.
##
## The dead host is kept, last. It costs nothing to have there, and if it ever
## comes back, or somebody points a private mirror at it, the app will find it.
## A plain `Array`, not a `PackedStringArray`.
##
## `const` in GDScript takes a *constant expression*, and calling
## `PackedStringArray(...)` is a call — evaluated at run time, so the parser
## refuses it and the whole script fails to compile. An `Array` literal is a
## literal, and is allowed. My error, and it stopped the app opening at all.
const ENDPOINTS: Array = [
	# The replacement Hugging Face's own refusal names, and the form its
	# current documentation shows. Same request, same answer: POST JSON, get
	# the image bytes straight back.
	"https://router.huggingface.co/hf-inference/models/%s",
	# The router's plain model form, in case the provider prefix moves again.
	"https://router.huggingface.co/models/%s",
	# Where this app has been knocking since it was written.
	"https://api-inference.huggingface.co/models/%s",
]

## Which address answered last time, so it is tried first next time.
const DOOR_FILE: String = "user://ai_endpoint.txt"

## Which of `ENDPOINTS` is being tried.
static var _door: int = -1
## How the last exchange went, in plain words, for the connection test and for
## anybody who needs to know whether the app is really talking to the site.
static var last_report: String = ""

## ▼▼▼ WRITE YOUR KEY HERE ▼▼▼
const API_TOKEN: String = "Bearer "
## ▲▲▲ WRITE YOUR KEY HERE ▲▲▲
##
## Your key is on that line. Two things follow from it that are worth knowing
## rather than finding out:
##
## A constant compiled into an APK can be read straight back out of the file
## by anyone who has it — `strings` on the binary is enough. So this build is
## fine to keep and to test with, and the moment you hand the APK to somebody
## you do not know, that key is theirs too, and Hugging Face bills the
## account it belongs to. Rotating it at huggingface.co/settings/tokens takes
## a few seconds and invalidates the old one everywhere.
##
## A key typed into `user://ai_key.txt` still overrides this line if one is
## ever put there. Nothing in the app writes that file any more — the
## settings page that did has been removed, because its place was wrong — but
## the door is left open, so a build for someone else can ship with the
## constant blank and the key supplied on the device instead.

## How the app remembers a key typed into the settings instead.
const KEY_FILE: String = "user://ai_key.txt"

## When the request in flight went out, so the report can say how long the
## site took rather than only what it said.
static var _sent_usec: int = 0

## The address in force.
static func endpoint() -> String:
	if _door < 0:
		_door = _remembered_door()
	return String(ENDPOINTS[clampi(_door, 0, ENDPOINTS.size() - 1)]) % MODEL

## The address that worked last time, if the app has ever got through.
static func _remembered_door() -> int:
	if not FileAccess.file_exists(DOOR_FILE):
		return 0
	var f: FileAccess = FileAccess.open(DOOR_FILE, FileAccess.READ)
	if f == null:
		return 0
	var was: String = f.get_as_text().strip_edges()
	f.close()
	for i in ENDPOINTS.size():
		if ENDPOINTS[i] == was:
			return i
	return 0

## Remembers the address that answered, so the search is not repeated.
static func _remember_door() -> void:
	var f: FileAccess = FileAccess.open(DOOR_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(String(ENDPOINTS[clampi(_door, 0, ENDPOINTS.size() - 1)]))
	f.close()

## Whether an answer means "this is the wrong address" rather than "no".
##
## 404 and 410 are the plain cases. The third is the one that actually
## happened: a 400 or a 500 whose *body* names a different host, which is how
## Hugging Face announced the move for most of a year before the old host went
## quiet altogether.
static func _wrong_door(code: int, body: PackedByteArray) -> bool:
	if code == 404 or code == 410:
		return true
	var said: String = body.get_string_from_utf8().to_lower()
	return said.contains("no longer supported") \
		or said.contains("router.huggingface.co")

## Moves to the next address. False when there are no more to try.
static func _next_door() -> bool:
	if _door < 0:
		_door = _remembered_door()
	if _door + 1 >= ENDPOINTS.size():
		return false
	_door += 1
	return true

## A cold model answers 503 and asks to be tried again. That is normal rather
## than broken — the first request of the day wakes the model up — so it is
## waited out rather than reported as a failure.
const COLD_TRIES: int = 6
const COLD_WAIT: float = 4.0

## Nothing should hang for ever on a tablet whose signal died in a lift.
const TIMEOUT: float = 120.0

## What a request is for. Only used to say something sensible while waiting
## and to route the answer back.
enum Job { IMAGINE, IMPROVE }

signal started(id: int, note: String)
signal progress(id: int, note: String)
## `picture` is premultiplied and ready to go onto a layer; `texture` is the
## same thing ready to be shown.
signal finished(id: int, picture: Image, texture: ImageTexture, job: Dictionary)
signal failed(id: int, why: String)
## Emitted whenever the queue changes, so a waiting mark can appear and go.
signal busy_changed(busy: bool)

var _net: HTTPRequest = null
var _queue: Array = []
var _now: Dictionary = {}
var _next_id: int = 1
var _tries: int = 0
var _stopping: bool = false

func _ready() -> void:
	_net = HTTPRequest.new()
	_net.name = "NetworkRequest"
	_net.timeout = TIMEOUT
	# Downloading on a thread keeps a slow answer from stuttering the canvas.
	# The drawing has to stay usable while a picture is being made — waiting
	# is bearable, a frozen app is not.
	_net.use_threads = true
	_net.accept_gzip = true
	add_child(_net)
	_net.request_completed.connect(_on_answer)

# ------------------------------------------------------------------ the key

## The key in force: the settings one if there is one, else the constant.
static func token() -> String:
	if FileAccess.file_exists(KEY_FILE):
		var f: FileAccess = FileAccess.open(KEY_FILE, FileAccess.READ)
		if f != null:
			var typed: String = f.get_as_text().strip_edges()
			f.close()
			if typed != "":
				return typed if typed.begins_with("Bearer ") \
					else "Bearer " + typed
	return API_TOKEN

## Remembers a key typed into the settings. An empty string forgets it and
## hands authority back to the constant.
static func remember_key(typed: String) -> void:
	var clean: String = typed.strip_edges()
	if clean == "":
		DirAccess.remove_absolute(KEY_FILE)
		return
	var f: FileAccess = FileAccess.open(KEY_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(clean if clean.begins_with("Bearer ")
		else "Bearer " + clean)
	f.close()

## Whether there is a key at all. Checked before a request is queued, so the
## answer to "nothing happened" is a sentence rather than a silence.
static func key_ready() -> bool:
	var t: String = token()
	return t != "" and not t.ends_with("YOUR_API_KEY_HERE")

# --------------------------------------------------------------- the asking

## A picture from a description alone.
##
## `size` is rounded to multiples of 16 because that is what the model works
## in; asking for 1000 gets 992 back and then nothing lines up.
func imagine(prompt: String, size: Vector2i = Vector2i(1024, 1024),
		tag: Dictionary = {}, who: AiIdentity = null) -> int:
	return _queue_job({
		"kind": Job.IMAGINE,
		"prompt": prompt,
		"size": _fit(size),
		"tag": tag,
		"who": who,
	})

## A picture guided by one already drawn.
##
## `strength` is how far the model may travel from the sketch: low keeps the
## drawing and cleans it, high treats it as a suggestion. The layer improver
## sits deliberately low.
func improve(sketch: Image, prompt: String, strength: float = 0.45,
		tag: Dictionary = {}, who: AiIdentity = null) -> int:
	if sketch == null:
		failed.emit(-1, UiKit.label_for("There is nothing drawn to improve",
			"لا يوجد رسم لتحسينه"))
		return -1
	# The palette is re-read from *this* drawing, now, before anything is
	# sent. That is the whole of the consistency promise: the artist has just
	# corrected something, and the request has to work from what they now
	# have rather than from what the model produced before they disagreed
	# with it.
	if who != null:
		who.refresh_from(sketch)
	return _queue_job({
		"kind": Job.IMPROVE,
		"prompt": prompt,
		"sketch": sketch,
		"strength": clampf(strength, 0.05, 0.95),
		"size": _fit(Vector2i(sketch.get_width(), sketch.get_height())),
		"tag": tag,
		"who": who,
	})

func busy() -> bool:
	return not _now.is_empty()

func waiting() -> int:
	return _queue.size()

## Everything not yet sent is dropped, and whatever is in the air is ignored
## when it lands. Reached from the Cancel on the waiting mark.
func stop_everything() -> void:
	_queue.clear()
	if not _now.is_empty():
		_stopping = true
		_net.cancel_request()
		var id: int = int(_now.get("id", -1))
		_now = {}
		failed.emit(id, UiKit.label_for("Stopped", "أُوقف"))
	busy_changed.emit(false)

# ------------------------------------------------------------------ plumbing

static func _fit(size: Vector2i) -> Vector2i:
	# Multiples of sixteen, and inside what the endpoint will accept.
	var w: int = clampi(int(round(float(size.x) / 16.0)) * 16, 256, 1024)
	var h: int = clampi(int(round(float(size.y) / 16.0)) * 16, 256, 1024)
	return Vector2i(w, h)

func _queue_job(job: Dictionary) -> int:
	if not key_ready():
		failed.emit(-1, UiKit.label_for(
			"No API key yet — put one on the API_TOKEN line in ai_assistant.gd",
			"لا يوجد مفتاح بعد — ضعه في سطر API_TOKEN في ai_assistant.gd"))
		return -1
	job["id"] = _next_id
	_next_id += 1
	_queue.append(job)
	busy_changed.emit(true)
	if _now.is_empty():
		_send_next()
	return int(job["id"])

func _send_next() -> void:
	if _queue.is_empty():
		_now = {}
		busy_changed.emit(false)
		return
	_now = _queue.pop_front()
	_tries = 0
	started.emit(int(_now["id"]), _what_for(_now))
	_fire()

static func _what_for(job: Dictionary) -> String:
	match int(job.get("kind", Job.IMAGINE)):
		Job.IMPROVE:
			return UiKit.label_for("Improving the drawing",
				"يحسّن الرسم")
		_:
			return UiKit.label_for("Drawing", "يرسم")

func _fire() -> void:
	if _now.is_empty() or _net == null:
		return
	var headers: PackedStringArray = PackedStringArray([
		"Authorization: %s" % token(),
		"Content-Type: application/json",
		"Accept: image/png",
		# Ask the endpoint to wait for a cold model rather than answering
		# 503 straight away. It does not always honour it, which is why the
		# retry below still exists.
		"x-wait-for-model: true",
	])
	var sent: Error = _net.request(endpoint(), headers, HTTPClient.METHOD_POST,
		_payload(_now))
	_sent_usec = Time.get_ticks_usec()
	if sent != OK:
		var id: int = int(_now["id"])
		_now = {}
		failed.emit(id, UiKit.label_for("Could not reach the network",
			"تعذّر الوصول إلى الشبكة"))
		_send_next()

## The JSON that goes up.
##
## `inputs` is the description. `parameters` carries the size and, when there
## is a drawing to work from, the drawing itself as a data URI and how far
## the model may stray from it.
static func _payload(job: Dictionary) -> String:
	var size: Vector2i = job.get("size", Vector2i(1024, 1024))
	var parameters: Dictionary = {
		"width": size.x,
		"height": size.y,
		# schnell is distilled to four steps and guidance does nothing for
		# it; both are sent anyway so the same payload works if the endpoint
		# is pointed at a model that wants them.
		"num_inference_steps": 4,
		"guidance_scale": 0.0,
	}
	# Who this is, before what they are doing.
	#
	# In front rather than behind, because attention thins towards the end of
	# a long prompt and the character's identity must not be the part that
	# gets skimmed. And the seed goes in beside it: the same number is the
	# same starting noise, which is what turns "another knight" into "the
	# same knight, from the other side".
	var words: String = String(job.get("prompt", ""))
	var who: AiIdentity = job.get("who", null)
	if who != null and who.ready():
		words = "%s. %s" % [who.words(), words]
		parameters.merge(who.parameters(), true)
	var body: Dictionary = {"inputs": words}

	var sketch: Image = job.get("sketch", null)
	if sketch != null:
		parameters["strength"] = float(job.get("strength", 0.45))
		body["image"] = data_uri(sketch)
	body["parameters"] = parameters
	# Without this a second identical request comes back from a cache, and
	# asking twice for a variation would give the same picture twice.
	body["options"] = {"wait_for_model": true, "use_cache": false}
	return JSON.stringify(body)

## A drawing as a `data:` string: PNG bytes, then base64, exactly as the
## specification asks.
##
## Un-premultiplied on the way out. Everything on the IVORY canvas is stored
## with its colour already multiplied by its transparency, which is right for
## compositing and wrong for anything outside this app — sent as it is, every
## soft edge arrives darker than it was drawn, and a model asked to improve
## it faithfully reproduces the darkening.
static func data_uri(picture: Image) -> String:
	var flat: Image = picture.duplicate()
	if flat.get_format() != Image.FORMAT_RGBA8:
		flat.convert(Image.FORMAT_RGBA8)
	_straighten(flat)
	var png: PackedByteArray = flat.save_png_to_buffer()
	return "data:image/png;base64," + Marshalls.raw_to_base64(png)

## Premultiplied pixels turned back into ordinary ones.
static func _straighten(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var data: PackedByteArray = img.get_data()
	for i in range(0, data.size(), 4):
		var a: int = data[i + 3]
		if a == 0 or a == 255:
			continue
		var k: float = 255.0 / float(a)
		data[i] = mini(int(float(data[i]) * k), 255)
		data[i + 1] = mini(int(float(data[i + 1]) * k), 255)
		data[i + 2] = mini(int(float(data[i + 2]) * k), 255)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)

## Ordinary pixels turned into the premultiplied ones the canvas keeps.
static func premultiply(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var data: PackedByteArray = img.get_data()
	for i in range(0, data.size(), 4):
		var a: int = data[i + 3]
		if a == 255:
			continue
		var k: float = float(a) / 255.0
		data[i] = int(float(data[i]) * k)
		data[i + 1] = int(float(data[i + 1]) * k)
		data[i + 2] = int(float(data[i + 2]) * k)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)

# ------------------------------------------------------------- what comes back

func _on_answer(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if _stopping:
		_stopping = false
		_send_next()
		return
	if _now.is_empty():
		return
	var id: int = int(_now["id"])

	var took: float = float(Time.get_ticks_usec() - _sent_usec) / 1000000.0
	last_report = "%s → %d (%.1fs)" % [endpoint(), code, took]

	if result != HTTPRequest.RESULT_SUCCESS:
		_give_up(id, UiKit.label_for(
			"The network did not answer. Check the connection and try again.",
			"لم تُجب الشبكة. تحقّق من الاتصال وأعد المحاولة."))
		return

	# The wrong door: try the next one straight away rather than reporting a
	# failure the person can do nothing about. See `ENDPOINTS`.
	if _wrong_door(code, body):
		if _next_door():
			progress.emit(id, UiKit.label_for(
				"That address has moved — trying the current one",
				"ذاك العنوان انتقل — تُجرَّب الوجهة الحالية"))
			_fire()
			return
		_give_up(id, UiKit.label_for(
			"No address answered. The service has moved and the app has run out of places to knock.",
			"لم يُجب أيّ عنوان. الخدمة انتقلت ولم يبقَ للتطبيق بابٌ يطرقه."))
		return

	# 503 is a cold model waking up, not a failure. 429 is too many requests
	# in a minute. Both are worth waiting out; everything else is not.
	if code == 503 or code == 429:
		_tries += 1
		if _tries <= COLD_TRIES:
			progress.emit(id, UiKit.label_for(
				"The model is waking up — waiting (%d of %d)"
					% [_tries, COLD_TRIES],
				"النموذج يستيقظ — في الانتظار (%d من %d)"
					% [_tries, COLD_TRIES]))
			await get_tree().create_timer(COLD_WAIT
				* float(_tries)).timeout
			if _now.is_empty() or int(_now.get("id", -1)) != id:
				return
			_fire()
			return
		_give_up(id, UiKit.label_for(
			"The model is still busy. Try again in a minute.",
			"النموذج ما زال مشغولاً. أعد المحاولة بعد دقيقة."))
		return

	if code == 401 or code == 403:
		_give_up(id, UiKit.label_for(
			"The API key was refused. Check the API_TOKEN line in ai_assistant.gd.",
			"رُفض مفتاح الـ API. تحقّق من سطر API_TOKEN في ai_assistant.gd."))
		return

	if code != 200:
		_give_up(id, _complaint_in(body, code))
		return

	var picture: Image = _decode(body)
	if picture == null:
		_give_up(id, _complaint_in(body, code))
		return

	# It answered with a picture, so this is the address. Written down, so the
	# next launch goes straight there.
	_remember_door()

	# Straight from the endpoint, so straight alpha; the canvas wants it
	# premultiplied like everything else it holds.
	premultiply(picture)
	var texture: ImageTexture = ImageTexture.create_from_image(picture)
	var job: Dictionary = _now
	_now = {}
	finished.emit(id, picture, texture, job)
	_send_next()

## Bytes into a picture, whatever shape they arrived in.
##
## The endpoint normally answers with the image itself. Some providers behind
## the same address answer with JSON holding base64 instead, so both are
## tried before giving up — the difference is invisible from here and costs
## one branch to survive.
static func _decode(body: PackedByteArray) -> Image:
	if body.is_empty():
		return null
	var img: Image = Image.new()
	if img.load_png_from_buffer(body) == OK:
		return img
	img = Image.new()
	if img.load_jpg_from_buffer(body) == OK:
		return img
	img = Image.new()
	if img.load_webp_from_buffer(body) == OK:
		return img

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var doc: Dictionary = parsed
	var packed: String = String(doc.get("image", doc.get("generated_image", "")))
	if packed == "":
		return null
	if packed.contains(","):
		packed = packed.split(",")[1]
	var raw: PackedByteArray = Marshalls.base64_to_raw(packed)
	img = Image.new()
	if img.load_png_from_buffer(raw) == OK:
		return img
	img = Image.new()
	if img.load_jpg_from_buffer(raw) == OK:
		return img
	return null

## The server's own words, when it has any, rather than a status number.
static func _complaint_in(body: PackedByteArray, code: int) -> String:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) == TYPE_DICTIONARY:
		var doc: Dictionary = parsed
		var said: String = String(doc.get("error", ""))
		if said != "":
			return said
	return UiKit.label_for("The service answered %d" % code,
		"أجابت الخدمة بالرمز %d" % code)

func _give_up(id: int, why: String) -> void:
	_now = {}
	failed.emit(id, why)
	_send_next()

# ----------------------------------------------------- proving it is there

## Knocks on the door and says exactly what came back.
##
## ## Why this exists
##
## "The app never calls the site" was the report, and it was not true — the
## app was calling and the site was answering 410 Gone, and every one of those
## exchanges was flattened into a sentence about the model being busy. From
## the outside that is indistinguishable from an app that never opened a
## socket at all. There was no way to tell the two apart, which is why the
## belief could not be corrected by looking.
##
## So there is now a way to look. This makes one real request, over the real
## network, with the real key, and reports the address it used, the number the
## server returned and how long it took. Not a summary. The numbers.
##
## A tiny image is asked for — the smallest the model will take — so the test
## costs almost nothing and finishes in a moment. What matters is not the
## picture; it is that a code came back from a host.
func test_connection() -> void:
	if _net == null:
		last_report = "no network node"
		failed.emit(-1, UiKit.label_for("The app has no network node",
			"لا يوجد عنصر شبكة في التطبيق"))
		return
	if not key_ready():
		last_report = "no key"
		failed.emit(-1, UiKit.label_for("There is no API key to test with",
			"لا يوجد مفتاح API لاختباره"))
		return
	last_report = "sending…"
	imagine("a single grey dot on white paper", Vector2i(256, 256),
		{"connection_test": true})

## Every address the app knows, and which one it is using, as plain text for
## the settings page.
static func describe_doors() -> String:
	var out: String = "endpoint in use:\n  %s\n" % endpoint()
	out += "known addresses, in the order they are tried:\n"
	for i in ENDPOINTS.size():
		var mark: String = "→" if i == clampi(_door, 0, ENDPOINTS.size() - 1) \
			else " "
		out += "  %s %s\n" % [mark, String(ENDPOINTS[i]) % MODEL]
	out += "key: %s\n" % ("present" if key_ready() else "MISSING")
	if last_report != "":
		out += "last exchange:\n  %s\n" % last_report
	else:
		out += "last exchange:\n  nothing sent yet this session\n"
	return out
