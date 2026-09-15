class_name BrushExtra
extends RefCounted
## The three families added at stage 137, kept out of `brush_library.gd`.
##
## ## Why they are in their own file
##
## `tools/check_size.py` holds the project to a rule: a file may grow, and the
## growth has to be paid for out of another file. Adding three families to
## `brush_library.gd` put it a hundred and seventeen lines further past its
## recorded size, and the honest way to pay that is to take the new part out
## rather than to raise the number.
##
## It reads better here anyway. These three are the only families in the app
## whose stamps are generated in C++, and they are the only ones that need a
## fallback for when the extension has not been built. That is a different
## kind of thing from the falloff-and-noise families, and it was sitting in
## the middle of them.
##
## ## What the fallback is for
##
## A checkout that has not been built for this platform must still paint with
## every brush on the rail. A brush that draws nothing is indistinguishable,
## to the person holding the phone, from a broken app — and the first thing
## anybody does with a new build is try the new brushes.
##
## So each of the three falls back to the nearest mark the GDScript already
## knows how to make. It is not the same mark and it is not pretended to be;
## it is a mark, made with the right family's spacing and scatter, and the
## stroke is usable. When the library is there, the real stamp is used and
## nothing here runs.

## The generated stamp for one of the three, or the nearest fallback.
##
## `library` is the `BrushLibrary` asking, and is used only to reach its own
## shape builders — the fallbacks are its shapes, not new ones.
static func stamp_for(library: BrushLibrary, family: String, variant: int,
		px: int) -> PackedFloat32Array:
	var fast: Object = Native.brush()
	if fast != null:
		var made: PackedFloat32Array = fast.stamp(family, px, variant)
		if made.size() == px * px:
			return made
	match family:
		"web":
			# A dry, broken round is as close as a falloff gets to a mesh.
			return library._dry_buffer(0.30, 0.42, 0.75)
		"halo":
			# A ring, which is one halo rather than a hundred of them.
			return library._ring_buffer(0.80, 0.30)
		_:
			# Chalk already has a close cousin in the sketch family.
			return library._tooth_buffer(0.62, 0.72, 3.2, 0.22, 4210)

## Whether a family's stamps come from here.
static func owns(family: String) -> bool:
	return family == "web" or family == "halo" or family == "chalk"

## The size and opacity each variant wants.
##
## The shared tuning in `BrushLibrary._tune` is written for a mark made with a
## nib, and all three of these break it somewhere. A venom strand is thin
## enough that at a small size there is nothing left of it to see; a bank of
## halos is meant to be built up over passes rather than laid down in one.
static func tune(p, family: String) -> void:
	match family:
		"web":
			# A network never runs dry. A strand that faded where the hand
			# went quickly would break the mesh, and an unbroken mesh is the
			# one thing this family has to give.
			p.speed_thin = 0.0
			match p.variant:
				1:
					p.default_size = 95.0
				2:
					p.default_size = 190.0
				3:
					p.default_size = 210.0
					p.default_opacity = 1.0
				4:
					p.default_size = 130.0
		"halo":
			p.speed_thin = 0.0
			match p.variant:
				1:
					p.default_size = 200.0
					p.default_opacity = 0.30
				2:
					p.default_size = 110.0
					p.default_opacity = 0.55
				3:
					p.default_size = 160.0
				4:
					p.default_size = 230.0
					p.default_opacity = 0.26
		"chalk":
			match p.variant:
				2:
					p.default_size = 52.0
				3:
					p.default_opacity = 1.0
				4:
					p.default_size = 64.0
					p.default_opacity = 0.55
					p.speed_thin = 0.15


## The three rows, shaped exactly as `BrushLibrary.FAMILIES` is:
## id, English, Arabic, spacing, scatter, angle jitter, size jitter,
## follow, speed thin, size, opacity.
static func families() -> Array:
	return [
		# --- three families from the reference sheets, at stage 137 ---
		#
		# Their stamps are generated in C++ (`IvoryBrush`), with the
		# fallbacks above. A cell network needs the nearest three seed
		# points for every pixel, which in GDScript is a visible pause the
		# first time the brush is picked up.

		# **Web.** Thin along its strands, swelling where three cells meet. It
		# never thins with speed — a strand that faded where the hand went
		# quickly would break the mesh.
		["web", "Web", "شبكة", 0.075, 0.0, 0.0, 0.06, true, 0.0,
			120.0, 0.9],

		# **Halo.** Rings in quantity. Wide scatter and free rotation, because a
		# cluster printed twice at the same angle is obviously one cluster
		# printed twice.
		["halo", "Hair halo", "هالات شعرية", 0.14, 0.30, PI, 0.34, false,
			0.0, 140.0, 0.42],

		# **Chalk.** The only one of the three that is a line: it follows the
		# stroke and thins hard with speed, which is what makes a flicked mark
		# taper.
		["chalk", "Chalk", "طباشير", 0.055, 0.0, 0.0, 0.07, true,
			0.40, 26.0, 1.0],
	]

## What each of the five is called. The shared five words — plain, fine,
## broad, rough, soft — are useless here: one of the nets is a fine mesh
## and another is venom, and a name that says nothing is worse than none.
static func names_for(family: String) -> Array:
	match family:
		"web":
			return [
				["Net", "شبكة"], ["Fine mesh", "شبكة دقيقة"], ["Coarse", "شبكة خشنة"],
				["Venom", "سُمّ"], ["Torn", "شبكة ممزّقة"],
			]
		"halo":
			return [
				["Halos", "هالات"], ["Wide", "هالات واسعة"], ["Foam", "رغوة"],
				["Bubbles", "فقاعات"], ["Tangle", "تشابك"],
			]
		"chalk":
			return [
				["Chalk", "طباشير"], ["Fine", "طباشير رفيع"], ["Broad", "طباشير عريض"],
				["Worn", "طباشير مهترئ"], ["Pastel", "باستيل"],
			]
	return []
