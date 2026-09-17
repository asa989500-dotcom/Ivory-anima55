#ifndef IVORY_LANG_H
#define IVORY_LANG_H

// Language: the parts that GDScript was getting wrong, not the table.
//
// ## What was already fine
//
// `lang.gd` keys every string on its English text, which is the right choice
// and stays: a reader sees the sentence rather than an identifier, and an
// untranslated string degrades into correct English rather than into a blank.
// The dictionary lookup is already constant time. None of that needed C++.
//
// ## What was wrong, and it is three things
//
// **Arabic plurals.** `count_of` picks between two wordings — one and many —
// and its own comment admits Arabic needs more and shrugs. Arabic has **six**
// categories, and the difference is not stylistic:
//
//     0        صفر إطارات      zero
//     1        إطار واحد        one
//     2        إطاران           two      (a whole grammatical number)
//     3-10     3 إطارات         few
//     11-99    11 إطاراً         many
//     100+     100 إطار         other
//
// Choosing "many" for two is not slightly off, it is wrong the way "two
// frame" is wrong in English. A person reading it sees a program that does
// not speak their language. Russian, Polish and Welsh have their own rules
// and are handled by the same mechanism.
//
// **Digits.** The GDScript converter builds a new String per character —
// quadratic in the length of the text, and run on every number in every
// panel. Here it is one pass into one buffer.
//
// **Bidirectional text.** This is the one nobody notices until it is pointed
// out and then cannot stop seeing. Drop a Western number into an Arabic
// sentence and the Unicode bidirectional algorithm may pull it out of place:
// "الإطار 3 من 48" can render with the numbers transposed, or with a trailing
// bracket jumping to the wrong end. The fix is to wrap each inserted value in
// an isolate — U+2066..U+2069 — which tells the algorithm to treat the run as
// one unit and lay it out where it was put. Two characters per substitution,
// and it is the difference between a sentence and a scramble.
//
// See `fill`, which is why this class exists at all.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class IvoryLang : public RefCounted {
	GDCLASS(IvoryLang, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryLang() = default;
	~IvoryLang() = default;

	// Matching `Lang.L` exactly.
	enum Tongue { EN, AR, ES, DE, JA, ZH, KO };

	// The CLDR plural categories, in CLDR's own order.
	enum Plural { ZERO, ONE, TWO, FEW, MANY, OTHER };

	void set_tongue(int tongue);
	int tongue() const { return tongue_; }
	bool is_rtl() const;

	// Which plural form a count takes in the current language.
	//
	// The rules are CLDR's, transcribed. They are not guesses and they are
	// not "close enough" — a plural rule is either the one the language uses
	// or it is wrong, and the ones here are the published ones.
	int plural_of(int64_t count) const;

	// Digits written the way the current language writes them. One pass.
	String digits(const String &text) const;

	// A number, in the language's own digits.
	String number(int64_t value) const;
	String decimal(double value, int places) const;

	// A sentence with values dropped into it.
	//
	// Every value is wrapped in a directional isolate when the language reads
	// right to left. See the header — this is the whole reason `fill` is not
	// three lines of `replace`.
	String fill(const String &pattern, const PackedStringArray &args) const;

	// Whether a piece of text contains any strong right-to-left character,
	// which is what decides whether it needs isolating inside a
	// left-to-right sentence.
	static bool has_rtl(const String &text);

	// A run of text made safe to embed in a sentence of the other direction.
	static String isolate(const String &text);

	// --- checking a translation table ---
	//
	// Handed the English key and one language's row, it says what is wrong
	// with it. This is the language half of "a checker for the code": a
	// translation can be present, non-empty and still broken, and the three
	// ways it breaks are all mechanical.
	//
	// Returns a bitmask of `Fault`.
	static int fault_of(const String &key, const String &row);

	enum Fault {
		FAULT_NONE = 0,
		// The row is the English key verbatim. Usually an unfinished row —
		// though not always, which is why this is reported and not fixed.
		FAULT_UNTRANSLATED = 1,
		// The row has different placeholders from the key: a missing {0}
		// prints nothing where a number should be, and an extra {2} prints
		// the literal text "{2}" to the user.
		FAULT_PLACEHOLDERS = 2,
		// The row is empty or only spaces.
		FAULT_EMPTY = 4,
		// The row is more than three times the key's length, or less than a
		// third of it. Not wrong by itself — German is long and Chinese is
		// short — but it is how a row pasted into the wrong cell shows up.
		FAULT_LENGTH = 8,
	};

private:
	int tongue_ = EN;
};

} // namespace godot

VARIANT_ENUM_CAST(IvoryLang::Tongue);
VARIANT_ENUM_CAST(IvoryLang::Plural);
VARIANT_ENUM_CAST(IvoryLang::Fault);

#endif // IVORY_LANG_H
