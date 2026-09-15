#include "../src/ivory_touch.h"
#include <cstdio>
#include <cmath>
using namespace godot;
int main(){ IvoryTouch t; t.configure(1.35,0.018,1.6,3.5,0.8); t.reset();
 double now=0; Vector2 p(100,100); t.filter(p,now);
 for(int i=1;i<=120;i++){ now=i/120.0; double n=(i%2?0.2:-0.2); t.filter(Vector2(100+n,100-n),now); }
 auto m=t.metrics(); bool ok=(bool)m["stable"] && (int)m["samples"]>100 && std::isfinite((double)m["jitter_rms_px"]);
 std::printf("Touch metrics C++: samples=%d jitter=%.4f max_speed=%.3f stable=%s\n",(int)m["samples"],(double)m["jitter_rms_px"],(double)m["max_speed_px_s"],ok?"true":"false"); return ok?0:1; }
