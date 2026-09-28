import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'runtime'))
from jev_selector import JevSelector, SelectionError, MODEL, make_request
import request_dataset
from request_dataset import RequestDataset, DatasetError

KEY = 'synthetic-test-key-not-real'


class Connection:
    status = 200
    will_close = False
    calls = 0

    def __init__(self, response):
        self.response = response

    def request(self, method, path, body, headers):
        self.calls += 1
        self.sent = json.loads(body)

    def getresponse(self):
        return self

    def read(self, size):
        return self.response

    def close(self):
        pass


class DatasetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'dataset'
        self.recorder = RequestDataset(self.root)
        self.payload = {'context': 'Input label: Delivery address', 'items': [
            {'id': 'older', 'text': '8 Cedar Road', 'app': 'Notes', 'recency_rank': 1},
            {'id': 'newer', 'text': '42 Harbour Road', 'app': 'Mail', 'recency_rank': 0}]}
        self.response = {'model': MODEL, 'answers': {'pick': {'type': 'choice',
            'choice': 'C0', 'confidence': .9,
            'probabilities': {'C0': .52, 'C1': .48, 'NONE': 0}}},
            'usage': {'input_tokens': 300, 'output_tokens': 20}}

    def selector(self, body=None):
        self.connection = Connection(body if body is not None else json.dumps(self.response).encode())
        return JevSelector(KEY, lambda: self.connection, recorder=self.recorder)

    def records(self):
        return {p.suffixes[-2]: json.loads(p.read_text()) for p in self.root.glob('*.json')}

    def test_exact_request_response_mapping_and_jev_choice_are_saved_privately(self):
        result = self.selector().rank(self.payload)
        records = self.records()
        request, response = records['.request'], records['.result']
        self.assertEqual(request['request'], self.connection.sent)
        self.assertEqual(request['candidate_id_map'], {'C0': 'older', 'C1': 'newer'})
        self.assertEqual(response['response'], self.response)
        self.assertEqual(response['selection_result'], result)
        self.assertNotIn('recency_changed', result)
        self.assertEqual(result['model_choice'], 'older')
        self.assertEqual(result['ranked'][0]['id'], 'older')
        self.assertEqual(request['label']['status'], 'unlabelled')
        self.assertEqual(response['paste_outcome'], 'not_observed_by_worker')
        self.assertEqual(request['record_id'], response['record_id'])
        self.assertEqual(self.root.stat().st_mode & 0o777, 0o700)
        for path in self.root.glob('*'):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertNotIn(KEY, path.read_text())
            self.assertNotIn('Authorization', path.read_text())

    def test_http_errors_record_safe_outcome_without_server_body(self):
        selector = self.selector(b'private server text ' + KEY.encode())
        self.connection.status = 401
        with self.assertRaises(SelectionError):
            selector.rank(self.payload)
        record = self.records()['.result']
        self.assertIsNone(record['response'])
        self.assertIsNone(record['selection_result'])
        self.assertIn('rejected the API key', record['error'])
        self.assertNotIn(KEY, json.dumps(self.records()))

    def test_secret_request_never_recorded_or_sent(self):
        self.payload['items'][0]['text'] = KEY
        selector = self.selector()
        with self.assertRaises(SelectionError):
            selector.rank(self.payload)
        self.assertFalse(self.root.exists())
        self.assertEqual(self.connection.calls, 0)

    def test_escaped_secret_response_never_recorded(self):
        escaped = ''.join('\\u%04x' % ord(c) for c in KEY)
        selector = self.selector(('{"extra":"' + escaped + '"}').encode())
        with self.assertRaises(SelectionError):
            selector.rank(self.payload)
        self.assertIsNone(self.records()['.result']['response'])
        self.assertNotIn(KEY, json.dumps(self.records()))

    def test_unavailable_recording_prevents_unrecorded_request(self):
        self.root.write_text('not a directory')
        selector = self.selector()
        with self.assertRaisesRegex(SelectionError, 'Nothing was sent'):
            selector.rank(self.payload)
        self.assertEqual(self.connection.calls, 0)

    def test_public_directory_and_symlink_are_rejected(self):
        self.root.mkdir(mode=0o755)
        self.root.chmod(0o755)
        with self.assertRaises(SelectionError):
            self.selector().rank(self.payload)
        self.root.rmdir()
        self.root.symlink_to(self.temp.name)
        with self.assertRaises(SelectionError):
            self.selector().rank(self.payload)
        self.assertEqual(self.connection.calls, 0)

    def test_missing_result_means_incomplete_not_success(self):
        request, ids = make_request(self.payload)
        self.recorder.begin(request, ids)
        self.assertEqual(set(self.records()), {'.request'})
        self.assertEqual(self.records()['.request']['transport_status'], 'prepared_send_not_confirmed')

    def test_result_write_failure_prevents_reporting_success(self):
        def fail(*args):
            from request_dataset import DatasetError
            raise DatasetError('write failed')
        self.recorder.finish = fail
        with self.assertRaisesRegex(SelectionError, 'Nothing was pasted'):
            self.selector().rank(self.payload)

    def test_worker_healthcheck_does_not_create_dataset_records(self):
        code = '''
import io, sys
import jev_worker
from jev_selector import JevSelector
from request_dataset import RequestDataset
root = sys.argv[1]
jev_worker.RequestDataset = lambda: RequestDataset(root)
JevSelector.warm_connection = lambda self: False
JevSelector.warm_connection_async = lambda self: None
sys.stdin = io.TextIOWrapper(io.BytesIO(b'{"api_key":"synthetic-test-key-not-real"}\\n{"ping":true}\\n'))
jev_worker.main()
'''
        result = subprocess.run([sys.executable, '-B', '-c', code, str(self.root)],
                                cwd=ROOT / 'runtime', capture_output=True, text=True, check=True)
        self.assertEqual([json.loads(line)['type'] for line in result.stdout.splitlines()], ['ready', 'ready'])
        self.assertFalse(self.root.exists())


class PackagedDatasetTests(unittest.TestCase):
    def test_packaged_runtime_uses_manifest_and_private_external_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            resources = Path(tmp) / 'Resources'
            runtime = resources / 'runtime'
            runtime.mkdir(parents=True)
            source_hashes = RequestDataset(Path(tmp) / 'unused').source_hashes
            (resources / 'source-hashes.json').write_text(json.dumps(source_hashes))
            destination = Path(tmp) / 'user-support' / 'selection-dataset'
            with patch.object(request_dataset, '__file__', str(runtime / 'request_dataset.py')), \
                 patch.dict(os.environ, {'CLEVERCLIPBOARD_DATASET_ROOT': str(destination)}):
                recorder = RequestDataset()
                self.assertEqual(recorder.source_hashes, source_hashes)
                recorder.write('synthetic.json', {'fixture': True})
            self.assertEqual(destination.stat().st_mode & 0o777, 0o700)
            self.assertEqual((destination / 'synthetic.json').stat().st_mode & 0o777, 0o600)
            self.assertFalse((resources / 'results').exists())

    def test_invalid_packaged_manifest_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            resources = Path(tmp)
            runtime = resources / 'runtime'
            runtime.mkdir()
            (resources / 'source-hashes.json').write_text('{"unexpected":"hash"}')
            with patch.object(request_dataset, '__file__', str(runtime / 'request_dataset.py')):
                with self.assertRaises(DatasetError):
                    RequestDataset(resources / 'unused')


if __name__ == '__main__':
    unittest.main()
