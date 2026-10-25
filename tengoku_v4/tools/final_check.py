"""final_check.py OUT.xml [T_END_SEC_NEW] — rules on the VISIBLE anime layer (V3 over V2) of an assembled sequence."""
import sys, json, subprocess
sys.path.insert(0, '/home/claude/v4tools'); sys.path.insert(0, '/home/claude/v3/at')
from tlib import load, visible, fmt
from common import shot_at, is_bad
S = '/tmp/claude-0/-home-user-Inscryption-v-2-0/d95f30c3-7b85-50c8-93eb-b3082d9e7805/scratchpad'
X = sys.argv[1]; TEND = float(sys.argv[2]) if len(sys.argv) > 2 else 1879.0
subprocess.run(['python3', f'{S}/tools/xparse.py', X, '/home/claude/work/_fc.json'], check=True, capture_output=True)
J = load('/home/claude/work/_fc.json')
vis = [s for s in visible(J, ('V3', 'V2'), 0, int(TEND * 25)) if not s.get('face') and s['ep']]
def si(ep, t):
    s = shot_at(ep, t); return s['i'] if s else None
adj, span, short, rep = [], [], [], []
for a, b in zip(vis, vis[1:]):
    if a['ep'] == b['ep'] and (b['st'] - a['en']) / 25 <= 3 and -0.5 <= b['s0'] - a['s1'] <= 30:
        ia, ib = si(a['ep'], a['s1'] - 0.01), si(b['ep'], b['s0'] + 0.01)
        if ib is not None and ia is not None and ib - ia == 1: adj.append((fmt(b['st']), a['ep'], ia, ib, a['tr'], b['tr']))
for s in vis:
    a, b = si(s['ep'], s['s0'] + 0.01), si(s['ep'], s['s1'] - 0.01)
    if a != b: span.append((fmt(s['st']), s['ep'], round(s['s0'], 2), a, b, s['tr']))
    if (s['en'] - s['st']) / 25 < 1.2: short.append((fmt(s['st']), round((s['en'] - s['st']) / 25, 2), s['tr']))
for i, x in enumerate(vis):
    for y in vis[i + 1:]:
        if (y['st'] - x['st']) / 25 > 900: break
        if x['ep'] == y['ep'] and min(x['s1'], y['s1']) - max(x['s0'], y['s0']) > 0.3:
            rep.append((fmt(x['st']), fmt(y['st']), x['ep'], round(x['s0'], 1)))
print(f'visible clips {len(vis)} | next-shot pairs {len(adj)} | clips across a cut {len(span)} | <1.2 s {len(short)} | repeats<15min {len(rep)}')
for k, v in (('NEXT', adj), ('SPAN', span), ('SHORT', short), ('REPEAT', rep)):
    for x in v[:60]: print(k, *x)
