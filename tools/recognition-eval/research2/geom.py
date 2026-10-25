"""Collect LiDAR/RoomPlan box dimensions for each iPad bench photo -> geom.json."""
import json, glob, os
BENCH = "/tmp/claude-501/bench"
rows = [json.loads(l) for l in open(f'{BENCH}/manifest.jsonl')]
geo = {}
for d in glob.glob(f'{BENCH}/ipad_raw/*'):
    s = os.path.basename(d)
    p = f'{d}/geometry.json'
    if os.path.exists(p):
        for o in json.load(open(p)).get('objects', []):
            geo[(s, o['id'])] = dict(dims=o['dimensions'], cat=o.get('category'), y=o['transform']['columns'][3][1])
    p = f'{d}/room.json'
    if os.path.exists(p):
        for o in json.load(open(p)).get('objects', []):
            geo[(s, o['identifier'])] = dict(dims=o['dimensions'], cat=list(o['category'])[0], y=o['transform'][13])
out = {}
for r in rows:
    if r['split'] != 'ipad':
        continue
    g = geo.get((r['scan'], r.get('object_id')))
    out[r['path']] = g
    if g:
        W, H, D = g['dims']
        print(f"{r['label']:12s} {r['true_object'][:30]:30s} cat={str(g['cat']):12s} W={W:.2f} H={H:.2f} D={D:.2f} y={g['y']:.2f}")
    else:
        print('MISS', r['label'], r['true_object'], r.get('object_id'))
json.dump(out, open(os.path.dirname(os.path.abspath(__file__)) + '/geom.json', 'w'))
