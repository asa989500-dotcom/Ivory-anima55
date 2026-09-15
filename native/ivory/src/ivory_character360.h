#ifndef IVORY_CHARACTER360_H
#define IVORY_CHARACTER360_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

// Character 360 is deliberately a two-view reconstruction, not another
// freehand point editor. Front supplies x/y and side supplies the
// physically plausible z extent at each y. The two are reconciled into one
// normalized character frame, then smoothed and clamped before posing.
class IvoryCharacter360 : public RefCounted {
	GDCLASS(IvoryCharacter360, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryCharacter360() = default;
	~IvoryCharacter360() = default;

	void set_front(const PackedByteArray &rgba, int width, int height);
	void set_side(const PackedByteArray &rgba, int width, int height);
	bool ready() const;

	// Build the common character frame. iterations controls only smoothing;
	// the reconstruction itself is deterministic and does not invent pixels.
	Dictionary build(int target_width = 256, int target_height = 256,
			int smoothing_iterations = 5);
	void cancel();
	bool built() const { return built_; }
	float progress() const { return progress_; }

	// The reconstructed depth, row-major, normalized to [0,1].
	PackedFloat32Array depth_map() const;
	PackedFloat32Array front_alpha() const;
	PackedFloat32Array side_profile() const;

	// Project a point from character-local space. The input is normalized
	// to [0,1] in x/y. Output remains normalized, so the same model can live
	// on any canvas size.
	Vector2 project(const Vector2 &normalized_xy, double yaw,
			double pitch = 0.0, double roll = 0.0) const;
	PackedVector2Array project_many(const PackedVector2Array &points,
		double yaw, double pitch = 0.0, double roll = 0.0) const;

	// Stronger than the old depth study, but still bounded. 2 means twice the
	// measured relief, not arbitrary extrusion.
	void set_depth_strength(double strength);
	double depth_strength() const { return depth_strength_; }

	// Build-time diagnostics used by tests and by the UI's final report.
	Dictionary diagnostics() const;
	Dictionary export_state() const;
	PackedByteArray render_view(double yaw, double pitch = 0.0, double roll = 0.0, int width = 512, int height = 512) const;

private:
	PackedByteArray front_;
	PackedByteArray side_;
	int fw_ = 0, fh_ = 0, sw_ = 0, sh_ = 0;
	int w_ = 0, h_ = 0;
	std::vector<float> depth_;
	std::vector<float> alpha_;
	std::vector<float> side_profile_;
	bool built_ = false;
	bool cancelled_ = false;
	float progress_ = 0.0f;
	double depth_strength_ = 1.6;
	double symmetry_score_ = 0.0;
	double silhouette_overlap_ = 0.0;
	double distortion_score_ = 0.0;

	static float alpha_at(const PackedByteArray &img, int width, int height,
			int x, int y);
	static float smoothstep(float a, float b, float x);
	float sample_depth_bilinear(float x, float y) const;
};

} // namespace godot

#endif
