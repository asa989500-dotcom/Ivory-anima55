#include "ivory_character360_rig.h"
#include <algorithm>
#include <cmath>

using namespace godot;
static constexpr double PI2 = 6.2831853071795864769;
static constexpr double EPS = 1e-7;

double IvoryCharacter360Rig::wrap_angle(double a) {
	a = std::fmod(a + 3.14159265358979323846, PI2);
	if (a < 0) a += PI2;
	return a - 3.14159265358979323846;
}

void IvoryCharacter360Rig::_bind_methods() {
	BIND_ENUM_CONSTANT(PIN_FIXED); BIND_ENUM_CONSTANT(PIN_BONE);
	BIND_ENUM_CONSTANT(PIN_ROTATION); BIND_ENUM_CONSTANT(PIN_STRETCH);
	BIND_ENUM_CONSTANT(PIN_ATTRIBUTE);
	ClassDB::bind_method(D_METHOD("add_disc","angle"), &IvoryCharacter360Rig::add_disc);
	ClassDB::bind_method(D_METHOD("remove_disc","index"), &IvoryCharacter360Rig::remove_disc);
	ClassDB::bind_method(D_METHOD("clear_discs"), &IvoryCharacter360Rig::clear_discs);
	ClassDB::bind_method(D_METHOD("set_disc_angle","index","angle"), &IvoryCharacter360Rig::set_disc_angle);
	ClassDB::bind_method(D_METHOD("disc_angle","index"), &IvoryCharacter360Rig::disc_angle);
	ClassDB::bind_method(D_METHOD("disc_count"), &IvoryCharacter360Rig::disc_count);
	ClassDB::bind_method(D_METHOD("disc_weights","angle"), &IvoryCharacter360Rig::disc_weights);
	ClassDB::bind_method(D_METHOD("blend_window","angle"), &IvoryCharacter360Rig::blend_window);
	ClassDB::bind_method(D_METHOD("settle","values","velocity","delta","frequency","damping","amount"), &IvoryCharacter360Rig::settle);
	ClassDB::bind_method(D_METHOD("set_ik_enabled","enabled"), &IvoryCharacter360Rig::set_ik_enabled);
	ClassDB::bind_method(D_METHOD("ik_enabled"), &IvoryCharacter360Rig::ik_enabled);
	ClassDB::bind_method(D_METHOD("solve_ik","points","parent","lengths","tip","target","passes"), &IvoryCharacter360Rig::solve_ik, DEFVAL(8));
	ClassDB::bind_method(D_METHOD("solve_ik_pole","points","parent","lengths","tip","target","pole","passes"), &IvoryCharacter360Rig::solve_ik_pole, DEFVAL(8));
	ClassDB::bind_method(D_METHOD("fk_pose","points","turns","parent","lengths"), &IvoryCharacter360Rig::fk_pose);
	ClassDB::bind_method(D_METHOD("add_constraint","bone"), &IvoryCharacter360Rig::add_constraint);
	ClassDB::bind_method(D_METHOD("set_constraint","id","min_angle","max_angle","spring","target_bone"), &IvoryCharacter360Rig::set_constraint, DEFVAL(-1));
	ClassDB::bind_method(D_METHOD("clear_constraints"), &IvoryCharacter360Rig::clear_constraints);
	ClassDB::bind_method(D_METHOD("apply_constraints","turns","delta"), &IvoryCharacter360Rig::apply_constraints, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("add_pin","rest","type","bone","amount"), &IvoryCharacter360Rig::add_pin, DEFVAL(-1), DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("set_pin_value","id","value"), &IvoryCharacter360Rig::set_pin_value);
	ClassDB::bind_method(D_METHOD("remove_pin","id"), &IvoryCharacter360Rig::remove_pin);
	ClassDB::bind_method(D_METHOD("clear_pins"), &IvoryCharacter360Rig::clear_pins);
	ClassDB::bind_method(D_METHOD("pin","id"), &IvoryCharacter360Rig::pin);
	ClassDB::bind_method(D_METHOD("resize_weights","vertex_count","bone_count"), &IvoryCharacter360Rig::resize_weights);
	ClassDB::bind_method(D_METHOD("weights"), &IvoryCharacter360Rig::weights);
	ClassDB::bind_method(D_METHOD("paint_weights","vertex","bone","strength","radius"), &IvoryCharacter360Rig::paint_weights, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("normalize_weights"), &IvoryCharacter360Rig::normalize_weights);
	ClassDB::bind_method(D_METHOD("vertex_weights","vertex"), &IvoryCharacter360Rig::vertex_weights);
	ClassDB::bind_method(D_METHOD("set_ffd","cols","rows","rest","live"), &IvoryCharacter360Rig::set_ffd);
	ClassDB::bind_method(D_METHOD("ffd_deform","points"), &IvoryCharacter360Rig::ffd_deform);
	ClassDB::bind_method(D_METHOD("clear_ffd"), &IvoryCharacter360Rig::clear_ffd);
	ClassDB::bind_method(D_METHOD("ffd_enabled"), &IvoryCharacter360Rig::ffd_enabled);
	ClassDB::bind_method(D_METHOD("begin_history","points","weights","turns"), &IvoryCharacter360Rig::begin_history);
	ClassDB::bind_method(D_METHOD("commit_history","points","weights","turns"), &IvoryCharacter360Rig::commit_history);
	ClassDB::bind_method(D_METHOD("undo"), &IvoryCharacter360Rig::undo);
	ClassDB::bind_method(D_METHOD("redo"), &IvoryCharacter360Rig::redo);
	ClassDB::bind_method(D_METHOD("undo_count"), &IvoryCharacter360Rig::undo_count);
	ClassDB::bind_method(D_METHOD("redo_count"), &IvoryCharacter360Rig::redo_count);
	ClassDB::bind_method(D_METHOD("diagnostics"), &IvoryCharacter360Rig::diagnostics);
}

int IvoryCharacter360Rig::add_disc(double angle) {
	Disc d; d.angle = (float)wrap_angle(angle); discs_.push_back(d);
	return (int)discs_.size()-1;
}
void IvoryCharacter360Rig::remove_disc(int i){ if(i>=0&&i<(int)discs_.size()) discs_[i].live=false; }
void IvoryCharacter360Rig::clear_discs(){discs_.clear();}
void IvoryCharacter360Rig::set_disc_angle(int i,double a){if(i>=0&&i<(int)discs_.size())discs_[i].angle=(float)wrap_angle(a);}
double IvoryCharacter360Rig::disc_angle(int i)const{return i>=0&&i<(int)discs_.size()&&discs_[i].live?discs_[i].angle:0.0;}
int IvoryCharacter360Rig::disc_count()const{int n=0;for(auto&d:discs_)if(d.live)n++;return n;}

PackedFloat32Array IvoryCharacter360Rig::disc_weights(double angle) const {
	PackedFloat32Array out; out.resize(discs_.size()); for(int i=0;i<out.size();++i)out[i]=0;
	std::vector<int> live; for(int i=0;i<(int)discs_.size();++i)if(discs_[i].live)live.push_back(i);
	std::sort(live.begin(), live.end(), [this](int a,int b){return discs_[a].angle<discs_[b].angle;});
	if(live.empty()) return out; if(live.size()==1){out[live[0]]=1;return out;}
	double a=wrap_angle(angle);
	for(size_t k=0;k<live.size();++k){
		int i=live[k], prev=live[(k+live.size()-1)%live.size()], next=live[(k+1)%live.size()];
		double left=wrap_angle(discs_[i].angle-discs_[prev].angle);
		double right=wrap_angle(discs_[next].angle-discs_[i].angle);
		if(left<=0)left+=PI2;if(right<=0)right+=PI2;
		double x=wrap_angle(a-discs_[i].angle);
		if(x<0)x+=PI2;
		double w=0;
		// A disc holds full weight at its own angle and falls to nought at
		// each neighbour.  Measuring the far side from `right` instead of
		// from the wrap point lost the whole span between the last disc and
		// the first, so a yaw of 315 on a four-disc rig blended back+left
		// rather than left+front.
		if(x<=right) w=1.0-x/std::max(right,EPS);
		else if(x>=PI2-left) w=1.0-(PI2-x)/std::max(left,EPS);
		else w=0.0;
		if(w<0.0) w=0.0;
		out[i]=(float)std::max(0.0,w);
	}
	double sum=0;for(int i=0;i<out.size();++i)sum+=out[i]; if(sum>EPS)for(int i=0;i<out.size();++i)out[i]/=(float)sum;
	return out;
}
Dictionary IvoryCharacter360Rig::blend_window(double angle) const {
	Dictionary d; PackedFloat32Array w=disc_weights(angle); d["weights"]=w; d["angle"]=wrap_angle(angle);
	int a=-1,b=-1;float wa=0,wb=0;for(int i=0;i<w.size();++i){if(w[i]>wa){wb=wa;b=a;wa=w[i];a=i;}else if(w[i]>wb){wb=w[i];b=i;}}
	d["primary"]=a;d["secondary"]=b;d["primary_weight"]=wa;d["secondary_weight"]=wb;return d;
}

PackedFloat32Array IvoryCharacter360Rig::settle(PackedFloat32Array values,PackedFloat32Array velocity,double delta,double frequency,double damping,double amount)const{
	double dt=std::clamp(delta,0.0,1.0/20.0), k=std::max(0.01,frequency)*6.283185307179586, c=std::max(0.01,damping)*2.0;
	int n=std::min((int)values.size(),(int)velocity.size());for(int i=0;i<n;++i){double x=values[i],v=velocity[i];double acc=-k*k*x-c*k*v;v+=acc*dt*std::clamp(amount,0.0,1.0);x+=v*dt;values[i]=(float)x;velocity[i]=(float)v;}return values;
}
void IvoryCharacter360Rig::set_ik_enabled(bool e){ik_enabled_=e;}
bool IvoryCharacter360Rig::ik_enabled()const{return ik_enabled_;}

PackedVector2Array IvoryCharacter360Rig::solve_ik(const PackedVector2Array &in,const PackedInt32Array &parent,const PackedFloat32Array &len,int tip,const Vector2&t,int passes)const{
	PackedVector2Array p=in;
	if(!ik_enabled_||tip<0||tip>=p.size())return p; std::vector<int> chain;int x=tip;for(int guard=0;x>=0&&x<p.size()&&x<parent.size()&&guard<p.size();++guard){chain.push_back(x);x=parent[x];}if(chain.size()<2)return p;std::reverse(chain.begin(),chain.end());
	PackedVector2Array j;for(int i:chain)j.push_back(p[i]);Vector2 root=j[0];int last=j.size()-1;if(last>=len.size()) return p;
	for(int pass=0;pass<std::clamp(passes,1,32);++pass){if(j[last].distance_to(t)<0.25)break;j[last]=t;for(int k=last;k>0;--k){Vector2 d=j[k-1]-j[k];if(d.length_squared()<EPS)d=Vector2(1,0);float L=len[chain[k-1]];j[k-1]=j[k]+d.normalized()*L;}j[0]=root;for(int k=0;k<last;++k){Vector2 d=j[k+1]-j[k];if(d.length_squared()<EPS)d=Vector2(1,0);float L=len[chain[k]];j[k+1]=j[k]+d.normalized()*L;}}
	for(int k=0;k<chain.size();++k)p[chain[k]]=j[k];return p;
}
PackedVector2Array IvoryCharacter360Rig::solve_ik_pole(const PackedVector2Array &in,
		const PackedInt32Array &parent, const PackedFloat32Array &len, int tip,
		const Vector2 &t, const Vector2 &pole, int passes) const {
	PackedVector2Array p = in;
	if (!ik_enabled_ || tip < 0 || tip >= p.size() || !std::isfinite(t.x) || !std::isfinite(t.y)) return p;
	std::vector<int> chain; int x = tip;
	for (int guard = 0; x >= 0 && x < p.size() && x < parent.size() && guard < p.size(); ++guard) {
		chain.push_back(x); x = parent[x];
	}
	if (chain.size() < 2) return p;
	std::reverse(chain.begin(), chain.end());
	const int n = (int)chain.size();
	PackedVector2Array j; for (int i : chain) j.push_back(p[i]);
	const Vector2 root = j[0];
	// Two-bone limbs use the same closed-form triangle as EasyIK. The pole is
	// only a bend-side selector and is ignored inside a small hysteresis band.
	if (n == 2 && chain[0] < len.size() && chain[1] < len.size()) {
		const double l1 = std::max(1.0e-6, (double)len[chain[0]]);
		const double l2 = std::max(1.0e-6, (double)len[chain[1]]);
		Vector2 span = t - root; double d = span.length();
		if (d < 1.0e-6) return p;
		const double raw_d = d;
		d = std::clamp(d, std::abs(l1-l2)+1.0e-4, l1+l2-1.0e-4);
		Vector2 dir = span / (real_t)raw_d;
		const double old_side = (double)dir.cross(j[1]-root);
		const double pole_side = (double)dir.cross(pole-root);
		const double side = std::abs(pole_side) > std::max(0.75, raw_d*0.0125) ? pole_side : old_side;
		const double sign = side < 0.0 ? -1.0 : 1.0;
		const double c = std::clamp((l1*l1 + d*d - l2*l2)/(2.0*l1*d), -1.0, 1.0);
		const double a = std::acos(c) * sign;
		const double base = dir.angle();
		const Vector2 elbow = root + Vector2((real_t)std::cos(base+a),(real_t)std::sin(base+a))*(real_t)l1;
		const Vector2 hand = root + dir*(real_t)d;
		j[1] = elbow; j[0] = root;
		// The tip is represented by the second joint for this point-array API;
		// retain exact target direction and exact lengths, never a matrix average.
		j[1] = elbow;
		PackedVector2Array out = p;
		out[chain[0]] = root; out[chain[1]] = hand;
		// In the point representation the original caller expects each point to
		// be a bone head. Rebuild the two points from the exact segment solution.
		out[chain[0]] = root + Vector2((real_t)std::cos(base+a),(real_t)std::sin(base+a))*(real_t)0.0;
		out[chain[1]] = elbow;
		return out;
	}
	// Long chains retain FABRIK, followed by a pole-side mirror of the complete
	// solved chain. No single joint is moved independently, so attachments stay closed.
	for (int pass=0; pass<std::clamp(passes,1,32); ++pass) {
		j[n-1]=t;
		for(int k=n-1;k>0;--k){Vector2 d=j[k-1]-j[k];if(d.length_squared()<EPS)d=Vector2(1,0);double L=(chain[k-1]<len.size()?len[chain[k-1]]:0.0);j[k-1]=j[k]+d.normalized()*(real_t)L;}
		j[0]=root;
		for(int k=0;k<n-1;++k){Vector2 d=j[k+1]-j[k];if(d.length_squared()<EPS)d=Vector2(1,0);double L=(chain[k]<len.size()?len[chain[k]]:0.0);j[k+1]=j[k]+d.normalized()*(real_t)L;}
		if(j[n-1].distance_squared_to(t)<0.0625) break;
	}
	const Vector2 axis=t-root; const double al2=axis.length_squared();
	if(al2>EPS && std::isfinite(pole.x) && std::isfinite(pole.y)){
		const double desired=(double)axis.cross(pole-root), current=(double)axis.cross(j[1]-root);
		if(std::abs(desired)>std::sqrt(al2)*0.0025 && std::abs(current)>std::sqrt(al2)*0.0025 && ((desired>0)!=(current>0))){
			Vector2 u=axis/(real_t)std::sqrt(al2);
			for(int k=1;k<n-1;++k){Vector2 v=j[k]-root;Vector2 on=root+u*(real_t)v.dot(u);j[k]=on+(on-j[k]);}
		}
	}
	for(int k=0;k<n;++k)p[chain[k]]=j[k];
	return p;
}

PackedVector2Array IvoryCharacter360Rig::fk_pose(PackedVector2Array p,const PackedFloat32Array&turns,const PackedInt32Array&parent,const PackedFloat32Array&len)const{
	for(int i=0;i<p.size()&&i<turns.size()&&i<len.size();++i){int par=i<parent.size()?parent[i]:-1;Vector2 dir=Vector2(1,0).rotated(turns[i]);if(par>=0&&par<p.size()){Vector2 base=p[par];p[i]=base+dir*len[i];}}
return p;
}

int IvoryCharacter360Rig::add_constraint(int bone){Constraint c;c.bone=bone;constraints_.push_back(c);return constraints_.size()-1;}
void IvoryCharacter360Rig::set_constraint(int id,double mn,double mx,double spring,int target){if(id<0||id>=constraints_.size())return;constraints_[id].min_angle=std::min(mn,mx);constraints_[id].max_angle=std::max(mn,mx);constraints_[id].spring=std::clamp(spring,0.0,1.0);constraints_[id].target_bone=target;}
void IvoryCharacter360Rig::clear_constraints(){constraints_.clear();}
PackedFloat32Array IvoryCharacter360Rig::apply_constraints(PackedFloat32Array t,double delta)const{
	for(auto&c:constraints_)if(c.bone>=0&&c.bone<t.size()){float goal=t[c.bone];if(c.target_bone>=0&&c.target_bone<t.size())goal=(float)wrap_angle(t[c.target_bone]);float limited=std::clamp(goal,(float)c.min_angle,(float)c.max_angle);float s=(float)std::clamp((double)c.spring,0.0,1.0);if(delta>0)s=std::min(1.0f,s*(float)std::min(1.0,delta*60.0));t[c.bone]=t[c.bone]+(limited-t[c.bone])*s;}return t;
}

int IvoryCharacter360Rig::add_pin(const Vector2&r,int type,int bone,double amount){Pin p;p.rest=r;p.value=r;p.type=(PinType)std::clamp(type,0,4);p.bone=bone;p.amount=(float)std::clamp(amount,0.0,1.0);pins_.push_back(p);return pins_.size()-1;}
void IvoryCharacter360Rig::set_pin_value(int i,const Vector2&v){if(i>=0&&i<pins_.size())pins_[i].value=v;}
void IvoryCharacter360Rig::remove_pin(int i){if(i>=0&&i<pins_.size())pins_[i].amount=0;}
void IvoryCharacter360Rig::clear_pins(){pins_.clear();}
Dictionary IvoryCharacter360Rig::pin(int i)const{Dictionary d;if(i<0||i>=pins_.size())return d;auto&p=pins_[i];d["rest"]=p.rest;d["value"]=p.value;d["type"]=(int)p.type;d["bone"]=p.bone;d["amount"]=p.amount;return d;}

void IvoryCharacter360Rig::resize_weights(int v,int b){wcols_=std::max(0,v);wbones_=std::max(0,b);weights_.assign(wcols_*wbones_,0);if(wbones_)for(int i=0;i<wcols_;++i)weights_[i*wbones_]=1;}
PackedFloat32Array IvoryCharacter360Rig::weights()const{PackedFloat32Array o;for(float x:weights_)o.push_back(x);return o;}
void IvoryCharacter360Rig::paint_weights(int v,int b,double strength,double radius){if(v<0||v>=wcols_||b<0||b>=wbones_)return;int r=std::max(0,(int)std::round(radius));for(int x=std::max(0,v-r);x<=std::min(wcols_-1,v+r);++x){double d=radius>0?std::abs(x-v)/radius:0;float s=(float)(std::clamp(strength,0.0,1.0)*(radius>0?std::max(0.0,1.0-d):1.0));weights_[x*wbones_+b]=std::clamp(weights_[x*wbones_+b]+s,0.0f,1.0f);}normalize_weights();}
void IvoryCharacter360Rig::normalize_weights(){for(int v=0;v<wcols_;++v){float sum=0;for(int b=0;b<wbones_;++b)sum+=weights_[v*wbones_+b];if(sum<EPS){if(wbones_)weights_[v*wbones_]=1;}else for(int b=0;b<wbones_;++b)weights_[v*wbones_+b]/=sum;}}
PackedFloat32Array IvoryCharacter360Rig::vertex_weights(int v)const{PackedFloat32Array o;if(v<0||v>=wcols_)return o;for(int b=0;b<wbones_;++b)o.push_back(weights_[v*wbones_+b]);return o;}

void IvoryCharacter360Rig::set_ffd(int c,int r,const PackedVector2Array&rest,const PackedVector2Array&live){ffd_cols_=std::max(0,c);ffd_rows_=std::max(0,r);ffd_rest_=rest;ffd_live_=live;}
PackedVector2Array IvoryCharacter360Rig::ffd_deform(const PackedVector2Array&points)const{
	if(!ffd_enabled())return points;
	PackedVector2Array o=points;
	const int n=std::min((int)ffd_rest_.size(),(int)ffd_live_.size());
	if(n < 4 || ffd_cols_ < 2 || ffd_rows_ < 2) return o;
	for(int q=0;q<o.size();++q){
		float u=0.0f,v=0.0f;
		const Vector2 p=o[q];
		const Vector2 minp=ffd_rest_[0], maxp=ffd_rest_[n-1];
		float sx=std::max(std::abs(maxp.x-minp.x),0.0001f), sy=std::max(std::abs(maxp.y-minp.y),0.0001f);
		u=std::clamp((p.x-minp.x)/sx,0.0f,1.0f); v=std::clamp((p.y-minp.y)/sy,0.0f,1.0f);
		float fx=u*(ffd_cols_-1), fy=v*(ffd_rows_-1);
		int x=std::clamp((int)std::floor(fx),0,ffd_cols_-2), y=std::clamp((int)std::floor(fy),0,ffd_rows_-2);
		float tx=fx-x, ty=fy-y;
		auto idx=[this](int xx,int yy){return yy*ffd_cols_+xx;};
		int i00=idx(x,y), i10=idx(x+1,y), i01=idx(x,y+1), i11=idx(x+1,y+1);
		Vector2 d00=ffd_live_[i00]-ffd_rest_[i00], d10=ffd_live_[i10]-ffd_rest_[i10];
		Vector2 d01=ffd_live_[i01]-ffd_rest_[i01], d11=ffd_live_[i11]-ffd_rest_[i11];
		Vector2 d=d00.lerp(d10,tx).lerp(d01.lerp(d11,tx),ty);
		o[q]=p+d;
	}
	return o;
}
void IvoryCharacter360Rig::clear_ffd(){ffd_rest_.clear();ffd_live_.clear();ffd_cols_=ffd_rows_=0;}
bool IvoryCharacter360Rig::ffd_enabled()const{return ffd_cols_>1&&ffd_rows_>1&&ffd_rest_.size()==ffd_live_.size();}

IvoryCharacter360Rig::Snapshot IvoryCharacter360Rig::make_snapshot(const PackedVector2Array&p,const PackedFloat32Array&w,const PackedFloat32Array&t)const{Snapshot s;s.points=p;s.weights=w;s.turns=t;return s;}
Dictionary IvoryCharacter360Rig::snapshot_dict(const Snapshot&s)const{Dictionary d;d["points"]=s.points;d["weights"]=s.weights;d["turns"]=s.turns;return d;}
void IvoryCharacter360Rig::begin_history(const PackedVector2Array&p,const PackedFloat32Array&w,const PackedFloat32Array&t){history_.clear();history_pos_=-1;commit_history(p,w,t);}
void IvoryCharacter360Rig::commit_history(const PackedVector2Array&p,const PackedFloat32Array&w,const PackedFloat32Array&t){if(history_pos_+1<(int)history_.size())history_.erase(history_.begin()+history_pos_+1,history_.end());history_.push_back(make_snapshot(p,w,t));if(history_.size()>64)history_.erase(history_.begin());history_pos_=history_.size()-1;}
Dictionary IvoryCharacter360Rig::undo(){Dictionary d;if(history_pos_<=0)return d;--history_pos_;return snapshot_dict(history_[history_pos_]);}
Dictionary IvoryCharacter360Rig::redo(){Dictionary d;if(history_pos_+1>=(int)history_.size())return d;++history_pos_;return snapshot_dict(history_[history_pos_]);}
int IvoryCharacter360Rig::undo_count()const{return std::max(history_pos_,0);}
int IvoryCharacter360Rig::redo_count()const{return std::max(0,(int)history_.size()-history_pos_-1);}
Dictionary IvoryCharacter360Rig::diagnostics()const{Dictionary d;d["discs"]=disc_count();d["pins"]=(int)pins_.size();d["constraints"]=(int)constraints_.size();d["weighted_vertices"]=wcols_;d["weight_bones"]=wbones_;d["ffd"]=ffd_enabled();d["undo"]=undo_count();d["redo"]=redo_count();return d;}
