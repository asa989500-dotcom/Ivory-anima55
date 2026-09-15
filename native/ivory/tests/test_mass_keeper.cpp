#include "ivory_mass_keeper.h"
#include <cstdio>
#include <cmath>
using namespace godot;

static int checks=0, failures=0;
static void ok(bool v,const char *m){++checks; if(!v){++failures; std::printf("FAIL: %s\n",m);}}
static PackedVector2Array pts(float s=1.0f){PackedVector2Array p; p.append(Vector2(0,0));p.append(Vector2(s,0));p.append(Vector2(0,s));p.append(Vector2(s,s));return p;}
int main(){
 IvoryMassKeeper k; k.configure();
 auto r=pts(); PackedInt32Array tri; tri.append(0);tri.append(1);tri.append(2);tri.append(1);tri.append(3);tri.append(2);
 auto q=r; q[1]=Vector2(1.0,0.05); q[2]=Vector2(-0.03,1.0); q[3]=Vector2(1.02,1.06);
 PackedVector2Array ba,bb; ba.append(Vector2(-.2,.5)); bb.append(Vector2(.5,.5)); ba.append(Vector2(.5,-.2)); bb.append(Vector2(.5,1.2));
 auto fixed=k.preserve_joint_mass(q,r,tri,ba,bb,.9,3);
 ok(fixed.size()==r.size(),"mass output size");
 auto rep=k.inspect(fixed,r,tri); ok(bool(rep.get("ok",false)),"mass inspect passes");
 ok(double(rep.get("min_area_ratio",0.0))>0.30,"area not collapsed");
 ok(double(rep.get("max_area_ratio",0.0))<2.20,"area not explosively expanded");

 PackedInt32Array b; PackedFloat32Array w; b.append(4);w.append(.9f);b.append(2);w.append(.2f);b.append(-1);w.append(.4f);b.append(3);w.append(NAN);
 auto sw=k.sanitize_weights(b,w,1,2); ok(bool(sw.get("ok",false)),"weights accepted after sanitation");
 PackedFloat32Array wb = sw.get("weights",PackedFloat32Array()); PackedInt32Array bb2 = sw.get("bones",PackedInt32Array());
 ok(wb.size()==2,"weight influence cap");
 ok(std::fabs(double(wb[0]+wb[1])-1.0)<1e-5,"weights normalized");
 ok(bb2[0]>=0 && bb2[1]>=0,"weight indices valid");

 ok(k.within_stretch(1.0,1.0),"unit stretch valid");
 ok(k.within_stretch(1.34,1.0),"upper stretch valid");
 ok(!k.within_stretch(1.50,1.0),"overshoot stretch blocked");
 ok(k.within_stretch(.75,1.0),"lower stretch valid");
 ok(!k.within_stretch(.60,1.0),"undershoot stretch blocked");
 ok(k.within_stretch(2.0,2.0),"scaled rest stretch valid");
 ok(k.within_stretch(0.0,1.0)==false,"zero length stretch blocked");
 ok(!k.within_stretch(NAN,1.0),"NaN stretch blocked");
 ok(int(rep.get("triangles",0))==2,"triangle count stable");
 ok(double(rep.get("min_edge_ratio",0.0))>0.30,"edge stability retained");
 std::printf("IvoryMassKeeper: %d checks, %d failures\n",checks,failures);
 return failures?1:0;
}
