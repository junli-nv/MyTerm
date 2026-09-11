#!/usr/bin/env python3
"""Require identical bundle files, symlinks and permissions after packaging/install."""
import hashlib
import pathlib
import stat
import sys

def manifest(root):
    root = pathlib.Path(root)
    if not (root / 'Contents/MacOS/MyTerm').is_file():
        raise SystemExit(f'Not a MyTerm application: {root}')
    result = {}
    for path in sorted(root.rglob('*')):
        info = path.lstat()
        mode = stat.S_IMODE(info.st_mode)
        if path.is_symlink():
            value = ('link', mode, str(path.readlink()))
        elif path.is_file():
            value = ('file', mode, hashlib.file_digest(path.open('rb'), 'sha256').hexdigest())
        elif path.is_dir():
            value = ('directory', mode)
        else:
            raise SystemExit(f'Unexpected bundle entry: {path}')
        result[str(path.relative_to(root))] = value
    return result

source, target = map(manifest, sys.argv[1:3])
different = sorted(key for key in source.keys() | target.keys() if source.get(key) != target.get(key))
if different:
    raise SystemExit('Bundle mismatch: ' + ', '.join(different))
print(f'PASS: identical application bundles ({len(source)} entries)')
