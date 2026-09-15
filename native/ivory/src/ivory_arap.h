#ifndef IVORY_ARAP_H
#define IVORY_ARAP_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

// The deformation itself: as-rigid-as-possible over a triangle mesh, with
// pinned vertices as hard constraints.
//
// ## Why the old warp "dragged"
//
// The complaint was that pulling a pin drags the drawing rather than
// stretching it, and that is exactly what the old solver did, for a reason
// that is worth writing down.
//
// It ran rigid moving-least-squares from the pins: every vertex was placed by
// a weighted average of what the pins wanted, weighted by one over distance
// squared. That is a *scattered-data interpolation*. It knows about pins and
// distances; it does not know the drawing is made of material. Nothing in it
// says a triangle would rather keep its shape, so a pin pulled sideways
// translates its whole neighbourhood sideways — which is what dragging is.
// The as-rigid-as-possible pass that followed then tried to repair the result,
// working against the very field that had just been imposed on it.
//
// ARAP is the other way round. The energy being minimised is
//
//     E = sum over edges  w_ij * || (p_i - p_j) - R_i (q_i - q_j) ||^2
//
// where q is the rest shape, p is where the mesh is now, and R_i is a rotation
// found per vertex. In words: **every edge would like to be its rest length,
// turned by however much its neighbourhood has turned.** Pull one end of an
// arm and the edges between resist; they lengthen a little each, so the arm
// stretches along its length and narrows across it, which is what material
// does and what the artist is asking for. Push two pins together and the mesh
// squashes and bulges. Neither behaviour is programmed in — both fall out of
// the energy.
//
// ## Two details that matter more than the choice of energy
//
//   * **Cotangent weights.** Using w_ij = 1 for every edge makes the mesh
//     stiffer where triangles happen to be small, so a warp behaves
//     differently in a finely meshed area than a coarse one. The cotangent
//     weight is the discretisation of the Laplacian that does not have that
//     bias, and it is why the same drag feels the same everywhere.
//
//   * **Pins are hard, not heavy.** A pinned vertex is removed from the
//     system, not given a large weight. A heavy soft constraint drifts — the
//     pin ends up near where you put it, and "near" grows as more pins fight
//     each other. That is the fault where pins stop being held once there are
//     several of them. Here a pinned vertex is simply never solved for, so it
//     is where you put it, exactly, at every iteration and for ever.
//
// ## Local/global
//
// Each iteration is two half-steps, the standard Sorkine–Alexa alternation:
// find the best rotation per vertex with the positions fixed (a 2x2 problem,
// closed form), then find the best positions with the rotations fixed (a
// sparse linear system, solved here by over-relaxed Gauss–Seidel because it
// needs no factorisation and a drag re-solves every frame).
class IvoryArapSolver : public RefCounted {
	GDCLASS(IvoryArapSolver, RefCounted)

protected:
	static void _bind_methods();

public:
	// The rest mesh. Weights are computed once here, not per frame.
	bool set_mesh(const PackedVector2Array &rest, const PackedInt32Array &triangles);

	// Which vertices are held, and where. Everything not named here is free.
	// Passing an empty list frees the mesh entirely.
	void set_pins(const PackedInt32Array &indices, const PackedVector2Array &at);

	// Additionally freeze vertices at their current position — the
	// double-tap. A frozen vertex behaves exactly like a pin whose target is
	// where it already is, which is the mathematically exact reading of
	// "do not move, at all, until I say".
	void freeze(const PackedInt32Array &indices);
	void thaw(const PackedInt32Array &indices);
	void thaw_all();
	bool is_frozen(int index) const;
	int frozen_count() const;

	// Runs the solve. Returns {ok, iterations, energy, moved, max_step}.
	Dictionary solve(int iterations);

	// Whether every triangle in `points` still has the winding and a positive
	// share of the area it started with at rest. See `prevent_foldover` in
	// the .cpp for why this exists: nothing in the Gauss-Seidel sweep above
	// stops a triangle passing through zero area and coming back inside out.
	bool mesh_is_valid(const std::vector<Vector2> &points) const;

	// Where the mesh is now.
	PackedVector2Array positions() const;
	void set_positions(const PackedVector2Array &p);
	void reset();

	// The ARAP energy, which is the honest measure of how much the drawing has
	// been distorted rather than merely moved. A rigid motion of the whole
	// mesh scores zero however far it travelled.
	double energy() const;

	// How much each triangle has been stretched, largest singular value of its
	// deformation gradient. 1.0 is unstretched. The tests assert on this,
	// because "it stretches instead of dragging" is a statement about these
	// numbers.
	PackedFloat32Array triangle_stretch() const;

	// How much each triangle's area has changed. 1.0 is unchanged, below one
	// is compressed, above one is expanded.
	//
	// Needed alongside `triangle_stretch` because that one reports the largest
	// singular value, and a sheet squashed along its length has its largest
	// singular value at exactly 1.0 — the untouched across-direction. Judged
	// on stretch alone a compression looks like nothing happening at all.
	PackedFloat32Array triangle_area_ratio() const;

	void set_relaxation(double omega);
	double relaxation() const { return omega_; }

private:
	void fit_rotations();
	double sweep();
	void prevent_foldover(const std::vector<Vector2> &before);

	std::vector<Vector2> rest_;
	std::vector<Vector2> now_;
	// The last configuration `sweep()` is known to have left with every
	// triangle right-side out. Restored, not the rest shape, when a step
	// cannot be salvaged by backing it off — see `prevent_foldover`.
	std::vector<Vector2> last_good_;
	std::vector<int> tris_;
	// Signed rest area per triangle (parallel to `tris_`, one entry every
	// three indices) and the span the degeneracy floor is measured against.
	// Both fixed at `set_mesh` and read only afterwards.
	std::vector<double> tri_rest_area_;
	double area_floor_span2_ = 1.0;

	// Neighbour lists in compressed form: neighbours of i are
	// adj_[adj_start_[i] .. adj_start_[i+1]).
	std::vector<int> adj_;
	std::vector<double> adj_w_;
	std::vector<int> adj_start_;
	std::vector<double> diag_;

	std::vector<double> rot_c_, rot_s_;
	std::vector<uint8_t> held_;      // pinned or frozen: never solved for
	std::vector<uint8_t> frozen_;    // frozen specifically, for is_frozen
	double omega_ = 1.6;
};

} // namespace godot
#endif
