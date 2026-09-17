#ifndef IVORY_STORE_H
#define IVORY_STORE_H

// Keeping work on disk, and being certain it is still there.
//
// ## What is actually hard about saving
//
// Not writing bytes. Writing bytes is easy and the current vault does it
// correctly. What is hard is the three questions underneath:
//
//   1. **What happens if the app dies halfway through a save?** A phone can
//      kill a process at any instruction. If that instruction is in the
//      middle of `project.json`, the file on disk is now half of the old
//      document and half of the new one — which is not a document, and which
//      the loader will either reject or, worse, partially accept.
//
//   2. **How little can be written?** A project is mostly pixels, and pixels
//      are mostly unchanged. Re-encoding forty layers because one of them was
//      drawn on is the difference between a save nobody notices and a save
//      that stutters the drawing every twenty-five seconds.
//
//   3. **What stops two saves colliding?** Autosave on a timer, a save on
//      close, and a save on quit can all want the same folder at the same
//      moment. Two writers interleaving in one directory is how a project
//      ends up with layer three from one save and layer four from another.
//
// This class answers those three and nothing else. It does not know what a
// project is, what a layer is, or what any of the bytes mean.
//
// ## The answer to the first: write somewhere else, then rename
//
// A rename within one filesystem is **atomic**. The operating system
// guarantees that a reader sees either the old file or the new one, never a
// mixture and never a gap — it is a single directory-entry update. So every
// write here goes to a temporary file, is flushed to the device, and is then
// renamed over the real one.
//
// The consequence is worth stating plainly: **there is no window in which the
// data is invalid.** Kill the process at any point and the file on disk is
// either exactly the previous save or exactly the new one. Not partially
// either.
//
// The previous pack is kept as `.bak` across the rename, so even a filesystem
// that lies about atomicity — some do, over some network mounts — leaves a
// complete older copy to fall back to.
//
// ## The answer to the second: content hashing
//
// Every record carries a 64-bit hash of its own bytes. Handing `put` the same
// bytes twice is free: the second call compares the hash, sees no change and
// returns. That is what makes an autosave of a project where one layer was
// touched cost one layer, not forty.
//
// **A promise worth being honest about.** Sub-millisecond saving is possible
// for *deciding what to write* and for *writing the metadata*, and those are
// the parts that run on every autosave tick. It is not possible for flushing
// twenty megabytes of new pixels to a phone's flash storage — no format makes
// that instant, and a class claiming otherwise would be lying. What this does
// is make sure the twenty megabytes are only written when twenty megabytes
// actually changed.
//
// ## The answer to the third: one pack, one writer, one generation
//
// All of a project's records live in a single pack file rather than in a
// directory of small files. That is what makes the atomic rename cover the
// *whole* project rather than one file of it: with forty separate files there
// are forty separate renames and forty chances to be killed between two of
// them, leaving a folder that is internally inconsistent — which is exactly
// the "things getting tangled together" this is meant to prevent.
//
// A generation counter in the header increases on every commit. A reader that
// has seen generation 12 and is handed generation 11 knows it is looking at a
// stale copy.
//
// ## The format
//
//   header    magic "IVST", version, generation, record count, index offset
//   payload   every record's bytes, back to back
//   index     per record: key, offset, length, hash, CRC32 of the bytes
//   footer    CRC32 of the index itself
//
// The index is at the *end* rather than the front, which is what lets records
// be appended without rewriting anything before them. The index CRC is
// checked before the index is trusted, and each record's CRC before that
// record is handed out — so a bad block on the device is detected as a bad
// block rather than silently returned as data.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace godot {

class IvoryStore : public RefCounted {
	GDCLASS(IvoryStore, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryStore() = default;
	~IvoryStore() = default;

	// Loads a pack, or starts an empty one when the file is absent. Returns
	// false only when a pack exists and is unreadable — an absent pack is a
	// new project, not an error.
	bool open(const String &path);

	// Whether the pack that was opened had to fall back to its backup, or was
	// beyond repair. The caller wants to know: a project that came back from
	// its backup has lost its most recent save and should say so.
	int health() const { return health_; }

	// Stores one record. Returns true when the pack actually changed —
	// false means the bytes were identical to what is already held and
	// nothing needed doing.
	bool put(const String &key, const PackedByteArray &bytes);

	// Reads one record. An absent or corrupt record comes back empty.
	PackedByteArray get(const String &key) const;

	bool has(const String &key) const;
	void erase(const String &key);
	PackedStringArray keys() const;

	// Whether `put` would change anything, without doing it.
	bool would_change(const String &key, const PackedByteArray &bytes) const;

	// Writes the pack. Temporary file, flush, rename — see the header.
	// Returns false when anything failed, in which case the file on disk is
	// untouched and still valid.
	bool commit();

	// Whether anything has been put or erased since the last commit.
	bool dirty() const { return dirty_; }

	int64_t generation() const { return generation_; }
	int record_count() const { return (int)order_.size(); }

	// How large the pack would be, for the caller's own budgeting.
	int64_t weight() const;

	// What is in the pack, for the test bench and for diagnostics: each
	// record's length, hash and offset.
	Dictionary report() const;

	// --- exposed because hashing is useful outside a pack too ---

	// FNV-1a, 64 bit. Not a cryptographic hash and not trying to be: the job
	// is telling two blobs apart, and for that a good non-cryptographic hash
	// is faster and entirely sufficient.
	static int64_t hash_bytes(const PackedByteArray &bytes);
	static int64_t crc32_of(const PackedByteArray &bytes);

	enum Health {
		HEALTH_FRESH,     // no pack existed; this is a new one
		HEALTH_GOOD,      // opened cleanly
		HEALTH_RECOVERED, // the main pack was bad, the backup was good
		HEALTH_LOST,      // both were bad
	};

private:
	struct Record {
		PackedByteArray bytes;
		uint64_t hash = 0;
	};

	String path_;
	std::vector<std::string> order_;
	std::unordered_map<std::string, Record> held_;
	int64_t generation_ = 0;
	bool dirty_ = false;
	int health_ = HEALTH_FRESH;

	bool read_pack(const String &from);
	bool write_pack(const String &to) const;
};

} // namespace godot

VARIANT_ENUM_CAST(IvoryStore::Health);

#endif // IVORY_STORE_H
