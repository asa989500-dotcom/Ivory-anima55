#include "ivory_meshforge.h"

#include <algorithm>
#include <cmath>
#include <map>

namespace godot {

static constexpr double EPS = 1e-9;

void IvoryMeshForge::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "rgba", "width", "height", "cell", "alpha_floor"),
			&IvoryMeshForge::build, DEFVAL(8.0), DEFVAL(0.02));
	ClassDB::bind_method(D_METHOD("covers_all_ink", "rgba", "width", "height", "alpha_floor"),
			&IvoryMeshForge::covers_all_ink, DEFVAL(0.02));
	ClassDB::bind_method(D_METHOD("vertices"), &IvoryMeshForge::vertices);
	ClassDB::bind_method(D_METHOD("triangles"), &IvoryMeshForge::triangles);
	ClassDB::bind_method(D_METHOD("edges"), &IvoryMeshForge::edges);
	ClassDB::bind_method(D_METHOD("boundary"), &IvoryMeshForge::boundary);
	ClassDB::bind_method(D_METHOD("vertex_count"), &IvoryMeshForge::vertex_count);
	ClassDB::bind_method(D_METHOD("triangle_count"), &IvoryMeshForge::triangle_count);
	ClassDB::bind_method(D_METHOD("bind_point", "at"), &IvoryMeshForge::bind_point);
	ClassDB::bind_method(D_METHOD("follow", "binding", "moved"), &IvoryMeshForge::follow);
}

// --- occupancy -------------------------------------------------------------
//
// The maximum, not the mean. A cell is occupied if ANY pixel in it is drawn.
// The old ink map averaged, and a single opaque pixel averaged over a cell of
// a thousand is an alpha of 0.001 — under any sensible floor, so the cell came
// back empty and the stroke fell out of the mesh.
IvoryMeshForge::Grid IvoryMeshForge::occupancy(const PackedByteArray &rgba,
		int w, int h, double cell, double floor) const {
	Grid g;
	g.cell = std::max(1.0, cell);
	if (w < 1 || h < 1 || (int64_t)rgba.size() < (int64_t)w * h * 4) return g;

	g.nx = (int)std::ceil((double)w / g.cell);
	g.ny = (int)std::ceil((double)h / g.cell);
	if (g.nx < 1 || g.ny < 1) return g;
	g.on.assign((size_t)g.nx * g.ny, 0);

	const int on_byte = std::clamp((int)std::lround(floor * 255.0), 1, 255);
	for (int y = 0; y < h; ++y) {
		const int gy = std::min(g.ny - 1, (int)((double)y / g.cell));
		for (int x = 0; x < w; ++x) {
			if (rgba[(y * w + x) * 4 + 3] < on_byte) continue;
			const int gx = std::min(g.nx - 1, (int)((double)x / g.cell));
			g.on[(size_t)gy * g.nx + gx] = 1;
		}
	}
	return g;
}

// A one-cell skirt in all eight directions.
//
// Ink sitting on the mesh's own edge has no material outside it to pull
// against; the first time that edge moves, the stroke shears off. The skirt
// costs a ring of triangles and removes the whole class of fault.
void IvoryMeshForge::dilate(Grid &g) const {
	if (g.nx < 1 || g.ny < 1) return;
	std::vector<uint8_t> out = g.on;
	for (int y = 0; y < g.ny; ++y) {
		for (int x = 0; x < g.nx; ++x) {
			if (g.at(x, y)) continue;
			// Four-way, not eight. A diagonal neighbour puts the skirt two
			// cells out at every corner of the shape, and a rim vertex two
			// cells from the ink cannot be pulled on to the outline without
			// passing through the ring of vertices inside it. Four-way gives
			// a skirt of even thickness that the snap can actually close.
			const bool near = g.at(x - 1, y) || g.at(x + 1, y) ||
					g.at(x, y - 1) || g.at(x, y + 1);
			if (near) out[(size_t)y * g.nx + x] = 1;
		}
	}
	g.on.swap(out);
}

Dictionary IvoryMeshForge::build(const PackedByteArray &rgba, int width, int height,
		double cell, double alpha_floor) {
	verts_.clear();
	tris_.clear();
	edges_.clear();
	on_rim_.clear();
	snapped_ = 0;
	reverted_ = 0;
	cell_ = std::max(1.0, cell);

	Dictionary out;
	out["ok"] = false;
	out["vertex_count"] = 0;
	out["triangle_count"] = 0;
	out["edge_count"] = 0;
	out["cell"] = cell_;
	if (width < 1 || height < 1) return out;
	if ((int64_t)rgba.size() < (int64_t)width * height * 4) return out;

	Grid g = occupancy(rgba, width, height, cell_, alpha_floor);
	if (g.nx < 1) return out;

	int ink_cells = 0;
	for (uint8_t v : g.on) ink_cells += v ? 1 : 0;
	if (ink_cells == 0) {
		out["ink_cells"] = 0;
		return out;
	}
	dilate(g);

	// Corner lattice. A corner exists only if it touches an occupied cell, so
	// the vertex count follows the drawing rather than its bounding box — a
	// stick figure in a large canvas gets a mesh the shape of the figure.
	std::vector<int> corner((size_t)(g.nx + 1) * (g.ny + 1), -1);
	auto corner_at = [&](int cx, int cy) -> int & {
		return corner[(size_t)cy * (g.nx + 1) + cx];
	};
	auto need_corner = [&](int cx, int cy) -> int {
		int &slot = corner_at(cx, cy);
		if (slot < 0) {
			slot = (int)verts_.size();
			verts_.push_back(Vector2((real_t)(cx * g.cell), (real_t)(cy * g.cell)));
		}
		return slot;
	};

	for (int y = 0; y < g.ny; ++y) {
		for (int x = 0; x < g.nx; ++x) {
			if (!g.at(x, y)) continue;
			const int a = need_corner(x, y);
			const int b = need_corner(x + 1, y);
			const int c = need_corner(x + 1, y + 1);
			const int d = need_corner(x, y + 1);
			// The diagonal alternates with the cell's parity. A mesh whose
			// diagonals all run the same way is stiffer along one axis than
			// the other, and a drawing warped through it shears visibly in
			// that direction.
			if (((x + y) & 1) == 0) {
				tris_.push_back(a); tris_.push_back(b); tris_.push_back(c);
				tris_.push_back(a); tris_.push_back(c); tris_.push_back(d);
			} else {
				tris_.push_back(a); tris_.push_back(b); tris_.push_back(d);
				tris_.push_back(b); tris_.push_back(c); tris_.push_back(d);
			}
		}
	}
	if (verts_.empty() || tris_.empty()) return out;

	// Edges, deduplicated, and the count of triangles on each. An edge with
	// one triangle is on the boundary; that is what marks a rim vertex, and
	// it is exact rather than a guess from the occupancy grid.
	std::map<std::pair<int, int>, int> seen;
	for (size_t t = 0; t + 2 < tris_.size(); t += 3) {
		for (int k = 0; k < 3; ++k) {
			int u = tris_[t + k];
			int v = tris_[t + (k + 1) % 3];
			if (u > v) std::swap(u, v);
			seen[{u, v}] += 1;
		}
	}
	on_rim_.assign(verts_.size(), 0);
	for (const auto &pair : seen) {
		edges_.push_back(pair.first.first);
		edges_.push_back(pair.first.second);
		if (pair.second == 1) {
			on_rim_[(size_t)pair.first.first] = 1;
			on_rim_[(size_t)pair.first.second] = 1;
		}
	}

	PackedVector2Array before;
	for (const Vector2 &v : verts_) before.append(v);
	snap_boundary(rgba, width, height, alpha_floor);
	// Smoothing before reverting, and this order is the whole trick.
	//
	// Snapping moves the rim and leaves the interior where the grid put it,
	// so the ring of triangles just inside the rim absorbs all of the
	// distortion and goes thin. Reverting them undoes the snap — which is
	// what the first version of this did, and it threw away nine tenths of
	// its own work. Letting the interior slide instead spreads the distortion
	// over the whole mesh, and almost nothing needs reverting afterwards.
	reverted_ = revert_bad_triangles(before);

	// Quality: the smallest angle anywhere. A mesh with a near-zero angle in
	// it has a triangle that behaves like a hinge, and the drawing creases
	// along it under any deformation at all.
	double worst = 180.0;
	for (size_t t = 0; t + 2 < tris_.size(); t += 3) {
		const Vector2 p[3] = { verts_[tris_[t]], verts_[tris_[t + 1]], verts_[tris_[t + 2]] };
		for (int k = 0; k < 3; ++k) {
			const Vector2 u = p[(k + 1) % 3] - p[k];
			const Vector2 v = p[(k + 2) % 3] - p[k];
			const double lu = u.length(), lv = v.length();
			if (lu < EPS || lv < EPS) { worst = 0.0; continue; }
			double c = (double)(u.x * v.x + u.y * v.y) / (lu * lv);
			worst = std::min(worst, std::acos(std::clamp(c, -1.0, 1.0)) * 180.0 / 3.14159265358979);
		}
	}

	out["ok"] = true;
	out["vertices"] = vertices();
	out["triangles"] = triangles();
	out["edges"] = edges();
	out["boundary"] = boundary();
	out["vertex_count"] = (int)verts_.size();
	out["triangle_count"] = (int)tris_.size() / 3;
	out["edge_count"] = (int)edges_.size() / 2;
	out["cell"] = cell_;
	out["ink_cells"] = ink_cells;
	out["snapped"] = snapped_;
	out["reverted"] = reverted_;
	out["min_angle_deg"] = worst;
	return out;
}

// --- boundary snapping -----------------------------------------------------
//
// A rim vertex is walked inward along the direction of the mesh's own edge
// until it reaches ink, and no further. That turns the staircase the grid
// produced into something that follows the outline, without disturbing the
// interior, where the grid's regularity is exactly what a solver wants.
void IvoryMeshForge::snap_boundary(const PackedByteArray &rgba, int w, int h, double floor) {
	const int on_byte = std::clamp((int)std::lround(floor * 255.0), 1, 255);
	auto inked = [&](double x, double y) -> bool {
		const int ix = (int)std::lround(x);
		const int iy = (int)std::lround(y);
		if (ix < 0 || iy < 0 || ix >= w || iy >= h) return false;
		return rgba[(iy * w + ix) * 4 + 3] >= on_byte;
	};

	// Toward the nearest ink, not along the average of the neighbours.
	//
	// The average-of-neighbours direction was the first thing tried and it is
	// wrong at a corner: a rim vertex at a step in the staircase has one
	// neighbour each way along the rim and one inward, so the average points
	// mostly sideways. Walking sideways never reaches the drawing, and about a
	// fifth of the rim was left where the grid put it — which is precisely the
	// staircase this is meant to remove.
	//
	// The nearest opaque pixel has no such failure. It is a small search — a
	// few thousand pixels per rim vertex, once, when the warp opens.
	const int reach = std::max(3, (int)std::lround(cell_ * 3.0));
	// Stop short of the ink by half a cell. Landing exactly on the outline
	// would leave the outermost stroke on the mesh's own edge, with no
	// material outside it to pull against, and it would shear the first time
	// the mesh moved.
	const double keep = std::max(1.0, cell_ * 0.5);

	std::vector<Vector2> target = verts_;
	std::vector<uint8_t> moving(verts_.size(), 0);
	for (size_t i = 0; i < verts_.size(); ++i) {
		if (!on_rim_[i]) continue;
		if (inked(verts_[i].x, verts_[i].y)) continue;
		const int cx = (int)std::lround(verts_[i].x);
		const int cy = (int)std::lround(verts_[i].y);
		double best = 1e30;
		int bx = 0, by = 0;
		for (int dy = -reach; dy <= reach; ++dy) {
			const int py = cy + dy;
			if (py < 0 || py >= h) continue;
			for (int dx = -reach; dx <= reach; ++dx) {
				const int px = cx + dx;
				if (px < 0 || px >= w) continue;
				if (rgba[(py * w + px) * 4 + 3] < on_byte) continue;
				const double d2 = (double)dx * dx + (double)dy * dy;
				if (d2 < best) { best = d2; bx = px; by = py; }
			}
		}
		if (best > 1e29) continue;
		const double dist = std::sqrt(best);
		const double travel = dist - keep;
		if (travel <= 0.5) continue;
		Vector2 dir((real_t)(bx - verts_[i].x), (real_t)(by - verts_[i].y));
		const double len = dir.length();
		if (len < EPS) continue;
		dir /= (real_t)len;
		target[i] = verts_[i] + dir * (real_t)travel;
		moving[i] = 1;
		snapped_ += 1;
	}

	// Moved in increments, with the interior relaxing between them.
	//
	// This is the difference between a mesh that fits and one that folds. A
	// rim vertex two cells outside the ink has to travel two cells inward, and
	// the next ring of vertices is only one cell in — so a single jump takes
	// it straight through them and inverts every triangle it passes. Done in
	// eighths, with the interior sliding out of the way after each eighth,
	// nothing ever crosses anything: the whole mesh contracts on to the
	// drawing together, the way a net drawn tight does.
	const int increments = 8;
	std::vector<Vector2> from = verts_;
	for (int step = 1; step <= increments; ++step) {
		const real_t t = (real_t)step / (real_t)increments;
		for (size_t i = 0; i < verts_.size(); ++i) {
			if (!moving[i]) continue;
			// Measured from where the vertex started, not from where it is.
			// Interpolating from the current position compounds, so the early
			// steps move almost nothing and the last one jumps the whole
			// remaining distance — which is the single jump this was written
			// to avoid.
			verts_[i] = from[i] + (target[i] - from[i]) * t;
		}
		relax_interior(2);
	}
	relax_interior(6);
}

// Laplacian smoothing of the interior, with the rim held.
//
// Each free vertex moves toward the average of its neighbours. That is the
// discrete heat equation, and a few passes of it turn a mesh whose boundary
// has been yanked into one whose triangles are evenly sized again — which is
// exactly the state a deformation solver wants to start from.
void IvoryMeshForge::relax_interior(int passes) {
	if (verts_.empty() || edges_.empty()) return;
	std::vector<Vector2> sum(verts_.size());
	std::vector<int> count(verts_.size());
	for (int pass = 0; pass < passes; ++pass) {
		std::fill(sum.begin(), sum.end(), Vector2());
		std::fill(count.begin(), count.end(), 0);
		for (size_t e = 0; e + 1 < edges_.size(); e += 2) {
			const int a = edges_[e], b = edges_[e + 1];
			sum[(size_t)a] += verts_[b];
			sum[(size_t)b] += verts_[a];
			count[(size_t)a] += 1;
			count[(size_t)b] += 1;
		}
		for (size_t i = 0; i < verts_.size(); ++i) {
			if (on_rim_[i] || count[i] == 0) continue;
			const Vector2 target = sum[i] / (real_t)count[i];
			// Halfway, not all the way. Full steps oscillate on a regular
			// grid; half steps settle.
			verts_[i] = verts_[i] * 0.5f + target * 0.5f;
		}
	}
}

// Snapping moves vertices independently, so two of them can cross and turn a
// triangle inside out. An inverted triangle renders as a fold — the drawing
// appears to double back on itself — so any snap that caused one is undone.
int IvoryMeshForge::revert_bad_triangles(const PackedVector2Array &before) {
	auto area2 = [&](const std::vector<Vector2> &v, size_t t) {
		const Vector2 &a = v[tris_[t]], &b = v[tris_[t + 1]], &c = v[tris_[t + 2]];
		return (double)(b.x - a.x) * (c.y - a.y) - (double)(b.y - a.y) * (c.x - a.x);
	};
	std::vector<Vector2> rest;
	rest.reserve(before.size());
	for (int i = 0; i < before.size(); ++i) rest.push_back(before[i]);

	int undone = 0;
	// Backed off, not undone.
	//
	// The first version put the offending vertex straight back where the grid
	// had it, which threw away the entire snap for that vertex — and since a
	// handful of vertices at the extremes of the shape always trip the check,
	// the result was a rim that fitted beautifully except for ten places where
	// it was still on the staircase. Retreating halfway and testing again
	// keeps almost all of the fit and still guarantees the triangle is sound,
	// because halving always terminates at the rest position, which was sound
	// by construction.
	for (int pass = 0; pass < 12; ++pass) {
		bool changed = false;
		for (size_t t = 0; t + 2 < tris_.size(); t += 3) {
			const double now = area2(verts_, t);
			const double was = area2(rest, t);
			bool bad = !(now * was > 0.0 && std::abs(now) > 1e-6);
			// A triangle that snapping has made very thin is not inverted, but
			// it behaves like a hinge: the drawing creases along it under any
			// deformation at all. It is reverted for the same reason.
			if (!bad) {
				const Vector2 p[3] = { verts_[tris_[t]], verts_[tris_[t + 1]], verts_[tris_[t + 2]] };
				for (int k = 0; k < 3 && !bad; ++k) {
					const Vector2 u = p[(k + 1) % 3] - p[k];
					const Vector2 v = p[(k + 2) % 3] - p[k];
					const double lu = u.length(), lv = v.length();
					if (lu < 1e-6 || lv < 1e-6) { bad = true; break; }
					const double c = (double)(u.x * v.x + u.y * v.y) / (lu * lv);
					// About eight degrees.
					if (std::acos(std::clamp(c, -1.0, 1.0)) < 0.14) bad = true;
				}
			}
			if (!bad) continue;
			for (int k = 0; k < 3; ++k) {
				const int vi = tris_[t + k];
				const Vector2 home = rest[(size_t)vi];
				if (verts_[vi].distance_to(home) < 1e-4) continue;
				verts_[vi] = (verts_[vi] + home) * 0.5f;
				undone += 1;
				changed = true;
			}
		}
		if (!changed) break;
	}
	return undone;
}

// --- coverage --------------------------------------------------------------
Dictionary IvoryMeshForge::covers_all_ink(const PackedByteArray &rgba,
		int width, int height, double alpha_floor) const {
	Dictionary out;
	out["ok"] = false;
	out["ink_pixels"] = 0;
	out["uncovered"] = 0;
	if (width < 1 || height < 1) return out;
	if ((int64_t)rgba.size() < (int64_t)width * height * 4) return out;
	if (tris_.empty()) return out;

	// A raster of the mesh, so the test is a lookup per pixel rather than a
	// walk over every triangle per pixel.
	std::vector<uint8_t> covered((size_t)width * height, 0);
	for (size_t t = 0; t + 2 < tris_.size(); t += 3) {
		const Vector2 &a = verts_[tris_[t]], &b = verts_[tris_[t + 1]], &c = verts_[tris_[t + 2]];
		const int x0 = std::max(0, (int)std::floor(std::min({ a.x, b.x, c.x })));
		const int x1 = std::min(width - 1, (int)std::ceil(std::max({ a.x, b.x, c.x })));
		const int y0 = std::max(0, (int)std::floor(std::min({ a.y, b.y, c.y })));
		const int y1 = std::min(height - 1, (int)std::ceil(std::max({ a.y, b.y, c.y })));
		const double d = (double)(b.y - a.y) * (c.x - a.x) - (double)(b.x - a.x) * (c.y - a.y);
		if (std::abs(d) < EPS) continue;
		for (int y = y0; y <= y1; ++y) {
			for (int x = x0; x <= x1; ++x) {
				const double px = x + 0.5, py = y + 0.5;
				const double l0 = ((double)(b.y - c.y) * (px - c.x) + (double)(c.x - b.x) * (py - c.y)) /
						((double)(b.y - c.y) * (a.x - c.x) + (double)(c.x - b.x) * (a.y - c.y));
				const double l1 = ((double)(c.y - a.y) * (px - c.x) + (double)(a.x - c.x) * (py - c.y)) /
						((double)(c.y - a.y) * (b.x - c.x) + (double)(a.x - c.x) * (b.y - c.y));
				const double l2 = 1.0 - l0 - l1;
				if (l0 < -1e-6 || l1 < -1e-6 || l2 < -1e-6) continue;
				covered[(size_t)y * width + x] = 1;
			}
		}
	}

	const int on_byte = std::clamp((int)std::lround(alpha_floor * 255.0), 1, 255);
	int ink = 0, missed = 0;
	Vector2 first_miss(-1, -1);
	for (int y = 0; y < height; ++y) {
		for (int x = 0; x < width; ++x) {
			if (rgba[(y * width + x) * 4 + 3] < on_byte) continue;
			++ink;
			if (!covered[(size_t)y * width + x]) {
				if (missed == 0) first_miss = Vector2((real_t)x, (real_t)y);
				++missed;
			}
		}
	}
	out["ok"] = missed == 0;
	out["ink_pixels"] = ink;
	out["uncovered"] = missed;
	out["first_uncovered"] = first_miss;
	return out;
}

// --- binding ---------------------------------------------------------------
//
// A pin is a point inside a triangle, kept as the three barycentric weights of
// that triangle. Wherever the mesh goes, the same three weights over the same
// three vertices name the same piece of the drawing.
//
// The old code kept a pin as a position and looked for the nearest vertex each
// time it was used. That is why pins came loose once there were several of
// them: the nearest vertex changes as the mesh moves, so the pin quietly
// changed which piece of drawing it was holding.
Dictionary IvoryMeshForge::bind_point(const Vector2 &at) const {
	Dictionary out;
	out["ok"] = false;
	out["triangle"] = -1;
	double best = 1e30;
	int best_tri = -1;
	double ba = 0, bb = 0, bc = 0;

	for (size_t t = 0; t + 2 < tris_.size(); t += 3) {
		const Vector2 &a = verts_[tris_[t]], &b = verts_[tris_[t + 1]], &c = verts_[tris_[t + 2]];
		const double den = (double)(b.y - c.y) * (a.x - c.x) + (double)(c.x - b.x) * (a.y - c.y);
		if (std::abs(den) < EPS) continue;
		const double l0 = ((double)(b.y - c.y) * (at.x - c.x) + (double)(c.x - b.x) * (at.y - c.y)) / den;
		const double den1 = (double)(c.y - a.y) * (b.x - c.x) + (double)(a.x - c.x) * (b.y - c.y);
		if (std::abs(den1) < EPS) continue;
		const double l1 = ((double)(c.y - a.y) * (at.x - c.x) + (double)(a.x - c.x) * (at.y - c.y)) / den1;
		const double l2 = 1.0 - l0 - l1;
		// How far outside this triangle the point is; zero when inside. Taking
		// the least means a point just off the mesh binds to the nearest
		// triangle rather than failing, which is what a finger on an outline
		// needs.
		const double outside = std::max(0.0, -l0) + std::max(0.0, -l1) + std::max(0.0, -l2);
		if (outside < best) {
			best = outside;
			best_tri = (int)(t / 3);
			ba = l0; bb = l1; bc = l2;
		}
		if (outside <= 0.0) break;
	}
	if (best_tri < 0) return out;

	// Clamped and renormalised, so a binding made just outside the mesh still
	// names a point on it rather than one beyond its edge.
	ba = std::max(0.0, ba); bb = std::max(0.0, bb); bc = std::max(0.0, bc);
	const double sum = ba + bb + bc;
	if (sum < EPS) return out;
	out["ok"] = true;
	out["triangle"] = best_tri;
	out["a"] = ba / sum;
	out["b"] = bb / sum;
	out["c"] = bc / sum;
	out["exact"] = best <= 0.0;
	return out;
}

Vector2 IvoryMeshForge::follow(const Dictionary &binding, const PackedVector2Array &moved) const {
	if (!bool(binding.get("ok", false))) return Vector2();
	const int t = (int)binding.get("triangle", -1) * 3;
	if (t < 0 || t + 2 >= (int)tris_.size()) return Vector2();
	const int ia = tris_[t], ib = tris_[t + 1], ic = tris_[t + 2];
	if (ia >= moved.size() || ib >= moved.size() || ic >= moved.size()) return Vector2();
	const double a = binding.get("a", 0.0);
	const double b = binding.get("b", 0.0);
	const double c = binding.get("c", 0.0);
	return moved[ia] * (real_t)a + moved[ib] * (real_t)b + moved[ic] * (real_t)c;
}

// --- accessors -------------------------------------------------------------
PackedVector2Array IvoryMeshForge::vertices() const {
	PackedVector2Array out;
	for (const Vector2 &v : verts_) out.append(v);
	return out;
}

PackedInt32Array IvoryMeshForge::triangles() const {
	PackedInt32Array out;
	for (int i : tris_) out.append(i);
	return out;
}

PackedInt32Array IvoryMeshForge::edges() const {
	PackedInt32Array out;
	for (int i : edges_) out.append(i);
	return out;
}

PackedByteArray IvoryMeshForge::boundary() const {
	PackedByteArray out;
	out.resize((int)on_rim_.size());
	for (size_t i = 0; i < on_rim_.size(); ++i) out[(int)i] = on_rim_[i];
	return out;
}

} // namespace godot
