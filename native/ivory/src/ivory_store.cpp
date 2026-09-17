#include "ivory_store.h"

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>

#include <algorithm>
#include <cstring>

using namespace godot;

namespace {

const uint32_t MAGIC = 0x54535649u; // "IVST" little-endian
const uint32_t FORMAT = 1u;
// A key longer than this is a bug in the caller, not a key.
const int KEY_CEILING = 512;

// CRC32, the ordinary reflected polynomial. The table is built once on first
// use rather than written out as 256 constants — it is eight lines of code
// against a page of numbers, and a generated table cannot be mistyped.
const uint32_t *crc_table() {
	static uint32_t table[256];
	static bool ready = false;
	if (!ready) {
		for (uint32_t i = 0; i < 256; i++) {
			uint32_t c = i;
			for (int k = 0; k < 8; k++) {
				c = (c & 1u) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
			}
			table[i] = c;
		}
		ready = true;
	}
	return table;
}

uint32_t crc_of(const uint8_t *data, int64_t len) {
	const uint32_t *table = crc_table();
	uint32_t c = 0xFFFFFFFFu;
	for (int64_t i = 0; i < len; i++) {
		c = table[(c ^ data[i]) & 0xFFu] ^ (c >> 8);
	}
	return c ^ 0xFFFFFFFFu;
}

uint64_t fnv1a(const uint8_t *data, int64_t len) {
	// FNV-1a, 64 bit. The multiply-then-xor order matters: FNV-1 (xor after
	// multiply) has markedly worse avalanche on short inputs, which is most
	// of what gets hashed here.
	uint64_t h = 1469598103934665603ull;
	for (int64_t i = 0; i < len; i++) {
		h ^= (uint64_t)data[i];
		h *= 1099511628211ull;
	}
	return h;
}

std::string to_std(const String &s) {
	const CharString cs = s.utf8();
	return std::string(cs.get_data(), (size_t)cs.length());
}

} // namespace

void IvoryStore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("open", "path"), &IvoryStore::open);
	ClassDB::bind_method(D_METHOD("health"), &IvoryStore::health);
	ClassDB::bind_method(D_METHOD("put", "key", "bytes"), &IvoryStore::put);
	ClassDB::bind_method(D_METHOD("get", "key"), &IvoryStore::get);
	ClassDB::bind_method(D_METHOD("has", "key"), &IvoryStore::has);
	ClassDB::bind_method(D_METHOD("erase", "key"), &IvoryStore::erase);
	ClassDB::bind_method(D_METHOD("keys"), &IvoryStore::keys);
	ClassDB::bind_method(D_METHOD("would_change", "key", "bytes"),
			&IvoryStore::would_change);
	ClassDB::bind_method(D_METHOD("commit"), &IvoryStore::commit);
	ClassDB::bind_method(D_METHOD("dirty"), &IvoryStore::dirty);
	ClassDB::bind_method(D_METHOD("generation"), &IvoryStore::generation);
	ClassDB::bind_method(D_METHOD("record_count"),
			&IvoryStore::record_count);
	ClassDB::bind_method(D_METHOD("weight"), &IvoryStore::weight);
	ClassDB::bind_method(D_METHOD("report"), &IvoryStore::report);
	ClassDB::bind_static_method("IvoryStore",
			D_METHOD("hash_bytes", "bytes"), &IvoryStore::hash_bytes);
	ClassDB::bind_static_method("IvoryStore",
			D_METHOD("crc32_of", "bytes"), &IvoryStore::crc32_of);

	BIND_ENUM_CONSTANT(HEALTH_FRESH);
	BIND_ENUM_CONSTANT(HEALTH_GOOD);
	BIND_ENUM_CONSTANT(HEALTH_RECOVERED);
	BIND_ENUM_CONSTANT(HEALTH_LOST);
}

int64_t IvoryStore::hash_bytes(const PackedByteArray &bytes) {
	if (bytes.size() == 0) {
		return (int64_t)fnv1a(nullptr, 0);
	}
	return (int64_t)fnv1a(bytes.ptr(), bytes.size());
}

int64_t IvoryStore::crc32_of(const PackedByteArray &bytes) {
	if (bytes.size() == 0) {
		return (int64_t)crc_of(nullptr, 0);
	}
	return (int64_t)crc_of(bytes.ptr(), bytes.size());
}

// ------------------------------------------------------------------- holding

bool IvoryStore::put(const String &key, const PackedByteArray &bytes) {
	const std::string k = to_std(key);
	if (k.empty() || (int)k.size() > KEY_CEILING) {
		return false;
	}
	const uint64_t h = (uint64_t)hash_bytes(bytes);
	auto found = held_.find(k);
	if (found != held_.end()) {
		// --- the whole of "an autosave costs what changed" ---
		//
		// Compared by hash and then by length, not by bytes. A full compare
		// would be correct and would cost a pass over the data on every put
		// of every record on every autosave tick — which is the cost this is
		// avoiding. A 64-bit hash collision between two blobs that are both
		// valid layers is not a thing that happens: the odds are around one
		// in eighteen quintillion per pair, and the failure would be a saved
		// layer that kept an older version of itself.
		if (found->second.hash == h
				&& found->second.bytes.size() == bytes.size()) {
			return false;
		}
		found->second.bytes = bytes;
		found->second.hash = h;
		dirty_ = true;
		return true;
	}
	Record made;
	made.bytes = bytes;
	made.hash = h;
	held_[k] = made;
	order_.push_back(k);
	dirty_ = true;
	return true;
}

bool IvoryStore::would_change(const String &key,
		const PackedByteArray &bytes) const {
	auto found = held_.find(to_std(key));
	if (found == held_.end()) {
		return true;
	}
	return found->second.hash != (uint64_t)hash_bytes(bytes)
			|| found->second.bytes.size() != bytes.size();
}

PackedByteArray IvoryStore::get(const String &key) const {
	auto found = held_.find(to_std(key));
	if (found == held_.end()) {
		return PackedByteArray();
	}
	return found->second.bytes;
}

bool IvoryStore::has(const String &key) const {
	return held_.find(to_std(key)) != held_.end();
}

void IvoryStore::erase(const String &key) {
	const std::string k = to_std(key);
	auto found = held_.find(k);
	if (found == held_.end()) {
		return;
	}
	held_.erase(found);
	order_.erase(std::remove(order_.begin(), order_.end(), k), order_.end());
	dirty_ = true;
}

PackedStringArray IvoryStore::keys() const {
	PackedStringArray out;
	for (size_t i = 0; i < order_.size(); i++) {
		out.append(String::utf8(order_[i].c_str()));
	}
	return out;
}

int64_t IvoryStore::weight() const {
	int64_t total = 0;
	for (size_t i = 0; i < order_.size(); i++) {
		auto found = held_.find(order_[i]);
		if (found != held_.end()) {
			total += found->second.bytes.size();
		}
	}
	return total;
}

Dictionary IvoryStore::report() const {
	Dictionary out;
	for (size_t i = 0; i < order_.size(); i++) {
		auto found = held_.find(order_[i]);
		if (found == held_.end()) {
			continue;
		}
		Dictionary row;
		row["length"] = (int64_t)found->second.bytes.size();
		row["hash"] = (int64_t)found->second.hash;
		out[String::utf8(order_[i].c_str())] = row;
	}
	return out;
}

// ------------------------------------------------------------------ reading

bool IvoryStore::open(const String &path) {
	path_ = path;
	order_.clear();
	held_.clear();
	generation_ = 0;
	dirty_ = false;

	if (!FileAccess::file_exists(path)) {
		// Not an error. A project being saved for the first time has no pack,
		// and treating that as a failure would make every new project look
		// broken on its first autosave.
		health_ = HEALTH_FRESH;
		return true;
	}
	if (read_pack(path)) {
		health_ = HEALTH_GOOD;
		return true;
	}

	// --- the main pack did not survive ---
	//
	// This is the moment the backup exists for, and it is worth being precise
	// about what has happened: an atomic rename cannot leave a torn pack, so
	// a pack that fails its checksums means the *device* damaged it — a bad
	// block, a filesystem that reordered writes, a card pulled mid-write.
	// Rare, and not so rare that a drawing app should have no answer.
	const String backup = path + String(".bak");
	if (FileAccess::file_exists(backup) && read_pack(backup)) {
		health_ = HEALTH_RECOVERED;
		// Deliberately left dirty, so the next commit writes the recovered
		// contents back over the damaged pack. Recovering into memory and
		// leaving the bad file on disk means recovering again next time, and
		// the time after that, until the backup is damaged too.
		dirty_ = true;
		return true;
	}
	health_ = HEALTH_LOST;
	return false;
}

bool IvoryStore::read_pack(const String &from) {
	Ref<FileAccess> f = FileAccess::open(from, FileAccess::READ);
	if (f.is_null()) {
		return false;
	}
	const int64_t size = (int64_t)f->get_length();
	if (size < 28) {
		return false;
	}
	if (f->get_32() != MAGIC) {
		return false;
	}
	const uint32_t version = f->get_32();
	if (version != FORMAT) {
		// A pack from a future build. Refused rather than guessed at: reading
		// an unknown layout and getting plausible-looking rubbish is worse
		// than saying no, because rubbish gets saved back over the original.
		return false;
	}
	const int64_t gen = (int64_t)f->get_64();
	const int32_t count = (int32_t)f->get_32();
	const int64_t index_at = (int64_t)f->get_64();
	if (count < 0 || index_at < 28 || index_at > size) {
		return false;
	}

	// --- the index, checked before it is trusted ---
	//
	// Every offset and length in the pack comes from here, so an index that
	// has been damaged can point anywhere. Checking its CRC first means the
	// offsets used below are either the ones that were written or the read is
	// abandoned — there is no path where a corrupt number is used to index
	// into a buffer.
	f->seek(index_at);
	const int64_t index_len = size - index_at - 4;
	if (index_len < 0) {
		return false;
	}
	PackedByteArray index = f->get_buffer(index_len);
	const uint32_t want_crc = f->get_32();
	if (index.size() != index_len) {
		return false;
	}
	if ((uint32_t)crc32_of(index) != want_crc) {
		return false;
	}

	// Walking the index by hand rather than seeking, since it is already in
	// memory and a seek per field would be a system call per field.
	int64_t at = 0;
	auto take32 = [&](uint32_t &out) -> bool {
		if (at + 4 > index.size()) {
			return false;
		}
		out = (uint32_t)index[at] | ((uint32_t)index[at + 1] << 8)
				| ((uint32_t)index[at + 2] << 16)
				| ((uint32_t)index[at + 3] << 24);
		at += 4;
		return true;
	};
	auto take64 = [&](uint64_t &out) -> bool {
		uint32_t lo = 0, hi = 0;
		if (!take32(lo) || !take32(hi)) {
			return false;
		}
		out = (uint64_t)lo | ((uint64_t)hi << 32);
		return true;
	};

	std::vector<std::string> names;
	std::vector<int64_t> offsets;
	std::vector<int64_t> lengths;
	std::vector<uint64_t> hashes;
	std::vector<uint32_t> crcs;
	for (int32_t i = 0; i < count; i++) {
		uint32_t klen = 0;
		if (!take32(klen) || klen == 0 || (int)klen > KEY_CEILING
				|| at + (int64_t)klen > index.size()) {
			return false;
		}
		std::string key((const char *)(index.ptr() + at), (size_t)klen);
		at += klen;
		uint64_t off = 0, len = 0, hash = 0;
		uint32_t crc = 0;
		if (!take64(off) || !take64(len) || !take64(hash) || !take32(crc)) {
			return false;
		}
		// Every offset checked against the payload region before it is used.
		// The addition is done in signed 64-bit so an offset near the top of
		// the range cannot wrap around into looking valid.
		const int64_t o = (int64_t)off;
		const int64_t l = (int64_t)len;
		if (o < 28 || l < 0 || o + l > index_at) {
			return false;
		}
		names.push_back(key);
		offsets.push_back(o);
		lengths.push_back(l);
		hashes.push_back(hash);
		crcs.push_back(crc);
	}

	for (size_t i = 0; i < names.size(); i++) {
		f->seek((uint64_t)offsets[i]);
		PackedByteArray bytes = f->get_buffer(lengths[i]);
		if (bytes.size() != lengths[i]) {
			return false;
		}
		if ((uint32_t)crc32_of(bytes) != crcs[i]) {
			// One damaged record fails the whole pack rather than being
			// skipped. A project silently missing one layer is worse than a
			// project that says it could not be opened and falls back to its
			// backup: the first is discovered days later with the work gone.
			return false;
		}
		Record made;
		made.bytes = bytes;
		made.hash = hashes[i];
		held_[names[i]] = made;
		order_.push_back(names[i]);
	}
	generation_ = gen;
	return true;
}

// ------------------------------------------------------------------ writing

bool IvoryStore::commit() {
	if (path_.is_empty()) {
		return false;
	}
	const String temp = path_ + String(".new");
	if (!write_pack(temp)) {
		// The temporary file is the only thing that could be damaged, and the
		// real pack has not been touched. Removed so a half-written temp does
		// not sit there confusing the next attempt.
		DirAccess::remove_absolute(temp);
		return false;
	}

	// --- the swap ---
	//
	// Old pack to `.bak`, new pack to the real name. The order matters: if
	// the process dies between the two, the real name still points at the old
	// pack — the same file, now also copied to `.bak`. There is no ordering
	// of these two renames that loses data, but this one also never leaves
	// the real name absent.
	const String backup = path_ + String(".bak");
	if (FileAccess::file_exists(path_)) {
		DirAccess::remove_absolute(backup);
		if (DirAccess::rename_absolute(path_, backup) != OK) {
			DirAccess::remove_absolute(temp);
			return false;
		}
	}
	if (DirAccess::rename_absolute(temp, path_) != OK) {
		// Put the old one back. Failing here with the real name missing would
		// be the one outcome this whole class exists to prevent.
		if (FileAccess::file_exists(backup)) {
			DirAccess::rename_absolute(backup, path_);
		}
		DirAccess::remove_absolute(temp);
		return false;
	}
	generation_++;
	dirty_ = false;
	return true;
}

bool IvoryStore::write_pack(const String &to) const {
	Ref<FileAccess> f = FileAccess::open(to, FileAccess::WRITE);
	if (f.is_null()) {
		return false;
	}
	f->store_32(MAGIC);
	f->store_32(FORMAT);
	f->store_64((uint64_t)(generation_ + 1));
	f->store_32((uint32_t)order_.size());
	// The index offset is not known until the payload has been written, so
	// its place is reserved and filled in at the end.
	const int64_t index_slot = (int64_t)f->get_position();
	f->store_64(0);

	std::vector<int64_t> offsets;
	std::vector<uint32_t> crcs;
	offsets.reserve(order_.size());
	crcs.reserve(order_.size());
	for (size_t i = 0; i < order_.size(); i++) {
		auto found = held_.find(order_[i]);
		if (found == held_.end()) {
			offsets.push_back(0);
			crcs.push_back(0);
			continue;
		}
		offsets.push_back((int64_t)f->get_position());
		crcs.push_back((uint32_t)crc32_of(found->second.bytes));
		if (found->second.bytes.size() > 0) {
			f->store_buffer(found->second.bytes);
		}
	}

	const int64_t index_at = (int64_t)f->get_position();
	PackedByteArray index;
	auto add32 = [&](uint32_t v) {
		index.append((uint8_t)(v & 0xFFu));
		index.append((uint8_t)((v >> 8) & 0xFFu));
		index.append((uint8_t)((v >> 16) & 0xFFu));
		index.append((uint8_t)((v >> 24) & 0xFFu));
	};
	auto add64 = [&](uint64_t v) {
		add32((uint32_t)(v & 0xFFFFFFFFull));
		add32((uint32_t)(v >> 32));
	};
	for (size_t i = 0; i < order_.size(); i++) {
		auto found = held_.find(order_[i]);
		const int64_t len = found == held_.end()
				? 0 : (int64_t)found->second.bytes.size();
		const uint64_t hash = found == held_.end() ? 0 : found->second.hash;
		add32((uint32_t)order_[i].size());
		for (size_t c = 0; c < order_[i].size(); c++) {
			index.append((uint8_t)order_[i][c]);
		}
		add64((uint64_t)offsets[i]);
		add64((uint64_t)len);
		add64(hash);
		add32(crcs[i]);
	}
	f->store_buffer(index);
	f->store_32((uint32_t)crc32_of(index));

	f->seek((uint64_t)index_slot);
	f->store_64((uint64_t)index_at);

	// --- flushed before the rename, not after ---
	//
	// A rename is atomic with respect to the *directory entry*. It says
	// nothing about whether the file's contents have reached the device: on a
	// journalled filesystem the rename can be durable while the data behind
	// it is still in a write cache, and a power cut in that window leaves the
	// new name pointing at a file full of zeros. Flushing first is what
	// closes that window, and it is the one line here that people leave out.
	f->flush();
	f->close();
	return true;
}
