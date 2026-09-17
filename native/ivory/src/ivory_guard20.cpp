#include "ivory_guard20.h"
#include <algorithm>
#include <cmath>

using namespace godot;

Dictionary IvoryGuard20::result(bool ok, int failures, const Array &issues) {
	Dictionary d; d["ok"] = ok; d["failures"] = failures; d["issues"] = issues; return d;
}
void IvoryGuard20::issue(Array &a, const String &c, const String &detail, int index) {
	Dictionary d; d["code"] = c; d["detail"] = detail; if (index >= 0) d["index"] = index; a.append(d);
}
bool IvoryGuard20::finite(double v) { return std::isfinite(v); }
bool IvoryGuard20::finite_vec(const Vector2 &v) { return finite(v.x) && finite(v.y); }
double IvoryGuard20::tri_area(const Vector2&a,const Vector2&b,const Vector2&c){return 0.5*((double)(b.x-a.x)*(double)(c.y-a.y)-(double)(c.x-a.x)*(double)(b.y-a.y));}

#define START Array issues; int failures = 0;
#define DONE(name, value) Dictionary out = result(failures == 0, failures, issues); out["guard"] = name; out["value"] = value; return out;

void IvoryGuard20::_bind_methods() {
#define B0(n) ClassDB::bind_method(D_METHOD(n), &IvoryGuard20::n)
	ClassDB::bind_method(D_METHOD("mesh_topology", "points", "neighbours", "triangles"), &IvoryGuard20::mesh_topology);
	ClassDB::bind_method(D_METHOD("finite_geometry", "points"), &IvoryGuard20::finite_geometry);
	ClassDB::bind_method(D_METHOD("triangle_area", "points", "triangles", "min_area"), &IvoryGuard20::triangle_area);
	ClassDB::bind_method(D_METHOD("pose_displacement", "rest", "now", "max_distance"), &IvoryGuard20::pose_displacement);
	ClassDB::bind_method(D_METHOD("pin_binding", "vertices", "vertex_count"), &IvoryGuard20::pin_binding);
	ClassDB::bind_method(D_METHOD("pin_finite", "pins"), &IvoryGuard20::pin_finite);
	ClassDB::bind_method(D_METHOD("bounds", "points", "min_corner", "max_corner", "epsilon"), &IvoryGuard20::bounds);
	ClassDB::bind_method(D_METHOD("skin_weights", "weights", "bone_count", "tolerance"), &IvoryGuard20::skin_weights);
	ClassDB::bind_method(D_METHOD("bone_hierarchy", "parents"), &IvoryGuard20::bone_hierarchy);
	ClassDB::bind_method(D_METHOD("transform_finite", "points"), &IvoryGuard20::transform_finite);
	ClassDB::bind_method(D_METHOD("symmetry", "angle", "count"), &IvoryGuard20::symmetry);
	ClassDB::bind_method(D_METHOD("timeline", "frames", "frame_count"), &IvoryGuard20::timeline);
	ClassDB::bind_method(D_METHOD("frame_budget", "elapsed_ms", "budget_ms"), &IvoryGuard20::frame_budget);
	ClassDB::bind_method(D_METHOD("texture_extent", "width", "height", "ceiling"), &IvoryGuard20::texture_extent);
	ClassDB::bind_method(D_METHOD("pixel_buffer", "bytes", "width", "height", "channels"), &IvoryGuard20::pixel_buffer);
	ClassDB::bind_method(D_METHOD("touch_stream", "points", "max_jump"), &IvoryGuard20::touch_stream);
	ClassDB::bind_method(D_METHOD("audio_sync", "video_seconds", "audio_seconds"), &IvoryGuard20::audio_sync);
	ClassDB::bind_method(D_METHOD("export_settings", "width", "height", "fps", "bitrate"), &IvoryGuard20::export_settings);
	ClassDB::bind_method(D_METHOD("memory_budget", "estimated_bytes", "budget_bytes"), &IvoryGuard20::memory_budget);
	ClassDB::bind_method(D_METHOD("aggregate", "checks"), &IvoryGuard20::aggregate);
#undef B0
}

Dictionary IvoryGuard20::mesh_topology(const PackedVector2Array&p,const PackedInt32Array&n,const PackedInt32Array&t)const{
	START; if(p.size()<3){issue(issues,"mesh_small","Mesh has fewer than three vertices.");++failures;} if(n.size()!=p.size()*4){issue(issues,"neighbour_stride","Expected four neighbour slots per vertex.");++failures;} if(t.size()%3){issue(issues,"triangle_stride","Triangle index buffer is not divisible by three.");++failures;} for(int i=0;i<n.size();++i) if(n[i]<-1||n[i]>=p.size()){issue(issues,"neighbour_index","Neighbour index is invalid.",i);++failures;} DONE("mesh_topology", p.size());}
Dictionary IvoryGuard20::finite_geometry(const PackedVector2Array&p)const{
	START; for(int i=0;i<p.size();++i) if(!finite_vec(p[i])){issue(issues,"non_finite","Geometry contains NaN/Inf.",i);++failures;} DONE("finite_geometry",p.size());}
Dictionary IvoryGuard20::triangle_area(const PackedVector2Array&p,const PackedInt32Array&t,double min_a)const{
	START; double floor=std::max(std::fabs(min_a),1e-12); for(int i=0;i+2<t.size();i+=3){int a=t[i],b=t[i+1],c=t[i+2]; if(a<0||b<0||c<0||a>=p.size()||b>=p.size()||c>=p.size()){issue(issues,"triangle_index","Triangle index invalid.",i/3);++failures;continue;} if(std::fabs(tri_area(p[a],p[b],p[c]))<floor){issue(issues,"degenerate_triangle","Triangle area is below the floor.",i/3);++failures;}} DONE("triangle_area",t.size()/3);}
Dictionary IvoryGuard20::pose_displacement(const PackedVector2Array&r,const PackedVector2Array&n,double max_d)const{
	START; if(r.size()!=n.size()){issue(issues,"pose_stride","Rest/current point counts differ.");++failures;} int c=std::min((int)r.size(),(int)n.size()); for(int i=0;i<c;++i){if(!finite_vec(r[i])||!finite_vec(n[i])){issue(issues,"pose_non_finite","Pose contains NaN/Inf.",i);++failures;continue;} if(std::hypot((double)n[i].x-r[i].x,(double)n[i].y-r[i].y)>max_d){issue(issues,"pose_jump","Pose displacement exceeds limit.",i);++failures;}} DONE("pose_displacement",c);}
Dictionary IvoryGuard20::pin_binding(const PackedInt32Array&v,int count)const{START; for(int i=0;i<v.size();++i)if(v[i]<-1||v[i]>=count){issue(issues,"pin_vertex","Pin references an invalid vertex.",i);++failures;} DONE("pin_binding",v.size());}
Dictionary IvoryGuard20::pin_finite(const PackedVector2Array&p)const{START; for(int i=0;i<p.size();++i)if(!finite_vec(p[i])){issue(issues,"pin_non_finite","Pin coordinate is not finite.",i);++failures;} DONE("pin_finite",p.size());}
Dictionary IvoryGuard20::bounds(const PackedVector2Array&p,const Vector2&lo,const Vector2&hi,double e)const{START;float lx=std::min(lo.x,hi.x),ly=std::min(lo.y,hi.y),hx=std::max(lo.x,hi.x),hy=std::max(lo.y,hi.y);for(int i=0;i<p.size();++i)if(!finite_vec(p[i])||p[i].x<lx-e||p[i].x>hx+e||p[i].y<ly-e||p[i].y>hy+e){issue(issues,"out_of_bounds","Point escaped bounds.",i);++failures;}DONE("bounds",p.size());}
Dictionary IvoryGuard20::skin_weights(const PackedFloat32Array&w,int bones,double tol)const{START;if(bones<=0){issue(issues,"bone_count","Bone count must be positive.");++failures;}for(int i=0;i<w.size();){double s=0;for(int b=0;b<bones&&i+b<w.size();++b){float x=w[i+b];if(!finite(x)||x<-float(tol)){issue(issues,"bad_weight","Skin weight invalid.",i+b);++failures;}s+=std::max(0.0,(double)x);}if(std::fabs(s-1.0)>tol){issue(issues,"weight_sum","Influence weights do not sum to one.",i/bones);++failures;}i+=bones;}DONE("skin_weights",w.size());}
Dictionary IvoryGuard20::bone_hierarchy(const PackedInt32Array&p)const{START;for(int i=0;i<p.size();++i){if(p[i]<-1||p[i]>=p.size()){issue(issues,"parent_index","Bone parent is invalid.",i);++failures;continue;}int hops=0,cur=i;while(cur>=0&&hops++<=p.size())cur=p[cur];if(hops>p.size()){issue(issues,"bone_cycle","Bone hierarchy contains a cycle.",i);++failures;}}DONE("bone_hierarchy",p.size());}
Dictionary IvoryGuard20::transform_finite(const PackedVector2Array&p)const{START;for(int i=0;i<p.size();++i)if(!finite_vec(p[i])){issue(issues,"transform_non_finite","Transformed point is invalid.",i);++failures;}DONE("transform_finite",p.size());}
Dictionary IvoryGuard20::symmetry(double angle,int count)const{START;if(!finite(angle)){issue(issues,"symmetry_angle","Symmetry angle is not finite.");++failures;}if(count<1||count>64){issue(issues,"symmetry_count","Symmetry count is outside supported range.");++failures;}DONE("symmetry",count);}
Dictionary IvoryGuard20::timeline(const PackedInt32Array&f,int count)const{START;if(count<0){issue(issues,"frame_count","Frame count is negative.");++failures;}for(int i=0;i<f.size();++i)if(f[i]<0||f[i]>=count){issue(issues,"frame_index","Timeline frame is outside range.",i);++failures;}DONE("timeline",f.size());}
Dictionary IvoryGuard20::frame_budget(double e,double b)const{START;if(!finite(e)||e<0||!finite(b)||b<=0){issue(issues,"frame_time","Invalid frame budget input.");++failures;}else if(e>b){issue(issues,"frame_over_budget","Frame exceeded budget.");++failures;}DONE("frame_budget",e);}
Dictionary IvoryGuard20::texture_extent(int w,int h,int c)const{START;if(w<=0||h<=0){issue(issues,"texture_size","Texture dimensions must be positive.");++failures;}if(c<=0){issue(issues,"texture_channels","Texture channel count must be positive.");++failures;}if(c>0&&((int64_t)w*h*c> (int64_t)c*16384*16384)){issue(issues,"texture_huge","Texture is unreasonably large.");++failures;}DONE("texture_extent",(int64_t)w*h);}
Dictionary IvoryGuard20::pixel_buffer(const PackedByteArray&b,int w,int h,int c)const{START;int64_t need=(int64_t)w*h*c;if(w<=0||h<=0||c<=0||need<0){issue(issues,"buffer_shape","Invalid pixel dimensions.");++failures;}else if(b.size()!=need){issue(issues,"buffer_stride","Pixel byte count does not match dimensions.");++failures;}DONE("pixel_buffer",b.size());}
Dictionary IvoryGuard20::touch_stream(const PackedVector2Array&p,double jump)const{START;for(int i=0;i<p.size();++i){if(!finite_vec(p[i])){issue(issues,"touch_non_finite","Touch coordinate invalid.",i);++failures;}if(i>0&&std::hypot((double)p[i].x-p[i-1].x,(double)p[i].y-p[i-1].y)>jump){issue(issues,"touch_jump","Touch stream contains an implausible jump.",i);++failures;}}DONE("touch_stream",p.size());}
Dictionary IvoryGuard20::audio_sync(double v,double a)const{START;if(!finite(v)||!finite(a)||v<0||a<0){issue(issues,"audio_time","Invalid audio/video duration.");++failures;}else if(std::fabs(v-a)>0.25){issue(issues,"av_drift","Audio/video duration drift exceeds 250 ms.");++failures;}DONE("audio_sync",std::fabs(v-a));}
Dictionary IvoryGuard20::export_settings(int w,int h,int fps,int bitrate)const{START;if(w<=0||h<=0){issue(issues,"export_size","Export dimensions are invalid.");++failures;}if(fps<1||fps>240){issue(issues,"export_fps","Export FPS is outside supported range.");++failures;}if(bitrate<0){issue(issues,"export_bitrate","Bitrate cannot be negative.");++failures;}DONE("export_settings",bitrate);}
Dictionary IvoryGuard20::memory_budget(int64_t est,int64_t budget)const{START;if(est<0||budget<=0){issue(issues,"memory_input","Invalid memory budget values.");++failures;}else if(est>budget){issue(issues,"memory_over_budget","Estimated allocation exceeds budget.");++failures;}DONE("memory_budget",est);}
Dictionary IvoryGuard20::aggregate(const Array&checks)const{START;for(int i=0;i<checks.size();++i){Dictionary d=checks[i];if(!bool(d.get("ok",false))){++failures;issue(issues,String(d.get("guard","unknown")),String(d.get("issues","guard failed")),i);}}DONE("aggregate",checks.size());}
#undef START
#undef DONE
