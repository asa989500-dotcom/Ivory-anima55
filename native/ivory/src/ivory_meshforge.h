#ifndef IVORY_MESHFORGE_H
#define IVORY_MESHFORGE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

// A warp mesh that sits on the drawing rather than over it.
//
// ## The complaint this answers
//
// "The mesh should hug the outline of the drawing however small it is, and it
// should stretch and squash when it is pulled, not drag."
//
// Those are two separate faults with two separate causes, and this class is
// the first of them. The old mesh was an axis-aligned grid of squares laid
// over the bounding box, with squares dropped where an ink map said there was
// nothing. Three consequences followed, and all three are visible when you use
// it:
//
//   * **The boundary was a staircase.** Every mesh vertex sat on a grid line,
//     so the outline of the mesh was made of horizontal and vertical steps of
//     one cell. Pull an arm and the arm's edge moves in blocks.
//
//   * **A thin stroke was a coin toss.** The cell either contained enough ink
//     to be kept or it did not, so an eyelash a pixel wide had cells along it
//     and cells missing between them. What is not in the mesh is not drawn.
//
//   * **The grid had no idea where the drawing's detail was.** A cell in the
//     middle of a solid area and a cell straddling the outline got the same
//     size, so there was never enough resolution where it mattered and always
//     too much where it did not.
//
// ## What is built instead
//
// Four steps.
//
// 1. **Occupancy, by maximum.** The alpha channel is reduced to a grid of
//    cells, and a cell is occupied if **any** pixel inside it has ink. Not the
//    average — the maximum. An average washes a hairline out; a maximum
//    cannot. This is the step that makes "however small" true.
//
// 2. **A one-cell skirt.** Occupancy is dilated by one cell in each direction,
//    so every piece of ink is strictly inside the mesh rather than on its
//    edge. A stroke exactly on the mesh boundary has no material outside it to
//    pull against and shears when the mesh moves.
//
// 3. **Boundary snapping.** Every vertex on the mesh's outer edge is moved on
//    to the real alpha contour — along the direction of the alpha gradient,
//    by a search that stops at the last opaque pixel. This is what turns a
//    staircase into an outline. Interior vertices are never moved, so the mesh
//    stays well-shaped inside.
//
// 4. **A quality pass.** Any triangle that snapping has made degenerate — a
//    sliver, or one turned inside out — is reported, and the snap that caused
//    it is backed off until the triangle is sound again. A mesh with an
//    inverted triangle in it renders as a fold in the drawing.
//
// The result is handed back as vertices, triangles, edges, and a flag per
// vertex saying whether it is on the boundary. `IvoryArapSolver` takes exactly
// that and deforms it.
class IvoryMeshForge : public RefCounted {
	GDCLASS(IvoryMeshForge, RefCounted)

protected:
	static void _bind_methods();

public:
	// Builds the mesh. `cell` is the target edge length in pixels; smaller is
	// finer and slower. `alpha_floor` is the alpha at which a pixel counts as
	// drawn — low, because the question is "is there anything here".
	//
	// Returns a Dictionary with:
	//   ok, vertices (PackedVector2Array), triangles (PackedInt32Array, 3 per),
	//   edges (PackedInt32Array, 2 per), boundary (PackedByteArray, 1 per
	//   vertex), vertex_count, triangle_count, edge_count, cell, bounds,
	//   ink_cells, snapped, reverted, min_angle_deg, thinnest_feature_px.
	Dictionary build(const PackedByteArray &rgba, int width, int height,
			double cell, double alpha_floor);

	// True when the mesh covers every pixel that has ink in it. This is the
	// property the old grid quietly broke, so it is measured rather than
	// assumed: the check walks the source and asks, for each opaque pixel,
	// whether some triangle contains it.
	//
	// Slow — it is for the tests and for the diagnostics room, not for a drag.
	Dictionary covers_all_ink(const PackedByteArray &rgba, int width, int height,
			double alpha_floor) const;

	// The mesh most recently built.
	PackedVector2Array vertices() const;
	PackedInt32Array triangles() const;
	PackedInt32Array edges() const;
	PackedByteArray boundary() const;
	int vertex_count() const { return (int)verts_.size(); }
	int triangle_count() const { return (int)tris_.size() / 3; }

	// Which triangle contains a point, and where inside it — the binding a pin
	// needs so it stays attached to the material rather than floating over it.
	// Returns {ok, triangle, a, b, c} where a+b+c == 1.
	Dictionary bind_point(const Vector2 &at) const;

	// The point a binding now refers to, after the mesh has moved.
	Vector2 follow(const Dictionary &binding, const PackedVector2Array &moved) const;

private:
	struct Grid {
		int nx = 0, ny = 0;
		double cell = 8.0;
		double ox = 0.0, oy = 0.0;
		std::vector<uint8_t> on;
		bool at(int x, int y) const {
			if (x < 0 || y < 0 || x >= nx || y >= ny) return false;
			return on[(size_t)y * nx + x] != 0;
		}
	};

	Grid occupancy(const PackedByteArray &rgba, int w, int h, double cell, double floor) const;
	void dilate(Grid &g) const;
	void snap_boundary(const PackedByteArray &rgba, int w, int h, double floor);
	void relax_interior(int passes);
	int revert_bad_triangles(const PackedVector2Array &before);

	std::vector<Vector2> verts_;
	std::vector<int> tris_;
	std::vector<int> edges_;
	std::vector<uint8_t> on_rim_;
	double cell_ = 8.0;
	int snapped_ = 0;
	int reverted_ = 0;
};

} // namespace godot
#endif
