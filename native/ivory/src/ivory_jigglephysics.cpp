#include "ivory_jigglephysics.h"

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <algorithm>
#include <cmath>

namespace godot {

namespace {
inline double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}
} // namespace

// ------------------------------------------------------------------ chains

int IvoryJigglePhysics::add_setting() {
	for (int i = 0; i < (int)setting_.size(); ++i) {
		if (!setting_[i].live) {
			setting_[i] = Setting();
			return i;
		}
	}
	setting_.push_back(Setting());
	return (int)setting_.size() - 1;
}

void IvoryJigglePhysics::remove_setting(int setting) {
	if (setting < 0 || setting >= (int)setting_.size()) {
		return;
	}
	setting_[setting] = Setting();
	setting_[setting].live = false;
}

void IvoryJigglePhysics::clear() {
	setting_.clear();
}

// ----------------------------------------------------------------- vertices

int IvoryJigglePhysics::add_vertex(int setting, double radius, double mobility,
		double delay, double acceleration) {
	if (!setting_ok(setting)) {
		return -1;
	}
	Vertex v;
	v.radius = (float)radius;
	v.mobility = (float)clampd(mobility, 0.0, 1.0);
	v.delay = (float)clampd(delay, 0.01, 1.0);
	v.acceleration = (float)std::max(0.0, acceleration);
	setting_[setting].vertex.push_back(v);
	return (int)setting_[setting].vertex.size() - 1;
}

int IvoryJigglePhysics::vertex_count(int setting) const {
	return setting_ok(setting) ? (int)setting_[setting].vertex.size() : 0;
}

// -------------------------------------------------------------------- input

void IvoryJigglePhysics::set_input(int setting, double degrees) {
	if (!setting_ok(setting)) {
		return;
	}
	setting_[setting].input_deg = (float)degrees;
}

double IvoryJigglePhysics::input(int setting) const {
	return setting_ok(setting) ? (double)setting_[setting].input_deg : 0.0;
}

// ------------------------------------------------------------------- solve

void IvoryJigglePhysics::update(double delta) {
	// A stale or huge delta (a breakpoint, a paused app resuming) would
	// otherwise hand the spring a single enormous step and fling the tail
	// off-screen for a frame. Clamped the same way a good animation
	// controller clamps its own delta.
	const float dt = (float)clampd(delta, 0.0, 1.0 / 15.0);
	if (dt <= 0.0f) {
		return;
	}

	for (Setting &s : setting_) {
		if (!s.live || s.vertex.empty()) {
			continue;
		}
		// Vertex 0 is the anchor: it does not swing, it *is* the driving
		// angle. Physical mobility on it would just be a slower, blurrier
		// copy of the same number, which is never what an artist wants
		// from the bone or parameter that started the chain.
		s.vertex[0].angle = s.input_deg;
		s.vertex[0].velocity = 0.0f;

		float parent_angle = s.vertex[0].angle;
		for (size_t i = 1; i < s.vertex.size(); ++i) {
			Vertex &v = s.vertex[i];

			// Critically-damped spring toward the parent's angle. `k`
			// (stiffness) comes from `acceleration` and `delay`: a stiffer,
			// faster-settling spring for a high `delay` (a "quick" vertex,
			// in Stretchy Studio's vocabulary), a loose trailing one for a
			// low `delay`. Damping is set to (very slightly under) the
			// critical value for that stiffness, which settles cleanly
			// without a metronome-like overshoot but keeps enough life that
			// a flicked head turn still reads as cloth or hair rather than
			// a servo.
			const float k = 8.0f + 40.0f * v.delay * std::max(0.1f, v.acceleration);
			const float c = 1.9f * std::sqrt(k);

			const float error = parent_angle - v.angle;
			const float accel = k * error - c * v.velocity;
			v.velocity += accel * dt;

			float dynamic_angle = v.angle + v.velocity * dt;

			// `mobility` blends between that free swing and rigidly
			// tracking the parent — nought is a vertex with nothing to
			// swing (a pinned hem), one is a vertex with nothing holding it
			// back at all.
			v.angle = parent_angle * (1.0f - v.mobility) + dynamic_angle * v.mobility;
			if (v.mobility <= 0.0f) {
				v.velocity = 0.0f;
			}

			parent_angle = v.angle;
		}
	}
}

// ------------------------------------------------------------------ output

double IvoryJigglePhysics::output_angle(int setting, int vertex, double scale) const {
	if (!setting_ok(setting)) {
		return 0.0;
	}
	const Setting &s = setting_[setting];
	if (vertex < 0 || vertex >= (int)s.vertex.size()) {
		return 0.0;
	}
	// Same normalization Stretchy Studio's shipped rules key their
	// `outputScale` to: `scale` degrees of output at a full 30-degree
	// swing of the anchor. See `normalization.angleMax` on every rule in
	// `physics.js` — all 30.
	return ((double)s.vertex[vertex].angle / 30.0) * scale;
}

void IvoryJigglePhysics::reset(int setting) {
	if (!setting_ok(setting)) {
		return;
	}
	for (Vertex &v : setting_[setting].vertex) {
		v.angle = 0.0f;
		v.velocity = 0.0f;
	}
	setting_[setting].input_deg = 0.0f;
}

// ----------------------------------------------------------------- project

Dictionary IvoryJigglePhysics::to_project() const {
	Array settings_out;
	for (const Setting &s : setting_) {
		Dictionary sd;
		sd["live"] = s.live;
		sd["input_deg"] = s.input_deg;
		Array vertices_out;
		for (const Vertex &v : s.vertex) {
			Dictionary vd;
			vd["radius"] = v.radius;
			vd["mobility"] = v.mobility;
			vd["delay"] = v.delay;
			vd["acceleration"] = v.acceleration;
			vd["angle"] = v.angle;
			vd["velocity"] = v.velocity;
			vertices_out.push_back(vd);
		}
		sd["vertices"] = vertices_out;
		settings_out.push_back(sd);
	}
	Dictionary out;
	out["settings"] = settings_out;
	return out;
}

void IvoryJigglePhysics::from_project(const Dictionary &state) {
	clear();
	if (!state.has("settings")) {
		return;
	}
	Array settings_in = state["settings"];
	for (int i = 0; i < settings_in.size(); ++i) {
		Dictionary sd = settings_in[i];
		Setting s;
		s.live = sd.has("live") ? (bool)sd["live"] : true;
		s.input_deg = sd.has("input_deg") ? (float)(double)sd["input_deg"] : 0.0f;
		if (sd.has("vertices")) {
			Array vertices_in = sd["vertices"];
			for (int j = 0; j < vertices_in.size(); ++j) {
				Dictionary vd = vertices_in[j];
				Vertex v;
				v.radius = vd.has("radius") ? (float)(double)vd["radius"] : 0.0f;
				v.mobility = vd.has("mobility") ? (float)(double)vd["mobility"] : 1.0f;
				v.delay = vd.has("delay") ? (float)(double)vd["delay"] : 1.0f;
				v.acceleration = vd.has("acceleration") ? (float)(double)vd["acceleration"] : 1.0f;
				v.angle = vd.has("angle") ? (float)(double)vd["angle"] : 0.0f;
				v.velocity = vd.has("velocity") ? (float)(double)vd["velocity"] : 0.0f;
				s.vertex.push_back(v);
			}
		}
		setting_.push_back(s);
	}
}

// -------------------------------------------------------------------- bind

void IvoryJigglePhysics::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_setting"), &IvoryJigglePhysics::add_setting);
	ClassDB::bind_method(D_METHOD("remove_setting", "setting"),
			&IvoryJigglePhysics::remove_setting);
	ClassDB::bind_method(D_METHOD("clear"), &IvoryJigglePhysics::clear);
	ClassDB::bind_method(D_METHOD("setting_count"), &IvoryJigglePhysics::setting_count);
	ClassDB::bind_method(
			D_METHOD("add_vertex", "setting", "radius", "mobility", "delay", "acceleration"),
			&IvoryJigglePhysics::add_vertex);
	ClassDB::bind_method(D_METHOD("vertex_count", "setting"),
			&IvoryJigglePhysics::vertex_count);
	ClassDB::bind_method(D_METHOD("set_input", "setting", "degrees"),
			&IvoryJigglePhysics::set_input);
	ClassDB::bind_method(D_METHOD("input", "setting"), &IvoryJigglePhysics::input);
	ClassDB::bind_method(D_METHOD("update", "delta"), &IvoryJigglePhysics::update);
	ClassDB::bind_method(D_METHOD("output_angle", "setting", "vertex", "scale"),
			&IvoryJigglePhysics::output_angle);
	ClassDB::bind_method(D_METHOD("reset", "setting"), &IvoryJigglePhysics::reset);
	ClassDB::bind_method(D_METHOD("to_project"), &IvoryJigglePhysics::to_project);
	ClassDB::bind_method(D_METHOD("from_project", "state"),
			&IvoryJigglePhysics::from_project);
}

} // namespace godot
