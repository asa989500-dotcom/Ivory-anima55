#include "ivory_animation.h"
#include <cstdio>
#include <cmath>

using namespace godot;
static int checks=0, failures=0;
static void ok(bool v,const char*m){++checks;if(!v){++failures;std::printf("FAIL: %s\n",m);}}
static float norm(float a){while(a>3.14159265f)a-=6.2831853f;while(a<=-3.14159265f)a+=6.2831853f;return a;}

int main(){
    IvoryAnimation a;
    PackedFloat32Array from,to;
    from.append(3.05f); to.append(-3.05f);
    a.begin_angle_blend(from,to,1.0);
    PackedFloat32Array mid=a.sample(0.5);
    ok(std::abs(norm(mid[0]) - 3.14159265f) < 0.2f,
            "angle interpolation takes the short path across +/-pi");
    a.update(2.0);
    ok(!a.blending() && std::abs(norm(a.sample(1.0)[0] + 3.05f)) < 0.01f,
            "blend reaches its target and stops");

    a.clear_events();
    Dictionary empty;
    ok(a.add_event(3,"hit",empty),"first event accepted");
    ok(a.add_event(7,"sound",empty),"second event accepted");
    ok(a.events_between(2,5,0,10,false).size()==1,"forward event crossing is exclusive at the start");
    ok(a.events_between(8,1,0,10,true).size()==0,
            "wrapped event range honours the requested authored frames");

    std::printf("IvoryAnimation: %d checks, %d failures\n",checks,failures);
    return failures==0?0:1;
}
