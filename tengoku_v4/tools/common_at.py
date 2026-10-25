"""Общие функции инструментов подбора кадров (агенты). Время серий = время MKV = время лёгких копий epNN.mp4."""
import json, re, glob, os
import cv2, numpy as np
from PIL import Image, ImageDraw, ImageFont
P = '/home/claude/proj'; V3 = '/home/claude/v3'
FONT = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 12)
FONTB = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 13)
AF = 24000 / 1001
def ep2(ep): return f'{int(ep):02d}'
_SH = {}
def shots(ep):
    ep = ep2(ep)
    if ep not in _SH: _SH[ep] = json.load(open(f'{P}/data/shots_ep{ep}.json'))['shots']
    return _SH[ep]
def shot_at(ep, t):
    for s in shots(ep):
        if s['t0'] <= t < s['t1']: return s
    return None
CAT = {}
for l in open(f'{P}/data/CATALOG.md', encoding='utf-8'):
    m = re.match(r'- (\d+)@(\d+):(\d+(?:\.\d+)?)\s+(.*)', l)
    if not m: continue
    ep = ep2(m.group(1)); body = f'{m.group(2)}:{m.group(3)} ' + m.group(4).strip()
    # строка каталога: «ММ:СС.с описание; ММ:СС.с описание…» — режем на подстроки со своим временем
    parts = re.split(r'(?:^|;\s*|\.\s+|,\s+)(?:—\s*)?(?:\d+@)?(?=\d{1,2}:\d{2}(?:\.\d+)?\s)', body)
    for p in parts:
        mm = re.match(r'(\d{1,2}):(\d{2}(?:\.\d+)?)\s*[–-]?\s*(?:\d{1,2}:\d{2}(?:\.\d+)?)?\s*(.*)', p.strip())
        if mm: CAT.setdefault(ep, []).append((int(mm.group(1)) * 60 + float(mm.group(2)), mm.group(3).strip(' —;.')))
BAD = re.compile(r'кров(?!ат)|труп|голая(?! кровать)|голый|обнаж|наг[ао]я|грудь|интим|поцел|ванн|душ\b|кишк|внутренност|мясо|разорв|съеда|пожира|не брать|эндинг|опенинг|титры|пошл', re.I)
BAD_RANGES = {}
for _l in open(f'{P}/data/CATALOG.md', encoding='utf-8'):
    if not BAD.search(_l): continue
    for _m in re.finditer(r'(\d+)@(\d+):(\d+(?:\.\d+)?)\s*[–-]\s*(?:\d+@)?(\d+):(\d+(?:\.\d+)?)', _l):
        _e = ep2(_m.group(1)); _a = int(_m.group(2)) * 60 + float(_m.group(3)); _b = int(_m.group(4)) * 60 + float(_m.group(5))
        if _b > _a: BAD_RANGES.setdefault(_e, []).append((_a, _b))
for _e in ('04', '05', '07', '09'): BAD_RANGES.setdefault(_e, []).append((1329.5, 1e9))
BAD_RANGES.setdefault('08', []).append((1222.0, 1e9))
for _e in ('02', '06', '07', '08', '09'): BAD_RANGES.setdefault(_e, []).append((0.0, 91.5))
BAD_RANGES.setdefault('05', []).append((208.0, 300.5))
for _e, _a, _b in (('01', 1338.5, 1e9), ('02', 1329.9, 1411.6), ('03', 1272.9, 1362.4), ('06', 1245.0, 1335.0), ('03', 90.9, 181.0), ('04', 19.7, 130.0),
                   ('06', 1354.8, 1357.35), ('06', 1359.5, 1361.95), ('06', 239.15, 242.0), ('09', 261.2, 265.2), ('09', 272.6, 283.8),
                   ('10', 1320.0, 1e9), ('11', 1320.0, 1e9), ('12', 1320.0, 1e9), ('13', 1419.0, 1e9), ('10', 0.0, 91.5), ('13', 0.0, 91.5),
                   ('11', 74.0, 164.5), ('12', 155.0, 247.5), ('04', 995.3, 997.5)):   # опенинги 11 и 12 серий — после холодного начала (проверено глазами 25.10)
    BAD_RANGES.setdefault(_e, []).append((_a, _b))
if os.path.exists(f'{V3}/at/bad_extra.json'):          # планы, отбракованные глазами (нагота, кровь, роды, интим)
    for _e, _a, _b in json.load(open(f'{V3}/at/bad_extra.json')): BAD_RANGES.setdefault(_e, []).append((_a, _b))
GOOD_FIX = [('04', 992.7, 995.0), ('05', 325.0, 332.0), ('05', 335.0, 343.0), ('05', 352.0, 360.0)]     # строка каталога ошибочно дала хороший кусок как BAD (плохое — с 16:35.3)
for _e, _a, _b in GOOD_FIX:
    BAD_RANGES[_e] = [r for r in BAD_RANGES.get(_e, []) if not (abs(r[0] - _a) < 0.05 and abs(r[1] - _b) < 0.05)]
def is_bad(ep, a, b):
    ep = ep2(ep)
    return any(x < b and a < y for x, y in BAD_RANGES.get(ep, []))
def cat_near(ep, a, b, pad=1.0):
    return [(t, d) for t, d in CAT.get(ep2(ep), []) if a - pad <= t <= b + pad]
_CAP = {}
def frame(ep, t, w=256):
    ep = ep2(ep)
    if ep not in _CAP: _CAP[ep] = cv2.VideoCapture(f'{P}/video/ep{ep}.mp4')
    cap = _CAP[ep]; cap.set(cv2.CAP_PROP_POS_MSEC, t * 1000); ok, f = cap.read()
    if not ok: f = np.zeros((360, 640, 3), np.uint8)
    return Image.fromarray(cv2.cvtColor(cv2.resize(f, (w, w * 9 // 16)), cv2.COLOR_BGR2RGB))
def sheet(tiles, cols, out):
    if not tiles: return
    w, h = tiles[0].size
    rows = (len(tiles) + cols - 1) // cols
    S = Image.new('RGB', (cols * w, rows * h), (20, 20, 20))
    for i, im in enumerate(tiles): S.paste(im, ((i % cols) * w, (i // cols) * h))
    S.save(out, quality=80)
def fmt(t): return f'{int(t // 60)}:{t % 60:04.1f}'
