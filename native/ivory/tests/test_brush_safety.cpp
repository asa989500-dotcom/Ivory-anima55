#include "ivory_brush_safety.h"
#include <cstdio>

using ivory::BrushSafety13;
static int checks = 0;
static int failures = 0;

static void ok(bool condition, const char *what) {
    ++checks;
    if (!condition) { ++failures; std::printf("FAIL: %s\n", what); }
}
static void test_numeric_domain() {
    ok(BrushSafety13::finite(1.0), "finite values accepted");
    ok(!BrushSafety13::finite(std::numeric_limits<double>::quiet_NaN()), "NaN rejected");
    ok(BrushSafety13::finite_point(2.0, 3.0), "finite points accepted");
    ok(!BrushSafety13::finite_point(2.0, std::numeric_limits<double>::infinity()), "infinite point rejected");
}
static void test_stamp_contract() {
    ok(BrushSafety13::positive_size(96), "normal stamp size accepted");
    ok(!BrushSafety13::positive_size(4), "tiny stamp rejected");
    ok(!BrushSafety13::positive_size(4096), "oversize stamp rejected");
    ok(BrushSafety13::valid_variant(4), "last variant accepted");
    ok(!BrushSafety13::valid_variant(5), "unknown variant rejected");
    ok(BrushSafety13::valid_stamp_request(128, 2), "valid stamp request accepted");
}
static void test_stroke_parameters() {
    ok(BrushSafety13::valid_opacity(0.5), "opacity accepted");
    ok(!BrushSafety13::valid_opacity(1.1), "opacity overflow rejected");
    ok(BrushSafety13::valid_pressure(0.0), "zero pressure accepted");
    ok(!BrushSafety13::valid_pressure(-0.1), "negative pressure rejected");
    ok(BrushSafety13::valid_spacing(1.0), "spacing accepted");
    ok(!BrushSafety13::valid_spacing(0.01), "spacing underflow rejected");
    ok(BrushSafety13::valid_radius(40.0), "radius accepted");
}
static void test_page_and_sequence() {
    ok(BrushSafety13::inside_page(20.0, 30.0, 100.0, 100.0), "point inside page accepted");
    ok(!BrushSafety13::inside_page(-1.0, 30.0, 100.0, 100.0), "point outside page rejected");
    ok(BrushSafety13::bounded_count(100), "reasonable point count accepted");
    ok(!BrushSafety13::bounded_count(0), "empty stream rejected");
    ok(BrushSafety13::monotonic_time(10.0, 10.0), "equal timestamps accepted");
    ok(!BrushSafety13::monotonic_time(10.0, 9.0), "backward timestamp rejected");
}
static void test_state_and_layer() {
    ok(BrushSafety13::no_reentry(false, true), "new stroke accepted");
    ok(!BrushSafety13::no_reentry(true, true), "reentrant stroke rejected");
    ok(BrushSafety13::paintable_layer(true, false, true), "paintable layer accepted");
    ok(!BrushSafety13::paintable_layer(true, true, true), "locked layer rejected");
    ok(!BrushSafety13::paintable_layer(false, false, true), "hidden layer rejected");
    ok(!BrushSafety13::paintable_layer(true, false, false), "missing surface rejected");
}
int main() {
    test_numeric_domain();
    test_stamp_contract();
    test_stroke_parameters();
    test_page_and_sequence();
    test_state_and_layer();
    std::printf("%d checks, %d failures\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
