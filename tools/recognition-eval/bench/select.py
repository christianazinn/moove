import csv,json,random,collections,sys,os
random.seed(7)
D='/tmp/claude-501/bench/dl'
TARGET=40
# fine class -> (moove label, OI classes, LVIS cats, wikimedia dir)
C={
 'scooter':('scooter',[],[],'scooter'),
 'vacuum':('vacuum',[],['vacuum_cleaner'],'vacuum'),
 'bicycle':('bicycle',['Bicycle'],['bicycle'],None),
 'chair':('chair',['Chair'],['chair','armchair','folding_chair'],None),
 'office_chair':('chair',[],[],'office_chair'),
 'sofa':('sofa',['Couch','Studio couch','Sofa bed'],['sofa'],None),
 'bed':('bed',['Bed'],['bed','bunk_bed'],None),
 'table':('table',['Table','Coffee table','Kitchen & dining room table'],['table','coffee_table','dining_table'],None),
 'desk':('table',['Desk'],['desk'],None),
 'dresser':('storage',['Chest of drawers'],['dresser'],None),
 'nightstand':('storage',['Nightstand'],[],None),
 'cabinet':('storage',['Filing cabinet','Cupboard','Wardrobe'],['file_cabinet'],None),
 'bookshelf':('storage',['Bookcase'],['bookcase'],None),
 'shelf':('shelf',['Shelf'],[],None),
 'lamp':('lamp',['Lamp'],['lamp','table_lamp'],None),
 'television':('television',['Television'],['television_set'],None),
 'monitor':('monitor',['Computer monitor'],['monitor_(computer_equipment) computer_monitor'],None),
 'laptop':('laptop',['Laptop'],['laptop_computer'],None),
 'refrigerator':('refrigerator',['Refrigerator'],['refrigerator'],None),
 'microwave':('microwave',['Microwave oven'],['microwave_oven'],None),
 'toilet':('toilet',['Toilet'],['toilet'],None),
 'sink':('sink',['Sink'],['sink','kitchen_sink'],None),
 'bathtub':('bathtub',['Bathtub'],['bathtub'],None),
 'shower_curtain':('shower curtain',[],['shower_curtain'],None),
 'mirror':('mirror',['Mirror'],['mirror'],None),
 'plant':('plant',['Houseplant'],['flowerpot'],None),
 'rug':('rug',[],['bath_mat','doormat'],'rug'),
 'suitcase':('suitcase',['Suitcase'],['suitcase'],None),
 'backpack':('backpack',['Backpack'],['backpack'],None),
 'bag':('bag',[],['duffel_bag'],None),
 'trash_can':('trash can',['Waste container'],['trash_can'],None),
 'box':('box',['Box'],['box','carton'],None),
 'guitar':('guitar',['Guitar'],['guitar'],None),
 'fan':('fan',['Mechanical fan'],['fan'],None),
 'heater':('heater',['Heater'],['heater'],'heater'),
 'radiator':('radiator',[],['radiator'],None),
 'ironing_board':('ironing board',[],['ironing_board'],'ironing_board'),
 'stroller':('stroller',[],['baby_buggy'],None),
 'yoga_mat':('yoga mat',[],['mat_(gym_equipment)'],'yoga_mat'),
 'washing_machine':('washerDryer',['Washing machine'],['automatic_washer'],None),
 'ladder':('ladder',['Ladder'],['ladder','stepladder','step_stool'],None),
 'towel_rack':('towel rack',[],['towel_rack'],None),
 'ottoman':('ottoman',[],['ottoman'],None),
 'dolly_cart':('cart',[],['handcart'],None),
}
INDOOR_OI={'Couch','Bed','Desk','Shelf','Cupboard','Chest of drawers','Lamp','Television','Sink','Toilet','Refrigerator','Curtain','Countertop','Fireplace','Picture frame','Ceiling fan','Bookcase','Nightstand','Stairs','Window blind','Kitchen & dining room table','Coffee table','Computer monitor','Bathtub','Microwave oven','Studio couch','Sofa bed','Cabinetry','Drawer','Wardrobe','Houseplant'}
INDOOR_LV={'sofa','bed','desk','bookcase','cabinet','drawer','lamp','lampshade','television_set','sink','toilet','refrigerator','curtain','fireplace','picture','pillow','cushion','coffee_table','monitor_(computer_equipment) computer_monitor','bathtub','microwave_oven','dresser','armchair','rug','blinds','shower_curtain','towel_rack','radiator','wall_socket','light_bulb','chandelier','doorknob','clock','vase','book','bookcase'}
OUTDOOR_LV={'car_(automobile)','bus_(vehicle)','truck','traffic_light','street_sign','lamppost','tree','sky','grass','motorcycle','train_(railroad_vehicle)','boat','umbrella','bench','parking_meter','fireplug'}
cands=collections.defaultdict(list)
# ---- Open Images
names={r[0]:r[1] for r in csv.reader(open(f'{D}/oi/oidv7-class-descriptions-boxable.csv'))}
want_oi={n:k for k,v in C.items() for n in v[1]}
imginfo={}
for split,f in [('validation','validation-images-with-rotation.csv'),('test','test-images-with-rotation.csv')]:
    for r in csv.DictReader(open(f'{D}/oi/{f}')):
        imginfo[r['ImageID']]=(split,r['License'],r['Author'],r['OriginalLandingURL'],r['Rotation'])
labels=collections.defaultdict(set); boxes=[]
for f in ['validation-annotations-bbox.csv','test-annotations-bbox.csv']:
    for r in csv.DictReader(open(f'{D}/oi/{f}')):
        n=names.get(r['LabelName']); labels[r['ImageID']].add(n)
        if n in want_oi and r['IsGroupOf']=='0' and r['IsDepiction']=='0':
            x0,x1,y0,y1=map(float,(r['XMin'],r['XMax'],r['YMin'],r['YMax']))
            if (x1-x0)>=0.1 and (y1-y0)>=0.1 and (x1-x0)*(y1-y0)>=0.02:
                boxes.append((want_oi[n],n,r['ImageID'],(x0,y0,x1,y1),r['IsOccluded'],r['IsTruncated']))
for cls,n,iid,b,occ,tr in boxes:
    sp,lic,auth,land,rot=imginfo[iid]
    if rot not in ('','0','0.0'): continue
    indoor=len(labels[iid]&INDOOR_OI)>0
    cands[(cls,'oi')].append(dict(cls=cls,src='Open Images V7',orig=n,img=iid,url=f'https://s3.amazonaws.com/open-images-dataset/{sp}/{iid}.jpg',
        box_norm=b,indoor=indoor,license=lic,author=auth,page=land))
# ---- LVIS (val + train)
want_lv={n:k for k,v in C.items() for n in v[2]}
for jf in ['lvis_v1_val.json','lvis_v1_train.json']:
    if not os.path.exists(f'{D}/lvis/{jf}'): print('missing',jf); continue
    d=json.load(open(f'{D}/lvis/{jf}'))
    lic={l['id']:(l['name'],l['url']) for l in d['licenses']}
    cats={c['id']:c['name'] for c in d['categories']}
    imgs={i['id']:i for i in d['images']}
    per=collections.defaultdict(set)
    for a in d['annotations']: per[a['image_id']].add(cats[a['category_id']])
    for a in d['annotations']:
        n=cats[a['category_id']]
        if n not in want_lv: continue
        x,y,w,h=a['bbox']
        if min(w,h)<40 or w*h<64*64: continue
        im=imgs[a['image_id']]; cls=want_lv[n]
        s=per[a['image_id']]; indoor=len(s&INDOOR_LV)>0 and not (s&OUTDOOR_LV)
        ln,lu=lic[im['license']]
        cands[(cls,'lvis')].append(dict(cls=cls,src='LVIS v1 (COCO 2017 images)',orig=n,img=str(im['id']),url=im['coco_url'],
            box_px=(x,y,x+w,y+h),wh=(im['width'],im['height']),indoor=indoor,license=f'{ln} ({lu})',author='',page=im.get('flickr_url',''),lvis_split=jf.split('_')[2].split('.')[0]))
    del d
# ---- pick
out=open('/tmp/claude-501/bench/dl/candidates.jsonl','w'); used_img=collections.Counter()
summary={}
for cls,(moove,oi,lv,wm) in C.items():
    pools=[]
    for s in ('oi','lvis'):
        p=cands.get((cls,s),[]); random.shuffle(p); p.sort(key=lambda c:not c['indoor']); pools.append(p)
    nwm=0
    if wm:
        nwm=sum(len(l.split()[2].split(',')) for l in open(os.path.dirname(__file__)+'/wm_keep.txt') if l.split()[0]==wm)
    need=max(TARGET-nwm, 15) if wm else TARGET
    need=int(need*1.25)+2  # overselect: some downloads/crops will fail
    picked=[];seen=set()
    quota=[need//2+need%2, need//2] if all(pools) else [need if pools[0] else 0, need if pools[1] else 0]
    rest=[]
    for q,p in zip(quota,pools):
        k=0
        for c in p:
            key=(c['src'],c['img'])
            if key in seen or used_img[key]>=2: continue
            if k<q: picked.append(c); seen.add(key); used_img[key]+=1; k+=1
            else: rest.append(c)
    for c in rest:
        if len(picked)>=need: break
        key=(c['src'],c['img'])
        if key in seen or used_img[key]>=2: continue
        picked.append(c); seen.add(key); used_img[key]+=1
    for c in picked: c['label']=moove; out.write(json.dumps(c)+'\n')
    summary[cls]=(len(picked),nwm,{s:len(cands.get((cls,s),[])) for s in ('oi','lvis')})
for k,v in summary.items(): print(k,v)
