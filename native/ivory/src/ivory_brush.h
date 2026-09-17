#ifndef IVORY_BRUSH_H
#define IVORY_BRUSH_H

// Three new kinds of mark: the cell network, the halos and the chalk.
//
// ## Why the stamps moved to C++
//
// `brush_library.gd` builds every stamp by writing into a `PackedFloat32Array`
// a pixel at a time. That was fine for the families already there, which are
// a falloff and some noise and are a few hundred thousand operations at two
// hundred and fifty-six pixels square.
//
// The three added here are not that. A cell network has to know, for every
// pixel, the distance to the *nearest three* seed points; a halo field is a
// hundred rings each of which touches a large part of the stamp. At the sizes
// these want, in GDScript, that is a visible pause the first time somebody
// picks the brush up — and it is paid again at the larger resolution when they
// paint big with it. Here it is a few milliseconds and nobody sees anything.
//
// ## The cell network — "the web"
//
// Worley's cellular texture (1996). Seeds are scattered, and every pixel asks
// how far it is to the nearest seed (`F1`), the next (`F2`) and the one after
// (`F3`). The **borders between cells are where `F2 - F1` is near zero**,
// because that is precisely the set of points equidistant from two seeds —
// which is the definition of a Voronoi edge. So the network is not drawn and
// then thickened; it is a level set, and it comes out closed, connected, and
// with no ends left hanging, for free.
//
// The reference sheet's network is not of even thickness, and that is the
// whole character of it: the strands are thin along their length and swell
// where three cells meet. `F3 - F1` is small exactly at those junctions and
// nowhere else, so it drives the swelling directly. The result flows into its
// junctions instead of crossing at them, which is the thing that reads as a
// living web rather than a wire grid.
//
// Seeds are on a **jittered lattice** rather than scattered freely. Poisson
// scattering clumps — that is what Poisson means — and clumps in a cell
// network are cells too small to see next to cells the size of a thumb. One
// seed per lattice cell, displaced within it, gives cells that vary without
// any of them collapsing.
//
// ## The halos
//
// Rings, not discs, laid down in quantity. Each is a narrow Gaussian band at
// its own radius, `exp(-((d - r) / w)^2)`, which gives a soft-edged circle
// with no aliasing to fix afterwards.
//
// They are combined by **screening** — `1 - (1 - a)(1 - b)` — rather than by
// adding or by taking the larger. Adding saturates to a white blob wherever
// four rings cross, which on a dense stamp is most of it. Taking the larger
// makes crossings invisible, and the crossings are the entire texture. The
// screen operator is what ink actually does: each ring takes a share of what
// light is left, so a crossing is darker than either ring and still not solid.
//
// ## The chalk
//
// A line with a **tooth**. Chalk on paper does not lay down a solid stripe; it
// catches on the raised grain and skips the pits, and the amount it catches
// falls off towards the edges of the stroke where the pressure does.
//
// So: a smooth profile across the line, multiplied by value noise at three
// octaves, then put through a soft threshold whose level *rises towards the
// edges*. The middle of the stroke keeps almost everything, the edges keep
// only the peaks of the grain, and the transition is ragged rather than
// straight. A uniform threshold gives a stripe with holes in it, which reads
// as a damaged brush rather than as chalk.
//
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

class IvoryBrush : public RefCounted {
	GDCLASS(IvoryBrush, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryBrush() = default;
	~IvoryBrush() = default;

	// The three families, five of each. Every one returns `px * px` alpha
	// values from nought to one, in rows, which is exactly what
	// `BrushLibrary.make_texture` already takes.
	PackedFloat32Array web(int px, int variant) const;
	PackedFloat32Array halo(int px, int variant) const;
	PackedFloat32Array chalk(int px, int variant) const;

	// By name, so `brush_library.gd` can ask for one without a match
	// statement that has to be kept in step with this file.
	PackedFloat32Array stamp(const String &family, int px, int variant) const;

	// Whether this class knows a family. Lets the GDScript ask before it
	// commits, and keeps the fallback path honest.
	bool knows(const String &family) const;

private:
	// Deterministic, and the same on every platform. `rand()` is neither:
	// two devices would generate different stamps for the same brush, and a
	// file moved between them would not look the same.
	static uint32_t hash32(uint32_t x);
	static double unit(int64_t a, int64_t b, int64_t salt);
	static double signed_unit(int64_t a, int64_t b, int64_t salt);
	// Value noise, smoothed, on a lattice.
	static double value_noise(double x, double y, int64_t salt);
	static double fbm(double x, double y, int octaves, double gain,
			int64_t salt);
	static double smooth_step(double edge0, double edge1, double x);
};

} // namespace godot

#endif // IVORY_BRUSH_H
