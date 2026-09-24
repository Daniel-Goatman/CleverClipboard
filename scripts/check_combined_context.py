"""Synthetic Swift to selector to local dataset bridge; no network or clipboard."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'runtime'))
from jev_selector import JevSelector, MODEL, make_request, request_body
from request_dataset import RequestDataset


class Connection:
    def __init__(self):
        self.calls = 0

    def request(self, method, path, body, headers):
        self.calls += 1
        assert method == 'POST' and path == '/v1/systemone'
        self.body = body
        request = json.loads(body)
        ids = list(request['questions']['pick']['criteria'])
        chosen = next(c['id'] for c in request['state']['clipboard'] if c['kind'] == 'text')
        self.response = json.dumps({'model': MODEL, 'answers': {'pick': {
            'type': 'choice', 'choice': chosen, 'confidence': 1,
            'probabilities': {key: int(key == chosen) for key in ids}}}}).encode()

    def getresponse(self):
        return self

    def read(self, size):
        return self.response

    status = 200
    will_close = False

    def close(self):
        pass


def main():
    with tempfile.TemporaryDirectory() as temporary:
        binary = Path(temporary) / 'bridge'
        sources = ['Sources/Diagnostics.swift', 'Sources/Context.swift', 'Sources/History.swift',
                   'Sources/CandidateText.swift', 'Sources/ModelWorker.swift', 'Sources/JevCredential.swift',
                   'Sources/ImageOCR.swift', 'Tests/CombinedBridgeTests.swift']
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-module-cache-path',
                        str(ROOT / '.build/module-cache'), *(str(ROOT / s) for s in sources),
                        '-o', str(binary)], check=True)
        wrapped = json.loads(subprocess.check_output([binary]))
        payload = wrapped['payload']
        assert wrapped['original_text'] == '1200'
        request, ids = make_request(payload)
        clips = request['state']['clipboard']
        text = next(c for c in clips if c['kind'] == 'text')
        image = next(c for c in clips if c['kind'] == 'image')
        assert 'Revenue' in text['source_context'] and 'Deposit' in text['source_context']
        assert text['text'] == '1200' and text['source_app'] == 'Safari'
        assert 'Bread' in image['text'] and '$12.00' in image['text']
        assert '[x ' in image['text'] and 'confidence ' in image['text']
        assert len(request_body(request)) <= 24000
        connection = Connection()
        dataset = Path(temporary) / 'dataset'
        result = JevSelector('synthetic-test-key-not-real', lambda: connection,
                             recorder=RequestDataset(dataset)).rank(payload)
        assert connection.calls == 1
        assert result['ranked'][0]['id'] == wrapped['text_id']
        assert wrapped['original_text'] == '1200'
        saved_request = json.loads(next(dataset.glob('*.request.json')).read_text())
        saved_result = json.loads(next(dataset.glob('*.result.json')).read_text())
        assert saved_request['request'] == json.loads(connection.body)
        assert saved_request['candidate_id_map'][next(c['id'] for c in clips if c['kind'] == 'text')] == wrapped['text_id']
        assert saved_result['selection_result'] == result
        assert saved_request['record_id'] == saved_result['record_id']
        print('PASS: history/reload/dedup/OCR -> Swift payload -> bounded request -> fake choice -> private paired dataset')


if __name__ == '__main__':
    main()
