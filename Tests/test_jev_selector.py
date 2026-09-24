import copy
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'runtime'))
from jev_selector import make_request, result_for, JevSelector, SelectionError, MODEL, request_body, MAX_REQUEST_BYTES

class JevTests(unittest.TestCase):
    def setUp(self):
        self.payload={'context':'App: Safari\nInput label: Search or enter website','items':[
            {'id':'stable-url','text':'https://example.org','app':'Notes'},
            {'id':'stable-email','text':'alice@example.org','app':'Contacts'}]}
    def response(self,request,choice):
        return {'model':MODEL,'answers':{'pick':{'type':'choice','choice':choice,'confidence':.9,
            'probabilities':{k:1.0 if k==choice else 0.0 for k in request['questions']['pick']['criteria']}}}}
    def test_maps_existing_item_and_abstention(self):
        request,ids=make_request(self.payload)
        self.assertEqual(result_for(self.response(request,'C1'),request,ids)['ranked'][0]['id'],'stable-email')
        for choice in ['NONE']:
            self.assertEqual(result_for(self.response(request,choice),request,ids)['ranked'],[])
    def test_rejects_invalid_model_and_probabilities(self):
        request,ids=make_request(self.payload)
        for mutation in ['model','nan','invented','normalization','type']:
            response=self.response(request,'C0');answer=response['answers']['pick']
            if mutation=='model': response['model']='unapproved'
            elif mutation=='nan':answer['probabilities']['C0']=float('nan')
            elif mutation=='invented':answer['choice']='C9'
            elif mutation=='normalization':answer['probabilities']['C0']=.2
            else:answer['type']='noul'
            with self.assertRaises(SelectionError):result_for(response,request,ids)
    def test_all_50_candidates_bounded_unicode(self):
        payload=copy.deepcopy(self.payload)
        payload['items']=[{'id':str(i),'text':'你好🙂'*5000,'app':'Test'} for i in range(50)]
        request,ids=make_request(payload)
        self.assertEqual(len(ids),50)
        self.assertEqual(len(request['questions']['pick']['criteria']),51)
        self.assertLess(len(json.dumps(request,ensure_ascii=False).encode()),64000)
        self.assertLessEqual(len(request_body(request)), MAX_REQUEST_BYTES)
        self.assertTrue(all(c['text_truncated'] for c in request['state']['clipboard']))
        self.assertTrue(all(v is None for k,v in request['questions']['pick']['criteria'].items() if k != 'NONE'))
    def test_short_allowance_reused_and_middle_preserved(self):
        text = 'A'*3000 + 'DISTINGUISHING-MIDDLE' + 'Z'*3000
        payload = {'context':self.payload['context'], 'items':[
            {'id':'short','text':'brief','app':'Notes'},
            {'id':'long','text':text,'app':'Notes'}]}
        request, ids = make_request(payload)
        self.assertEqual(ids, ['short','long'])
        candidates = request['state']['clipboard']
        self.assertEqual(candidates[0]['text'], 'brief')
        self.assertIn('DISTINGUISHING-MIDDLE', candidates[1]['text'])
        self.assertGreater(len(candidates[1]['text'].encode()), 1600)
        self.assertTrue(candidates[1]['text_truncated'])
        self.assertEqual(make_request(payload)[0], request)
    def test_escaping_and_giant_single_item_are_finally_bounded(self):
        payload = {'context':self.payload['context'], 'items':[
            {'id':'giant','text':('🙂\\\n\t'*200000), 'app':'Notes',
             'hint':'OCR: '+('字'*300), 'pinned':True}]}
        request, ids = make_request(payload)
        self.assertEqual(ids, ['giant'])
        self.assertLessEqual(len(request_body(request)), MAX_REQUEST_BYTES)
        self.assertTrue(request['state']['clipboard'][0]['text_truncated'])
    def test_52_long_texts_hints_ocr_and_destination_fit_with_ids(self):
        payload = {'context':'Visible editor context '+('界'*30000), 'items':[
            {'id':f'item-{i}', 'text':'Image OCR: '+('🧾\\\n'*4000),
             'app':'Screenshot tool'*20, 'kind':'image', 'hint':'Source label '+('字'*300),
             'pinned':True} for i in range(52)]}
        request, ids = make_request(payload)
        self.assertEqual(ids, [f'item-{i}' for i in range(52)])
        self.assertEqual([c['id'] for c in request['state']['clipboard']], [f'C{i}' for i in range(52)])
        self.assertEqual(len(request['questions']['pick']['criteria']), 53)
        self.assertLessEqual(len(request_body(request)), MAX_REQUEST_BYTES)
        self.assertTrue(any(c['hint_truncated'] for c in request['state']['clipboard']))
        self.assertEqual(result_for(self.response(request,'C51'), request, ids)['ranked'][0]['id'], 'item-51')
    def test_request_boundary_rejects_exactly_over_cap_before_transport(self):
        request, _ = make_request(self.payload)
        actual = len(request_body(request))
        with patch('jev_selector.MAX_REQUEST_BYTES', actual):
            self.assertEqual(len(request_body(request)), actual)
        with patch('jev_selector.MAX_REQUEST_BYTES', actual-1):
            with self.assertRaises(SelectionError): request_body(request)
        class Connection:
            calls = 0
            def request(self,*args): self.calls += 1
        connection = Connection()
        selector = JevSelector('test-secret-not-a-real-key', lambda:connection)
        with patch('jev_selector.MAX_REQUEST_BYTES', 1):
            with self.assertRaises(SelectionError): selector.rank(self.payload)
        self.assertEqual(connection.calls, 0)
    def test_bounded_source_context_reaches_request(self):
        self.payload['items'][0]['source_context'] = 'Copy event in Safari · Selected field: Revenue'
        request, _ = make_request(self.payload)
        candidate = request['state']['clipboard'][0]
        self.assertEqual(candidate['source_context'], self.payload['items'][0]['source_context'])
        self.assertFalse(candidate['source_context_truncated'])
        self.assertIsNone(request['questions']['pick']['criteria']['C0'])
        self.assertEqual(request['state']['clipboard'][1]['source_context'], 'Source unknown')
        self.payload['items'][0]['source_context'] = 'x' * 1201
        with self.assertRaises(SelectionError):
            make_request(self.payload)
    def test_source_context_loss_is_flagged_and_budgeted(self):
        payload = copy.deepcopy(self.payload)
        payload['items'] = [{'id':'x', 'text':'1200', 'app':'Safari',
            'source_context':'A'*250 + 'DISTINCT-SOURCE-LABEL' + 'B'*550}]
        candidate = make_request(payload)[0]['state']['clipboard'][0]
        self.assertNotIn('DISTINCT-SOURCE-LABEL', candidate['source_context'])
        self.assertTrue(candidate['source_context_truncated'])
        payload['items'][0]['source_context'] = 'Copy event in Safari'
        payload['items'][0]['source_context_truncated'] = True  # Swift already shortened it.
        self.assertTrue(make_request(payload)[0]['state']['clipboard'][0]['source_context_truncated'])
        payload['items'][0]['source_context_truncated'] = 'true'
        with self.assertRaises(SelectionError): make_request(payload)

        crowded = copy.deepcopy(self.payload)
        crowded['items'] = [{'id':str(i), 'text':'A'*5000 + f'MIDDLE-{i}' + 'Z'*5000,
            'app':'Safari', 'hint':'h'*1000, 'source_context':'Revenue🙂'*100}
            for i in range(52)]
        request, ids = make_request(crowded)
        self.assertEqual(len(ids), 52)
        self.assertLessEqual(len(request_body(request)), MAX_REQUEST_BYTES)
        self.assertTrue(all(c['source_context_truncated'] for c in request['state']['clipboard']))
        self.assertTrue(all(c['text_truncated'] for c in request['state']['clipboard']))
    def test_20_saved_entries_fit_with_32_recent_history_items(self):
        payload=copy.deepcopy(self.payload)
        history=[{'id':f'history-{i}','text':f'History {i}','app':'Notes','kind':'text',
                  'recency_rank':i,'age_seconds':i,'pinned':False,'hint':''} for i in range(32)]
        saved=[{'id':f'pin-{i}','text':f'Saved {i}','app':'Persistent entry','kind':'text',
                'recency_rank':32+i,'age_seconds':0,'pinned':True,
                'hint':f'Use for saved purpose {i}'} for i in range(20)]
        payload['items']=history+saved
        request,ids=make_request(payload)
        self.assertEqual(len(ids),52)
        self.assertEqual(ids[32:],[f'pin-{i}' for i in range(20)])
        self.assertEqual(len(request['questions']['pick']['criteria']),53)
        self.assertLess(len(json.dumps(request,ensure_ascii=False).encode()),64000)
    def test_saved_file_uses_metadata_without_file_bytes(self):
        self.payload['items']=[{'id':'pin-resume','text':'File: Resume.pdf · type: com.adobe.pdf',
            'app':'Persistent entry','kind':'file','recency_rank':0,'age_seconds':0,
            'pinned':True,'hint':'My resume for job applications'}]
        request,ids=make_request(self.payload)
        candidate=request['state']['clipboard'][0]
        self.assertEqual(candidate['kind'],'file')
        self.assertEqual(candidate['purpose_hint'],'My resume for job applications')
        self.assertNotIn('file_bytes',json.dumps(request))
        self.assertEqual(result_for(self.response(request,'C0'),request,ids)['ranked'][0]['id'],'pin-resume')
    def test_structured_navigation_context_preserved(self):
        p=copy.deepcopy(self.payload)
        p['context']=json.dumps({'version':2,'app':'Safari','bundleID':'com.apple.Safari','windowTitle':'Search',
            'field':{'attributes':{'description':'Smart Search Field'},'identifier':'ADDRESS_AND_SEARCH_FIELD'},
            'ancestors':[{'role':'AXToolbar','text':''}]})
        request,_=make_request(p)
        self.assertIn('website address',request['state']['destination']['field']['purpose'])
    def test_inline_caret_context_reaches_jev(self):
        for before,after,replacing in [('Reach out to me at my number ', '', ''),
                                       ('Email me at ', ', thanks', 'old value'),
                                       ('Website: ', ' for more details', '')]:
            raw={'version':2,'app':'Codex','bundleID':'com.openai.codex','windowTitle':'Chat',
                 'field':{'attributes':{'description':'Message'}},
                 'insertion':{'source':'ax_value_and_selected_text_range','before':before,'after':after,
                              'replacing':replacing,'isReplacement':bool(replacing)}}
            self.payload['context']=json.dumps(raw)
            request,_=make_request(self.payload)
            self.assertEqual(request['state']['destination']['insertion'], {'available': True, **raw['insertion']})
            self.assertEqual(request['state']['destination']['field']['label'],'Message')
        marker = raw['insertion'].copy()
        marker['source'] = 'ax_text_marker_range'
        raw['insertion'] = marker
        self.payload['context'] = json.dumps(raw)
        request,_ = make_request(self.payload)
        self.assertEqual(request['state']['destination']['insertion']['source'],'ax_text_marker_range')
    def test_rich_editor_preserves_all_candidates_and_jev_choice(self):
        for before in ('Reach me at ', 'Please attach ', 'The project link is '):
            payload={'context':json.dumps({'version':2,'app':'Editor','destinationKind':'editable',
                'field':{'attributes':{'description':'Message'}},
                'insertion':{'source':'ax_value_and_selected_text_range','before':before,'after':'',
                             'replacing':'','isReplacement':False}}),
                'items':[{'id':'recent-prose','text':'A copied paragraph','app':'Notes','kind':'text'},
                         {'id':'image','text':'Image OCR: diagram','app':'Preview','kind':'image'},
                         {'id':'saved-file','text':'Resume.pdf','app':'Persistent entry','kind':'file',
                          'pinned':True,'hint':'My resume'},
                         {'id':'saved-text','text':'https://example.org','app':'Persistent entry','kind':'text',
                          'pinned':True,'hint':'Project website'}]}
            request,ids=make_request(payload)
            self.assertEqual(ids,['recent-prose','image','saved-file','saved-text'])
            self.assertEqual(request['state']['destination']['insertion']['before'],before)
            self.assertEqual(result_for(self.response(request,'C1'),request,ids)['ranked'][0]['id'],'image')
            self.assertEqual(result_for(self.response(request,'C2'),request,ids)['ranked'][0]['id'],'saved-file')
            self.assertEqual(result_for(self.response(request,'NONE'),request,ids)['decision'],'latest')

    def test_no_literal_type_rescue_overrides_jev(self):
        for label in ('Email address', 'Phone number', 'Shipping address', 'Website', 'Invoice number'):
            self.payload['context']=json.dumps({'version':2,'destinationKind':'editable',
                'field':{'attributes':{'description':label}}})
            request,ids=make_request(self.payload)
            self.assertEqual(result_for(self.response(request,'C0'),request,ids)['ranked'][0]['id'],'stable-url')
            self.assertEqual(result_for(self.response(request,'NONE'),request,ids)['decision'],'latest')

    def test_missing_caret_never_infers_end_from_field_value(self):
        self.payload['context']=json.dumps({'version':2,'field':{'attributes':{'value':'PRIVATE FULL DOCUMENT'}}})
        request,_=make_request(self.payload)
        self.assertEqual(request['state']['destination']['insertion'], {'available': False})
        self.assertNotIn('PRIVATE FULL DOCUMENT',json.dumps(request))
    def test_invalid_or_oversized_inline_context_rejected(self):
        for changed in [{'before':'x'*601},{'source':'invented'},{'isReplacement':'yes'},{'after':None}]:
            insertion={'source':'ax_value_and_selected_text_range','before':'call me at ','after':'','replacing':'','isReplacement':False}
            insertion.update(changed)
            self.payload['context']=json.dumps({'version':2,'field':{'attributes':{}},'insertion':insertion})
            with self.assertRaises(SelectionError):make_request(self.payload)
    def test_duplicate_ids_rejected(self):
        self.payload['items'][1]['id']='stable-url'
        with self.assertRaises(SelectionError):make_request(self.payload)
    def test_key_never_sent_as_candidate(self):
        self.payload['items'][0]['text']='test-secret-not-a-real-key'
        calls=[]
        selector=JevSelector('test-secret-not-a-real-key',lambda:calls.append(True))
        with self.assertRaises(SelectionError):selector.rank(self.payload)
        self.assertEqual(calls,[])
    def test_http_failure_no_retry_or_fallback(self):
        class Connection:
            calls=0
            def request(self,*args):self.calls+=1
            def getresponse(self):return self
            def read(self,n):return b'private server exception'
            def close(self):pass
            status=401
        connection=Connection()
        selector=JevSelector('test-secret-not-a-real-key',lambda:connection)
        with self.assertRaisesRegex(SelectionError,'rejected the API key'):selector.rank(self.payload)
        self.assertEqual(connection.calls,1)
        self.assertIsNone(selector.connection)
    def test_connection_reused_successfully(self):
        request,_=make_request(self.payload);response=json.dumps(self.response(request,'C0')).encode()
        class Connection:
            calls=0;status=200;will_close=False
            def request(self,*args):self.calls+=1
            def getresponse(self):return self
            def read(self,n):return response
            def close(self):pass
        c=Connection();selector=JevSelector('test-secret-not-a-real-key',lambda:c)
        for _ in range(2):self.assertEqual(selector.rank(self.payload)['ranked'][0]['id'],'stable-url')
        self.assertEqual(c.calls,2)
        self.assertIs(selector.connection,c)

if __name__=='__main__':unittest.main()
