"""Jev owns ranking; metadata never causes a local selection override."""
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'runtime'))
from jev_selector import make_request, result_for, MODEL

class SelectionPolicyTests(unittest.TestCase):
    def decide(self, confidence, *, chosen='C0', probabilities=None):
        context = json.dumps({'version':2,'field':{'attributes':{'description':'Email address'}},
            'insertion':{'source':'ax_value_and_selected_text_range','before':'My phone number: ',
                         'after':'','replacing':'','isReplacement':False}})
        items = [{'id':'phone','text':'+1 202 555 0147','app':'Fixture','recency_rank':1},
                 {'id':'email','text':'me@example.org','app':'Fixture','recency_rank':0,
                  'pinned':True,'hint':'My email address'}]
        request, ids = make_request({'context':context,'items':items})
        response = {'model':MODEL,'answers':{'pick':{'type':'choice','choice':chosen,
            'confidence':confidence,'probabilities':probabilities or {'C0':.51,'C1':.49,'NONE':0}}}}
        return result_for(response, request, ids)

    def test_jev_choice_is_not_overridden_by_matching_hint_or_recency(self):
        result = self.decide(.9)
        self.assertEqual(result['ranked'][0]['id'], 'phone')
        self.assertEqual(result['model_choice'], 'phone')
        self.assertNotIn('recency_changed', result)

    def test_low_confidence_uses_latest(self):
        for confidence in [0, .01, .69, .7]:
            result = self.decide(confidence)
            self.assertEqual(result['decision'], 'latest')
            self.assertEqual(result['ranked'], [])
            self.assertEqual(result['fallback_reason'], 'low_confidence')

    def test_only_above_threshold_accepts_choice(self):
        self.assertEqual(self.decide(.700001)['ranked'][0]['id'], 'phone')

    def test_none_uses_latest(self):
        result = self.decide(1, chosen='NONE', probabilities={'C0':0,'C1':0,'NONE':1})
        self.assertEqual(result['fallback_reason'], 'no_match')
        self.assertEqual(result['decision'], 'latest')

    def test_flat_probabilities_with_low_confidence_fall_back(self):
        result = self.decide(.01, probabilities={'C0':.34,'C1':.33,'NONE':.33})
        self.assertEqual(result['ranked'], [])

if __name__ == '__main__': unittest.main()
