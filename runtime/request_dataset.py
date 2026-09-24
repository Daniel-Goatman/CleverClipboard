"""Local, immutable request/result pairs for explicitly enabled dataset collection."""
import hashlib
import json
import os
from pathlib import Path
import stat
from datetime import datetime, timezone
import uuid


class DatasetError(Exception):
    pass


def contains_secret(value, secret):
    if isinstance(value, str):
        return secret in value
    if isinstance(value, dict):
        return any(contains_secret(k, secret) or contains_secret(v, secret) for k, v in value.items())
    if isinstance(value, (list, tuple)):
        return any(contains_secret(v, secret) for v in value)
    return False


class RequestDataset:
    def __init__(self, root=None):
        project = Path(__file__).resolve().parents[1]
        self.root = Path(root) if root is not None else project / 'results' / 'selection-dataset'
        paths = ['runtime/jev_selector.py', 'runtime/destination_context.py',
                 'runtime/context_evidence.py', 'Sources/CandidateText.swift', 'Sources/Context.swift']
        self.source_hashes = {p: hashlib.sha256((project / p).read_bytes()).hexdigest() for p in paths}

    def write(self, name, record):
        try:
            self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
            info = self.root.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise DatasetError('Dataset directory must be private and owned by this account.')
            encoded = json.dumps(record, ensure_ascii=False, allow_nan=False, indent=2).encode('utf-8')
            fd = os.open(self.root / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, 'wb') as stream:
                stream.write(encoded)
                stream.flush()
                os.fsync(stream.fileno())
        except (OSError, ValueError, TypeError) as error:
            raise DatasetError('Could not save the local request dataset.') from error

    def begin(self, request, ids):
        identifier = str(uuid.uuid4())
        self.write(identifier + '.request.json', {
            'schema_version': 1, 'record_id': identifier,
            'created_at': datetime.now(timezone.utc).isoformat(),
            'source_sha256': self.source_hashes,
            'request': request,
            'candidate_id_map': {f'C{i}': value for i, value in enumerate(ids)},
            'transport_status': 'prepared_send_not_confirmed',
            'label': {'status': 'unlabelled', 'expected_candidate_id': None},
            'paste_outcome': 'not_observed_by_worker',
        })
        return identifier

    def finish(self, identifier, response, result, error, elapsed_ms):
        self.write(identifier + '.result.json', {
            'schema_version': 1, 'record_id': identifier,
            'finished_at': datetime.now(timezone.utc).isoformat(),
            'response': response, 'selection_result': result,
            'error': error, 'elapsed_ms': elapsed_ms,
            'paste_outcome': 'not_observed_by_worker',
        })
