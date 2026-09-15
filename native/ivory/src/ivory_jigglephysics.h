#ifndef IVORY_JIGGLEPHYSICS_H
#define IVORY_JIGGLEPHYSICS_H

// Secondary motion. Hair, hems, and the last joint of an arm, moving a beat
// after the thing that carries them.
//
// ================================================================
// Where this came from, and what it is not
// ================================================================
//
// Stretchy Studio's `src/io/live2d/cmo3/physics.js` writes a
// `CPhysicsSettingsSourceSet`: a description of a pendulum chain, saved into
// a `.cmo3` file for Cubism Editor to simulate later. That file is an
// *export format*. It has no `update(delta)` — nothing in the reference
// runs the pendulum, because nothing in the reference needs to: the sim
// happens afterward, inside Cubism, on somebody else's clock.
//
// The touch room needs the opposite thing. A finger drags a head turn across
// the canvas *now*, sixty times a second, and hair that snapped to the new
// angle instantly would look like it was nailed on. So this class keeps the
// authoring vocabulary Stretchy Studio uses — a chain of vertices, each with
// a `radius`, a `mobility`, a `delay`, and an `acceleration` — and gives it
// the one thing the export format never needed: a solver that steps forward
// in time and can be asked, every frame, where each vertex has got to.
//
// ## The chain
//
// Vertex 0 is the anchor and tracks the driving angle exactly — it is the
// bone or parameter this dial is riding on, not a separate physical body.
// Every later vertex chases the one before it with a critically-damped
// spring: `acceleration` scales how hard it pulls toward its parent's
// current angle, `delay` sets how much that pull is damped (low delay is a
// loose, trailing tail; high delay is a stiff one that arrives almost at
// once), and `mobility` blends between the free swing and rigidly following
// the parent outright — nought mobility is a vertex that does not swing at
// all, one is a vertex with nothing holding it back.
//
// This is a physically-motivated approximation tuned for a believable touch
// feel, not a reimplementation of Cubism's own (closed, undocumented)
// runtime — the reference in this repository is the XML it writes, not the
// solver that reads it, so there is nothing to port byte-for-byte.
//
// ## Cost and safety
//
// Every vertex is one spring step: a couple of multiplies and adds. A chain
// of six settings with three vertices each is under thirty float ops a
// frame, which is nothing next to a touch redraw. No allocation after
// `add_setting`/`add_vertex`, no platform calls, nothing that behaves any
// differently on Android than on desktop.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <vector>

namespace godot {

class IvoryJigglePhysics : public RefCounted {
	GDCLASS(IvoryJigglePhysics, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryJigglePhysics() = default;
	~IvoryJigglePhysics() = default;

	// A new empty chain. Returns its index.
	int add_setting();
	void remove_setting(int setting);
	void clear();
	int setting_count() const { return (int)setting_.size(); }

	// A vertex on the chain, appended after the last one. Vertex 0 of a
	// fresh chain is the anchor; give it mobility 0 so it has nothing to
	// resist and simply tracks the driving angle. `radius` is kept only
	// because Stretchy Studio's rules carry it (rest-pose arm length); the
	// solver itself does not need it to produce a lagged angle, only to
	// stay a faithful home for data authored on the other side.
	int add_vertex(int setting, double radius, double mobility, double delay,
			double acceleration);
	int vertex_count(int setting) const;

	// The driving angle, in degrees, measured the way Stretchy Studio's
	// `SRC_TO_G_ANGLE` inputs are: an already-weighted combination of
	// whatever head/body parameters feed this rule. Combining several
	// inputs into one number is the caller's job, same as it is in
	// `physics.js`'s `ruleOutputs` — this class only ever sees the result.
	void set_input(int setting, double degrees);
	double input(int setting) const;

	// Advances every chain by `delta` seconds. Call this once a frame,
	// after `set_input` for anything that moved, before reading
	// `output_angle`.
	void update(double delta);

	// Vertex `vertex`'s current angle, in degrees, scaled the way a
	// Stretchy Studio `PhysicsOutputSpec.scale` is: `scale` is the angle
	// this vertex reads out at a full 30-degree swing of the anchor, which
	// is the same normalization `physics.js` keys its rules to
	// (`normalization.angleMax = 30` on every shipped rule). A vertex with
	// no lag left (freshly reset, or `mobility` 0 all the way down the
	// chain) reads back the anchor's own angle, scaled the same way.
	double output_angle(int setting, int vertex, double scale) const;

	// Zeroes every vertex's angle and velocity without discarding the
	// chain's configuration — for snapping a character back to rest when a
	// document loads, rather than easing in from wherever the last one left
	// off.
	void reset(int setting);

	Dictionary to_project() const;
	void from_project(const Dictionary &state);

private:
	struct Vertex {
		float radius = 0.0f;
		float mobility = 1.0f;
		float delay = 1.0f;
		float acceleration = 1.0f;
		float angle = 0.0f; // degrees
		float velocity = 0.0f; // degrees / second
	};
	struct Setting {
		std::vector<Vertex> vertex;
		float input_deg = 0.0f;
		bool live = true;
	};

	std::vector<Setting> setting_;

	bool setting_ok(int setting) const {
		return setting >= 0 && setting < (int)setting_.size() && setting_[setting].live;
	}
};

} // namespace godot

#endif // IVORY_JIGGLEPHYSICS_H
