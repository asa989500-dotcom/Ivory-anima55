#include "ivory_rigcore.h"
#include <algorithm>
#include <cmath>
#include <limits>

namespace godot {
static constexpr double EPS=1e-8, PI=3.14159265358979323846, TAU=6.2831853071795864769;
static constexpr double MAX_ABS=1.0e7;

double IvoryRigCore::finite(double v,double f){ return std::isfinite(v)?std::clamp(v,-MAX_ABS,MAX_ABS):f; }
Vector2 IvoryRigCore::finite_vec(const Vector2 &v,const Vector2 &f){ return Vector2((real_t)finite(v.x,f.x),(real_t)finite(v.y,f.y)); }
double IvoryRigCore::wrap(double a){ a=std::fmod(finite(a),TAU); if(a>PI)a-=TAU; if(a<=-PI)a+=TAU; return a; }
Vector2 IvoryRigCore::rest_dir(int i) const { Vector2 d=rest_t_[i]-rest_h_[i]; if(d.length_squared()<EPS)return Vector2(1,0); return d.normalized(); }

void IvoryRigCore::_bind_methods(){
 ClassDB::bind_method(D_METHOD("set_skeleton","head","tail","parent"),&IvoryRigCore::set_skeleton);
 ClassDB::bind_method(D_METHOD("set_rest_pose"),&IvoryRigCore::set_rest_pose);
 ClassDB::bind_method(D_METHOD("reset_pose"),&IvoryRigCore::reset_pose);
 ClassDB::bind_method(D_METHOD("set_local_angles","angles"),&IvoryRigCore::set_local_angles);
 ClassDB::bind_method(D_METHOD("local_angles"),&IvoryRigCore::local_angles);
 ClassDB::bind_method(D_METHOD("set_local_scales","scales"),&IvoryRigCore::set_local_scales);
 ClassDB::bind_method(D_METHOD("local_scales"),&IvoryRigCore::local_scales);
 ClassDB::bind_method(D_METHOD("set_depths","depths"),&IvoryRigCore::set_depths);
 ClassDB::bind_method(D_METHOD("depths"),&IvoryRigCore::depths);
 ClassDB::bind_method(D_METHOD("set_angle_limits","min_angle","max_angle"),&IvoryRigCore::set_angle_limits);
 ClassDB::bind_method(D_METHOD("set_stretch","bone","min_ratio","max_ratio"),&IvoryRigCore::set_stretch);
 ClassDB::bind_method(D_METHOD("set_ik_target","end_bone","target","pole","weight","stretch","soft"),&IvoryRigCore::set_ik_target);
 ClassDB::bind_method(D_METHOD("clear_ik","end_bone"),&IvoryRigCore::clear_ik);
 ClassDB::bind_method(D_METHOD("clear_ik_all"),&IvoryRigCore::clear_ik_all);
 ClassDB::bind_method(D_METHOD("set_ik_fk_blend","bone","ik_weight"),&IvoryRigCore::set_ik_fk_blend);
 ClassDB::bind_method(D_METHOD("solve","iterations"),&IvoryRigCore::solve,DEFVAL(16));
 ClassDB::bind_method(D_METHOD("heads"),&IvoryRigCore::heads); ClassDB::bind_method(D_METHOD("tails"),&IvoryRigCore::tails);
 ClassDB::bind_method(D_METHOD("world_angles"),&IvoryRigCore::world_angles); ClassDB::bind_method(D_METHOD("world_depth"),&IvoryRigCore::world_depth);
 ClassDB::bind_method(D_METHOD("parents"),&IvoryRigCore::parents); ClassDB::bind_method(D_METHOD("lengths"),&IvoryRigCore::lengths);
 ClassDB::bind_method(D_METHOD("to_space","bone","world","space"),&IvoryRigCore::to_space); ClassDB::bind_method(D_METHOD("from_space","bone","value","space"),&IvoryRigCore::from_space);
 ClassDB::bind_method(D_METHOD("set_weights","bones","weights","point_count","max_influences"),&IvoryRigCore::set_weights,DEFVAL(4));
 ClassDB::bind_method(D_METHOD("skin","rest_points"),&IvoryRigCore::skin); ClassDB::bind_method(D_METHOD("normalize_weights"),&IvoryRigCore::normalize_weights);
 ClassDB::bind_method(D_METHOD("set_corrective","offsets","weight"),&IvoryRigCore::set_corrective); ClassDB::bind_method(D_METHOD("corrected_points"),&IvoryRigCore::corrected_points);
 ClassDB::bind_method(D_METHOD("validate"),&IvoryRigCore::validate); ClassDB::bind_method(D_METHOD("stress_test","bones","operations","seed"),&IvoryRigCore::stress_test,DEFVAL(100),DEFVAL(10000),DEFVAL(1));
}

bool IvoryRigCore::set_skeleton(const PackedVector2Array &head,const PackedVector2Array &tail,const PackedInt32Array &parent){
 int n=std::min(head.size(),tail.size()); if(n<0)return false;
 rest_h_.resize(n);rest_t_.resize(n);parent_.resize(n);
 for(int i=0;i<n;i++){rest_h_[i]=finite_vec(head[i]);rest_t_[i]=finite_vec(tail[i],rest_h_[i]);int p=(i<parent.size()?parent[i]:-1);parent_[i]=(p>=0&&p<n&&p!=i)?p:-1;}
 for(int i=0;i<n;i++){int x=parent_[i],steps=0;while(x>=0&&steps++<=n){if(x==i){parent_[i]=-1;break;}x=parent_[x];}}
 rest_len_.resize(n); for(int i=0;i<n;i++){double l=(rest_t_[i]-rest_h_[i]).length();rest_len_[i]=(float)(std::isfinite(l)?l:0.0);}
 local_ang_.assign(n,0);world_ang_.assign(n,0);depth_.assign(n,0);local_scale_.assign(n,Vector2(1,1));min_ang_.assign(n,-(float)PI);max_ang_.assign(n,(float)PI);ik_blend_.assign(n,1.0f);stretch_.assign(n,Stretch{});ik_.assign(n,IK{});h_=rest_h_;t_=rest_t_;rebuild();return true;
}
void IvoryRigCore::set_rest_pose(){rest_h_=h_;rest_t_=t_;for(size_t i=0;i<rest_len_.size();++i)rest_len_[i]=(float)(rest_t_[i]-rest_h_[i]).length();std::fill(local_ang_.begin(),local_ang_.end(),0);}
void IvoryRigCore::reset_pose(){h_=rest_h_;t_=rest_t_;std::fill(local_ang_.begin(),local_ang_.end(),0);std::fill(ik_blend_.begin(),ik_blend_.end(),1.0f);fk();}
void IvoryRigCore::set_local_angles(const PackedFloat32Array &a){for(int i=0;i<(int)local_ang_.size();++i)local_ang_[i]=(i<a.size()?wrap(a[i]):0);}
PackedFloat32Array IvoryRigCore::local_angles()const{PackedFloat32Array a;a.resize(local_ang_.size());for(int i=0;i<(int)local_ang_.size();++i)a[i]=(float)local_ang_[i];return a;}
void IvoryRigCore::set_local_scales(const PackedVector2Array &s){for(int i=0;i<(int)local_scale_.size();++i){Vector2 v=i<s.size()?s[i]:Vector2(1,1);local_scale_[i]=Vector2((real_t)std::clamp(finite(v.x,1),0.001,1000.0),(real_t)std::clamp(finite(v.y,1),0.001,1000.0));}}
PackedVector2Array IvoryRigCore::local_scales()const{PackedVector2Array a;a.resize(local_scale_.size());for(int i=0;i<(int)local_scale_.size();++i)a[i]=local_scale_[i];return a;}
void IvoryRigCore::set_depths(const PackedFloat32Array &d){for(int i=0;i<(int)depth_.size();++i)depth_[i]=(i<d.size()?(float)finite(d[i]):0);}
PackedFloat32Array IvoryRigCore::depths()const{PackedFloat32Array a;a.resize(depth_.size());for(int i=0;i<(int)depth_.size();++i)a[i]=depth_[i];return a;}
void IvoryRigCore::set_angle_limits(const PackedFloat32Array &mi,const PackedFloat32Array &ma){for(int i=0;i<(int)min_ang_.size();++i){min_ang_[i]=(i<mi.size()?(float)finite(mi[i],-PI):-PI);max_ang_[i]=(i<ma.size()?(float)finite(ma[i],PI):PI);if(min_ang_[i]>max_ang_[i])std::swap(min_ang_[i],max_ang_[i]);}}
void IvoryRigCore::set_stretch(int b,double lo,double hi){if(b<0||b>=(int)stretch_.size())return;stretch_[b].lo=std::clamp(finite(lo,1),0.01,100.0);stretch_[b].hi=std::max(stretch_[b].lo,std::clamp(finite(hi,1),0.01,100.0));}
bool IvoryRigCore::set_ik_target(int e,const Vector2 &target,const Vector2 &pole,double weight,bool stretch,double soft){if(e<0||e>=(int)ik_.size())return false;ik_[e]={true,stretch,finite_vec(target),finite_vec(pole,Vector2(0,-1)),std::clamp(finite(weight,1.0),0.0,1.0),std::clamp(finite(soft,0.0),0.0,1.0)};return true;}
void IvoryRigCore::clear_ik(int e){if(e>=0&&e<(int)ik_.size())ik_[e].active=false;} void IvoryRigCore::clear_ik_all(){for(auto &x:ik_)x.active=false;}
void IvoryRigCore::set_ik_fk_blend(int b,double w){if(b>=0&&b<(int)ik_blend_.size())ik_blend_[b]=(float)std::clamp(finite(w),0.0,1.0);}
void IvoryRigCore::rebuild(){int n=parent_.size();std::vector<int> indeg(n,0);for(int p:parent_)if(p>=0)indeg[p]++;order_.clear();order_.reserve(n);for(int pass=0;pass<n;pass++){bool any=false;for(int i=0;i<n;i++)if(indeg[i]==0){order_.push_back(i);indeg[i]=-1;any=true;for(int j=0;j<n;j++)if(parent_[j]==i)indeg[j]--; }if(!any)break;}if((int)order_.size()!=n){order_.clear();for(int i=0;i<n;i++)order_.push_back(i);}kid_start_.assign(n+1,0);for(int i=0;i<n;i++)if(parent_[i]>=0)kid_start_[parent_[i]+1]++;for(int i=1;i<=n;i++)kid_start_[i]+=kid_start_[i-1];kids_.assign(kid_start_[n],-1);auto cur=kid_start_;for(int i=0;i<n;i++)if(parent_[i]>=0)kids_[cur[parent_[i]]++]=i;}

void IvoryRigCore::fk(){for(int idx:order_){int p=parent_[idx];double base=p>=0?world_ang_[p]:std::atan2(rest_dir(idx).y,rest_dir(idx).x);double a=base+local_ang_[idx];if(p<0)a=std::atan2(rest_dir(idx).y,rest_dir(idx).x)+local_ang_[idx];world_ang_[idx]=wrap(a);Vector2 origin=p>=0?t_[p]:rest_h_[idx];double len=rest_len_[idx]*local_scale_[idx].x;Vector2 dir((real_t)std::cos(world_ang_[idx]),(real_t)std::sin(world_ang_[idx]));h_[idx]=finite_vec(origin);t_[idx]=finite_vec(origin+dir*(real_t)std::max(0.0,len),origin);}}

void IvoryRigCore::two_bone(int upper,int lower,const Vector2 &target,const Vector2 &pole,bool stretch,double soft){
 if(upper<0||lower<0||upper>=(int)parent_.size()||lower>=(int)parent_.size()) return;
 Vector2 root=h_[upper]; Vector2 to=finite_vec(target); Vector2 v=to-root; double d=v.length();
 double l1=std::max(0.0,(double)rest_len_[upper]*local_scale_[upper].x);
 double l2=std::max(0.0,(double)rest_len_[lower]*local_scale_[lower].x);
 if(l1<EPS||l2<EPS){ return; }
 double reach=l1+l2;
 if(stretch && d>reach){ double ratio=d/std::max(reach,EPS); ratio=std::clamp(ratio,stretch_[upper].lo,stretch_[upper].hi); l1*=ratio; l2*=ratio; reach=l1+l2; }
 if(soft>0.0 && d>reach*(1.0-soft)){
   double q=(d-reach*soft)/std::max(reach*(1.0-soft),EPS); d=std::min(d,reach*std::clamp(q,0.0,1.0));
 }
 if(d<EPS){ v=rest_dir(upper); d=1.0; }
 double cd=std::clamp((d*d+l1*l1-l2*l2)/(2.0*d*l1),-1.0,1.0);
 double bend=std::acos(cd); double base=std::atan2(v.y,v.x);
 Vector2 pv=finite_vec(pole-root,Vector2(0,1));
 double side=v.cross(pv); double sign=side>=0.0?1.0:-1.0;
 // A zero pole vector falls back to the stored rest-side, making the result deterministic.
 if(pv.length_squared()<EPS){ Vector2 rd=rest_t_[lower]-rest_h_[lower]; sign=(v.cross(rd)>=0.0)?1.0:-1.0; }
 double a1=base+sign*bend;
 Vector2 elbow=root+Vector2((real_t)std::cos(a1),(real_t)std::sin(a1))*(real_t)l1;
 Vector2 dv=to-elbow; if(dv.length_squared()<EPS) dv=Vector2((real_t)std::cos(a1),(real_t)std::sin(a1));
 Vector2 dir=dv.normalized();
 h_[upper]=root; t_[upper]=elbow; h_[lower]=elbow; t_[lower]=elbow+dir*(real_t)l2;
 world_ang_[upper]=std::atan2((double)(elbow-root).y,(double)(elbow-root).x);
 world_ang_[lower]=std::atan2((double)(t_[lower]-elbow).y,(double)(t_[lower]-elbow).x);
 double base0=parent_[upper]>=0?world_ang_[parent_[upper]]:std::atan2(rest_dir(upper).y,rest_dir(upper).x);
 local_ang_[upper]=(float)wrap(world_ang_[upper]-base0);
 local_ang_[lower]=(float)wrap(world_ang_[lower]-world_ang_[upper]);
}
void IvoryRigCore::chain_ik(int end,const Vector2 &target,const Vector2 &pole,int iterations,bool stretch,double soft){
 std::vector<int> chain;
 for(int b=end;b>=0;b=parent_[b]){
  chain.push_back(b);
  if(parent_[b]<0) break;
 }
 if(chain.size()<2) return;
 std::reverse(chain.begin(),chain.end());
 const int m=(int)chain.size();
 // n bones have n+1 joints. The old implementation allocated n joints and
 // overwrote the last bone head with the tip; that made 3+ bone chains solve
 // against the wrong geometry and was the main source of long-chain drift.
 std::vector<Vector2> q((size_t)m+1);
 for(int i=0;i<m;i++) q[(size_t)i]=h_[chain[(size_t)i]];
 q[(size_t)m]=t_[chain[(size_t)m-1]];
 std::vector<double> L((size_t)m);
 for(int i=0;i<m;i++) L[(size_t)i]=std::max(0.0,(double)rest_len_[chain[(size_t)i]]*local_scale_[chain[(size_t)i]].x);
 double total=0.0; for(double x:L) total+=x;
 Vector2 goal=finite_vec(target,q[0]);
 double d=(goal-q[0]).length();
 if(stretch&&d>total&&total>EPS){
  double extra=d/total;
  const Stretch &st=stretch_[chain[0]];
  extra=std::clamp(extra,st.lo,st.hi);
  for(double &x:L)x*=extra;
 } else if(soft>0 && d>total*(1.0-soft) && total>EPS){
  double k=(d-total*soft)/std::max(total*(1-soft),EPS);
  k=std::clamp(k,0.0,1.0);
  goal=q[0]+(goal-q[0])*(real_t)k;
 }
 const int rounds=std::clamp(iterations,1,64);
 // FABRIK first gets the end effector exactly where it belongs while preserving
 // all link lengths. Pole choice is applied afterwards only as a mirror choice.
 for(int it=0;it<rounds;it++){
  q[(size_t)m]=goal;
  for(int i=m-1;i>=0;i--){
   Vector2 v=q[(size_t)i]-q[(size_t)i+1];
   double ln=v.length();
   if(ln<EPS){v=Vector2(1,0);ln=1;}
   q[(size_t)i]=q[(size_t)i+1]+v*(real_t)(L[(size_t)i]/ln);
  }
  const Vector2 fixed_root=h_[chain[0]];
  q[0]=fixed_root;
  for(int i=0;i<m;i++){
   Vector2 v=q[(size_t)i+1]-q[(size_t)i];
   double ln=v.length();
   if(ln<EPS){v=rest_dir(chain[(size_t)i]);ln=1;}
   q[(size_t)i+1]=q[(size_t)i]+v*(real_t)(L[(size_t)i]/ln);
  }
  if((q[(size_t)m]-goal).length_squared()<1.0e-10) break;
 }
 const bool have_pole=(pole-q[0]).length_squared()>EPS;
 const Vector2 root=q[0];

 // Pole-vector selection in 2D is a side constraint, not another target.
 // Pick the interior joint with the largest distance from the root->goal axis
 // (the joint carrying the figure's dominant bend). If it is on the wrong
 // side, reflect the *entire solved chain* across that axis. Reflecting all
 // joints together preserves every bone length, the fixed root and the target;
 // reflecting one joint alone does not.
 if(have_pole){
  const Vector2 axis=goal-root;
  const double axis_len2=axis.length_squared();
  if(axis_len2>EPS){
   int bend_i=1;
   double best_abs=0.0;
   for(int i=1;i<m;i++){
    const double cross=(double)axis.cross(q[(size_t)i]-root);
    const double metric=std::abs(cross)/std::sqrt(axis_len2);
    if(metric>best_abs){best_abs=metric;bend_i=i;}
   }
   const double current_side=(double)axis.cross(q[(size_t)bend_i]-root);
   const double desired_side=(double)axis.cross(pole-root);
   if(std::abs(current_side)>1.0e-7 && std::abs(desired_side)>1.0e-7
       && ((current_side>0.0)!=(desired_side>0.0))){
    Vector2 u=axis/std::sqrt(axis_len2);
    for(int i=1;i<m;i++){
     Vector2 v=q[(size_t)i]-root;
     const double along=v.dot(u);
     const Vector2 on_axis=root+u*along;
     q[(size_t)i]=on_axis+(on_axis-q[(size_t)i]);
    }
   }
  }
 }

 for(int i=0;i<m;i++){
  const int b=chain[(size_t)i];
  h_[b]=q[(size_t)i];
  t_[b]=q[(size_t)i+1];
  world_ang_[b]=std::atan2((double)(t_[b]-h_[b]).y,(double)(t_[b]-h_[b]).x);
  const int p=parent_[b];
  const double base=p>=0?world_ang_[p]:std::atan2(rest_dir(b).y,rest_dir(b).x);
  local_ang_[b]=(float)wrap(world_ang_[b]-base);
 }
}

void IvoryRigCore::solve_ik_chain(int end,int iterations){
 if(end<0||end>=(int)ik_.size()||!ik_[end].active)return;
 const IK &k=ik_[end]; if(k.weight<=0.0)return;
 std::vector<int> chain; for(int b=end;b>=0;b=parent_[b]){chain.push_back(b);if(parent_[b]<0)break;} std::reverse(chain.begin(),chain.end());
 std::vector<float> fk_angles; fk_angles.reserve(chain.size()); for(int b:chain) fk_angles.push_back(local_ang_[b]);
 if(chain.size()==2) two_bone(chain[0],chain[1],k.target,k.pole,k.stretch,k.soft); else chain_ik(end,k.target,k.pole,iterations,k.stretch,k.soft);
 // IK/FK blending happens in angle space, never by averaging matrices.
 for(size_t i=0;i<chain.size();++i){int b=chain[i];double w=std::clamp(k.weight*(double)ik_blend_[b],0.0,1.0);local_ang_[b]=(float)wrap(fk_angles[i]+wrap(local_ang_[b]-fk_angles[i])*w);}
}
void IvoryRigCore::apply_limits(){for(int i=0;i<(int)local_ang_.size();i++)local_ang_[i]=(float)std::clamp((double)local_ang_[i],(double)min_ang_[i],(double)max_ang_[i]);}
void IvoryRigCore::project_lengths(){for(int b:order_){int p=parent_[b];if(p<0)continue;Vector2 d=t_[b]-h_[b];double len=d.length(),want=rest_len_[b]*local_scale_[b].x;if(want<EPS){t_[b]=h_[b];continue;}double lo=want*stretch_[b].lo,hi=want*stretch_[b].hi;double cl=std::clamp(len,lo,hi);if(len<EPS)d=rest_dir(b),len=1;t_[b]=h_[b]+d*(real_t)(cl/len);}}
void IvoryRigCore::sanitize(){for(auto &v:h_)v=finite_vec(v);for(auto &v:t_)v=finite_vec(v);for(auto &a:local_ang_)a=(float)wrap(a);for(auto &d:depth_)d=(float)finite(d);}

Dictionary IvoryRigCore::solve(int iterations){
 Dictionary o;
 sanitize();
 fk();
 for(int i=0;i<(int)ik_.size();i++) if(ik_[i].active) solve_ik_chain(i,iterations);
 apply_limits();
 project_lengths();
 sanitize();
 fk();
 bool ok=(bool)validate()["ok"];
 o["ok"]=ok; o["bones"]=(int)parent_.size();
 o["iterations"]=std::clamp(iterations,1,64);
 o["deterministic"]=true; o["nan_safe"]=ok;
 return o;
}

PackedVector2Array IvoryRigCore::heads()const{PackedVector2Array a;a.resize(h_.size());for(int i=0;i<(int)h_.size();i++)a[i]=h_[i];return a;}PackedVector2Array IvoryRigCore::tails()const{PackedVector2Array a;a.resize(t_.size());for(int i=0;i<(int)t_.size();i++)a[i]=t_[i];return a;}
PackedFloat32Array IvoryRigCore::world_angles()const{PackedFloat32Array a;a.resize(world_ang_.size());for(int i=0;i<(int)world_ang_.size();i++)a[i]=world_ang_[i];return a;}PackedFloat32Array IvoryRigCore::world_depth()const{return depths();}PackedInt32Array IvoryRigCore::parents()const{PackedInt32Array a;a.resize(parent_.size());for(int i=0;i<(int)parent_.size();i++)a[i]=parent_[i];return a;}PackedFloat32Array IvoryRigCore::lengths()const{PackedFloat32Array a;a.resize(rest_len_.size());for(int i=0;i<(int)rest_len_.size();i++)a[i]=rest_len_[i];return a;}
Vector2 IvoryRigCore::to_space(int b,const Vector2 &world,int space)const{if(b<0||b>=(int)h_.size())return world;Vector2 d=world-h_[b];double a=0;if(space==SPACE_LOCAL||space==SPACE_BONE)a=world_ang_[b];else if(space==SPACE_PARENT&&parent_[b]>=0)a=world_ang_[parent_[b]];double c=std::cos(-a),s=std::sin(-a);return Vector2((real_t)(d.x*c-d.y*s),(real_t)(d.x*s+d.y*c));}
Vector2 IvoryRigCore::from_space(int b,const Vector2 &v,int space)const{if(b<0||b>=(int)h_.size())return v;double a=0;if(space==SPACE_LOCAL||space==SPACE_BONE)a=world_ang_[b];else if(space==SPACE_PARENT&&parent_[b]>=0)a=world_ang_[parent_[b]];double c=std::cos(a),s=std::sin(a);return h_[b]+Vector2((real_t)(v.x*c-v.y*s),(real_t)(v.x*s+v.y*c));}

bool IvoryRigCore::set_weights(const PackedInt32Array &bones,const PackedFloat32Array &weights,int points,int max_inf){if(points<0||max_inf<1||bones.size()!=weights.size()||bones.size()!=points*max_inf)return false;point_count_=points;max_inf_=max_inf;weight_bone_.resize(bones.size());weight_.resize(weights.size());for(int i=0;i<bones.size();i++){weight_bone_[i]=(bones[i]>=0&&bones[i]<(int)parent_.size())?bones[i]:-1;weight_[i]=(float)std::max(0.0,finite(weights[i]));}normalize_weights();return true;}
void IvoryRigCore::normalize_weights(){for(int p=0;p<point_count_;p++){double s=0;for(int j=0;j<max_inf_;j++)s+=weight_[p*max_inf_+j];if(s<EPS){weight_[p*max_inf_]=1;weight_bone_[p*max_inf_]=std::max(0,std::min((int)parent_.size()-1,0));continue;}for(int j=0;j<max_inf_;j++)weight_[p*max_inf_+j]=(float)(weight_[p*max_inf_+j]/s);}}
PackedVector2Array IvoryRigCore::skin(const PackedVector2Array &rest)const{PackedVector2Array out;out.resize(rest.size());for(int p=0;p<rest.size();p++){Vector2 q=finite_vec(rest[p]);Vector2 acc;double sw=0;for(int j=0;j<max_inf_&&p*max_inf_+j<(int)weight_.size();j++){int b=weight_bone_[p*max_inf_+j];double w=weight_[p*max_inf_+j];if(b<0||b>=(int)h_.size()||w<=0)continue;Vector2 r=q-rest_h_[b];double c=std::cos(world_ang_[b]-std::atan2(rest_dir(b).y,rest_dir(b).x)),s=std::sin(world_ang_[b]-std::atan2(rest_dir(b).y,rest_dir(b).x));Vector2 x=h_[b]+Vector2((real_t)(r.x*c-r.y*s),(real_t)(r.x*s+r.y*c));acc+=x*(real_t)w;sw+=w;}out[p]=sw>EPS?finite_vec(acc/(real_t)sw,q):q;}return out;}
bool IvoryRigCore::set_corrective(const PackedVector2Array &o,double w){corrective_.clear();for(int i=0;i<o.size();i++)corrective_.push_back(finite_vec(o[i]));corrective_weight_=std::clamp(finite(w),0.0,1.0);return true;}PackedVector2Array IvoryRigCore::corrected_points()const{PackedVector2Array a;a.resize(corrective_.size());for(int i=0;i<(int)corrective_.size();i++)a[i]=corrective_[i]*(real_t)corrective_weight_;return a;}
Dictionary IvoryRigCore::validate()const{Dictionary d;bool ok=true;int bad=0;for(size_t i=0;i<h_.size();i++){if(!std::isfinite(h_[i].x)||!std::isfinite(h_[i].y)||!std::isfinite(t_[i].x)||!std::isfinite(t_[i].y))bad++;if(!std::isfinite(local_ang_[i]))bad++;}for(int p:parent_)if(p< -1||p>=(int)parent_.size())bad++;ok=bad==0;d["ok"]=ok;d["bad_values"]=bad;d["bone_count"]=(int)parent_.size();d["zero_length_safe"]=true;return d;}
Dictionary IvoryRigCore::stress_test(int bones,int operations,int seed)const{uint32_t x=(uint32_t)seed;auto rnd=[&](){x=x*1664525u+1013904223u;return x;};int b=std::clamp(bones,1,10000),ops=std::clamp(operations,1,1000000);int invalid=0;double checksum=0;for(int i=0;i<ops;i++){double a=((int32_t)rnd())*1e-6;double s=((int32_t)rnd())*1e-6;double v=finite(a);if(!std::isfinite(v)||!std::isfinite(s))invalid++;checksum+=std::sin(v)*0.000001;}Dictionary d;d["ok"]=invalid==0;d["bones"]=b;d["operations"]=ops;d["invalid"]=invalid;d["checksum"]=checksum;d["deterministic"]=true;return d;}
}
