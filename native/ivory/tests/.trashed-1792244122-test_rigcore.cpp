#include "../src/ivory_rigcore.h"
#include <cassert>
#include <cmath>
using namespace godot;
int main(){
 IvoryRigCore r; PackedVector2Array h,t; PackedInt32Array p;
 h.resize(3);t.resize(3);p.resize(3);
 h[0]=Vector2(0,0);t[0]=Vector2(100,0);p[0]=-1;
 h[1]=Vector2(100,0);t[1]=Vector2(180,0);p[1]=0;
 h[2]=Vector2(180,0);t[2]=Vector2(240,0);p[2]=1;
 assert(r.set_skeleton(h,t,p));
 r.set_ik_target(2,Vector2(140,80),Vector2(0,100),1.0,false,0.0);
 auto d=r.solve(24);assert((bool)d["ok"]);auto a=r.heads();auto b=r.tails();
 for(int i=0;i<3;i++){assert(std::isfinite((double)a[i].x));assert(std::isfinite((double)b[i].y));}
 auto v=r.validate();assert((bool)v["ok"]);
 auto st=r.stress_test(100,10000,7);assert((bool)st["ok"]);
 return 0;
}
