"""Shared helpers for the v4 re-edit (anime layer V2 on Vlad's «правки» timeline)."""
import json, glob, os, sys
sys.path.insert(0, '/home/claude/v3/at')
from common import shots, shot_at, is_bad, frame, sheet, FONT, FONTB, AF
from PIL import Image, ImageDraw
V4 = '/home/claude/v4'
FPS = 25
FR = 1 / AF                     # one source frame (23.976)
def load_chunk(n): return json.load(open(f'{V4}/chunks/chunk_{int(n):02d}.json'))
def load_all(): return json.load(open(f'{V4}/all.json'))
def load_plan(fn):
    p = json.load(open(fn))
    for x in p:
        x['ep'] = f"{int(x['ep']):02d}" if x.get('ep') else None
        x['t0'] = round(round(x['t0'] * FPS) / FPS, 2); x['t1'] = round(round(x['t1'] * FPS) / FPS, 2)
        x['s1'] = x['s0'] + (x['t1'] - x['t0'])
    return sorted(p, key=lambda x: x['t0'])
def plans_except(n):
    out = []
    for fn in sorted(glob.glob(f'{V4}/plans/plan_*.json')):
        k = int(os.path.basename(fn)[5:7])
        if k != int(n):
            for x in load_plan(fn): x['chunk'] = k; out.append(x)
    return out
def visible_stream(n, plan):
    """locked clips of the whole range + this plan + other chunks' plans (or current for chunks without a plan)."""
    A = load_all(); b = A['bounds']
    have = {int(os.path.basename(fn)[5:7]) for fn in glob.glob(f'{V4}/plans/plan_*.json')}
    out = []
    for c in A['current']:
        if c['locked']:
            out.append({**c, 'src': 'locked'}); continue
        # unlocked current clip: kept only in chunks with no plan yet (as context)
        k = max(i for i in range(len(b) - 1) if b[i] <= (c['t0'] + c['t1']) / 2) if (c['t0'] + c['t1']) / 2 < b[-1] else None
        if k is None: continue
        if k != int(n) and k not in have: out.append({**c, 'src': f'cur{k}'})
    for x in plans_except(n): out.append({**x, 'src': f"plan{x['chunk']}"})
    for x in plan: out.append({**x, 'src': 'plan'})
    return sorted(out, key=lambda x: x['t0'])
def words_in(chunk, a, b):
    ws = []
    for v in chunk['voice']:
        for w0, w1, w in v['words']:
            if a - 0.05 <= (w0 + w1) / 2 < b: ws.append(w)
    return ' '.join(ws)
def subs_in(chunk, a, b):
    out = []
    for x in chunk['inserts']:
        if x['t1'] <= a or x['t0'] >= b: continue
        for s0, s1, txt in x['subs']:
            tl0 = x['t0'] + (s0 - x['s0']); tl1 = x['t0'] + (s1 - x['s0'])
            if tl1 > a and tl0 < b and txt not in out: out.append(txt)
    return ' / '.join(out)
def shot_of(ep, t):
    s = shot_at(ep, t); return s['i'] if s else None
