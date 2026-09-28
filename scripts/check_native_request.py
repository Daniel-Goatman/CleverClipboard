"""Offline native request parity against the development Python reference."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'runtime'), str(ROOT / 'Tests')]
from jev_selector import make_request
from context_cases import CASES
from benchmark_hierarchy import cases


def main():
    samples = [(case['name'], {'context': json.dumps(case['raw']), 'items': [
        {'id': str(i), 'text': text, 'app': 'Fixture'} for i, text in enumerate(case['items'])]}) for case in CASES]
    samples += [(case['name'], case['payload']) for case in cases()]
    samples += [('legacy', {'context': 'Input label: Email', 'items': [{'id':'one','text':'x@example.org','app':'Fixture'}]})]
    for label, text in [('unicode', '你好🙂'*5000), ('escaping', '"\\\n\t'*5000), ('long', 'a'*3000+'middle'+'z'*3000)]:
        samples.append((label, {'context':'Input label: Fixture', 'items':[
            {'id':str(i),'text':text,'app':'Fixture','hint':'h'*1000,'source_context':'Source evidence '*60}
            for i in range(52)]}))
    with tempfile.TemporaryDirectory(prefix='cleverclipboard-parity-') as directory:
        directory = Path(directory)
        fixtures = []
        for name, payload in samples:
            request, ids = make_request(payload)
            fixtures.append({'name':name,'payload':payload,'request':request,'ids':ids})
        path = directory/'fixtures.json'
        path.write_text(json.dumps(fixtures, ensure_ascii=False))
        binary = directory/'request-tests'
        sources = ['Diagnostics','Context','History','CandidateText','DestinationContext','JevRequest']
        subprocess.run(['xcrun','swiftc','-swift-version','5','-module-cache-path',str(ROOT/'.build/module-cache'),
                        *(str(ROOT/'Sources'/f'{name}.swift') for name in sources),
                        str(ROOT/'Tests/JevRequestTests.swift'),'-o',str(binary)], check=True)
        subprocess.run([str(binary), str(path)], check=True)


if __name__ == '__main__':
    main()
