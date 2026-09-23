import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'runtime'))
from destination_context import hierarchical_destination
from jev_selector import matched_hint


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
        self.assertNotIn('window_title', d['application'])

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

    def test_background_does_not_trigger_pinned_tie_break(self):
        d = hierarchical_destination(context('My email: ', windowTitle='Invoice payment'))
        self.assertFalse(matched_hint({'pinned': True, 'purpose_hint': 'Invoice payment'}, d))
        self.assertTrue(matched_hint({'pinned': True, 'purpose_hint': 'My email'}, d))

    def test_source_and_replacement_retained(self):
        raw = json.loads(context('Contact: ', ' tomorrow'))
        raw['insertion'].update(source='ax_text_marker_range', replacing='obsolete', isReplacement=True)
        d = hierarchical_destination(json.dumps(raw))
        self.assertEqual(d['insertion']['replacing'], 'obsolete')
        self.assertTrue(d['insertion']['isReplacement'])
        self.assertEqual(d['insertion']['source'], 'ax_text_marker_range')


if __name__ == '__main__':
    unittest.main()
