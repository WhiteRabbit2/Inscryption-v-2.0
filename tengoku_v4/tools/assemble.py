"""Build the v4 sequence XML from Vlad's export («правки») + v4 plans + the Durev ad.
python3 assemble.py OUT.xml [--no-ad]
- V2 (unlocked Cowork clips) in [0, T_STOP] replaced by plans/plan_*.json (unlinked clips);
- links to removed V2 clips dropped, every <link> clipindex recomputed by id;
- all episode audio (A3/A4 inserts, his episode audio on A1/A2) at least +8 dB (2.51189);
- Durev ad (all tracks of «Стена_v3_с_графикой_и_рекламой» [13444, +1972)) inserted at his 13305 with ripple;
  in the ad the toothbrush shot 01@189.31 (next shot of the original before 01@192.61) -> 02@660.50 (Kiruko with a toothbrush);
- first occurrence of every file id carries the full <file> description."""
import sys, json, glob, copy, re, uuid, math
import xml.etree.ElementTree as ET
sys.path.insert(0, '/home/claude/v4tools')
from tlib import load, clips, ep_of
TPS = 254016000000; FPS = 25; TPF = TPS // FPS
IN = '/home/claude/work/in_pravki.xml'; ADX = '/home/claude/work/in_v3_gfx_ad.xml'
AD_SRC0, AD_LEN, AD_AT = 13444, 1972, 13305
GAIN8 = 2.51189
out_fn = sys.argv[1]; with_ad = '--no-ad' not in sys.argv
A = json.load(open('/home/claude/v4/all.json')); T_STOP = int(round(A['T1'] * FPS))
V3J = load('/home/claude/work/v3.json')

tree = ET.parse(IN); root = tree.getroot(); seq = root.find('sequence')
VT = seq.find('media/video').findall('track'); AT = seq.find('media/audio').findall('track')
def items(tr): return [c for c in tr if c.tag in ('clipitem', 'transitionitem')]

# ---------- full file definitions ----------
FULL = {}
def harvest(r, prefix=''):
    for f in r.iter('file'):
        if f.get('id') and len(f):
            k = prefix + f.get('id')
            if k not in FULL: FULL[k] = copy.deepcopy(f)
harvest(root)

# ---------- plans ----------
import os
plan = []
for fn in sorted(glob.glob(os.environ.get('PLANS', '/home/claude/v4/plans') + '/plan_*.json')):
    plan += json.load(open(fn))
plan.sort(key=lambda x: x['t0'])
PLAN_END = max(int(round(x['t1'] * FPS)) for x in plan) if plan else T_STOP
# ---------- 1. remove replaceable V2 clips ----------
v3v2 = [(c['name'], c['s0'], c['s1']) for c in clips(V3J, 'V2')]
def ticks_s(ci, tag): v = ci.findtext(tag); return int(v) / TPS if v is not None else None
def cowork(ci):
    nm = ci.findtext('name'); s0 = ticks_s(ci, 'pproTicksIn'); s1 = ticks_s(ci, 'pproTicksOut')
    return any(n == nm and abs(a - s0) < 0.05 and abs(b - s1) < 0.05 for n, a, b in v3v2)
V2 = VT[1]
removed = set(); templates = {}
for ci in V2.findall('clipitem'):
    nm = ci.findtext('name') or ''
    m = re.search(r'Tengoku Daimakyou - (\d\d)', nm)
    if m and m.group(1) not in templates: templates[m.group(1)] = copy.deepcopy(ci)
    st = int(ci.findtext('start'))
    en = int(ci.findtext('end'))
    if m and st < T_STOP and (ci.findtext('enabled') or 'TRUE').upper() == 'TRUE' and cowork(ci):
        if en > T_STOP and en > PLAN_END:
            # keep the tail after the plan's end
            d = max(T_STOP, PLAN_END) - st
            ci.find('start').text = str(st + d); ci.find('in').text = str(int(ci.findtext('in')) + d)
            ci.find('pproTicksIn').text = str(int(ci.findtext('pproTicksIn')) + d * TPF)
            print('kept tail of', ci.get('id'), 'from', st + d, 'to', en)
            continue
        removed.add(ci.get('id')); V2.remove(ci)
print('removed V2 clips:', len(removed))

# ---------- 2. new V2 clips from plans ----------
_n = [0]
def new_clip(ep, st, en, s0, idprefix='clipitem-v4-'):
    t = templates[f'{int(ep):02d}']
    ci = copy.deepcopy(t); _n[0] += 1
    ci.set('id', f'{idprefix}{_n[0]}')
    for l in ci.findall('link'): ci.remove(l)
    ci.find('start').text = str(st); ci.find('end').text = str(en)
    ti = int(round(s0 * TPS)); ti -= ti % 1  # exact ticks
    inn = int(round(s0 * FPS))
    ci.find('in').text = str(inn); ci.find('out').text = str(inn + en - st)
    ci.find('pproTicksIn').text = str(ti); ci.find('pproTicksOut').text = str(ti + (en - st) * TPF)
    f = ci.find('file'); fid = f.get('id')
    for ch in list(f): f.remove(ch)
    return ci
newv2 = []
for x in plan:
    st = int(round(x['t0'] * FPS)); en = int(round(x['t1'] * FPS))
    if en <= st: continue
    newv2.append(new_clip(x['ep'], st, en, x['s0']))
for ci in newv2: V2.append(ci)
print('new V2 clips:', len(newv2))

# ---------- 3. drop links to removed clips ----------
for tr in VT + AT:
    for ci in tr.findall('clipitem'):
        for l in ci.findall('link'):
            if l.findtext('linkclipref') in removed: ci.remove(l)
        # a link set with only the clip itself is noise
        ls = ci.findall('link')
        if len(ls) == 1 and ls[0].findtext('linkclipref') == ci.get('id'): ci.remove(ls[0])

# ---------- 4. episode audio >= +8 dB ----------
ng = 0
for tr in AT:
    for ci in tr.findall('clipitem'):
        if not re.search(r'Tengoku Daimakyou - \d\d', ci.findtext('name') or ''): continue
        for flt in ci.findall('filter'):
            if flt.findtext('effect/effectid') == 'audiolevels':
                for p in flt.findall('effect/parameter'):
                    if p.findtext('parameterid') == 'level':
                        v = float(p.findtext('value'))
                        if v < GAIN8 - 1e-4: p.find('value').text = str(GAIN8); ng += 1
print('insert clips raised to +8 dB:', ng)

# ---------- 5. Durev ad ----------
adclips = []
if with_ad:
    def shift(e):
        st_, en_ = int(e.findtext('start')), int(e.findtext('end'))
        if st_ >= AD_AT or (st_ == -1 and en_ > AD_AT):
            for tag in ('start', 'end'):
                el = e.find(tag)
                if int(el.text) >= 0: el.text = str(int(el.text) + AD_LEN)
        elif en_ > AD_AT:
            raise SystemExit(f'clip straddles the ad point: {e.get("id")} {st_}-{en_}')
    for tr in VT + AT:
        for e in items(tr): shift(e)
    for mk in seq.findall('marker'):
        el = mk.find('in')
        if int(el.text) >= AD_AT: el.text = str(int(el.text) + AD_LEN)
    seq.find('duration').text = str(int(seq.findtext('duration')) + AD_LEN)
    ad = ET.parse(ADX).getroot().find('sequence')
    harvest(ad.getparent() if hasattr(ad, 'getparent') else ET.parse(ADX).getroot(), prefix='AD:')
    AVT = ad.find('media/video').findall('track'); AAT = ad.find('media/audio').findall('track')
    idmap = {}; fmap = {}; mmap = {}; adclips.clear()
    def take(src_tracks, dst_tracks, kinds):
        for ti, (st_, dt_) in enumerate(zip(src_tracks, dst_tracks)):
            for ci in st_.findall('clipitem'):
                s = int(ci.findtext('start')); e = int(ci.findtext('end'))
                if not (AD_SRC0 <= s < AD_SRC0 + AD_LEN): continue
                c = copy.deepcopy(ci)
                nid = 'clipitem-ad4-' + ci.get('id').split('-')[-1] + f'-{len(idmap)}'
                idmap[ci.get('id')] = nid; c.set('id', nid)
                c.find('start').text = str(s - AD_SRC0 + AD_AT); c.find('end').text = str(e - AD_SRC0 + AD_AT)
                f = c.find('file')
                if f is not None:
                    fid = f.get('id'); nf = fmap.setdefault(fid, 'file-ad4-' + str(len(fmap) + 1)); f.set('id', nf)
                    if len(f):
                        FULL.setdefault(nf, copy.deepcopy(f))
                    elif 'AD:' + fid in FULL:
                        g = copy.deepcopy(FULL['AD:' + fid]); g.set('id', nf); FULL.setdefault(nf, g)
                mc = c.find('masterclipid')
                if mc is not None: mc.text = mmap.setdefault(mc.text, 'masterclip-ad4-' + str(len(mmap) + 1))
                adclips.append((dt_, c))
    take(AVT, VT, 'video'); take(AAT, AT, 'audio')
    for dt_, c in adclips:
        for l in c.findall('link'):
            r = l.findtext('linkclipref')
            if r in idmap: l.find('linkclipref').text = idmap[r]
            else: c.remove(l)
    # ad shot fixes: (ep, source start) -> (new ep, new source start)
    AD_FIX = {('01', 734.10): ('04', 1068.50),   # Mimihime close-up: 01@734.1 is used at 8:10 by the new edit; pensive Mimihime from ep 4
              ('02', 588.80): ('02', 234.78)}    # «Хэллоуин»: moon with tentacles is used at 16:11 by the new edit; full moon in clouds (02 #98)
    for dt_, c in list(adclips):
        nm = c.findtext('name') or ''
        m_ = re.search(r'Tengoku Daimakyou - (\d\d)', nm)
        if not m_ or dt_ is not VT[1]: continue
        s0 = int(c.findtext('pproTicksIn')) / TPS
        for (fe, fs), (ne, ns) in AD_FIX.items():
            if m_.group(1) == fe and abs(s0 - fs) < 0.05:
                st = int(c.findtext('start')); en = int(c.findtext('end'))
                nc = new_clip(ne, st, en, ns, idprefix='clipitem-ad4fix-')
                idx = adclips.index((dt_, c)); adclips[idx] = (dt_, nc); print('ad shot replaced', fe, fs, '->', ne, ns)
    # toothbrush 01#71 (189.31) then toilet paper 01#72 (192.61) were the original order: show the paper first
    # (Maru lifts it like a treasure: «сокровища там посерьёзнее…»), then Kiruko with the toothbrush
    tb = [(i, c) for i, (dt_, c) in enumerate(adclips) if dt_ is VT[1] and 'Tengoku Daimakyou - 01' in (c.findtext('name') or '')
          and abs(int(c.findtext('pproTicksIn')) / TPS - 189.31) < 0.05]
    tp = [(i, c) for i, (dt_, c) in enumerate(adclips) if dt_ is VT[1] and 'Tengoku Daimakyou - 01' in (c.findtext('name') or '')
          and abs(int(c.findtext('pproTicksIn')) / TPS - 192.61) < 0.05]
    if tb and tp:
        (ia, a_), (ib, b_) = tb[0], tp[0]
        sa, ea = int(a_.findtext('start')), int(a_.findtext('end')); sb, eb = int(b_.findtext('start')), int(b_.findtext('end'))
        assert ea == sb
        lp = eb - sb
        adclips[ia] = (VT[1], new_clip('01', sa, sa + lp, 192.61, idprefix='clipitem-ad4fix-'))
        adclips[ib] = (VT[1], new_clip('01', sa + lp, eb, 189.31, idprefix='clipitem-ad4fix-'))
        print('ad: paper/toothbrush swapped', sa, sa + lp, eb)
    # 04@247.16 ran across the cut #124 (Tokio tiny on the wall) -> #125 (camera lens): lens first, then the wall
    tw = [(i, c) for i, (dt_, c) in enumerate(adclips) if dt_ is VT[1] and 'Tengoku Daimakyou - 04' in (c.findtext('name') or '')
          and abs(int(c.findtext('pproTicksIn')) / TPS - 247.16) < 0.05]
    if tw:
        i, c = tw[0]; sa, ea = int(c.findtext('start')), int(c.findtext('end'))
        adclips[i] = (VT[1], new_clip('04', sa, sa + 30, 249.00, idprefix='clipitem-ad4fix-'))
        adclips.insert(i + 1, (VT[1], new_clip('04', sa + 30, ea, 247.14, idprefix='clipitem-ad4fix-')))
        print('ad: lens/wall reordered', sa, ea)
    for dt_, c in adclips: dt_.append(c)
    print('ad clips added:', len(adclips))

# ---------- 6. place new items in time order without disturbing transition chains ----------
NEWIDS = set(c.get('id') for c in newv2) | (set(c.get('id') for _, c in adclips) if with_ad else set())
def rstart(lst, i):
    e = lst[i]; s_ = int(e.findtext('start'))
    if s_ >= 0: return s_
    j = i - 1
    while j >= 0:
        sj = int(lst[j].findtext('start'))
        if sj >= 0: return sj
        j -= 1
    return 0
for tr in VT + AT:
    its = items(tr)
    old = [e for e in its if e.get('id') not in NEWIDS]
    new = sorted([e for e in its if e.get('id') in NEWIDS], key=lambda e: int(e.findtext('start')))
    if not new: continue
    for e in its: tr.remove(e)
    rs = [rstart(old, i) for i in range(len(old))]
    merged = []; j = 0
    for i, e in enumerate(old):
        while j < len(new) and int(new[j].findtext('start')) < rs[i] and not (e.tag == 'transitionitem' or int(e.findtext('start')) < 0):
            merged.append(new[j]); j += 1
        merged.append(e)
    merged += new[j:]
    others = [i for i, c in enumerate(list(tr)) if c.tag in ('enabled', 'locked', 'outputchannelindex')]
    at = others[0] if others else len(tr)
    for k, e in enumerate(merged): tr.insert(at + k, e)

# ---------- 7. file definitions: full at first occurrence, refs after ----------
seen = set()
for kind in ('video', 'audio'):
    for tr in seq.find('media/' + kind).findall('track'):
        for ci in tr.findall('clipitem'):
            f = ci.find('file')
            if f is None: continue
            fid = f.get('id')
            if fid not in seen:
                seen.add(fid)
                if not len(f):
                    if fid not in FULL: raise SystemExit(f'no full definition for {fid}')
                    g = copy.deepcopy(FULL[fid]); g.set('id', fid)
                    i = list(ci).index(f); ci.remove(f); ci.insert(i, g)
            else:
                for ch in list(f): f.remove(ch)

# ---------- 8. relink by id ----------
pos = {}
for kind in ('video', 'audio'):
    for ti, tr in enumerate(seq.find('media/' + kind).findall('track'), 1):
        for ci_i, e in enumerate(items(tr), 1):
            if e.tag == 'clipitem': pos[e.get('id')] = (kind, ti, ci_i)
nl = 0; dropped = 0
for kind in ('video', 'audio'):
    for tr in seq.find('media/' + kind).findall('track'):
        for ci in tr.findall('clipitem'):
            for l in ci.findall('link'):
                r = l.findtext('linkclipref')
                if r not in pos: ci.remove(l); dropped += 1; continue
                k, ti, cx = pos[r]
                l.find('mediatype').text = k; l.find('trackindex').text = str(ti); l.find('clipindex').text = str(cx); nl += 1
print('links', nl, 'dropped', dropped)

# ---------- 9. name, uuid, write ----------
seq.find('name').text = 'Стена v4 (первые 30 мин + Durev)' if with_ad else 'Стена v4 (первые 30 мин)'
u = seq.find('uuid')
if u is not None: u.text = str(uuid.uuid4())
xml = ET.tostring(root, encoding='unicode')
open(out_fn, 'w', encoding='utf-8').write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n' + xml)
print('written', out_fn)
