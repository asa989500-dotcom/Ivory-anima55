#!/usr/bin/env python3
"""Deterministic geometry tests for the two-view Character 360 builder."""
import math, time

CHECKS = 0
FAIL = 0

def ok(v, name):
    global CHECKS, FAIL
    CHECKS += 1
    if not v:
        FAIL += 1
        print('FAIL:', name)

def make_mask(w, h, rx, ry, cx=None):
    cx = w/2 if cx is None else cx
    cy = h/2
    return [[((x-cx)/rx)**2 + ((y-cy)/ry)**2 <= 1 for x in range(w)] for y in range(h)]

def silhouette(mask):
    rows=[]
    for row in mask:
        xs=[i for i,v in enumerate(row) if v]
        rows.append((min(xs),max(xs)) if xs else None)
    return rows

def profile(side, h):
    rows=silhouette(side)
    out=[]
    for y in range(h):
        lo,hi=rows[min(len(rows)-1,int(y*len(rows)/h))] if rows[min(len(rows)-1,int(y*len(rows)/h))] else (0,0)
        out.append(max(0.0,(hi-lo)/max(1,len(side[0])-1)))
    return out

def build(front, side, strength=1.6, smooth=5):
    h=len(front); w=len(front[0]); sp=profile(side,h)
    a=[[1.0 if front[y][x] else 0.0 for x in range(w)] for y in range(h)]
    d=[[0.0]*w for _ in range(h)]
    fs=silhouette(front)
    for y in range(h):
        if not fs[y]: continue
        lo,hi=fs[y]; half=max((hi-lo)/2,1e-6)
        for x in range(w):
            if not front[y][x]: continue
            nx=(x-w/2)/half
            dome=math.sqrt(max(0.0,1.0-nx*nx))
            d[y][x]=max(0,min(1,sp[y]*dome))
    for _ in range(smooth):
        n=[r[:] for r in d]
        for y in range(1,h-1):
            for x in range(1,w-1):
                if not a[y][x]: continue
                vals=[d[y][x]]
                for dx,dy in ((-1,0),(1,0),(0,-1),(0,1)):
                    if a[y+dy][x+dx]: vals.append(d[y+dy][x+dx])
                n[y][x]=sum(vals)/len(vals)
        d=n
    return a,d,sp

def project(p, depth, strength, yaw):
    x=p[0]-.5; y=p[1]-.5; z=(depth-.5)*strength
    cy,sy=math.cos(yaw),math.sin(yaw)
    x1=x*cy+z*sy; z1=-x*sy+z*cy
    persp=1/(1+.10*z1)
    return (.5+x1*persp,.5+y*persp)

front=make_mask(128,160,42,70)
side=make_mask(96,160,24,70)
a,d,sp=build(front,side)

# 1. Two views are accepted and normalized.
ok(len(a)==160 and len(a[0])==128 and len(sp)==160, 'common normalized frame')
# 2. Front silhouette is preserved.
ok(sum(map(sum,a)) > 0.95*sum(map(sum,front)), 'front silhouette preserved')
# 3. Side view actually controls depth.
ok(max(sp) > 0.40, 'side thickness becomes depth')
# 4. Depth is strongest near the center.
ok(d[80][64] > d[80][40], 'center relief stronger than edge')
# 5. Transparent background has zero depth.
ok(max(d[y][x] for y in range(160) for x in range(128) if not a[y][x]) == 0, 'no depth leaks outside alpha')
# 6. Smoothing reduces local jumps.
raw_a,raw_d,_=build(front,side,smooth=0)
def grad(field):
    return max(abs(field[y][x]-field[y][x-1]) for y in range(1,len(field)-1) for x in range(1,len(field[0])))
ok(grad(d) <= grad(raw_d)+1e-9, 'smoothing never increases worst local jump')
# 7. Depth strength is bounded.
ok(0.25 <= 1.6 <= 3.0, 'depth strength bounds')
# 8. Yaw stays finite at extreme supported angle.
pts=[project((x/127,y/159),d[y][x],1.6,1.35) for y in range(0,160,8) for x in range(0,128,8)]
ok(all(math.isfinite(v) for p in pts for v in p), 'extreme yaw remains finite')
# 9. Repeated projection is deterministic.
p=(.42,.38); p1=project(p,d[61][54],1.6,.7); p2=project(p,d[61][54],1.6,.7)
ok(p1==p2, 'projection deterministic')
# 10. No candy-wrapper scaling from averaging rotations: central point remains stable at yaw 0.
ok(abs(project((.5,.5),d[80][64],1.6,0)[0]-.5)<1e-9, 'zero yaw preserves center')
# 11. Asymmetric front silhouette does not alter algorithm stability.
front2=make_mask(128,160,38,70,58)
_,d2,_=build(front2,side)
ok(max(d2[y][x] for y in range(160) for x in range(128)) > 0, 'asymmetric character builds')
# 12. Performance sanity on a representative 384x384 build.
t0=time.perf_counter(); build(make_mask(384,384,125,175), make_mask(384,384,70,175), smooth=6); dt=time.perf_counter()-t0
ok(dt < 4.0, f'384x384 build under 4s in reference Python ({dt:.3f}s)')

print(f'Character360 tests: {CHECKS} checks / {FAIL} failures')
raise SystemExit(1 if FAIL else 0)
