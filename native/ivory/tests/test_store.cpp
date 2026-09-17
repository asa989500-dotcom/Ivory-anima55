// A test bench for the pack format's arithmetic.
//
//   g++ -std=c++17 -I<stub> -I../src test_store.cpp ../src/ivory_store.cpp -o test_store
//
// ## What can and cannot be tested here
//
// The stub has no filesystem, so `commit` and `open` are not exercised —
// those need a real device and are checked by the app itself. What *is*
// checked is everything that decides whether a saved file is trustworthy: the
// checksums, the hashing, and the change detection that makes an autosave
// cost what changed rather than what exists.
//
// That split is worth being honest about rather than papering over. A bench
// that claimed to prove the atomic rename works would be lying — a rename's
// atomicity is a property of the filesystem, not of this code, and the only
// way to test it is to kill a process mid-save on a real device.

#include "ivory_store.h"

#include <cstdio>
#include <string>

using namespace godot;

static int checks = 0;
static int failures = 0;

static void ok(bool cond, const std::string &what) {
	checks++;
	if (!cond) {
		failures++;
		std::printf("  FAIL  %s\n", what.c_str());
	}
}

static PackedByteArray bytes_of(const std::string &s) {
	PackedByteArray out;
	out.resize((int)s.size());
	for (size_t i = 0; i < s.size(); i++) {
		out[(int)i] = (uint8_t)s[i];
	}
	return out;
}

static void test_crc() {
	std::printf("checksums\n");
	// The published CRC32 of "123456789" is 0xCBF43926. Checking against a
	// known value rather than against itself is the point: a table built
	// wrong is still self-consistent, and would pass every round-trip test
	// while producing checksums no other program agrees with.
	PackedByteArray probe = bytes_of("123456789");
	ok((uint32_t)IvoryStore::crc32_of(probe) == 0xCBF43926u,
			"CRC32 of the standard check string");

	// Empty input has a defined answer too, and it is zero for this
	// polynomial and initialisation.
	ok((uint32_t)IvoryStore::crc32_of(PackedByteArray()) == 0u,
			"CRC32 of nothing is zero");

	// A one-bit change must change the checksum. This is the property the
	// whole format leans on.
	PackedByteArray a = bytes_of("hello world");
	PackedByteArray b = bytes_of("hellp world");
	ok(IvoryStore::crc32_of(a) != IvoryStore::crc32_of(b),
			"one letter changes the checksum");
}

static void test_hash() {
	std::printf("content hashing\n");
	// FNV-1a of the empty input is the offset basis itself.
	ok((uint64_t)IvoryStore::hash_bytes(PackedByteArray())
			== 1469598103934665603ull,
			"the empty hash is the offset basis");

	PackedByteArray a = bytes_of("layer three");
	PackedByteArray b = bytes_of("layer three");
	ok(IvoryStore::hash_bytes(a) == IvoryStore::hash_bytes(b),
			"the same bytes hash the same");

	PackedByteArray c = bytes_of("layer four");
	ok(IvoryStore::hash_bytes(a) != IvoryStore::hash_bytes(c),
			"different bytes hash differently");

	// Transposition. A weak hash — a sum, or FNV-1 rather than FNV-1a —
	// gives the same answer for both of these, and two layers that differ
	// only by a swap would be treated as unchanged and never saved.
	ok(IvoryStore::hash_bytes(bytes_of("ab"))
			!= IvoryStore::hash_bytes(bytes_of("ba")),
			"a transposition changes the hash");
}

static void test_change_detection() {
	std::printf("only what changed\n");
	IvoryStore s;
	PackedByteArray one = bytes_of("the first layer");
	ok(s.put(String("layer/1"), one), "storing something new is a change");
	ok(!s.put(String("layer/1"), one),
			"storing the same bytes again is not");
	ok(s.record_count() == 1, "and did not add a second record");

	PackedByteArray two = bytes_of("the first layer, drawn on");
	ok(s.put(String("layer/1"), two), "different bytes are a change");
	ok(s.get(String("layer/1")).size() == two.size(),
			"and the new bytes are what comes back");

	ok(s.would_change(String("layer/2"), one),
			"a key that is not there would change");
	ok(!s.would_change(String("layer/1"), two),
			"and one holding these bytes would not");
}

static void test_keeping() {
	std::printf("holding records\n");
	IvoryStore s;
	s.put(String("a"), bytes_of("one"));
	s.put(String("b"), bytes_of("two"));
	s.put(String("c"), bytes_of("three"));
	ok(s.record_count() == 3, "three records");
	ok(s.keys().size() == 3, "three keys");
	ok(s.has(String("b")), "b is there");

	// Order is insertion order and stays that way. It is what the pack is
	// written in, so a project whose records shuffle between saves writes a
	// completely different file every time and defeats any hope of the
	// filesystem deduplicating it.
	ok(s.keys()[0] == "a" && s.keys()[2] == "c",
			"keys come back in the order they went in");

	s.erase(String("b"));
	ok(!s.has(String("b")), "b is gone");
	ok(s.record_count() == 2, "two left");
	ok(s.keys()[0] == "a" && s.keys()[1] == "c",
			"and the rest kept their order");

	// Erasing something absent is not an error and must not disturb the rest.
	s.erase(String("zzz"));
	ok(s.record_count() == 2, "erasing what is not there does nothing");

	ok(s.get(String("b")).size() == 0, "reading a gone key gives nothing");
	ok(s.get(String("never")).size() == 0, "and so does one never stored");
}

static void test_weight_and_dirty() {
	std::printf("weight and the dirty flag\n");
	IvoryStore s;
	ok(!s.dirty(), "a fresh store is clean");
	s.put(String("a"), bytes_of("12345"));
	ok(s.dirty(), "and dirty once something is put");
	ok(s.weight() == 5, "weight is the bytes held");
	s.put(String("b"), bytes_of("123"));
	ok(s.weight() == 8, "and adds up");
	s.erase(String("a"));
	ok(s.weight() == 3, "and comes down again");
}

static void test_refusals() {
	std::printf("things that should be refused\n");
	IvoryStore s;
	ok(!s.put(String(""), bytes_of("x")), "an empty key is refused");
	ok(s.record_count() == 0, "and nothing was stored");

	// A key longer than the ceiling. The ceiling exists because the index
	// stores key lengths as 32-bit numbers read back from a file, and a
	// reader that trusted an arbitrary length would allocate whatever a
	// damaged file asked it to.
	std::string huge(2000, 'k');
	ok(!s.put(String(huge.c_str()), bytes_of("x")),
			"an absurdly long key is refused");

	// An empty value is legitimate — a layer with nothing drawn on it is a
	// real thing to store — and must not be mistaken for a refusal.
	ok(s.put(String("blank"), PackedByteArray()),
			"an empty value is stored, not refused");
	ok(s.has(String("blank")), "and is there afterwards");
	ok(!s.put(String("blank"), PackedByteArray()),
			"and storing it again is still no change");

	// Committing with no path cannot write anywhere and must say so rather
	// than writing to a file called "".
	ok(!s.commit(), "committing an unopened store fails");
}

int main() {
	std::printf("\nthe pack format\n===============\n\n");
	test_crc();
	test_hash();
	test_change_detection();
	test_keeping();
	test_weight_and_dirty();
	test_refusals();
	std::printf("\n%d checks, %d failures\n\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
