import sys,json,unittest,copy
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'runtime'))
from context_evidence import resolve
from context_cases import CASES,evidence,near

class EvidenceTests(unittest.TestCase):
    def test_associations(self):
        for case in CASES:
            with self.subTest(case=case['name']):
                r=resolve(json.dumps(case['raw']))
                self.assertEqual(r['label'],case['label'])
                self.assertEqual(bool(r['navigation']),case.get('navigation',False))
    def test_explicit_link_outranks_description(self):
        r=resolve(json.dumps(evidence('Email',linked='Maya email')))
        self.assertEqual(r['label'],'Maya email')
    def test_ocr_duplicate_is_not_ambiguity(self):
        raw=evidence('',nearby=[near('Maya email')]);raw['ocr']=[near('Maya email',source='ocr')]
        self.assertEqual(resolve(json.dumps(raw))['label'],'Maya email')
    def test_low_confidence_and_deep_nodes(self):
        raw=evidence('',nearby=[near('Wrong label',depth=3)]);n=near('Maya email',source='ocr');n['confidence']=.2;raw['ocr']=[n]
        self.assertEqual(resolve(json.dumps(raw))['label'],'')
    def test_legacy_and_invalid(self):
        self.assertIsNone(resolve('Input label: Email'))
        for value in ['{}','{"version":2,"field":[]}','{"version":2,"field":{"attributes":[]}}']:
            with self.assertRaises(ValueError):resolve(value)
    def test_existing_values_do_not_enter_model_state(self):
        raw=evidence('Cover letter');raw['field']['value']='PRIVATE_OLD_VALUE';raw['field']['selected']='PRIVATE_SELECTION'
        self.assertNotIn('PRIVATE',resolve(json.dumps(raw))['state'])
    def test_invalid_geometry_and_confidence(self):
        for value in [float('nan'),-1,'high',True]:
            raw=evidence('');node=near('Maya email');node['confidence']=value;raw['nearby']=[node]
            with self.assertRaises(ValueError):resolve(json.dumps(raw))
        raw=evidence('');node=near('Maya email');node['bounds']=[0,0,float('nan'),30];raw['nearby']=[node]
        self.assertEqual(resolve(json.dumps(raw))['label'],'')
    def test_label_cannot_cross_another_input(self):
        raw=evidence('',nearby=[near('Maya email',40,305,100)])
        raw['nearbyInputs']=[[160,300,100,40]]
        self.assertEqual(resolve(json.dumps(raw))['label'],'')
    def test_semantic_heading_can_supply_scope_without_becoming_label(self):
        raw=evidence('Notes');raw['headings']=[{**near('Project: Orchid',300,100,300),'role':'AXHeading','depth':1}]
        r=resolve(json.dumps(raw))
        self.assertEqual(r['label'],'Notes')
        self.assertEqual(r['scope'],'Project: Orchid')
        self.assertIn('Section: Project: Orchid',r['state'])
    def test_window_level_paste_preserves_visible_context_without_fake_label(self):
        raw=evidence('',nearby=[near('Drop an image here')])
        raw['destinationKind']='window'
        raw['app']='Browser'
        raw['windowTitle']='Artwork uploader'
        raw['ocr']=[near('Paste a screenshot to upload',source='ocr')]
        result=resolve(json.dumps(raw))
        self.assertEqual(result['label'],'')
        self.assertEqual(result['operation'],'window_paste')
        self.assertIn('Paste a screenshot to upload',result['state'])
    def test_rich_editor_ocr_is_bounded_context_when_caret_is_unavailable(self):
        raw=evidence('Message body',role='AXTextArea')
        raw['field']['bounds']=[300,300,400,200]
        raw['ocr']=[near('My mobile:',310,330,180,20,source='ocr'),
                    near('Unrelated toolbar',10,10,180,20,source='ocr')]
        state=resolve(json.dumps(raw))['state']
        self.assertIn('Visible text in focused editor (caret location unavailable): My mobile:',state)
        self.assertNotIn('Unrelated toolbar',state)
        raw['insertion']={'before':'My email: '}
        self.assertNotIn('caret location unavailable',resolve(json.dumps(raw))['state'])
