#ifndef IVORY_TOUCH_H
#define IVORY_TOUCH_H

// What the finger actually meant, from what the screen actually reported.
//
// ## The two problems, which are opposites
//
// A touch screen reports a position that is **noisy** — a still finger jitters
// by a pixel or two — and it reports it **late**, because the panel scans, the
// system batches, and the frame is drawn after all of that. Between the two
// there is usually twenty to forty milliseconds between where the finger is
// and where the pin is drawn.
//
// Smoothing fixes the first and makes the second worse: every filter that
// removes jitter does it by lagging. So the answer cannot be a filter alone.
//
// ## The one-euro filter
//
// Casiez, Roussel and Vogel (2012). An exponential filter whose cutoff
// frequency rises with the speed of the pointer:
//
//     cutoff = min_cutoff + beta * |speed|
//
// Standing still, the cutoff is low and the jitter is gone. Moving fast, the
// cutoff is high, the filter is nearly transparent, and there is nearly no
// lag. It is one line of insight and it beats every fixed-cutoff filter at
// both ends at once, which is why it is what touch pipelines use.
//
// The speed itself is filtered — a derivative of a noisy signal is noisier
// than the signal — at its own fixed cutoff.
//
// ## And the lead
//
// The lag that is left is systematic rather than random, so it can be
// subtracted rather than filtered: the position is advanced along the filtered
// velocity by a fixed number of milliseconds. Held small, because prediction
// buys responsiveness with overshoot at direction changes and the trade turns
// bad quickly — twelve milliseconds is about a frame's worth of latency
// removed with no visible overshoot on a hand-drawn arc.
//
// This is applied to **pin dragging and joint posing**, never to drawing. A
// brush stroke is a record of where the hand went and predicting it would be
// inventing ink; a pin is a control being aimed, and a control that arrives
// where the thumb already is feels like the thumb is touching the drawing
// rather than pushing it.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class IvoryTouch : public RefCounted {
	GDCLASS(IvoryTouch, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryTouch();
	~IvoryTouch();

	void configure(double min_cutoff, double beta, double speed_cutoff,
			double lead_ms, double deadband_px = 0.0);
	void set_deadband(double pixels);
	double deadband() const { return deadband_; }
	void reset();
	// `now` is a timestamp in seconds. Returns where the finger is judged to
	// be, which is not quite where the screen said it was.
	Vector2 filter(const Vector2 &raw, double now);
	Vector2 velocity() const;
	// Touch diagnostics used by the bone rig. These measure the digitizer,
	// not the artwork, so a noisy panel can be corrected without ever altering
	// a brush stroke.
	Dictionary metrics() const;
	void sample_pressure(double pressure);
	void reset_metrics();
	bool stable() const;
	bool started() const;
	

private:
	double min_cutoff_ = 1.2;
	double beta_ = 0.035;
	double speed_cutoff_ = 1.0;
	double lead_ = 0.012;
	// Screen-space quiet zone. It rejects digitizer micro-motion before the
	// derivative opens the filter, so a still bone joint cannot tremble.
	double deadband_ = 0.0;
	double jitter_sq_sum_ = 0.0;
	double max_speed_ = 0.0;
	double pressure_ = 1.0;
	int sample_count_ = 0;
	int deadband_hits_ = 0;

	bool have_ = false;
	double last_time_ = 0.0;
	Vector2 value_;
	Vector2 speed_;
	Vector2 raw_last_;

	static double alpha_for(double cutoff, double dt);
};

} // namespace godot

#endif // IVORY_TOUCH_H
