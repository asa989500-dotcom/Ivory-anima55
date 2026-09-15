#ifndef IVORY_BLEND_H
#define IVORY_BLEND_H

// Merging two colours, properly.
//
// ## The thing that makes a blend tool feel cheap
//
// Mixing colours by averaging their sRGB bytes. It is one line, every drawing
// program has shipped it at some point, and it is wrong in two separate ways
// that compound.
//
// **sRGB is not light.** The byte 128 is not half of the byte 255; it is about
// 21% of the light, because the encoding has a roughly 2.2 gamma baked into it
// so that the codes are spread evenly over what the eye can tell apart.
// Averaging the codes therefore averages neither the light nor the appearance.
// Blend pure red with pure green that way and the middle comes out muddy and
// dark, and every artist recognises that mud instantly even if they could not
// say why it is there.
//
// **Linear light is not appearance either.** Undo the gamma and average the
// light, and the middle is now too *bright* and drifts in hue — blue to white
// goes through a purple that is not on the line between them. Light is what
// physics adds; it is not what a person sees as halfway.
//
// ## OKLab
//
// Ottosson (2020). A Lab space fitted to modern colour-appearance data, in
// which the straight line between two colours looks like the sequence of
// colours between them, and equal steps look equally different. It is cheap —
// two three-by-three matrices and a cube root — and it does not have CIELAB's
// blue-hue problem, where interpolating towards blue visibly bends purple.
//
// So: decode from sRGB, go to OKLab, take the straight line, come back. Red to
// green passes through a real olive rather than mud, blue to white stays blue,
// and a gradient laid down with this has evenly spaced steps rather than
// bunching in the middle.
//
// ## What "in the style of the brush" means here
//
// Every brush in the app is a stamp: a picture of how much ink lands where.
// This tool takes that same picture and reads it as **how much mixing happens
// where** — the middle of a soft round mixes fully and its edge barely at all;
// the chalk mixes through its own tooth and leaves the pits alone; the cell
// network mixes along its strands. So the blend tool has the whole brush
// library rather than a shape of its own, and choosing a shape in its panel
// is choosing the character of the mix.
//
// ## Alpha, and why it is done premultiplied
//
// Mixing the colour of a transparent pixel with the colour of an opaque one,
// weighted only by the kernel, drags the invisible colour of the transparent
// pixel into the visible result. On a layer with anything drawn on it, that
// shows as a dark or grey halo along every edge — the classic fringe, and it
// looks exactly like a bug even though every line of it is doing what it was
// told. Weighting each pixel's contribution by its own alpha as well is what
// removes it, and that is what premultiplying is.
//
// ## Speed
//
// A dab is a few thousand pixels and there are sixty of them a second while a
// finger is moving. Two things pay for that: decoding sRGB through a
// **256-entry table** rather than calling `pow` per channel per pixel, and
// touching only the pixels the stamp actually covers. Everything else is
// arithmetic on floats in a contiguous buffer.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

class IvoryBlend : public RefCounted {
	GDCLASS(IvoryBlend, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryBlend();
	~IvoryBlend() = default;

	// How the two colours are brought together.
	enum Mode {
		// Every pixel moves towards one colour taken from the line between
		// the two, at a position the settings choose. The plain merge.
		MODE_MIX,
		// The position along that line is where the stroke has got to, so
		// one drag lays a gradient from the first colour to the second.
		MODE_GRADIENT,
		// What is already under the brush is picked up and carried along,
		// mixing into whatever it meets. Smudging, and the one that merges
		// two colours already on the canvas rather than two chosen ones.
		MODE_PULL,
		// Every pixel moves towards the average of what is under the stamp.
		// Softens a border between two colours without moving either of
		// them, which is what people usually mean by "blend these".
		MODE_AVERAGE,
		// Towards the two colours, whichever is nearer in appearance. Sharp
		// where the two meet, so it tidies a boundary rather than blurring
		// it.
		MODE_SNAP,
	};

	// --- the surface being worked on ---

	// Hands over a tile of RGBA8. Held, not copied back, until `surface` is
	// asked for — so a stroke of two hundred dabs crosses the boundary twice
	// rather than four hundred times.
	void set_surface(const PackedByteArray &rgba, int width, int height);
	PackedByteArray surface() const;
	int width() const { return w_; }
	int height() const { return h_; }

	// --- the settings ---

	// The two colours, as sRGB bytes with alpha.
	void set_colours(const PackedByteArray &first, const PackedByteArray &second);

	// The stamp: `px * px` weights from nought to one, straight out of
	// `BrushLibrary`. That is what makes this tool carry every brush shape.
	void set_stamp(const PackedFloat32Array &weights, int px);

	// How hard it mixes, nought to one. At one a single dab replaces the
	// colour under the middle of the stamp outright; at a tenth it takes ten
	// passes to get there, which is how a person actually blends.
	void set_strength(double strength);
	// The dab's diameter in pixels.
	void set_size(double size);
	// How much of what it passes over the brush carries with it, for the
	// modes that carry anything.
	void set_pickup(double pickup);
	void set_mode(int mode);
	// Whether a dab may change how opaque a pixel is. Off by default: a
	// blend tool that quietly erases is a blend tool nobody trusts.
	void set_touch_alpha(bool on);

	// Forgets what the brush is carrying. Called when a stroke starts, or
	// the next stroke begins with the last one's colour still on it.
	void reset_carry();

	// --- doing it ---

	// One dab, centred at `at`. `t` runs nought to one along the stroke and
	// is only read in gradient mode. Returns what it did.
	Dictionary dab(const Vector2 &at, double t);

	// A whole stroke, dabbed along a path at a spacing. Returns the same
	// summary, totalled. Here so that a stroke is one call rather than two
	// hundred, which on a phone is the difference that matters.
	Dictionary stroke(const PackedVector2Array &path, double spacing);

	// The rectangle changed since the last `clear_damage`, so the caller
	// re-uploads a tile rather than the whole layer.
	Dictionary damage() const;
	void clear_damage();

	// --- the colour arithmetic, exposed because it is the part that must be
	// right and a test that cannot see it is a test of nothing ---

	// Halfway between two sRGB colours, the way it should look.
	static PackedByteArray mix_srgb(const PackedByteArray &a,
			const PackedByteArray &b, double t);

	// The three OKLab coordinates of an sRGB colour, and back.
	static PackedFloat32Array to_oklab(const PackedByteArray &srgb);
	static PackedByteArray from_oklab(const PackedFloat32Array &lab,
			int alpha);

private:
	struct Lab {
		double l = 0.0, a = 0.0, b = 0.0, alpha = 1.0;
	};

	std::vector<uint8_t> pixel_;
	int w_ = 0;
	int h_ = 0;

	std::vector<float> stamp_;
	int stamp_px_ = 0;

	Lab first_;
	Lab second_;
	Lab carry_;
	bool carrying_ = false;

	double strength_ = 0.45;
	double size_ = 40.0;
	double pickup_ = 0.55;
	int mode_ = MODE_MIX;
	bool touch_alpha_ = false;

	int dirty_x0_ = 0, dirty_y0_ = 0, dirty_x1_ = -1, dirty_y1_ = -1;

	// sRGB byte to linear light. A table, because `pow` per channel per
	// pixel per dab is the single most expensive thing in the tool and there
	// are only two hundred and fifty-six possible answers.
	static double decode_[256];
	static bool table_built_;
	static void build_table();
	static uint8_t encode(double linear);

	static Lab lab_of_bytes(const uint8_t *rgba);
	static void bytes_of_lab(const Lab &in, uint8_t *rgba, bool with_alpha);
	static Lab lab_from_linear(double r, double g, double b, double a);
	static void linear_from_lab(const Lab &in, double &r, double &g,
			double &b);
	static Lab lerp_lab(const Lab &a, const Lab &b, double t);
	static double lab_distance(const Lab &a, const Lab &b);

	double weight_at(double u, double v) const;
	void touch(int x0, int y0, int x1, int y1);
};

} // namespace godot

VARIANT_ENUM_CAST(IvoryBlend::Mode);

#endif // IVORY_BLEND_H
