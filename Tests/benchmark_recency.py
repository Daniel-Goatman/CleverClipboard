"""Synthetic Jev comparison; reads the existing key directly to memory, reports IDs/timings only."""
import argparse, importlib.util, json, statistics, subprocess, sys, time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'runtime'))
import jev_selector as new
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', type=Path, required=True, help='Path to a compatible historical jev_selector.py for comparison')
old_path = parser.parse_args().baseline.resolve()
if not old_path.is_file():
    parser.error('Baseline selector file does not exist')
spec=importlib.util.spec_from_file_location('old_jev_selector',old_path)
old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)

cases=[
 ('address_recent','Input label: Shipping address',[('latest','Meeting notes for tomorrow',0,None),('recent','42 Harbour Road, Perth WA 6000',1,None),('old','8 Cedar Road, Perth WA 6000',2,None)],'recent'),
 ('address_specific','Input label: Shipping address · Use 8 Cedar Road, Perth WA 6000',[('latest','Meeting notes for tomorrow',0,None),('recent','42 Harbour Road, Perth WA 6000',1,None),('old','8 Cedar Road, Perth WA 6000',2,None)],'old'),
 ('pin_personal','Reach out to me at my email ',[('recent','bob.morgan@example.net',0,None),('pin-0','daniel.wilson@example.org',1,'my email address')],'pin-0'),
 ('image_recent','Attach the screenshot to this message',[('latest','Meeting notes for tomorrow',0,None),('recent','Image OCR: order summary #42',1,'image'),('old','Image OCR: order summary #41',2,'image')],'recent'),
 ('image_specific','Attach the screenshot of order #41',[('latest','Meeting notes for tomorrow',0,None),('recent','Image OCR: order summary #42',1,'image'),('old','Image OCR: order summary #41',2,'image')],'old'),
 ('no_match','Input label: Phone number',[('recent','The meeting is tomorrow.',0,None),('old','https://example.org',1,None)],'latest'),
]
key=subprocess.check_output(['/usr/bin/security','find-generic-password','-s','local.daniel.LayaClipboard.TypeSafe','-a','api-key','-w'],text=True).strip()
assert key and len(key)>15
client=new.JevSelector(key)
rows=[]
for name,context,raw,expected in cases:
    items=[{'id':i,'text':t,'app':'Synthetic fixture','recency_rank':rank,
            **({'kind':'image'} if kind=='image' else {}),
            **({'pinned':True,'hint':kind} if kind and kind!='image' else {})} for i,t,rank,kind in sorted(raw,key=lambda row:row[2])]
    payload={'context':context,'items':items}
    entries=[]
    for label,module in [('old',old),('new',new)]:
        req,ids=module.make_request(payload)
        start=time.perf_counter()
        response=client.connection or client.connection_factory()
        client.connection=response
        response.request('POST','/v1/systemone',json.dumps(req).encode(),{'Authorization':'Bearer '+key,'Content-Type':'application/json'})
        reply=response.getresponse(); data=reply.read(128001)
        if reply.status != 200: raise RuntimeError('Jev status '+str(reply.status))
        parsed=json.loads(data)
        selected=module.result_for(parsed,req,ids)
        plain_id=ids[int(parsed['answers']['pick']['choice'][1:])] if parsed['answers']['pick']['choice'] != 'NONE' else 'latest'
        pick=lambda r:r['ranked'][0]['id'] if r['ranked'] else 'latest'
        entries.append({'policy':label,'selected':pick(selected),'model_only':plain_id,
                        'ms':round((time.perf_counter()-start)*1000)})
        if reply.will_close: client.close()
    rows.append({'case':name,'expected':expected,'runs':entries})
    print(name, entries,flush=True)
client.close();key=''
print('summary',json.dumps({label:{'correct':sum(row['expected']==next(r['selected'] for r in row['runs'] if r['policy']==label) for row in rows),
 'count':len(rows),'p50_ms':round(statistics.median(next(r['ms'] for r in row['runs'] if r['policy']==label) for row in rows)),
 'p95_ms':round((lambda values:values[4]+.75*(values[5]-values[4]))(sorted(next(r['ms'] for r in row['runs'] if r['policy']==label) for row in rows)))} for label in ['old','new']}))
