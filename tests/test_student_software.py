"""Run real Ansible tasks against fake CLIs; no AWS, sudo or Store access."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
FAKE_CLI = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['SOFTWARE_TEST_ROOT'])
kind = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls').open('a') as f:
    f.write(json.dumps([kind] + args) + '\n')
state_file = root / (kind + '.json')
state = json.loads(state_file.read_text())
if kind == 'snap' and args == ['version']:
    print('snap 2.60.4\nsnapd 2.60.4\nseries 16\nubuntu 22.04\nkernel 6.2.0')
elif kind == 'snap' and args[0] == 'list':
    print('Name Version Rev Tracking Publisher Notes')
    for name in state:
        print(name, '1.0 1 latest/stable test -')
elif kind == 'code' and args == ['--list-extensions']:
    print('\n'.join(state))
elif kind == 'snap' and args[0] == 'info':
    # Reproduce the old module's IndexError once, before installation.
    marker = root / 'snap-info-failed'
    if not marker.exists():
        marker.touch()
        print('error: no snap found', file=sys.stderr)
        sys.exit(1)
    print('name:', args[-1])
elif (kind == 'snap' and args[0] == 'install') or (kind == 'code' and args[0] == '--install-extension'):
    marker = root / (kind + '-install-failed')
    if not marker.exists() or (root / 'permanent-failure').exists():
        marker.touch()
        print('Server returned 503', file=sys.stderr)
        sys.exit(1)
    name = args[-1]
    state.append(name)
    state_file.write_text(json.dumps(state))
    print('Successfully installed', name)
else:
    raise RuntimeError('Unexpected command: ' + repr([kind] + args))
'''


@unittest.skipUnless(shutil.which('ansible-playbook'), 'ansible-playbook required in PATH')
class StudentSoftwareTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ('snap', 'code'):
            cli = self.root / name
            cli.write_text(FAKE_CLI)
            cli.chmod(0o755)
            (self.root / (name + '.json')).write_text(json.dumps(['existing']))
        (self.root / 'ansible.cfg').write_text('[defaults]\nhost_key_checking = True\n')
        self.env = dict(os.environ, ANSIBLE_CONFIG=str(self.root / 'ansible.cfg'),
                        PATH=str(self.root) + os.pathsep + os.environ['PATH'],
                        SOFTWARE_TEST_ROOT=str(self.root))

    def run_tasks(self, check=False):
        play = [{'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
                 'vars': {'ansible_python_interpreter': shutil.which('python3'),
                          'ansible_hostname': os.environ.get('USER', 'test'),
                          'student_common_snap_packages': [{'package': 'existing', 'classic': False}],
                          'student_enabled_snap_packages': [{'package': 'missing', 'classic': False}],
                          'student_enabled_vscode_extensions': ['EXISTING', 'new.extension'],
                          'student_software_retries': 2, 'student_software_retry_delay': 0},
                 'tasks': [{'ansible.builtin.import_tasks': str(ROOT / 'roles/student/tasks' / (name + '.yml'))}
                           for name in ('snaps', 'vscode')]}]
        path = self.root / 'play.yml'
        path.write_text(yaml.safe_dump(play))
        result = subprocess.run(['ansible-playbook', '-i', 'localhost,', str(path)] +
                                (['--check'] if check else []), env=self.env, cwd=self.root,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        calls = [json.loads(line) for line in (self.root / 'calls').read_text().splitlines()]
        return result, calls

    def test_transient_errors_then_idempotent_rerun(self):
        result, calls = self.run_tasks()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('RETRYING', result.stdout)
        self.assertFalse(any(c[1:2] == ['info'] and c[-1] == 'existing' for c in calls))
        self.assertEqual(json.loads((self.root / 'snap.json').read_text()), ['existing', 'missing'])
        self.assertEqual(json.loads((self.root / 'code.json').read_text()), ['existing', 'new.extension'])
        (self.root / 'calls').write_text('')
        result, calls = self.run_tasks()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('changed=0', result.stdout)
        self.assertEqual(calls, [['snap', 'list'], ['code', '--list-extensions']])

    def test_persistent_extension_failure_is_not_hidden(self):
        (self.root / 'snap.json').write_text(json.dumps(['existing', 'missing']))
        (self.root / 'permanent-failure').touch()
        result, calls = self.run_tasks()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('Server returned 503', result.stdout)
        self.assertEqual(sum(c[1:2] == ['--install-extension'] for c in calls), 3)

    def test_check_mode_does_not_install(self):
        result, calls = self.run_tasks(check=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(any(c[1:2] in (['install'], ['--install-extension']) for c in calls))


if __name__ == '__main__':
    unittest.main()
