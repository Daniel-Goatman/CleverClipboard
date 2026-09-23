"""Resolve observed destination evidence; never infer intent from clipboard items."""
from __future__ import annotations
import json
import math
import re

GENERIC = {'', 'text', 'text field', 'text area', 'input', 'edit', 'editor', 'rich text editor', 'search',
           'message', 'message body', 'message content', 'email body', 'mail body', 'reply', 'notes',
           'description', 'comment', 'write a message', 'type here', 'enter text',
           'the focused editable field', 'form', 'group', 'content', 'web content', 'document', 'body', 'composer'}
BROWSERS = {'com.apple.Safari', 'com.google.Chrome', 'com.microsoft.edgemac', 'org.mozilla.firefox', 'com.brave.Browser'}

def clean(value, limit=240):
    return re.sub(r'\s+', ' ', value).strip()[:limit] if isinstance(value, str) else ''

def meaningful(text):
    return clean(text).casefold().rstrip(':') not in GENERIC

def box(raw):
    if not isinstance(raw, list) or len(raw)!=4 or any(isinstance(x,bool) or not isinstance(x,(int,float)) or not math.isfinite(x) for x in raw):
        return None
    x,y,w,h=raw
    return (x,y,w,h) if w>0 and h>0 else None

def spatial_score(target, node, barriers=()):
    a,b=box(target),box(node.get('bounds'))
    if not a or not b:return None
    x,y,w,h=a; nx,ny,nw,nh=b
    # Text inside the editable rectangle is a value/placeholder, not a nearby label.
    overlap_x=max(0,min(x+w,nx+nw)-max(x,nx))
    overlap_y=max(0,min(y+h,ny+nh)-max(y,ny))
    if overlap_x*overlap_y>0:return None
    if node.get('depth',0)>2:return None
    # Prefer aligned labels above/left; don't cross another field or container.
    if overlap_y/min(h,nh)>=.45 and nx+nw<=x and x-(nx+nw)<=240:
        distance=(x-nx-nw)/240
        path=(nx+nw,max(y,ny),x-(nx+nw),min(y+h,ny+nh)-max(y,ny))
    elif overlap_x/min(w,nw)>=.5 and ny+nh<=y and y-(ny+nh)<=90:
        distance=(y-ny-nh)/90+.08
        path=(max(x,nx),ny+nh,min(x+w,nx+nw)-max(x,nx),y-(ny+nh))
    elif overlap_y/min(h,nh)>=.65 and nx>=x+w and nx-x-w<=100:
        distance=(nx-x-w)/100+.2
        path=(x+w,max(y,ny),nx-(x+w),min(y+h,ny+nh)-max(y,ny))
    else:return None
    px,py,pw,ph=path
    for raw in barriers:
        other=box(raw)
        if other:
            bx,by,bw,bh=other
            if min(px+pw,bx+bw)>max(px,bx) and min(py+ph,by+bh)>max(py,by):return None
    return 1-distance*.5-min(2,node.get('depth',0))*.08

def resolve(context):
    """Legacy string passthrough; v2 evidence produces compact, source-tagged state."""
    if not context.lstrip().startswith('{'):return None
    raw=json.loads(context)
    if not isinstance(raw,dict) or raw.get('version')!=2:raise ValueError('Unsupported context version')
    field=raw.get('field',{})
    if not isinstance(field,dict):raise ValueError('Invalid field evidence')
    attrs=field.get('attributes',{})
    if not isinstance(attrs,dict):raise ValueError('Invalid attributes')
    ancestors=raw.get('ancestors',[])
    nearby,ocr=raw.get('nearby',[]),raw.get('ocr',[])
    if not isinstance(nearby,list) or not isinstance(ocr,list):raise ValueError('Invalid text observations')
    headings=raw.get('headings',[])
    if not isinstance(headings,list) or len(headings)>8:raise ValueError('Invalid section headings')
    nodes=nearby+ocr
    barriers=raw.get('nearbyInputs',[])
    if not isinstance(barriers,list) or len(barriers)>20:raise ValueError('Invalid neighboring inputs')
    if not isinstance(ancestors,list) or len(ancestors)>6 or len(nodes)>80:raise ValueError('Oversized context evidence')
    if any(not isinstance(n,dict) for n in ancestors+nodes+headings):raise ValueError('Invalid context node')
    for n in nodes+headings:
        depth=n.get('depth',0); confidence=n.get('confidence',1)
        if isinstance(depth,bool) or not isinstance(depth,int) or not 0<=depth<=4:raise ValueError('Invalid depth')
        if isinstance(confidence,bool) or not isinstance(confidence,(int,float)) or not math.isfinite(confidence) or not 0<=confidence<=1:raise ValueError('Invalid confidence')
    if raw.get('destinationKind') == 'window':
        # A page or canvas can own Paste without an editable AX field. Preserve
        # bounded visible context instead of inventing a field label from OCR.
        visible=[]
        for node in [*headings, *nodes]:
            if node.get('source') == 'ocr' and node.get('confidence',0) < .65:continue
            text=clean(node.get('text'),160)
            if meaningful(text) and text not in visible:visible.append(text)
        state='Window-level paste target; no focused editable field.\n'
        state+='App: '+clean(raw.get('app'),80)+'\n'
        state+='Window: '+clean(raw.get('windowTitle'),160)
        if visible:state+='\nVisible context: '+' | '.join(visible[:12])
        return {'label':'','source':'window','scope':'','help':'','navigation':False,
                'uncertain':True,'operation':'window_paste','ambiguous':False,
                'state':state[:1400],'raw':raw}
    if not isinstance(field.get('linkedLabels',[]),list) or len(field.get('linkedLabels',[]))>40:raise ValueError('Invalid labels')
    linked=[clean(x) for x in field.get('linkedLabels',[]) if isinstance(x,str)]
    observed=[('linked_label',x) for x in linked]+[(k,clean(attrs.get(k))) for k in ('title','description','placeholder')]
    direct=next(((k,v) for k,v in observed if meaningful(v)),None)
    generic=next(((k,v) for k,v in observed if v),('missing',''))
    label_source,label=direct or generic
    competing=[]
    if not direct:
        eligible=[]
        for n in nodes:
            text=clean(n.get('text'),160)
            if not meaningful(text) or len(text)>120:continue
            if n.get('source')=='ocr' and n.get('confidence',0)<.65:continue
            score=spatial_score(field.get('bounds'),n,barriers)
            if score is not None:eligible.append((score,text,n.get('source','ax')))
        # Identical OCR/AX observations are one piece of evidence, not two competitors.
        unique={}
        for row in eligible:
            key=row[1].casefold()
            if key not in unique or row[0]>unique[key][0]:unique[key]=row
        ranked=sorted(unique.values(),key=lambda x:(-x[0],x[1]))
        if ranked and ranked[0][0]>=.68 and (len(ranked)==1 or ranked[0][0]-ranked[1][0]>=.12):
            _,label,label_source=ranked[0];label_source+=':spatial_label'
        elif ranked:
            competing=[r[1] for r in ranked[:2]]
    roles=[clean(n.get('role')) for n in ancestors]
    identifier=clean(field.get('identifier'))
    # Identity + browser chrome location distinguish navigation from in-page search.
    navigation=(raw.get('bundleID') in BROWSERS and 'AXToolbar' in roles and
                ('ADDRESS_AND_SEARCH' in identifier.upper() or re.search(r'\b(address|smart search|location)\b',label,re.I)))
    scope=[]
    for n in ancestors:
        text=clean(n.get('text'),160)
        if meaningful(text) and text!=label and text not in scope:scope.append(text)
    field_box=box(field.get('bounds'))
    if field_box:
        x,y,w,h=field_box
        sections=[]
        for node in headings:
            bounds=box(node.get('bounds'));text=clean(node.get('text'),160)
            if not bounds or not meaningful(text) or text==label:continue
            hx,hy,hw,hh=bounds
            if hy+hh<=y and hx<=x+w and hx+hw>=x:
                sections.append((node.get('depth',0),y-hy-hh,text))
        if sections:
            section=sorted(sections)[0][2]
            if section not in scope:scope.insert(0,section)
    help_text=clean(attrs.get('help'),220)
    # Associated group context is retained as scope, never promoted into the field label.
    operation='browser_navigation_or_search' if navigation else ('form_or_editor')
    uncertain=not meaningful(label) or bool(competing)
    # Keep raw provenance for inspection, but do not make the small decision model
    # interpret AX symbols or field-coordinate bookkeeping as destination semantics.
    lines=[f'Input: {label or "unavailable"}']
    if scope:lines.append('Section: '+' / '.join(scope[:2]))
    if help_text:lines.append('Instructions: '+help_text)
    if navigation:
        lines += ['Location: browser toolbar',
                  'Purpose: Enter a website address or search the web.',
                  'Accepted content: URL or search terms.']
    elif not direct and not meaningful(label):
        lines.append('App: '+clean(raw.get('app'),80))
    if competing:lines.append('Unresolved nearby labels: '+' | '.join(competing))
    if not isinstance(raw.get('insertion'),dict) and field_box:
        # Mail and other rich editors may expose a body but not an AX caret
        # range. Preserve bounded visible draft text as context without
        # pretending that its final line is the insertion point.
        x,y,w,h=field_box
        visible=[]
        for node in ocr:
            bounds=box(node.get('bounds'))
            if not bounds or node.get('confidence',0)<.65:continue
            nx,ny,nw,nh=bounds
            if x<=nx+nw/2<=x+w and y<=ny+nh/2<=y+h:
                text=clean(node.get('text'),120)
                if meaningful(text) and text not in visible:visible.append(text)
        if visible:
            lines.append('Visible text in focused editor (caret location unavailable): '
                         +' | '.join(visible[-6:])[:500])
    if uncertain:lines.append('Field purpose: insufficient or ambiguous evidence')
    return {'label':label,'source':label_source,'scope':' / '.join(scope[:2]),
            'help':help_text,'navigation':navigation,'uncertain':uncertain,
            'operation':operation,'ambiguous':bool(competing),'state':'\n'.join(lines)[:1400],'raw':raw}

def legacy_view(evidence):
    """Compatibility envelope for existing ranking; extra facts go to actual model state."""
    raw=evidence['raw'];label=evidence['label']
    # Browser navigation admits URLs, but choosing between URL/search is not established
    # by the control alone. Keep the semantic matcher in charge (no URL-only rewrite).
    return '\n'.join([f'App: {clean(raw.get("app"))} ({clean(raw.get("bundleID"))})',
        f'Input label: {label}',f'Input group: {evidence["scope"]}',
        f'Window: {clean(raw.get("windowTitle"),200)}'])
