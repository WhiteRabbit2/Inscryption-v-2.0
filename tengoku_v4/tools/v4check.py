"""v4check.py N [PLAN.json] - check plan of chunk N against the v4 rules. E = must fix, W = look at it.
Rules: covers every anime/insert slot exactly; nothing over face/locked; clip >= 1.2 s (no upper limit; >6 s under voice is a W);
inside ONE source shot with 0.06 s margin (a clip across a cut = two original shots in a row); no BAD; no repeats of a source
moment within 15 min; NO NEXT SHOT: a clip may not be followed (<=3 s later on the timeline) by the NEXT shot of the same
episode going forward (shot N then shot N+1). Shot N+2 after N, or going back, is fine (Vlad's rule)."""
import sys, json
sys.path.insert(0, '/home/claude/v4/tools')
from v4lib import *
n = int(sys.argv[1])
fn = sys.argv[2] if len(sys.argv) > 2 else f'{V4}/plans/plan_{n:02d}.json'
ch = load_chunk(n); plan = load_plan(fn)
E, W = [], []
def tc(t): return f'{int(t // 60)}:{t % 60:05.2f}'
T0, T1 = ch['T0'], ch['T1']
# --- coverage ---
need = [(m['t0'], m['t1'], m['m']) for m in ch['mask'] if m['m'] in ('anime', 'insert') and m['t1'] > T0 and m['t0'] < T1]
for a, b, k in need:
    a = max(a, T0); b = min(b, T1); t = a
    cov = sorted([(x['t0'], x['t1']) for x in plan if x['t1'] > a and x['t0'] < b])
    for x0, x1 in cov:
        if x0 - t > 0.045: E.append(f'HOLE {tc(t)}–{tc(x0)} ({k}) not covered')
        t = max(t, x1)
    if b - t > 0.045: E.append(f'HOLE {tc(t)}–{tc(b)} ({k}) not covered')
for x in plan:
    for m in ch['mask']:
        if m['m'] in ('face', 'locked'):
            ov = min(x['t1'], m['t1']) - max(x['t0'], m['t0'])
            if ov > 0.045: E.append(f"OVER {tc(x['t0'])} clip lies {ov:.2f}s over {m['m']} {tc(m['t0'])}–{tc(m['t1'])}")
for a, b in zip(plan, plan[1:]):
    if b['t0'] < a['t1'] - 0.01: E.append(f"OVERLAP {tc(a['t0'])} and {tc(b['t0'])}")
# --- per clip ---
for x in plan:
    d = x['t1'] - x['t0']; t = tc(x['t0']); ep = x['ep']
    if not ep: E.append(f'{t} no ep'); continue
    own_ins0 = any(i['ep'] == ep and min(i['s1'], x['s0'] + d) - max(i['s0'], x['s0']) > 0.1 for i in ch['inserts'])
    if d > 6.0 + 1e-6 and not own_ins0: W.append(f'{t} long {d:.2f}s under voice (pace: 2–4 s, >6 s drags)')
    if d < 1.2 - 1e-6: E.append(f'{t} SHORT {d:.2f}s < 1.2')
    elif d < 1.6 - 1e-6: W.append(f'{t} short {d:.2f}s')
    s0, s1 = x['s0'], x['s1']
    a = shot_at(ep, s0 + 0.001); b = shot_at(ep, s1 - 0.001)
    if a is None or b is None: E.append(f'{t} ep{ep}@{s0:.2f} outside episode'); continue
    if a['i'] != b['i']: E.append(f"{t} SPAN ep{ep}@{s0:.2f}-{s1:.2f} crosses the cut #{a['i']}->#{b['i']} = two shots of the original in a row: split it and put another shot between")
    else:
        if s0 - a['t0'] < 0.06 or a['t1'] - s1 < 0.06:
            E.append(f"{t} EDGE ep{ep}@{s0:.2f}-{s1:.2f} within 1.5 frames of shot #{a['i']} [{a['t0']:.2f}-{a['t1']:.2f}] (flash)")
    own_ins = any(i['ep'] == ep and min(i['s1'], s1) - max(i['s0'], s0) > 0.1 for i in ch['inserts'])
    if is_bad(ep, s0, s1):
        (W if own_ins else E).append(f'{t} BAD ep{ep}@{s0:.2f}-{s1:.2f} (blood/nudity/titles/OP/ED…)' + (' — insert original, look at it' if own_ins else ''))
    if not x.get('why'): W.append(f'{t} no why')
# --- stream checks ---
S = visible_stream(n, plan)
def same_ep(a, b): return a.get('ep') and a.get('ep') == b.get('ep')
def fwd(a, b, gap=20.0): return same_ep(a, b) and -0.5 <= b['s0'] - a['s1'] <= gap
inrange = lambda x: x['t1'] > T0 - 3 and x['t0'] < T1 + 3
def sidx(x, t):
    s = shot_at(x['ep'], t); return s['i'] if s else -99
for i in range(len(S) - 1):
    a, b = S[i], S[i + 1]
    if not inrange(a) and not inrange(b): continue
    if 'plan' not in (a['src'], b['src']): continue
    if b['t0'] - a['t1'] > 3.0: continue
    if fwd(a, b, 30):
        ia = sidx(a, a['s1'] - 0.01); ib = sidx(b, b['s0'] + 0.01); gap = b['s0'] - a['s1']
        if ib - ia == 1:
            E.append(f"{tc(b['t0'])} FWD ep{a['ep']}@{a['s0']:.2f}-{a['s1']:.2f} #{ia} -> @{b['s0']:.2f} #{ib}: the NEXT shot of the original follows - reorder or put another shot between")
        elif ib == ia:
            W.append(f"{tc(b['t0'])} jump ep{a['ep']} same shot #{ia} continues ({gap:+.1f}s) - a jump cut; better another shot between")
    if i + 2 < len(S):
        c = S[i + 2]
        if 'plan' in (a['src'], b['src'], c['src']) and same_ep(a, b) and same_ep(b, c) and c['t0'] - a['t1'] <= 10:
            ia, ib, ic = sidx(a, a['s0'] + 0.01), sidx(b, b['s0'] + 0.01), sidx(c, c['s0'] + 0.01)
            if 0 < ib - ia <= 2 and 0 < ic - ib <= 2:
                W.append(f"{tc(a['t0'])} run3 ep{a['ep']} shots #{ia} -> #{ib} -> #{ic}: three shots almost in the original order")
# repeats across the whole 0–30 min (plans + locked + current of chunks without plans)
for x in plan:
    for y in S:
        if y is x or y.get('src') == 'plan' and y['t0'] == x['t0']: continue
        if not same_ep(x, y): continue
        ov = min(x['s1'], y['s1']) - max(x['s0'], y['s0'])
        if ov > 0.3 and abs(y['t0'] - x['t0']) > 0.01:
            xi = any(i['ep'] == x['ep'] and min(i['s1'], x['s1']) - max(i['s0'], x['s0']) > 0.1 for i in ch['inserts'])
            (E if abs(y['t0'] - x['t0']) < 900 and not xi else W).append(
                f"{tc(x['t0'])} REPEAT ep{x['ep']}@{x['s0']:.2f} also at {tc(y['t0'])} ({y['src']}) overlap {ov:.1f}s")
# other-episode clips: list for visual check
eps = {}
for x in plan: eps[x['ep']] = eps.get(x['ep'], 0) + (x['t1'] - x['t0'])
main = max(eps, key=eps.get) if eps else None
for x in plan:
    if x['ep'] != main: W.append(f"{tc(x['t0'])} FILL ep{x['ep']}@{x['s0']:.2f} (other episode: same place, time of day, people? say so in why)")
E = list(dict.fromkeys(E)); W = list(dict.fromkeys(W))
print(f'chunk {n}: {len(plan)} clips, E={len(E)} W={len(W)}')
for e in E: print('E', e)
for w in W: print('W', w)
