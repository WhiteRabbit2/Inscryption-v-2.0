"""validate4.py OUT.xml — structure + content checks of the v4 XML against Vlad's export."""
import sys, json, re, subprocess
import xml.etree.ElementTree as ET
sys.path.insert(0, '/home/claude/v4tools')
from tlib import load, clips, ep_of, visible, fmt
TPS = 254016000000
X = sys.argv[1]; AD_AT, AD_LEN = 13305, 1972
root = ET.parse(X).getroot(); seq = root.find('sequence')
errs = []
def items(tr): return [c for c in tr if c.tag in ('clipitem', 'transitionitem')]
tracks = [('V%d' % (i + 1), t) for i, t in enumerate(seq.find('media/video').findall('track'))] + \
         [('A%d' % (i + 1), t) for i, t in enumerate(seq.find('media/audio').findall('track'))]
where = {}
for name, tr in tracks:
    its = items(tr); prev_end = -1
    for ci, el in enumerate(its):
        where[el.get('id')] = (name, ci + 1)
        if el.tag != 'clipitem': continue
        S, E = int(el.findtext('start')), int(el.findtext('end'))
        if S >= 0 and E >= 0:
            if E <= S: errs.append(('len<=0', name, el.get('id')))
            if S < prev_end: errs.append(('overlap', name, el.get('id'), S, prev_end))
            prev_end = max(prev_end, E)
            pi, po = el.findtext('pproTicksIn'), el.findtext('pproTicksOut')
            if pi and po and re.search(r'Tengoku Daimakyou - \d\d', el.findtext('name') or '') and name.startswith('V'):
                if abs((int(po) - int(pi)) - (E - S) * TPS // 25) > 2: errs.append(('ticks-len', name, el.get('id')))
                if int(el.findtext('out')) - int(el.findtext('in')) != E - S: errs.append(('inout-len', name, el.get('id')))
        elif E >= 0: prev_end = max(prev_end, E)
for name, tr in tracks:
    for el in items(tr):
        for ln in el.findall('link'):
            ref = ln.findtext('linkclipref')
            if ref not in where: errs.append(('link-missing', el.get('id'), ref)); continue
            tn, cx = where[ref]
            if int(ln.findtext('trackindex')) != int(tn[1:]) or int(ln.findtext('clipindex')) != cx or ln.findtext('mediatype') != ('video' if tn[0] == 'V' else 'audio'):
                errs.append(('link-index', el.get('id'), ref))
seen = set()
for name, tr in tracks:
    for el in items(tr):
        f = el.find('file')
        if f is None: continue
        if f.get('id') not in seen:
            seen.add(f.get('id'))
            if len(f) == 0: errs.append(('file-first-empty', el.get('id'), f.get('id')))
            if name.startswith('A') and f.find('media/audio') is None: errs.append(('file-no-audio', el.get('id'), f.get('id')))
print('structure errors:', len(errs)); [print('  ', e) for e in errs[:30]]
# ---------- content vs his export ----------
S = '/tmp/claude-0/-home-user-Inscryption-v-2-0/d95f30c3-7b85-50c8-93eb-b3082d9e7805/scratchpad'
subprocess.run(['python3', f'{S}/tools/xparse.py', X, '/home/claude/work/_val.json'], check=True, capture_output=True)
N = load('/home/claude/work/_val.json'); P = load('/home/claude/work/pravki.json')
ad = N['duration'] - P['duration']
print('duration', fmt(N['duration']), 'his', fmt(P['duration']), 'diff', ad)
def m(t): return t + ad if t >= AD_AT else t
for tr in ('V1', 'A1', 'A2', 'A3', 'A4', 'V3', 'V4', 'V5'):
    a = [((c['st'] + ad, c['en'] + ad) if c['st'] >= AD_AT else (c['st'], c['en'])) + (c['name'], round(c['s0'], 2)) for c in clips(P, tr)]
    b = [(c['st'], c['en'], c['name'], round(c['s0'], 2)) for c in clips(N, tr) if not (ad and AD_AT <= c['st'] < AD_AT + ad)]
    print(f'{tr}: his {len(a)} new(outside ad) {len(b)} same={sorted(a) == sorted(b)}')
def cover(J, shift):
    fr = set()
    for tr in ('V2', 'V3'):
        for c in clips(J, tr):
            if not c['enabled']: continue
            off = ad if (shift and c['st'] >= AD_AT) else 0
            for f in range(c['st'], c['en']): fr.add(f + off)
    return fr
cp = cover(P, True); cn = cover(N, False)
cn_out = {f for f in cn if not (ad and AD_AT <= f < AD_AT + ad)}
print('anime coverage frames his', len(cp), 'new (outside ad)', len(cn_out), 'only-his', len(cp - cn_out), 'only-new', len(cn_out - cp))
diff = sorted(cp ^ cn_out)
if diff:
    runs = []; s = diff[0]; p = s
    for f in diff[1:] + [None]:
        if f is None or f != p + 1:
            runs.append((s, p)); s = f
        p = f if f is not None else p
    print('coverage differences:', [(fmt(a), b - a + 1) for a, b in runs[:20]])
# gaps between V2 clips (face flashes)
v2 = sorted([c for c in clips(N, 'V2') if c['enabled']], key=lambda c: c['st'])
g = [(c['st'], d['st'] - c['en']) for c, d in zip(v2, v2[1:]) if 0 < d['st'] - c['en'] < 8]
print('V2 gaps 1-7 frames:', len(g), [fmt(a) for a, _ in g[:10]])
