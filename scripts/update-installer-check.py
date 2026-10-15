#!/usr/bin/env python3
"""Exercise the production installer against disposable, signed app bundles only."""
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / 'packaging/install-update.sh'

def run(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, **kwargs)

with tempfile.TemporaryDirectory(prefix='myterm-updater-fixtures-') as temporary:
    root = pathlib.Path(temporary)
    source = root / 'fixture.c'
    source.write_text('int main(void) { return 0; }\n')
    executable = root / 'fixture'
    run('/usr/bin/clang', str(source), '-o', str(executable))
    def app(path, version, too_new=False):
        (path / 'Contents/MacOS').mkdir(parents=True)
        shutil.copy2(executable, path / 'Contents/MacOS/MyTerm')
        info = dict(CFBundleIdentifier='org.myterm.updater.fixture', CFBundleName='Updater fixture',
                    CFBundleExecutable='MyTerm', CFBundlePackageType='APPL',
                    CFBundleShortVersionString=version, CFBundleVersion='1')
        if too_new: info['LSMinimumSystemVersion'] = '99.0'
        (path / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        run('/usr/bin/codesign', '--force', '--sign', '-', str(path))
    def version(path):
        return plistlib.loads((path / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
    for name, remote, expected, tamper in [('success', '9.1', '9.1', False),
                                          ('version-mismatch', '9.1', '9.2', False),
                                          ('signature-failure', '9.1', '9.1', True),
                                          ('launch-rollback', '9.1', '9.1', False)]:
        case = root / name
        target = case / 'installed/MyTerm.app'
        stage = case / 'myterm-update-fixture'
        update = stage / 'unpacked/MyTerm.app'
        app(target, '9.0'); app(update, remote, too_new=name == 'launch-rollback')
        if tamper:
            with (update / 'Contents/MacOS/MyTerm').open('ab') as out: out.write(b'bad-signature')
        parent = subprocess.Popen(['/bin/sleep', '30'] if name == 'success' else ['/usr/bin/true'])
        if name != 'success': parent.wait()
        installer = subprocess.Popen(['/bin/bash', str(HELPER), str(parent.pid), str(update), str(target), expected, str(stage)],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            if name == 'success':
                deadline = time.monotonic() + 5
                while not (stage / 'ready').exists() and installer.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.02)
                assert (stage / 'ready').exists(), 'Installer did not signal readiness'
                assert version(target) == '9.0', 'Installer replaced a running application'
                parent.terminate(); parent.wait()
            stdout, stderr = installer.communicate(timeout=20)
            result = subprocess.CompletedProcess(installer.args, installer.returncode, stdout, stderr)
        finally:
            if parent.poll() is None: parent.terminate(); parent.wait()
            if installer.poll() is None: installer.terminate(); installer.wait()
        if name == 'success':
            assert result.returncode == 0 and version(target) == remote, result.stdout + result.stderr
        else:
            assert result.returncode != 0 and version(target) == '9.0', result.stdout + result.stderr
        assert not stage.exists(), 'Staging files were retained'
        assert not list(target.parent.glob('.myterm-update.*')), 'Pending replacement was retained'
        print(f'PASS: automatic installer {name}; original preservation, cleanup and launch path')
