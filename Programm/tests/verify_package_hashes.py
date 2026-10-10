"""Verify repository bytes and the runtime integrity contract, without starting software."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
package = json.loads((root / 'PACKAGE_HASHES.json').read_text(encoding='utf-8-sig'))
runtime_root = root / 'Programm' / 'runtime'
runtime = json.loads((runtime_root / 'manifest.json').read_text(encoding='utf-8-sig'))
for base, entries in ((root, package['files']), (runtime_root, runtime['files'])):
    for name, expected in entries.items():
        path = base.joinpath(*name.replace('\\', '/').split('/'))
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit(f'Hash mismatch: {path.relative_to(root)}')
print('Package and runtime file hashes verified.')
