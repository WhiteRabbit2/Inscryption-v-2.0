"""Parse an FCP7 xmeml sequence into flat clip lists per track.
python3 xparse.py IN.xml OUT.json
Each clip: kind (V/A), track (1-based), idx, st, en (timeline frames), inn, out, s0, s1 (source seconds from pproTicks
or in/out / timebase), file id, name, path, enabled, levels_db (audio), speed."""
import sys, json, re, math
import xml.etree.ElementTree as ET
from urllib.parse import unquote
TPS = 254016000000

def main(fn, out):
    root = ET.parse(fn).getroot()
    seq = root.find('sequence')
    files = {}
    for f in root.iter('file'):
        fid = f.get('id')
        if fid and (f.find('pathurl') is not None or f.find('name') is not None):
            if fid not in files or 'path' not in files[fid]:
                d = {'name': f.findtext('name')}
                p = f.findtext('pathurl')
                if p: d['path'] = unquote(p)
                tb = f.findtext('rate/timebase'); nt = f.findtext('rate/ntsc')
                if tb: d['tb'] = int(tb); d['ntsc'] = (nt or 'FALSE').upper() == 'TRUE'
                files[fid] = d
    res = {'name': seq.findtext('name'), 'duration': int(seq.findtext('duration') or 0),
           'tb': int(seq.findtext('rate/timebase')), 'tracks': {}, 'markers': []}
    for m in seq.findall('marker'):
        res['markers'].append({'name': m.findtext('name'), 'in': int(m.findtext('in'))})
    media = seq.find('media')
    for kind, tag in (('V', 'video'), ('A', 'audio')):
        sec = media.find(tag)
        if sec is None: continue
        for ti, tr in enumerate(sec.findall('track'), 1):
            clips = []
            for ci, el in enumerate(list(tr)):
                if el.tag not in ('clipitem', 'transitionitem'): continue
                if el.tag == 'transitionitem':
                    clips.append({'tr': True, 'idx': ci, 'st': int(el.findtext('start')), 'en': int(el.findtext('end')),
                                  'name': el.findtext('effect/name')})
                    continue
                f = el.find('file'); fid = f.get('id') if f is not None else None
                fd = files.get(fid, {})
                c = {'idx': ci, 'id': el.get('id'), 'st': int(el.findtext('start')), 'en': int(el.findtext('end')),
                     'inn': int(el.findtext('in')), 'out': int(el.findtext('out')), 'fid': fid,
                     'name': fd.get('name') or el.findtext('name'), 'path': fd.get('path'),
                     'enabled': (el.findtext('enabled') or 'TRUE').upper() == 'TRUE'}
                rt = el.findtext('rate/timebase')
                tb = int(rt) if rt else res['tb']
                pi, po = el.findtext('pproTicksIn'), el.findtext('pproTicksOut')
                if pi is not None and po is not None:
                    c['s0'] = int(pi) / TPS; c['s1'] = int(po) / TPS
                else:
                    c['s0'] = c['inn'] / tb; c['s1'] = c['out'] / tb
                st = el.find('sourcetrack')
                if st is not None: c['srctrack'] = st.findtext('trackindex')
                for flt in el.findall('filter'):
                    eid = flt.findtext('effect/effectid') or ''
                    if eid == 'audiolevels' or (flt.findtext('effect/name') or '') == 'Audio Levels':
                        v = flt.findtext('effect/parameter/value')
                        if v:
                            try: c['gain'] = float(v); c['db'] = round(20 * math.log10(float(v)), 2) if float(v) > 0 else None
                            except ValueError: pass
                    if eid == 'timeremap':
                        for p in flt.findall('effect/parameter'):
                            if p.findtext('parameterid') == 'speed': c['speed'] = float(p.findtext('value'))
                    if eid == 'basic':
                        for p in flt.findall('effect/parameter'):
                            pid = p.findtext('parameterid')
                            if pid == 'scale': c['scale'] = float(p.findtext('value'))
                            if pid == 'center':
                                h = p.findtext('value/horiz'); v = p.findtext('value/vert')
                                if h is not None: c['center'] = [float(h), float(v)]
                clips.append(c)
            # resolve -1 starts/ends from neighbouring transitions
            for i, c in enumerate(clips):
                if c.get('tr'): continue
                if c['st'] == -1:
                    j = i - 1
                    if j >= 0 and clips[j].get('tr'): c['st'] = clips[j]['st']; c['st_tr'] = True
                if c['en'] == -1:
                    j = i + 1
                    if j < len(clips) and clips[j].get('tr'): c['en'] = clips[j]['en']; c['en_tr'] = True
            res['tracks'][f'{kind}{ti}'] = clips
    json.dump(res, open(out, 'w'), ensure_ascii=False)
    print(res['name'], res['duration'], {k: len(v) for k, v in res['tracks'].items()})

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
