"""v4board.py N OUT.jpg [--from MM:SS|sec] [--to …] [--plan PLAN.json] [--cur] — storyboard of the visible anime layer:
one tile per clip (middle frame; small first/last frames), caption: time, duration, ep@source #shot, L = his locked clip,
the voice words under the clip, «ВСТ:» insert dialogue. Red caption = rule problem. --cur shows the CURRENT edit."""
import sys, argparse, textwrap
sys.path.insert(0, '/home/claude/v4/tools')
from v4lib import *
ap = argparse.ArgumentParser(); ap.add_argument('n', type=int); ap.add_argument('out')
ap.add_argument('--from', dest='a'); ap.add_argument('--to', dest='b'); ap.add_argument('--plan'); ap.add_argument('--cur', action='store_true')
ap.add_argument('--cols', type=int, default=5)
o = ap.parse_args()
def sec(v):
    if v is None: return None
    if ':' in v: m, s = v.split(':'); return int(m) * 60 + float(s)
    return float(v)
ch = load_chunk(o.n)
a = sec(o.a) if o.a else ch['T0']; b = sec(o.b) if o.b else ch['T1']
if o.cur:
    S = [dict(x, src='locked' if x['locked'] else 'cur') for x in ch['current']]
else:
    plan = load_plan(o.plan or f'{V4}/plans/plan_{o.n:02d}.json')
    S = visible_stream(o.n, plan)
S = [x for x in S if x['t1'] > a and x['t0'] < b]
TW, TH = 288, 162
tiles = []
for i, x in enumerate(S):
    im = Image.new('RGB', (TW, TH + 92), (18, 18, 18))
    if x.get('ep'):
        mid = (x['s0'] + x['s1']) / 2
        im.paste(frame(x['ep'], mid, TW), (0, 0))
        f0 = frame(x['ep'], x['s0'] + 0.05, 96); f1 = frame(x['ep'], x['s1'] - 0.05, 96)
        im.paste(f0, (0, TH - 54)); im.paste(f1, (TW - 96, TH - 54))
    d = ImageDraw.Draw(im)
    prev = S[i - 1] if i else None
    bad = []
    if prev and prev.get('ep') and prev.get('ep') == x.get('ep') and x['t0'] - prev['t1'] <= 3 and -0.5 <= x['s0'] - prev['s1'] <= 30:
        ip = shot_of(prev['ep'], prev['s1'] - 0.01); ix = shot_of(x['ep'], x['s0'] + 0.01)
        if ip is not None and ix is not None and ix - ip == 1: bad.append('NEXT')
    if x.get('ep'):
        a_ = shot_of(x['ep'], x['s0'] + 0.01); b_ = shot_of(x['ep'], x['s1'] - 0.01)
        if a_ != b_: bad.append('SPAN')
    if x.get('ep') and is_bad(x['ep'], x['s0'], x['s1']): bad.append('BAD')
    dur = x['t1'] - x['t0']
    sh = shot_of(x['ep'], x['s0'] + 0.01) if x.get('ep') else None
    lab = f"{int(x['t0'] // 60)}:{x['t0'] % 60:04.1f} {dur:.1f}s " + (f"ep{x['ep']}@{x['s0']:.1f} #{sh}" if x.get('ep') else (x.get('file') or '')[:18])
    if x.get('src') == 'locked': lab += ' L'
    if bad: lab += ' ' + ','.join(bad)
    d.rectangle((0, 0, TW, 15), fill=(0, 0, 0)); d.text((3, 1), lab, fill=(255, 70, 70) if bad else (255, 230, 0), font=FONTB)
    ws = words_in(ch, x['t0'], x['t1']); ss = subs_in(ch, x['t0'], x['t1'])
    txt = (f'ВСТ: {ss}' if ss else '') + (('  | ' if ss and ws else '') + ws if ws else '')
    y = TH + 2
    for line in textwrap.wrap(txt, 44)[:5]:
        d.text((3, y), line, fill=(120, 200, 255) if txt.startswith('ВСТ') else (230, 230, 230), font=FONT); y += 15
    if x.get('why'):
        d.text((3, TH + 77), x['why'][:46], fill=(150, 150, 150), font=FONT)
    tiles.append(im)
sheet(tiles, o.cols, o.out); print(o.out, len(tiles), 'tiles')
