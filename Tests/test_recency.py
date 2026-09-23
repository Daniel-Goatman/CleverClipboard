import sys, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'runtime'))
from jev_selector import make_request, result_for, MODEL

class RecencyTests(unittest.TestCase):
    def result(self, items, choices, context='Input label: Shipping address'):
        request, ids = make_request({'context':context,'items':items})
        probs = {key:0.0 for key in request['questions']['pick']['criteria']}
        probs.update(choices)
        return request, ids, {'model':MODEL,'answers':{'pick':{'type':'choice','choice':max(probs,key=probs.get),
            'confidence':max(probs.values()),'probabilities':probs}}}
    def test_close_address_prefers_recent(self):
        items=[{'id':'old','text':'8 Cedar Road, Perth WA 6000','app':'Notes','recency_rank':1},
               {'id':'new','text':'42 Harbour Road, Perth WA 6000','app':'Notes','recency_rank':0}]
        request,ids,response=self.result(items,{'C0':.52,'C1':.48})
        self.assertEqual(result_for(response,request,ids,recency=False)['ranked'][0]['id'],'old')
        self.assertEqual(result_for(response,request,ids)['ranked'][0]['id'],'new')
    def test_clear_match_not_overridden(self):
        items=[{'id':'old','text':'8 Cedar Road, Perth WA 6000','app':'Notes','recency_rank':1},
               {'id':'new','text':'42 Harbour Road, Perth WA 6000','app':'Notes','recency_rank':0}]
        request,ids,response=self.result(items,{'C0':.8,'C1':.2})
        self.assertEqual(result_for(response,request,ids)['ranked'][0]['id'],'old')
    def test_matching_pin_wins_close_choice(self):
        items=[{'id':'new','text':'bob@example.org','app':'Notes','recency_rank':0},
               {'id':'pin-0','text':'me@example.org','app':'Persistent entry','recency_rank':1,
                'pinned':True,'hint':'my email address'}]
        request,ids,response=self.result(items,{'C0':.51,'C1':.49},'Email me at my address')
        self.assertEqual(result_for(response,request,ids)['ranked'][0]['id'],'pin-0')
    def test_image_and_none(self):
        items=[{'id':'old','text':'Image OCR: order 80','app':'Screenshot','kind':'image','recency_rank':1},
               {'id':'new','text':'Image OCR: order 81','app':'Screenshot','kind':'image','recency_rank':0}]
        request,ids,response=self.result(items,{'C0':.52,'C1':.48},'Paste screenshot into message')
        self.assertEqual(result_for(response,request,ids)['ranked'][0]['id'],'new')
        _,_,no_match=self.result(items,{'NONE':1.0},'Input label: Email')
        self.assertEqual(result_for(no_match,request,ids)['ranked'],[])
    def test_metadata_bounds(self):
        with self.assertRaises(Exception):make_request({'context':'Input label: Email','items':[
            {'id':'x','text':'a','app':'A','kind':'image','hint':'h'*1001}]})

if __name__=='__main__': unittest.main()
