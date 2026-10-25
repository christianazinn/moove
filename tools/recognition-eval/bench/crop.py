import json,os,urllib.request,concurrent.futures as cf,collections
from PIL import Image, ImageOps
B='/tmp/claude-501/bench'; CACHE=B+'/dl/cache'; os.makedirs(CACHE,exist_ok=True)
cands=[json.loads(l) for l in open(B+'/dl/candidates.jsonl')]
def fetch(url):
    fn=os.path.join(CACHE,url.split('/')[-2]+'_'+url.split('/')[-1])
    if os.path.exists(fn) and os.path.getsize(fn)>0: return fn
    try:
        data=urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'MooveBench/0.1'}),timeout=90).read()
        open(fn,'wb').write(data); return fn
    except Exception as e: return None
urls=sorted({c['url'] for c in cands})
with cf.ThreadPoolExecutor(24) as ex: res=dict(zip(urls,ex.map(fetch,urls)))
print('downloaded',sum(1 for v in res.values() if v),'of',len(urls))
out=open(B+'/dl/crops.jsonl','w'); n=collections.Counter()
for c in cands:
    fn=res.get(c['url'])
    if not fn: continue
    try: im=Image.open(fn); im.load(); im=im.convert('RGB')
    except Exception: continue
    W,H=im.size
    if 'box_norm' in c:
        x0,y0,x1,y1=c['box_norm']; x0*=W;x1*=W;y0*=H;y1*=H
    else:
        x0,y0,x1,y1=c['box_px']; sx,sy=W/c['wh'][0],H/c['wh'][1]; x0*=sx;x1*=sx;y0*=sy;y1*=sy
    pw,ph=(x1-x0)*0.1,(y1-y0)*0.1
    box=(max(0,int(x0-pw)),max(0,int(y0-ph)),min(W,int(x1+pw)),min(H,int(y1+ph)))
    if min(box[2]-box[0],box[3]-box[1])<48: continue
    cr=im.crop(box); cr.thumbnail((800,800))
    tag='oi' if c['src'].startswith('Open') else 'lvis'
    n[c['cls']]+=1
    p=f"images/{c['cls']}/{tag}_{c['img']}_{n[c['cls']]:03d}.jpg"
    os.makedirs(os.path.dirname(B+'/'+p),exist_ok=True); cr.save(B+'/'+p,quality=88)
    c['path']=p; c['crop_px']=box; c['crop_size']=cr.size
    out.write(json.dumps(c)+'\n')
print(dict(n))
