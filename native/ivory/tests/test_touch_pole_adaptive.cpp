#include "../src/ivory_bone.h"
#include <cstdio>
#include <cmath>
#include <algorithm>
using namespace godot;
static int checks=0,failures=0;
static void ok(bool v,const char*m){++checks;if(!v){++failures;std::printf("FAIL: %s\n",m);}}
static double d(Vector2 a,Vector2 b){return std::sqrt((double)(a-b).length_squared());}
int main(){
 IvoryBone r; PackedVector2Array h,t; PackedInt32Array p;
 h.append(Vector2(0,0));t.append(Vector2(100,0));p.append(-1);
 h.append(Vector2(100,0));t.append(Vector2(180,0));p.append(0);
 h.append(Vector2(180,0));t.append(Vector2(240,0));p.append(1);
 r.set_skeleton(h,t,p);
 ok(r.bone_count()==3,"3 bone chain");
 r.reach_pole(1,Vector2(150,60),Vector2(100,100),8);
 auto a=r.head(); auto b=r.tail(); auto L=r.lengths();
 ok(std::isfinite((double)b[1].x),"finite elbow");
 ok(std::abs(d(a[0],b[0])-L[0])<1e-4,"upper length preserved");
 ok(std::abs(d(a[1],b[1])-L[1])<1e-4,"lower length preserved");
 ok(d(b[0],a[1])<1e-5,"joint closed");
 double side=((double)(b[0]-a[0]).cross(Vector2(100,100)-a[0]));
 ok(side>0,"pole selects stable bend side");
 // Near-collinear pole: must not chatter to the other side.
 Vector2 old_elbow=b[0];
 for(int i=0;i<50;i++){ double y=(i%2==0)?0.2:-0.2; r.reach_pole(1,Vector2(179.8,y),Vector2(100,y),4); auto aa=r.head(),bb=r.tail(); ok(d(bb[0],aa[1])<1e-5,"joint remains closed during jitter"); ok(std::abs(d(aa[0],bb[0])-L[0])<1e-4,"upper remains rigid during jitter"); }
 // Long reach remains finite and bounded.
 r.reach_pole(2,Vector2(500,30),Vector2(100,100),8); a=r.head();b=r.tail();
 for(int i=0;i<3;i++){ok(std::isfinite((double)a[i].x)&&std::isfinite((double)b[i].y),"long chain finite");ok(std::abs(d(a[i],b[i])-L[i])<1e-3,"long chain length");}
 std::printf("Touch pole adaptive C++: %d checks, %d failures\n",checks,failures); return failures?1:0;
}
