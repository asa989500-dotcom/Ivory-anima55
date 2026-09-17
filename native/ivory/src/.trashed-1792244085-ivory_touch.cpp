#include "ivory_touch.h"

#include <algorithm>
#include <cmath>

using namespace godot;

void IvoryTouch::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "min_cutoff", "beta",
									 "speed_cutoff", "lead_ms", "deadband_px"),
				&IvoryTouch::configure, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("set_deadband", "pixels"),
			&IvoryTouch::set_deadband);
	ClassDB::bind_method(D_METHOD("reset"), &IvoryTouch::reset);
	ClassDB::bind_method(D_METHOD("filter", "raw", "now"),
			&IvoryTouch::filter);
	ClassDB::bind_method(D_METHOD("velocity"), &IvoryTouch::velocity);
	ClassDB::bind_method(D_METHOD("started"), &IvoryTouch::started);
	ClassDB::bind_method(D_METHOD("metrics"), &IvoryTouch::metrics);
	ClassDB::bind_method(D_METHOD("sample_pressure", "pressure"), &IvoryTouch::sample_pressure);
	ClassDB::bind_method(D_METHOD("reset_metrics"), &IvoryTouch::reset_metrics);
	ClassDB::bind_method(D_METHOD("stable"), &IvoryTouch::stable);
}

IvoryTouch::IvoryTouch() {}
IvoryTouch::~IvoryTouch() {}

void IvoryTouch::configure(double min_cutoff, double beta,
		double speed_cutoff, double lead_ms, double deadband_px) {
	min_cutoff_ = std::max(min_cutoff, 0.01);
	beta_ = std::max(beta, 0.0);
	speed_cutoff_ = std::max(speed_cutoff, 0.01);
	// Prediction buys responsiveness with overshoot, and the trade turns bad
	// quickly. Capped well below where a direction change starts to swing.
		lead_ = std::min(std::max(lead_ms, 0.0), 40.0) * 0.001;
	set_deadband(deadband_px);
}

void IvoryTouch::set_deadband(double pixels) {
	deadband_ = std::min(std::max(pixels, 0.0), 8.0);
}

void IvoryTouch::reset() {
	have_ = false;
	speed_ = Vector2();
	reset_metrics();
}

bool IvoryTouch::started() const {
	return have_;
}

Vector2 IvoryTouch::velocity() const {
	return speed_;
}

// The smoothing factor of a one-pole low pass at this cutoff and this
// interval. Derived rather than tuned: the time constant of a filter with
// cutoff `f` is `1 / (2 pi f)`, and the factor that reaches it in `dt` is
// `dt / (tau + dt)`.
double IvoryTouch::alpha_for(double cutoff, double dt) {
	const double tau = 1.0 / (6.283185307179586 * cutoff);
	return dt / (tau + dt);
}

Vector2 IvoryTouch::filter(const Vector2 &raw, double now) {
	if (!have_) {
		have_ = true;
		last_time_ = now;
		value_ = raw;
		raw_last_ = raw;
		speed_ = Vector2();
		return raw;
	}
	double dt = now - last_time_;
	// A frame that took no time reports an infinite speed, and one that took a
	// second is a dropped finger rather than a slow one. Both are clamped to
	// the band a touch screen actually reports in.
	if (dt < 0.001) {
		dt = 0.001;
	} else if (dt > 0.2) {
		dt = 0.2;
	}
	last_time_ = now;

	// The derivative, filtered at its own fixed cutoff — the derivative of a
	// noisy signal is noisier than the signal, and an unfiltered speed would
	// open the position filter wide on nothing but jitter.
		// Reject micro-motion before differentiating it. Otherwise a still finger
		// creates a large false velocity and the one-euro filter opens precisely
		// when it should be quiet. The raw sample is still accepted immediately
		// once it leaves the quiet zone, so deliberate movement stays responsive.
		Vector2 sample = raw;
		if (deadband_ > 0.0 && raw.distance_to(value_) <= (real_t)deadband_) {
			sample = value_;
			++deadband_hits_;
		}
		const Vector2 raw_delta = sample - raw_last_;
	const Vector2 raw_speed = raw_delta / (real_t)dt;
		raw_last_ = sample;
	const double jitter = (double)raw_delta.length();
	jitter_sq_sum_ += jitter * jitter;
	max_speed_ = std::max(max_speed_, (double)raw_speed.length());
	++sample_count_;
	const double da = alpha_for(speed_cutoff_, dt);
	speed_ += (raw_speed - speed_) * (real_t)da;

	// The whole of the one-euro idea: open the filter as the hand moves.
	const double pace = std::sqrt((double)speed_.length_squared());
	const double cutoff = min_cutoff_ + beta_ * pace;
	const double a = alpha_for(cutoff, dt);
	value_ += (sample - value_) * (real_t)a;

	if (lead_ <= 0.0) {
		return value_;
	}
	return value_ + speed_ * (real_t)lead_;
}

Dictionary IvoryTouch::metrics() const {
	Dictionary d;
	const double rms = sample_count_ > 0 ? std::sqrt(jitter_sq_sum_ / (double)sample_count_) : 0.0;
	d["samples"] = sample_count_;
	d["jitter_rms_px"] = rms;
	d["max_speed_px_s"] = max_speed_;
	d["deadband_hits"] = deadband_hits_;
	d["pressure"] = pressure_;
	d["stable"] = stable();
	return d;
}

void IvoryTouch::sample_pressure(double pressure) {
	if (std::isfinite(pressure)) pressure_ = std::clamp(pressure, 0.0, 1.0);
}

void IvoryTouch::reset_metrics() {
	jitter_sq_sum_ = 0.0;
	max_speed_ = 0.0;
	pressure_ = 1.0;
	sample_count_ = 0;
	deadband_hits_ = 0;
}

bool IvoryTouch::stable() const {
	if (sample_count_ < 2) return true;
	const double rms = std::sqrt(jitter_sq_sum_ / (double)sample_count_);
	return std::isfinite(rms) && rms <= std::max(0.25, deadband_ * 1.5);
}
