import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'runtime'))
from destination_context import hierarchical_destination


def context(before, after='', **extra):
    return json.dumps({'version': 2, 'app': 'Fixture', 'windowTitle': 'Unrelated subject',
        'field': {'attributes': {'description': 'Message body'}, 'bounds': [0, 0, 800, 600]},
        'insertion': {'source': 'ax_value_and_selected_text_range', 'before': before,
                      'after': after, 'replacing': '', 'isReplacement': False}, **extra})


class HierarchyTests(unittest.TestCase):
    def test_only_current_line_is_immediate_context(self):
        d = hierarchical_destination(context('Invoice 4711\nMy email: ', '\nMy number: '))
        self.assertEqual(d['insertion']['before'], 'My email: ')
        self.assertEqual(d['insertion']['after'], '')
        self.assertEqual(d['document']['earlier_text'], 'Invoice 4711\n')
        self.assertEqual(d['document']['later_text'], '\nMy number: ')
        self.assertEqual(d['priority_order'], ['insertion', 'field', 'document', 'application'])

    def test_ocr_not_repeated_with_known_caret(self):
        d = hierarchical_destination(context('My email: ', ocr=[{'text': 'DISTRACTING OCR',
            'source': 'ocr', 'confidence': 1, 'bounds': [10, 10, 100, 20]}]))
        self.assertNotIn('DISTRACTING OCR', json.dumps(d))
        self.assertEqual(d['application']['window_title'], 'Unrelated subject')

    def test_empty_composer_keeps_conversation_identity_as_background(self):
        d = hierarchical_destination(context('', windowTitle='Conversation with Maya'))
        self.assertEqual(d['insertion']['before'], '')
        self.assertEqual(d['field']['label'], 'Message body')
        self.assertTrue(d['field']['uncertain'])
        self.assertEqual(d['application']['window_title'], 'Conversation with Maya')
        self.assertIn('Field purpose: insufficient', d['document']['unanchored_context'])

    def test_insertion_outweighs_conflicting_window_title(self):
        d = hierarchical_destination(context('My email is ', windowTitle='Invoice payment'))
        self.assertEqual(d['insertion']['before'], 'My email is ')
        self.assertEqual(d['application']['window_title'], 'Invoice payment')
        self.assertEqual(d['priority_order'], ['insertion', 'field', 'document', 'application'])

    def test_known_caret_keeps_associated_section_without_noisy_neighbors(self):
        raw = json.loads(context('', ancestors=[{'role': 'AXGroup', 'text': 'Conversation with Maya'}],
            nearby=[{'text': 'Unrelated sidebar', 'source': 'ax', 'bounds': [1100, 50, 200, 20]}]))
        d = hierarchical_destination(json.dumps(raw))
        self.assertEqual(d['document']['section'], 'Conversation with Maya')
        self.assertNotIn('Unrelated sidebar', json.dumps(d))

    def test_missing_insertion_uses_explicit_field_label(self):
        raw = json.loads(context('ignored'))
        raw.pop('insertion')
        raw['field']['attributes']['description'] = 'Recipient email'
        d = hierarchical_destination(json.dumps(raw))
        self.assertFalse(d['insertion']['available'])
        self.assertEqual(d['field']['label'], 'Recipient email')
        self.assertFalse(d['field']['uncertain'])

    def test_missing_spreadsheet_headings_are_not_invented(self):
        raw = json.loads(context('', app='Numbers', windowTitle='Budget spreadsheet'))
        raw['field']['attributes'] = {'description': 'Cell'}
        raw['headings'] = []
        d = hierarchical_destination(json.dumps(raw))
        self.assertEqual(d['document'].get('section'), None)
        self.assertNotIn('row', json.dumps(d).lower())
        self.assertTrue(d['field']['uncertain'])

    def test_ambiguity_and_incomplete_capture_remain_explicit(self):
        raw = json.loads(context('', app='Mail'))
        raw['field']['attributes'] = {}
        raw['field']['bounds'] = [300, 300, 400, 40]
        raw['nearby'] = [
            {'text': 'Work email', 'source': 'ax', 'bounds': [120, 305, 150, 22]},
            {'text': 'Home email', 'source': 'ocr', 'confidence': .98, 'bounds': [120, 305, 151, 22]},
        ]
        raw['budgetExhausted'] = True
        d = hierarchical_destination(json.dumps(raw))
        self.assertTrue(d['field']['ambiguous'])
        self.assertTrue(d['field']['uncertain'])
        self.assertTrue(d['document']['capture_incomplete'])
        self.assertIn('Unresolved nearby labels', d['document']['unanchored_context'])

    def test_permission_absence_does_not_become_an_association(self):
        raw = json.loads(context('ignored', app=None, windowTitle=None))
        raw.pop('insertion')
        raw['field'] = {'attributes': {}, 'bounds': []}
        d = hierarchical_destination(json.dumps(raw))
        self.assertFalse(d['insertion']['available'])
        self.assertEqual(d['field']['label'], '')
        self.assertTrue(d['field']['uncertain'])
        self.assertEqual(d['application']['name'], '')
        self.assertEqual(d['application']['window_title'], '')

    def test_destination_encoding_is_bounded(self):
        raw = json.loads(context('a' * 600, 'b' * 240, windowTitle='w' * 200))
        raw['field']['attributes']['help'] = 'h' * 220
        raw['ancestors'] = [{'role': 'AXGroup', 'text': 's' * 160} for _ in range(6)]
        d = hierarchical_destination(json.dumps(raw))
        self.assertLessEqual(len(json.dumps(d, ensure_ascii=False).encode()), 3000)
        self.assertLessEqual(len(d['application']['window_title'].encode()), 160)

    def test_missing_anchor_is_not_fabricated_from_last_visible_line(self):
        raw = json.loads(context('ignored'))
        raw.pop('insertion')
        raw['ocr'] = [{'text': 'My email: ', 'source': 'ocr', 'confidence': 1,
                       'bounds': [10, 10, 100, 20]}]
        d = hierarchical_destination(json.dumps(raw))
        self.assertEqual(d['insertion'], {'available': False})
        self.assertIn('My email', d['document']['unanchored_context'])

    def test_empty_current_line_stays_empty(self):
        d = hierarchical_destination(context('Previous line\n'))
        self.assertEqual(d['insertion']['before'], '')
        self.assertEqual(d['document']['earlier_text'], 'Previous line\n')

    def test_unicode_split_preserves_exact_adjacency(self):
        before = '🙂' * 140 + ' gap '
        d = hierarchical_destination(context(before, '🙂' * 55))
        self.assertTrue(before.endswith(d['insertion']['before']))
        self.assertEqual(d['document']['earlier_text'] + d['insertion']['before'], before)
        self.assertLessEqual(len(d['insertion']['before'].encode()), 300)
        self.assertLessEqual(len(d['insertion']['after'].encode()), 160)

    def test_background_stays_below_insertion(self):
        d = hierarchical_destination(context('My email: ', windowTitle='Invoice payment'))
        self.assertEqual(d['priority_order'][0], 'insertion')
        self.assertEqual(d['insertion']['before'], 'My email: ')

    def test_source_and_replacement_retained(self):
        raw = json.loads(context('Contact: ', ' tomorrow'))
        raw['insertion'].update(source='ax_text_marker_range', replacing='obsolete', isReplacement=True)
        d = hierarchical_destination(json.dumps(raw))
        self.assertEqual(d['insertion']['replacing'], 'obsolete')
        self.assertTrue(d['insertion']['isReplacement'])
        self.assertEqual(d['insertion']['source'], 'ax_text_marker_range')


if __name__ == '__main__':
    unittest.main()
