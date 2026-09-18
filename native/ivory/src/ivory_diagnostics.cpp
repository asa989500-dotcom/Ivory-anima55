#include "ivory_diagnostics.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
constexpr double EPS = 1.0e-9;
constexpr double DEFAULT_MAX_DISPLACEMENT = 1.0e9;
}

void IvoryDiagnostics::_bind_methods() {
	ClassDB::bind_method(D_METHOD("check_mesh", "rest", "neighbours", "rim",
			"triangles", "min_area"), &IvoryDiagnostics::check_mesh);
	ClassDB::bind_method(D_METHOD("check_pose", "rest", "now",
			"max_displacement"), &IvoryDiagnostics::check_pose);
	ClassDB::bind_method(D_METHOD("check_pins", "rest_pins", "now_pins",
			"vertex", "turn", "vertex_count"), &IvoryDiagnostics::check_pins);
	ClassDB::bind_method(D_METHOD("check_bounds", "points", "min_corner",
			"max_corner", "epsilon"), &IvoryDiagnostics::check_bounds);
	ClassDB::bind_method(D_METHOD("check_frame", "elapsed_ms", "budget_ms",
			"vertex_count", "triangle_count"), &IvoryDiagnostics::check_frame);
	ClassDB::bind_method(D_METHOD("health", "mesh", "pose", "pins",
			"bounds", "frame"), &IvoryDiagnostics::health);
}

bool IvoryDiagnostics::finite(double value) {
	return std::isfinite(value);
}

bool IvoryDiagnostics::finite_vec(const Vector2 &value) {
	return finite(value.x) && finite(value.y);
}

double IvoryDiagnostics::area(const Vector2 &a, const Vector2 &b,
		const Vector2 &c) {
	return 0.5 * ((double)(b.x - a.x) * (double)(c.y - a.y)
			- (double)(c.x - a.x) * (double)(b.y - a.y));
}

void IvoryDiagnostics::issue(Array &issues, const String &code,
		const String &detail, int index) {
	Dictionary row;
	row["code"] = code;
	row["detail"] = detail;
	if (index >= 0) {
		row["index"] = index;
	}
	issues.append(row);
}

Dictionary IvoryDiagnostics::result(bool ok, int failures,
		const Array &issues) {
	Dictionary out;
	out["ok"] = ok;
	out["failures"] = failures;
	out["issues"] = issues;
	return out;
}

Dictionary IvoryDiagnostics::check_mesh(const PackedVector2Array &rest,
		const PackedInt32Array &neighbours, const PackedByteArray &rim,
		const PackedInt32Array &triangles, double min_area) const {
	Array issues;
	int failures = 0;
	const int n = rest.size();
	const double area_floor = std::max(std::fabs(min_area), EPS);

	if (n < 3) {
		issue(issues, "mesh_too_small", "A warp mesh needs at least three vertices.");
		++failures;
	}
	if (neighbours.size() != n * 4) {
		issue(issues, "neighbour_stride", "Neighbour table must contain four entries per vertex.");
		++failures;
	}
	if (rim.size() != n) {
		issue(issues, "rim_size", "Rim flags must contain one entry per vertex.");
		++failures;
	}
	if (triangles.size() % 3 != 0) {
		issue(issues, "triangle_stride", "Triangle index data is not divisible by three.");
		++failures;
	}

	for (int i = 0; i < n; ++i) {
		if (!finite_vec(rest[i])) {
			issue(issues, "non_finite_vertex", "Rest vertex contains NaN or infinity.", i);
			++failures;
			continue;
		}
		for (int k = 0; k < 4 && i * 4 + k < neighbours.size(); ++k) {
			const int j = neighbours[i * 4 + k];
			if (j < -1 || j >= n) {
				issue(issues, "bad_neighbour", "Neighbour index is outside the mesh.", i);
				++failures;
			}
		}
	}

	for (int t = 0; t + 2 < triangles.size(); t += 3) {
		const int a = triangles[t];
		const int b = triangles[t + 1];
		const int c = triangles[t + 2];
		if (a < 0 || b < 0 || c < 0 || a >= n || b >= n || c >= n) {
			issue(issues, "bad_triangle_index", "Triangle references a missing vertex.", t / 3);
			++failures;
			continue;
		}
		const double ar = area(rest[a], rest[b], rest[c]);
		if (!finite(ar) || std::fabs(ar) < area_floor) {
			issue(issues, "degenerate_triangle", "Triangle has near-zero or non-finite rest area.", t / 3);
			++failures;
		}
	}

	Dictionary out = result(failures == 0, failures, issues);
	out["vertices"] = n;
	out["triangles"] = triangles.size() / 3;
	return out;
}

Dictionary IvoryDiagnostics::check_pose(const PackedVector2Array &rest,
		const PackedVector2Array &now, double max_displacement) const {
	Array issues;
	int failures = 0;
	const int n = rest.size();
	const double limit = max_displacement > 0.0 ? max_displacement
			: DEFAULT_MAX_DISPLACEMENT;
	if (now.size() != n) {
		issue(issues, "pose_size", "Current pose must have exactly one point per rest vertex.");
		++failures;
	}
	const int count = std::min(n, (int)now.size());
	for (int i = 0; i < count; ++i) {
		if (!finite_vec(now[i])) {
			issue(issues, "non_finite_pose", "Pose contains NaN or infinity.", i);
			++failures;
			continue;
		}
		const double dx = (double)now[i].x - (double)rest[i].x;
		const double dy = (double)now[i].y - (double)rest[i].y;
		if (std::hypot(dx, dy) > limit) {
			issue(issues, "pose_escape", "Vertex displacement exceeded the diagnostic limit.", i);
			++failures;
		}
	}
	Dictionary out = result(failures == 0, failures, issues);
	out["vertices"] = n;
	return out;
}

Dictionary IvoryDiagnostics::check_pins(const PackedVector2Array &rest_pins,
		const PackedVector2Array &now_pins, const PackedInt32Array &vertex,
		const PackedFloat32Array &turn, int vertex_count) const {
	Array issues;
	int failures = 0;
	const int n = rest_pins.size();
	if (now_pins.size() != n || vertex.size() != n || turn.size() != n) {
		issue(issues, "pin_stride", "All pin arrays must have identical lengths.");
		++failures;
	}
	const int count = std::min(n, std::min((int)now_pins.size(), std::min((int)vertex.size(), (int)turn.size())));
	for (int i = 0; i < count; ++i) {
		if (!finite_vec(rest_pins[i]) || !finite_vec(now_pins[i]) || !finite(turn[i])) {
			issue(issues, "non_finite_pin", "Pin data contains NaN or infinity.", i);
			++failures;
		}
		if (vertex[i] < -1 || vertex[i] >= vertex_count) {
			issue(issues, "bad_pin_vertex", "Pin references a vertex outside the mesh.", i);
			++failures;
		}
	}
	Dictionary out = result(failures == 0, failures, issues);
	out["pins"] = n;
	return out;
}

Dictionary IvoryDiagnostics::check_bounds(const PackedVector2Array &points,
		const Vector2 &min_corner, const Vector2 &max_corner, double epsilon) const {
	Array issues;
	int failures = 0;
	const double e = std::max(std::fabs(epsilon), 0.0);
	const float lo_x = std::min(min_corner.x, max_corner.x);
	const float lo_y = std::min(min_corner.y, max_corner.y);
	const float hi_x = std::max(min_corner.x, max_corner.x);
	const float hi_y = std::max(min_corner.y, max_corner.y);
	for (int i = 0; i < points.size(); ++i) {
		const Vector2 &p = points[i];
		if (!finite_vec(p)) {
			issue(issues, "non_finite_bound_point", "Bound check received NaN or infinity.", i);
			++failures;
			continue;
		}
		if ((double)p.x < (double)lo_x - e || (double)p.x > (double)hi_x + e
				|| (double)p.y < (double)lo_y - e || (double)p.y > (double)hi_y + e) {
			issue(issues, "out_of_bounds", "Pose vertex escaped the configured canvas bounds.", i);
			++failures;
		}
	}
	Dictionary out = result(failures == 0, failures, issues);
	out["points"] = points.size();
	return out;
}

Dictionary IvoryDiagnostics::check_frame(double elapsed_ms, double budget_ms,
		int vertex_count, int triangle_count) const {
	Array issues;
	int failures = 0;
	const double budget = budget_ms > 0.0 ? budget_ms : 16.67;
	if (!finite(elapsed_ms) || elapsed_ms < 0.0) {
		issue(issues, "bad_frame_time", "Frame time is invalid.");
		++failures;
	} else if (elapsed_ms > budget) {
		issue(issues, "frame_budget", "Native solve exceeded its configured frame budget.");
		++failures;
	}
	if (vertex_count < 0 || triangle_count < 0) {
		issue(issues, "bad_geometry_count", "Negative geometry count reported to watchdog.");
		++failures;
	}
	Dictionary out = result(failures == 0, failures, issues);
	out["elapsed_ms"] = elapsed_ms;
	out["budget_ms"] = budget;
	out["vertices"] = vertex_count;
	out["triangles"] = triangle_count;
	return out;
}

Dictionary IvoryDiagnostics::health(const Dictionary &mesh,
		const Dictionary &pose, const Dictionary &pins,
		const Dictionary &bounds, const Dictionary &frame) const {
	Array issues;
	int failures = 0;
	const Dictionary checks[] = {mesh, pose, pins, bounds, frame};
	for (int i = 0; i < 5; ++i) {
		if (!bool(checks[i].get("ok", false))) {
			++failures;
			Array rows = checks[i].get("issues", Array());
			for (int j = 0; j < rows.size(); ++j) {
				issues.append(rows[j]);
			}
		}
	}
	Dictionary out = result(failures == 0, failures, issues);
	out["checks"] = 5;
	out["issue_count"] = issues.size();
	return out;
}
