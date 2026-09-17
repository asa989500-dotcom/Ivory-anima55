#include "ivory_lang.h"

#include <cmath>

using namespace godot;

void IvoryLang::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_tongue", "tongue"),
			&IvoryLang::set_tongue);
	ClassDB::bind_method(D_METHOD("tongue"), &IvoryLang::tongue);
	ClassDB::bind_method(D_METHOD("is_rtl"), &IvoryLang::is_rtl);
	ClassDB::bind_method(D_METHOD("plural_of", "count"),
			&IvoryLang::plural_of);
	ClassDB::bind_method(D_METHOD("digits", "text"), &IvoryLang::digits);
	ClassDB::bind_method(D_METHOD("number", "value"), &IvoryLang::number);
	ClassDB::bind_method(D_METHOD("decimal", "value", "places"),
			&IvoryLang::decimal);
	ClassDB::bind_method(D_METHOD("fill", "pattern", "args"),
			&IvoryLang::fill);
	ClassDB::bind_static_method("IvoryLang", D_METHOD("has_rtl", "text"),
			&IvoryLang::has_rtl);
	ClassDB::bind_static_method("IvoryLang", D_METHOD("isolate", "text"),
			&IvoryLang::isolate);
	ClassDB::bind_static_method("IvoryLang",
			D_METHOD("fault_of", "key", "row"), &IvoryLang::fault_of);

	BIND_ENUM_CONSTANT(EN);
	BIND_ENUM_CONSTANT(AR);
	BIND_ENUM_CONSTANT(ES);
	BIND_ENUM_CONSTANT(DE);
	BIND_ENUM_CONSTANT(JA);
	BIND_ENUM_CONSTANT(ZH);
	BIND_ENUM_CONSTANT(KO);
	BIND_ENUM_CONSTANT(ZERO);
	BIND_ENUM_CONSTANT(ONE);
	BIND_ENUM_CONSTANT(TWO);
	BIND_ENUM_CONSTANT(FEW);
	BIND_ENUM_CONSTANT(MANY);
	BIND_ENUM_CONSTANT(OTHER);
	BIND_ENUM_CONSTANT(FAULT_NONE);
	BIND_ENUM_CONSTANT(FAULT_UNTRANSLATED);
	BIND_ENUM_CONSTANT(FAULT_PLACEHOLDERS);
	BIND_ENUM_CONSTANT(FAULT_EMPTY);
	BIND_ENUM_CONSTANT(FAULT_LENGTH);
}

void IvoryLang::set_tongue(int tongue) {
	tongue_ = tongue < 0 ? 0 : (tongue > KO ? (int)KO : tongue);
}

bool IvoryLang::is_rtl() const {
	return tongue_ == AR;
}

// ------------------------------------------------------------------ plurals

int IvoryLang::plural_of(int64_t count) const {
	const int64_t n = count < 0 ? -count : count;
	switch (tongue_) {
		case AR: {
			// CLDR's rule for Arabic, transcribed. The two middle cases are
			// on `n % 100` because the pattern repeats within each hundred:
			// 103 takes the same form as 3, and 111 the same as 11.
			if (n == 0) {
				return ZERO;
			}
			if (n == 1) {
				return ONE;
			}
			if (n == 2) {
				return TWO;
			}
			const int64_t hundred = n % 100;
			if (hundred >= 3 && hundred <= 10) {
				return FEW;
			}
			if (hundred >= 11 && hundred <= 99) {
				return MANY;
			}
			return OTHER;
		}
		case JA:
		case ZH:
		case KO:
			// No grammatical number at all. One form for every count, which
			// is not a simplification — these languages genuinely do not
			// inflect the noun, and offering a translator two boxes to fill
			// with the same text invites them to differ by accident.
			return OTHER;
		case EN:
		case ES:
		case DE:
		default:
			return n == 1 ? ONE : OTHER;
	}
}

// ------------------------------------------------------------------- digits

String IvoryLang::digits(const String &text) const {
	if (tongue_ != AR) {
		return text;
	}
	// Eastern Arabic numerals are U+0660..U+0669, contiguous and in order, so
	// the conversion is one addition rather than a lookup table.
	//
	// Built into one buffer rather than by concatenation. The GDScript
	// version appended to a String per character, and appending to an
	// immutable string in a loop is quadratic — invisible on "24 fps" and
	// very much not on a paragraph.
	const int n = text.length();
	String out;
	for (int i = 0; i < n; i++) {
		const char32_t c = text[i];
		if (c >= U'0' && c <= U'9') {
			out += String::chr((char32_t)(0x0660 + (c - U'0')));
		} else {
			out += String::chr(c);
		}
	}
	return out;
}

String IvoryLang::number(int64_t value) const {
	return digits(String::num_int64(value));
}

String IvoryLang::decimal(double value, int places) const {
	const int p = places < 0 ? 0 : (places > 6 ? 6 : places);
	return digits(String::num(value, p));
}

// --------------------------------------------------------------- direction

bool IvoryLang::has_rtl(const String &text) {
	for (int i = 0; i < text.length(); i++) {
		const char32_t c = text[i];

		// --- digits are not strong, and this is the bug that caught me ---
		//
		// The first version tested the whole 0x0590–0x08FF block, which is
		// Hebrew through Arabic and reads like the right answer. It is not:
		// **Arabic-Indic digits live inside that block**, at 0x0660–0x0669,
		// and their Unicode bidi class is AN — Arabic Number — which is a
		// *weak* type, not a strong direction.
		//
		// The consequence was exact and invisible. `fill` isolates a value
		// only when the value is not itself right-to-left; a number converted
		// to Eastern digits was reported as right-to-left, so it was never
		// isolated — and the numbers in Arabic sentences were left to the
		// bidirectional algorithm to place, which is the entire failure the
		// isolation exists to prevent. The feature was off precisely where it
		// was needed and on everywhere else.
		//
		// Caught only because the bench asserted the *length* of a filled
		// Arabic sentence, which counts the isolation marks. Nothing about
		// the visible text would have shown it until somebody read a panel.
		if ((c >= 0x0660 && c <= 0x0669) || (c >= 0x06F0 && c <= 0x06F9)) {
			continue;
		}
		// Arabic-Indic percent, decimal and thousands separators, and the
		// tatweel, are all weak or neutral for the same reason.
		if (c == 0x066A || c == 0x066B || c == 0x066C || c == 0x0640) {
			continue;
		}

		// What is left: Hebrew, Arabic letters, Syriac, Thaana, and the
		// Arabic supplements and presentation forms. Ranges rather than a
		// per-script table, because the question is only "is there a strong
		// right-to-left character in this run".
		if ((c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFDFF)
				|| (c >= 0xFE70 && c <= 0xFEFF)) {
			return true;
		}
	}
	return false;
}

String IvoryLang::isolate(const String &text) {
	if (text.is_empty()) {
		return text;
	}
	// U+2068 FIRST STRONG ISOLATE and U+2069 POP DIRECTIONAL ISOLATE.
	//
	// "First strong" rather than an explicit left-to-right isolate because it
	// works for both: the direction of the run is taken from its own first
	// strong character, so a number comes out left to right and an Arabic
	// name inside an English sentence comes out right to left, from the same
	// wrapper.
	//
	// What this buys: the bidirectional algorithm treats everything between
	// the two marks as a single opaque unit placed where it sits in the
	// sentence. Without it, a number at the end of an Arabic sentence
	// followed by a full stop can render with the stop on the wrong side, and
	// two numbers in one sentence can swap.
	return String::chr((char32_t)0x2068) + text
			+ String::chr((char32_t)0x2069);
}

String IvoryLang::fill(const String &pattern,
		const PackedStringArray &args) const {
	// Walked once rather than one `replace` per argument.
	//
	// Beyond speed, the single pass is what makes it *correct*: replacing
	// "{0}" and then "{1}" means that if the value substituted for {0}
	// happens to contain the text "{1}" — a filename, something a person
	// typed — the second replace would reach into it. One pass never looks at
	// what it has already written.
	String out;
	const int n = pattern.length();
	const bool wrap = is_rtl();
	int i = 0;
	while (i < n) {
		const char32_t c = pattern[i];
		if (c == U'{') {
			int j = i + 1;
			int index = 0;
			bool digits_seen = false;
			while (j < n && pattern[j] >= U'0' && pattern[j] <= U'9') {
				index = index * 10 + (int)(pattern[j] - U'0');
				digits_seen = true;
				j++;
			}
			if (digits_seen && j < n && pattern[j] == U'}') {
				String value = index < args.size()
						? args[index] : String("");
				value = digits(value);
				// Isolated only in a right-to-left sentence, and only when
				// the value is not itself right-to-left. Wrapping an Arabic
				// value inside Arabic text costs two invisible characters and
				// buys nothing.
				if (wrap && !has_rtl(value)) {
					value = isolate(value);
				}
				out += value;
				i = j + 1;
				continue;
			}
		}
		out += String::chr(c);
		i++;
	}
	return out;
}

// ------------------------------------------------------- checking a table

int IvoryLang::fault_of(const String &key, const String &row) {
	int faults = FAULT_NONE;
	if (row.strip_edges().is_empty()) {
		return FAULT_EMPTY;
	}
	if (row == key) {
		faults |= FAULT_UNTRANSLATED;
	}

	// Placeholders, counted in both. A row that lost its {0} prints nothing
	// where a number belongs; one that gained a {2} prints the literal
	// characters to the user. Both are silent in testing unless somebody
	// happens to open that panel in that language.
	int key_marks = 0;
	int row_marks = 0;
	int highest_key = -1;
	int highest_row = -1;
	for (int pass = 0; pass < 2; pass++) {
		const String &text = pass == 0 ? key : row;
		int &count = pass == 0 ? key_marks : row_marks;
		int &highest = pass == 0 ? highest_key : highest_row;
		for (int i = 0; i + 2 < text.length(); i++) {
			if (text[i] != U'{') {
				continue;
			}
			int j = i + 1;
			int index = 0;
			bool seen = false;
			while (j < text.length() && text[j] >= U'0' && text[j] <= U'9') {
				index = index * 10 + (int)(text[j] - U'0');
				seen = true;
				j++;
			}
			if (seen && j < text.length() && text[j] == U'}') {
				count++;
				if (index > highest) {
					highest = index;
				}
			}
		}
	}
	if (key_marks != row_marks || highest_key != highest_row) {
		faults |= FAULT_PLACEHOLDERS;
	}

	// Length. Measured in characters, and deliberately generous: German runs
	// long, Chinese runs very short, and a rule tight enough to catch every
	// mistake would flag half of a correct table. What this catches is the
	// row pasted into the wrong cell, which is off by a factor of ten rather
	// than of two.
	const int kl = key.length();
	const int rl = row.length();
	if (kl > 8 && (rl > kl * 3 || rl * 3 < kl)) {
		faults |= FAULT_LENGTH;
	}
	return faults;
}
