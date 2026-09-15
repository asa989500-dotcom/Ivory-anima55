#ifndef IVORY_STRETCHY_TRACKS_H
#define IVORY_STRETCHY_TRACKS_H

#include <cstdint>
#include <string>
#include <vector>

namespace ivory {

struct AudioTrack {
	std::string id;
	std::string source;
	std::int64_t start_us = 0;
	std::int64_t end_us = 0;
	float gain = 1.0f;
	bool enabled = true;
};

struct PerformanceSample {
	std::int64_t frame = 0;
	double render_ms = 0.0;
	double audio_ms = 0.0;
	double submit_ms = 0.0;
	double total_ms = 0.0;
};

class PerformanceTrack final {
	std::vector<PerformanceSample> samples_;
	std::uint64_t dropped_frames_ = 0;
public:
	void clear() noexcept;
	void reserve(std::size_t count);
	void sample(const PerformanceSample &value);
	void dropped_frame() noexcept { ++dropped_frames_; }
	const std::vector<PerformanceSample> &samples() const noexcept { return samples_; }
	std::uint64_t dropped_frames() const noexcept { return dropped_frames_; }
	double average_total_ms() const noexcept;
	double peak_total_ms() const noexcept;
};

} // namespace ivory

#endif
