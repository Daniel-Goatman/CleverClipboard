"""Private pipe protocol; key arrives in first message, never argv/env/disk."""
import json
import sys
from jev_selector import JevSelector, SelectionError

def emit(value):
    print(json.dumps(value, separators=(',',':')), flush=True)

def main():
    selector = None
    try:
        raw = sys.stdin.buffer.readline(4097)
        if len(raw)>4096 or not raw.endswith(b'\n'):
            raise SelectionError('Invalid Jev credential setup.')
        setup = json.loads(raw)
        selector = JevSelector(setup.pop('api_key',None))
        raw = b''; setup = None
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
                # Local IPC health check; never a paid keepalive inference.
                result = {'type':'ready'} if payload.get('ping') is True else selector.rank(payload)
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
