#include "ivory_field.h"

#include <algorithm>
#include <cmath>

using namespace godot;

void IvoryField::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_tile", "px"), &IvoryField::set_tile);
	ClassDB::bind_method(D_METHOD("tile"), &IvoryField::tile);
	ClassDB::bind_method(D_METHOD("tile_of", "canvas"), &IvoryField::tile_of);
	ClassDB::bind_method(D_METHOD("tile_rect", "at"), &IvoryField::tile_rect);
	ClassDB::bind_method(D_METHOD("tiles_in", "canvas_rect", "cap"),
			&IvoryField::tiles_in);
	ClassDB::bind_method(D_METHOD("set_view", "pan", "zoom", "screen_size"),
			&IvoryField::set_view);
	ClassDB::bind_method(D_METHOD("pan"), &IvoryField::pan);
	ClassDB::bind_method(D_METHOD("zoom"), &IvoryField::zoom);
	ClassDB::bind_method(D_METHOD("to_canvas", "screen"),
			&IvoryField::to_canvas);
	ClassDB::bind_method(D_METHOD("to_screen", "canvas"),
			&IvoryField::to_screen);
	ClassDB::bind_method(D_METHOD("visible"), &IvoryField::visible);
	ClassDB::bind_method(D_METHOD("anchor", "canvas"), &IvoryField::anchor);
	ClassDB::bind_method(D_METHOD("set_anchor_grid", "px"),
			&IvoryField::set_anchor_grid);
	ClassDB::bind_method(D_METHOD("anchor_grid"), &IvoryField::anchor_grid);
	ClassDB::bind_method(D_METHOD("note", "canvas_rect"), &IvoryField::note);
	ClassDB::bind_method(D_METHOD("note_point", "canvas"),
			&IvoryField::note_point);
	ClassDB::bind_method(D_METHOD("anything_drawn"),
			&IvoryField::anything_drawn);
	ClassDB::bind_method(D_METHOD("content"), &IvoryField::content);
	ClassDB::bind_method(D_METHOD("forget_content"),
			&IvoryField::forget_content);
	ClassDB::bind_method(D_METHOD("touch_tile", "at", "now"),
			&IvoryField::touch_tile);
	ClassDB::bind_method(D_METHOD("live_tiles"), &IvoryField::live_tiles);
	ClassDB::bind_method(D_METHOD("evictions", "budget", "ring"),
			&IvoryField::evictions);
	ClassDB::bind_method(D_METHOD("drop_tile", "at"), &IvoryField::drop_tile);
	ClassDB::bind_method(D_METHOD("working_bytes"), &IvoryField::working_bytes);
	ClassDB::bind_method(D_METHOD("report"), &IvoryField::report);
}

IvoryField::IvoryField() {}

int64_t IvoryField::key_of(int64_t x, int64_t y) {
	// Two 32-bit halves in one 64-bit key. The lattice is therefore a little
	// over four thousand million tiles across, which at 256 pixels a tile is
	// a canvas a million million pixels wide — past any drawing, and honest
	// about where the real limit is rather than claiming there is none.
	const uint64_t ux = (uint64_t)(uint32_t)(int32_t)x;
	const uint64_t uy = (uint64_t)(uint32_t)(int32_t)y;
	return (int64_t)((ux << 32) | uy);
}

Vector2i IvoryField::from_key(int64_t key) {
	const uint64_t u = (uint64_t)key;
	return Vector2i((int)(int32_t)(uint32_t)(u >> 32),
			(int)(int32_t)(uint32_t)(u & 0xFFFFFFFFULL));
}

void IvoryField::set_tile(int px) {
	tile_ = std::max(px, 8);
}

Vector2i IvoryField::tile_of(const Vector2 &canvas) const {
	// Floor, not truncation. Truncation folds -0.5 and +0.5 into the same
	// tile and puts a seam through the origin that nothing else has.
	return Vector2i((int)std::floor((double)canvas.x / (double)tile_),
			(int)std::floor((double)canvas.y / (double)tile_));
}

Rect2 IvoryField::tile_rect(const Vector2i &at) const {
	return Rect2((real_t)((double)at.x * tile_), (real_t)((double)at.y * tile_),
			(real_t)tile_, (real_t)tile_);
}

Dictionary IvoryField::tiles_in(const Rect2 &canvas_rect, int cap) const {
	Dictionary out;
	PackedVector2Array list;
	const int limit = cap > 0 ? cap : 4096;

	const double t = (double)tile_;
	const int64_t x0 = (int64_t)std::floor((double)canvas_rect.position.x / t);
	const int64_t y0 = (int64_t)std::floor((double)canvas_rect.position.y / t);
	const int64_t x1 = (int64_t)std::floor((double)canvas_rect.end().x / t);
	const int64_t y1 = (int64_t)std::floor((double)canvas_rect.end().y / t);

	const int64_t across = x1 - x0 + 1;
	const int64_t down = y1 - y0 + 1;
	const int64_t want = across * down;

	bool truncated = false;
	for (int64_t y = y0; y <= y1 && !truncated; ++y) {
		for (int64_t x = x0; x <= x1; ++x) {
			if (list.size() >= limit) {
				truncated = true;
				break;
			}
			list.append(Vector2((real_t)x, (real_t)y));
		}
	}

	out["tiles"] = list;
	out["wanted"] = (int64_t)want;
	out["truncated"] = truncated;
	return out;
}

// ------------------------------------------------------------------ the view

void IvoryField::set_view(const Vector2 &pan, double zoom,
		const Vector2 &screen_size) {
	pan_x_ = pan.x;
	pan_y_ = pan.y;
	// A zoom of nought would divide by nought on the way back, and a
	// negative one would mirror the drawing. Neither is a view anybody
	// asked for.
	zoom_ = std::max(zoom, 1e-6);
	screen_w_ = std::max((double)screen_size.x, 0.0);
	screen_h_ = std::max((double)screen_size.y, 0.0);
}

Vector2 IvoryField::to_canvas(const Vector2 &screen) const {
	// In double. Far from the origin this is a small number made by
	// subtracting two large ones, and in single precision that is where the
	// digits go.
	const double x = ((double)screen.x - pan_x_) / zoom_;
	const double y = ((double)screen.y - pan_y_) / zoom_;
	return Vector2((real_t)x, (real_t)y);
}

Vector2 IvoryField::to_screen(const Vector2 &canvas) const {
	const double x = (double)canvas.x * zoom_ + pan_x_;
	const double y = (double)canvas.y * zoom_ + pan_y_;
	return Vector2((real_t)x, (real_t)y);
}

Rect2 IvoryField::visible() const {
	const Vector2 a = to_canvas(Vector2(0, 0));
	const Vector2 b = to_canvas(Vector2((real_t)screen_w_, (real_t)screen_h_));
	return Rect2(a, b - a);
}

void IvoryField::set_anchor_grid(double px) {
	anchor_grid_ = std::max(px, 0.001);
}

Vector2 IvoryField::anchor(const Vector2 &canvas) const {
	const double g = anchor_grid_;
	return Vector2((real_t)(std::floor((double)canvas.x / g) * g),
			(real_t)(std::floor((double)canvas.y / g) * g));
}

// --------------------------------------------------------- what is drawn on

void IvoryField::note(const Rect2 &canvas_rect) {
	const double ax = canvas_rect.position.x;
	const double ay = canvas_rect.position.y;
	const double bx = ax + canvas_rect.size.x;
	const double by = ay + canvas_rect.size.y;
	if (!drawn_) {
		x0_ = std::min(ax, bx);
		y0_ = std::min(ay, by);
		x1_ = std::max(ax, bx);
		y1_ = std::max(ay, by);
		drawn_ = true;
		return;
	}
	x0_ = std::min(x0_, std::min(ax, bx));
	y0_ = std::min(y0_, std::min(ay, by));
	x1_ = std::max(x1_, std::max(ax, bx));
	y1_ = std::max(y1_, std::max(ay, by));
}

void IvoryField::note_point(const Vector2 &canvas) {
	note(Rect2(canvas, Vector2(0, 0)));
}

Rect2 IvoryField::content() const {
	if (!drawn_) {
		return Rect2();
	}
	return Rect2((real_t)x0_, (real_t)y0_, (real_t)(x1_ - x0_),
			(real_t)(y1_ - y0_));
}

void IvoryField::forget_content() {
	drawn_ = false;
	x0_ = y0_ = x1_ = y1_ = 0.0;
}

// ------------------------------------------------------------------- tiles

void IvoryField::touch_tile(const Vector2i &at, double now) {
	seen_[key_of(at.x, at.y)] = now;
}

void IvoryField::drop_tile(const Vector2i &at) {
	seen_.erase(key_of(at.x, at.y));
}

PackedVector2Array IvoryField::evictions(int budget, int ring) const {
	PackedVector2Array out;
	const int keep = std::max(budget, 0);
	if ((int)seen_.size() <= keep) {
		return out;
	}

	// What is on screen, plus a ring of tiles around it. Never evicted,
	// whatever the budget says. Without the ring, every small pan discards
	// tiles that are wanted again a frame later and the drawing flickers as
	// they are rebuilt.
	const Rect2 view = visible();
	const int pad = std::max(ring, 0);
	const double t = (double)tile_;
	const int64_t vx0 = (int64_t)std::floor((double)view.position.x / t) - pad;
	const int64_t vy0 = (int64_t)std::floor((double)view.position.y / t) - pad;
	const int64_t vx1 = (int64_t)std::floor((double)view.end().x / t) + pad;
	const int64_t vy1 = (int64_t)std::floor((double)view.end().y / t) + pad;

	std::vector<std::pair<double, int64_t>> candidates;
	candidates.reserve(seen_.size());
	for (const auto &kv : seen_) {
		const Vector2i at = from_key(kv.first);
		const bool near_view = at.x >= vx0 && at.x <= vx1 && at.y >= vy0 &&
				at.y <= vy1;
		if (near_view) {
			continue;
		}
		candidates.push_back({ kv.second, kv.first });
	}

	// Oldest first.
	std::sort(candidates.begin(), candidates.end());
	const int over = (int)seen_.size() - keep;
	for (int i = 0; i < over && i < (int)candidates.size(); ++i) {
		const Vector2i at = from_key(candidates[(size_t)i].second);
		out.append(Vector2((real_t)at.x, (real_t)at.y));
	}
	return out;
}

int64_t IvoryField::working_bytes() const {
	return (int64_t)seen_.size() * (int64_t)tile_ * (int64_t)tile_ * 4;
}

Dictionary IvoryField::report() const {
	Dictionary out;
	out["tile"] = tile_;
	out["zoom"] = zoom_;
	out["visible"] = visible();
	out["drawn"] = drawn_;
	out["content"] = content();
	out["live_tiles"] = live_tiles();
	out["working_bytes"] = working_bytes();
	// How far the addressing reaches, so that "infinite" is a number
	// somebody can look at rather than a claim.
	out["reach"] = (int64_t)((int64_t)tile_ * 2147483647LL);
	return out;
}
