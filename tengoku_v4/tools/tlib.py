import json, re
def ep_of(c):
    n = c.get('name') or ''
    m = re.search(r'Tengoku Daimakyou - (\d\d)', n)
    if m: return m.group(1)
    return None
def load(fn):
    return json.load(open(fn))
def fmt(fr, tb=25):
    s = fr / tb; m = int(s // 60); return f"{m}:{s - 60*m:05.2f}"
def short(c):
    e = ep_of(c)
    if e: return f"ep{e}@{c['s0']:.2f}-{c['s1']:.2f}"
    return (c.get('name') or '?')[:40]

def clips(J, tr):
    return [c for c in J['tracks'].get(tr, []) if not c.get('tr')]

def visible(J, tracks=('V3', 'V2'), a=0, b=None):
    """Top-most enabled anime/film clip per frame -> merged segments with source mapping."""
    b = b or J['duration']
    lay = {tr: sorted([c for c in clips(J, tr) if c['enabled'] and c['st'] >= 0], key=lambda c: c['st']) for tr in tracks}
    # event points
    pts = {a, b}
    for tr in tracks:
        for c in lay[tr]:
            if c['en'] > a and c['st'] < b: pts.add(max(a, c['st'])); pts.add(min(b, c['en']))
    pts = sorted(pts)
    segs = []
    import bisect
    starts = {tr: [c['st'] for c in lay[tr]] for tr in tracks}
    for x0, x1 in zip(pts, pts[1:]):
        if x1 <= x0: continue
        top = None
        for tr in tracks:
            i = bisect.bisect_right(starts[tr], x0) - 1
            if i >= 0 and lay[tr][i]['en'] > x0:
                top = (tr, lay[tr][i]); break
        if not top:
            segs.append({'st': x0, 'en': x1, 'face': True}); continue
        tr, c = top
        sp = c.get('speed', 100) / 100.0
        s0 = c['s0'] + (x0 - c['st']) / 25 * sp
        s1 = c['s0'] + (x1 - c['st']) / 25 * sp
        seg = {'st': x0, 'en': x1, 'tr': tr, 'ep': ep_of(c), 'name': c['name'], 's0': s0, 's1': s1, 'cid': c['id']}
        p = segs[-1] if segs else None
        if p and not p.get('face') and p.get('cid') == c['id'] and p['en'] == x0:
            p['en'] = x1; p['s1'] = s1
        elif p and p.get('face') and seg.get('face') and p['en'] == x0:
            p['en'] = x1
        else:
            segs.append(seg)
    # merge consecutive face segs
    out = []
    for s in segs:
        if out and s.get('face') and out[-1].get('face') and out[-1]['en'] == s['st']:
            out[-1]['en'] = s['en']
        else:
            out.append(s)
    return out

def voice_map(P, V):
    """pairs (pravki_frame, v3_frame) anchoring voice clips matched by mic source time."""
    vi = {}
    for d in clips(V, 'A1'): vi.setdefault(d['name'], []).append(d)
    pairs = []
    for c in clips(P, 'A1'):
        best = None
        for d in vi.get(c['name'], []):
            ov = min(c['s1'], d['s1']) - max(c['s0'], d['s0'])
            if ov > 0 and (best is None or ov > best[0]): best = (ov, d)
        if best:
            d = best[1]
            # same source instant -> timeline frames
            s = max(c['s0'], d['s0'])
            pairs.append((c['st'] + (s - c['s0']) * 25, d['st'] + (s - d['s0']) * 25))
    pairs.sort()
    return pairs

def map_time(pairs, t):
    import bisect
    i = bisect.bisect_right([p[0] for p in pairs], t) - 1
    if i < 0: i = 0
    return t - pairs[i][0] + pairs[i][1]

_SH = {}
def shots(ep):
    if ep not in _SH:
        d = json.load(open(f'/home/claude/proj/data/shots_ep{ep}.json'))
        _SH[ep] = d
    return _SH[ep]
def shot_idx(ep, t):
    d = shots(ep); sh = d['shots']
    for i, s in enumerate(sh):
        a, b = (s[0], s[1]) if isinstance(s, (list, tuple)) else (s.get('t0', s.get('start')), s.get('t1', s.get('end')))
        if a <= t < b: return i
    return None
