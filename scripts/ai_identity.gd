class_name AiIdentity
extends RefCounted
## What makes it the same character the second time.
##
## This is the hard part, and it is worth saying plainly why a good image
## model does not solve it on its own. Ask for "a knight in silver armour"
## twice and you get two knights. Both are good; neither is the same person.
## For a drawing that is fine and for an animation it is useless — a character
## who is a slightly different person in every shot is not a character.
##
## Four things are held steady, and they are held steady because each one
## fixes a different way the character drifts:
##
##   **The seed.** The same number gives the model the same starting noise, so
##   the same words land on the same face rather than on a new one. Left to
##   chance it is a new person every request; fixed, it is the same person
##   asked to do something else. This alone is most of the battle.
##
##   **The spine.** The sentence that must appear in every prompt, whatever
##   else is asked for: who this is, what they are wearing, what the drawing
##   style is. Written once when the character is established and then
##   attached to every later request without the artist retyping it — because
##   what actually happens otherwise is that the tenth prompt says less than
##   the first and the character quietly simplifies.
##
##   **The palette.** Read off the artist's own drawing, as numbers, and
##   stated in words the model can use. "Silver armour" is a wish; a stated
##   set of six colours is an instruction, and it is the thing that stops the
##   armour going gold in the fourth shot.
##
##   **The reference — re-read after every edit.** The one that matters most
##   and the one that is easiest to get wrong. If the artist fixes the model's
##   hands and then asks for another angle, the request has to work from the
##   drawing *as it now is*, not from what the model produced before the
##   artist disagreed with it. Otherwise every correction is undone by the
##   next request and the artist is arguing with the tool.
##
## The order matters too: the artist's drawing outranks the model's memory,
## always. That is the whole stance of this feature — the AI is the assistant
## and the artist is the one being assisted.

## How many colours are lifted off a drawing. Six is enough to pin skin,
## hair, two garment colours and two accents, and few enough that the model
## treats them as a palette rather than as noise.
const PALETTE_SIZE: int = 6

## Colours are grouped into a coarse cube before counting. Without this, two
## pixels a shade apart count as two colours and the palette comes out as six
## shades of the same brown.
const BUCKET: int = 32

## Named so the character can be spoken about and so two of them on one page
## do not get confused.
var title: String = ""

## The starting noise. Random once, then never again.
var seed_value: int = 0

## The sentence attached to every request about this character.
var spine: String = ""

## Hex colours read off the drawing, most used first.
var palette: PackedStringArray = PackedStringArray()

## When the reference was last re-read, so the room can say whether it is
## working from the artist's latest drawing or from something older.
var refreshed_at: int = 0

static func make(named: String, description: String) -> AiIdentity:
	var out: AiIdentity = AiIdentity.new()
	out.title = named
	out.spine = description.strip_edges()
	# Positive and inside what an inference endpoint will accept as a seed.
	out.seed_value = absi(int(Time.get_unix_time_from_system())
		* 2654435761) % 2147483647
	return out

## Re-reads the palette from the drawing as it now stands.
##
## Called every time the artist's version changes — after an improvement is
## placed, after the layer is drawn on, before any request that names this
## character. That is what keeps a correction from being undone by the next
## request.
func refresh_from(art: Image) -> void:
	if art == null:
		return
	palette = read_palette(art)
	refreshed_at = int(Time.get_unix_time_from_system())

## The most-used colours in a drawing, ignoring what is transparent.
##
## Deliberately simple — counting into a coarse cube rather than clustering.
## A proper k-means would give prettier centres and cost a hundred times as
## much on a tablet, and the model is being handed six colours to stay near,
## not being asked to match a swatch book.
static func read_palette(art: Image) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if art == null:
		return out
	var w: int = art.get_width()
	var h: int = art.get_height()
	if w <= 0 or h <= 0:
		return out
	# At most a quarter of a million samples, whatever the drawing's size:
	# a palette is a summary and reading every pixel of a large page to build
	# one is time spent for no extra accuracy.
	var step: int = maxi(int(sqrt(float(w * h) / 250000.0)), 1)
	var counts: Dictionary = {}
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c: Color = art.get_pixel(x, y)
			if c.a < 0.35:
				continue
			# Near-white and near-black are paper and ink, not the
			# character's colours, and left in they crowd out everything
			# that identifies the drawing.
			var light: float = (c.r + c.g + c.b) / 3.0
			if light > 0.94 or light < 0.06:
				continue
			var key: int = _bucket_of(c)
			counts[key] = int(counts.get(key, 0)) + 1

	var keys: Array = counts.keys()
	keys.sort_custom(func(a: int, b: int) -> bool:
		return int(counts[a]) > int(counts[b]))
	for i in range(mini(PALETTE_SIZE, keys.size())):
		out.append(_hex_of(int(keys[i])))
	return out

static func _bucket_of(c: Color) -> int:
	# Floored on purpose — a bucket index is whole — and written as a float
	# divide so the intent is on the page rather than in a warning.
	var r: int = int(c.r * 255.0 / float(BUCKET))
	var g: int = int(c.g * 255.0 / float(BUCKET))
	var b: int = int(c.b * 255.0 / float(BUCKET))
	return (r << 16) | (g << 8) | b

static func _hex_of(key: int) -> String:
	# Back to the middle of the bucket rather than its corner, so the colour
	# named is the one actually seen.
	var half: int = int(float(BUCKET) / 2.0)
	var r: int = mini(((key >> 16) & 0xFF) * BUCKET + half, 255)
	var g: int = mini(((key >> 8) & 0xFF) * BUCKET + half, 255)
	var b: int = mini((key & 0xFF) * BUCKET + half, 255)
	return "#%02x%02x%02x" % [r, g, b]

## The words this identity adds to any request.
##
## Put in front of what the artist typed rather than behind it, because
## attention thins towards the end of a long prompt and who the character is
## must not be the part that gets skimmed.
func words() -> String:
	var parts: Array = []
	if title != "":
		parts.append(title)
	if spine != "":
		parts.append(spine)
	if not palette.is_empty():
		parts.append("exact colour palette %s" % ", ".join(palette))
	parts.append("identical character in every image, same face, "
		+ "same proportions, same clothing, same drawing style")
	return ", ".join(parts)

## What goes into a request alongside the words.
func parameters() -> Dictionary:
	return {"seed": seed_value}

## Whether there is enough here to be worth attaching.
func ready() -> bool:
	return spine != "" or not palette.is_empty()

# ------------------------------------------------------------------- storage

## Saved with the project, so a character survives the app being closed.
##
## The seed above all. Lose it and the character cannot be drawn again — the
## next request starts from different noise and returns somebody who merely
## resembles them, which is the failure this whole file exists to prevent.
func to_dict() -> Dictionary:
	return {
		"title": title,
		"seed": seed_value,
		"spine": spine,
		"palette": palette,
		"refreshed": refreshed_at,
	}

static func from_dict(doc: Dictionary) -> AiIdentity:
	if doc.is_empty():
		return null
	var out: AiIdentity = AiIdentity.new()
	out.title = String(doc.get("title", ""))
	out.seed_value = int(doc.get("seed", 0))
	out.spine = String(doc.get("spine", ""))
	out.refreshed_at = int(doc.get("refreshed", 0))
	for hex in doc.get("palette", []):
		out.palette.append(String(hex))
	return out
