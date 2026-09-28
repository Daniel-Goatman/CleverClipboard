"""Development-only legacy pipe harness. Production uses the native Swift client."""
import json
import os
import sys
from jev_selector import JevSelector, SelectionError
from request_dataset import RequestDataset

def emit(value):
    print(json.dumps(value, separators=(',',':')), flush=True)

def main():
    selector = None
    try:
        raw = sys.stdin.buffer.readline(4097)
        if len(raw)>4096 or not raw.endswith(b'\n'):
            raise SelectionError('Invalid Jev credential setup.')
        setup = json.loads(raw)
        selector = JevSelector(setup.pop('api_key',None), recorder=RequestDataset() if os.environ.get('CLEVERCLIPBOARD_DATASET_ROOT') else None)
        raw = b''; setup = None
        selector.warm_connection()
        emit({'type':'ready'})
        while True:
            raw = sys.stdin.buffer.readline(512001)
            if not raw:
                return
            if len(raw)>512000 or not raw.endswith(b'\n'):
                emit({'type':'error','error':'Request too large.'});return
            try:
                payload = json.loads(raw)
                if not isinstance(payload,dict):
                    raise SelectionError('Invalid selection request.')
                # Refresh the documented metadata endpoint off the selection path.
                # The local ping never makes a paid inference.
                if payload.get('ping') is True:
                    selector.warm_connection_async()
                    result = {'type':'ready'}
                else:
                    result = selector.rank(payload)
                emit(result)
            except SelectionError as error:
                emit({'type':'error','error':str(error)})
            except Exception:
                emit({'type':'error','error':'Jev selection failed. Nothing was pasted.'})
            finally:
                raw = b''; payload = None; result = None
    except Exception:
        emit({'type':'error','error':'Jev setup failed. Configure the API key from the menu.'})
    finally:
        if selector:
            selector.close()

if __name__ == '__main__':
    main()
