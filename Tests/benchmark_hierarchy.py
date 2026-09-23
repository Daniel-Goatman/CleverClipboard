"""Paired synthetic live benchmark. No user clipboard/draft text is read or stored."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'runtime'))
import jev_selector as new
spec = importlib.util.spec_from_file_location('baseline', Path(__file__).parent / 'fixtures/selector_before_hierarchy.py')
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)


def item(id, text, hint='', kind='text'):
    return {'id': id, 'text': text, 'app': 'Synthetic saved entry' if hint else 'Synthetic Notes',
            'kind': kind, 'pinned': bool(hint), 'hint': hint}


def cases():
    items = [item('latest', 'The revised project timeline will be available next week.'),
             item('other-email', 'bob.morgan@example.net'),
             item('other-number', '+1 202 555 0168'),
             item('new-address', '42 Harbour Road, Perth WA 6000'),
             item('old-address', '8 Cedar Road, Perth WA 6000'),
             item('url', 'https://cedar.example.org'),
             item('invoice', 'INV-2048'),
             item('cover-letter', 'I build practical software and would welcome the opportunity to contribute to your engineering team.'),
             item('date', 'Tuesday 15 September at 10:30 am'),
             item('image', 'Screenshot OCR: order 42 receipt', kind='image'),
             item('file', 'File: Resume.pdf · type: com.adobe.pdf', 'My resume for applications', 'file')]
    items += [item(f'noise-{i}', f'Unrelated project {i} notes: update the design review and task checklist.') for i in range(31)]
    items += [item('my-email', 'alex.chen@example.org', 'My personal contact email address'),
              item('my-number', '+1 202 555 0147', 'My personal contact number')]
    for i, x in enumerate(items):
        x.update(recency_rank=i, age_seconds=0 if x['pinned'] else i*90)
    clutter = 'Billing contact: bob.morgan@example.net\nCall the office at +1 202 555 0168.\nThe revised project timeline will be available next week.\n'
    def case(name, before, expected, *, after='', label='Message body', replacing='', title='Invoice and project timeline', anchor=True, kind='editable'):
        raw = {'version': 2, 'app': 'Synthetic Editor', 'bundleID': 'fixture.editor',
               'windowTitle': title, 'destinationKind': kind,
               'field': {'role': 'AXWebArea', 'attributes': {'description': label},
                         'bounds': [100, 100, 700, 500]},
               'ocr': [{'text': text, 'source': 'ocr', 'confidence': .99,
                        'bounds': [110, 110+i*25, 450, 20]}
                       for i, text in enumerate((clutter + before).splitlines())]}
        if anchor:
            raw['insertion'] = {'source': 'ax_text_marker_range', 'before': clutter+before,
                                'after': after, 'replacing': replacing, 'isReplacement': bool(replacing)}
        return {'name': name, 'expected': expected, 'payload': {'context': json.dumps(raw), 'items': copy.deepcopy(items)}}
    result = [
        case('email_clutter', 'My email: ', 'my-email'),
        case('number_clutter', 'My number: ', 'my-number'),
        case('different_owner', "Bob Morgan's email is ", 'other-email'),
        case('mid_sentence', 'Reach me at my email ', 'my-email', after=', and we can arrange a call.\nMy number: '),
        case('replacement', 'My email: ', 'my-email', replacing='bob.morgan@example.net'),
        case('conflicting_background', 'My number: ', 'my-number', title='Email address for the invoice'),
        case('specific_old_address', 'The Cedar Road delivery address is ', 'old-address'),
        case('website_gap', 'The Cedar Studio website is ', 'url'),
        case('invoice_identifier', 'For the invoice, use reference ', 'invoice'),
        case('cover_letter', 'My cover letter: ', 'cover-letter'),
        case('meeting_date', 'Our meeting is scheduled for ', 'date'),
        case('empty_labelled_field', '', 'my-email', label='Your contact email address', anchor=False),
        case('no_suitable_value', 'My passport number: ', 'latest', label='Passport number'),
        case('window_image', 'Paste the screenshot of order 42 here', 'image', label='', anchor=False, kind='window'),
        # These cannot establish which of several visible cues owns the caret.
        # Report selections but do not invent a correct label for accuracy scoring.
        case('missing_caret_multiple_cues', 'My email:\nMy number:', None, anchor=False),
        case('missing_caret_generic', '', None, anchor=False),
        # Additional held-out cases, added after the first paired run.
        case('holdout_email_wrong_title', 'Please contact me at my email ', 'my-email', title='Phone numbers and office contacts'),
        case('holdout_number_wrong_title', 'You can reach me on my number ', 'my-number', title='Email support information'),
        case('holdout_url_wrong_title', 'Visit Cedar Studio online at ', 'url', title='Personal contact email'),
        case('holdout_invoice_wrong_title', 'The invoice reference is ', 'invoice', title='Delivery address changes'),
    ]
    return result


def percentile(values, q):
    values = sorted(values)
    pos = (len(values)-1)*q
    lo = int(pos)
    return values[lo] + (values[min(lo+1, len(values)-1)]-values[lo])*(pos-lo)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rounds', type=int, default=2)
    parser.add_argument('--fixtures-only', action='store_true')
    args = parser.parse_args()
    out = ROOT / 'results/hierarchy'
    out.mkdir(parents=True, exist_ok=True)
    fixtures = cases()
    (out / 'fixtures.json').write_text(json.dumps(fixtures, indent=2))
    (out / 'email-request.json').write_text(json.dumps(new.make_request(fixtures[0]['payload'])[0], indent=2))
    if args.fixtures_only:
        return
    key = subprocess.check_output(['/usr/bin/security', 'find-generic-password', '-s',
        'local.daniel.LayaClipboard.TypeSafe', '-a', 'api-key', '-w'], text=True).strip()
    client = new.JevSelector(key)
    rows = []
    try:
        for repeat in range(args.rounds):
            for index, case in enumerate(fixtures):
                policies = [('flat', old), ('hierarchy', new)]
                if (index+repeat) % 2:
                    policies.reverse()
                for policy, module in policies:
                    request, ids = module.make_request(case['payload'])
                    body = json.dumps(request).encode()
                    assert len(body) < 64000 and key.encode() not in body
                    cold = client.connection is None
                    if cold:
                        client.connection = client.connection_factory()
                    start = time.perf_counter()
                    client.connection.request('POST', '/v1/systemone', body,
                        {'Authorization': 'Bearer '+key, 'Content-Type': 'application/json'})
                    response = client.connection.getresponse()
                    raw = response.read(128001)
                    elapsed = (time.perf_counter()-start)*1000
                    if response.status != 200:
                        raise RuntimeError('Jev status '+str(response.status))
                    parsed = json.loads(raw)
                    selected = module.result_for(parsed, request, ids)
                    direct = module.result_for(parsed, request, ids, recency=False)
                    pick = lambda result: result['ranked'][0]['id'] if result['ranked'] else 'latest'
                    answer = parsed['answers']['pick']
                    probs = answer['probabilities']
                    row = {'case': case['name'], 'round': repeat+1, 'policy': policy,
                           'expected': case['expected'], 'selected': pick(selected),
                           'model_only': pick(direct), 'decision': selected['decision'],
                           'recency_changed': selected.get('recency_changed', False),
                           'top_probability': probs[answer['choice']],
                           'api_ms': round(elapsed, 1), 'cold_connection': cold,
                           'request_bytes': len(body)}
                    rows.append(row)
                    (out / 'runs.json').write_text(json.dumps(rows, indent=2))
                    print(f"{repeat+1} {policy} {case['name']}: {row['selected']} ({row['api_ms']} ms)", flush=True)
                    if response.will_close:
                        client.close()
    finally:
        client.close()
        key = ''
    summary = {}
    for policy in ('flat', 'hierarchy'):
        scored = [r for r in rows if r['policy'] == policy and r['expected'] is not None]
        warm = [r['api_ms'] for r in rows if r['policy'] == policy and not r['cold_connection']]
        summary[policy] = {'correct': sum(r['selected'] == r['expected'] for r in scored),
            'total': len(scored), 'wrong_paste_rate': sum(r['selected'] != r['expected'] for r in scored)/len(scored),
            'model_correct': sum(r['model_only'] == r['expected'] for r in scored),
            'recency_overrides': sum(r['recency_changed'] for r in rows if r['policy'] == policy),
            'warm_api_p50_ms': round(statistics.median(warm), 1),
            'warm_api_p95_ms': round(percentile(warm, .95), 1)}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
