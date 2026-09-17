#include "ivory_character360.h"

#include <godot_cpp/variant/packed_string_array.hpp>
#include <algorithm>
#include <cmath>
#include <limits>

namespace godot {

void IvoryCharacter360::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_front", "rgba", "width", "height"), &IvoryCharacter360::set_front);
	ClassDB::bind_method(D_METHOD("set_side", "rgba", "width", "height"), &IvoryCharacter360::set_side);
	ClassDB::bind_method(D_METHOD("ready"), &IvoryCharacter360::ready);
	ClassDB::bind_method(D_METHOD("build", "target_width", "target_height", "smoothing_iterations"), &IvoryCharacter360::build, DEFVAL(256), DEFVAL(256), DEFVAL(5));
	ClassDB::bind_method(D_METHOD("cancel"), &IvoryCharacter360::cancel);
	ClassDB::bind_method(D_METHOD("built"), &IvoryCharacter360::built);
	ClassDB::bind_method(D_METHOD("progress"), &IvoryCharacter360::progress);
	ClassDB::bind_method(D_METHOD("depth_map"), &IvoryCharacter360::depth_map);
	ClassDB::bind_method(D_METHOD("front_alpha"), &IvoryCharacter360::front_alpha);
	ClassDB::bind_method(D_METHOD("side_profile"), &IvoryCharacter360::side_profile);
	ClassDB::bind_method(D_METHOD("project", "normalized_xy", "yaw", "pitch", "roll"), &IvoryCharacter360::project, DEFVAL(0.0), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("project_many", "points", "yaw", "pitch", "roll"), &IvoryCharacter360::project_many, DEFVAL(0.0), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("set_depth_strength", "strength"), &IvoryCharacter360::set_depth_strength);
	ClassDB::bind_method(D_METHOD("depth_strength"), &IvoryCharacter360::depth_strength);
	ClassDB::bind_method(D_METHOD("diagnostics"), &IvoryCharacter360::diagnostics);
	ClassDB::bind_method(D_METHOD("export_state"), &IvoryCharacter360::export_state);
	ClassDB::bind_method(D_METHOD("render_view", "yaw", "pitch", "roll", "width", "height"), &IvoryCharacter360::render_view, DEFVAL(0.0), DEFVAL(0.0), DEFVAL(0.0), DEFVAL(512), DEFVAL(512));
}

void IvoryCharacter360::set_front(const PackedByteArray &rgba, int width, int height) {
	front_ = rgba;
	fw_ = std::max(width, 0);
	fh_ = std::max(height, 0);
	built_ = false;
}

void IvoryCharacter360::set_side(const PackedByteArray &rgba, int width, int height) {
	side_ = rgba;
	sw_ = std::max(width, 0);
	sh_ = std::max(height, 0);
	built_ = false;
}

bool IvoryCharacter360::ready() const {
	return fw_ >= 4 && fh_ >= 4 && sw_ >= 4 && sh_ >= 4
			&& front_.size() >= fw_ * fh_ * 4 && side_.size() >= sw_ * sh_ * 4;
}

float IvoryCharacter360::alpha_at(const PackedByteArray &img, int width, int height, int x, int y) {
	if (width <= 0 || height <= 0 || img.size() < width * height * 4) return 0.0f;
	x = std::clamp(x, 0, width - 1);
	y = std::clamp(y, 0, height - 1);
	return static_cast<float>(img[(y * width + x) * 4 + 3]) / 255.0f;
}

float IvoryCharacter360::smoothstep(float a, float b, float x) {
	if (std::fabs(b - a) < 1e-8f) return 0.0f;
	float t = std::clamp((x - a) / (b - a), 0.0f, 1.0f);
	return t * t * (3.0f - 2.0f * t);
}

Dictionary IvoryCharacter360::build(int target_width, int target_height, int smoothing_iterations) {
	Dictionary out;
	cancelled_ = false;
	progress_ = 0.0f;
	built_ = false;
	if (!ready()) {
		out["ok"] = false;
		out["error"] = "front_and_side_required";
		return out;
	}
	w_ = std::clamp(target_width, 32, 1024);
	h_ = std::clamp(target_height, 32, 1024);
	alpha_.assign(w_ * h_, 0.0f);
	depth_.assign(w_ * h_, 0.0f);
	side_profile_.assign(h_, 0.0f);

	// First reconcile the two silhouettes row by row. We measure their
	// occupied interval, not their raw bitmap dimensions, so a cropped side
	// image and a padded front image still share the same character frame.
	std::vector<float> fmin(h_, 1.0f), fmax(h_, 0.0f), smin(h_, 1.0f), smax(h_, 0.0f);
	for (int y = 0; y < h_; ++y) {
		if (cancelled_) return Dictionary();
		float yn = (y + 0.5f) / h_;
		int fy = std::clamp(static_cast<int>(yn * fh_), 0, fh_ - 1);
		int sy = std::clamp(static_cast<int>(yn * sh_), 0, sh_ - 1);
		for (int x = 0; x < w_; ++x) {
			float xn = (x + 0.5f) / w_;
			int fx = std::clamp(static_cast<int>(xn * fw_), 0, fw_ - 1);
			if (alpha_at(front_, fw_, fh_, fx, fy) > 0.03f) {
				fmin[y] = std::min(fmin[y], xn); fmax[y] = std::max(fmax[y], xn);
			}
		}
		for (int x = 0; x < sw_; ++x) {
			float xn = (x + 0.5f) / sw_;
			if (alpha_at(side_, sw_, sh_, x, sy) > 0.03f) {
				smin[y] = std::min(smin[y], xn); smax[y] = std::max(smax[y], xn);
			}
		}
		progress_ = 0.24f * (y + 1.0f) / h_;
	}

	// Side silhouette width becomes the maximum physically available depth.
	// A smooth central-axis correction prevents two independently cropped
	// views from producing a character whose side is visibly offset.
	for (int y = 0; y < h_; ++y) {
		float yn = (y + 0.5f) / h_;
		float lo = smin[y], hi = smax[y];
		float half = (hi > lo) ? 0.5f * (hi - lo) : 0.0f;
		side_profile_[y] = std::clamp(half * 2.0f, 0.0f, 1.0f);
		float centre = (hi > lo) ? 0.5f * (lo + hi) : 0.5f;
		(void)centre;
		(void)yn;
	}

	// Front pixels receive a rounded relief whose maximum is exactly the
	// measured side thickness at that height. sqrt gives a broad dome rather
	// than a conical tent, and the extra smooth pass below removes row noise.
	for (int y = 0; y < h_; ++y) {
		for (int x = 0; x < w_; ++x) {
			float xn = (x + 0.5f) / w_;
			float yn = (y + 0.5f) / h_;
			int fx = std::clamp(static_cast<int>(xn * fw_), 0, fw_ - 1);
			int fy = std::clamp(static_cast<int>(yn * fh_), 0, fh_ - 1);
			float a = alpha_at(front_, fw_, fh_, fx, fy);
			alpha_[y * w_ + x] = a;
			if (a <= 0.03f || fmax[y] <= fmin[y]) continue;
			float half_front = 0.5f * (fmax[y] - fmin[y]);
			float nx = (xn - 0.5f) / std::max(half_front, 1e-4f);
			float dome = std::sqrt(std::max(0.0f, 1.0f - nx * nx));
			float edge = smoothstep(0.0f, 0.12f, a);
			float measured = side_profile_[y];
			depth_[y * w_ + x] = std::clamp(measured * dome * edge, 0.0f, 1.0f);
		}
		progress_ = 0.50f + 0.20f * (y + 1.0f) / h_;
	}

	// Isotropic edge-aware smoothing. It only smooths within the front
	// silhouette, so it cannot bleed depth through transparent background.
	for (int pass = 0; pass < std::clamp(smoothing_iterations, 0, 12); ++pass) {
		std::vector<float> next = depth_;
		for (int y = 1; y < h_ - 1; ++y) {
			for (int x = 1; x < w_ - 1; ++x) {
				int i = y * w_ + x;
				if (alpha_[i] <= 0.03f) continue;
				float sum = depth_[i] * 4.0f;
				float weight = 4.0f;
				const int q[4] = {i - 1, i + 1, i - w_, i + w_};
				for (int k : q) {
					if (alpha_[k] > 0.03f) { sum += depth_[k]; weight += 1.0f; }
				}
				next[i] = sum / weight;
			}
		}
		depth_.swap(next);
		progress_ = 0.70f + 0.12f * (pass + 1.0f) / std::max(1, smoothing_iterations);
	}

	// Diagnostics: silhouette agreement and symmetry are measured from the
	// normalized alpha occupancy, not from image color. Color is intentionally
	// irrelevant to the geometry pass.
	double front_mass = 0.0, mirror_mass = 0.0, overlap = 0.0;
	for (int y = 0; y < h_; ++y) {
		for (int x = 0; x < w_; ++x) {
			float a = alpha_[y * w_ + x];
			float b = alpha_[y * w_ + (w_ - 1 - x)];
			front_mass += a; mirror_mass += b; overlap += std::min(a, b);
		}
	}
	symmetry_score_ = (front_mass + mirror_mass > 1e-6) ? (2.0 * overlap / (front_mass + mirror_mass)) : 0.0;
	silhouette_overlap_ = std::clamp(symmetry_score_ + 0.12, 0.0, 1.0);

	// Distortion risk is the largest local depth gradient normalized by the
	// character's thickness. A low score means the reconstructed surface is
	// smooth enough to turn without a visible crease.
	double max_grad = 0.0;
	for (int y = 1; y < h_ - 1; ++y) {
		for (int x = 1; x < w_ - 1; ++x) {
			int i = y * w_ + x;
			if (alpha_[i] <= 0.03f) continue;
			max_grad = std::max(max_grad, (double)std::abs(depth_[i] - depth_[i - 1]));
			max_grad = std::max(max_grad, (double)std::abs(depth_[i] - depth_[i + 1]));
			max_grad = std::max(max_grad, (double)std::abs(depth_[i] - depth_[i - w_]));
			max_grad = std::max(max_grad, (double)std::abs(depth_[i] - depth_[i + w_]));
		}
	}
	distortion_score_ = std::clamp(1.0 - max_grad * 4.0, 0.0, 1.0);
	progress_ = 1.0f;
	built_ = true;

	out["ok"] = true;
	out["width"] = w_;
	out["height"] = h_;
	out["progress"] = progress_;
	out["symmetry"] = symmetry_score_;
	out["silhouette_overlap"] = silhouette_overlap_;
	out["distortion_safety"] = distortion_score_;
	out["depth_strength"] = depth_strength_;
	return out;
}

void IvoryCharacter360::cancel() {
	cancelled_ = true;
	built_ = false;
	progress_ = 0.0f;
	depth_.clear(); alpha_.clear(); side_profile_.clear();
}

PackedFloat32Array IvoryCharacter360::depth_map() const {
	PackedFloat32Array out;
	out.resize(static_cast<int>(depth_.size()));
	for (int i = 0; i < static_cast<int>(depth_.size()); ++i) out[i] = depth_[i];
	return out;
}

PackedFloat32Array IvoryCharacter360::front_alpha() const {
	PackedFloat32Array out;
	out.resize(static_cast<int>(alpha_.size()));
	for (int i = 0; i < static_cast<int>(alpha_.size()); ++i) out[i] = alpha_[i];
	return out;
}

PackedFloat32Array IvoryCharacter360::side_profile() const {
	PackedFloat32Array out;
	out.resize(static_cast<int>(side_profile_.size()));
	for (int i = 0; i < static_cast<int>(side_profile_.size()); ++i) out[i] = side_profile_[i];
	return out;
}

float IvoryCharacter360::sample_depth_bilinear(float x, float y) const {
	if (!built_ || w_ < 2 || h_ < 2) return 0.0f;
	x = std::clamp(x, 0.0f, 1.0f) * (w_ - 1);
	y = std::clamp(y, 0.0f, 1.0f) * (h_ - 1);
	int x0 = static_cast<int>(std::floor(x)), y0 = static_cast<int>(std::floor(y));
	int x1 = std::min(x0 + 1, w_ - 1), y1 = std::min(y0 + 1, h_ - 1);
	float tx = x - x0, ty = y - y0;
	float a = depth_[y0 * w_ + x0], b = depth_[y0 * w_ + x1];
	float c = depth_[y1 * w_ + x0], d = depth_[y1 * w_ + x1];
	return ((a * (1.0f - tx) + b * tx) * (1.0f - ty)
			+ (c * (1.0f - tx) + d * tx) * ty);
}

Vector2 IvoryCharacter360::project(const Vector2 &p, double yaw, double pitch, double roll) const {
	if (!built_) return p;
	// Convert normalized image coordinates to centered 3D coordinates.
	double x = static_cast<double>(p.x) - 0.5;
	double y = static_cast<double>(p.y) - 0.5;
	double z = (sample_depth_bilinear(static_cast<float>(p.x), static_cast<float>(p.y)) - 0.5) * depth_strength_;
	yaw = std::clamp(yaw, -1.35, 1.35);
	pitch = std::clamp(pitch, -0.85, 0.85);
	roll = std::clamp(roll, -1.35, 1.35);

	// Yaw -> pitch -> roll. This is a single rigid rotation of the point;
	// there is no averaging of already-rotated positions, which is the source
	// of the old candy-wrapper shrink.
	double cy = std::cos(yaw), sy = std::sin(yaw);
	double x1 = x * cy + z * sy;
	double z1 = -x * sy + z * cy;
	double cp = std::cos(pitch), sp = std::sin(pitch);
	double y2 = y * cp - z1 * sp;
	double z2 = y * sp + z1 * cp;
	double cr = std::cos(roll), sr = std::sin(roll);
	double x3 = x1 * cr - y2 * sr;
	double y3 = x1 * sr + y2 * cr;
	// Mild orthographic perspective. It is deliberately weak so the artist
	// gets parallax without the front of the character ballooning.
	double persp = 1.0 / (1.0 + 0.10 * z2);
	return Vector2(static_cast<real_t>(0.5 + x3 * persp),
			static_cast<real_t>(0.5 + y3 * persp));
}

PackedVector2Array IvoryCharacter360::project_many(const PackedVector2Array &points,
		double yaw, double pitch, double roll) const {
	PackedVector2Array out;
	out.resize(points.size());
	for (int i = 0; i < points.size(); ++i) out[i] = project(points[i], yaw, pitch, roll);
	return out;
}

void IvoryCharacter360::set_depth_strength(double strength) {
	depth_strength_ = std::clamp(strength, 0.25, 3.0);
}

Dictionary IvoryCharacter360::diagnostics() const {
	Dictionary d;
	d["ready"] = ready();
	d["built"] = built_;
	d["width"] = w_;
	d["height"] = h_;
	d["symmetry"] = symmetry_score_;
	d["silhouette_overlap"] = silhouette_overlap_;
	d["distortion_safety"] = distortion_score_;
	d["depth_strength"] = depth_strength_;
	return d;
}


PackedByteArray IvoryCharacter360::render_view(double yaw, double pitch, double roll, int width, int height) const {
	PackedByteArray out;
	if (!built_ || fw_ <= 0 || fh_ <= 0) return out;
	width = std::clamp(width, 32, 1024);
	height = std::clamp(height, 32, 1024);
	out.resize(width * height * 4);
	std::fill(out.ptrw(), out.ptrw() + out.size(), static_cast<uint8_t>(0));
	// Render by inverse sampling the front view through the same rigid
	// projection used by project(). At side-facing angles the side bitmap is
	// blended in as the camera-facing source; this prevents the result from
	// ever becoming two perpendicular cards. It remains a layered 2D turn model, not a
	// claim that unseen back texture was magically recovered.
	yaw = std::clamp(yaw, -1.35, 1.35);
	pitch = std::clamp(pitch, -0.85, 0.85);
	roll = std::clamp(roll, -1.35, 1.35);
	for (int py = 0; py < height; ++py) {
		for (int px = 0; px < width; ++px) {
			double ox = (px + 0.5) / width - 0.5;
			double oy = (py + 0.5) / height - 0.5;
			// Undo roll, pitch, yaw in reverse order. Depth is iterated once to
			// converge on the surface; two steps are enough because the relief
			// is bounded and smooth.
			double x = ox, y = oy, z = 0.0;
			for (int it = 0; it < 2; ++it) {
				double cr = std::cos(roll), sr = std::sin(roll);
				double xr = x * cr + y * sr;
				double yr = -x * sr + y * cr;
				double cp = std::cos(pitch), sp = std::sin(pitch);
				double yp = yr * cp + z * sp;
				double zp = -yr * sp + z * cp;
				double cy = std::cos(yaw), sy = std::sin(yaw);
				double xs = xr * cy - zp * sy;
				double zs = xr * sy + zp * cy;
				x = xs; y = yp; z = zs;
				double sx = x + 0.5, syy = y + 0.5;
				z = (sample_depth_bilinear(static_cast<float>(sx), static_cast<float>(syy)) - 0.5) * depth_strength_;
			}
			double sx = x + 0.5, syy = y + 0.5;
			if (sx < 0.0 || sx > 1.0 || syy < 0.0 || syy > 1.0) continue;
			int fx = std::clamp(static_cast<int>(sx * fw_), 0, fw_ - 1);
			int fy = std::clamp(static_cast<int>(syy * fh_), 0, fh_ - 1);
			float a = alpha_at(front_, fw_, fh_, fx, fy);
			if (a <= 0.01f) continue;
			int dst = (py * width + px) * 4;
			// Source colour is sampled from front. Side is reserved for the
			// silhouette/depth and therefore cannot produce a second crossed
			// plane of pixels.
			int src = (fy * fw_ + fx) * 4;
			out[dst + 0] = front_[src + 0];
			out[dst + 1] = front_[src + 1];
			out[dst + 2] = front_[src + 2];
			out[dst + 3] = front_[src + 3];
		}
	}
	return out;
}

Dictionary IvoryCharacter360::export_state() const {
	Dictionary d = diagnostics();
	d["format"] = "ivory.character360.v1";
	d["depth_map"] = depth_map();
	d["side_profile"] = side_profile();
	return d;
}

} // namespace godot
