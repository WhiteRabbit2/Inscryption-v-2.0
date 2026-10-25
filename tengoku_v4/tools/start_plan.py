"""start_plan.py N OUT.json — the CURRENT (v3) clips of chunk N as a plan, clipped to the anime/insert slots (a starting point)."""
import sys, json
sys.path.insert(0, '/home/claude/v4/tools')
from v4lib import *
n = int(sys.argv[1]); ch = load_chunk(n)
slots = [(max(m['t0'], ch['T0']), min(m['t1'], ch['T1'])) for m in ch['mask'] if m['m'] in ('anime', 'insert') and m['t1'] > ch['T0'] and m['t0'] < ch['T1']]
out = []
for c in ch['current']:
    if c['locked'] or not c['ep']: continue
    for a, b in slots:
        x0 = max(a, c['t0']); x1 = min(b, c['t1'])
        if x1 - x0 > 0.03:
            out.append({'t0': round(x0, 2), 't1': round(x1, 2), 'ep': c['ep'], 's0': round(c['s0'] + (x0 - c['t0']), 3), 'why': 'v3'})
json.dump(out, open(sys.argv[2], 'w'), ensure_ascii=False, indent=0); print(len(out), 'clips')
