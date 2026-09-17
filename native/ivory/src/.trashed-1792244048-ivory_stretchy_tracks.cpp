#include "ivory_stretchy_tracks.h"

#include <algorithm>

namespace ivory {

void PerformanceTrack::clear() noexcept {
	samples_.clear();
	dropped_frames_ = 0;
}

void PerformanceTrack::reserve(std::size_t count) {
	samples_.reserve(count);
}

void PerformanceTrack::sample(const PerformanceSample &value) {
	if (value.frame < 0 || value.render_ms < 0.0 || value.audio_ms < 0.0 ||
			value.submit_ms < 0.0 || value.total_ms < 0.0) {
		return;
	}
	samples_.push_back(value);
}

double PerformanceTrack::average_total_ms() const noexcept {
	if (samples_.empty()) return 0.0;
	double sum = 0.0;
	for (const PerformanceSample &s : samples_) sum += s.total_ms;
	return sum / static_cast<double>(samples_.size());
}

double PerformanceTrack::peak_total_ms() const noexcept {
	double peak = 0.0;
	for (const PerformanceSample &s : samples_) peak = std::max(peak, s.total_ms);
	return peak;
}

} // namespace ivory
