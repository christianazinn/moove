# usage: commons.py <outdir> <class> <maxfiles> <Category1> [Category2 ...]  (prefix cat with + to include subcats 1 level)
import json,sys,os,urllib.request,urllib.parse,re,html,time
UA='MooveBench/0.1 (research eval dataset; ros97@stanford.edu)'
def api(**p):
    p.update(format='json')
    req=urllib.request.Request('https://commons.wikimedia.org/w/api.php?'+urllib.parse.urlencode(p),headers={'User-Agent':UA})
    return json.load(urllib.request.urlopen(req,timeout=60))
def members(cat,typ):
    out=[];cont={}
    while True:
        d=api(action='query',list='categorymembers',cmtitle='Category:'+cat,cmtype=typ,cmlimit=500,**cont)
        out+= [m['title'] for m in d['query']['categorymembers']]
        if 'continue' not in d: return out
        cont=d['continue']; cont.pop('continue',None)
outdir,cls,maxn=sys.argv[1],sys.argv[2],int(sys.argv[3])
titles=[]
for c in sys.argv[4:]:
    sub=c.startswith('+'); c=c.lstrip('+')
    titles+=members(c,'file')
    if sub:
        for sc in members(c,'subcat'): titles+=members(sc.split(':',1)[1],'file')
seen=set(); titles=[t for t in titles if not (t in seen or seen.add(t)) and re.search(r'\.(jpe?g|png)$',t,re.I)]
os.makedirs(f'{outdir}/{cls}',exist_ok=True)
meta=open(f'{outdir}/{cls}/_meta.jsonl','a')
n=0
for i in range(0,len(titles),40):
    if n>=maxn: break
    d=api(action='query',titles='|'.join(titles[i:i+40]),prop='imageinfo',iiprop='url|extmetadata|size',iiurlwidth=640)
    for pg in d['query']['pages'].values():
        if n>=maxn: break
        ii=pg.get('imageinfo',[{}])[0]; em=ii.get('extmetadata',{})
        lic=em.get('LicenseShortName',{}).get('value','')
        if not re.search(r'CC0|Public domain|PD|CC BY',lic,re.I) or re.search(r'NC|ND',lic): continue
        url=ii.get('thumburl') or ii.get('url')
        fn=f"{outdir}/{cls}/wm_{pg['pageid']}.jpg"
        try:
            req=urllib.request.Request(url,headers={'User-Agent':UA}); data=urllib.request.urlopen(req,timeout=60).read()
        except Exception as e: print('fail',url,e); continue
        open(fn,'wb').write(data); n+=1
        artist=re.sub('<[^>]+>','',html.unescape(em.get('Artist',{}).get('value','')))[:120]
        meta.write(json.dumps({'file':os.path.basename(fn),'title':pg['title'],'page':ii.get('descriptionurl'),'license':lic,'license_url':em.get('LicenseUrl',{}).get('value',''),'author':artist.strip()})+'\n')
        time.sleep(0.2)
print(cls,n,'of',len(titles))
