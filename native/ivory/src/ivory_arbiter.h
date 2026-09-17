#ifndef IVORY_ARBITER_H
#define IVORY_ARBITER_H

// One tool at a time, everywhere in the app.
//
// ## The rule
//
// **No two buttons may be pressed and working at once.** Choosing a new one
// takes the old one's effect away completely before the new one begins.
//
// This sounds like something the interface should manage, and that is exactly
// why it kept going wrong. Each screen had its own idea of what "off" meant —
// the comic board's cut mode, the move tool's floating box, the blend tool's carried colour, the blend tool's carried colour — and each one was turned off by the
// screens that happened to remember to turn it off. Every new tool added is
// another entry in a table nobody has, and the failure is silent: two modes
// are live, a stroke does something nobody asked for, and it costs somebody a
// page.
//
// So there is one place that owns the answer, and it is here rather than in
// GDScript because it has to be the same answer for the drawing screen, the
// animation screen, the comic screen and the knitting board. A rule kept in
// four places is four rules.
//
// ## Standing tools
//
// Some things on the rail are not modes. A skeleton is *structure* — it is
// part of the layer the way the ink is, not a state the app is temporarily
// in. Turning it off because somebody picked up the brush would be deleting
// work, not tidying up.
//
// So a tool is registered as one of two kinds:
//
//   * **`KIND_MODE`** — the ordinary sort. Exactly one may be live. Choosing
//     another ends it, and the cancel gesture ends it.
//   * **`KIND_STANDING`** — structure, like the bone rig. It is not counted
//     among the modes, choosing a mode does not disturb it, and the cancel
//     gesture leaves it alone. This is the "the ones built like bones do not
//     count" exemption, made explicit rather than remembered.
//
// ## Four fingers
//
// A way out that always works, from anywhere, without hunting for whichever
// button turned the current state on.
//
// Four, not three: three fingers is within reach of a hand resting on a phone
// while the thumb draws, and a gesture that fires by accident while somebody
// is working is worse than no gesture. Four fingers on a screen is a
// deliberate act.
//
// It is recognised as a **tap**, which means three separate conditions and not
// one:
//
//   * four touches down **at the same time** — within a short window, so that
//     four fingers landing one after another over a second is not it;
//   * **none of them travelled** — a four-finger drag is a pan, and the pan
//     must not also cancel the tool;
//   * and they were down **briefly** — a rested hand is not a tap.
//
// Any of the three failing means no cancel. All three are cheap and all three
// matter: dropping the movement test alone is enough to make every four-finger
// pan cancel the tool underneath it.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <map>
#include <vector>

namespace godot {

class IvoryArbiter : public RefCounted {
	GDCLASS(IvoryArbiter, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryArbiter() = default;
	~IvoryArbiter() = default;

	enum Kind {
		KIND_MODE,
		KIND_STANDING,
	};

	// --- what exists ---

	// Registers a tool. Calling it again for the same id changes its kind,
	// which is what a screen does when the same button means something
	// different in a different project.
	void offer(const String &id, int kind);
	void forget(const String &id);
	bool known(const String &id) const;
	int kind_of(const String &id) const;
	PackedStringArray offered() const;

	// --- choosing ---

	// Picks a tool. Returns what happened, including the id of whatever was
	// dropped so the caller can tear its effect down.
	//
	// Choosing the tool that is already live turns it **off**. A rail where
	// the lit button does nothing when pressed leaves people tapping it and
	// wondering; a rail where it turns the mode off is how every drawing
	// program behaves.
	Dictionary choose(const String &id);

	// Turns off whatever mode is live. Standing tools are untouched.
	Dictionary clear();

	String live() const { return live_; }
	bool anything_live() const { return !live_.is_empty(); }

	// Whether a standing tool is up. Several may be, and none of them is
	// "the live tool".
	bool standing(const String &id) const;
	PackedStringArray standing_now() const;
	void raise(const String &id);
	void lower(const String &id);

	// --- the four-finger cancel ---

	// A touch went down. `id` is the platform's finger index.
	void finger_down(int id, const Vector2 &at, double now);
	void finger_moved(int id, const Vector2 &at);
	// A touch came up. Returns whether this release completed the gesture,
	// and what it cancelled.
	Dictionary finger_up(int id, double now);
	int fingers_down() const { return (int)touch_.size(); }

	// How far a finger may travel and still count as having stayed put, and
	// how long the four may take to arrive and to leave.
	void set_gesture(double slop_px, double gather_s, double hold_s);

	// How many times the gesture has fired. For the settings screen, which
	// shows people that it is working.
	int cancels() const { return cancels_; }

private:
	struct Touch {
		Vector2 down;
		Vector2 at;
		double when = 0.0;
		double travelled = 0.0;
	};

	std::map<String, int> kind_;
	std::map<String, bool> up_;
	String live_;

	std::map<int, Touch> touch_;
	// How many were down at once during this gesture, and whether any of
	// them has disqualified it. Kept across the releases, because by the
	// time the fourth finger lifts there is only one left to look at.
	int peak_ = 0;
	bool spoiled_ = false;
	double first_down_ = 0.0;

	double slop_ = 14.0;
	double gather_ = 0.35;
	double hold_ = 1.10;
	int cancels_ = 0;

	void reset_gesture();
};

} // namespace godot

VARIANT_ENUM_CAST(IvoryArbiter::Kind);

#endif // IVORY_ARBITER_H
