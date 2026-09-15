#ifndef IVORY_WARP_H
#define IVORY_WARP_H

// The puppet warp's arithmetic, in C++.
//
// ## What this is and what it is not
//
// It is not a new deformation. It is the same two solvers that
// `scripts/puppet_warp.gd` already runs — rigid moving least squares over the
// pins, then as-rigid-as-possible over the mesh — written where the inner
// loops are affordable. GDScript does them correctly and pays a bound-call
// and a Variant for every one of the tens of thousands of arithmetic
// operations a single frame of a drag needs.
//
// Because it is the same arithmetic, the GDScript stays and stays working.
// If this library is not built, `puppet_warp.gd` runs exactly as it did.
//
// ## What is genuinely better here, and not merely faster
//
// Three things, and each is a change of method rather than of language:
//
//   * **Distance through the mesh is now exact.** GDScript measures it by
//     repeated relaxation sweeps — every vertex offering its neighbours a
//     route through itself until nothing improves — which converges to the
//     right answer and stops when it is close. Here it is Dijkstra with a
//     binary heap: each vertex is settled once, in order, and the answer is
//     the true shortest path through the mesh rather than a good
//     approximation of it. It is also O(V log V) instead of O(V x sweeps).
//
//   * **The global ARAP step is over-relaxed.** Gauss-Seidel on a Laplace
//     system converges, slowly, at a rate set by the mesh's spectral radius.
//     Successive over-relaxation — taking the step and then some, by a factor
//     omega between 1 and 2 — is the standard acceleration for exactly this
//     class of system and reaches the same answer in roughly a third of the
//     sweeps. See `sweep`.
//
//   * **The sums are accumulated in double.** The MLS weights run over
//     several orders of magnitude within one vertex — a pin a few units away
//     and one across the drawing — and adding a large number to a small one
//     in single precision throws the small one away. In double the
//     cancellation is far below anything that can reach a pixel.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>
#include <utility>
#include <array>

namespace godot {

class IvoryWarp : public RefCounted {
	GDCLASS(IvoryWarp, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryWarp();
	~IvoryWarp();

	// The mesh, handed over once when it is built or rebuilt.
	//
	// `neighbours` is four entries per vertex, -1 where the mesh ends — the
	// same flat layout `puppet_warp.gd` keeps in `_near`. `rim` marks the
	// vertices on the outline. `cell_span` is how far apart two neighbouring
	// vertices are at rest, which is what sets how quickly a pin's grip fades.
	void set_mesh(const PackedVector2Array &rest,
			const PackedInt32Array &neighbours, const PackedByteArray &rim,
			double cell_span, const PackedInt32Array &triangles);

	void set_params(double stiffness, double softness, double rigid,
			double smoothing, double omega);

	// Hard canvas bounds. The deformer may move freely inside the source
	// rectangle, but never let a vertex escape it. This is a safety constraint
	// rather than a visual crop: the mesh itself remains valid for rendering.
	void set_bounds(const Vector2 &min_corner, const Vector2 &max_corner);

	// Which class of local transform the moving least squares is allowed to
	// fit. This is the single number that decides whether pulling a pin
	// *moves* the drawing or *stretches* it, and it is a change of method
	// rather than of degree.
	//
	//   0 RIGID       rotation and translation only. Every distance in the
	//                 drawing is preserved exactly, so pulling one pin
	//                 towards another slides the material between them out of
	//                 the way. This is right for a jointed figure and wrong
	//                 for everything else — a line with a pin at each end,
	//                 pulled together, does not shorten. It bows.
	//
	//   1 SIMILARITY  rotation, translation and one uniform scale. Pull two
	//                 pins apart and the whole neighbourhood grows; push them
	//                 together and it shrinks. Proportions are kept.
	//
	//   2 AFFINE      the full least-squares linear fit: independent scale on
	//                 each axis, and shear. Pull a pin towards another and
	//                 the material *between them compresses*, while what is
	//                 square to that line is left alone. This is what
	//                 stretching and squashing a two-dimensional drawing
	//                 means, and it is the default here for that reason.
	//
	// All three are Schaefer, McPhail and Warren (2006), section by section.
	// The weights, the walked distances and everything else are identical
	// between them; only the fit at the end of `warp_vertex` differs.
	void set_mode(int mode);

	// Where the pins were placed, where they are now, which vertex each sits
	// on, and how far each has been turned.
	//
	// Setting the pins marks the walked distances stale. They are rebuilt on
	// the next solve and never during a drag: a pin measures from where it was
	// *placed*, and that does not change while it is being pulled.
	void set_pins(const PackedVector2Array &rest_pins,
			const PackedVector2Array &now_pins,
			const PackedInt32Array &vertex, const PackedFloat32Array &turn);

	// Only the positions and turns, for a frame of a drag. Cheap, and does not
	// touch the walked distances.
	void move_pins(const PackedVector2Array &now_pins,
			const PackedFloat32Array &turn);

	// Where every vertex has ended up. `settle` asks for the careful answer,
	// for the moment a finger lifts and nothing is waiting.
	PackedVector2Array solve(bool settle);

	// The pose, for warm-starting after a rebuild.
	PackedVector2Array pose() const;
	void set_pose(const PackedVector2Array &now);

	bool ready() const;
	int vertex_count() const;

private:
	// --- the mesh ---
	std::vector<Vector2> rest_;
	std::vector<Vector2> now_;
	// The last pose `prevent_foldover` verified sound. Restored, not `rest_`,
	// when even the step's starting point cannot be trusted — see the .cpp.
	std::vector<Vector2> last_good_;
	std::vector<int32_t> near_;
	// The actual triangle-edge graph used by ARAP. The old four-neighbour
	// graph is still kept for walked distances, but solving on it made the
	// deformation directionally biased because the real mesh also contains
	// alternating diagonals. Each pair is (vertex, cotangent weight).
	std::vector<std::vector<std::pair<int32_t, double>>> edges_;
	std::vector<uint8_t> rim_;
	// The actual triangle list is retained so the solver can enforce a hard
	// orientation constraint. A valid triangle must never cross through zero
	// area and flip its winding during a drag.
	std::vector<std::array<int32_t, 3>> triangles_;
	std::vector<double> rest_area_;
	double min_area_ratio_ = 0.015;
	double cell_span_ = 1.0;

	// --- the pins ---
	std::vector<Vector2> pin_rest_;
	std::vector<Vector2> pin_now_;
	std::vector<int32_t> pin_vertex_;
	std::vector<float> pin_turn_;
	// One row per pin: how far every vertex is from it, walked through the
	// mesh. Costly to build and completely unaffected by dragging.
	std::vector<std::vector<float>> reach_;
	bool reach_dirty_ = true;
	bool any_turn_ = false;

	// --- working ---
	std::vector<float> hold_;
	std::vector<float> rot_c_;
	std::vector<float> rot_s_;
	std::vector<uint8_t> pinned_;
	std::vector<double> weight_;
	std::vector<Vector2> spare_;

	double stiffness_ = 1.0;
	double softness_ = 7.0;
	double rigid_ = 0.55;
	double smoothing_ = 0.4;
	double omega_ = 1.62;
	Vector2 bounds_min_ = Vector2();
	Vector2 bounds_max_ = Vector2();
	bool bounded_ = false;
	// See `set_mode`. Two is affine, which is the stretch-and-squash answer.
	int mode_ = 2;

	void build_edges(const PackedInt32Array &triangles);
	void build_reach();
	void measure_hold();
	void mark_pinned();
	Vector2 warp_vertex(int at);
	Vector2 turned_about(double outx, double outy);
	void fit();
	void sweep(bool backwards, double pull);
	void smooth_by(double amount);
	void enforce_pins();
	void enforce_bounds();
	bool mesh_is_valid(const std::vector<Vector2> &points) const;
	void prevent_foldover(const std::vector<Vector2> &before);
};

} // namespace godot

#endif // IVORY_WARP_H
