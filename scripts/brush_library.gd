class_name BrushLibrary
extends RefCounted

# Every brush is a stamp texture (white RGB, shaped alpha) plus dynamics.
# The stamp is tinted at draw time, so one texture serves every colour.

## Stamps are generated once and reused at every size. 256 means a 400px
## brush is being shrunk rather than stretched, which is the difference
## between a crisp edge and a soft one.
const STAMP_PX: int = 256

class Preset:
	var id: String = ""
	## Which family this belongs to, and which of its five shapes it is.
	## Variants share a family's rhythm — its spacing, its scatter, the way
	## it answers to speed — and differ only in the stamp itself. That is
	## what keeps five inks feeling like ink.
	var family: String = ""
	var variant: int = 0
	var name_en: String = ""
	var name_ar: String = ""
	## Built the first time this brush is actually painted with. Generating
	## all eight at 256 pixels on startup is around half a million pixel
	## operations before the first frame is shown, paid for brushes most
	## sessions never touch.
	var texture: ImageTexture = null
	var spacing: float = 0.10       # stamp gap as a fraction of size
	var scatter: float = 0.0        # random offset, fraction of size
	var angle_jitter: float = 0.0   # radians
	var size_jitter: float = 0.0    # fraction
	var follow_direction: bool = false
	var speed_thin: float = 0.0     # how much a fast stroke thins the mark
	var default_size: float = 22.0
	var default_opacity: float = 1.0

var presets: Array[Preset] = []

## A stamp is a fixed picture, so painting at 600 pixels from a 256 pixel
## stamp is asking one pixel to cover six — which is exactly the softness
## that shows up on large brushes. When a size asks for more than the stamp
## holds, a bigger one is generated once and kept.
var _large: Dictionary = {}

func _init() -> void:
	_build()

## The stamp to use at this size: the standard one until it would be
## stretched, then a purpose-built larger one.
func texture_for(index: int, dab_size: float) -> Texture2D:
	var p: Preset = get_preset(index)
	if p == null:
		return null
	if dab_size <= float(STAMP_PX) * 1.05:
		return standard_texture(p)
	if _large.has(p.id):
		return _large[p.id]
	var big: ImageTexture = _build_large(p)
	_large[p.id] = big
	return big

## Regenerates one preset's shape at double resolution. Done once per brush,
## the first time someone paints large with it.
func _build_large(p: Preset) -> ImageTexture:
	var keep: int = _px
	_px = STAMP_PX * 2
	var tex: ImageTexture = make_texture(_shape_for(p.id))
	_px = keep
	return tex

func get_preset(i: int) -> Preset:
	if presets.is_empty():
		return null
	return presets[clampi(i, 0, presets.size() - 1)]

## The standard stamp for a preset, generated on first use and kept.
func standard_texture(p: Preset) -> ImageTexture:
	if p == null:
		return null
	if p.texture == null:
		p.texture = make_texture(_shape_for(p.id))
	return p.texture

## One place that knows which shape belongs to which brush, used both for
## the standard stamp and for the larger one big sizes need.
## The stamp for one preset: its family decides the kind of mark, its
## variant decides which of the five.
func _shape_for(id: String) -> PackedFloat32Array:
	var parts: PackedStringArray = id.split("_")
	var family: String = parts[0]
	var v: int = int(parts[1]) if parts.size() > 1 else 0
	match family:
		"pen":
			match v:
				0: return round_buffer(0.94)          # clean liner
				1: return round_buffer(0.99)          # hard technical
				2: return _nib_buffer(0.95, 0.42, -PI * 0.25)   # chisel
				3: return _nib_buffer(0.90, 0.62, PI * 0.25)    # italic
				_: return _dry_buffer(0.92, 0.30, 0.35)         # pencil-ish
		"ink":
			match v:
				0: return round_buffer(0.55)          # soft round
				1: return round_buffer(0.20)          # wet, bleeding
				2: return _nib_buffer(0.60, 0.35, 0.0)          # broad nib
				3: return _dry_buffer(0.55, 0.11, 0.55)         # dry brush
				_: return _dry_buffer(0.35, 0.34, 0.70)         # rough ink
		"airbrush":
			match v:
				0: return round_buffer(0.0)
				1: return round_buffer(0.18)          # tighter core
				2: return round_buffer(0.35)          # nearly a soft round
				3: return _dry_buffer(0.05, 0.24, 0.50)         # speckled
				_: return _nib_buffer(0.0, 0.55, PI * 0.5)      # oval spray
		"watercolor":
			match v:
				0: return _watercolor_buffer(1337, 1.0)
				1: return _watercolor_buffer(4801, 0.55)        # broader wash
				2: return _watercolor_buffer(2209, 1.8)         # ragged edge
				3: return _watercolor_buffer(6633, 2.6)         # granulating
				_: return _watercolor_buffer(8842, 0.35)        # flat wash
		"paint":
			match v:
				0: return _bristle_buffer(4242, 1.0)
				1: return _bristle_buffer(1120, 0.5)            # few, fat
				2: return _bristle_buffer(9033, 1.8)            # dense
				3: return _bristle_buffer(3377, 1.35)           # flat brush
				_: return _dry_buffer(0.45, 0.09, 0.65)         # scrub
		"spruce":
			match v:
				0: return _spruce_buffer(777, 1.0)
				1: return _spruce_buffer(1414, 0.55)            # sparse
				2: return _spruce_buffer(2828, 1.7)             # thick
				3: return _spruce_buffer(5656, 2.4)             # bushy
				_: return _spruce_buffer(9999, 0.8)             # young
		"leaves":
			match v:
				0: return _leaves_buffer(2024, 1.0)
				1: return _leaves_buffer(1701, 0.45)            # scattered
				2: return _leaves_buffer(3141, 1.8)             # dense
				3: return _leaves_buffer(2718, 2.6)             # canopy
				_: return _leaves_buffer(1618, 0.7)             # sprig
		"light":
			# A hot core, a spread that falls away by inverse square, and
			# for two of them a flare. The five are genuinely different
			# lights rather than five sizes of the same one.
			match v:
				0: return _light_buffer(0.16, 0.22, 0)      # a bright bulb
				1: return _light_buffer(0.06, 0.10, 0)      # neon filament
				2: return _light_buffer(0.26, 0.42, 0)      # broad lamp
				3: return _light_buffer(0.14, 0.26, 4)      # four-point flare
				_: return _light_buffer(0.05, 0.58, 0)      # ambient haze
		"cloud":
			# Five weathers, not five sizes. A wisp and a thunderhead are
			# built by the same recursion at settings far enough apart that
			# nobody would mistake one for the other.
			match v:
				# Fat billows, a firm flat base: fair-weather cumulus.
				0: return _cloud_buffer(3300, 1.0, 1.0, 0.60)
				# Cirrus: few lumps, barely any weight to the underside, so
				# it drags out into a streak instead of piling up.
				1: return _cloud_buffer(5150, 0.45, 0.35, 1.30)
				# A thunderhead: crowded, hard-lit on top, cut off sharply
				# beneath — the anvil sitting on its own flat floor.
				2: return _cloud_buffer(7720, 1.9, 1.8, 0.34)
				# One small puff, for the little clouds that sit apart from
				# the bank.
				3: return _cloud_buffer(1180, 0.5, 1.2, 0.75)
				# Ground mist: almost no lift, no floor, all softness.
				_: return _cloud_buffer(9040, 1.4, 0.15, 1.40)
		"foliage":
			# Five plants. The last two are not clumps at all — a frond runs
			# along one heading and undergrowth is small and low — so the
			# family covers a tree and the ground under it.
			match v:
				# A round bush: many short sprays facing every way.
				0: return _foliage_buffer(8100, 1.0, 1.0, 1.0, 0.15)
				# A sprig: one or two twigs, few leaves, for edges and gaps.
				1: return _foliage_buffer(2450, 0.35, 0.5, 1.0, 0.45)
				# Canopy: dense and large, for filling the body of a tree.
				2: return _foliage_buffer(6390, 1.9, 1.6, 1.25, 0.10)
				# A frond: leaves marching along one direction, which is a
				# fern or a palm rather than a bush.
				3: return _foliage_buffer(4870, 0.5, 2.2, 0.9, 0.95)
				# Undergrowth: small leaves, loosely spread.
				_: return _foliage_buffer(1560, 1.3, 0.8, 0.55, 0.30)
		"skydust":
			# Five kinds of light in the air, from a pinprick to a shaft.
			match v:
				# Plain motes: mostly specks, no rings.
				0: return _mote_buffer(4400, 1.0, 1.0, 0.0, 0.0)
				# Bokeh: fewer and much larger, and every large one a ring —
				# the out-of-focus lights behind a subject.
				1: return _mote_buffer(8810, 0.35, 2.4, 1.0, 0.0)
				# Pollen: very many, very small, no rings at all.
				2: return _mote_buffer(2270, 2.6, 0.42, 0.0, 0.0)
				# Fireflies: a handful of bright points, each with a halo.
				3: return _mote_buffer(6600, 0.18, 1.7, 0.35, 0.0)
				# A shaft: haze across the middle with dust hanging in it,
				# meant to be dragged along a ray rather than dabbed.
				_: return _mote_buffer(3960, 0.8, 1.1, 0.5, 0.55)
		"sketch":
			# Five things to draw a line with. All keep their spine and are
			# broken only at the edges — see `_tooth_buffer` — and they
			# differ in how hard the edge is bitten and how big the grain is.
			match v:
				# A marker: firm, a little tooth, an even edge.
				0: return _tooth_buffer(0.88, 0.45, 2.6, 0.06, 9100)
				# A hairline: nearly clean, fine grain, for the thin one on
				# the reference sheet.
				1: return _tooth_buffer(0.96, 0.26, 1.7, 0.02, 3310)
				# A chisel: the same tooth on a squashed stamp, so the line
				# thickens and thins with its heading.
				2: return _tooth_chisel(0.86, 0.42, 2.8, 0.08, 5540)
				# A crayon: bitten deep, coarse flecks, broken through the
				# middle as well.
				3: return _tooth_buffer(0.72, 0.80, 3.4, 0.26, 7780)
				# Charcoal: soft-edged and very grainy, the heaviest of them.
				_: return _tooth_buffer(0.40, 0.88, 4.2, 0.32, 1290)
		"web", "halo", "chalk":
			# Generated natively, and lifted into `brush_extra.gd` — see the
			# note at the top of that file about paying for the growth.
			return BrushExtra.stamp_for(self, family, v, _px)
		"fur":
			match v:
				0: return _fur_buffer(5150, 1.0)
				1: return _fur_buffer(6060, 0.5)                # coarse
				2: return _fur_buffer(7070, 1.7)                # fine
				3: return _fur_buffer(8080, 2.4)                # thick pelt
				_: return _fur_buffer(9090, 0.75)               # short
	return round_buffer(0.7)

# ---------------------------------------------------------------- building

## Thirteen families, five shapes each.
##
## A family is a way of behaving: how far apart the stamps fall, how much
## they scatter and turn, whether they follow the stroke, how speed thins
## the mark. Its five variants share all of that and differ only in the
## stamp — so five inks feel like ink, and choosing among them is choosing a
## nib rather than a different tool.
const FAMILIES: Array = [
	# id, English, Arabic, spacing, scatter, angle jitter, size jitter,
	# follow, speed thin, size, opacity
	["pen", "Pen", "قلم", 0.06, 0.0, 0.0, 0.0, false, 0.25, 8.0, 1.0],
	["ink", "Ink", "حبر", 0.07, 0.0, 0.0, 0.0, false, 0.0, 16.0, 1.0],
	["watercolor", "Watercolor", "ألوان مائية", 0.16, 0.06, PI, 0.18,
		false, 0.0, 90.0, 0.35],
	["paint", "Paint", "دهان", 0.05, 0.0, 0.0, 0.08, true, 0.0, 60.0, 0.75],
	["spruce", "Spruce", "شجر صنوبر", 0.30, 0.22, 0.5, 0.35, false, 0.55,
		70.0, 1.0],
	["leaves", "Leaves", "أوراق شجر", 0.34, 0.30, PI, 0.40, false, 0.0,
		80.0, 1.0],
	["fur", "Fur", "فرو", 0.12, 0.0, 0.25, 0.25, true, 0.0, 55.0, 0.85],
	["airbrush", "Airbrush", "رذاذ", 0.04, 0.0, 0.0, 0.0, false, 0.0,
		70.0, 0.12],
	# Light falls very close together and never turns: a glow is a
	# continuous thing, and a gap between two dabs shows as a bead on the
	# stroke rather than as texture. It also never thins with speed —
	# light does not run out because a hand moved quickly.
	["light", "Light", "ضوء", 0.03, 0.0, 0.0, 0.0, false, 0.0, 64.0, 0.55],

	# --- four families built from the reference sheets ---
	#
	# Each is a way of behaving before it is a set of shapes, and each of the
	# four behaves quite unlike the others.
	#
	# **Cloud** is laid down in overlapping passes rather than drawn: the
	# stamps fall close, turn freely, and vary in size, so dragging once
	# gives a bank of billows instead of a sausage. It never thins with
	# speed — a cloud has no nib to run dry.
	["cloud", "Cloud", "غيوم", 0.055, 0.16, PI, 0.34, false, 0.0,
		150.0, 0.34],

	# **Foliage** is stamped, not stroked. The gap is wide and the turn is
	# free, because a clump of leaves put down twice in the same place at
	# the same angle is obviously one clump printed twice.
	["foliage", "Foliage", "أوراق وأشجار", 0.42, 0.34, PI, 0.42, false,
		0.0, 95.0, 1.0],

	# **Sky dust** is scattered wide and set light. Dust is sparse by
	# nature, and the mistake every dust brush makes is being dense enough
	# to read as a stain. Very free scatter and a low opacity mean it is
	# built up in passes, which is also how it is looked at.
	["skydust", "Sky dust", "غبار الضوء", 0.30, 0.85, PI, 0.55, false,
		0.0, 130.0, 0.30],

	# **Sketch** is the only one of the four that is a line. It follows the
	# stroke and thins hard with speed, which together are what make a
	# flicked mark taper the way the reference sheet's do.
	["sketch", "Sketch line", "خط رسم", 0.045, 0.0, 0.0, 0.05, true,
		0.45, 14.0, 1.0],

]

## What each variant is called within its family. The same five words for
## every family, because they mean the same thing everywhere: the first is
## the plain one, and the rest are the ways it is usually varied.
const VARIANT_NAMES: Array = [
	["Plain", "عادية"],
	["Fine", "رفيعة"],
	["Broad", "عريضة"],
	["Rough", "خشنة"],
	["Soft", "ناعمة"],
]

## Families whose five are genuinely different things rather than five sizes
## of one thing, and so are named for what they are.
##
## The shared five words — plain, fine, broad, rough, soft — are right when
## the variants really are one shape at five settings. They are useless for a
## family where one variant is a thunderhead and another is a wisp of cirrus,
## and a name that says nothing is worse than no name at all.
const SPECIAL_NAMES: Dictionary = {
	"light": [
		["Bulb", "مصباح"], ["Filament", "خيط متوهج"], ["Lamp", "ضوء واسع"],
		["Flare", "توهج نجمي"], ["Haze", "ضباب ضوئي"],
	],
	"cloud": [
		["Cumulus", "ركامية"], ["Wisp", "خصلة"], ["Thunderhead", "رأس عاصفة"],
		["Puff", "نفخة"], ["Mist", "ضباب"],
	],
	"foliage": [
		["Bush", "شجيرة"], ["Sprig", "غصين"], ["Canopy", "ظُلَّة"],
		["Frond", "سعفة"], ["Undergrowth", "أعشاب"],
	],
	"skydust": [
		["Motes", "ذرات"], ["Bokeh", "هالات"], ["Pollen", "لقاح"],
		["Fireflies", "يراعات"], ["Shaft", "عمود ضوء"],
	],
	"sketch": [
		["Marker", "قلم عريض"], ["Hairline", "شعرة"], ["Chisel", "إزميل"],
		["Crayon", "طباشير"], ["Charcoal", "فحم"],
	],
}

const PER_FAMILY: int = 5

func _build() -> void:
	presets.clear()
	# The stage-137 families live in `brush_extra.gd`, appended rather than
	# slotted in: a preset index is written into every saved project, and
	# inserting a family in the middle would change what old files paint.
	for row in (FAMILIES + BrushExtra.families()):
		for v in PER_FAMILY:
			var p: Preset = Preset.new()
			p.family = String(row[0])
			p.variant = v
			p.id = "%s_%d" % [p.family, v]
			# A family with its own five words uses them; everything else
			# takes the shared ones.
			var words: Array = BrushExtra.names_for(p.family)
			if words.is_empty():
				words = SPECIAL_NAMES.get(p.family, VARIANT_NAMES)
			p.name_en = "%s %s" % [String(row[1]), String(words[v][0])]
			p.name_ar = "%s %s" % [String(row[2]), String(words[v][1])]
			p.spacing = float(row[3])
			p.scatter = float(row[4])
			p.angle_jitter = float(row[5])
			p.size_jitter = float(row[6])
			p.follow_direction = bool(row[7])
			p.speed_thin = float(row[8])
			p.default_size = float(row[9])
			p.default_opacity = float(row[10])
			_tune(p)
			presets.append(p)

## Small adjustments where a variant's shape asks for them. A dry stamp
## needs to fall closer together or the gaps in it become gaps in the line;
## a broad nib wants a little more room. Everything else stays as the
## family set it.
func _tune(p: Preset) -> void:
	match p.variant:
		1:
			# Fine: smaller, and it tapers a little more with speed, the way
			# a thin nib naturally does.
			p.default_size *= 0.68
			p.speed_thin = minf(p.speed_thin + 0.15, 0.85)
			p.size_jitter *= 0.6
		2:
			# Broad: wider, set further apart, and steadier — a broad mark
			# with the same jitter as a fine one looks ragged rather than
			# confident.
			p.default_size *= 1.35
			p.spacing *= 1.15
			p.size_jitter *= 0.5
			p.angle_jitter *= 0.5
		3:
			# Rough: the stamp has gaps in it, so the stamps must fall
			# closer together or its gaps become gaps in the line. A touch
			# more opacity makes up for the ink it loses.
			p.spacing *= 0.55
			p.default_opacity = minf(p.default_opacity * 1.15, 1.0)
			p.size_jitter = maxf(p.size_jitter, 0.10)
		4:
			# Soft: larger, closer, and lighter — it builds up rather than
			# covering in one pass, which is what soft means in practice.
			p.default_size *= 1.15
			p.spacing *= 0.8
			p.default_opacity *= 0.85

	# --- the four reference families ---
	#
	# The shared tuning above is written for a mark made with a nib, and each
	# of these breaks it somewhere. Where it is left alone, it is because it
	# happens to be right.

	if BrushExtra.owns(p.family):
		BrushExtra.tune(p, p.family)

	if p.family == "cloud":
		# A cloud never runs dry, and it is always built up in passes rather
		# than laid down in one. The variant sizes are set outright because
		# a wisp and a thunderhead are not the same cloud at two sizes.
		p.speed_thin = 0.0
		match p.variant:
			1:
				p.default_size = 130.0
				p.default_opacity = 0.22
			2:
				p.default_size = 210.0
				p.default_opacity = 0.42
			3:
				p.default_size = 62.0
				p.default_opacity = 0.40
			4:
				p.default_size = 240.0
				p.default_opacity = 0.16
				p.spacing = 0.04

	elif p.family == "foliage":
		p.speed_thin = 0.0
		match p.variant:
			1:
				# A sprig is small and goes at the edges, so it needs to be
				# placeable one at a time rather than dragged.
				p.default_size = 48.0
				p.spacing = 0.55
			2:
				p.default_size = 150.0
				p.spacing = 0.34
			3:
				# A frond has a heading of its own, so it follows the stroke
				# and stops turning at random — a fern whose leaves point
				# every way is not a fern.
				p.default_size = 105.0
				p.follow_direction = true
				p.angle_jitter = 0.22
				p.spacing = 0.30
			4:
				p.default_size = 60.0
				p.scatter = 0.45

	elif p.family == "skydust":
		p.speed_thin = 0.0
		match p.variant:
			1:
				# Bokeh is few and large and wants to be seen singly.
				p.default_size = 175.0
				p.default_opacity = 0.42
				p.spacing = 0.55
			2:
				p.default_size = 95.0
				p.default_opacity = 0.24
				p.spacing = 0.18
			3:
				p.default_size = 150.0
				p.default_opacity = 0.55
				p.spacing = 0.70
			4:
				# A shaft is dragged along the light, so it holds its
				# heading and does not scatter away from the ray.
				p.default_size = 200.0
				p.default_opacity = 0.26
				p.follow_direction = true
				p.angle_jitter = 0.0
				p.scatter = 0.10
				p.spacing = 0.05

	elif p.family == "sketch":
		# Every one of the five is a line, so they all follow the stroke and
		# they all taper. What the shared tuning gets wrong here is opacity:
		# a broken edge is *meant* to show the paper, and topping the opacity
		# up to make good the ink it loses fills the tooth back in.
		p.follow_direction = true
		match p.variant:
			1:
				p.default_size = 8.0
				p.speed_thin = 0.55
			2:
				p.default_size = 20.0
				p.speed_thin = 0.30
			3:
				p.default_size = 24.0
				p.default_opacity = 0.92
				p.spacing = 0.035
			4:
				p.default_size = 30.0
				p.default_opacity = 0.85
				p.spacing = 0.03

	# Light keeps its own names and its own rhythm.
	#
	# The shared tuning above is written for marks made of pigment, and two
	# of its rules are wrong for a glow: thinning with speed, which light
	# does not do, and the loose spacing a broad mark wants, which leaves a
	# glow beaded instead of continuous.
	if p.family == "light":
		p.speed_thin = 0.0
		p.spacing = minf(p.spacing, 0.035)
		match p.variant:
			1:
				# A filament is thin and fierce.
				p.default_size = 26.0
				p.default_opacity = 0.85
			2:
				p.default_size = 130.0
				p.default_opacity = 0.40
			3:
				p.default_size = 90.0
				p.default_opacity = 0.60
			4:
				# Haze is meant to be built up in passes, never laid down
				# in one.
				p.default_size = 190.0
				p.default_opacity = 0.22

## The families, in order, for a panel that shows them as one row.
#
# ## Why these are not just `round_buffer` with a hard edge
#
# They nearly are, and the difference is the whole point. `round_buffer` takes
# a hardness and fades from it outward, which is right for a brush: the fade is
# what lets two overlapping dabs read as one stroke rather than two circles.
#
# A knife dot must read as a circle. So the edge here is a **one-pixel
# transition** — solid inside, nothing outside, and exactly one row of
# in-between pixels to keep it from looking sawn. That single row is
# antialiasing and nothing more; it is not a soft edge and it does not grow
# with the brush, because the stamp is generated at the size it is drawn.
#
# The result is a dot with a definite boundary, which is what the reference
# sheets show and is what makes a row of them read as a pattern rather than as
# a dotted line drawn by hand.

func families() -> Array:
	var out: Array = []
	for row in FAMILIES:
		out.append({"id": String(row[0]), "en": String(row[1]),
			"ar": String(row[2])})
	return out

func index_of(family_index: int, variant: int) -> int:
	return clampi(family_index, 0, FAMILIES.size() - 1) * PER_FAMILY \
		+ clampi(variant, 0, PER_FAMILY - 1)

func family_index_of(preset_index: int) -> int:
	var i: int = floori(float(clampi(preset_index, 0, presets.size() - 1)) / float(PER_FAMILY))
	return i

func variant_of(preset_index: int) -> int:
	return clampi(preset_index, 0, presets.size() - 1) % PER_FAMILY

# ---------------------------------------------------------------- helpers

## The shapes below were tuned on a 128px stamp. This keeps their
## proportions when the stamp grows, rather than re-tuning twenty numbers.
## The working size for the stamp being generated right now. Normally the
## constant; briefly doubled while a large variant is built.
var _px: int = STAMP_PX

## The shapes below were tuned on a 128px stamp. This keeps their
## proportions whatever the stamp is generated at.
var S: float = float(STAMP_PX) / 128.0

func _blank() -> PackedFloat32Array:
	S = float(_px) / 128.0
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(_px * _px)
	b.fill(0.0)
	return b

## Soft dot blended with max() so overlapping dabs never bloom past 1.0.
func _dab(buf: PackedFloat32Array, cx: float, cy: float,
		radius: float, strength: float) -> void:
	var r: float = maxf(radius, 0.6)
	var x0: int = maxi(int(floor(cx - r)), 0)
	var x1: int = mini(int(ceil(cx + r)), _px - 1)
	var y0: int = maxi(int(floor(cy - r)), 0)
	var y1: int = mini(int(ceil(cy + r)), _px - 1)
	for y in range(y0, y1 + 1):
		var dy: float = float(y) - cy
		for x in range(x0, x1 + 1):
			var dx: float = float(x) - cx
			var d: float = sqrt(dx * dx + dy * dy) / r
			if d >= 1.0:
				continue
			var a: float = (1.0 - d * d) * strength
			var i: int = y * _px + x
			if a > buf[i]:
				buf[i] = a

## A dab with a flat top: solid across most of itself, soft only at the rim.
##
## `_dab` above is a dome — full strength at its exact centre and falling away
## from there — which is right for building a soft brush out of many small
## marks and wrong for building a *shape* out of a few large ones. Because
## dabs blend by taking whichever is stronger, a small dome laid on a big one
## reaches a higher value in its little middle than the big one has anywhere
## nearby, and shows as a dark spot. Every billow of a cloud and every leaf of
## a canopy came out with its own visible disc inside the mass.
##
## A plateau has no such middle. Two overlapping plateaus are one shape with
## one silhouette, which is exactly what a cloud is and what a painted leaf
## is. `edge` is how much of the radius is given over to the falloff.
func _puff(buf: PackedFloat32Array, cx: float, cy: float, radius: float,
		edge: float, strength: float) -> void:
	var r: float = maxf(radius, 0.6)
	var soft: float = clampf(edge, 0.02, 1.0)
	var x0: int = maxi(int(floor(cx - r)), 0)
	var x1: int = mini(int(ceil(cx + r)), _px - 1)
	var y0: int = maxi(int(floor(cy - r)), 0)
	var y1: int = mini(int(ceil(cy + r)), _px - 1)
	for y in range(y0, y1 + 1):
		var dy: float = float(y) - cy
		for x in range(x0, x1 + 1):
			var dx: float = float(x) - cx
			var d: float = sqrt(dx * dx + dy * dy) / r
			if d >= 1.0:
				continue
			var a: float = (1.0 - smoothstep(1.0 - soft, 1.0, d)) * strength
			var i: int = y * _px + x
			if a > buf[i]:
				buf[i] = a

func _line(buf: PackedFloat32Array, a: Vector2, b: Vector2,
		r0: float, r1: float, strength: float) -> void:
	var steps: int = maxi(int(a.distance_to(b) / maxf(r0, 0.8) * 1.6), 2)
	for s in range(steps + 1):
		var t: float = float(s) / float(steps)
		var p: Vector2 = a.lerp(b, t)
		_dab(buf, p.x, p.y, lerpf(r0, r1, t), strength)

func make_texture(buf: PackedFloat32Array) -> ImageTexture:
	var img: Image = Image.create_empty(_px, _px, false, Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(_px * _px * 4)
	for i in range(_px * _px):
		var a: int = int(clampf(buf[i], 0.0, 1.0) * 255.0)
		var o: int = i * 4
		bytes[o] = 255
		bytes[o + 1] = 255
		bytes[o + 2] = 255
		bytes[o + 3] = a
	img.set_data(_px, _px, false, Image.FORMAT_RGBA8, bytes)
	# Mipmaps matter more than they look: a 4px pen samples a 256px stamp,
	# and without them that is a lottery of single pixels — the source of
	# the crawling, sparkling edge on thin strokes.
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ----------------------------------------------------------------- shapes

## A solid square of the current stamp size, for the square eraser.
func solid_buffer() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	buf.fill(1.0)
	return buf

func round_buffer(hardness: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var c: float = float(_px) * 0.5
	var rad: float = c - 2.0
	var inner: float = clampf(hardness, 0.0, 0.98)
	for y in _px:
		for x in _px:
			var d: float = Vector2(float(x) - c + 0.5, float(y) - c + 0.5).length() / rad
			var a: float = 0.0
			if d < 1.0:
				a = 1.0 - smoothstep(inner, 1.0, d)
			buf[y * _px + x] = a
	return buf

## Light, built the way light behaves rather than the way a soft brush does.
##
## A soft round brush falls off in a smooth curve from the middle to the
## edge, and it reads as a blurry blob because nothing in the world dims like
## that. Light has two parts and they are not the same shape: a core that is
## simply *saturated* — as bright as the medium goes, flat across its whole
## width — and around it a spread that falls away by the inverse square of
## distance, which is the law light actually obeys. The two together give the
## small fierce middle and the long faint reach that the eye reads as
## something glowing, instead of something smudged.
##
## `spikes`, when asked for, adds a flare: the spread is doubled along a few
## directions and left alone elsewhere. That is what a lens does with a bright
## point, and it is why four-point stars appear around highlights in a
## photograph.
##
## The whole stamp is faded out over its last fifth. Without that, the spread
## would still be faintly alive when it reached the edge of the texture and
## every dab would carry a square boundary in it.
func _light_buffer(core: float, spread: float, spikes: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var c: float = float(_px) * 0.5
	var rad: float = c - 2.0
	var reach: float = maxf(spread, 0.0001)
	for y in _px:
		for x in _px:
			var off: Vector2 = Vector2(float(x) - c + 0.5, float(y) - c + 0.5)
			var d: float = off.length() / rad
			if d >= 1.0:
				buf[y * _px + x] = 0.0
				continue
			# The core: full strength, easing out over its outer third so
			# there is no visible disc edge inside the glow.
			var v: float = 1.0 - smoothstep(core * 0.35, core, d)
			# The spread: inverse square, the law light obeys.
			var halo: float = 1.0 / (1.0 + (d / reach) * (d / reach))
			v = maxf(v, halo * 0.92)
			if spikes > 0:
				# Sharpened by raising to a high power, so a spike is a
				# narrow ray rather than a broad lobe.
				var along: float = absf(cos(off.angle() * float(spikes) * 0.5))
				var ray: float = pow(along, 14.0)
				v += ray * halo * 0.85
			buf[y * _px + x] = clampf(v, 0.0, 1.0) \
				* (1.0 - smoothstep(0.80, 1.0, d))
	return buf

## A nib: a round stamp squashed along one axis and turned.
##
## Drawing with it gives a line that thickens and thins with direction —
## what a chisel or an italic nib does, and what a plain disc never can.
## The corners are eased slightly so the ends of a stroke are not two hard
## points, which is the one place a squashed disc gives itself away.
func _nib_buffer(hardness: float, squash: float, angle: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var c: float = float(_px) * 0.5
	var r: float = c - 2.0 * S
	var turn: Vector2 = Vector2(cos(angle), sin(angle))
	for y in _px:
		for x in _px:
			var d: Vector2 = Vector2(float(x) - c, float(y) - c)
			# Measured in the nib's own frame, so the squash follows the
			# angle rather than the screen.
			var along: float = d.dot(turn)
			var across: float = d.dot(Vector2(-turn.y, turn.x))
			# A superellipse rather than a plain ellipse: the exponent
			# rounds the two ends without fattening the middle.
			var u: float = absf(along) / r
			var v: float = absf(across) / (r * maxf(squash, 0.05))
			var reach: float = pow(pow(u, 2.4) + pow(v, 2.4), 1.0 / 2.4)
			var a: float = 0.0
			if reach < 1.0:
				a = 1.0 - smoothstep(clampf(hardness, 0.0, 0.98), 1.0, reach)
			buf[y * _px + x] = a
	return buf

## A dry stamp: a round one with its ink broken up, for a brush that has
## almost run out.
##
## Three things make this read as tooth on paper rather than as static:
##
##   The grain is *multiplied* in, never added, so the silhouette stays
##   round and only the coverage suffers.
##
##   Two frequencies are used together — a coarse one for the clumps and a
##   finer one for the tooth inside them. One frequency alone looks like
##   noise; two look like a surface.
##
##   The break-up strengthens toward the rim. A dry brush loses its edge
##   first and keeps ink longest in the middle, and doing this evenly is
##   what makes cheap dry brushes look like a photocopy.
func _dry_buffer(hardness: float, grain_size: float, bite: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = round_buffer(hardness)
	var coarse: FastNoiseLite = FastNoiseLite.new()
	coarse.set_seed(9091)
	coarse.noise_type = FastNoiseLite.TYPE_SIMPLEX
	coarse.frequency = grain_size / S

	var fine: FastNoiseLite = FastNoiseLite.new()
	fine.set_seed(3312)
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fine.frequency = (grain_size * 3.1) / S

	var c: float = float(_px) * 0.5
	var rad: float = c - 2.0 * S
	for y in _px:
		for x in _px:
			var i: int = y * _px + x
			if buf[i] <= 0.0:
				continue
			var n: float = (coarse.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var g: float = (fine.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var tooth: float = n * 0.72 + g * 0.28
			var edge: float = clampf(
				Vector2(float(x) - c, float(y) - c).length() / rad, 0.0, 1.0)
			var strength: float = bite * (0.55 + 0.45 * edge)
			buf[i] *= clampf(1.0 - strength + tooth * strength * 1.9, 0.0, 1.0)
	return buf

func _watercolor_buffer(seed_at: int = 1337, edge_bite: float = 1.0) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var c: float = float(_px) * 0.5
	var rad: float = c - 3.0

	var edge: FastNoiseLite = FastNoiseLite.new()
	edge.set_seed(seed_at)
	edge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	edge.frequency = (0.020 * edge_bite) / S

	var grain: FastNoiseLite = FastNoiseLite.new()
	grain.set_seed(seed_at + 61)
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = 0.16 / S

	for y in _px:
		for x in _px:
			var v: Vector2 = Vector2(float(x) - c + 0.5, float(y) - c + 0.5)
			var d: float = v.length() / rad
			var wobble: float = edge.get_noise_2d(float(x), float(y)) * 0.22
			var a: float = 1.0 - smoothstep(0.28 + wobble, 1.0 + wobble, d)
			if a <= 0.0:
				continue
			# paper grain, plus the darker rim real watercolour leaves behind
			var g: float = 0.72 + 0.28 * (grain.get_noise_2d(float(x), float(y)) * 0.5 + 0.5)
			var rim: float = 1.0 + 0.45 * smoothstep(0.55, 0.95, d)
			buf[y * _px + x] = clampf(a * g * rim, 0.0, 1.0)
	return buf

func _bristle_buffer(seed_at: int = 4242, bristle_density: float = 1.0) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.set_seed(seed_at)
	var w: float = float(_px)
	for i in int(46.0 * S * bristle_density):
		var y: float = 8.0 * S + rng.randf() * (w - 16.0 * S)
		var thick: float = rng.randf_range(0.7, 2.0) * S
		var strength: float = rng.randf_range(0.35, 1.0)
		var sway: float = rng.randf_range(-3.0, 3.0) * S
		var prev: Vector2 = Vector2(4.0 * S, y)
		var seg: int = 6
		for s in range(1, seg + 1):
			var t: float = float(s) / float(seg)
			var p: Vector2 = Vector2(4.0 * S + (w - 8.0 * S) * t, y + sin(t * PI) * sway)
			_line(buf, prev, p, thick, thick, strength)
			prev = p
	# fade the two ends so consecutive stamps blend into a continuous streak
	for y2 in _px:
		for x2 in _px:
			var fx: float = absf(float(x2) - w * 0.5) / (w * 0.5)
			buf[y2 * _px + x2] *= 1.0 - smoothstep(0.75, 1.0, fx)
	return buf

func _spruce_buffer(seed_at: int = 777, branch_density: float = 1.0) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.set_seed(seed_at)
	var c: Vector2 = Vector2(float(_px) * 0.5, float(_px) * 0.5)
	for i in int(9.0 * branch_density):
		var ang: float = rng.randf_range(0.0, TAU)
		var length: float = rng.randf_range(24.0, 52.0) * S
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		var base: Vector2 = c + dir * rng.randf_range(0.0, 16.0) * S
		var tip: Vector2 = base + dir * length
		_line(buf, base, tip, 2.2 * S, 0.8 * S, 0.95)
		var needles: int = 9
		for n in range(1, needles):
			var t: float = float(n) / float(needles)
			var along: Vector2 = base.lerp(tip, t)
			var nlen: float = (1.0 - t) * rng.randf_range(7.0, 13.0) * S
			for side in [-1.0, 1.0]:
				var na: float = ang + side * rng.randf_range(0.7, 1.15)
				_line(buf, along, along + Vector2(cos(na), sin(na)) * nlen,
					1.5 * S, 0.5 * S, rng.randf_range(0.5, 0.95))
	return buf

func _leaves_buffer(seed_at: int = 2024, leaf_density: float = 1.0) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.set_seed(seed_at)
	var c: Vector2 = Vector2(float(_px) * 0.5, float(_px) * 0.5)
	for i in int(26.0 * S * leaf_density):
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = sqrt(rng.randf()) * (float(_px) * 0.42)
		var pos: Vector2 = c + Vector2(cos(ang), sin(ang)) * dist
		var leaf_ang: float = rng.randf_range(0.0, TAU)
		var leaf_len: float = rng.randf_range(6.0, 13.0) * S
		var dir: Vector2 = Vector2(cos(leaf_ang), sin(leaf_ang))
		var strength: float = rng.randf_range(0.45, 1.0)
		# taper: thin at both tips, fat in the middle
		_line(buf, pos - dir * leaf_len, pos, 0.8 * S, 3.2 * S, strength)
		_line(buf, pos, pos + dir * leaf_len, 3.2 * S, 0.8 * S, strength)
	return buf

func _fur_buffer(seed_at: int = 5150, strand_density: float = 1.0) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.set_seed(seed_at)
	var w: float = float(_px)
	for i in int(70.0 * S * strand_density):
		var x: float = rng.randf_range(6.0 * S, w - 6.0 * S)
		var y: float = rng.randf_range(6.0 * S, w - 6.0 * S)
		var ang: float = rng.randf_range(-0.55, 0.55)
		var length: float = rng.randf_range(9.0, 26.0) * S
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		_line(buf, Vector2(x, y), Vector2(x, y) + dir * length,
			1.6 * S, 0.4 * S, rng.randf_range(0.35, 1.0))
	# soften the border so tiled stamps do not show seams
	var c: float = w * 0.5
	for y2 in _px:
		for x2 in _px:
			var d: float = Vector2(float(x2) - c, float(y2) - c).length() / (c - 2.0)
			buf[y2 * _px + x2] *= 1.0 - smoothstep(0.7, 1.0, d)
	return buf

# ------------------------------------------------- clouds, leaves and light

## A cloud, built the way a cloud is shaped rather than blurred.
##
## The reference is a painted sky: fat billows crowding along the top of a
## mass, a flat soft underside, and a rim that is nearly hard where the light
## catches it and dissolves where it does not. Three things make that, and a
## soft round dab makes none of them.
##
## **Billows, not blur.** The silhouette is built from discs — a few large
## ones for the body, then smaller ones crowded around the upper rim of each,
## then smaller again. That is one round of the same recursion a real cumulus
## goes through, and it is why the edge comes out lumpy at two scales instead
## of smooth at one. A gaussian has no lumps at any scale, which is why a
## blurred blob reads as smoke and never as cloud.
##
## **Light from above.** The dabs on top are laid at full strength and the
## ones below at less, so the mass is bright where the sun is and heavy
## underneath — the single cue that tells an eye this is a solid thing with a
## top and a bottom rather than a flat patch of white.
##
## **A base that lets go.** Cumulus sits on a flat bottom because that is the
## height where the air stops being able to hold water. `flatten` is that
## line: above it the shape is free, below it the strength falls away quickly,
## which is what stops a cloud looking like a ball of cotton.
##
## `lumps` is how many big billows, `lift` how strongly the top is favoured
## over the bottom, and `flatten` how sharply the underside is cut.
func _cloud_buffer(seed_at: int = 3300, lumps: float = 1.0,
		lift: float = 1.0, flatten: float = 0.6) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.set_seed(seed_at)
	var c: Vector2 = Vector2(float(_px), float(_px)) * 0.5
	var reach: float = float(_px) * 0.34

	# The body: a few large billows spread wider than they are tall, because a
	# cloud is a thing lying along the air rather than standing in it.
	var big: int = maxi(int(4.0 * lumps), 2)
	var seats: Array = []
	for i in big:
		var across: float = rng.randf_range(-1.0, 1.0) * reach
		var down: float = rng.randf_range(-0.45, 0.30) * reach
		var r: float = rng.randf_range(0.42, 0.72) * reach
		var seat: Vector2 = c + Vector2(across, down * 0.62)
		seats.append([seat, r])
		# Every billow at full strength.
		#
		# Shading them individually was the first attempt and it was wrong:
		# dabs blend by taking whichever is stronger, so a dab at sixty per
		# cent beside one at full shows its own circle wherever the two
		# overlap, and a cloud came out as a heap of visible balls. The
		# silhouette is built solid here and lit afterwards, over the whole
		# shape at once — which is also how light actually falls on a cloud.
		_puff(buf, seat.x, seat.y, r, 0.42, 1.0)

	# The rim: smaller billows crowded around the upper half of each body
	# lump, which is where a cumulus actually cauliflowers.
	for row in seats:
		var seat: Vector2 = row[0]
		var r: float = row[1]
		var crowd: int = maxi(int(9.0 * lumps), 4)
		for k in crowd:
			# Biased to the top half: the angle is drawn across the upper
			# semicircle and only occasionally allowed to fall below.
			var ang: float = rng.randf_range(PI * 1.05, PI * 1.95)
			if rng.randf() < 0.22:
				ang = rng.randf_range(0.0, PI)
			var out: Vector2 = Vector2(cos(ang), sin(ang))
			var small: float = r * rng.randf_range(0.28, 0.52)
			var at: Vector2 = seat + out * (r - small * 0.55)
			_puff(buf, at.x, at.y, small, 0.46, 1.0)
			# One more round, smaller again, on the outermost of them. Two
			# scales of lump is what the eye reads as cloud; one is a blob.
			if rng.randf() < 0.55:
				var tiny: float = small * rng.randf_range(0.35, 0.60)
				var edge: Vector2 = at + out * (small * 0.7)
				_puff(buf, edge.x, edge.y, tiny, 0.52, 1.0)

	# Now the light, the floor and the rim, over the whole silhouette at
	# once.
	#
	# Sun from above: full strength along the top of the mass, falling away
	# toward the bottom by `lift`. Because this runs after the shape is
	# built, it shades the *cloud* rather than the individual billows — so
	# the gradient runs across the whole bank the way daylight does, and no
	# billow shows its own outline inside the mass.
	var floor_at: float = c.y + reach * clampf(flatten, 0.05, 1.4) * 0.55
	var top_at: float = c.y - reach * 0.85
	for y in _px:
		var below: float = (float(y) - floor_at) / maxf(reach * 0.55, 1.0)
		var cut: float = 1.0 - smoothstep(0.0, 1.0, below)
		var down_from_top: float = clampf((float(y) - top_at)
			/ maxf(floor_at - top_at, 1.0), 0.0, 1.0)
		var sun: float = lerpf(1.0, 1.0 - 0.42 * clampf(lift, 0.0, 2.0) * 0.5,
			pow(down_from_top, 0.85))
		for x in _px:
			var i: int = y * _px + x
			if buf[i] <= 0.0:
				continue
			var d: float = Vector2(float(x) - c.x, float(y) - c.y).length() \
				/ (float(_px) * 0.5 - 2.0)
			buf[i] *= cut * sun * (1.0 - smoothstep(0.80, 1.0, d))
	return buf

## One leaf: pointed at the tip, widest a third of the way along, and joined
## to its stem at the other end.
##
## Drawn from its own midrib outward rather than as a stamped oval, so a leaf
## can be any length and any width and still be a leaf. The width follows a
## curve that peaks early — which is what makes it read as a leaf and not as
## an almond — and the last tenth is brought to a point.
func _leaf(buf: PackedFloat32Array, base: Vector2, dir: Vector2,
		length: float, width: float, strength: float) -> void:
	var steps: int = maxi(int(length / 1.6), 6)
	for s in steps + 1:
		var t: float = float(s) / float(steps)
		# Peaks at about a third, tapers to nothing at the tip.
		var w: float = width * pow(sin(pow(t, 0.72) * PI), 0.85)
		if t > 0.90:
			w *= (1.0 - t) / 0.10
		# Flat-topped, so a leaf is a shape with an edge rather than a
		# ridge running down its middle — see `_puff`.
		_puff(buf, base.x + dir.x * length * t, base.y + dir.y * length * t,
			maxf(w, 0.55), 0.55, strength)

## Foliage, in the flat cut-paper manner of the reference.
##
## The `leaves` family already here is made of tapered strokes, and strokes
## give a soft impressionist mass. This is the other kind entirely: whole
## leaves with their own silhouettes, crowded into a clump, the way a painted
## tree is built out of shapes rather than out of marks.
##
## What makes it read as a tree rather than as scattered leaves is that the
## leaves are laid in **sprays** — a handful sharing one direction, springing
## from one point, the way leaves actually come off a twig — and the sprays
## are scattered instead of the leaves. Scattering leaves individually gives
## confetti; scattering sprays gives foliage.
##
## `spray` is how many leaves come off each twig, `clumps` how many twigs,
## `leaf_len` their size, and `along` how strongly a spray keeps one heading
## (near nought is a rosette, near one is a frond).
func _foliage_buffer(seed_at: int = 8100, clumps: float = 1.0,
		spray: float = 1.0, leaf_len: float = 1.0,
		along: float = 0.5) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.set_seed(seed_at)
	var c: Vector2 = Vector2(float(_px), float(_px)) * 0.5
	var reach: float = float(_px) * 0.40

	# Many more twigs than looks necessary written down.
	#
	# The first setting of this was seven, and it rendered as a scatter of
	# leaves with grey between them — leaves, but not foliage. A painted
	# canopy is *mass*: the ink is continuous and the silhouette is broken
	# only at its edge. It takes about four times as many.
	# One heading for the whole stamp, which each twig then departs from by
	# as much as `along` allows.
	#
	# Without this a frond was seventeen twigs each pointing wherever it
	# liked, and the setting meant to make a fern made a slightly tidier
	# bush. A frond is one direction: the twigs share it, and only the
	# leaves fan out from it.
	var stamp_heading: float = rng.randf_range(0.0, TAU)
	var line: float = clampf(along, 0.0, 1.0)
	for i in maxi(int(34.0 * clumps), 5):
		var ang: float = rng.randf_range(0.0, TAU)
		# Square-rooted so the clumps sit evenly over the *area* rather than
		# bunching in the middle, which is the difference between a round
		# bush and a dark blot with a fringe.
		var dist: float = sqrt(rng.randf()) * reach
		var twig: Vector2 = c + Vector2(cos(ang), sin(ang)) * dist
		# Squashed across the heading as `along` rises, so a frond's twigs
		# sit along a spine instead of filling a circle.
		if line > 0.5:
			var spine: Vector2 = Vector2(cos(stamp_heading),
				sin(stamp_heading))
			var off: Vector2 = twig - c
			var across_spine: float = off.dot(Vector2(-spine.y, spine.x))
			twig -= Vector2(-spine.y, spine.x) * across_spine \
				* (line - 0.5) * 1.5
		var heading: float = lerpf(rng.randf_range(0.0, TAU), stamp_heading,
			line)
		var fan: float = lerpf(PI, 0.55, line)

		for k in maxi(int(9.0 * spray), 3):
			var turn: float = heading + rng.randf_range(-fan, fan)
			var dir: Vector2 = Vector2(cos(turn), sin(turn))
			var length: float = rng.randf_range(9.0, 18.0) * S * leaf_len
			# Broader than a first guess suggests. A narrow leaf is a
			# beautiful shape on its own and disappears in a mass, and the
			# reference is a mass.
			var width: float = length * rng.randf_range(0.38, 0.56)
			# Leaves nearer the outside of the clump are lighter, so the
			# clump has a solid heart and a broken edge — which is what a
			# painted canopy does and what an even scatter never does.
			var out: float = clampf(dist / maxf(reach, 1.0), 0.0, 1.0)
			var strength: float = rng.randf_range(0.80, 1.0) \
				* lerpf(1.0, 0.80, out)
			# Started a little way back along the twig so the spray has a
			# stem rather than all springing from one pixel.
			var from: Vector2 = twig - dir * rng.randf_range(0.0, 3.0) * S
			_leaf(buf, from, dir, length, width, strength)

	var edge: float = float(_px) * 0.5 - 2.0
	for y in _px:
		for x in _px:
			var i2: int = y * _px + x
			if buf[i2] <= 0.0:
				continue
			var d: float = Vector2(float(x) - c.x, float(y) - c.y).length() / edge
			buf[i2] *= 1.0 - smoothstep(0.86, 1.0, d)
	return buf

## Dust in the air with light behind it.
##
## The reference is a forest at dusk: motes hanging in a shaft, most of them
## too small to be anything but a point, a few near enough to be little discs
## with a bright edge. Two things have to be right or it reads as noise.
##
## **The sizes must be very unequal.** Dust at a distance is a pinprick and
## dust near the lens is a soft disc, and a scatter of same-sized dots is
## static on a television. The size is drawn from a curve weighted hard toward
## the small end, so most motes are specks and a handful are large — which is
## what gives the depth.
##
## **The big ones must be brighter at the rim than in the middle.** That is
## what an out-of-focus point of light does: it spreads across the shape of
## the lens opening, leaving a disc that is edged rather than filled. Filled
## discs look like paint; edged ones look like light.
##
## `beam` adds a soft shaft of haze through the middle, for the variant meant
## to be dragged along a ray of light rather than dabbed.
func _mote_buffer(seed_at: int = 4400, count: float = 1.0,
		fat: float = 1.0, rim: float = 0.0,
		beam: float = 0.0) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.set_seed(seed_at)
	var c: Vector2 = Vector2(float(_px), float(_px)) * 0.5
	var reach: float = float(_px) * 0.46

	if beam > 0.0:
		# A soft band across the middle: bright along its spine, gone by its
		# edges. Painted first so the motes sit inside it rather than on it.
		var half: float = float(_px) * 0.5 * clampf(beam, 0.05, 1.0)
		for y in _px:
			var off: float = absf(float(y) - c.y) / maxf(half, 1.0)
			if off >= 1.0:
				continue
			var band: float = (1.0 - off * off) * 0.30
			for x in _px:
				var fade: float = 1.0 - smoothstep(0.55, 1.0,
					absf(float(x) - c.x) / reach)
				var i: int = y * _px + x
				buf[i] = maxf(buf[i], band * fade)

	for i2 in maxi(int(70.0 * S * count), 8):
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = sqrt(rng.randf()) * reach
		var at: Vector2 = c + Vector2(cos(ang), sin(ang)) * dist
		# Fourth power: most motes tiny, a few genuinely large. A plain
		# random range gives them all much the same size and the depth dies.
		var roll: float = rng.randf()
		var r: float = lerpf(0.7, 9.0, pow(roll, 4.0)) * S * fat
		var bright: float = lerpf(1.0, 0.65, roll) \
			* (1.0 - smoothstep(0.55, 1.0, dist / reach))
		if r > 2.4 * S and rim > 0.0:
			# An out-of-focus point of light: a ring rather than a dot.
			var edge_r: float = r
			var hole: float = r * lerpf(0.85, 0.35, clampf(rim, 0.0, 1.0))
			var x0: int = maxi(int(at.x - edge_r) - 1, 0)
			var x1: int = mini(int(at.x + edge_r) + 1, _px - 1)
			var y0: int = maxi(int(at.y - edge_r) - 1, 0)
			var y1: int = mini(int(at.y + edge_r) + 1, _px - 1)
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var d: float = Vector2(float(x) - at.x,
						float(y) - at.y).length()
					if d > edge_r:
						continue
					# Flat across the disc, lifted at the rim, and eased at
					# the very outside so it is not a cut circle.
					var v: float = 0.42
					v += smoothstep(hole, edge_r * 0.94, d) * 0.58
					v *= 1.0 - smoothstep(edge_r * 0.90, edge_r, d)
					var k: int = y * _px + x
					var lit: float = v * bright
					if lit > buf[k]:
						buf[k] = lit
		else:
			_dab(buf, at.x, at.y, r, bright)
	return buf

## A line with tooth: the grain of paper showing through a confident stroke.
##
## The reference is a marker or a soft pencil dragged across a sheet — solid
## down the middle of the mark, broken along its edges, and never mechanically
## even. `_dry_buffer` already here breaks a stamp up all over, which gives a
## scrubbed, chalky mark. This is the other thing: the middle stays whole and
## only the edge is eaten, which is what a line drawn with any confidence
## actually looks like.
##
## The tooth is cut with a random lattice rather than per-pixel noise, so the
## grain has a *size* — pixel noise gives a fizzing edge that shimmers when
## the brush is scaled, and this gives flecks that hold together.
##
## `bite` is how deep the edge is eaten, `tooth` the size of the flecks, and
## `dark` how much the middle is allowed to be broken as well.
func _tooth_buffer(hardness: float = 0.85, bite: float = 0.55,
		tooth: float = 3.0, dark: float = 0.12,
		seed_at: int = 9100) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _blank()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.set_seed(seed_at)
	var c: float = float(_px) * 0.5
	var rad: float = c - 2.0
	# The flecks must be big enough to be flecks.
	#
	# At two or three pixels this was per-pixel noise: it read as television
	# static, and worse, it shimmered as the brush was scaled because each
	# pixel of the stamp was its own random number. Tripled, the grain holds
	# together as marks on paper and survives being resampled.
	var cell: float = maxf(tooth * S * 1.9, 2.0)
	var across: int = int(ceil(float(_px) / cell)) + 1

	# The grain lattice, drawn once and read by every pixel that falls in it.
	var grain: PackedFloat32Array = PackedFloat32Array()
	grain.resize(across * across)
	for i in grain.size():
		grain[i] = rng.randf()

	var inner: float = clampf(hardness, 0.0, 0.98)
	for y in _px:
		for x in _px:
			var d: float = Vector2(float(x) - c + 0.5,
				float(y) - c + 0.5).length() / rad
			if d >= 1.0:
				buf[y * _px + x] = 0.0
				continue
			var a: float = 1.0 - smoothstep(inner, 1.0, d)
			# Read between the four nearest lattice points, so the flecks
			# have soft shoulders instead of being little squares.
			var gx: float = float(x) / cell
			var gy: float = float(y) / cell
			var ix: int = clampi(int(gx), 0, across - 2)
			var iy: int = clampi(int(gy), 0, across - 2)
			var fx: float = smoothstep(0.0, 1.0, gx - float(ix))
			var fy: float = smoothstep(0.0, 1.0, gy - float(iy))
			var g00: float = grain[iy * across + ix]
			var g10: float = grain[iy * across + ix + 1]
			var g01: float = grain[(iy + 1) * across + ix]
			var g11: float = grain[(iy + 1) * across + ix + 1]
			var g: float = lerpf(lerpf(g00, g10, fx), lerpf(g01, g11, fx), fy)
			# Deepest at the edge and shallow in the middle. This is the
			# whole difference from a dry brush: the mark keeps its spine.
			# The knee sits well out from the centre, so the middle two
			# thirds of the mark are very nearly untouched and only the rim
			# is broken.
			var eaten: float = lerpf(dark, bite, smoothstep(0.45, 1.0, d))
			a *= clampf(1.0 - eaten * (1.0 - g), 0.0, 1.0)
			buf[y * _px + x] = a
	return buf

## The same tooth on a squashed, turned stamp.
##
## A chisel makes a line whose weight changes with its heading — thick across
## the nib, thin along it — and that comes from the shape of the stamp, not
## from anything the stroke does. Built by taking the tooth stamp and reading
## it through a squash, so the grain and the shape agree instead of being two
## textures laid over one another.
func _tooth_chisel(hardness: float, bite: float, tooth: float, dark: float,
		seed_at: int) -> PackedFloat32Array:
	var flat: PackedFloat32Array = _tooth_buffer(hardness, bite, tooth,
		dark, seed_at)
	var out: PackedFloat32Array = _blank()
	var c: float = float(_px) * 0.5
	var turn: float = -PI * 0.25
	var cs: float = cos(turn)
	var sn: float = sin(turn)
	var squash: float = 0.44
	for y in _px:
		for x in _px:
			var off: Vector2 = Vector2(float(x) - c + 0.5, float(y) - c + 0.5)
			# Turned back and stretched, so what is read is the round stamp
			# the squashed one came from.
			var local: Vector2 = Vector2(off.x * cs + off.y * sn,
				(-off.x * sn + off.y * cs) / squash)
			var sx: int = int(round(local.x + c))
			var sy: int = int(round(local.y + c))
			if sx < 0 or sy < 0 or sx >= _px or sy >= _px:
				continue
			out[y * _px + x] = flat[sy * _px + sx]
	return out
