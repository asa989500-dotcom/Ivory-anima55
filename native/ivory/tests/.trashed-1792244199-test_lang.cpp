// A test bench for the language engine and the layout resolver.
//
//   g++ -std=c++17 -I<stub> -I../src test_lang.cpp \
//       ../src/ivory_lang.cpp ../src/ivory_layout.cpp -o test_lang
//
// ## What is worth asserting here
//
// The plural rules are the one place in this app where the correct answer is
// **published** — CLDR states them, and a transcription either matches or is
// wrong. So those are checked against the boundaries the published rule names:
// 0, 1, 2, 3, 10, 11, 99, 100, 102, 103. Every one of those is a place the
// Arabic rule changes category, and a rule that gets 5 and 50 right while
// getting 102 wrong is exactly the kind of thing that ships.
//
// For the layout resolver the assertion is a property rather than a position:
// **after resolving, nothing overlaps.** Where each rectangle ended up is not
// something to pin down — there are many correct answers — but "no two
// overlap, no pinned one moved, nothing left the screen" holds for all of
// them.

#include "ivory_lang.h"
#include "ivory_layout.h"

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

static void same(int got, int want, const std::string &what) {
	checks++;
	if (got != want) {
		failures++;
		std::printf("  FAIL  %s — got %d, wanted %d\n",
				what.c_str(), got, want);
	}
}

// ------------------------------------------------------------- plurals

static void test_arabic_plurals() {
	std::printf("Arabic plural categories\n");
	IvoryLang l;
	l.set_tongue(IvoryLang::AR);

	// Every boundary the published rule names. A transcription that is right
	// for small numbers and wrong at 102 is the failure that ships, because
	// nobody tests a panel with a hundred and two of anything.
	same(l.plural_of(0), IvoryLang::ZERO, "0 is zero");
	same(l.plural_of(1), IvoryLang::ONE, "1 is one");
	same(l.plural_of(2), IvoryLang::TWO, "2 is two, a real grammatical dual");
	same(l.plural_of(3), IvoryLang::FEW, "3 is few");
	same(l.plural_of(10), IvoryLang::FEW, "10 is still few");
	same(l.plural_of(11), IvoryLang::MANY, "11 is many");
	same(l.plural_of(99), IvoryLang::MANY, "99 is still many");
	same(l.plural_of(100), IvoryLang::OTHER, "100 is other");
	same(l.plural_of(101), IvoryLang::OTHER, "101 is other");
	same(l.plural_of(102), IvoryLang::OTHER, "102 is other");
	same(l.plural_of(103), IvoryLang::FEW, "103 repeats the pattern of 3");
	same(l.plural_of(111), IvoryLang::MANY, "111 repeats the pattern of 11");
	same(l.plural_of(200), IvoryLang::OTHER, "200 is other");
	same(l.plural_of(203), IvoryLang::FEW, "203 is few");

	// Negative counts are not a thing a user sees, and a rule that crashed or
	// returned a category outside the enum on one would be a crash in a panel
	// nobody expected.
	same(l.plural_of(-3), IvoryLang::FEW, "a negative count uses its size");
}

static void test_other_plurals() {
	std::printf("plural categories elsewhere\n");
	IvoryLang l;
	l.set_tongue(IvoryLang::EN);
	same(l.plural_of(1), IvoryLang::ONE, "English: 1 is one");
	same(l.plural_of(0), IvoryLang::OTHER, "English: 0 takes the plural");
	same(l.plural_of(2), IvoryLang::OTHER, "English: 2 is other");

	l.set_tongue(IvoryLang::JA);
	same(l.plural_of(1), IvoryLang::OTHER, "Japanese has one form");
	same(l.plural_of(7), IvoryLang::OTHER, "and it is the same for seven");

	l.set_tongue(IvoryLang::DE);
	same(l.plural_of(1), IvoryLang::ONE, "German: 1 is one");
	same(l.plural_of(0), IvoryLang::OTHER, "German: 0 is other");
}

// ------------------------------------------------------- digits and bidi

static void test_digits() {
	std::printf("digits\n");
	IvoryLang en;
	en.set_tongue(IvoryLang::EN);
	ok(en.digits(String("24 fps")).length() == 6,
			"English digits are left alone");

	IvoryLang ar;
	ar.set_tongue(IvoryLang::AR);
	// Length is preserved: one Western digit becomes exactly one Eastern
	// one, and the words between them are untouched.
	String got = ar.digits(String("1920 x 1080"));
	same(got.length(), 11, "converting digits does not change the length");
	// The first character is now U+0661, and the space after the fourth is
	// still a space — which is the whole of "the words are left alone".
	ok(got[0] == (char32_t)0x0661, "1 became the Eastern one");
	ok(got[4] == U' ', "the space between is untouched");
	ok(got[5] == U'x', "and so is the letter");
}

static void test_bidi() {
	std::printf("directional isolation\n");
	ok(!IvoryLang::has_rtl(String("Frame 3 of 48")),
			"plain English has no right-to-left run");
	String arabic;
	arabic += String::chr((char32_t)0x0627); // alef
	arabic += String::chr((char32_t)0x0644); // lam
	ok(IvoryLang::has_rtl(arabic), "Arabic letters are found");

	// Arabic-Indic digits are *not* a strong direction — their bidi class is
	// AN, which is weak. Treating them as strong is what stopped numbers in
	// Arabic sentences from being isolated, which was the whole point.
	String eastern;
	eastern += String::chr((char32_t)0x0664);
	eastern += String::chr((char32_t)0x0668);
	ok(!IvoryLang::has_rtl(eastern),
			"Eastern digits are not a strong direction");

	String wrapped = IvoryLang::isolate(String("48"));
	same(wrapped.length(), 4, "isolating adds exactly two characters");
	ok(wrapped[0] == (char32_t)0x2068, "opened with first-strong isolate");
	ok(wrapped[3] == (char32_t)0x2069, "closed with pop");
	ok(IvoryLang::isolate(String("")).length() == 0,
			"isolating nothing adds nothing");
}

static void test_fill() {
	std::printf("filling a sentence\n");
	IvoryLang en;
	en.set_tongue(IvoryLang::EN);
	PackedStringArray args;
	args.append(String("3"));
	args.append(String("48"));
	String got = en.fill(String("Frame {0} of {1}"), args);
	same(got.length(), (int)std::string("Frame 3 of 48").size(),
			"both placeholders were replaced");

	// A value containing what looks like another placeholder. Replacing one
	// at a time would find "{1}" inside the text just substituted for {0} and
	// replace it again — the single pass never looks at what it has written.
	PackedStringArray tricky;
	tricky.append(String("{1}"));
	tricky.append(String("second"));
	String out = en.fill(String("[{0}][{1}]"), tricky);
	same(out.length(), (int)std::string("[{1}][second]").size(),
			"a value that looks like a placeholder is not re-substituted");

	// Missing arguments print nothing rather than the literal braces. A
	// caller that passed too few has a bug, and showing "{2}" to a user is a
	// worse way to report it than showing a gap.
	PackedStringArray few;
	few.append(String("x"));
	String thin = en.fill(String("a{0}b{1}c"), few);
	same(thin.length(), 4, "a missing argument leaves a gap, not braces");

	// Text that is not a placeholder is left exactly alone.
	same(en.fill(String("100% {sure}"), args).length(), 11,
			"braces round a word are not a placeholder");

	// In Arabic each Western value is isolated, so the result grows by two
	// characters per substitution.
	IvoryLang ar;
	ar.set_tongue(IvoryLang::AR);
	String ar_out = ar.fill(String("{0}-{1}"), args);
	// "3" and "48" become Eastern digits, each wrapped in two marks:
	// 1 + 2 + 1 + 2 + 2 = 8.
	same(ar_out.length(), 8, "each value is wrapped in an isolate");
}

// ------------------------------------------------- checking a translation

static void test_faults() {
	std::printf("faults in a translation row\n");
	same(IvoryLang::fault_of(String("Brush"), String("الفرشاة")),
			IvoryLang::FAULT_NONE, "a good row has no faults");
	same(IvoryLang::fault_of(String("Brush"), String("")),
			IvoryLang::FAULT_EMPTY, "an empty row");
	same(IvoryLang::fault_of(String("Brush"), String("Brush")),
			IvoryLang::FAULT_UNTRANSLATED, "a row left as the English");

	// The placeholder faults, which are the ones that reach a user as
	// visible nonsense rather than as English.
	ok((IvoryLang::fault_of(String("Frame {0} of {1}"),
			String("Cuadro {0}")) & IvoryLang::FAULT_PLACEHOLDERS) != 0,
			"a row that lost a placeholder");
	ok((IvoryLang::fault_of(String("Frame {0}"),
			String("Cuadro {0} de {1}")) & IvoryLang::FAULT_PLACEHOLDERS) != 0,
			"a row that gained one");
	ok((IvoryLang::fault_of(String("Frame {0} of {1}"),
			String("Cuadro {0} de {1}")) & IvoryLang::FAULT_PLACEHOLDERS) == 0,
			"a row that kept both");

	// Length, generously: this is for the row pasted into the wrong cell,
	// which is off by a factor of ten, not for German being long.
	ok((IvoryLang::fault_of(String("Undo the last thing"), String("Zurueck"))
			& IvoryLang::FAULT_LENGTH) == 0,
			"a shorter translation is not a fault by itself");
	ok((IvoryLang::fault_of(String("Undo the last thing"),
			String("a")) & IvoryLang::FAULT_LENGTH) != 0,
			"one letter for a sentence is");
}

// ------------------------------------------------------------- the layout

static Rect2 box(double x, double y, double w, double h) {
	return Rect2((real_t)x, (real_t)y, (real_t)w, (real_t)h);
}

static void test_layout_separates() {
	std::printf("nothing overlaps after resolving\n");
	IvoryLayout l;
	Array boxes;
	// Five buttons piled nearly on top of each other, which is what a rail
	// laid out for a wide screen looks like on a narrow one.
	boxes.append(box(100, 100, 60, 44));
	boxes.append(box(110, 105, 60, 44));
	boxes.append(box(120, 110, 60, 44));
	boxes.append(box(105, 130, 60, 44));
	boxes.append(box(130, 90, 60, 44));
	l.set_boxes(boxes, PackedInt32Array());
	l.set_margin(6.0);
	ok(l.tangled(), "they start tangled");
	l.resolve(24);
	ok(!l.tangled(), "and are not tangled afterwards");
	ok(l.collisions().size() == 0, "the collision list is empty");
}

static void test_layout_pinned() {
	std::printf("a pinned control does not move\n");
	IvoryLayout l;
	Array boxes;
	boxes.append(box(200, 200, 80, 44));   // pinned: a panel under its button
	boxes.append(box(210, 210, 80, 44));
	boxes.append(box(190, 190, 80, 44));
	PackedInt32Array pinned;
	pinned.append(0);
	l.set_boxes(boxes, pinned);
	l.set_margin(8.0);
	l.resolve(24);
	Rect2 first = l.box(0);
	ok((double)first.position.x == 200.0 && (double)first.position.y == 200.0,
			"the pinned one is exactly where it was");
	ok(!l.tangled(), "and nothing overlaps");
}

static void test_layout_bounds() {
	std::printf("nothing is pushed off the screen\n");
	IvoryLayout l;
	Array boxes;
	// Six buttons crammed into a corner, so resolving them wants to push
	// several off the left and top edges.
	for (int i = 0; i < 6; i++) {
		boxes.append(box(10 + i * 2, 10 + i * 2, 70, 44));
	}
	l.set_boxes(boxes, PackedInt32Array());
	l.set_margin(6.0);
	l.set_bounds(box(0, 0, 400, 700));
	l.resolve(24);
	bool inside = true;
	for (int i = 0; i < 6; i++) {
		Rect2 r = l.box(i);
		if (r.position.x < -0.01 || r.position.y < -0.01
				|| r.position.x + r.size.x > 400.01
				|| r.position.y + r.size.y > 700.01) {
			inside = false;
		}
	}
	ok(inside, "every control is still on the screen");
}

static void test_touch() {
	std::printf("which control a finger meant\n");
	IvoryLayout l;
	Array boxes;
	boxes.append(box(0, 0, 50, 44));
	boxes.append(box(70, 0, 50, 44));
	l.set_boxes(boxes, PackedInt32Array());
	same(l.touched(Vector2(25, 20), 0.0), 0, "a touch inside the first");
	same(l.touched(Vector2(95, 20), 0.0), 1, "a touch inside the second");
	same(l.touched(Vector2(200, 200), 0.0), -1, "a touch on neither");

	// In the gap. With no slop it belongs to nobody; with slop it goes to the
	// nearer one, which is what stops a near miss reading as a dead button.
	same(l.touched(Vector2(60, 20), 0.0), -1, "the gap belongs to nobody");
	same(l.touched(Vector2(58, 20), 12.0), 0, "with slop, to the nearer one");
	same(l.touched(Vector2(64, 20), 12.0), 1, "and on the other side, to it");

	// Overlapping controls: the one whose centre is nearer wins, rather than
	// whichever happens to come first in the list.
	IvoryLayout o;
	Array two;
	two.append(box(0, 0, 100, 44));
	two.append(box(80, 0, 100, 44));
	o.set_boxes(two, PackedInt32Array());
	same(o.touched(Vector2(90, 20), 0.0), 0,
			"in the overlap, nearer the first centre");
	same(o.touched(Vector2(130, 20), 0.0), 1,
			"further along, the second");
}

static void test_layout_degenerate() {
	std::printf("layouts that should not crash\n");
	IvoryLayout l;
	same(l.resolve(8), 0, "resolving nothing does nothing");
	same(l.touched(Vector2(1, 1), 4.0), -1, "and nothing is under a finger");
	ok(!l.tangled(), "an empty layout is not tangled");

	Array one;
	one.append(box(0, 0, 10, 10));
	l.set_boxes(one, PackedInt32Array());
	same(l.resolve(8), 0, "one control cannot overlap anything");

	// Two identical rectangles, both pinned: nothing can be done, and saying
	// so beats moving one anyway.
	IvoryLayout stuck;
	Array same_place;
	same_place.append(box(5, 5, 40, 40));
	same_place.append(box(5, 5, 40, 40));
	PackedInt32Array both;
	both.append(0);
	both.append(1);
	stuck.set_boxes(same_place, both);
	stuck.resolve(8);
	ok((double)stuck.box(0).position.x == 5.0
			&& (double)stuck.box(1).position.x == 5.0,
			"two pinned controls are left where they are");
}

int main() {
	std::printf("\nlanguage and layout\n===================\n\n");
	test_arabic_plurals();
	test_other_plurals();
	test_digits();
	test_bidi();
	test_fill();
	test_faults();
	test_layout_separates();
	test_layout_pinned();
	test_layout_bounds();
	test_touch();
	test_layout_degenerate();
	std::printf("\n%d checks, %d failures\n\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
