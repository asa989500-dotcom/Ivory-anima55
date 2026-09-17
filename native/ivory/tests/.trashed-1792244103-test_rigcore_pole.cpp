#include "ivory_rigcore.h"
#include <cstdio>
#include <cmath>
#include <algorithm>

using namespace godot;
static int checks=0, failures=0;
static void ok(bool v,const char *m){++checks;if(!v){++failures;std::printf("FAIL: %s\n",m);}}
static double dist(const Vector2&a,const Vector2&b){return (double)a.distance_to(b);}

int main(){
    IvoryRigCore r;
    PackedVector2Array h,t; PackedInt32Array p;
    // 4-link chain: 0->1->2->3.
    h.append(Vector2(0,0)); t.append(Vector2(80,0)); p.append(-1);
    h.append(Vector2(80,0)); t.append(Vector2(150,25)); p.append(0);
    h.append(Vector2(150,25)); t.append(Vector2(210,5)); p.append(1);
    h.append(Vector2(210,5)); t.append(Vector2(260,45)); p.append(2);
    ok(r.set_skeleton(h,t,p),"skeleton accepted");
    PackedVector2Array heads=r.heads(), tails=r.tails();
    ok(heads.size()==4 && tails.size()==4,"four-link geometry retained");

    r.set_ik_target(3, Vector2(205,110), Vector2(40,150), 1.0, false, 0.0);
    Dictionary rep=r.solve(24);
    ok(bool(rep["ok"]),"solve stayed numerically valid");
    heads=r.heads(); tails=r.tails();
    double worst_joint=0;
    for(int i=1;i<4;i++) worst_joint=std::max(worst_joint,dist(heads[i],tails[i-1]));
    ok(worst_joint<1e-3,"adjacent joints remain closed after pole solve");

    PackedFloat32Array lens=r.lengths();
    double worst_len=0;
    for(int i=0;i<4;i++) worst_len=std::max(worst_len,std::abs(dist(heads[i],tails[i])-(double)lens[i]));
    ok(worst_len<1e-3,"bone lengths are preserved by pole projection");

    // A target on the other side must be allowed to cross, but the pole keeps
    // the bend on the chosen side instead of a one-frame mirror flip.
    r.set_ik_target(3, Vector2(205,-110), Vector2(40,-150), 1.0, false, 0.0);
    r.solve(24);
    heads=r.heads(); tails=r.tails();
    worst_joint=0;
    for(int i=1;i<4;i++) worst_joint=std::max(worst_joint,dist(heads[i],tails[i-1]));
    ok(worst_joint<1e-3,"joint closure survives a pole-side change");

    std::printf("RigCore pole/long-chain: %d checks, %d failures\n",checks,failures);
    return failures==0?0:1;
}
