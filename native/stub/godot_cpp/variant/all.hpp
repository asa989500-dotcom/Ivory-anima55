#pragma once
#include <initializer_list>
// A small, honest stand-in for the parts of godot-cpp the native half uses.
//
// ## Why this exists at all
//
// The real godot-cpp is a checkout and a toolchain away, and neither is here
// on a machine that has only just cloned the project. Without something to
// compile against, a C++ mistake in `native/ivory/src` is found by whoever
// next runs `scons` — which on this project has historically been nobody for
// several stages at a time, so the mistakes pile up in the dark.
//
// ## What changed at stage 137
//
// It used to be a *syntax* stub: `Dictionary::operator[]` returned a reference
// to one shared static `Variant` that held nothing, so code that filled a
// dictionary compiled and code that read one compiled, and neither did
// anything. That is enough to catch a missing semicolon and nothing else.
//
// So `Variant`, `Dictionary` and `Array` are real here now — a tagged union
// with shared storage for the two container types, matching Godot's reference
// semantics. The point is not fidelity for its own sake. It is that the native
// tests in `native/ivory/tests` now **run**, off-engine, in a second, on any
// machine with a compiler. A geometry claim that is asserted and executed is a
// claim somebody checked; one that is only compiled is a comment with
// punctuation.
//
// It is still a stub and is meant to stay one. Anything here that grows past
// what the tests need belongs in the real library instead.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>
#include <memory>
#include <type_traits>
#include <string>
#include <vector>

#define Math_PI 3.14159265358979323846
#define Math_TAU 6.28318530717958647692

namespace godot {

typedef float real_t;

struct Vector2 {
	real_t x = 0, y = 0;
	Vector2() {}
	Vector2(real_t a, real_t b) : x(a), y(b) {}
	Vector2 operator-(const Vector2 &o) const { return Vector2(x - o.x, y - o.y); }
	Vector2 operator+(const Vector2 &o) const { return Vector2(x + o.x, y + o.y); }
	Vector2 operator*(real_t s) const { return Vector2(x * s, y * s); }
	Vector2 operator/(real_t s) const { return Vector2(x / s, y / s); }
	Vector2 operator-() const { return Vector2(-x, -y); }
	Vector2 &operator+=(const Vector2 &o) { x += o.x; y += o.y; return *this; }
	Vector2 &operator-=(const Vector2 &o) { x -= o.x; y -= o.y; return *this; }
	Vector2 &operator*=(real_t s) { x *= s; y *= s; return *this; }
	Vector2 &operator/=(real_t s) { x /= s; y /= s; return *this; }
	bool operator==(const Vector2 &o) const { return x == o.x && y == o.y; }
	bool operator!=(const Vector2 &o) const { return !(*this == o); }
	double length() const { return std::sqrt((double)x * x + (double)y * y); }
	double length_squared() const { return (double)x * x + (double)y * y; }
	double distance_to(const Vector2 &o) const { return (*this - o).length(); }
	double distance_squared_to(const Vector2 &o) const {
		return (*this - o).length_squared();
	}
	double cross(const Vector2 &o) const { return (double)x * o.y - (double)y * o.x; }
	double dot(const Vector2 &o) const { return (double)x * o.x + (double)y * o.y; }
	double angle() const { return std::atan2((double)y, (double)x); }
	double angle_to(const Vector2 &o) const { return std::atan2(cross(o), dot(o)); }
	Vector2 normalized() const {
		double l = length();
		return l > 0 ? Vector2((real_t)(x / l), (real_t)(y / l)) : Vector2();
	}
	Vector2 orthogonal() const { return Vector2(-y, x); }
	Vector2 rotated(double a) const {
		const double c = std::cos(a), s = std::sin(a);
		return Vector2((real_t)(x * c - y * s), (real_t)(x * s + y * c));
	}
	Vector2 lerp(const Vector2 &o, real_t t) const {
		return Vector2(x + (o.x - x) * t, y + (o.y - y) * t);
	}
	Vector2 floor() const {
		return Vector2((real_t)std::floor(x), (real_t)std::floor(y));
	}
};

inline Vector2 operator*(real_t s, const Vector2 &v) {
	return Vector2(v.x * s, v.y * s);
}

struct Vector2i {
	int x = 0, y = 0;
	Vector2i() {}
	Vector2i(int a, int b) : x(a), y(b) {}
	bool operator==(const Vector2i &o) const { return x == o.x && y == o.y; }
};

struct Rect2 {
	Vector2 position, size;
	Rect2() {}
	Rect2(real_t a, real_t b, real_t c, real_t d) : position(a, b), size(c, d) {}
	Rect2(const Vector2 &p, const Vector2 &s) : position(p), size(s) {}
	Vector2 get_center() const {
		return Vector2(position.x + size.x / 2, position.y + size.y / 2);
	}
	Vector2 end() const { return Vector2(position.x + size.x, position.y + size.y); }
	Vector2 get_end() const { return end(); }
	double get_area() const { return (double)size.x * size.y; }
	Rect2 expand(const Vector2 &p) const {
		Rect2 r = *this;
		real_t x0 = std::min(position.x, p.x), y0 = std::min(position.y, p.y);
		real_t x1 = std::max(position.x + size.x, p.x);
		real_t y1 = std::max(position.y + size.y, p.y);
		r.position = Vector2(x0, y0);
		r.size = Vector2(x1 - x0, y1 - y0);
		return r;
	}
	Rect2 grow(real_t by) const {
		return Rect2(position.x - by, position.y - by,
				size.x + by * 2, size.y + by * 2);
	}
	Rect2 merge(const Rect2 &o) const { return expand(o.position).expand(o.end()); }
	bool intersects(const Rect2 &o) const {
		return position.x < o.position.x + o.size.x &&
				position.x + size.x > o.position.x &&
				position.y < o.position.y + o.size.y &&
				position.y + size.y > o.position.y;
	}
	bool has_point(const Vector2 &p) const {
		return p.x >= position.x && p.y >= position.y &&
				p.x <= position.x + size.x && p.y <= position.y + size.y;
	}
};

struct Rect2i {
	Vector2i position, size;
	Rect2i() {}
	Rect2i(int a, int b, int c, int d) : position(a, b), size(c, d) {}
};

template <class T>
struct Packed {
	std::vector<T> v;
	Packed() {}
	Packed(std::initializer_list<T> init) : v(init) {}
	int size() const { return (int)v.size(); }
	bool is_empty() const { return v.empty(); }
	void clear() { v.clear(); }
	void resize(int n) { v.resize(n); }
	void reverse() { std::reverse(v.begin(), v.end()); }
	void append(const T &t) { v.push_back(t); }
	void push_back(const T &t) { v.push_back(t); }
	void append_array(const Packed<T> &o) {
		v.insert(v.end(), o.v.begin(), o.v.end());
	}
	T &operator[](int i) { return v[i]; }
	const T &operator[](int i) const { return v[i]; }
	void fill(const T &t) { for (auto &e : v) e = t; }
	const T *ptr() const { return v.empty() ? nullptr : v.data(); }
	T *ptrw() { return v.empty() ? nullptr : v.data(); }
	Packed<T> duplicate() const { return *this; }
	Packed<T> slice(int a, int b) const {
		Packed<T> out;
		const int n = (int)v.size();
		a = std::max(0, a);
		b = std::min(n, b);
		for (int i = a; i < b; ++i) out.v.push_back(v[i]);
		return out;
	}
	bool operator==(const Packed<T> &o) const { return v == o.v; }
};

struct CharString {
	std::string s;
	const char *get_data() const { return s.c_str(); }
	int length() const { return (int)s.size(); }
};

// UTF-32 inside, UTF-8 on the way out. Godot's String is a code-point sequence
// and several places index it, so a std::string of bytes would give the wrong
// answer the moment Arabic text arrived.
struct String {
	std::vector<char32_t> u;

	String() {}
	String(const char *c) { assign_utf8(c ? c : ""); }
	String(const std::string &c) { assign_utf8(c); }

	void assign_utf8(const std::string &in) {
		u.clear();
		size_t i = 0;
		while (i < in.size()) {
			const unsigned char c = (unsigned char)in[i];
			char32_t cp = c;
			int extra = 0;
			if (c >= 0xF0) { cp = c & 0x07; extra = 3; }
			else if (c >= 0xE0) { cp = c & 0x0F; extra = 2; }
			else if (c >= 0xC0) { cp = c & 0x1F; extra = 1; }
			++i;
			for (int k = 0; k < extra && i < in.size(); ++k, ++i) {
				cp = (cp << 6) | ((unsigned char)in[i] & 0x3F);
			}
			u.push_back(cp);
		}
	}

	std::string to_utf8() const {
		std::string out;
		for (char32_t c : u) {
			if (c < 0x80) {
				out += (char)c;
			} else if (c < 0x800) {
				out += (char)(0xC0 | (c >> 6));
				out += (char)(0x80 | (c & 0x3F));
			} else if (c < 0x10000) {
				out += (char)(0xE0 | (c >> 12));
				out += (char)(0x80 | ((c >> 6) & 0x3F));
				out += (char)(0x80 | (c & 0x3F));
			} else {
				out += (char)(0xF0 | (c >> 18));
				out += (char)(0x80 | ((c >> 12) & 0x3F));
				out += (char)(0x80 | ((c >> 6) & 0x3F));
				out += (char)(0x80 | (c & 0x3F));
			}
		}
		return out;
	}

	CharString utf8() const {
		CharString c;
		c.s = to_utf8();
		return c;
	}

	int length() const { return (int)u.size(); }
	bool is_empty() const { return u.empty(); }
	char32_t operator[](int i) const { return u[i]; }

	String &operator+=(const String &o) {
		u.insert(u.end(), o.u.begin(), o.u.end());
		return *this;
	}
	String operator+(const String &o) const {
		String r = *this;
		r += o;
		return r;
	}
	bool operator==(const String &o) const { return u == o.u; }
	bool operator!=(const String &o) const { return u != o.u; }
	bool operator<(const String &o) const { return u < o.u; }

	String strip_edges() const {
		int a = 0, b = (int)u.size();
		auto space = [](char32_t c) {
			return c == ' ' || c == '\t' || c == '\n' || c == '\r';
		};
		while (a < b && space(u[a])) ++a;
		while (b > a && space(u[b - 1])) --b;
		String r;
		r.u.assign(u.begin() + a, u.begin() + b);
		return r;
	}
	bool contains(const String &needle) const {
		if (needle.u.empty()) return true;
		if (needle.u.size() > u.size()) return false;
		return std::search(u.begin(), u.end(), needle.u.begin(),
				needle.u.end()) != u.end();
	}
	bool begins_with(const String &p) const {
		if (p.u.size() > u.size()) return false;
		return std::equal(p.u.begin(), p.u.end(), u.begin());
	}
	int find(const String &needle) const {
		auto it = std::search(u.begin(), u.end(), needle.u.begin(),
				needle.u.end());
		return it == u.end() ? -1 : (int)(it - u.begin());
	}
	String substr(int from, int len = -1) const {
		String r;
		const int n = (int)u.size();
		from = std::max(0, std::min(from, n));
		const int end = len < 0 ? n : std::min(n, from + len);
		r.u.assign(u.begin() + from, u.begin() + end);
		return r;
	}

	static String chr(char32_t c) {
		String r;
		r.u.push_back(c);
		return r;
	}
	static String utf8(const char *c) { return String(c); }
	static String num_int64(long long v) { return String(std::to_string(v)); }
	static String num(double v, int places = 6) {
		char buf[64];
		std::snprintf(buf, sizeof(buf), "%.*f", places < 0 ? 6 : places, v);
		return String(buf);
	}
	String operator+(const char *c) const { return *this + String(c); }
	bool operator==(const char *c) const { return *this == String(c); }
	bool operator!=(const char *c) const { return !(*this == String(c)); }
};

inline String operator+(const char *a, const String &b) { return String(a) + b; }

typedef Packed<Vector2> PackedVector2Array;
typedef Packed<float> PackedFloat32Array;
typedef Packed<int32_t> PackedInt32Array;
typedef Packed<uint8_t> PackedByteArray;
typedef Packed<String> PackedStringArray;

struct Dictionary;
struct Array;

// A tagged union, with the two container types held by shared pointer so that
// copying a Dictionary shares its contents the way Godot's does.
struct Variant {
	enum Type {
		NIL, BOOL, INT, REAL, STRING, VEC2, VEC2I, RECT2, RECT2I,
		P_VEC2, P_F32, P_I32, P_BYTE, P_STR, DICT, ARR
	};

	Type type = NIL;
	bool b = false;
	int64_t i = 0;
	double d = 0.0;
	String s;
	Vector2 v2;
	Vector2i v2i;
	Rect2 r2;
	Rect2i r2i;
	PackedVector2Array pv2;
	PackedFloat32Array pf32;
	PackedInt32Array pi32;
	PackedByteArray pb;
	PackedStringArray pstr;
	std::shared_ptr<std::map<String, Variant>> dict;
	std::shared_ptr<std::vector<Variant>> arr;

	Variant() {}
	Variant(bool x) : type(BOOL), b(x), i(x ? 1 : 0), d(x ? 1 : 0) {}
	Variant(int x) : type(INT), b(x != 0), i(x), d(x) {}
	Variant(unsigned int x) : type(INT), b(x != 0), i(x), d(x) {}
	// `int64_t` is `long` on a 64-bit Linux and `long long` on Windows, so
	// exactly one of the two spellings is still missing whichever platform
	// this is built on — and a literal written the missing way is ambiguous
	// against the two floating-point constructors rather than merely
	// unconverted. The template takes whichever it is without either being
	// declared twice.
	template <class T, class = typename std::enable_if<
			std::is_integral<T>::value &&
			!std::is_same<T, bool>::value &&
			(sizeof(T) > sizeof(int))>::type>
	Variant(T x) : type(INT), b(x != 0), i((int64_t)x), d((double)x) {}
	Variant(float x) : type(REAL), b(x != 0), i((int64_t)x), d(x) {}
	Variant(double x) : type(REAL), b(x != 0), i((int64_t)x), d(x) {}
	Variant(const char *x) : type(STRING), s(x) {}
	Variant(const String &x) : type(STRING), s(x) {}
	Variant(const Vector2 &x) : type(VEC2), v2(x) {}
	Variant(const Vector2i &x) : type(VEC2I), v2i(x) {}
	Variant(const Rect2 &x) : type(RECT2), r2(x) {}
	Variant(const Rect2i &x) : type(RECT2I), r2i(x) {}
	Variant(const PackedVector2Array &x) : type(P_VEC2), pv2(x) {}
	Variant(const PackedFloat32Array &x) : type(P_F32), pf32(x) {}
	Variant(const PackedInt32Array &x) : type(P_I32), pi32(x) {}
	Variant(const PackedByteArray &x) : type(P_BYTE), pb(x) {}
	Variant(const PackedStringArray &x) : type(P_STR), pstr(x) {}
	Variant(const Dictionary &x);
	Variant(const Array &x);

	Type get_type() const { return type; }

	operator bool() const { return type == STRING ? !s.is_empty() : b; }
	operator int() const { return (int)i; }
	operator int64_t() const { return i; }
	operator float() const { return (float)(type == INT ? (double)i : d); }
	operator double() const { return type == INT ? (double)i : d; }
	operator String() const { return s; }
	operator Vector2() const { return v2; }
	operator Vector2i() const { return v2i; }
	operator Rect2() const { return r2; }
	operator Rect2i() const { return r2i; }
	operator PackedVector2Array() const { return pv2; }
	operator PackedFloat32Array() const { return pf32; }
	operator PackedInt32Array() const { return pi32; }
	operator PackedByteArray() const { return pb; }
	operator PackedStringArray() const { return pstr; }
	operator Dictionary() const;
	operator Array() const;
};

struct Dictionary {
	std::shared_ptr<std::map<String, Variant>> m =
			std::make_shared<std::map<String, Variant>>();

	Variant &operator[](const String &k) { return (*m)[k]; }
	Variant operator[](const String &k) const {
		auto it = m->find(k);
		return it == m->end() ? Variant() : it->second;
	}
	bool has(const String &k) const { return m->find(k) != m->end(); }
	int size() const { return (int)m->size(); }
	bool is_empty() const { return m->empty(); }
	void clear() { m->clear(); }
	Variant get(const String &k, const Variant &fallback) const {
		auto it = m->find(k);
		return it == m->end() ? fallback : it->second;
	}
	PackedStringArray keys() const {
		PackedStringArray out;
		for (const auto &kv : *m) out.append(kv.first);
		return out;
	}
};

struct Array {
	std::shared_ptr<std::vector<Variant>> a =
			std::make_shared<std::vector<Variant>>();

	int size() const { return (int)a->size(); }
	bool is_empty() const { return a->empty(); }
	void clear() { a->clear(); }
	void append(const Variant &v) { a->push_back(v); }
	void push_back(const Variant &v) { a->push_back(v); }
	void resize(int n) { a->resize(n); }
	Variant &operator[](int i) { return (*a)[i]; }
	const Variant &operator[](int i) const { return (*a)[i]; }
};

inline Variant::Variant(const Dictionary &x) : type(DICT), dict(x.m) {}
inline Variant::Variant(const Array &x) : type(ARR), arr(x.a) {}

inline Variant::operator Dictionary() const {
	Dictionary out;
	if (dict) out.m = dict;
	return out;
}
inline Variant::operator Array() const {
	Array out;
	if (arr) out.a = arr;
	return out;
}

enum Error { OK = 0, FAILED = 1 };

struct RefCounted {
	virtual ~RefCounted() {}
};

template <class T>
struct Ref {
	T *p = nullptr;
	Ref() {}
	Ref(T *x) : p(x) {}
	bool is_null() const { return p == nullptr; }
	bool is_valid() const { return p != nullptr; }
	T *operator->() const { return p; }
	T *ptr() const { return p; }
};

struct FileAccess {
	enum ModeFlags { READ, WRITE };
	static bool file_exists(const String &) { return false; }
	static Ref<FileAccess> open(const String &, int) { return Ref<FileAccess>(); }
	long long get_length() { return 0; }
	unsigned int get_32() { return 0; }
	unsigned long long get_64() { return 0; }
	void seek(unsigned long long) {}
	PackedByteArray get_buffer(long long) { return PackedByteArray(); }
	void store_32(unsigned int) {}
	void store_64(unsigned long long) {}
	unsigned long long get_position() { return 0; }
	void store_buffer(const PackedByteArray &) {}
	void flush() {}
	void close() {}
};

struct DirAccess {
	static Error remove_absolute(const String &) { return OK; }
	static Error rename_absolute(const String &, const String &) { return OK; }
	static Error make_dir_recursive_absolute(const String &) { return OK; }
};

struct MethodDef {};
template <class... A>
inline MethodDef D_METHOD_impl(A &&...) { return MethodDef(); }
#define D_METHOD(...) godot::D_METHOD_impl(__VA_ARGS__)

struct ClassDBStub {
	template <class... A> static void bind_method(A &&...) {}
	template <class... A> static void bind_static_method(A &&...) {}
};
#define ClassDB godot::ClassDBStub
#define GDCLASS(a, b)
#define VARIANT_ENUM_CAST(x)
#define BIND_ENUM_CONSTANT(x)

} // namespace godot
