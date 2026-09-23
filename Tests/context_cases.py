"""Synthetic destination evidence: labels/geometry are observations, not real captures."""
import copy,json

def evidence(label='', *, linked=None, scope='', role='AXTextField', nearby=None, identifier='', toolbar=False, help=''):
    return {'version':2,'app':'Safari','bundleID':'com.apple.Safari','windowTitle':'Form',
      'field':{'role':role,'subrole':'','identifier':identifier,'attributes':{'description':label,'help':help},
               'linkedLabels':[] if linked is None else [linked], 'bounds':[300,300,400,40]},
      'ancestors':[{'role':'AXToolbar' if toolbar else 'AXGroup','text':scope}],
      'nearby':nearby or [],'ocr':[]}

def near(text,x=120,y=305,w=150,h=22,source='ax',depth=0):
    return {'text':text,'bounds':[x,y,w,h],'source':source,'depth':depth,'confidence':.98,'role':'AXStaticText'}

CASES=[
 {'name':'linked_email','raw':evidence('',linked='Maya email'),'label':'Maya email','oracle':'Maya email','items':['noah@example.net','maya@example.org','Meeting tomorrow'],'expected':1},
 {'name':'left_email','raw':evidence('',nearby=[near('Maya email')]),'label':'Maya email','oracle':'Maya email','items':['noah@example.net','maya@example.org','Meeting tomorrow'],'expected':1},
 {'name':'above_phone','raw':evidence('',nearby=[near('Phone number',300,270)]),'label':'Phone number','oracle':'Phone number','items':['+61 4 1234 5678','maya@example.org','Meeting tomorrow'],'expected':0},
 {'name':'right_label','raw':evidence('',nearby=[near('Website URL',720,305,90)]),'label':'Website URL','oracle':'Website URL','items':['https://cedar.test','maya@example.org','Meeting tomorrow'],'expected':0},
 {'name':'ocr_email','raw':evidence(''),'label':'Maya email','oracle':'Maya email','items':['noah@example.net','maya@example.org','Meeting tomorrow'],'expected':1},
 {'name':'explicit_beats_neighbor','raw':evidence('Maya email',nearby=[near('Noah email')]),'label':'Maya email','oracle':'Maya email','items':['noah@example.net','maya@example.org','Meeting tomorrow'],'expected':1},
 {'name':'ambiguous_neighbors','raw':evidence('',nearby=[near('Maya email'),near('Noah email',120,305,151)]),'label':'','oracle':'','items':['noah@example.net','maya@example.org','Meeting tomorrow'],'expected':None},
 {'name':'far_label','raw':evidence('',nearby=[near('Maya email',120,20)]),'label':'','oracle':'','items':['noah@example.net','maya@example.org','Meeting tomorrow'],'expected':None},
 {'name':'field_value_not_label','raw':evidence('',nearby=[near('Noah email',310,305)]),'label':'','oracle':'','items':['noah@example.net','maya@example.org','Meeting tomorrow'],'expected':None},
 {'name':'browser_chrome','raw':evidence('smart search field',identifier='WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD',toolbar=True),'label':'smart search field','navigation':True,'oracle':'Website URL or web search terms','items':['https://cedar.test','The order arrives Friday.','maya@example.org'],'expected':0},
 {'name':'page_search','raw':evidence('Search',scope='Search documentation'),'label':'Search','navigation':False,'oracle':'Search documentation','items':['Configuration reference','The order arrives Friday.','maya@example.org'],'expected':0},
 {'name':'cover_letter_heading','raw':evidence('Description',scope='Job application',nearby=[near('Cover letter',300,270)],role='AXTextArea'),'label':'Cover letter','oracle':'Cover letter for a job application','items':['I would love to join your team and bring my software engineering experience to this role.','Lunch tomorrow at noon works for me.','maya@example.org'],'expected':0},
 {'name':'cover_letter_help','raw':evidence('Cover letter',help='Explain your interest in the role and relevant experience.'),'label':'Cover letter','oracle':'Explain your interest in the role and relevant experience.','items':['My background in customer service would help me contribute to your team.','Lunch tomorrow at noon works for me.','maya@example.org'],'expected':0},
 {'name':'shipping_section','raw':evidence('Street address',scope='Shipping address'),'label':'Street address','oracle':'Shipping street address','items':['18 Oak Street, Bristol','maya@example.org','Meeting tomorrow'],'expected':0},
 {'name':'scoped_notes','raw':evidence('Notes',scope='Project: Orchid'),'label':'Notes','oracle':'Notes about Orchid project','items':['Orchid project milestones','Meeting tomorrow','maya@example.org'],'expected':0},
 {'name':'custom_id','raw':evidence('',nearby=[near('Reservation reference')]),'label':'Reservation reference','oracle':'Reservation reference','items':['QF-8721','Meeting tomorrow','maya@example.org'],'expected':0},
 {'name':'missing_context','raw':evidence('Text area'),'label':'Text area','oracle':'','items':['Meeting tomorrow','Lunch at noon','maya@example.org'],'expected':None},
 {'name':'wrong_entity','raw':evidence('',linked='Maya email'),'label':'Maya email','oracle':'Maya email','items':['noah@example.net','bob@example.org','Meeting tomorrow'],'expected':None},
]
CASES[4]['raw']['ocr']=[near('Maya email',source='ocr')]

def legacy(raw):
    field=raw['field'];attrs=field['attributes'];labels=[attrs.get(k,'') for k in ('title','description','help','placeholder')]+field.get('linkedLabels',[])
    labels=list(dict.fromkeys(x for x in labels if x))
    ocr='\n'.join(n['text'] for n in raw.get('nearby',[])+raw.get('ocr',[]))
    return f'App: {raw["app"]} ({raw["bundleID"]})\nInput role: {field["role"]}\nInput label: {" · ".join(labels)}\nExisting input: \nSelected text: \nInput group: {raw["ancestors"][0]["text"]}\nWindow: {raw["windowTitle"]}\nVisible window text:\n{ocr}'
