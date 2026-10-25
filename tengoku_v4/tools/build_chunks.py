"""Chunk data for the v4 re-edit of the anime layer (V2) on HIS timeline («Стена v3 (перемонтаж)_правки»).
python3 build_chunks.py T_END_SEC N_CHUNKS
Output: v4/chunks/chunk_NN.json and v4/all.json (whole range)."""
import sys, json, re, glob, bisect
sys.path.insert(0, '/home/claude/v4tools')
from tlib import *
W = '/home/claude/work'
P = load(f'{W}/pravki.json'); V = load(f'{W}/v3.json')
T_END = float(sys.argv[1]) if len(sys.argv) > 1 else 1800.0
NCH = int(sys.argv[2]) if len(sys.argv) > 2 else 6
FPS = 25

# ---------- v3 chunks: voice words (v3 timeline), pid, script ----------
SEG = []; SCRIPT = {}
for fn in sorted(glob.glob('/home/claude/v3/chunks3/chunk_*.json')):
    c = json.load(open(fn))
    SEG += [s for s in c['segments'] if s['type'] == 'voice']
    SCRIPT.update(c['script'])
SEG.sort(key=lambda s: s['t0'])
seg_t0 = [s['t0'] for s in SEG]
def v3seg(v3clip):
    t = v3clip['st'] / FPS
    i = bisect.bisect_left(seg_t0, t - 0.05)
    for s in SEG[i:i + 3]:
        if abs(s['t0'] - t) < 0.05: return s
    return None

# ---------- subtitles (AniLibria .ass with end times) ----------
def ass(ep):
    out = []
    fn = f'/home/claude/proj/data/subs/ep{ep}_ru_anilibria.ass'
    for l in open(fn, encoding='utf-8-sig'):
        if not l.startswith('Dialogue:'): continue
        p = l.split(',', 9)
        def t(x):
            h, m, s = x.split(':'); return int(h) * 3600 + int(m) * 60 + float(s)
        txt = re.sub(r'\{[^}]*\}', '', p[9].strip()).replace('\\N', ' ')
        out.append((t(p[1]), t(p[2]), txt))
    return sorted(out)
_SUB = {}
def subs(ep, a, b):
    if ep not in _SUB: _SUB[ep] = ass(ep)
    return [(round(x, 2), round(y, 2), z) for x, y, z in _SUB[ep] if x < b and y > a]

# ---------- voice on his timeline ----------
va = clips(V, 'A1'); vi = {}
for d in va: vi.setdefault(d['name'], []).append(d)
voice = []
for c in clips(P, 'A1'):
    if c['st'] / FPS >= T_END + 30: break
    if not (c['name'] or '').startswith('Untitled'): continue
    words = []; pid = None; mode = None
    for d in vi.get(c['name'], []):
        if min(c['s1'], d['s1']) - max(c['s0'], d['s0']) <= 0: continue
        s = v3seg(d)
        if not s: continue
        pid = pid or s.get('pid'); mode = mode or s.get('mode')
        for w0, w1, w in s['words']:
            m0 = d['s0'] + (w0 - d['st'] / FPS); m1 = d['s0'] + (w1 - d['st'] / FPS)
            mid = (m0 + m1) / 2
            if c['s0'] - 0.02 <= mid <= c['s1'] + 0.02:
                words.append([round(c['st'] / FPS + m0 - c['s0'], 2), round(c['st'] / FPS + m1 - c['s0'], 2), w])
    voice.append({'t0': c['st'] / FPS, 't1': c['en'] / FPS, 'mic': c['name'], 'pid': pid, 'mode': mode,
                  'text': ' '.join(w[2] for w in words), 'words': words})

# ---------- inserts (episode audio on A3, and his episode audio on A1) ----------
ins = []
for tr in ('A3', 'A1'):
    for c in clips(P, tr):
        e = ep_of(c)
        if not e or c['st'] / FPS >= T_END + 30: continue
        ins.append({'t0': c['st'] / FPS, 't1': c['en'] / FPS, 'ep': e, 's0': round(c['s0'], 3), 's1': round(c['s1'], 3),
                    'track': tr, 'subs': subs(e, c['s0'], c['s1'])})
ins.sort(key=lambda x: x['t0'])
g = 0
for i, x in enumerate(ins):
    if i and not (x['ep'] == ins[i - 1]['ep'] and x['t0'] - ins[i - 1]['t1'] < 0.2 and 0 <= x['s0'] - ins[i - 1]['s1'] < 12):
        g += 1
    x['g'] = g

# ---------- locked clips: his V3 + his changed V2 ----------
v3v2 = clips(V, 'V2')
def cowork(c):
    e = ep_of(c)
    for d in v3v2:
        if d['name'] == c['name'] and abs(d['s0'] - c['s0']) < 0.05 and abs(d['s1'] - c['s1']) < 0.05: return True
    return False
pv2 = [c for c in clips(P, 'V2') if c['enabled']]
pv3 = [c for c in clips(P, 'V3') if c['enabled']]
locked_ids = set(c['id'] for c in pv3) | set(c['id'] for c in pv2 if c['st'] / FPS < T_END + 30 and (not cowork(c) or not ep_of(c)))

# ---------- frame mask ----------
N = int(round((T_END + 30) * FPS))
cov2 = bytearray(N); cov3 = bytearray(N); insm = bytearray(N); lockm = bytearray(N)
for c in pv2:
    for f in range(max(0, c['st']), min(N, c['en'])):
        cov2[f] = 1
        if c['id'] in locked_ids: lockm[f] = 1
for c in pv3:
    for f in range(max(0, c['st']), min(N, c['en'])): cov3[f] = 1; lockm[f] = 1
for x in ins:
    for f in range(max(0, int(round(x['t0'] * FPS))), min(N, int(round(x['t1'] * FPS)))): insm[f] = 1
def kind(f):
    if cov3[f] or lockm[f]: return 'locked'
    if not cov2[f]: return 'face'
    return 'insert' if insm[f] else 'anime'
mask = []
for f in range(N):
    k = kind(f)
    if mask and mask[-1]['m'] == k: mask[-1]['t1'] = (f + 1) / FPS
    else: mask.append({'m': k, 't0': f / FPS, 't1': (f + 1) / FPS})

# ---------- current visible stream ----------
cur = []
for s in visible(P, ('V3', 'V2'), 0, N):
    if s.get('face'): continue
    d = {'t0': s['st'] / FPS, 't1': s['en'] / FPS, 'ep': s['ep'], 'file': None if s['ep'] else s['name'],
         's0': round(s['s0'], 3), 's1': round(s['s1'], 3), 'locked': s['cid'] in locked_ids, 'track': s['tr']}
    if s['ep']: d['shot'] = shot_idx(s['ep'], s['s0'] + 0.01)
    cur.append(d)

# ---------- chunk boundaries at long face stretches near equal splits ----------
faces = [m for m in mask if m['m'] == 'face' and m['t1'] - m['t0'] >= 2.0 and m['t1'] <= T_END]
bounds = [0.0]
for k in range(1, NCH):
    target = T_END * k / NCH
    best = min(faces, key=lambda m: abs((m['t0'] + m['t1']) / 2 - target))
    bounds.append(round((best['t0'] + best['t1']) / 2, 2))
end = next((m for m in mask if m['m'] == 'face' and m['t0'] >= T_END - 1 and m['t1'] - m['t0'] >= 1.0), None)
T_STOP = round((end['t0'] + end['t1']) / 2, 2) if end else T_END
bounds.append(T_STOP)

def cut(lst, a, b, k0='t0', k1='t1'):
    return [x for x in lst if x[k1] > a and x[k0] < b]
allc = {'T0': 0.0, 'T1': T_STOP, 'bounds': bounds}
json.dump({'mask': cut(mask, 0, T_STOP), 'voice': cut(voice, 0, T_STOP), 'inserts': cut(ins, 0, T_STOP),
           'current': cut(cur, 0, T_STOP), **allc}, open('/home/claude/v4/all.json', 'w'), ensure_ascii=False)
for i, (a, b) in enumerate(zip(bounds, bounds[1:])):
    vc = cut(voice, a, b)
    pids = []
    for v in vc:
        if v['pid'] and v['pid'] not in pids: pids.append(v['pid'])
    # include neighbour script lines
    keys = list(SCRIPT.keys())
    sel = {}
    for p in pids:
        if p in SCRIPT: sel[p] = SCRIPT[p]
    ch = {'chunk': i, 'T0': a, 'T1': b, 'mask': cut(mask, a, b), 'voice': vc, 'inserts': cut(ins, a, b),
          'current': cut(cur, a - 20, b + 20), 'script': sel}
    json.dump(ch, open(f'/home/claude/v4/chunks/chunk_{i:02d}.json', 'w'), ensure_ascii=False, indent=0)
    nm = {k: round(sum(m['t1'] - m['t0'] for m in cut(mask, a, b) if m['m'] == k), 1) for k in ('anime', 'insert', 'locked', 'face')}
    print(i, fmt(a * 25), fmt(b * 25), 'voice', len(vc), 'ins', len(cut(ins, a, b)), 'cur', len(cut(cur, a, b)), nm)
print('locked clips', len(locked_ids))
