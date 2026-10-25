import json,os,shutil,collections,sys
from PIL import Image
B='/tmp/claude-501/bench'; W=B+'/dl/wm'; S=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,S)
LABEL={'scooter':'scooter','vacuum':'vacuum','office_chair':'chair','rug':'rug','heater':'heater','ironing_board':'ironing board','yoga_mat':'yoga mat','fan':'fan'}
REL=json.load(open(S+'/relabel.json'))
RELLAB={'ceiling_fan':'ceiling fan','heater':'heater'}
drop=set(l.strip() for l in open(S+'/drop.txt')) if os.path.exists(S+'/drop.txt') else set()
CAP=60
rows=[]
# public crops
for l in open(B+'/dl/crops.jsonl'):
    c=json.loads(l)
    if c['path'] in drop:
        if os.path.exists(B+'/'+c['path']): os.remove(B+'/'+c['path'])
        continue
    if not os.path.exists(B+'/'+c['path']) and c['path'] not in REL: continue
    lic=c['license']
    if c['path'] in REL:
        new=REL[c['path']]; np_='images/'+new+'/'+os.path.basename(c['path'])
        os.makedirs(B+'/images/'+new,exist_ok=True); os.rename(B+'/'+c['path'],B+'/'+np_)
        c['path']=np_; c['cls']=new; c['label']=RELLAB[new]
    elif c['cls']=='fan' and not os.path.exists(B+'/'+c['path']): continue
    rows.append(dict(path=c['path'],split='public',label=c['label'],fine_label=c['cls'],source=c['src'],original_class=c['orig'],
        license=lic,author=c.get('author',''),source_page=c.get('page',''),image_url=c['url'],crop_box_px=c['crop_px'],indoor_hint=c['indoor'],
        noncommercial=('NonCommercial' in lic)))
# wikimedia picks (whole object-centric photos, not box crops)
for l in open(S+'/wm_keep.txt'):
    cls,sheet,idx=l.split(); sheet=int(sheet)
    fs=sorted(f for f in os.listdir(f'{W}/{cls}') if f.lower().endswith(('.jpg','.png')))
    meta={}
    for m in open(f'{W}/{cls}/_meta.jsonl'): m=json.loads(m); meta[m['file']]=m
    for i in map(int,idx.split(',')):
        f=fs[sheet*24+i]; p=f'images/{cls}/{f}'
        if p in drop: continue
        os.makedirs(f'{B}/images/{cls}',exist_ok=True)
        im=Image.open(f'{W}/{cls}/{f}').convert('RGB'); im.thumbnail((800,800)); im.save(f'{B}/{p}',quality=88)
        m=meta[f]
        rows.append(dict(path=p,split='public',label=LABEL[cls],fine_label=cls,source='Wikimedia Commons',original_class='Category: '+m['title'],
            license=m['license'],license_url=m['license_url'],author=m['author'],source_page=m['page'],crop_box_px=None,indoor_hint=None,noncommercial=False))
# cap per class: prefer keeping wikimedia + indoor, drop extras
by=collections.defaultdict(list)
for r in rows: by[r['fine_label']].append(r)
final=[]
for cls,rs in by.items():
    rs.sort(key=lambda r:(r['source']=='Wikimedia Commons', not r['indoor_hint']))
    keep=rs[:CAP] if any(r['source']=='Wikimedia Commons' for r in rs) else rs[:40]
    for r in rs:
        if r not in keep and os.path.exists(B+'/'+r['path']): os.remove(B+'/'+r['path'])
    final+=keep
with open(B+'/manifest.jsonl','w') as f:
    for r in final: f.write(json.dumps(r)+'\n')
    for l in open(B+'/ipad_manifest.jsonl'): f.write(l)
cnt=collections.defaultdict(collections.Counter)
for r in final: cnt[r['fine_label']][r['source'].split(' ')[0]]+=1
for k in sorted(cnt): print(k, sum(cnt[k].values()), dict(cnt[k]))
print('public total',len(final))
