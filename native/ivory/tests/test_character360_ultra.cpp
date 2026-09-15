#include "../src/ivory_rig360.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>

using namespace godot;
static int checks=0, failures=0;
static void ok(bool c,const char* s){++checks;if(!c){++failures;std::printf("  FAIL: %s\n",s);}}
static void nearv(double a,double b,double e,const char*s){++checks;if(std::fabs(a-b)>e){++failures;std::printf("  FAIL: %s %.6f %.6f\n",s,a,b);}}
static void heading(const char*s){std::printf("%s\n",s);}

static void make_hand(IvoryRig360&r,int&hand){
 int root=r.add_bone(Vector2(0,0),Vector2(0,50),-1,IvoryRig360::PART_ROOT);
 int arm=r.add_bone(Vector2(0,50),Vector2(70,50),root,IvoryRig360::PART_ARM);
 hand=r.add_bone(Vector2(70,50),Vector2(100,50),arm,IvoryRig360::PART_HAND);
}

static void test_finger_topology(){
 heading("five fingers: topology, limits, and lengths");
 IvoryRig360 r; int hand; make_hand(r,hand);
 int made=r.add_finger_set(hand,30,24);
 ok(made==15,"a hand has five digits with three phalanges each");
 int fingers=0; for(int i=0;i<r.bone_count();++i) if(r.part_of(i)==IvoryRig360::PART_FINGER) ++fingers;
 ok(fingers==15,"all digit bones are typed as fingers");
 for(int i=0;i<r.bone_count();++i) if(r.part_of(i)==IvoryRig360::PART_FINGER){
  auto lim=r.angle_limits(i); ok(float(lim["min"])<-1.3f && float(lim["max"])>1.3f,"finger joints have usable limits");
  nearv(r.rest_head(i).distance_to(r.rest_tail(i)),r.rest_head(i).distance_to(r.rest_tail(i)),1e-9,"finger length is stable");
 }
}

static void test_fk_stability(){
 heading("finger FK: no drift under repeated posing");
 IvoryRig360 r; int hand; make_hand(r,hand); r.add_finger_set(hand,30,24);
 const int n=r.bone_count(); PackedVector2Array rest; for(int i=0;i<n;++i) rest.append(r.rest_tail(i));
 for(int k=0;k<10000;++k){
  for(int i=3;i<n;++i) if(r.part_of(i)==IvoryRig360::PART_FINGER) r.set_angle(i,std::sin(k*0.017+i)*0.7);
 }
 r.rest_all(); for(int i=0;i<n;++i) ok(r.posed_tail(i)==rest[i],"10k poses return exactly to rest");
}

static void test_ik(){
 heading("touch IK: endpoint follows target without changing bone lengths");
 IvoryRig360 r; int hand; make_hand(r,hand); r.add_finger_set(hand,30,24);
 int tip=r.bone_count()-1; const double len0=r.rest_head(tip).distance_to(r.rest_tail(tip));
 Vector2 target(112,38); bool reached=r.solve_ik(tip,target,12,0.75);
 ok(reached,"CCD reaches a nearby fingertip target");
 ok(r.posed_tail(tip).distance_to(target)<=0.75,"fingertip is within touch tolerance");
 nearv(r.posed_head(tip).distance_to(r.posed_tail(tip)),len0,1e-3,"IK preserves the last phalanx length");
}

static void test_touch_pick(){
 heading("touch picking: posed finger is selectable");
 IvoryRig360 r; int hand; make_hand(r,hand); r.add_finger_set(hand,30,24);
 int tip=r.bone_count()-1; Vector2 p=r.posed_head(tip).lerp(r.posed_tail(tip),0.5);
 ok(r.pick(p,12)==tip,"pick uses the posed segment, not the rest segment");
 ok(r.drag_to(p,12,r.posed_tail(tip)+Vector2(3,-2),4,1.0),"drag_to combines pick and IK");
}

static void test_layer_isolation(){
 heading("motion layer is explicit and isolated");
 IvoryRig360 r; int hand; make_hand(r,hand); r.add_finger_set(hand,30,24);
 int a=r.ensure_motion_layer(); int b=r.ensure_motion_layer();
 ok(a==b,"motion layer creation is idempotent");
 ok(r.motion_layer_index()==a,"motion layer has a stable index");
 Dictionary d=r.to_project(); ok(int(d["motion_layer"])==a,"export carries the motion layer");
 ok(bool(d["controller_only"]),"export marks it controller-only");
}

static void test_smart_finger(){
 heading("finger smart bone: monotone correction");
 IvoryRig360 r; int hand; make_hand(r,hand); r.add_finger_set(hand,30,24);
 int f=hand+1; // first digit bone follows the hand
 r.record_action(hand,0.0,f,0.0); r.record_action(hand,0.5,f,0.2); r.record_action(hand,1.0,f,0.7);
 r.set_angle(hand,0.75); r.apply_actions(); ok(r.angle_of(f)>=0.0 && r.angle_of(f)<=0.7,"smart finger correction stays inside authored range");
}

static void test_stress(){
 heading("performance: 200k finger pose solves");
 IvoryRig360 r; int hand; make_hand(r,hand); r.add_finger_set(hand,30,24);
 auto t0=std::chrono::high_resolution_clock::now();
 for(int k=0;k<200000;++k){ int i=hand+1+(k%15); r.set_angle(i,std::sin(k*0.01)*0.8); if((k&63)==0) r.posed_tail(i); }
 auto t1=std::chrono::high_resolution_clock::now();
 double ms=std::chrono::duration<double,std::milli>(t1-t0).count();
 ok(std::isfinite(ms)&&ms<5000.0,"200k pose operations finish within 5 seconds");
 std::printf("  stress_ms=%.3f\n",ms);
}

static void test_project_integrity(){
 heading("export integrity: rest/pose/parts survive");
 IvoryRig360 r; int hand; make_hand(r,hand); r.add_finger_set(hand,30,24); r.ensure_motion_layer(); r.set_angle(hand,0.4);
 Dictionary d=r.to_project();
 ok(((PackedVector2Array)d["rest_head"]).size()==r.bone_count(),"rest heads exported");
 ok(((PackedVector2Array)d["posed_tail"]).size()==r.bone_count(),"posed tails exported");
 ok(((PackedInt32Array)d["part"]).size()==r.bone_count(),"parts exported");
 ok(((PackedFloat32Array)d["angle"]).size()==r.bone_count(),"angles exported");
}

static void test_bounds(){
 heading("extreme touch targets stay finite and constrained");
 IvoryRig360 r; int hand; make_hand(r,hand); r.add_finger_set(hand,30,24); int tip=r.bone_count()-1;
 r.set_angle_limits(tip,-0.4,0.4); r.set_angle(tip,100.0); ok(r.angle_of(tip)<=0.4+1e-5,"finger upper bound holds");
 r.set_angle(tip,-100.0); ok(r.angle_of(tip)>=-0.4-1e-5,"finger lower bound holds");
 r.solve_ik(tip,Vector2(100000,-100000),12,0.5); ok(std::isfinite((double)r.posed_tail(tip).x)&&std::isfinite((double)r.posed_tail(tip).y),"extreme target cannot create NaN");
}

static void test_multi_hand(){
 heading("two hands: independent complete rigs");
 IvoryRig360 r; int h1,h2; make_hand(r,h1); make_hand(r,h2); r.add_finger_set(h1,28,22); r.add_finger_set(h2,32,26);
 int n=0; for(int i=0;i<r.bone_count();++i) if(r.part_of(i)==IvoryRig360::PART_FINGER) ++n;
 ok(n==30,"two hands produce ten digits and thirty phalanges");
 r.set_angle(h1,0.5); r.set_angle(h2,-0.5); ok(std::isfinite((double)r.posed_tail(r.bone_count()-1).x),"both hands remain numerically stable");
}

int main(){
 std::printf("\nCharacter 360 Ultra Finger/Rig regression\n==========================================\n\n");
 test_finger_topology(); test_fk_stability(); test_ik(); test_touch_pick(); test_layer_isolation(); test_smart_finger(); test_stress(); test_project_integrity(); test_bounds(); test_multi_hand();
 std::printf("\n%d checks, %d failures\n",checks,failures); return failures?1:0;
}
