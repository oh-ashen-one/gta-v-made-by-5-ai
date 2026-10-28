#!/usr/bin/env python3
"""CPU equation study only: not a Godot shader compiler or rendered test.

The existing density/shading equations are transcribed here to quantify the
projection change. Source hashes bind the receipt for independent code review.
No images, engine, UI, GPU, or live game state are produced or changed.
"""
from pathlib import Path
import hashlib
import json
import math
import re

ROOT = Path(__file__).resolve().parents[3]
SHADER = ROOT / "game/assets/authored/shaders/golden_hour_sky.gdshader"
BEFORE_SHA = "daf5b419a7026eed3bd5b0e62ce1b3006a5b35b0e4cf15cce7ddb40a2d282c84"
CAP = 0.4
EPS = 1e-5
SCALE = 3.2


def add(a, b): return tuple(x+y for x, y in zip(a, b))
def mul(a, k): return tuple(x*k for x in a)
def mix(a, b, w): return a*(1-w)+b*w
def fract(x): return x-math.floor(x)
def clamp(x, a, b): return min(max(x, a), b)
def smooth(a, b, x):
    t = clamp((x-a)/(b-a), 0., 1.)
    return t*t*(3.-2.*t)


def hash2(p):
    q = (fract(p[0]*123.34), fract(p[1]*456.21))
    v = sum(x*(x+45.32) for x in q)
    return fract((q[0]+v)*(q[1]+v))


def vnoise(p):
    i = tuple(math.floor(x) for x in p)
    f = tuple(fract(x) for x in p)
    f = tuple(x*x*(3.-2.*x) for x in f)
    a, b, c, d = (hash2(add(i, q)) for q in [(0,0),(1,0),(0,1),(1,1)])
    return mix(mix(a,b,f[0]),mix(c,d,f[0]),f[1])


def fbm3(p):
    n = 0.; a = .5
    for _ in range(3):
        n += vnoise(p)*a
        p = (.8*p[0]-.6*p[1], .6*p[0]+.8*p[1])
        p = add(mul(p,2.03),(1.7,9.2)); a *= .5
    return n/.875


def billow(p):
    n = 0.; a = .5
    for _ in range(4):
        n += (1.-abs(vnoise(p)*2.-1.))*a
        p = (.8*p[0]+.6*p[1],-.6*p[0]+.8*p[1])
        p = add(mul(p,2.07),(3.1,4.7)); a *= .42
    return n/.8526


def puff(p):
    i = tuple(math.floor(x) for x in p); f = tuple(fract(x) for x in p)
    md = 1.
    for y in range(-1,2):
        for x in range(-1,2):
            g = (x,y); cell = add(i,g)
            o = (hash2(cell),hash2(add(cell,(17.3,5.9))))
            r = add(add(g,o),mul(f,-1.))
            md = min(md,sum(v*v for v in r))
    return 1.-clamp(math.sqrt(md),0.,1.)


def density(p):
    c = fbm3(mul(p,.8)); w = add(p,(c*.6,-c*.5))
    b = puff(mul(w,1.7))*.62+puff(add(mul(w,3.6),(4.1,2.3)))*.26+billow(mul(w,7.5))*.12
    n = c*.66+b*.50
    cov = .55+.30*(vnoise(add(mul(p,.21),(3.,8.)))-.5)
    lo = 1.17-cov
    return smooth(lo,lo+.07,n)*(.75+.25*smooth(lo+.07,lo+.25,n))


def field(d, new):
    q = (d[0]+EPS,d[2]+EPS); radius = math.hypot(*q)
    if radius == 0 and not new:
        return None  # Legacy normalize(0), not a made-up finite old value.
    dh = mul(q,1./radius) if radius else (0.,0.)
    sh = (.8+EPS,.45+EPS); sh = mul(sh,1./math.hypot(*sh))
    az = clamp(sum(a*b for a,b in zip(dh,sh))*.5+.5,0.,1.)
    direction = dh
    if new and d[1] > 0.:
        weight = smooth(0.,CAP,radius)
        direction = mul(dh,weight)
        if weight < 1.: az = mix(.5,az,weight)
    r = (d[1]+.06)**(-.62)*.68
    p = add(mul(direction,r*SCALE),(7.3,2.1))
    up1, up2, dn1 = (density(add(p,mul(direction,s))) for s in [-.10,-.26,.14])
    sn1, sn2 = (density(add(p,mul(sh,s))) for s in [.10,.26])
    D = density(p); above = up1*.55+up2*.45; toward = sn1*.5+sn2*.5
    base = clamp((D-dn1)*1.6,0.,1.)*above
    light = clamp(1.15-1.05*above-.45*toward*(.4+.6*az)-.55*base+.25*(1.-toward)*az,0.,1.15)
    return {"p":p,"direction":direction,"az":az,"density":D,
            "radial_shadow_samples":(up1,up2,dn1),"light":light}


def ray(radius, angle):
    return radius*math.cos(angle),math.sqrt(max(0.,1.-radius*radius)),radius*math.sin(angle)


def main():
    code = SHADER.read_text()
    # Bind numerical parameters to the actual source; this is still a CPU
    # transcription and cannot establish GPU compilation or output identity.
    assert re.search(r"pole_weight\s*=\s*smoothstep\(0\.0,\s*0\.4,\s*azimuth_radius\)",code)
    assert "vec2 azimuth_ray = d.xz + vec2(1e-5);" in code
    assert "uniform float cloud_scale = 3.2;" in code
    rings = []
    for degrees in [20.,10.,1.5,.1,.001,.00001]:
        radius = math.sin(math.radians(degrees))
        sets = {key:[field(ray(radius,i*math.tau/64),new) for i in range(64)]
                for key,new in [("before",False),("after",True)]}
        row = {"angular_distance_from_true_zenith_degrees":degrees}
        for key, values in sets.items():
            row[key] = {"opposite_x_ray_uv_distance":math.dist(values[0]["p"],values[32]["p"]),
                "azimuth_lighting_range":max(v["az"] for v in values)-min(v["az"] for v in values),
                "density_range":max(v["density"] for v in values)-min(v["density"] for v in values),
                "light_range":max(v["light"] for v in values)-min(v["light"] for v in values),
                "all_field_and_shading_samples_finite":all(math.isfinite(x) for v in values
                    for x in [*v["p"],*v["direction"],v["az"],v["density"],*v["radial_shadow_samples"],v["light"]])}
        rings.append(row)
    singular = (-EPS,math.sqrt(1.-2.*EPS*EPS),-EPS)
    corrected = field(singular,True)
    assert field(singular,False) is None
    assert corrected["p"] == (7.3,2.1) and corrected["az"] == .5
    # Outside the declared cap the same operations/parameters are selected.
    # Compare complete field/shadow/light values, not only projected points.
    outside_count = 0
    for elevation in [.01,5.,20.,40.,60.,65.]:
        radius = math.cos(math.radians(elevation))
        for i in range(64):
            d = ray(radius,i*math.tau/64)
            assert math.hypot(d[0]+EPS,d[2]+EPS) >= CAP
            assert field(d,False) == field(d,True)
            outside_count += 1
    boundary_error = 0.
    for i in range(64):
        # Approach the cap from inside in its actual epsilon-shifted frame.
        q = mul((math.cos(i*math.tau/64),math.sin(i*math.tau/64)),CAP-1e-6)
        x,z = q[0]-EPS,q[1]-EPS
        d = (x,math.sqrt(1.-x*x-z*z),z)
        a,b = field(d,False),field(d,True)
        values_a = [*a['p'],*a['direction'],a['az'],a['density'],*a['radial_shadow_samples'],a['light']]
        values_b = [*b['p'],*b['direction'],b['az'],b['density'],*b['radial_shadow_samples'],b['light']]
        boundary_error = max(boundary_error,max(abs(x-y) for x,y in zip(values_a,values_b)))
    assert boundary_error < 1e-7
    after = hashlib.sha256(SHADER.read_bytes()).hexdigest()
    capture = ROOT/'loop/singapore-fidelity/evidence/helicopter-world-rendered-r1/stills/03_look_up.png'
    if not capture.exists():
        capture = Path('/private/tmp/singapore-fidelity/heli-world-rendered-r1/captures/03_look_up.png')
    result = {"scope":"CPU equation study only; no shader compilation, runtime, render or performance acceptance",
        "shader_before_sha256":BEFORE_SHA,"shader_after_sha256":after,
        "equation_study_script_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "declared_cap":"h > 0 and length(d.xz + vec2(1e-5)) < 0.4; approximately upper23.6degrees",
        "outside_cap_exact_field_shading_comparisons":outside_count,
        "cap_inside_boundary_samples":64,"cap_inside_distance_from_boundary":1e-6,
        "maximum_cap_boundary_field_shading_difference_from_legacy":boundary_error,
        "legacy_shifted_normalize_zero_ray":{"view_ray":singular,"before_defined":False,"after":corrected},
        "true_zenith_after":field((0.,1.,0.),True),"convergence_rings":rings,
        "rendered_capture_inspected":"heli-world-rendered-r1/captures/03_look_up.png",
        "capture_sha256":hashlib.sha256(capture.read_bytes()).hexdigest(),
        "notes":["Legacy epsilon shifts the mathematical normalize-zero ray slightly off true zenith; practical near-zenith rays still sampled a nearly full noise ring.",
                 "Cloud field, radial self-shadow sampling and azimuth-dependent lighting now approach one finite limit together.",
                 "Sun-direction and forward-scattering calculations are unchanged.",
                 "A tiny guard also defines legacy dh where its input is exactlyzero; ordinary defined rays outside the cap retain their old calculation."]}
    output = Path(__file__).with_name('equation-study.json')
    output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    print(json.dumps({"shader_after_sha256":after,"outside_cap_exact_comparisons":outside_count,
                      "near_vertical_1_5_degrees":rings[2],"output":str(output)}))


if __name__ == '__main__': main()
